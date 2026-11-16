import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../erreurs.dart';
import '../modeles_donnees.dart';
import 'aides.dart';

/// Gestion des classes d'une année scolaire.
class ClasseDepot {
  ClasseDepot(this._db);

  final Database _db;

  static Classe _depuis(Map<String, Object?> l) => Classe(
        id: l['id'] as int,
        anneeId: l['annee_id'] as int,
        niveau: (l['niveau'] as String?) ?? '',
        nom: l['nom'] as String,
      );

  /// Classes d'une année avec leur nombre de matières et d'élèves.
  Future<List<ClasseResume>> lister(int anneeId) async {
    final lignes = await _db.rawQuery(
      '''
      SELECT c.id, c.annee_id, c.niveau, c.nom,
        (SELECT COUNT(*) FROM matiere_classe m WHERE m.classe_id = c.id)
          AS nb_matieres,
        (SELECT COUNT(*) FROM inscription i WHERE i.classe_id = c.id)
          AS nb_eleves
      FROM classe c
      WHERE c.annee_id = ?
      ORDER BY c.niveau COLLATE NOCASE, c.nom COLLATE NOCASE
      ''',
      [anneeId],
    );
    return [
      for (final l in lignes)
        ClasseResume(
          classe: _depuis(l),
          nbMatieres: l['nb_matieres'] as int,
          nbEleves: l['nb_eleves'] as int,
        ),
    ];
  }

  Future<Classe?> obtenir(int id) async {
    final lignes = await _db.query('classe', where: 'id = ?', whereArgs: [id]);
    return lignes.isEmpty ? null : _depuis(lignes.first);
  }

  Future<Classe> creer({
    required int anneeId,
    required String nom,
    String niveau = '',
  }) async {
    final nomValide = _nomValide(nom);
    final niveauValide = _niveauValide(niveau);
    return _db.transaction<Classe>((txn) async {
      final annee = await compter(
        txn,
        'SELECT COUNT(*) FROM annee_scolaire WHERE id = ?',
        [anneeId],
      );
      if (annee == 0) throw const ErreurGesco('Année scolaire introuvable.');
      await _verifierNomLibre(txn, anneeId, nomValide);
      final id = await txn.insert('classe', {
        'annee_id': anneeId,
        'niveau': niveauValide,
        'nom': nomValide,
      });
      return Classe(
        id: id,
        anneeId: anneeId,
        niveau: niveauValide,
        nom: nomValide,
      );
    });
  }

  Future<void> modifier(
    int id, {
    required String nom,
    required String niveau,
  }) async {
    final nomValide = _nomValide(nom);
    final niveauValide = _niveauValide(niveau);
    await _db.transaction<void>((txn) async {
      final lignes = await txn.query(
        'classe',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (lignes.isEmpty) throw const ErreurGesco('Classe introuvable.');
      final anneeId = lignes.first['annee_id'] as int;
      await _verifierNomLibre(txn, anneeId, nomValide, sauf: id);
      await txn.update(
        'classe',
        {'nom': nomValide, 'niveau': niveauValide},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Supprime une classe et ses matières. Refusé si des élèves y sont
  /// inscrits (et donc si elle contient des notes).
  Future<void> supprimer(int id) async {
    final classe = await obtenir(id);
    if (classe == null) throw const ErreurGesco('Classe introuvable.');
    final eleves = await compter(
      _db,
      'SELECT COUNT(*) FROM inscription WHERE classe_id = ?',
      [id],
    );
    if (eleves > 0) {
      throw ErreurGesco(
        'Impossible de supprimer la classe « ${classe.nom} » : '
        '${pluriel(eleves, 'élève')} y '
        '${eleves > 1 ? 'sont inscrits' : 'est inscrit'}.',
      );
    }
    await _db.delete('classe', where: 'id = ?', whereArgs: [id]);
  }

  static String _nomValide(String nom) {
    final n = nom.trim();
    if (n.isEmpty) throw const ErreurGesco('Le nom de la classe est obligatoire.');
    if (n.length > 60) {
      throw const ErreurGesco('Le nom de la classe est trop long (60 caractères maximum).');
    }
    return n;
  }

  static String _niveauValide(String niveau) {
    final n = niveau.trim();
    if (n.length > 60) {
      throw const ErreurGesco('Le niveau est trop long (60 caractères maximum).');
    }
    return n;
  }

  static Future<void> _verifierNomLibre(
    DatabaseExecutor db,
    int anneeId,
    String nom, {
    int? sauf,
  }) async {
    // Comparaison faite en Dart : la fonction lower() de SQLite ne gère pas
    // les lettres accentuées (« É » resterait différent de « é »).
    final existantes = await db.query(
      'classe',
      columns: ['id', 'nom'],
      where: 'annee_id = ?',
      whereArgs: [anneeId],
    );
    final cible = nom.toLowerCase();
    for (final l in existantes) {
      if (l['id'] != sauf && (l['nom'] as String).toLowerCase() == cible) {
        throw ErreurGesco('Une classe « $nom » existe déjà pour cette année.');
      }
    }
  }
}
