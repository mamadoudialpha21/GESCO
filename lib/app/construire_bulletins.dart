/// Construction des bulletins d'une classe à partir des résultats calculés.
library;

import '../data/depots/appreciation_depot.dart';
import '../data/modeles_donnees.dart';
import '../documents/modele_bulletin.dart';
import '../domain/arrondi.dart';
import '../domain/calendrier.dart';
import '../domain/moteur_resultats.dart';
import 'calcul_classe.dart';

/// Bulletins des élèves d'une classe pour une période.
///
/// - [type] : mensuel, périodique (trimestre, semestre, séquence) ou annuel ;
///   le bulletin annuel ajoute le récapitulatif de chaque période.
/// - [inscriptions] : si fourni, seuls ces élèves sont édités (dans l'ordre de
///   la classe) ; sinon tous les élèves qui suivent la classe. Les élèves
///   partis ne reçoivent un bulletin que s'ils sont demandés explicitement.
/// - [fiches] : fiches complètes (photo, lieu de naissance) par identifiant
///   d'élève ; facultatives.
List<Bulletin> construireBulletins({
  required CalculClasse calcul,
  required Portee portee,
  required String periodeLibelle,
  required TypeBulletin type,
  required Etablissement etablissement,
  required String anneeLibelle,
  Map<int, AppreciationEleve> appreciations = const {},
  Map<int, Map<int, String>> appreciationsMatieres = const {},
  Map<int, Eleve> fiches = const {},
  Set<int>? inscriptions,
  DateTime? dateEdition,
}) {
  final resultats = {for (final r in calcul.resultats(portee)) r.inscriptionId: r};
  final stats = calcul.stats(portee);
  final classe = calcul.classe.classe;

  // Par matière : note et rang de chaque élève, moyenne / min / max de la classe.
  final parMatiere = <int, Map<int, ResultatMatiere>>{};
  final statsMatiere = <int, (int?, int?, int?)>{};
  for (final m in calcul.matieres) {
    final liste = calcul.moteur.classementMatiere(m.id, portee);
    parMatiere[m.id] = {for (final r in liste) r.inscriptionId: r};
    final actifs = {for (final e in calcul.eleves) if (e.actif) e.inscriptionId};
    final notes = [
      for (final r in liste)
        if (r.note != null && actifs.contains(r.inscriptionId)) r.note!,
    ];
    if (notes.isEmpty) {
      statsMatiere[m.id] = (null, null, null);
    } else {
      final somme = notes.fold(0, (a, b) => a + b);
      statsMatiere[m.id] = (
        divisionArrondie(somme, notes.length),
        notes.reduce((a, b) => a < b ? a : b),
        notes.reduce((a, b) => a > b ? a : b),
      );
    }
  }

  // Élèves classés (base du « rang sur N ») et rangs partagés.
  final classes = [
    for (final e in calcul.eleves)
      if (resultats[e.inscriptionId]?.rang != null) resultats[e.inscriptionId]!,
  ];
  final effectif = classes.length;
  final partages = <int, int>{};
  for (final r in classes) {
    partages[r.rang!] = (partages[r.rang!] ?? 0) + 1;
  }

  // Récapitulatif par période (bulletin annuel).
  final resultatsPeriodes = <PeriodeScolaire, Map<int, ResultatEleve>>{};
  if (type == TypeBulletin.annuel) {
    for (final p in calcul.calendrier.periodes) {
      resultatsPeriodes[p] = {
        for (final r in calcul.resultats(Portee.periode(p))) r.inscriptionId: r,
      };
    }
  }

  final retenus = [
    for (final e in calcul.eleves)
      if (inscriptions != null ? inscriptions.contains(e.inscriptionId) : e.actif) e,
  ];

  return [
    for (final e in retenus)
      () {
        final r = resultats[e.inscriptionId]!;
        final fiche = fiches[e.eleveId];
        final avis = appreciations[e.inscriptionId];
        return Bulletin(
          type: type,
          periodeLibelle: periodeLibelle,
          anneeLibelle: anneeLibelle,
          etablissementNom: etablissement.nom,
          adresse: etablissement.adresse,
          telephone: etablissement.telephone,
          email: etablissement.email,
          devise: etablissement.devise,
          infosAdmin: etablissement.infosAdmin,
          directeur: etablissement.directeur,
          logo: etablissement.logo,
          signature: etablissement.signatureDirecteur,
          cachet: etablissement.cachet,
          classeNom: classe.nom,
          niveau: classe.libelleNiveau,
          eleveNom: e.nom,
          elevePrenom: e.prenom,
          matricule: e.matricule,
          sexe: e.sexe,
          dateNaissance: e.dateNaissance ?? fiche?.dateNaissance,
          lieuNaissance: fiche?.lieuNaissance ?? '',
          photo: fiche?.photo,
          lignes: [
            for (final m in calcul.matieres)
              LigneBulletin(
                matiere: m.nom,
                coefficient: m.coefficient,
                note: parMatiere[m.id]![e.inscriptionId]?.note,
                rang: parMatiere[m.id]![e.inscriptionId]?.rang,
                moyenneClasse: statsMatiere[m.id]!.$1,
                minClasse: statsMatiere[m.id]!.$2,
                maxClasse: statsMatiere[m.id]!.$3,
                appreciation: appreciationsMatieres[e.inscriptionId]?[m.id] ?? '',
                facultative: m.facultative,
              ),
          ],
          moyenne: r.moyenne,
          rang: r.rang,
          exAequo: r.rang != null && (partages[r.rang!] ?? 0) > 1,
          effectif: effectif,
          moyenneClasse: stats.moyenneClasse,
          meilleureMoyenne: stats.meilleureMoyenne,
          plusFaibleMoyenne: stats.plusFaibleMoyenne,
          mention: r.mention,
          decision: r.decision,
          incomplet: r.incomplet,
          appreciation: avis?.appreciation ?? '',
          decisionConseil: avis?.decision ?? '',
          periodes: [
            for (final entree in resultatsPeriodes.entries)
              ResumePeriode(
                libelle: entree.key.libelle,
                moyenne: entree.value[e.inscriptionId]?.moyenne,
                rang: entree.value[e.inscriptionId]?.rang,
              ),
          ],
          dateEdition: dateEdition,
        );
      }(),
  ];
}
