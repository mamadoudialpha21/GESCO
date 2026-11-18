import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/modeles.dart';
import '../../domain/permissions.dart';
import '../controle.dart';
import '../erreurs.dart';

/// Seuils de mentions et de décisions, enregistrés séparément pour chaque
/// année scolaire : les modifier ne change pas les résultats des années
/// passées.
class ConfigResultatsDepot {
  ConfigResultatsDepot(this._db, {this.controle = Controle.aucun});

  final Database _db;
  final Controle controle;

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
    controle.exiger(Permission.parametresGerer, 'modifier les seuils et mentions');
    final erreurs = config.erreurs();
    if (erreurs.isNotEmpty) {
      throw ErreurGesco(erreurs.join('\n'));
    }
    await _db.insert(
      'config_resultats',
      {'annee_id': anneeId, 'json': config.toJsonString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await controle.noter('modification', 'seuils', id: anneeId);
  }
}
