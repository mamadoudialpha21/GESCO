import 'package:flutter/material.dart';

import '../domain/modeles.dart';

/// Codes couleur de GESCO :
/// vert = bons résultats, orange = moyens, rouge = insuffisants,
/// bleu = informations générales, gris = informations secondaires.
class CouleursGesco {
  const CouleursGesco._();

  static const Color vert = Color(0xFF2E7D32);
  static const Color orange = Color(0xFFEF6C00);
  static const Color rouge = Color(0xFFC62828);
  static const Color bleu = Color(0xFF1F5FA8);
  static const Color gris = Color(0xFF6B7280);

  static const Color vertClair = Color(0xFFE8F5E9);
  static const Color orangeClair = Color(0xFFFFF3E0);
  static const Color rougeClair = Color(0xFFFFEBEE);
  static const Color bleuClair = Color(0xFFE3F0FB);
  static const Color grisClair = Color(0xFFF1F2F4);

  /// Fond des pages.
  static const Color fond = Color(0xFFF4F6FA);

  /// Bleu profond du menu latéral et des bandeaux.
  static const Color bleuFonce = Color(0xFF0F3566);

  /// Texte principal et trait fin des cartes et séparateurs.
  static const Color texte = Color(0xFF1C2330);
  static const Color bordure = Color(0xFFE1E6EE);

  /// Trait des champs de saisie (un peu plus marqué que celui des cartes).
  static const Color bordureChamp = Color(0xFFB9C2D0);
}

/// Couleur associée à un niveau de résultat (vert / orange / rouge).
Color couleurNiveau(NiveauResultat niveau) => switch (niveau) {
      NiveauResultat.bon => CouleursGesco.vert,
      NiveauResultat.moyen => CouleursGesco.orange,
      NiveauResultat.insuffisant => CouleursGesco.rouge,
    };

/// Fond clair associé à un niveau de résultat.
Color fondNiveau(NiveauResultat niveau) => switch (niveau) {
      NiveauResultat.bon => CouleursGesco.vertClair,
      NiveauResultat.moyen => CouleursGesco.orangeClair,
      NiveauResultat.insuffisant => CouleursGesco.rougeClair,
    };

ThemeData construireTheme() {
  final forme = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: CouleursGesco.bleu),
    scaffoldBackgroundColor: CouleursGesco.fond,
    dividerTheme: const DividerThemeData(
      color: CouleursGesco.bordure,
      space: 1,
      thickness: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: forme,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: forme,
        side: const BorderSide(color: CouleursGesco.bordureChamp),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: forme,
    ),
  );
}
