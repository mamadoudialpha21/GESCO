import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/depots/calendrier_depot.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/schema.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/niveaux.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Migration de la version 4 vers la version 5 : maternelle, programmes par
/// cycle et nouvelles méthodes de calcul.
void main() {
  sqfliteFfiInit();

  late Directory dossier;
  late String chemin;
  late int anneeActive;
  late int anneeArchivee;
  late Calendrier personnalise;

  /// Crée une base à la version 4 (l'état de l'application avant ce lot).
  Future<void> creerBaseV4() async {
    final v4 = await databaseFactoryFfi.openDatabase(
      chemin,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          for (final instruction in schemaV1) {
            await db.execute(instruction);
          }
          await db.insert('etablissement', {'id': 1});
          for (var v = 2; v <= 4; v++) {
            await GescoDatabase.migrations[v]!(db);
          }
        },
      ),
    );
    anneeArchivee = await v4.insert('annee_scolaire',
        {'libelle': '2025-2026', 'active': 0, 'cree_le': '2025-10-01', 'archivee': 1});
    anneeActive = await v4.insert(
        'annee_scolaire', {'libelle': '2026-2027', 'active': 1, 'cree_le': '2026-10-01'});

    // Calendrier modifié par l'utilisateur : il doit rester tel quel.
    personnalise = Calendrier(
      type: TypePeriodes.personnalise,
      periodes: const [
        PeriodeScolaire(cle: 'p1', libelle: 'Premier bloc', mois: [10, 11, 12]),
        PeriodeScolaire(cle: 'p2', libelle: 'Second bloc', mois: [1, 2, 3, 4, 5, 6]),
      ],
    );
    for (final (annee, cycle, calendrier) in [
      (anneeActive, 'primaire', Calendrier.trimestres),
      (anneeActive, 'college', Calendrier.deuxTrimestres),
      (anneeActive, 'lycee', personnalise),
      (anneeArchivee, 'college', Calendrier.deuxTrimestres),
    ]) {
      await v4.insert('config_calendrier_cycle',
          {'annee_id': annee, 'cycle': cycle, 'json': calendrier.toJsonString()});
    }

    final c10 = await v4.insert('classe', {
      'annee_id': anneeActive,
      'niveau': '10e année',
      'niveau_code': 10,
      'nom': '10e A',
    });
    await v4.insert('classe', {
      'annee_id': anneeActive,
      'niveau': 'Terminale',
      'niveau_code': 13,
      'serie': 'SM',
      'nom': 'Tle SM',
    });
    await v4.insert('classe', {'annee_id': anneeActive, 'niveau': 'Libre', 'nom': 'Sans niveau'});
    await v4.insert('matiere_classe', {
      'classe_id': c10,
      'nom': 'Mathématiques',
      'coefficient': 300,
      'ordre': 0,
    });
    await v4.close();
  }

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('gesco_migration5_');
    chemin = p.join(dossier.path, 'gesco.db');
    await creerBaseV4();
  });

  tearDown(() async {
    if (dossier.existsSync()) await dossier.delete(recursive: true);
  });

  test('la base passe en version 5, intacte', () async {
    final gdb = await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
    expect(await gdb.version(), 5);
    expect(await gdb.verifierIntegrite(), isEmpty);
    await gdb.fermer();
  });

  test('les classes et leurs matières sont conservées (aucune suppression en cascade)',
      () async {
    final gdb = await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
    final classes = await gdb.db.query('classe', orderBy: 'id');
    expect([for (final c in classes) c['nom']], ['10e A', 'Tle SM', 'Sans niveau']);
    expect([for (final c in classes) c['niveau_code']], [10, 13, null]);
    expect([for (final c in classes) c['serie']], ['', 'SM', '']);
    expect([for (final c in classes) c['niveau']], ['10e année', 'Terminale', 'Libre']);
    final matieres = await gdb.db.query('matiere_classe');
    expect(matieres.single['nom'], 'Mathématiques');
    expect(matieres.single['coefficient'], 300);
    await gdb.fermer();
  });

  test('les niveaux 14 à 16 (maternelle) sont acceptés, 17 et 0 refusés', () async {
    final gdb = await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
    for (final code in [14, 15, 16]) {
      await gdb.db.insert('classe', {'annee_id': anneeActive, 'nom': 'M$code', 'niveau_code': code});
    }
    for (final code in [0, 17, 100]) {
      await expectLater(
        gdb.db.insert('classe', {'annee_id': anneeActive, 'nom': 'X$code', 'niveau_code': code}),
        throwsA(isA<DatabaseException>()),
        reason: 'niveau $code',
      );
    }
    final lignes = await gdb.db.query('classe', where: 'niveau_code >= 14');
    expect(lignes.length, 3);
    await gdb.fermer();
  });

  test('les index de la table des classes existent toujours', () async {
    final gdb = await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
    final index = await gdb.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name IN ('classe', 'programme_matiere')");
    final noms = {for (final i in index) i['name']};
    expect(noms, containsAll(['idx_classe_niveau', 'idx_programme_annee']));
    await gdb.fermer();
  });

  test('calendriers : ceux d\'origine d\'une année non archivée passent à la méthode du cycle; '
      'les calendriers modifiés et ceux des années archivées restent', () async {
    final gdb = await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
    final calendriers = CalendrierDepot(gdb.db);
    // Année active : primaire et collège n'avaient jamais été modifiés.
    expect(await calendriers.lire(anneeActive, cycle: Cycle.primaire), Calendrier.compositions);
    expect(await calendriers.lire(anneeActive, cycle: Cycle.college), Calendrier.semestresCompo);
    // Lycée modifié par l'utilisateur : conservé.
    expect(await calendriers.lire(anneeActive, cycle: Cycle.lycee), personnalise);
    // Maternelle : n'existait pas, méthode des compositions.
    expect(await calendriers.lire(anneeActive, cycle: Cycle.maternelle), Calendrier.compositions);
    // Année archivée : ses résultats gardent leur méthode d'origine.
    expect(await calendriers.lire(anneeArchivee, cycle: Cycle.college), Calendrier.deuxTrimestres);
    final restantes = await gdb.db.query('config_calendrier_cycle');
    expect(restantes.length, 2, reason: 'lycée modifié + collège de l\'année archivée');
    await gdb.fermer();
  });

  test('la table des calendriers accepte désormais la maternelle', () async {
    final gdb = await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
    await CalendrierDepot(gdb.db)
        .enregistrer(anneeActive, Calendrier.trimestres, cycle: Cycle.maternelle);
    expect(await CalendrierDepot(gdb.db).lire(anneeActive, cycle: Cycle.maternelle),
        Calendrier.trimestres);
    await expectLater(
      gdb.db.insert('config_calendrier_cycle',
          {'annee_id': anneeActive, 'cycle': 'crèche', 'json': '{}'}),
      throwsA(isA<DatabaseException>()),
    );
    await gdb.fermer();
  });

  group('table des programmes', () {
    late GescoDatabase gdb;

    Map<String, Object?> ligne({
      String cycle = 'primaire',
      String serie = '',
      String nom = 'Lecture',
      int coefficient = 200,
      int bareme = 20,
      int? annee,
    }) =>
        {
          'annee_id': annee ?? anneeActive,
          'cycle': cycle,
          'serie': serie,
          'nom': nom,
          'coefficient': coefficient,
          'bareme': bareme,
        };

    setUp(() async {
      gdb = await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
    });

    tearDown(() async => gdb.fermer());

    test('accepte chaque cycle, et les trois options au lycée', () async {
      for (final cycle in ['maternelle', 'primaire', 'college']) {
        await gdb.db.insert('programme_matiere', ligne(cycle: cycle));
      }
      for (final serie in ['SS', 'SE', 'SM']) {
        await gdb.db.insert('programme_matiere', ligne(cycle: 'lycee', serie: serie));
      }
      expect((await gdb.db.query('programme_matiere')).length, 6);
    });

    test('refuse une option hors lycée ou inconnue, un coefficient nul, un barème '
        'hors limites, un nom vide, un cycle inconnu', () async {
      final refuses = <String, Map<String, Object?>>{
        'option hors lycée': ligne(serie: 'SM'),
        'option inconnue': ligne(cycle: 'lycee', serie: 'XX'),
        'coefficient nul': ligne(coefficient: 0),
        'barème nul': ligne(bareme: 0),
        'barème trop grand': ligne(bareme: 1001),
        'nom vide': ligne(nom: '   '),
        'cycle inconnu': ligne(cycle: 'crèche'),
        'année inconnue': ligne(annee: 9999),
      };
      for (final entree in refuses.entries) {
        await expectLater(
          gdb.db.insert('programme_matiere', entree.value),
          throwsA(isA<DatabaseException>()),
          reason: entree.key,
        );
      }
      expect(await gdb.db.query('programme_matiere'), isEmpty);
    });

    test('une matière n\'existe qu\'une fois par année, cycle et option', () async {
      await gdb.db.insert('programme_matiere', ligne(cycle: 'lycee', serie: 'SM', nom: 'Physique'));
      await expectLater(
        gdb.db.insert('programme_matiere', ligne(cycle: 'lycee', serie: 'SM', nom: 'Physique')),
        throwsA(isA<DatabaseException>()),
      );
      // Autre option, autre cycle ou autre année : possible.
      await gdb.db.insert('programme_matiere', ligne(cycle: 'lycee', serie: 'SE', nom: 'Physique'));
      await gdb.db.insert('programme_matiere', ligne(cycle: 'college', nom: 'Physique'));
      await gdb.db.insert('programme_matiere',
          ligne(cycle: 'lycee', serie: 'SM', nom: 'Physique', annee: anneeArchivee));
    });

    test('le programme disparaît avec son année', () async {
      await gdb.db.insert('programme_matiere', ligne(annee: anneeArchivee));
      await gdb.db.delete('annee_scolaire', where: 'id = ?', whereArgs: [anneeArchivee]);
      expect(await gdb.db.query('programme_matiere'), isEmpty);
    });
  });

  test('une copie de la base d\'avant la mise à jour est conservée', () async {
    final gdb = await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
    await gdb.fermer();
    final copies = Directory(p.join(dossier.path, 'sauvegardes'))
        .listSync()
        .map((f) => p.basename(f.path))
        .where((n) => n.startsWith('${GescoDatabase.prefixeAvantMiseAJour}v4-vers-v5'))
        .toList();
    expect(copies, hasLength(1));
  });

  test('rouvrir la base ne refait pas la migration', () async {
    var gdb = await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
    await gdb.db.insert('programme_matiere', {
      'annee_id': anneeActive,
      'cycle': 'primaire',
      'serie': '',
      'nom': 'Lecture',
      'coefficient': 200,
    });
    await gdb.fermer();
    gdb = await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
    expect(await gdb.version(), 5);
    expect((await gdb.db.query('programme_matiere')).length, 1);
    expect((await gdb.db.query('config_calendrier_cycle')).length, 2);
    await gdb.fermer();
  });
}
