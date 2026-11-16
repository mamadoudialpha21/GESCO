import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/modeles.dart';
import '../erreurs.dart';

/// Seuils de mentions et de décisions, enregistrés séparément pour chaque
/// année scolaire : les modifier ne change pas les résultats des années
/// passées.
class ConfigResultatsDepot {
  ConfigResultatsDepot(this._db);

  final Database _db;

  /// Configuration de l'année. Si aucune n'a été enregistrée, les valeurs par
  /// défaut sont retournées.
  Future<ConfigResultats> lire(int anneeId) async {
    final lignes = await _db.query(
      'config_resultats',
      where: 'annee_id = ?',
      whereArgs: [anneeId],
    );
    if (lignes.isEmpty) return ConfigResultats.defaut;
    try {
      return ConfigResultats.fromJsonString(lignes.first['json'] as String);
    } catch (_) {
      throw const ErreurGesco(
        'La configuration des mentions et décisions de cette année est '
        'illisible. Restaurez une sauvegarde ou réenregistrez les seuils.',
      );
    }
  }

  /// Enregistre la configuration après validation. Si elle contient des
  /// erreurs, rien n'est modifié et une [ErreurGesco] liste les problèmes.
  Future<void> enregistrer(int anneeId, ConfigResultats config) async {
    final erreurs = config.erreurs();
    if (erreurs.isNotEmpty) {
      throw ErreurGesco(erreurs.join('\n'));
    }
    await _db.insert(
      'config_resultats',
      {'annee_id': anneeId, 'json': config.toJsonString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
