import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../modeles_securite.dart';
import 'aides.dart';

/// Journal des opérations (qui a fait quoi et quand), journal des connexions
/// et historique des notes.
class JournalDepot {
  JournalDepot(this._db, {DateTime Function()? maintenant})
      : _maintenant = maintenant ?? DateTime.now;

  final Database _db;
  final DateTime Function() _maintenant;

  /// Ajoute une ligne au journal, signée par l'utilisateur connecté.
  Future<void> enregistrer({
    required String action,
    String entite = '',
    int? entiteId,
    String details = '',
  }) async {
    final contexte = await _db.query('contexte', where: 'id = 1');
    final utilisateurId = contexte.isEmpty ? null : contexte.first['utilisateur_id'] as int?;
    final nom = contexte.isEmpty ? '' : contexte.first['utilisateur_nom'] as String;
    await _db.insert('journal', {
      'date_heure': horodatage(_maintenant()),
      'utilisateur_id': utilisateurId,
      'utilisateur_nom': nom,
      'action': action,
      'entite': entite,
      'entite_id': entiteId,
      'details': details,
    });
  }

  // ----------------------------------------------------------- Opérations

  ({String clause, List<Object?> args}) _filtre({
    String? recherche,
    String? entite,
    String? action,
    String? depuis,
    String? jusqua,
  }) {
    final c = <String>[];
    final a = <Object?>[];
    if (recherche != null && recherche.trim().isNotEmpty) {
      c.add('(utilisateur_nom LIKE ? OR details LIKE ? OR entite LIKE ? OR action LIKE ?)');
      final m = '%${recherche.trim()}%';
      a.addAll([m, m, m, m]);
    }
    if (entite != null && entite.isNotEmpty) {
      c.add('entite = ?');
      a.add(entite);
    }
    if (action != null && action.isNotEmpty) {
      c.add('action = ?');
      a.add(action);
    }
    if (depuis != null) {
      c.add('date_heure >= ?');
      a.add(depuis);
    }
    if (jusqua != null) {
      c.add('date_heure <= ?');
      a.add(jusqua);
    }
    return (clause: c.isEmpty ? '' : 'WHERE ${c.join(' AND ')}', args: a);
  }

  Future<List<EntreeJournal>> lister({
    int limite = 100,
    int decalage = 0,
    String? recherche,
    String? entite,
    String? action,
    String? depuis,
    String? jusqua,
  }) async {
    final f = _filtre(
      recherche: recherche,
      entite: entite,
      action: action,
      depuis: depuis,
      jusqua: jusqua,
    );
    final l = await _db.rawQuery(
      'SELECT * FROM journal ${f.clause} ORDER BY date_heure DESC, id DESC LIMIT ? OFFSET ?',
      [...f.args, limite, decalage],
    );
    return [
      for (final r in l)
        EntreeJournal(
          id: r['id'] as int,
          dateHeure: r['date_heure'] as String,
          utilisateurNom: r['utilisateur_nom'] as String,
          action: r['action'] as String,
          entite: r['entite'] as String,
          entiteId: r['entite_id'] as int?,
          details: r['details'] as String,
        ),
    ];
  }

  Future<int> compter({
    String? recherche,
    String? entite,
    String? action,
    String? depuis,
    String? jusqua,
  }) async {
    final f = _filtre(
      recherche: recherche,
      entite: entite,
      action: action,
      depuis: depuis,
      jusqua: jusqua,
    );
    final l = await _db.rawQuery('SELECT COUNT(*) AS n FROM journal ${f.clause}', f.args);
    return l.first['n'] as int;
  }

  /// Dernières opérations (tableau de bord).
  Future<List<EntreeJournal>> recentes([int n = 8]) => lister(limite: n);

  // ------------------------------------------------------------ Connexions

