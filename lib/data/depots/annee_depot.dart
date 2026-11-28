import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/modeles.dart';
import '../../domain/permissions.dart';
import '../controle.dart';
import '../erreurs.dart';
import '../modeles_donnees.dart';
import 'aides.dart';
import 'programme_depot.dart';

/// Gestion des années scolaires.
///
/// Chaque année possède ses propres classes, matières, coefficients, seuils,
/// inscriptions et notes. Créer une année ne supprime ni ne modifie jamais
/// les données des années précédentes.
class AnneeDepot {
  AnneeDepot(
    this._db, {
    DateTime Function()? maintenant,
    this.controle = Controle.aucun,
  }) : _maintenant = maintenant ?? DateTime.now;

  final Database _db;
  final DateTime Function() _maintenant;
  final Controle controle;

  static AnneeScolaire _depuis(Map<String, Object?> l) => AnneeScolaire(
        id: l['id'] as int,
        libelle: l['libelle'] as String,
        active: (l['active'] as int) == 1,
        creeLe: l['cree_le'] as String,
        archivee: ((l['archivee'] as int?) ?? 0) == 1,
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
  ///   coefficients, les seuils et le calendrier de cette année sont recopiés (jamais les
  ///   élèves ni les notes).
  /// - Si [activer] est vrai, la nouvelle année devient l'année active.
  ///
  /// Tout ou rien : en cas d'erreur, rien n'est créé.
  Future<AnneeScolaire> creer(
    String libelle, {
    int? copierDepuisAnneeId,
    bool activer = false,
  }) async {
    controle.exiger(Permission.anneesGerer, 'créer une année scolaire');
    final nom = _libelleValide(libelle);

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
        await ProgrammeDepot.copierProgramme(txn, copierDepuisAnneeId, nouvelle);
        final calendrier = await txn.query(
          'config_calendrier',
          where: 'annee_id = ?',
          whereArgs: [copierDepuisAnneeId],
        );
        if (calendrier.isNotEmpty) {
          await txn.insert('config_calendrier', {
            'annee_id': nouvelle,
            'json': calendrier.first['json'],
          });
        }
        final parCycle = await txn.query(
          'config_calendrier_cycle',
          where: 'annee_id = ?',
          whereArgs: [copierDepuisAnneeId],
        );
        for (final ligne in parCycle) {
          await txn.insert('config_calendrier_cycle', {
            'annee_id': nouvelle,
            'cycle': ligne['cycle'],
            'json': ligne['json'],
          });
        }
      }
      if (premiere || activer) {
        await _activer(txn, nouvelle);
      }
      return nouvelle;
    });

    await controle.noter('creation', 'annee', id: id, details: nom);
    return (await obtenir(id))!;
  }

  static String _libelleValide(String libelle) {
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
    return nom;
  }

  /// Change le libellé d'une année (les classes, élèves et notes ne bougent pas).
  Future<void> renommer(int id, String libelle) async {
    controle.exiger(Permission.anneesGerer, 'modifier une année scolaire');
    final nom = _libelleValide(libelle);
    final annee = await obtenir(id);
    if (annee == null) throw const ErreurGesco('Année scolaire introuvable.');
    if (annee.libelle == nom) return;
    final doublon = await compter(
      _db,
      'SELECT COUNT(*) FROM annee_scolaire WHERE libelle = ? AND id <> ?',
      [nom, id],
    );
    if (doublon > 0) throw ErreurGesco('L\'année scolaire « $nom » existe déjà.');
    await _db.update(
      'annee_scolaire',
      {'libelle': nom},
      where: 'id = ?',
      whereArgs: [id],
    );
    await controle.noter(
      'modification',
      'annee',
      id: id,
      details: '${annee.libelle} → $nom',
    );
  }

  /// Archive une année terminée : plus aucune note ni évaluation n'y est
  /// modifiable, mais tout reste consultable. Refusé pour l'année active.
  /// Avec [archivee] faux, l'année est de nouveau modifiable.
  Future<void> archiver(int id, {bool archivee = true}) async {
    controle.exiger(
      Permission.anneesGerer,
      archivee ? 'archiver une année scolaire' : 'rouvrir une année scolaire',
    );
    final annee = await obtenir(id);
    if (annee == null) throw const ErreurGesco('Année scolaire introuvable.');
    if (archivee && annee.active) {
      throw ErreurGesco(
        'Impossible d\'archiver l\'année « ${annee.libelle} » : c\'est l\'année '
        'active. Activez d\'abord une autre année.',
      );
    }
    if (annee.archivee == archivee) return;
    await _db.update(
      'annee_scolaire',
      {'archivee': archivee ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    await controle.noter(
      archivee ? 'archivage' : 'reouverture',
      'annee',
      id: id,
      details: annee.libelle,
    );
  }

  /// Chiffres d'une année : classes, élèves, répartition filles / garçons,
  /// départs et abandons.
  Future<EffectifsAnnee> effectifs(int anneeId) async {
    final classes = await compter(
      _db,
      'SELECT COUNT(*) FROM classe WHERE annee_id = ?',
      [anneeId],
    );
    final lignes = await _db.rawQuery(
      '''
      SELECT COUNT(*) AS total,
        COALESCE(SUM(CASE WHEN e.sexe = 'F' THEN 1 ELSE 0 END), 0) AS filles,
        COALESCE(SUM(CASE WHEN e.sexe = 'M' THEN 1 ELSE 0 END), 0) AS garcons,
        COALESCE(SUM(CASE WHEN i.statut = 'depart' THEN 1 ELSE 0 END), 0) AS departs,
        COALESCE(SUM(CASE WHEN i.statut = 'abandon' THEN 1 ELSE 0 END), 0) AS abandons
      FROM inscription i JOIN eleve e ON e.id = i.eleve_id
      WHERE i.annee_id = ?
      ''',
      [anneeId],
    );
    final l = lignes.first;
    return EffectifsAnnee(
      anneeId: anneeId,
      classes: classes,
      eleves: l['total'] as int,
      filles: l['filles'] as int,
      garcons: l['garcons'] as int,
      departs: l['departs'] as int,
      abandons: l['abandons'] as int,
    );
  }

  /// Rend [id] l'unique année active.
  Future<void> activer(int id) async {
    controle.exiger(Permission.anneesGerer, 'changer l\'année active');
    await _db.transaction<void>((txn) async {
      final existe = await compter(
        txn,
        'SELECT COUNT(*) FROM annee_scolaire WHERE id = ?',
        [id],
      );
      if (existe == 0) {
        throw const ErreurGesco('Année scolaire introuvable.');
      }
      final archivee = await compter(
        txn,
        'SELECT COUNT(*) FROM annee_scolaire WHERE id = ? AND archivee = 1',
        [id],
      );
      if (archivee > 0) {
        throw const ErreurGesco(
          'Cette année est archivée : rouvrez-la avant de l\'activer.',
        );
      }
      await _activer(txn, id);
    });
    await controle.noter('activation', 'annee', id: id);
  }

  /// Supprime une année vide. Refusé pour l'année active et pour toute année
  /// qui contient des classes (donc des élèves ou des notes possibles).
  Future<void> supprimer(int id) async {
    controle.exiger(Permission.anneesGerer, 'supprimer une année scolaire');
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
    await controle.noter('suppression', 'annee', id: id, details: annee.libelle);
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
        'niveau_code': c['niveau_code'],
        'serie': c['serie'],
        'nom': c['nom'],
        'capacite': c['capacite'],
        'prof_principal_id': c['prof_principal_id'],
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
          'bareme': m['bareme'],
          'facultative': m['facultative'],
          'enseignant_id': m['enseignant_id'],
        });
      }
    }
  }
}

/// Chiffres d'une année scolaire (voir [AnneeDepot.effectifs]).
class EffectifsAnnee {
  const EffectifsAnnee({
    required this.anneeId,
    required this.classes,
    required this.eleves,
    required this.filles,
    required this.garcons,
    required this.departs,
    required this.abandons,
  });

  final int anneeId;
  final int classes;

  /// Élèves inscrits dans l'année, y compris partis et abandons.
  final int eleves;
  final int filles;
  final int garcons;
  final int departs;
  final int abandons;

  /// Élèves qui ont suivi l'année jusqu'au bout.
  int get actifs => eleves - departs - abandons;
}
