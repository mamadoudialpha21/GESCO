/// Les styles de mise en page des documents PDF (bulletins, classements...).
library;

import 'package:pdf/pdf.dart';

/// Décor de l'en-tête d'un document.
enum OrnementEntete {
  /// Un filet de couleur sous l'en-tête.
  filet,

  /// Deux filets fins (un épais, un fin) sous l'en-tête.
  doubleFilet,

  /// Bandeau plein de la couleur principale, texte clair.
  bandeau,

  /// Bande aux trois couleurs du drapeau guinéen en haut de page.
  tricolore,

  /// Aucun décor : seulement un trait noir très fin.
  sobre,
}

/// Couleurs et typographie d'un style de document.
class StyleBulletin {
  const StyleBulletin({
    required this.id,
    required this.nom,
    required this.description,
    required this.principale,
    required this.claire,
    required this.accent,
    this.texte = const PdfColor.fromInt(0xFF1E2430),
    this.discret = const PdfColor.fromInt(0xFF5A6270),
    this.bordure = const PdfColor.fromInt(0xFFC9CED6),
    this.surPrincipale = PdfColors.white,
    this.ornement = OrnementEntete.filet,
    this.enteteTableauPlein = true,
    this.serif = false,
  });

  /// Identifiant stable (enregistré dans les préférences).
  final String id;
  final String nom;
  final String description;

  /// Couleur dominante : titres, en-tête du tableau.
  final PdfColor principale;

  /// Teinte très claire : lignes alternées, encadrés.
  final PdfColor claire;

  /// Couleur de rehaut : filets, mise en valeur de la moyenne.
  final PdfColor accent;
  final PdfColor texte;
  final PdfColor discret;
  final PdfColor bordure;

  /// Couleur du texte posé sur la couleur principale.
  final PdfColor surPrincipale;
  final OrnementEntete ornement;

  /// En-tête du tableau rempli de la couleur principale (sinon : simple filet).
  final bool enteteTableauPlein;

  /// Police à empattements pour les titres et le texte.
  final bool serif;

  /// Classique bleu : le style par défaut.
  static const classiqueBleu = StyleBulletin(
    id: 'classique_bleu',
    nom: 'Classique bleu',
    description: 'Sobre et institutionnel, bleu marine.',
    principale: PdfColor.fromInt(0xFF1F3A68),
    claire: PdfColor.fromInt(0xFFEAF0F9),
    accent: PdfColor.fromInt(0xFF2F5597),
    ornement: OrnementEntete.doubleFilet,
  );

  /// Rouge, jaune, vert : les couleurs du drapeau de la Guinée.
  static const couleursGuineennes = StyleBulletin(
    id: 'couleurs_guineennes',
    nom: 'Couleurs guinéennes',
    description: 'Rouge, jaune et vert du drapeau guinéen.',
    principale: PdfColor.fromInt(0xFF007A4D),
    claire: PdfColor.fromInt(0xFFFFF6D1),
    accent: PdfColor.fromInt(0xFFCE1126),
    ornement: OrnementEntete.tricolore,
  );

  static const elegantRose = StyleBulletin(
    id: 'elegant_rose',
    nom: 'Élégant rose',
    description: 'Rose profond, police à empattements.',
    principale: PdfColor.fromInt(0xFFA8325E),
    claire: PdfColor.fromInt(0xFFFBEAF1),
    accent: PdfColor.fromInt(0xFFD17A9E),
    ornement: OrnementEntete.doubleFilet,
    serif: true,
  );

  static const moderneAnthracite = StyleBulletin(
    id: 'moderne_anthracite',
    nom: 'Moderne anthracite',
    description: 'Bandeau anthracite, touche orangée.',
    principale: PdfColor.fromInt(0xFF2B2F36),
    claire: PdfColor.fromInt(0xFFF0F1F3),
    accent: PdfColor.fromInt(0xFFE8590C),
    ornement: OrnementEntete.bandeau,
  );

  static const minimalisteNoirBlanc = StyleBulletin(
    id: 'minimaliste_noir_blanc',
    nom: 'Minimaliste noir et blanc',
    description: 'Noir sur blanc, économe en encre.',
    principale: PdfColor.fromInt(0xFF000000),
    claire: PdfColor.fromInt(0xFFF4F4F4),
    accent: PdfColor.fromInt(0xFF000000),
    texte: PdfColor.fromInt(0xFF000000),
    discret: PdfColor.fromInt(0xFF4D4D4D),
    bordure: PdfColor.fromInt(0xFF8C8C8C),
    ornement: OrnementEntete.sobre,
    enteteTableauPlein: false,
  );

  static const bleuEtOr = StyleBulletin(
    id: 'bleu_et_or',
    nom: 'Bleu et or',
    description: 'Bleu nuit relevé de filets dorés.',
    principale: PdfColor.fromInt(0xFF14284B),
    claire: PdfColor.fromInt(0xFFF7F1DC),
    accent: PdfColor.fromInt(0xFFB8901F),
    ornement: OrnementEntete.doubleFilet,
    serif: true,
  );

  static const vertSauge = StyleBulletin(
    id: 'vert_sauge',
    nom: 'Vert sauge',
    description: 'Tons doux de vert sauge.',
    principale: PdfColor.fromInt(0xFF58775F),
    claire: PdfColor.fromInt(0xFFEDF3EE),
    accent: PdfColor.fromInt(0xFF8DAA93),
  );

  static const violet = StyleBulletin(
    id: 'violet',
    nom: 'Violet',
    description: 'Violet profond, accent lilas.',
    principale: PdfColor.fromInt(0xFF5B3A8E),
    claire: PdfColor.fromInt(0xFFF1EBF8),
    accent: PdfColor.fromInt(0xFF8E6BC1),
  );

  /// Tous les styles proposés, dans l'ordre d'affichage.
  static const tous = <StyleBulletin>[
    classiqueBleu,
    couleursGuineennes,
    elegantRose,
    moderneAnthracite,
    minimalisteNoirBlanc,
    bleuEtOr,
    vertSauge,
    violet,
  ];

  /// Le style portant cet identifiant, ou le style classique si inconnu.
  static StyleBulletin parId(String? id) =>
      tous.firstWhere((s) => s.id == id, orElse: () => classiqueBleu);
}

/// Les trois couleurs du drapeau de la Guinée.
const rougeGuinee = PdfColor.fromInt(0xFFCE1126);
const jauneGuinee = PdfColor.fromInt(0xFFFCD116);
const vertGuinee = PdfColor.fromInt(0xFF009460);