  Future<List<EntreeConnexion>> listerConnexions({
    int limite = 100,
    int decalage = 0,
    String? recherche,
  }) async {
    final cherche = recherche != null && recherche.trim().isNotEmpty;
    final l = await _db.rawQuery(
      'SELECT * FROM journal_connexion '
      '${cherche ? 'WHERE identifiant LIKE ? OR evenement LIKE ? OR detail LIKE ?' : ''} '
      'ORDER BY date_heure DESC, id DESC LIMIT ? OFFSET ?',
      [
        if (cherche) ...['%${recherche.trim()}%', '%${recherche.trim()}%', '%${recherche.trim()}%'],
        limite,
        decalage,
      ],
    );
    return [
      for (final r in l)
        EntreeConnexion(
          id: r['id'] as int,
          dateHeure: r['date_heure'] as String,
          identifiant: r['identifiant'] as String,
          evenement: r['evenement'] as String,
          detail: r['detail'] as String,
        ),
    ];
  }

  Future<int> compterConnexions({String? recherche}) async {
    final cherche = recherche != null && recherche.trim().isNotEmpty;
    final m = '%${recherche?.trim()}%';
    final l = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM journal_connexion '
      '${cherche ? 'WHERE identifiant LIKE ? OR evenement LIKE ? OR detail LIKE ?' : ''}',
      [if (cherche) ...[m, m, m]],
    );
    return l.first['n'] as int;
  }

  // ----------------------------------------------------- Historique des notes

  Future<List<EntreeHistoriqueNote>> historiqueNotes({
    int limite = 100,
    int decalage = 0,
    int? inscriptionId,
    String? recherche,
  }) async {
    final c = <String>[];
    final a = <Object?>[];
    if (inscriptionId != null) {
      c.add('inscription_id = ?');
      a.add(inscriptionId);
    }
    if (recherche != null && recherche.trim().isNotEmpty) {
      c.add('(eleve_nom LIKE ? OR matiere_nom LIKE ? OR classe_nom LIKE ? OR utilisateur_nom LIKE ?)');
      final m = '%${recherche.trim()}%';
      a.addAll([m, m, m, m]);
    }
    final l = await _db.rawQuery(
      'SELECT * FROM historique_note ${c.isEmpty ? '' : 'WHERE ${c.join(' AND ')}'} '
      'ORDER BY date_heure DESC, id DESC LIMIT ? OFFSET ?',
      [...a, limite, decalage],
    );
    return [
      for (final r in l)
        EntreeHistoriqueNote(
          id: r['id'] as int,
          dateHeure: r['date_heure'] as String,
          utilisateurNom: r['utilisateur_nom'] as String,
          source: r['source'] as String,
          operation: r['operation'] as String,
          eleveNom: (r['eleve_nom'] as String?) ?? '',
          matiereNom: (r['matiere_nom'] as String?) ?? '',
          classeNom: (r['classe_nom'] as String?) ?? '',
          mois: r['mois'] as int?,
          evaluationId: r['evaluation_id'] as int?,
          bareme: (r['bareme'] as int?) ?? 20,
          ancienEtat: r['ancien_etat'] as String?,
          ancienneValeur: r['ancienne_valeur'] as int?,
          nouvelEtat: r['nouvel_etat'] as String?,
          nouvelleValeur: r['nouvelle_valeur'] as int?,
        ),
    ];
  }

  Future<int> compterHistoriqueNotes({int? inscriptionId, String? recherche}) async {
    final c = <String>[];
    final a = <Object?>[];
    if (inscriptionId != null) {
      c.add('inscription_id = ?');
      a.add(inscriptionId);
    }
    if (recherche != null && recherche.trim().isNotEmpty) {
      c.add('(eleve_nom LIKE ? OR matiere_nom LIKE ? OR classe_nom LIKE ? OR utilisateur_nom LIKE ?)');
      final m = '%${recherche.trim()}%';
      a.addAll([m, m, m, m]);
    }
    final l = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM historique_note'
      '${c.isEmpty ? '' : ' WHERE ${c.join(' AND ')}'}',
      a,
    );
    return l.first['n'] as int;
  }
}
