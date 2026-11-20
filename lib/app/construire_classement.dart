/// Construction du contenu d'un classement de classe à imprimer.
library;

import '../data/modeles_donnees.dart';
import '../documents/elements_pdf.dart';
import '../documents/modele_classement.dart';
import '../domain/calendrier.dart';
import 'calcul_classe.dart';

/// Classement d'une classe pour une étendue.
///
/// - Sans [matiereId] : classement général (moyenne, mention, décision) ; avec
///   [matiereId] : classement dans la matière (note sur 20, pas de décision).
/// - [detaillerPeriodes] : ajoute une colonne par période (résultats annuels).
///   Ignoré pour un classement par matière.
/// - Les élèves non classés (sans note, partis, abandons) figurent à la fin,
///   avec leur observation.
DocumentClassement construireClassement({
  required CalculClasse calcul,
  required Portee portee,
  required String periodeLibelle,
  required Etablissement etablissement,
  required String anneeLibelle,
  int? matiereId,
  bool detaillerPeriodes = false,
  DateTime? dateEdition,
}) {
  final parMatiere = matiereId != null;
  final matiere = parMatiere ? calcul.matieres.firstWhere((m) => m.id == matiereId) : null;
  final List<PeriodeScolaire> periodes =
      detaillerPeriodes && !parMatiere ? calcul.calendrier.periodes : const [];

  final resultatsPeriodes = [
    for (final p in periodes)
      {for (final r in calcul.resultats(Portee.periode(p))) r.inscriptionId: r.moyenne},
  ];

  final lignes = [
    for (final l in lignesClassement(calcul, portee, matiereId: matiereId))
      LigneDocClassement(
        nom: l.eleve.nomComplet,
        matricule: l.eleve.matricule,
        rang: l.rang,
        exAequo: l.exAequo,
        moyenne: l.moyenne,
        mention: l.mention,
        decision: l.decision,
        observation: _observation(l),
        incomplet: l.incomplet,
        moyennesPeriodes: [
          for (final m in resultatsPeriodes) m[l.eleve.inscriptionId],
        ],
      ),
  ];

  final String titre;
  if (parMatiere) {
    titre = 'CLASSEMENT EN ${matiere!.nom.toUpperCase()}';
  } else if (detaillerPeriodes && portee.annuelle) {
    titre = 'RÉSULTATS ANNUELS';
  } else {
    titre = 'CLASSEMENT GÉNÉRAL';
  }

  return DocumentClassement(
    entete: EnteteEtablissement(
      nom: etablissement.nom,
      adresse: etablissement.adresse,
      telephone: etablissement.telephone,
      email: etablissement.email,
      devise: etablissement.devise,
      infosAdmin: etablissement.infosAdmin,
      logo: etablissement.logo,
    ),
    titre: titre,
    sousTitre: periodeLibelle,
    classeNom: calcul.classe.classe.nom,
    anneeLibelle: anneeLibelle,
    libelleMoyenne: parMatiere ? 'Note /20' : 'Moyenne',
    periodes: [for (final p in periodes) p.libelle],
    avecDecision: !parMatiere,
    lignes: lignes,
    stats: parMatiere ? null : calcul.stats(portee),
    directeur: etablissement.directeur,
    signature: etablissement.signatureDirecteur,
    cachet: etablissement.cachet,
    dateEdition: dateEdition,
  );
}

String _observation(LigneClassement l) {
  if (l.rang != null) return '';
  if (!l.eleve.actif) return l.eleve.statut.libelle;
  return 'Sans note';
}
