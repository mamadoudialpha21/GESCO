import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/dates.dart';
import '../../domain/permissions.dart';
import '../controle.dart';
import '../erreurs.dart';
import '../modeles_absences.dart';
import 'aides.dart';

/// Absences et retards des élèves inscrits.
///
/// Lecture libre ; écriture réservée à qui gère les élèves. Chaque ajout,
/// modification ou suppression est inscrit au journal.
class AbsenceDepot {
  AbsenceDepot(this._db, {this.controle = Controle.aucun, DateTime Function()? maintenant})
      : _maintenant = maintenant ?? DateTime.now;

  final Database _db;
  final Controle controle;
  final DateTime Function() _maintenant;

  static const int longueurMaxMotif = 200;
  static const int dureeMaxRetard = 600;

  static Absence _depuis(Map<String, Object?> l) => Absence(
        id: l['id'] as int,
        inscriptionId: l['inscription_id'] as int,
        date: l['date'] as String,
        type: TypeAbsence.parCode(l['type'] as String),
        justifiee: (l['justifiee'] as int) == 1,
        dureeMinutes: l['duree_minutes'] as int?,
        motif: (l['motif'] as String?) ?? '',
        eleveNom: (l['eleve_nom'] as String?) ?? '',
        matricule: (l['matricule'] as String?) ?? '',
        classeNom: (l['classe_nom'] as String?) ?? '',
      );

  /// Vérifie les champs et retourne l'absence à enregistrer (motif nettoyé,
  /// durée ignorée pour une absence).
  static Absence verifier(Absence a) {
    if (analyserDateIso(a.date) == null) {
      throw const ErreurGesco('La date est invalide : utilisez le format JJ/MM/AAAA.');
    }
    final motif = a.motif.trim();
    if (motif.length > longueurMaxMotif) {
      throw const ErreurGesco('Le motif est trop long (200 caractères au plus).');
    }
    int? duree;
    if (a.type == TypeAbsence.retard && a.dureeMinutes != null) {
      duree = a.dureeMinutes;
      if (duree! < 1 || duree > dureeMaxRetard) {
        throw const ErreurGesco('La durée du retard doit être comprise entre 1 et 600 minutes.');
      }
    }
    return Absence(
      id: a.id,
      inscriptionId: a.inscriptionId,
      date: a.date,
      type: a.type,
      justifiee: a.justifiee,
      dureeMinutes: duree,
      motif: motif,
    );
  }

  Map<String, Object?> _valeurs(Absence a) => {
        'inscription_id': a.inscriptionId,
        'date': a.date,
        'type': a.type.code,
        'justifiee': a.justifiee ? 1 : 0,
        'duree_minutes': a.dureeMinutes,
        'motif': a.motif,
      };

  String _resume(Absence a) =>
      '${a.type.libelle} du ${formaterDateFr(a.date)}${a.justifiee ? ' (justifiée)' : ''}';

  Future<int> ajouter(Absence absence) async {
    controle.exiger(Permission.elevesGerer, 'enregistrer une absence ou un retard');
    final a = verifier(absence);
    final id = await _db.transaction<int>((txn) async {
      final inscrit = await compter(
        txn,
        'SELECT COUNT(*) FROM inscription WHERE id = ?',
        [a.inscriptionId],
      );
      if (inscrit == 0) throw const ErreurGesco('L\'élève n\'est plus inscrit.');
      await _verifierLibre(txn, a);
      return txn.insert('absence', {
        ..._valeurs(a),
        'cree_le': horodatage(_maintenant()),
      });
    });
    await controle.noter('creation', 'absence', id: id, details: _resume(a));
    return id;
  }

  Future<void> modifier(Absence absence) async {
    controle.exiger(Permission.elevesGerer, 'modifier une absence ou un retard');
    final a = verifier(absence);
    await _db.transaction<void>((txn) async {
      final existe = await compter(txn, 'SELECT COUNT(*) FROM absence WHERE id = ?', [a.id]);
      if (existe == 0) throw const ErreurGesco('Cette absence n\'existe plus.');
      await _verifierLibre(txn, a, sauf: a.id);
      await txn.update('absence', _valeurs(a), where: 'id = ?', whereArgs: [a.id]);
    });
    await controle.noter('modification', 'absence', id: a.id, details: _resume(a));
  }

