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
