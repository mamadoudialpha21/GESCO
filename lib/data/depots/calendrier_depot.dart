import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/calendrier.dart';
import '../../domain/niveaux.dart';
import '../../domain/permissions.dart';
import '../controle.dart';
import '../erreurs.dart';

/// Calendrier des périodes (trimestres, semestres, séquences), propre à
/// chaque année scolaire et à chaque cycle d'études : le primaire a trois
/// trimestres, le collège et le lycée deux. Modifier le calendrier d'une
/// année ne change pas les résultats des années passées.
///
/// Sans cycle, les méthodes lisent et écrivent le calendrier général de
/// l'année, que suivent les classes non rattachées à un cycle.
class CalendrierDepot {
  CalendrierDepot(this._db, {this.controle = Controle.aucun});

  final Database _db;
  final Controle controle;

  /// Calendrier de l'année pour un [cycle]. Si aucun n'a été enregistré : le
  /// modèle du cycle (trois trimestres au primaire, deux au collège et au
  /// lycée) ; sans cycle, trois trimestres (octobre-décembre, janvier-mars,
  /// avril-juin).
  Future<Calendrier> lire(int anneeId, {Cycle? cycle}) async {
    final lignes = cycle == null
        ? await _db.query(
            'config_calendrier',
            where: 'annee_id = ?',
            whereArgs: [anneeId],
          )
        : await _db.query(
            'config_calendrier_cycle',
            where: 'annee_id = ? AND cycle = ?',
            whereArgs: [anneeId, cycle.cle],
          );
    if (lignes.isEmpty) return Calendrier.pourCycle(cycle);
    return _decoder(lignes.first['json'] as String, cycle);
  }

  /// Tous les calendriers de l'année, en une seule lecture.
  Future<CalendriersAnnee> lireTous(int anneeId) async {
    final parCycle = <Cycle, Calendrier>{};
    final lignes = await _db.query(
      'config_calendrier_cycle',
      where: 'annee_id = ?',
      whereArgs: [anneeId],
    );
    for (final l in lignes) {
      final cycle = Cycle.depuisCle(l['cycle'] as String?);
      if (cycle != null) parCycle[cycle] = _decoder(l['json'] as String, cycle);
    }
    return CalendriersAnnee(general: await lire(anneeId), parCycle: parCycle);
  }

  static Calendrier _decoder(String json, Cycle? cycle) {
    try {
      final calendrier = Calendrier.fromJsonString(json);
      if (calendrier.erreurs().isNotEmpty) throw const FormatException();
      return calendrier;
    } catch (_) {
      final precision = cycle == null ? '' : ' (${cycle.libelle})';
      throw ErreurGesco(
        'Le calendrier des périodes$precision de cette année est illisible. '
        'Restaurez une sauvegarde ou réenregistrez les périodes.',
      );
    }
  }

  /// Enregistre le calendrier après validation. Si une note existe déjà, les
  /// notes ne bougent pas : seuls les regroupements de mois changent.
  Future<void> enregistrer(
    int anneeId,
    Calendrier calendrier, {
    Cycle? cycle,
  }) async {
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
    if (cycle == null) {
      await _db.insert(
        'config_calendrier',
        {'annee_id': anneeId, 'json': calendrier.toJsonString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await _db.insert(
        'config_calendrier_cycle',
        {'annee_id': anneeId, 'cycle': cycle.cle, 'json': calendrier.toJsonString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await controle.noter(
      'modification',
      'calendrier',
      id: anneeId,
      details: cycle?.libelle ?? '',
    );
  }

  /// Revient au modèle par défaut : celui du cycle, ou les trois trimestres
  /// pour le calendrier général.
  Future<void> reinitialiser(int anneeId, {Cycle? cycle}) async {
    controle.exiger(Permission.parametresGerer, 'modifier les périodes');
    if (cycle == null) {
      await _db.delete(
        'config_calendrier',
        where: 'annee_id = ?',
        whereArgs: [anneeId],
      );
    } else {
      await _db.delete(
        'config_calendrier_cycle',
        where: 'annee_id = ? AND cycle = ?',
        whereArgs: [anneeId, cycle.cle],
      );
    }
    await controle.noter(
      'reinitialisation',
      'calendrier',
      id: anneeId,
      details: cycle?.libelle ?? '',
    );
  }
}
