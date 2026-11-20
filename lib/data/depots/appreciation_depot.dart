import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/permissions.dart';
import '../controle.dart';
import '../erreurs.dart';

/// Appréciation générale et décision du conseil d'un élève pour une période.
class AppreciationEleve {
  const AppreciationEleve({this.appreciation = '', this.decision = ''});

  final String appreciation;
  final String decision;

  bool get vide => appreciation.isEmpty && decision.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is AppreciationEleve &&
      other.appreciation == appreciation &&
      other.decision == decision;

  @override
  int get hashCode => Object.hash(appreciation, decision);
}

/// Appréciations des enseignants (par matière), appréciation générale et
/// décision du conseil de classe.
///
/// Elles sont rangées par **clé de période** : `m10` (octobre), `t1`, `s2`,
/// `q3` (séquence) ou `annee`, les mêmes clés que [Portee.cle]. Un texte vide
/// efface l'appréciation.
class AppreciationDepot {
  AppreciationDepot(this._db, {this.controle = Controle.aucun});

  final Database _db;
  final Controle controle;

  static const int longueurMaxMatiere = 200;
  static const int longueurMaxGenerale = 400;
  static const int longueurMaxDecision = 100;

  static final RegExp _cleValide = RegExp(r'^[a-z][a-z0-9]{0,19}$');

  /// Appréciation générale et décision de chaque élève de la classe
  /// (inscription -> valeurs) ; les élèves sans appréciation sont absents.
  Future<Map<int, AppreciationEleve>> eleves(int classeId, String periode) async {
    final lignes = await _db.rawQuery(
      '''
      SELECT a.inscription_id, a.appreciation, a.decision_conseil
      FROM appreciation_eleve a
      JOIN inscription i ON i.id = a.inscription_id
      WHERE i.classe_id = ? AND a.periode = ?
      ''',
      [classeId, periode],
    );
    return {
      for (final l in lignes)
        l['inscription_id'] as int: AppreciationEleve(
          appreciation: l['appreciation'] as String,
          decision: l['decision_conseil'] as String,
        ),
    };
  }

  /// Appréciations par matière de la classe : inscription -> matière -> texte.
  Future<Map<int, Map<int, String>>> matieres(int classeId, String periode) async {
    final lignes = await _db.rawQuery(
      '''
      SELECT a.inscription_id, a.matiere_id, a.texte
      FROM appreciation_matiere a
      JOIN inscription i ON i.id = a.inscription_id
      WHERE i.classe_id = ? AND a.periode = ?
      ''',
      [classeId, periode],
    );
    final resultat = <int, Map<int, String>>{};
    for (final l in lignes) {
      (resultat[l['inscription_id'] as int] ??= {})[l['matiere_id'] as int] =
          l['texte'] as String;
    }
    return resultat;
  }

  /// Enregistre l'appréciation générale et la décision de plusieurs élèves en
  /// une seule opération : tout est enregistré ou rien. Une valeur vide efface.
  Future<void> enregistrerEleves(
    Map<int, AppreciationEleve> valeurs,
    String periode,
  ) async {
    controle.exiger(Permission.appreciationsSaisir, 'saisir les appréciations');
    _verifierPeriode(periode);
    if (valeurs.isEmpty) return;
    final nettoyees = <int, AppreciationEleve>{};
    for (final e in valeurs.entries) {
      final a = e.value.appreciation.trim();
      final d = e.value.decision.trim();
      if (a.length > longueurMaxGenerale) {
        throw ErreurGesco(
          'L\'appréciation générale est trop longue '
          '($longueurMaxGenerale caractères au maximum).',
        );
      }
      if (d.length > longueurMaxDecision) {
        throw ErreurGesco(
          'La décision du conseil est trop longue '
          '($longueurMaxDecision caractères au maximum).',
        );
      }
      nettoyees[e.key] = AppreciationEleve(appreciation: a, decision: d);
    }
    await _db.transaction((txn) async {
      for (final e in nettoyees.entries) {
        await _verifierInscription(txn, e.key);
        if (e.value.vide) {
          await txn.delete(
            'appreciation_eleve',
            where: 'inscription_id = ? AND periode = ?',
            whereArgs: [e.key, periode],
          );
        } else {
          await txn.insert(
            'appreciation_eleve',
            {
              'inscription_id': e.key,
              'periode': periode,
              'appreciation': e.value.appreciation,
              'decision_conseil': e.value.decision,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
    await controle.noter(
      'modification',
      'appreciation',
      details: '${nettoyees.length} élève(s), période $periode',
    );
  }

  /// Appréciations par matière d'un élève (matière -> texte), en une seule
  /// opération. Un texte vide efface l'appréciation de la matière.
  Future<void> enregistrerMatieres(
    int inscriptionId,
    String periode,
    Map<int, String> textes,
  ) async {
    controle.exiger(Permission.appreciationsSaisir, 'saisir les appréciations');
    _verifierPeriode(periode);
    if (textes.isEmpty) return;
    final nettoyes = <int, String>{};
    for (final e in textes.entries) {
      final t = e.value.trim();
      if (t.length > longueurMaxMatiere) {
        throw ErreurGesco(
          'Une appréciation de matière est trop longue '
          '($longueurMaxMatiere caractères au maximum).',
        );
      }
      nettoyes[e.key] = t;
    }
    await _db.transaction((txn) async {
      final classeId = await _verifierInscription(txn, inscriptionId);
      for (final e in nettoyes.entries) {
        final m = await txn.query(
          'matiere_classe',
          columns: ['classe_id'],
          where: 'id = ?',
          whereArgs: [e.key],
        );
        if (m.isEmpty || m.first['classe_id'] != classeId) {
          throw const ErreurGesco('Cette matière n\'appartient pas à la classe de l\'élève.');
        }
        if (e.value.isEmpty) {
          await txn.delete(
            'appreciation_matiere',
            where: 'inscription_id = ? AND matiere_id = ? AND periode = ?',
            whereArgs: [inscriptionId, e.key, periode],
          );
        } else {
          await txn.insert(
            'appreciation_matiere',
            {
              'inscription_id': inscriptionId,
              'matiere_id': e.key,
              'periode': periode,
              'texte': e.value,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
    await controle.noter(
      'modification',
      'appreciation',
      id: inscriptionId,
      details: 'appréciations par matière, période $periode',
    );
  }

  void _verifierPeriode(String periode) {
    if (!_cleValide.hasMatch(periode)) {
      throw const ErreurGesco('Période inconnue pour les appréciations.');
    }
  }

  /// Vérifie que l'inscription existe et que son année n'est pas archivée ;
  /// retourne l'identifiant de sa classe.
  Future<int> _verifierInscription(DatabaseExecutor db, int inscriptionId) async {
    final l = await db.rawQuery(
      '''
      SELECT i.classe_id, a.archivee
      FROM inscription i JOIN annee_scolaire a ON a.id = i.annee_id
      WHERE i.id = ?
      ''',
      [inscriptionId],
    );
    if (l.isEmpty) throw const ErreurGesco('Élève introuvable.');
    if (l.first['archivee'] == 1) {
      throw const ErreurGesco(
        'Cette année scolaire est archivée : les appréciations ne peuvent '
        'plus être modifiées.',
      );
    }
    return l.first['classe_id'] as int;
  }
}
