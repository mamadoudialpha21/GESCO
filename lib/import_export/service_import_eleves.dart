/// Import des élèves depuis Excel : lit la base pour le contexte de
/// vérification, écrit en une transaction, puis **relit** la base pour
/// confirmer que chaque élève annoncé y est bien.
library;

import 'dart:io';
import 'dart:typed_data';

import '../app/services.dart';
import '../data/depots/eleve_depot.dart';
import '../data/erreurs.dart';
import '../domain/permissions.dart';
import '../tableur/classeur.dart';
import '../tableur/xlsx.dart';
import 'import_eleves.dart';
import 'lecture_tableur.dart';
import 'modele_export.dart';
import 'service_export.dart';

/// Un classeur choisi par l'utilisateur : son nom et son contenu.
class FichierChoisi {
  const FichierChoisi({required this.nom, required this.octets});

  final String nom;
  final Uint8List octets;
}

/// Ce que l'import a réellement fait, après relecture de la base.
class ResultatImportEleves {
  const ResultatImportEleves({
    required this.nbImportes,
    required this.nbVerifies,
    required this.nbDejaPresents,
    required this.nbLignesEnErreur,
  });

  /// Élèves créés par la transaction.
  final int nbImportes;

  /// Élèves retrouvés dans la base, dans la bonne classe, après l'import.
  final int nbVerifies;

  /// Lignes ignorées car l'élève existait déjà (rien n'a été écrasé).
  final int nbDejaPresents;

  /// Lignes en erreur ignorées à la demande de l'utilisateur.
  final int nbLignesEnErreur;
}

/// Feuille d'un classeur ouverte pour l'import, avec son en-tête repéré.
class FeuilleImport {
  const FeuilleImport({required this.indice, required this.nom, required this.indexEntete});

  /// Rang de la feuille dans le classeur (à partir de 0).
  final int indice;
  final String nom;

  /// Indice (à partir de 0) de la ligne d'en-tête repérée, ou null si vide.
  final int? indexEntete;
}

class ServiceImportEleves {
  ServiceImportEleves(this.services, {DateTime Function()? maintenant})
      : _maintenant = maintenant ?? DateTime.now;

  final Services services;
  final DateTime Function() _maintenant;

  /// Ouvre un classeur Excel. Lève une [ErreurGesco] lisible s'il est
  /// illisible (autre format, fichier abîmé).
  ClasseurLu ouvrir(Uint8List octets) {
    services.controle.exiger(Permission.importExport, 'importer des élèves');
    return lireClasseur(octets);
  }

  /// Les feuilles du classeur avec leur ligne d'en-tête repérée.
  List<FeuilleImport> feuilles(ClasseurLu classeur) => [
        for (var i = 0; i < classeur.feuilles.length; i++)
          FeuilleImport(
            indice: i,
            nom: classeur.feuilles[i].nom,
            indexEntete: trouverLigneEntete(classeur.feuilles[i], titresConnusEleves),
          ),
      ];

  /// Feuille proposée d'abord : la première dont l'en-tête est reconnu
  /// (au moins deux titres connus), à défaut la première feuille.
  int feuilleProposee(ClasseurLu classeur) {
    for (var i = 0; i < classeur.feuilles.length; i++) {
      final f = classeur.feuilles[i];
      final e = trouverLigneEntete(f, titresConnusEleves);
      if (e == null) continue;
      var connus = 0;
      for (final c in f.lignes[e]) {
        if (titresConnusEleves.contains(cleColonne(c.texte))) connus++;
      }
      if (connus >= 2) return i;
    }
    return 0;
  }

  /// Ce que la vérification doit savoir de la base : classes de l'année,
  /// élèves déjà enregistrés.
  Future<ContexteImportEleves> contexte(
    int anneeId, {
    int? classeParDefautId,
    bool autoriserDepassement = false,
  }) async {
    final annee = await services.annees.obtenir(anneeId);
    if (annee == null) throw const ErreurGesco('Année scolaire introuvable.');
    final classes = await services.classes.lister(anneeId);
    return ContexteImportEleves(
      anneeLibelle: annee.libelle,
      maintenant: _maintenant(),
      classes: [
        for (final c in classes)
          ClasseImport(
            id: c.classe.id,
            nom: c.classe.nom,
            capacite: c.classe.capacite,
            nbActifs: c.nbActifs,
          ),
      ],
      existants: await services.eleves.identites(),
      classeParDefautId: classeParDefautId,
      autoriserDepassement: autoriserDepassement,
    );
  }

