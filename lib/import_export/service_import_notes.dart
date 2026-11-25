/// Import des notes depuis Excel : lit la base pour le contexte de
/// vérification, écrit en une transaction, puis **relit** chaque note écrite
/// pour confirmer qu'elle est bien dans la base.
library;

import 'dart:io';
import 'dart:typed_data';

import '../app/services.dart';
import '../data/erreurs.dart';
import '../data/modeles_donnees.dart';
import '../domain/calendrier.dart';
import '../domain/permissions.dart';
import '../tableur/classeur.dart';
import '../tableur/xlsx.dart';
import 'import_notes.dart';
import 'lecture_tableur.dart';
import 'service_export.dart';
import 'service_import_eleves.dart';

/// Ce que l'import des notes a réellement fait, après relecture de la base.
class BilanImportNotes {
  const BilanImportNotes({
    required this.nbEvaluationsCreees,
    required this.nbNotes,
    required this.nbRemplacees,
    required this.nbVerifiees,
    required this.nbIdentiques,
    required this.nbConservees,
    required this.nbLignesEnErreur,
    required this.nbLignesSansNote,
  });

  /// Évaluations créées par la transaction.
  final int nbEvaluationsCreees;

  /// Notes enregistrées (nouvelles et remplacées).
  final int nbNotes;

  /// Parmi elles, notes qui en ont remplacé une autre.
  final int nbRemplacees;

  /// Notes relues dans la base, identiques à celles annoncées.
  final int nbVerifiees;

  /// Notes du fichier déjà identiques à celles de GESCO (rien à écrire).
  final int nbIdentiques;

  /// Notes du fichier différentes de celles de GESCO, laissées telles quelles.
  final int nbConservees;

  /// Lignes en erreur ignorées à la demande de l'utilisateur.
  final int nbLignesEnErreur;

  /// Élèves du fichier sans aucune note remise.
  final int nbLignesSansNote;
}

class ServiceImportNotes {
  ServiceImportNotes(this.services, {DateTime Function()? maintenant})
      : _maintenant = maintenant ?? DateTime.now;

  final Services services;
  final DateTime Function() _maintenant;

  /// Ouvre un classeur Excel. Lève une [ErreurGesco] lisible s'il est
  /// illisible (autre format, fichier abîmé).
  ClasseurLu ouvrir(Uint8List octets) {
    services.controle.exiger(Permission.importExport, 'importer des notes');
    return lireClasseur(octets);
  }

  /// Les feuilles du classeur avec leur ligne d'en-tête repérée.
  List<FeuilleImport> feuilles(ClasseurLu classeur) => [
        for (var i = 0; i < classeur.feuilles.length; i++)
          FeuilleImport(
            indice: i,
            nom: classeur.feuilles[i].nom,
            indexEntete: trouverLigneEntete(classeur.feuilles[i], titresConnusNotes),
          ),
      ];

  /// Feuille proposée d'abord : la première dont l'en-tête est reconnu
  /// (au moins deux titres connus), à défaut la première feuille.
  int feuilleProposee(ClasseurLu classeur) {
    for (var i = 0; i < classeur.feuilles.length; i++) {
      final f = classeur.feuilles[i];
      final e = trouverLigneEntete(f, titresConnusNotes);
      if (e == null) continue;
      var connus = 0;
      for (final c in f.lignes[e]) {
        if (titresConnusNotes.contains(cleColonne(c.texte))) connus++;
      }
      if (connus >= 2) return i;
    }
    return 0;
  }

  /// Ce que la vérification doit savoir de la base : élèves de l'année,
  /// évaluations de la matière, notes déjà enregistrées, mois verrouillés.
  Future<ContexteImportNotes> contexte({
    required int anneeId,
    required Classe classe,
    required MatiereClasse matiere,
    required PeriodeScolaire periode,
    bool remplacerExistantes = false,
  }) async {
    final annee = await services.annees.obtenir(anneeId);
    if (annee == null) throw const ErreurGesco('Année scolaire introuvable.');
    final eleves = await services.eleves.lister(anneeId);
    final resumes = await services.evaluations.lister(
      classeId: classe.id,
      matiereId: matiere.id,
    );
    final evaluations = [for (final r in resumes) r.evaluation];
    final notes = {
      for (final e in evaluations) e.id: await services.evaluations.lireNotes(e.id),
    };
    return ContexteImportNotes(
      classeId: classe.id,
      classeNom: classe.nom,
      matiereId: matiere.id,
      matiereNom: matiere.nom,
      matiereBareme: matiere.bareme,
      anneeLibelle: annee.libelle,
      trimestreLibelle: periode.libelle,
      moisTrimestre: periode.mois,
      eleves: eleves,
      evaluations: evaluations,
      notesExistantes: notes,
      moisVerrouilles: await services.notes.moisVerrouilles(classe.id),
      remplacerExistantes: remplacerExistantes,
    );
  }

