/// Contenu d'un classement ou d'un état des résultats annuels, indépendant de
/// sa mise en page.
library;

import 'dart:typed_data';

import '../domain/statistiques.dart';
import 'elements_pdf.dart';

/// Une ligne du classement.
class LigneDocClassement {
  const LigneDocClassement({
    required this.nom,
    required this.matricule,
    this.rang,
    this.exAequo = false,
    this.moyenne,
    this.mention = '',
    this.decision = '',
    this.observation = '',
    this.incomplet = false,
    this.moyennesPeriodes = const [],
  });

  /// « DIALLO Aminata ».
  final String nom;
  final String matricule;

  /// Rang (ex æquo possibles), null si l'élève n'est pas classé.
  final int? rang;
  final bool exAequo;

  /// Moyenne ou note en centièmes, null sans note.
  final int? moyenne;
  final String mention;
  final String decision;

  /// Précision pour un élève non classé : « Parti », « Abandon », « Sans note ».
  final String observation;
  final bool incomplet;

  /// Moyenne de chaque période, dans l'ordre de [DocumentClassement.periodes].
  final List<int?> moyennesPeriodes;
}

/// Un classement de classe prêt à imprimer.
class DocumentClassement {
  const DocumentClassement({
    required this.entete,
    required this.titre,
    this.sousTitre = '',
    required this.classeNom,
    this.anneeLibelle = '',
    this.libelleMoyenne = 'Moyenne',
    this.periodes = const [],
    this.avecDecision = true,
    required this.lignes,
    this.stats,
    this.directeur = '',
    this.signature,
    this.cachet,
    this.dateEdition,
  });

  final EnteteEtablissement entete;

  /// « CLASSEMENT GÉNÉRAL », « RÉSULTATS ANNUELS »...
  final String titre;
  final String sousTitre;
  final String classeNom;
  final String anneeLibelle;

  /// Titre de la colonne principale : « Moyenne » ou « Note /20 ».
  final String libelleMoyenne;

  /// Libellés des colonnes de périodes (résultats annuels), éventuellement vide.
  final List<String> periodes;

  /// Afficher la colonne « Décision » (absente d'un classement par matière).
  final bool avecDecision;
  final List<LigneDocClassement> lignes;

  /// Statistiques de la classe, imprimées sous le tableau.
  final StatsClasse? stats;
  final String directeur;
  final Uint8List? signature;
  final Uint8List? cachet;
  final DateTime? dateEdition;
}
