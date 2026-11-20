/// Polices embarquées dans les PDF.
///
/// Les polices standard d'un PDF ne contiennent pas tous les caractères du
/// français (« œ », « € », guillemets…). DejaVu, libre de droits, les contient
/// tous : elle est intégrée à l'application et incorporée dans chaque document.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:pdf/widgets.dart' as pw;

class PolicesPdf {
  const PolicesPdf({
    required this.sans,
    required this.sansGras,
    required this.sansItalique,
    required this.serif,
    required this.serifGras,
    required this.serifItalique,
  });

  /// Construit les polices à partir du contenu des fichiers .ttf.
  factory PolicesPdf.depuisOctets({
    required Uint8List sans,
    required Uint8List sansGras,
    required Uint8List sansItalique,
    required Uint8List serif,
    required Uint8List serifGras,
    required Uint8List serifItalique,
  }) {
    pw.Font police(Uint8List o) => pw.Font.ttf(ByteData.sublistView(o));
    return PolicesPdf(
      sans: police(sans),
      sansGras: police(sansGras),
      sansItalique: police(sansItalique),
      serif: police(serif),
      serifGras: police(serifGras),
      serifItalique: police(serifItalique),
    );
  }

  /// Chemins des fichiers dans les ressources de l'application.
  static const fichiers = <String>[
    'assets/fonts/DejaVuSans.ttf',
    'assets/fonts/DejaVuSans-Bold.ttf',
    'assets/fonts/DejaVuSans-Oblique.ttf',
    'assets/fonts/DejaVuSerif.ttf',
    'assets/fonts/DejaVuSerif-Bold.ttf',
    'assets/fonts/DejaVuSerif-Italic.ttf',
  ];

  /// Charge les six fichiers depuis les ressources de l'application.
  static Future<PolicesPdf> charger({AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    final donnees = <ByteData>[for (final f in fichiers) await b.load(f)];
    pw.Font police(int i) => pw.Font.ttf(donnees[i]);
    return PolicesPdf(
      sans: police(0),
      sansGras: police(1),
      sansItalique: police(2),
      serif: police(3),
      serifGras: police(4),
      serifItalique: police(5),
    );
  }

  final pw.Font sans;
  final pw.Font sansGras;
  final pw.Font sansItalique;
  final pw.Font serif;
  final pw.Font serifGras;
  final pw.Font serifItalique;

  /// Thème PDF : texte courant, gras et italique de la famille choisie.
  pw.ThemeData theme({required bool serif}) => serif
      ? pw.ThemeData.withFont(
          base: this.serif,
          bold: serifGras,
          italic: serifItalique,
          boldItalic: serifGras,
        )
      : pw.ThemeData.withFont(
          base: sans,
          bold: sansGras,
          italic: sansItalique,
          boldItalic: sansGras,
        );
}