  /// Reconnaît une liste produite par GESCO : null si le classeur n'a pas de
  /// feuille technique « GESCO » (fichier Excel quelconque).
  PropositionGesco? reconnaitreListeGesco(ClasseurLu classeur, ContexteImportNotes ctx) {
    final liste = lireFeuilleTechnique(classeur);
    if (liste == null) return null;
    return proposerDepuisListeGesco(classeur: classeur, liste: liste, ctx: ctx);
  }

  /// Enregistre les notes du [rapport] en une seule transaction, puis relit
  /// chaque note dans la base pour vérifier qu'elle y est telle qu'annoncée.
  Future<BilanImportNotes> importer(
    RapportImportNotes rapport, {
    required Classe classe,
    required MatiereClasse matiere,
    required bool ignorerErreurs,
  }) async {
    services.controle.exiger(Permission.importExport, 'importer des notes');
    if (rapport.bloque) {
      throw const ErreurGesco('Le fichier a un problème qui empêche l\'import : corrigez-le d\'abord.');
    }
    if (rapport.nbNotesAEcrire == 0) {
      throw const ErreurGesco('Aucune note à importer.');
    }
    if (rapport.nbLignesErreur > 0 && !ignorerErreurs) {
      throw const ErreurGesco(
        'Des lignes sont en erreur : corrigez le fichier, ou choisissez d\'ignorer ces lignes.',
      );
    }
    final resultat = await services.evaluations.importerNotes(
      classeId: classe.id,
      matiereId: matiere.id,
      colonnes: rapport.plan,
    );

    var verifiees = 0;
    for (var i = 0; i < rapport.plan.length; i++) {
      final lues = await services.evaluations.lireNotes(resultat.evaluationIds[i]);
      for (final e in rapport.plan[i].notes.entries) {
        if (lues[e.key] == e.value) verifiees++;
      }
    }
    if (verifiees != resultat.nbNotes) {
      throw ErreurGesco(
        'Vérification après import : seulement $verifiees note(s) retrouvée(s) sur '
        '${resultat.nbNotes}. Contrôlez les notes avant de continuer.',
      );
    }
    return BilanImportNotes(
      nbEvaluationsCreees: resultat.nbEvaluationsCreees,
      nbNotes: resultat.nbNotes,
      nbRemplacees: resultat.nbNotesRemplacees,
      nbVerifiees: verifiees,
      nbIdentiques: rapport.nbIdentiques,
      nbConservees: rapport.nbConservees,
      nbLignesEnErreur: rapport.nbLignesErreur,
      nbLignesSansNote: rapport.nbLignesSansNote,
    );
  }

  /// Écrit le rapport de vérification dans un fichier Excel (jamais écrasé),
  /// relu après l'écriture.
  Future<FichierEnregistre> enregistrerRapport(
    RapportImportNotes rapport, {
    required ContexteImportNotes ctx,
    required String nomFichier,
    Directory? dossier,
  }) async {
    services.controle.exiger(Permission.importExport, 'exporter des données');
    final etablissement = await services.etablissements.lire();
    final feuilles = feuillesRapportImportNotes(
      etablissement: etablissement.nom,
      nomFichier: nomFichier,
      date: _maintenant(),
      ctx: ctx,
      rapport: rapport,
    );
    return ServiceExport(services, maintenant: _maintenant).enregistrer(
      FichierExcel(
        nomBase: 'Rapport import notes ${ctx.classeNom} ${ctx.matiereNom}',
        octets: ecrireClasseur(feuilles),
        feuilles: [for (final f in feuilles) nomOngletValide(f.nom)],
      ),
      dossier: dossier,
    );
  }
}
