import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'schema.dart';
import 'schema_v2.dart';
import 'schema_v3.dart';
import 'schema_v4.dart';

/// Accès à la base SQLite locale de GESCO.
///
/// Tout est stocké dans un seul fichier sur le disque de l'appareil :
/// aucun serveur, aucune connexion Internet.
class GescoDatabase {
  GescoDatabase._(this.db);

  final Database db;

  /// Version courante du schéma. À incrémenter à chaque changement, avec
  /// l'ajout de la migration correspondante dans [migrations].
  static const int versionSchema = 4;

  /// Début du nom des copies faites avant une mise à jour de la base.
  static const String prefixeAvantMiseAJour = 'avant-mise-a-jour_';

  /// Migrations : version cible -> étapes à appliquer pour l'atteindre.
  /// Une base neuve est créée en version 1 puis passe par les mêmes
  /// migrations qu'une base existante : les deux ont donc le même schéma.
  static final Map<int, Future<void> Function(Database)> migrations = {
    2: (db) => _executerTout(db, migrationV2),
    3: (db) async {
      await _executerTout(db, migrationV3);
      await rattraperNiveaux(db);
    },
    4: (db) => _executerTout(db, migrationV4),
  };

  static Future<void> _executerTout(Database db, List<String> instructions) async {
    for (final instruction in instructions) {
      await db.execute(instruction);
    }
  }

  /// Ouvre (ou crée) la base. [fabrique] est injectée pour pouvoir utiliser
  /// SQLite FFI sur ordinateur, sqflite sur mobile, ou une base en mémoire
  /// dans les tests.
  static Future<GescoDatabase> ouvrir({
    required DatabaseFactory fabrique,
    required String chemin,
  }) async {
    if (chemin != inMemoryDatabasePath) {
      await _copierAvantMigration(fabrique, chemin);
    }
    final db = await fabrique.openDatabase(
      chemin,
      options: OpenDatabaseOptions(
        version: versionSchema,
        singleInstance: chemin != inMemoryDatabasePath,
        onConfigure: _configurer,
        onCreate: _creer,
        onUpgrade: _migrer,
      ),
    );
    return GescoDatabase._(db);
  }

  /// Avant d'ouvrir une base d'une version plus ancienne (donc de la mettre à
  /// jour), copie le fichier tel quel dans le dossier `sauvegardes` : si la
  /// mise à jour se passait mal, les données d'avant restent intactes.
  /// Retourne le chemin de la copie, ou null s'il n'y avait rien à copier.
  static Future<String?> _copierAvantMigration(
    DatabaseFactory fabrique,
    String chemin,
  ) async {
    try {
      final fichier = File(chemin);
      if (!await fichier.exists() || await fichier.length() == 0) return null;
      final lecture = await fabrique.openDatabase(
        chemin,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final int version;
      try {
        version = await lecture.getVersion();
      } finally {
        await lecture.close();
      }
      if (version <= 0 || version >= versionSchema) return null;
      final dossier = Directory(p.join(p.dirname(chemin), 'sauvegardes'));
      await dossier.create(recursive: true);
      String d2(int n) => n.toString().padLeft(2, '0');
      final d = DateTime.now();
      final nom = '${prefixeAvantMiseAJour}v$version-vers-v$versionSchema'
          '_${d.year}-${d2(d.month)}-${d2(d.day)}_${d2(d.hour)}${d2(d.minute)}${d2(d.second)}.db';
      final copie = File(p.join(dossier.path, nom));
      await fichier.copy(copie.path);
      return copie.path;
    } on Object {
      // La copie de précaution ne doit jamais empêcher d'ouvrir la base.
      return null;
    }
  }

  static Future<void> _configurer(Database db) async {
    // Les clés étrangères sont désactivées par défaut dans SQLite.
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _creer(Database db, int version) async {
    final batch = db.batch();
    for (final instruction in schemaV1) {
      batch.execute(instruction);
    }
    batch.insert('etablissement', {'id': 1});
    await batch.commit(noResult: true);
    for (var v = 2; v <= version; v++) {
      await migrations[v]!(db);
    }
  }

  static Future<void> _migrer(Database db, int ancienne, int nouvelle) async {
    for (var v = ancienne + 1; v <= nouvelle; v++) {
      final migration = migrations[v];
      if (migration == null) {
        throw StateError('Migration vers la version $v introuvable.');
      }
      await migration(db);
    }
  }

  /// Version du schéma stockée dans le fichier.
  Future<int> version() => db.getVersion();

  /// Vérifie l'intégrité du fichier et des clés étrangères.
  /// Retourne la liste des problèmes (vide si tout est correct).
  Future<List<String>> verifierIntegrite() async {
    final problemes = <String>[];

    final integrite = await db.rawQuery('PRAGMA integrity_check');
    for (final ligne in integrite) {
      final texte = ligne.values.first?.toString() ?? '';
      if (texte != 'ok') {
        problemes.add('Intégrité : $texte');
      }
    }

    final cles = await db.rawQuery('PRAGMA foreign_key_check');
    for (final ligne in cles) {
      problemes.add(
        'Clé étrangère invalide : table ${ligne['table']}, ligne ${ligne['rowid']}',
      );
    }

    return problemes;
  }

  Future<void> fermer() => db.close();
}
