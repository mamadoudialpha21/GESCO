import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/modeles.dart';
import '../erreurs.dart';
import '../modeles_donnees.dart';
import 'aides.dart';

/// Gestion des années scolaires.
///
/// Chaque année possède ses propres classes, matières, coefficients, seuils,
/// inscriptions et notes. Créer une année ne supprime ni ne modifie jamais
/// les données des années précédentes.
class AnneeDepot {
  AnneeDepot(this._db, {DateTime Function()? maintenant})
      : _maintenant = maintenant ?? DateTime.now;

  final Database _db;
  final DateTime Function() _maintenant;

  static AnneeScolaire _depuis(Map<String, Object?> l) => AnneeScolaire(
        id: l['id'] as int,
        libelle: l['libelle'] as String,
        active: (l['active'] as int) == 1,
        creeLe: l['cree_le'] as String,
      );

  /// Toutes les années, la plus récente d'abord.
  Future<List<AnneeScolaire>> lister() async {
    final lignes = await _db.query('annee_scolaire', orderBy: 'libelle DESC');
    return [for (final l in lignes) _depuis(l)];
  }

  Future<AnneeScolaire?> obtenir(int id) async {
    final lignes = await _db.query(
      'annee_scolaire',
      where: 'id = ?',
      whereArgs: [id],
    );
    return lignes.isEmpty ? null : _depuis(lignes.first);
  }

  /// L'année active, ou null s'il n'existe encore aucune année.
  Future<AnneeScolaire?> active() async {
    final lignes = await _db.query('annee_scolaire', where: 'active = 1');
    return lignes.isEmpty ? null : _depuis(lignes.first);
  }

  /// Crée une année.
  ///
  /// - La toute première année créée devient automatiquement l'année active.
  /// - Si [copierDepuisAnneeId] est fourni, les classes, les matières, les
  ///   coefficients et les seuils de cette année sont recopiés (jamais les
  ///   élèves ni les notes).
  /// - Si [activer] est vrai, la nouvelle année devient l'année active.
  ///
  /// Tout ou rien : en cas d'erreur, rien n'est créé.
  Future<AnneeScolaire> creer(
    String libelle, {
    int? copierDepuisAnneeId,
    bool activer = false,
  }) async {
    final nom = libelle.trim();
    if (nom.isEmpty) {
      throw const ErreurGesco(
        'Le libellé de l\'année scolaire est obligatoire (ex. 2026-2027).',
      );
    }
    if (nom.length > 30) {
      throw const ErreurGesco(
        'Le libellé de l\'année scolaire est trop long (30 caractères maximum).',
      );
    }

    final id = await _db.transaction<int>((txn) async {
      final doublon = await compter(
        txn,
        'SELECT COUNT(*) FROM annee_scolaire WHERE libelle = ?',
        [nom],
      );
      if (doublon > 0) {
        throw ErreurGesco('L\'année scolaire « $nom » existe déjà.');
      }

      var config = ConfigResultats.defaut;
      if (copierDepuisAnneeId != null) {
        final existe = await compter(
          txn,
          'SELECT COUNT(*) FROM annee_scolaire WHERE id = ?',
          [copierDepuisAnneeId],
        );
        if (existe == 0) {
          throw const ErreurGesco('L\'année à copier est introuvable.');
        }
        final source = await txn.query(
          'config_resultats',
          where: 'annee_id = ?',
          whereArgs: [copierDepuisAnneeId],
        );
        if (source.isNotEmpty) {
          config = ConfigResultats.fromJsonString(
            source.first['json'] as String,
          );
        }
      }

      final premiere =
          await compter(txn, 'SELECT COUNT(*) FROM annee_scolaire') == 0;
      final nouvelle = await txn.insert('annee_scolaire', {
        'libelle': nom,
        'active': 0,
        'cree_le': _maintenant().toIso8601String(),
      });
      await txn.insert('config_resultats', {
        'annee_id': nouvelle,
        'json': config.toJsonString(),
      });
      if (copierDepuisAnneeId != null) {
        await _copierClasses(txn, copierDepuisAnneeId, nouvelle);
      }
      if (premiere || activer) {
        await _activer(txn, nouvelle);
      }
      return nouvelle;
    });

    return (await obtenir(id))!;
  }

  /// Rend [id] l'unique année active.
  Future<void> activer(int id) async {
    await _db.transaction<void>((txn) async {
      final existe = await compter(
        txn,
        'SELECT COUNT(*) FROM annee_scolaire WHERE id = ?',
        [id],
      );
      if (existe == 0) {
        throw const ErreurGesco('Année scolaire introuvable.');
      }
      await _activer(txn, id);
    });
  }

  /// Supprime une année vide. Refusé pour l'année active et pour toute année
  /// qui contient des classes (donc des élèves ou des notes possibles).
  Future<void> supprimer(int id) async {
    final annee = await obtenir(id);
    if (annee == null) {
      throw const ErreurGesco('Année scolaire introuvable.');
    }
    if (annee.active) {
      throw ErreurGesco(
        'Impossible de supprimer l\'année « ${annee.libelle} » : '
        'c\'est l\'année active. Activez d\'abord une autre année.',
      );
    }
    final classes = await compter(
      _db,
      'SELECT COUNT(*) FROM classe WHERE annee_id = ?',
      [id],
    );
    if (classes > 0) {
      throw ErreurGesco(
        'Impossible de supprimer l\'année « ${annee.libelle} » : elle contient '
        '${pluriel(classes, 'classe')}. Les anciens résultats sont conservés.',
      );
    }
    await _db.delete('annee_scolaire', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> _activer(DatabaseExecutor db, int id) async {
    // Deux instructions séparées : l'index unique n'autorise qu'une année
    // active, il faut donc désactiver l'ancienne avant d'activer la nouvelle.
    await db.update('annee_scolaire', {'active': 0}, where: 'active = 1');
    await db.update(
      'annee_scolaire',
      {'active': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> _copierClasses(
    DatabaseExecutor db,
    int source,
    int cible,
  ) async {
    final classes = await db.query(
      'classe',
      where: 'annee_id = ?',
      whereArgs: [source],
      orderBy: 'id',
    );
    for (final c in classes) {
      final nouvelleClasse = await db.insert('classe', {
        'annee_id': cible,
        'niveau': c['niveau'],
        'nom': c['nom'],
      });
      final matieres = await db.query(
        'matiere_classe',
        where: 'classe_id = ?',
        whereArgs: [c['id']],
        orderBy: 'ordre, id',
      );
      for (final m in matieres) {
        await db.insert('matiere_classe', {
          'classe_id': nouvelleClasse,
          'nom': m['nom'],
          'coefficient': m['coefficient'],
          'ordre': m['ordre'],
        });
      }
    }
  }
}
