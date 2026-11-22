/// Construction des fiches de notes remises aux professeurs.
library;

import '../data/modeles_donnees.dart';
import '../data/modeles_notation.dart';
import '../documents/elements_pdf.dart';
import '../documents/modele_fiche_notes.dart';
import '../domain/dates.dart';
import '../domain/periodes.dart';

/// Nombre maximal de colonnes de notes sur une fiche.
const int colonnesNotesMax = 10;

/// Titres des colonnes de notes d'une fiche.
///
/// Si [saisie] contient des titres séparés par des virgules ou des
/// points-virgules, ce sont eux (dans la limite de [colonnesNotesMax]) ;
/// sinon [nombre] colonnes « Note 1 », « Note 2 »... (une seule : « Note »).
List<String> intitulesFiche(String saisie, int nombre) {
  final titres = [
    for (final t in saisie.split(RegExp(r'[,;\n]')))
      if (t.trim().isNotEmpty) t.trim(),
  ];
  if (titres.isNotEmpty) return titres.take(colonnesNotesMax).toList();
  final n = nombre.clamp(1, colonnesNotesMax);
  if (n == 1) return const ['Note'];
  return [for (var i = 1; i <= n; i++) 'Note $i'];
}

/// Réglages communs aux fiches d'une même impression.
class OptionsFicheNotes {
  const OptionsFicheNotes({
    this.periode = '',
    this.intitules = const ['Note'],
    this.avecMatricule = true,
    this.avecSexe = false,
    this.avecObservations = true,
  });

  /// « Novembre », « 1er trimestre »... ; vide = à écrire à la main.
  final String periode;
  final List<String> intitules;
  final bool avecMatricule;
  final bool avecSexe;
  final bool avecObservations;
}

EnteteEtablissement _entete(Etablissement e) => EnteteEtablissement(
      nom: e.nom,
      adresse: e.adresse,
      telephone: e.telephone,
      email: e.email,
      devise: e.devise,
      infosAdmin: e.infosAdmin,
      logo: e.logo,
    );

/// Élèves qui suivent la classe, dans l'ordre reçu (celui des écrans de saisie).
List<LigneFicheNotes> _lignes(List<EleveInscrit> eleves) {
  final actifs = [
    for (final e in eleves)
      if (e.actif) e,
  ];
  return [
    for (var i = 0; i < actifs.length; i++)
      LigneFicheNotes(
        numero: i + 1,
        nom: actifs[i].nomComplet,
        matricule: actifs[i].matricule,
        sexe: actifs[i].sexe,
      ),
  ];
}

/// Une fiche de notes par matière de [matieres], dans cet ordre.
///
/// [enseignants] associe l'identifiant d'un enseignant à son nom complet : une
/// matière sans enseignant connu laisse la ligne « Enseignant » à remplir à la
/// main. Les élèves partis ou ayant abandonné ne figurent pas sur les fiches.
List<FicheNotes> construireFichesNotes({
  required Etablissement etablissement,
  required String anneeLibelle,
  required String classeNom,
  required List<EleveInscrit> eleves,
  required List<MatiereClasse> matieres,
  Map<int, String> enseignants = const {},
  OptionsFicheNotes options = const OptionsFicheNotes(),
  DateTime? dateEdition,
}) {
  final lignes = _lignes(eleves);
  return [
    for (final m in matieres)
      FicheNotes(
        entete: _entete(etablissement),
        classeNom: classeNom,
        anneeLibelle: anneeLibelle,
        matiereNom: m.nom,
        enseignant: enseignants[m.enseignantId] ?? '',
        bareme: m.bareme,
        periode: options.periode.trim(),
        intitules: options.intitules,
        avecMatricule: options.avecMatricule,
        avecSexe: options.avecSexe,
        avecObservations: options.avecObservations,
        lignes: lignes,
        dateEdition: dateEdition,
      ),
  ];
}

/// Liste de la classe sans matière ni colonne de notes.
FicheNotes construireListeClasse({
  required Etablissement etablissement,
  required String anneeLibelle,
  required String classeNom,
  required List<EleveInscrit> eleves,
  OptionsFicheNotes options = const OptionsFicheNotes(),
  DateTime? dateEdition,
}) {
  return FicheNotes(
    entete: _entete(etablissement),
    classeNom: classeNom,
    anneeLibelle: anneeLibelle,
    intitules: const [],
    avecMatricule: options.avecMatricule,
    avecSexe: options.avecSexe,
    avecObservations: options.avecObservations,
    lignes: _lignes(eleves),
    dateEdition: dateEdition,
  );
}

/// Fiche d'une évaluation précise : une seule colonne, au titre de
/// l'évaluation, sur le barème de celle-ci.
FicheNotes construireFicheEvaluation({
  required Etablissement etablissement,
  required String anneeLibelle,
  required String classeNom,
  required List<EleveInscrit> eleves,
  required Evaluation evaluation,
  required MatiereClasse matiere,
  String enseignant = '',
  OptionsFicheNotes options = const OptionsFicheNotes(),
  DateTime? dateEdition,
}) {
  final date = formaterDateFr(evaluation.date);
  return FicheNotes(
    entete: _entete(etablissement),
    classeNom: classeNom,
    anneeLibelle: anneeLibelle,
    matiereNom: matiere.nom,
    enseignant: enseignant,
    bareme: evaluation.bareme,
    periode: libelleMois(evaluation.mois),
    evaluation: date.isEmpty ? evaluation.titre : '${evaluation.titre} du $date',
    intitules: [evaluation.titre],
    avecMatricule: options.avecMatricule,
    avecSexe: options.avecSexe,
    avecObservations: options.avecObservations,
    lignes: _lignes(eleves),
    dateEdition: dateEdition,
  );
}
