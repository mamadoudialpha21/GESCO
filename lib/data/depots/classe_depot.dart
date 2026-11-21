import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/niveaux.dart';
import '../../domain/permissions.dart';
import '../controle.dart';
import '../erreurs.dart';
import '../modeles_donnees.dart';
import 'aides.dart';

/// Gestion des classes d'une année scolaire.
class ClasseDepot {
  ClasseDepot(this._db, {this.controle = Controle.aucun});

  final Database _db;
  final Controle controle;

  static Classe _depuis(Map<String, Object?> l) => Classe(
        id: l['id'] as int,
        anneeId: l['annee_id'] as int,
        niveau: (l['niveau'] as String?) ?? '',
        nom: l['nom'] as String,
        capacite: l['capacite'] as int?,
        profPrincipalId: l['prof_principal_id'] as int?,
        niveauCode: l['niveau_code'] as int?,
        serie: SerieLycee.depuisCode(l['serie'] as String?),
      );

  /// Classes d'une année avec leur nombre de matières et d'élèves.
  Future<List<ClasseResume>> lister(int anneeId) async {
    final lignes = await _db.rawQuery(
      '''
      SELECT c.id, c.annee_id, c.niveau, c.niveau_code, c.serie, c.nom, c.capacite,
        c.prof_principal_id,
        (SELECT TRIM(ens.nom || ' ' || ens.prenom) FROM enseignant ens
          WHERE ens.id = c.prof_principal_id) AS prof_nom,
        (SELECT COUNT(*) FROM matiere_classe m WHERE m.classe_id = c.id)
          AS nb_matieres,
        (SELECT COUNT(*) FROM inscription i WHERE i.classe_id = c.id)
          AS nb_eleves,
        (SELECT COUNT(*) FROM inscription i
          WHERE i.classe_id = c.id AND i.statut = 'inscrit') AS nb_actifs,
        (SELECT COUNT(*) FROM inscription i JOIN eleve e ON e.id = i.eleve_id
          WHERE i.classe_id = c.id AND i.statut = 'inscrit' AND e.sexe = 'F')
          AS nb_filles,
        (SELECT COUNT(*) FROM inscription i JOIN eleve e ON e.id = i.eleve_id
          WHERE i.classe_id = c.id AND i.statut = 'inscrit' AND e.sexe = 'M')
          AS nb_garcons
      FROM classe c
      WHERE c.annee_id = ?
      ORDER BY (c.niveau_code IS NULL), c.niveau_code, c.serie,
        c.niveau COLLATE NOCASE, c.nom COLLATE NOCASE
      ''',
      [anneeId],
    );
    return [
      for (final l in lignes)
        ClasseResume(
          classe: _depuis(l),
          nbMatieres: l['nb_matieres'] as int,
          nbEleves: l['nb_eleves'] as int,
          nbActifs: l['nb_actifs'] as int,
          nbFilles: l['nb_filles'] as int,
          nbGarcons: l['nb_garcons'] as int,
          profPrincipalNom: (l['prof_nom'] as String?) ?? '',
        ),
    ];
  }

  Future<Classe?> obtenir(int id) async {
    final lignes = await _db.query('classe', where: 'id = ?', whereArgs: [id]);
    return lignes.isEmpty ? null : _depuis(lignes.first);
  }

  /// Crée une classe. [niveauCode] la rattache au catalogue des niveaux
  /// (1re année à Terminale) : le texte de [niveau] est alors remplacé par le
  /// nom du niveau et la classe suit le calendrier de son cycle. [serie]
  /// (option du lycée) n'est possible que de la 11e année à la Terminale.
  Future<Classe> creer({
    required int anneeId,
    required String nom,
    String niveau = '',
    int? niveauCode,
    SerieLycee? serie,
    ReglagesClasse reglages = const ReglagesClasse(),
  }) async {
    controle.exiger(Permission.classesGerer, 'créer une classe');
    final nomValide = _nomValide(nom);
    final niveauValide = _texteDuNiveau(niveau, niveauCode, serie);
    _verifierCapacite(reglages.capacite);
    final classe = await _db.transaction<Classe>((txn) async {
      final annee = await compter(
        txn,
        'SELECT COUNT(*) FROM annee_scolaire WHERE id = ?',
        [anneeId],
      );
      if (annee == 0) throw const ErreurGesco('Année scolaire introuvable.');
      await _verifierNomLibre(txn, anneeId, nomValide);
      await _verifierEnseignant(txn, reglages.profPrincipalId);
      final id = await txn.insert('classe', {
        'annee_id': anneeId,
        'niveau': niveauValide,
        'niveau_code': niveauCode,
        'serie': serie?.code ?? '',
        'nom': nomValide,
        'capacite': reglages.capacite,
        'prof_principal_id': reglages.profPrincipalId,
      });
      return Classe(
        id: id,
        anneeId: anneeId,
        niveau: niveauValide,
        nom: nomValide,
        capacite: reglages.capacite,
        profPrincipalId: reglages.profPrincipalId,
        niveauCode: niveauCode,
        serie: serie,
      );
    });
    await controle.noter('creation', 'classe', id: classe.id, details: nomValide);
    return classe;
  }

