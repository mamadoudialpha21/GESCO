/// Contenu d'une fiche de notes (ou d'une liste de classe) à remettre au
/// professeur, indépendant de sa mise en page.
library;

import 'elements_pdf.dart';

/// Un élève de la fiche.
class LigneFicheNotes {
  const LigneFicheNotes({
    required this.numero,
    required this.nom,
    this.matricule = '',
    this.sexe = '',
  });

  /// Numéro d'ordre dans la fiche (1, 2, 3...), le même que l'ordre de l'écran
  /// de saisie : le professeur et la personne qui saisit se repèrent ainsi.
  final int numero;

  /// « DIALLO Aminata ».
  final String nom;
  final String matricule;

  /// « F », « M » ou vide.
  final String sexe;
}

/// Une fiche : la liste d'une classe avec des colonnes vides pour les notes
/// d'une matière. Sans [matiereNom], c'est une simple liste de classe.
class FicheNotes {
  const FicheNotes({
    required this.entete,
    required this.classeNom,
    this.anneeLibelle = '',
    this.matiereNom,
    this.enseignant = '',
    this.bareme = 20,
    this.periode = '',
    this.evaluation = '',
    this.intitules = const [],
    this.avecMatricule = true,
    this.avecSexe = false,
    this.avecObservations = true,
    required this.lignes,
    this.dateEdition,
  });

  final EnteteEtablissement entete;
  final String classeNom;
  final String anneeLibelle;

  /// Matière notée ; null pour une liste de classe seule.
  final String? matiereNom;

  /// Nom de l'enseignant ; vide si la matière n'en a pas : la ligne est alors
  /// laissée à remplir à la main.
  final String enseignant;

  /// Note maximale de la matière (10, 20, 40...).
  final int bareme;

  /// « Novembre », « 1er trimestre »... ; vide = à écrire à la main.
  final String periode;

  /// Titre de l'évaluation (« Devoir n° 2 »), s'il s'agit d'une évaluation
  /// précise.
  final String evaluation;

  /// Titre de chaque colonne de notes à remplir.
  final List<String> intitules;
  final bool avecMatricule;
  final bool avecSexe;
  final bool avecObservations;
  final List<LigneFicheNotes> lignes;
  final DateTime? dateEdition;

  bool get estListe => matiereNom == null;

  /// « FICHE DE NOTES » ou « LISTE DE CLASSE ».
  String get titre => estListe ? 'LISTE DE CLASSE' : 'FICHE DE NOTES';

  int get nbFilles => lignes.where((l) => l.sexe == 'F').length;
  int get nbGarcons => lignes.where((l) => l.sexe == 'M').length;
}
