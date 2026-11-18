import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Exécute une requête `SELECT COUNT(*) ...` et retourne le nombre obtenu.
Future<int> compter(
  DatabaseExecutor db,
  String sql, [
  List<Object?>? arguments,
]) async {
  final lignes = await db.rawQuery(sql, arguments);
  if (lignes.isEmpty) return 0;
  return (lignes.first.values.first as int?) ?? 0;
}

/// Pluriel simple : `pluriel(2, 'élève')` -> « 2 élèves ».
String pluriel(int nombre, String mot) =>
    nombre > 1 ? '$nombre ${mot}s' : '$nombre $mot';

/// Date et heure au format enregistré dans les journaux : `2026-11-17T08:05:09`
/// (heure locale, sans fraction de seconde). Se trie comme du texte.
String horodatage(DateTime date) {
  String d2(int n) => n.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-${d2(date.month)}-${d2(date.day)}'
      'T${d2(date.hour)}:${d2(date.minute)}:${d2(date.second)}';
}