  /// Modifie une classe. Comme à la création, [niveauCode] et [serie]
  /// remplacent ceux de la classe (null = classe hors catalogue / sans option).
  Future<void> modifier(
    int id, {
    required String nom,
    required String niveau,
    int? niveauCode,
    SerieLycee? serie,
    ReglagesClasse? reglages,
  }) async {
    controle.exiger(Permission.classesGerer, 'modifier une classe');
    final nomValide = _nomValide(nom);
    final niveauValide = _texteDuNiveau(niveau, niveauCode, serie);
    if (reglages != null) _verifierCapacite(reglages.capacite);
    await _db.transaction<void>((txn) async {
      final lignes = await txn.query(
        'classe',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (lignes.isEmpty) throw const ErreurGesco('Classe introuvable.');
      final anneeId = lignes.first['annee_id'] as int;
      await _verifierNomLibre(txn, anneeId, nomValide, sauf: id);
      if (reglages != null) {
        await _verifierEnseignant(txn, reglages.profPrincipalId);
        final capacite = reglages.capacite;
        if (capacite != null) {
          final actifs = await compter(
            txn,
            "SELECT COUNT(*) FROM inscription WHERE classe_id = ? AND statut = 'inscrit'",
            [id],
          );
          if (capacite < actifs) {
            throw ErreurGesco(
              'La capacité ($capacite) est inférieure à l\'effectif actuel '
              '($actifs). Changez d\'abord des élèves de classe.',
            );
          }
        }
      }
      await txn.update(
        'classe',
        {
          'nom': nomValide,
          'niveau': niveauValide,
          'niveau_code': niveauCode,
          'serie': serie?.code ?? '',
          if (reglages != null) 'capacite': reglages.capacite,
          if (reglages != null) 'prof_principal_id': reglages.profPrincipalId,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    await controle.noter('modification', 'classe', id: id, details: nomValide);
  }

  /// Supprime une classe et ses matières. Refusé si des élèves y sont
  /// inscrits (et donc si elle contient des notes).
  Future<void> supprimer(int id) async {
    controle.exiger(Permission.classesGerer, 'supprimer une classe');
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
    await controle.noter('suppression', 'classe', id: id, details: classe.nom);
  }

  static const int capaciteMax = 500;

  static void _verifierCapacite(int? capacite) {
    if (capacite == null) return;
    if (capacite < 1 || capacite > capaciteMax) {
      throw const ErreurGesco(
        'La capacité doit être comprise entre 1 et $capaciteMax élèves.',
      );
    }
  }

  static Future<void> _verifierEnseignant(DatabaseExecutor db, int? id) async {
    if (id == null) return;
    final ok = await compter(db, 'SELECT COUNT(*) FROM enseignant WHERE id = ?', [id]);
    if (ok == 0) throw const ErreurGesco('Enseignant introuvable.');
  }

  static String _nomValide(String nom) {
    final n = nom.trim();
    if (n.isEmpty) throw const ErreurGesco('Le nom de la classe est obligatoire.');
    if (n.length > 60) {
      throw const ErreurGesco('Le nom de la classe est trop long (60 caractères maximum).');
    }
    return n;
  }

  /// Vérifie le niveau du catalogue et l'option, et donne le texte du niveau
  /// à enregistrer.
  static String _texteDuNiveau(
    String niveau,
    int? niveauCode,
    SerieLycee? serie,
  ) {
    if (niveauCode == null) {
      if (serie != null) {
        throw const ErreurGesco(
          'Choisissez le niveau (11e année, 12e année ou Terminale) avant '
          'l\'option du lycée.',
        );
      }
      return _niveauValide(niveau);
    }
    final n = niveauDeCode(niveauCode);
    if (n == null) throw const ErreurGesco('Niveau inconnu.');
    if (serie != null && !n.aDesOptions) {
      throw ErreurGesco(
        'Une option (${serie.libelle}) n\'existe que pour le lycée : '
        '11e année, 12e année et Terminale. ${n.libelle} n\'en a pas.',
      );
    }
    return n.libelle;
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

/// Capacité et professeur principal d'une classe. Les valeurs nulles
/// signifient « non limitée » et « aucun ».
class ReglagesClasse {
  const ReglagesClasse({this.capacite, this.profPrincipalId});

  final int? capacite;
  final int? profPrincipalId;
}