  /// Enregistre les élèves du [rapport] en une seule transaction, puis
  /// vérifie dans la base que chacun y figure dans la bonne classe.
  Future<ResultatImportEleves> importer(
    RapportImportEleves rapport, {
    required int anneeId,
    required String nomFichier,
    required bool ignorerErreurs,
    bool autoriserDepassement = false,
  }) async {
    services.controle.exiger(Permission.importExport, 'importer des élèves');
    if (rapport.bloque) {
      throw const ErreurGesco('Le fichier a un problème qui empêche l\'import : corrigez-le d\'abord.');
    }
    if (rapport.nbAImporter == 0) {
      throw const ErreurGesco('Aucun élève à importer.');
    }
    if (rapport.nbErreurs > 0 && !ignorerErreurs) {
      throw const ErreurGesco(
        'Des lignes sont en erreur : corrigez le fichier, ou choisissez d\'ignorer ces lignes.',
      );
    }
    final lot = [
      for (final l in rapport.aImporter)
        EleveAImporter(eleve: l.eleve!, classeId: l.classeId!, ligne: l.numero),
    ];
    final n = await services.eleves.importerLot(
      lot,
      anneeId: anneeId,
      depasserCapacite: autoriserDepassement,
      source: nomFichier,
    );

    final inscrits = await services.eleves.lister(anneeId, inclureArchives: true);
    final parMatricule = {for (final e in inscrits) e.matricule.trim().toLowerCase(): e};
    var verifies = 0;
    for (final e in lot) {
      final trouve = parMatricule[e.eleve.matricule.trim().toLowerCase()];
      if (trouve != null && trouve.classeId == e.classeId) verifies++;
    }
    if (verifies != n) {
      throw ErreurGesco(
        'Vérification après import : seulement $verifies élève(s) retrouvé(s) sur $n. '
        'Contrôlez la liste des élèves avant de continuer.',
      );
    }
    return ResultatImportEleves(
      nbImportes: n,
      nbVerifies: verifies,
      nbDejaPresents: rapport.nbDejaPresents,
      nbLignesEnErreur: rapport.nbErreurs,
    );
  }

  Future<ContexteExport> _contexteExport(int anneeId) async {
    final annee = await services.annees.obtenir(anneeId);
    if (annee == null) throw const ErreurGesco('Année scolaire introuvable.');
    final etablissement = await services.etablissements.lire();
    return ContexteExport(etablissement: etablissement.nom, annee: annee.libelle, date: _maintenant());
  }

  /// Écrit le rapport de vérification dans un fichier Excel (jamais écrasé),
  /// relu après l'écriture.
  Future<FichierEnregistre> enregistrerRapport(
    RapportImportEleves rapport, {
    required int anneeId,
    required String nomFichier,
    Directory? dossier,
  }) async {
    services.controle.exiger(Permission.importExport, 'exporter des données');
    final ctx = await _contexteExport(anneeId);
    final feuille = feuilleRapportImportEleves(
      etablissement: ctx.etablissement,
      anneeLibelle: ctx.annee,
      nomFichier: nomFichier,
      date: ctx.date,
      rapport: rapport,
    );
    return ServiceExport(services, maintenant: _maintenant).enregistrer(
      FichierExcel(
        nomBase: 'Rapport import eleves ${ctx.annee}',
        octets: ecrireClasseur([feuille]),
        feuilles: [nomOngletValide(feuille.nom)],
      ),
      dossier: dossier,
    );
  }

  /// Écrit le modèle vierge à remplir puis importer.
  Future<FichierEnregistre> enregistrerModele({
    required int anneeId,
    Directory? dossier,
  }) async {
    services.controle.exiger(Permission.importExport, 'exporter des données');
    final ctx = await _contexteExport(anneeId);
    final feuille = feuilleModeleImportEleves(
      etablissement: ctx.etablissement,
      anneeLibelle: ctx.annee,
    );
    return ServiceExport(services, maintenant: _maintenant).enregistrer(
      FichierExcel(
        nomBase: 'Modele import eleves ${ctx.annee}',
        octets: ecrireClasseur([feuille]),
        feuilles: [nomOngletValide(feuille.nom)],
      ),
      dossier: dossier,
    );
  }
}
