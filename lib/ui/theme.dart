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

  static const Color fond = Color(0xFFF6F8FB);
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
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: CouleursGesco.bleu),
    scaffoldBackgroundColor: CouleursGesco.fond,
  );
}
