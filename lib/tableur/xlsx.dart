/// Lecture et écriture des fichiers Excel (.xlsx) avec la bibliothèque `excel`
/// (pur Dart, aucun accès réseau). C'est le seul fichier qui la connaît.
library;

import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;

import '../data/erreurs.dart';
import 'classeur.dart';

/// Lit un classeur .xlsx. Lève une [ErreurGesco] lisible si le fichier n'est pas
/// un classeur Excel valide (autre format, fichier abîmé, ancien .xls).
ClasseurLu lireClasseur(Uint8List octets) {
  final xl.Excel classeur;
  try {
    classeur = xl.Excel.decodeBytes(octets);
  } catch (_) {
    throw const ErreurGesco(
      'Ce fichier n\'est pas un classeur Excel (.xlsx) lisible. '
      'Enregistrez-le au format « Classeur Excel (*.xlsx) » puis réessayez.',
    );
  }
  final feuilles = <FeuilleLue>[];
  for (final entree in classeur.tables.entries) {
    final lignes = <List<Cellule>>[
      for (final ligne in entree.value.rows)
        [for (final donnee in ligne) _lire(donnee?.value)],
    ];
    feuilles.add(FeuilleLue(entree.key, lignes));
  }
  if (feuilles.isEmpty) {
    throw const ErreurGesco('Ce classeur ne contient aucune feuille.');
  }
  return ClasseurLu(feuilles);
}

Cellule _lire(xl.CellValue? v) {
  if (v == null) return const Cellule();
  if (v is xl.TextCellValue) return Cellule(texte: v.toString().trim());
  if (v is xl.IntCellValue) return Cellule(texte: '${v.value}', nombre: v.value.toDouble());
  if (v is xl.DoubleCellValue) {
    return Cellule(texte: _texteNombre(v.value), nombre: v.value);
  }
  if (v is xl.DateCellValue) {
    final d = v.asDateTimeLocal();
    return Cellule(texte: _texteDate(d), date: d);
  }
  if (v is xl.DateTimeCellValue) {
    final d = DateTime(v.year, v.month, v.day);
    return Cellule(texte: _texteDate(d), date: d);
  }
  if (v is xl.BoolCellValue) return Cellule(texte: v.value ? 'VRAI' : 'FAUX');
  if (v is xl.FormulaCellValue) return Cellule(texte: v.formula, formule: true);
  return Cellule(texte: v.toString().trim());
}

String _texteNombre(double d) => d == d.roundToDouble() ? '${d.toInt()}' : '$d';

String _texteDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ------------------------------------------------------------------ Écriture

const _bleu = 'FF1F3A68';

xl.CellStyle _style(StyleCellule s) => switch (s) {
      StyleCellule.normal => xl.CellStyle(verticalAlign: xl.VerticalAlign.Center),
      StyleCellule.titre => xl.CellStyle(
          bold: true,
          fontSize: 14,
          fontColorHex: xl.ExcelColor.fromHexString(_bleu),
        ),
      StyleCellule.entete => xl.CellStyle(
          bold: true,
          fontColorHex: xl.ExcelColor.white,
          backgroundColorHex: xl.ExcelColor.fromHexString(_bleu),
          horizontalAlign: xl.HorizontalAlign.Center,
          verticalAlign: xl.VerticalAlign.Center,
          textWrapping: xl.TextWrapping.WrapText,
        ),
      StyleCellule.consigne => xl.CellStyle(
          italic: true,
          fontColorHex: xl.ExcelColor.fromHexString('FF5A6270'),
          textWrapping: xl.TextWrapping.WrapText,
        ),
      StyleCellule.discret => xl.CellStyle(
          italic: true,
          fontColorHex: xl.ExcelColor.fromHexString('FF5A6270'),
        ),
      StyleCellule.etiquette => xl.CellStyle(bold: true),
      StyleCellule.saisie => xl.CellStyle(
          backgroundColorHex: xl.ExcelColor.fromHexString('FFFFF8DC'),
          horizontalAlign: xl.HorizontalAlign.Center,
        ),
      StyleCellule.note => xl.CellStyle(
          horizontalAlign: xl.HorizontalAlign.Center,
          numberFormat: xl.NumFormat.standard_2,
        ),
      StyleCellule.entier => xl.CellStyle(
          horizontalAlign: xl.HorizontalAlign.Center,
          numberFormat: xl.NumFormat.standard_1,
        ),
      StyleCellule.centre => xl.CellStyle(horizontalAlign: xl.HorizontalAlign.Center),
      StyleCellule.date => xl.CellStyle(
          horizontalAlign: xl.HorizontalAlign.Center,
          numberFormat: xl.NumFormat.standard_14,
        ),
    };

xl.CellValue? _valeur(Object? v) {
  if (v == null) return null;
  if (v is String) return v.isEmpty ? null : xl.TextCellValue(v);
  if (v is int) return xl.IntCellValue(v);
  if (v is double) return xl.DoubleCellValue(v);
  if (v is DateTime) return xl.DateCellValue.fromDateTime(v);
  if (v is bool) return xl.BoolCellValue(v);
  return xl.TextCellValue(v.toString());
}

/// Écrit les [feuilles] dans un classeur .xlsx (une feuille au moins).
Uint8List ecrireClasseur(List<FeuilleEcrite> feuilles) {
  if (feuilles.isEmpty) {
    throw ArgumentError('Un classeur contient au moins une feuille.');
  }
  final classeur = xl.Excel.createExcel();
  final defaut = classeur.getDefaultSheet() ?? 'Sheet1';
  final styles = {for (final s in StyleCellule.values) s: _style(s)};

  final dejaUtilises = <String>{};
  for (var i = 0; i < feuilles.length; i++) {
    final f = feuilles[i];
    final base = nomOngletValide(f.nom);
    var nom = base;
    for (var n = 2; dejaUtilises.contains(nom.toLowerCase()); n++) {
      final suffixe = ' ($n)';
      final debut = base.length + suffixe.length > 31
          ? base.substring(0, 31 - suffixe.length)
          : base;
      nom = '$debut$suffixe';
    }
    dejaUtilises.add(nom.toLowerCase());

    if (i == 0) classeur.rename(defaut, nom);
    final feuille = classeur[nom];
    for (var r = 0; r < f.lignes.length; r++) {
      final ligne = f.lignes[r];
      for (var c = 0; c < ligne.length; c++) {
        final cellule = ligne[c];
        if (cellule == null) continue;
        feuille.updateCell(
          xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
          _valeur(cellule.valeur),
          cellStyle: styles[cellule.style],
        );
      }
    }
    for (var c = 0; c < f.largeurs.length; c++) {
      feuille.setColumnWidth(c, f.largeurs[c]);
    }
  }
  final octets = classeur.encode();
  if (octets == null) {
    throw const ErreurGesco('Le fichier Excel n\'a pas pu être créé.');
  }
  return Uint8List.fromList(octets);
}