  Future<void> supprimer(int id) async {
    controle.exiger(Permission.elevesGerer, 'supprimer une absence ou un retard');
    String? resume;
    await _db.transaction<void>((txn) async {
      final l = await txn.query('absence', where: 'id = ?', whereArgs: [id]);
      if (l.isEmpty) throw const ErreurGesco('Cette absence n\'existe plus.');
      resume = _resume(_depuis(l.first));
      await txn.delete('absence', where: 'id = ?', whereArgs: [id]);
    });
    await controle.noter('suppression', 'absence', id: id, details: resume ?? '');
  }

  Future<void> _verifierLibre(DatabaseExecutor db, Absence a, {int? sauf}) async {
    final doublons = await compter(
      db,
      'SELECT COUNT(*) FROM absence WHERE inscription_id = ? AND date = ? AND type = ? '
      'AND id <> ?',
      [a.inscriptionId, a.date, a.type.code, sauf ?? 0],
    );
    if (doublons > 0) {
      throw ErreurGesco(
        'Un${a.type == TypeAbsence.absence ? 'e absence est' : ' retard est'} '
        'déjà enregistré${a.type == TypeAbsence.absence ? 'e' : ''} '
        'pour cet élève le ${formaterDateFr(a.date)}.',
      );
    }
  }

  /// Absences et retards d'une inscription, du plus récent au plus ancien.
  Future<List<Absence>> lister(int inscriptionId) async {
    final lignes = await _db.query(
      'absence',
      where: 'inscription_id = ?',
      whereArgs: [inscriptionId],
      orderBy: 'date DESC, id DESC',
    );
    return [for (final l in lignes) _depuis(l)];
  }

  /// Absences et retards des élèves d'une année (ou d'une seule classe), avec le
  /// nom de l'élève et de la classe : classe, nom, puis date.
  Future<List<Absence>> listerAnnee(int anneeId, {int? classeId}) async {
    final lignes = await _db.rawQuery(
      '''
      SELECT a.*, e.matricule AS matricule, c.nom AS classe_nom,
             UPPER(e.nom) || ' ' || e.prenom AS eleve_nom
      FROM absence a
      JOIN inscription i ON i.id = a.inscription_id
      JOIN eleve e ON e.id = i.eleve_id
      JOIN classe c ON c.id = i.classe_id
      WHERE c.annee_id = ?${classeId == null ? '' : ' AND c.id = ?'}
      ORDER BY c.nom COLLATE NOCASE, e.nom COLLATE NOCASE, e.prenom COLLATE NOCASE,
               a.date, a.id
      ''',
      [anneeId, if (classeId != null) classeId],
    );
    return [for (final l in lignes) _depuis(l)];
  }

  /// Totaux de chaque inscription d'une année (ou d'une classe) ayant au moins
  /// une absence ou un retard.
  Future<Map<int, TotauxAbsences>> totauxAnnee(int anneeId, {int? classeId}) async {
    final lignes = await _db.rawQuery(
      '''
      SELECT a.inscription_id AS ins,
             SUM(CASE WHEN a.type = 'absence' THEN 1 ELSE 0 END) AS absences,
             SUM(CASE WHEN a.type = 'absence' AND a.justifiee = 1 THEN 1 ELSE 0 END) AS abs_j,
             SUM(CASE WHEN a.type = 'retard' THEN 1 ELSE 0 END) AS retards,
             SUM(CASE WHEN a.type = 'retard' AND a.justifiee = 1 THEN 1 ELSE 0 END) AS ret_j,
             SUM(CASE WHEN a.type = 'retard' THEN COALESCE(a.duree_minutes, 0) ELSE 0 END) AS minutes
      FROM absence a
      JOIN inscription i ON i.id = a.inscription_id
      JOIN classe c ON c.id = i.classe_id
      WHERE c.annee_id = ?${classeId == null ? '' : ' AND c.id = ?'}
      GROUP BY a.inscription_id
      ''',
      [anneeId, if (classeId != null) classeId],
    );
    return {
      for (final l in lignes)
        l['ins'] as int: TotauxAbsences(
          absences: (l['absences'] as int?) ?? 0,
          absencesJustifiees: (l['abs_j'] as int?) ?? 0,
          retards: (l['retards'] as int?) ?? 0,
          retardsJustifies: (l['ret_j'] as int?) ?? 0,
          minutesRetard: (l['minutes'] as int?) ?? 0,
        ),
    };
  }

  /// Totaux d'une inscription.
  Future<TotauxAbsences> totaux(int inscriptionId) async =>
      TotauxAbsences.depuis(await lister(inscriptionId));
}
