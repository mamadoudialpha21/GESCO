import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/calendrier.dart';
import '../../domain/permissions.dart';
import '../controle.dart';
import '../erreurs.dart';

/// Calendrier des périodes (trimestres, semestres, séquences), propre à
/// chaque année scolaire : modifier celui d'une année ne change pas les
/// résultats des années passées.
class CalendrierDepot {
  CalendrierDepot(this._db, {this.controle = Controle.aucun});

  final Database _db;
  final Controle controle;

  /// Calendrier de l'année. Si aucun n'a été enregistré, trois trimestres
  /// (octobre-décembre, janvier-mars, avril-juin) sont retournés.
  Future<Calendrier> lire(int anneeId) async {
    final lignes = await _db.query(
      'config_calendrier',
      where: 'annee_id = ?',
      whereArgs: [anneeId],
    );
    if (lignes.isEmpty) return Calendrier.defaut;
    try {
      final calendrier = Calendrier.fromJsonString(lignes.first['json'] as String);
      if (calendrier.erreurs().isNotEmpty) throw const FormatException();
      return calendrier;
    } catch (_) {
      throw const ErreurGesco(
        'Le calendrier des périodes de cette année est illisible. '
        'Restaurez une sauvegarde ou réenregistrez les périodes.',
      );
    }
  }

  /// Enregistre le calendrier après validation. Si une note existe déjà, les
  /// notes ne bougent pas : seuls les regroupements de mois changent.
  Future<void> enregistrer(int anneeId, Calendrier calendrier) async {
    controle.exiger(Permission.parametresGerer, 'modifier les périodes');
    final erreurs = calendrier.erreurs();
    if (erreurs.isNotEmpty) {
      throw ErreurGesco(erreurs.join('\n'));
    }
    final existe = await _db.query(
      'annee_scolaire',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [anneeId],
    );
    if (existe.isEmpty) {
      throw const ErreurGesco('Année scolaire introuvable.');
    }
    await _db.insert(
      'config_calendrier',
      {'annee_id': anneeId, 'json': calendrier.toJsonString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await controle.noter('modification', 'calendrier', id: anneeId);
  }

  /// Revient aux trois trimestres par défaut.
  Future<void> reinitialiser(int anneeId) async {
    controle.exiger(Permission.parametresGerer, 'modifier les périodes');
    await _db.delete(
      'config_calendrier',
      where: 'annee_id = ?',
      whereArgs: [anneeId],
    );
    await controle.noter('reinitialisation', 'calendrier', id: anneeId);
  }
}
