import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/schema.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher refuse(String texte) => throwsA(
      isA<DatabaseException>().having((e) => e.toString(), 'message', contains(texte)),
    );

/// Remplit une base avec le jeu de données d'un utilisateur de la version 1.
Future<void> remplirV1(Database db) async {
  final annee = await db.insert('annee_scolaire', {
    'libelle': '2026-2027',
    'active': 1,
    'cree_le': '2026-10-01',
  });
  final classe =
      await db.insert('classe', {'annee_id': annee, 'niveau': '10e', 'nom': '10e A'});
  final maths = await db.insert('matiere_classe',
      {'classe_id': classe, 'nom': 'Maths', 'coefficient': 400, 'ordre': 0});
  final francais = await db.insert('matiere_classe',
      {'classe_id': classe, 'nom': 'Français', 'coefficient': 300, 'ordre': 1});
  for (var i = 1; i <= 3; i++) {
    final eleve = await db.insert('eleve', {
      'matricule': '2026-000$i',
      'nom': 'NOM$i',
      'prenom': 'Prenom$i',
      'sexe': i.isEven ? 'M' : 'F',
      'adresse': 'Conakry',
    });
    final insc = await db.insert('inscription', {
      'eleve_id': eleve,
      'classe_id': classe,
      'annee_id': annee,
      'date_inscription': '2026-10-0$i',
    });
    await db.insert('note', {
      'inscription_id': insc,
      'matiere_id': maths,
      'mois': 10,
      'etat': 'saisie',
      'valeur': 1000 + i * 100,
      'modifie_le': '2026-10-20',
    });
    await db.insert('note', {
      'inscription_id': insc,
      'matiere_id': francais,
      'mois': 10,
      'etat': i == 3 ? 'absent' : 'saisie',
      'valeur': i == 3 ? null : 900 + i * 50,
      'modifie_le': '2026-10-20',
    });
  }
  await db.update('etablissement', {
    'nom': 'Groupe Scolaire Test',
    'adresse': 'Tombolia',
    'logo': Uint8List.fromList([1, 2, 3, 4]),
  });
  await db.insert('config_resultats', {'annee_id': annee, 'json': '{"x":1}'});
}

Future<Set<String>> nomsDeTables(Database db) async {
  final l = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
  return l.map((e) => e['name'] as String).toSet();
}

Future<Map<String, List<String>>> colonnes(Database db) async {
  final resultat = <String, List<String>>{};
  for (final t in await nomsDeTables(db)) {
    final l = await db.rawQuery('PRAGMA table_info($t)');
    resultat[t] = [for (final c in l) c['name'] as String]..sort();
  }
  return resultat;
}

Future<Set<String>> declencheurs(Database db) async {
  final l = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='trigger'");
  return l.map((e) => e['name'] as String).toSet();
}

void main() {
  sqfliteFfiInit();

  group('mise à jour d\'une base de la version 1', () {
    late Directory dossier;
    late String chemin;

    setUp(() async {
      dossier = await Directory.systemTemp.createTemp('gesco_migration_');
      chemin = p.join(dossier.path, 'gesco.db');
      final v1 = await databaseFactoryFfi.openDatabase(
        chemin,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, v) async {
            for (final instruction in schemaV1) {
              await db.execute(instruction);
            }
            await db.insert('etablissement', {'id': 1});
          },
        ),
      );
      await remplirV1(v1);
      await v1.close();
    });

    tearDown(() async {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    });

    test('toutes les données existantes sont conservées', () async {
      final gdb =
          await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
      final db = gdb.db;
      expect(await gdb.version(), GescoDatabase.versionSchema);

      expect((await db.query('eleve')).length, 3);
      expect((await db.query('inscription')).length, 3);
      expect((await db.query('note')).length, 6);
      expect((await db.query('matiere_classe')).length, 2);

      final notes = await db.query('note', orderBy: 'id');
      expect(notes.first['valeur'], 1100);
      expect(notes.where((n) => n['etat'] == 'absent').length, 1);

      final etab = (await db.query('etablissement')).single;
      expect(etab['nom'], 'Groupe Scolaire Test');
      expect(etab['logo'], [1, 2, 3, 4]);
      expect(etab['directeur'], '');
      expect(etab['signature_directeur'], isNull);

      expect((await db.query('config_resultats')).single['json'], '{"x":1}');
      expect(await gdb.verifierIntegrite(), isEmpty);
      await gdb.fermer();
    });

    test('les nouvelles colonnes ont des valeurs par défaut sûres', () async {
      final gdb =
          await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
      final db = gdb.db;
      final matiere = (await db.query('matiere_classe', orderBy: 'id')).first;
      expect(matiere['bareme'], 20);
      expect(matiere['facultative'], 0);
      expect(matiere['enseignant_id'], isNull);
      expect((await db.query('annee_scolaire')).single['archivee'], 0);
      final classe = (await db.query('classe')).single;
      expect(classe['capacite'], isNull);
      expect(classe['prof_principal_id'], isNull);
      final insc = (await db.query('inscription')).first;
      expect(insc['statut'], 'inscrit');
      expect((await db.query('eleve')).first['archive'], 0);
      final note = (await db.query('note')).first;
      expect(note['brut'], isNull);
      expect(note['bareme'], isNull);
      await gdb.fermer();
    });

    test('chaque inscription reçoit son mouvement d\'origine', () async {
      final gdb =
          await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
      final lignes = await gdb.db.query('mouvement_inscription', orderBy: 'id');
      expect(lignes.length, 3);
      expect(lignes.map((l) => l['type']).toSet(), {'inscription'});
      expect(lignes.first['date_mouvement'], '2026-10-01');
      await gdb.fermer();
    });

    test('une base mise à jour a le même schéma qu\'une base neuve', () async {
      final misAJour =
          await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
      final neuve = await GescoDatabase.ouvrir(
        fabrique: databaseFactoryFfi,
        chemin: inMemoryDatabasePath,
      );
      expect(await nomsDeTables(misAJour.db), await nomsDeTables(neuve.db));
      expect(await colonnes(misAJour.db), await colonnes(neuve.db));
      expect(await declencheurs(misAJour.db), await declencheurs(neuve.db));
      await misAJour.fermer();
      await neuve.fermer();
    });

    test('une fois mise à jour, la base se rouvre sans nouvelle migration', () async {
      var gdb =
          await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
      await gdb.db.update('etablissement', {'directeur': 'M. Diallo'});
      await gdb.fermer();
      gdb = await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
      expect((await gdb.db.query('etablissement')).single['directeur'], 'M. Diallo');
      expect((await gdb.db.query('note')).length, 6);
      await gdb.fermer();
    });

    test('les anciennes notes restent protégées par les anciens garde-fous', () async {
      final gdb =
          await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
      final db = gdb.db;
      await expectLater(
        db.update('note', {'valeur': 2500}),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.delete('matiere_classe', where: 'nom = ?', whereArgs: ['Maths']),
        throwsA(isA<DatabaseException>()),
      );
      expect((await db.query('note')).length, 6);
      await gdb.fermer();
    });
  });

  group('nouvelle base : contraintes', () {
    late GescoDatabase gdb;
    late Database db;
    late int annee;
    late int classe;
    late int classeB;
    late int maths;
    late int mathsB;
    late int insc;
    late int inscB;
    late int insc2;

    setUp(() async {
      gdb = await GescoDatabase.ouvrir(
        fabrique: databaseFactoryFfi,
        chemin: inMemoryDatabasePath,
      );
      db = gdb.db;
      annee = await db.insert('annee_scolaire',
          {'libelle': '2026-2027', 'active': 1, 'cree_le': '2026-10-01'});
      classe = await db.insert('classe', {'annee_id': annee, 'nom': '10e A'});
      classeB = await db.insert('classe', {'annee_id': annee, 'nom': '10e B'});
      maths = await db.insert('matiere_classe',
          {'classe_id': classe, 'nom': 'Maths', 'coefficient': 400});
      mathsB = await db.insert('matiere_classe',
          {'classe_id': classeB, 'nom': 'Maths', 'coefficient': 400});
      final e1 = await db.insert('eleve',
          {'matricule': 'M1', 'nom': 'DIALLO', 'prenom': 'Aminata', 'sexe': 'F'});
      final e2 = await db.insert('eleve',
          {'matricule': 'M2', 'nom': 'BARRY', 'prenom': 'Ibrahima', 'sexe': 'M'});
      insc = await db.insert('inscription', {
        'eleve_id': e1,
        'classe_id': classe,
        'annee_id': annee,
        'date_inscription': '2026-10-01',
      });
      final e3 = await db.insert('eleve',
          {'matricule': 'M3', 'nom': 'SOW', 'prenom': 'Mariama', 'sexe': 'F'});
      insc2 = await db.insert('inscription', {
        'eleve_id': e3,
        'classe_id': classe,
        'annee_id': annee,
        'date_inscription': '2026-10-01',
      });
      inscB = await db.insert('inscription', {
        'eleve_id': e2,
        'classe_id': classeB,
        'annee_id': annee,
        'date_inscription': '2026-10-01',
      });
    });

    tearDown(() async => gdb.fermer());

    Future<int> noter(int i, int m, int mois, int valeur) => db.insert('note', {
          'inscription_id': i,
          'matiere_id': m,
          'mois': mois,
          'etat': 'saisie',
          'valeur': valeur,
          'modifie_le': '2026-10-02',
        });

    group('matières, classes, élèves, enseignants, utilisateurs', () {
      test('barème 20 et obligatoire par défaut ; barèmes absurdes refusés', () async {
        final m = (await db.query('matiere_classe', where: 'id = ?', whereArgs: [maths]))
            .single;
        expect(m['bareme'], 20);
        expect(m['facultative'], 0);
        for (final b in [0, -5, 1001]) {
          await expectLater(
            db.update('matiere_classe', {'bareme': b},
                where: 'id = ?', whereArgs: [maths]),
            throwsA(isA<DatabaseException>()),
            reason: 'barème $b',
          );
        }
        await db.update('matiere_classe', {'bareme': 100, 'facultative': 1},
            where: 'id = ?', whereArgs: [maths]);
      });

      test('capacité de classe : positive ou absente', () async {
        await db.update('classe', {'capacite': 50}, where: 'id = ?', whereArgs: [classe]);
        await expectLater(
          db.update('classe', {'capacite': 0}, where: 'id = ?', whereArgs: [classe]),
          throwsA(isA<DatabaseException>()),
        );
      });

      test('un professeur principal supprimé laisse la classe sans titulaire', () async {
        final ens = await db.insert('enseignant',
            {'nom': 'CAMARA', 'prenom': 'Sékou', 'cree_le': '2026-10-01'});
        await db.update('classe', {'prof_principal_id': ens},
            where: 'id = ?', whereArgs: [classe]);
        await db.update('matiere_classe', {'enseignant_id': ens},
            where: 'id = ?', whereArgs: [maths]);
        await db.delete('enseignant', where: 'id = ?', whereArgs: [ens]);
        expect((await db.query('classe', where: 'id = ?', whereArgs: [classe]))
            .single['prof_principal_id'], isNull);
        expect((await db.query('matiere_classe', where: 'id = ?', whereArgs: [maths]))
            .single['enseignant_id'], isNull);
      });

      test('enseignant : nom obligatoire, matricule unique, sexe M ou F', () async {
        await expectLater(
          db.insert('enseignant', {'nom': ' ', 'prenom': 'X', 'cree_le': 'd'}),
          throwsA(isA<DatabaseException>()),
        );
        await db.insert('enseignant',
            {'nom': 'A', 'prenom': 'B', 'matricule': 'E1', 'cree_le': 'd'});
        await expectLater(
          db.insert('enseignant',
              {'nom': 'C', 'prenom': 'D', 'matricule': 'E1', 'cree_le': 'd'}),
          throwsA(isA<DatabaseException>()),
        );
        await expectLater(
          db.insert('enseignant',
              {'nom': 'C', 'prenom': 'D', 'sexe': 'X', 'cree_le': 'd'}),
          throwsA(isA<DatabaseException>()),
        );
      });

      test('utilisateur : rôle connu, identifiant de 3 caractères, unique sans casse',
          () async {
        Map<String, Object?> u(String id, {String role = 'consultation'}) => {
              'identifiant': id,
              'role': role,
              'mot_de_passe_hash': 'h',
              'sel': 's',
              'iterations': 1,
              'cree_le': 'd',
            };
        await db.insert('utilisateur', u('admin', role: 'administrateur'));
        await expectLater(
            db.insert('utilisateur', u('ADMIN')), throwsA(isA<DatabaseException>()));
        await expectLater(
            db.insert('utilisateur', u('ab')), throwsA(isA<DatabaseException>()));
        await expectLater(db.insert('utilisateur', u('pirate', role: 'dieu')),
            throwsA(isA<DatabaseException>()));
        for (final r in ['direction', 'saisie', 'consultation']) {
          await db.insert('utilisateur', u('compte_$r', role: r));
        }
      });

      test('statut d\'inscription : inscrit, départ ou abandon seulement', () async {
        for (final s in ['depart', 'abandon', 'inscrit']) {
          await db.update('inscription', {'statut': s},
              where: 'id = ?', whereArgs: [insc]);
        }
        await expectLater(
          db.update('inscription', {'statut': 'inconnu'},
              where: 'id = ?', whereArgs: [insc]),
          throwsA(isA<DatabaseException>()),
        );
      });

      test('appréciations supprimées avec l\'inscription', () async {
        await db.insert('appreciation_eleve', {
          'inscription_id': insc,
          'periode': 't1',
          'appreciation': 'Bon travail',
          'decision_conseil': 'Passage',
        });
        await db.insert('appreciation_matiere',
            {'inscription_id': insc, 'matiere_id': maths, 'periode': 't1', 'texte': 'ok'});
        await db.delete('inscription', where: 'id = ?', whereArgs: [insc]);
        expect(await db.query('appreciation_eleve'), isEmpty);
        expect(await db.query('appreciation_matiere'), isEmpty);
      });

      test('mouvements d\'inscription supprimés avec l\'inscription', () async {
        await db.insert('mouvement_inscription', {
          'inscription_id': insc,
          'type': 'depart',
          'date_mouvement': '2026-11-01',
        });
        await expectLater(
          db.insert('mouvement_inscription', {
            'inscription_id': insc,
            'type': 'vacances',
            'date_mouvement': '2026-11-01',
          }),
          throwsA(isA<DatabaseException>()),
        );
        await db.delete('inscription', where: 'id = ?', whereArgs: [insc]);
        expect(await db.query('mouvement_inscription'), isEmpty);
      });
    });

    group('historique automatique des notes', () {
      test('création, modification et suppression sont enregistrées', () async {
        await db.update('contexte', {'utilisateur_id': 7, 'utilisateur_nom': 'Alice'});
        final id = await noter(insc, maths, 10, 1000);
        await db.update('note', {'valeur': 1250}, where: 'id = ?', whereArgs: [id]);
        await db.update('note', {'etat': 'absent', 'valeur': null},
            where: 'id = ?', whereArgs: [id]);
        await db.delete('note', where: 'id = ?', whereArgs: [id]);

        final h = await db.query('historique_note', orderBy: 'id');
        expect(h.map((l) => l['operation']).toList(),
            ['creation', 'modification', 'modification', 'suppression']);
        expect(h.every((l) => l['source'] == 'mensuelle'), isTrue);
        expect(h.every((l) => l['utilisateur_nom'] == 'Alice'), isTrue);
        expect(h.every((l) => l['utilisateur_id'] == 7), isTrue);
        expect(h.first['nouvelle_valeur'], 1000);
        expect(h.first['ancienne_valeur'], isNull);
        expect(h[1]['ancienne_valeur'], 1000);
        expect(h[1]['nouvelle_valeur'], 1250);
        expect(h[2]['ancien_etat'], 'saisie');
        expect(h[2]['nouvel_etat'], 'absent');
        expect(h[3]['ancienne_valeur'], isNull);
        expect(h[3]['ancien_etat'], 'absent');
        expect(h.first['eleve_nom'], 'DIALLO Aminata');
        expect(h.first['matiere_nom'], 'Maths');
        expect(h.first['classe_nom'], '10e A');
        expect(h.first['mois'], 10);
        expect(h.first['date_heure'], matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$')));
      });

      test('réécrire la même valeur ne crée pas de ligne d\'historique', () async {
        final id = await noter(insc, maths, 10, 1000);
        await db.update('note', {'valeur': 1000, 'modifie_le': '2026-10-09'},
            where: 'id = ?', whereArgs: [id]);
        expect((await db.query('historique_note')).length, 1);
      });

      test('l\'historique survit à la suppression de l\'élève', () async {
        final id = await noter(insc, maths, 10, 1400);
        await db.delete('note', where: 'id = ?', whereArgs: [id]);
        await db.delete('inscription', where: 'id = ?', whereArgs: [insc]);
        final h = await db.query('historique_note', orderBy: 'id');
        expect(h.length, 2);
        expect(h.last['operation'], 'suppression');
        expect(h.last['eleve_nom'], 'DIALLO Aminata');
        expect(h.last['ancienne_valeur'], 1400);
      });
    });

    group('verrouillage des mois et archivage des années', () {
      test('un mois verrouillé refuse l\'ajout, la modification et la suppression',
          () async {
        final id = await noter(insc, maths, 10, 1000);
        await db.insert('verrou_notes', {
          'classe_id': classe,
          'mois': 10,
          'verrouille_le': '2026-10-31',
          'utilisateur_nom': 'Alice',
        });
        await expectLater(noter(insc, maths, 10, 1100), refuse('Mois verrouille'));
        await expectLater(
          db.update('note', {'valeur': 1500}, where: 'id = ?', whereArgs: [id]),
          refuse('Mois verrouille'),
        );
        await expectLater(
          db.delete('note', where: 'id = ?', whereArgs: [id]),
          refuse('Mois verrouille'),
        );
        expect((await db.query('note', where: 'id = ?', whereArgs: [id])).single['valeur'],
            1000);
      });

      test('seul le mois et la classe verrouillés sont concernés', () async {
        await db.insert('verrou_notes',
            {'classe_id': classe, 'mois': 10, 'verrouille_le': '2026-10-31'});
        await noter(insc, maths, 11, 1000);
        await noter(inscB, mathsB, 10, 1000);
      });

      test('déverrouiller rend la saisie possible', () async {
        await db.insert('verrou_notes',
            {'classe_id': classe, 'mois': 10, 'verrouille_le': '2026-10-31'});
        await expectLater(noter(insc, maths, 10, 900), refuse('Mois verrouille'));
        await db.delete('verrou_notes',
            where: 'classe_id = ? AND mois = ?', whereArgs: [classe, 10]);
        await noter(insc, maths, 10, 900);
      });

      test('une année archivée est en lecture seule', () async {
        final id = await noter(insc, maths, 10, 1000);
        await db.update('annee_scolaire', {'archivee': 1},
            where: 'id = ?', whereArgs: [annee]);
        await expectLater(noter(insc, maths, 11, 1000), refuse('Annee archivee'));
        await expectLater(
          db.update('note', {'valeur': 1200}, where: 'id = ?', whereArgs: [id]),
          refuse('Annee archivee'),
        );
        await expectLater(
          db.delete('note', where: 'id = ?', whereArgs: [id]),
          refuse('Annee archivee'),
        );
        await db.update('annee_scolaire', {'archivee': 0},
            where: 'id = ?', whereArgs: [annee]);
        await noter(insc, maths, 11, 1000);
      });
    });

    group('transfert d\'un élève avec notes', () {
      test('sans indicateur de transfert, la classe reste verrouillée', () async {
        await noter(insc, maths, 10, 1000);
        await expectLater(
          db.update('inscription', {'classe_id': classeB},
              where: 'id = ?', whereArgs: [insc]),
          refuse('Classe verrouillee'),
        );
      });

      test('avec l\'indicateur, les notes suivent l\'élève vers la matière équivalente',
          () async {
        await noter(insc, maths, 10, 1000);
        await noter(insc, maths, 11, 1200);
        await db.update('contexte', {'transfert': 1});
        await db.update('note', {'matiere_id': mathsB},
            where: 'inscription_id = ? AND matiere_id = ?', whereArgs: [insc, maths]);
        await db.update('inscription', {'classe_id': classeB},
            where: 'id = ?', whereArgs: [insc]);
        await db.update('contexte', {'transfert': 0});

        final notes = await db.query('note', where: 'inscription_id = ?', whereArgs: [insc]);
        expect(notes.length, 2);
        expect(notes.every((n) => n['matiere_id'] == mathsB), isTrue);
        // Aucune ligne d'historique parasite : les valeurs n'ont pas changé.
        expect((await db.query('historique_note')).length, 2);
      });

      test('l\'indicateur remis à zéro, la cohérence est de nouveau contrôlée',
          () async {
        final id = await noter(insc, maths, 10, 1000);
        await expectLater(
          db.update('note', {'matiere_id': mathsB}, where: 'id = ?', whereArgs: [id]),
          refuse('Matiere hors classe'),
        );
      });
    });

    group('évaluations et leurs notes', () {
      Future<int> evaluation({
        int? classeId,
        int? matiereId,
        int mois = 10,
        int bareme = 20,
        String type = 'devoir',
      }) =>
          db.insert('evaluation', {
            'classe_id': classeId ?? classe,
            'matiere_id': matiereId ?? maths,
            'mois': mois,
            'type': type,
            'titre': 'Devoir 1',
            'bareme': bareme,
            'cree_le': '2026-10-05',
          });

      Future<int> noteEval(int ev, int i, {String etat = 'saisie', int? brut}) =>
          db.insert('evaluation_note', {
            'evaluation_id': ev,
            'inscription_id': i,
            'etat': etat,
            'brut': brut,
            'modifie_le': '2026-10-06',
          });

      test('une évaluation a un barème, un coefficient et un type contrôlés', () async {
        final ev = await evaluation(bareme: 40);
        final l = (await db.query('evaluation', where: 'id = ?', whereArgs: [ev])).single;
        expect(l['bareme'], 40);
        expect(l['coefficient'], 100);
        expect(l['valide'], 0);
        await expectLater(
            evaluation(type: 'quiz'), throwsA(isA<DatabaseException>()));
        await expectLater(
            evaluation(bareme: 0), throwsA(isA<DatabaseException>()));
        await expectLater(
            evaluation(mois: 7), throwsA(isA<DatabaseException>()));
        for (final t in ['interrogation', 'composition', 'examen', 'evaluation']) {
          await evaluation(type: t);
        }
      });

      test('la matière doit appartenir à la classe de l\'évaluation', () async {
        await expectLater(
          evaluation(matiereId: mathsB),
          refuse('Matiere hors classe'),
        );
      });

      test('une note d\'évaluation est conservée telle que saisie (brut)', () async {
        final ev = await evaluation(bareme: 10);
        await noteEval(ev, insc, brut: 700);
        final l = (await db.query('evaluation_note')).single;
        expect(l['brut'], 700);
      });

      test('une note au-dessus du barème de l\'évaluation est refusée', () async {
        final ev = await evaluation(bareme: 10);
        await noteEval(ev, insc, brut: 1000);
        await expectLater(noteEval(ev, insc2, brut: 1001), refuse('Note hors bareme'));
        final ev40 = await evaluation(bareme: 40);
        await noteEval(ev40, insc, brut: 4000);
        await expectLater(
          db.update('evaluation_note', {'brut': 4100},
              where: 'evaluation_id = ?', whereArgs: [ev40]),
          refuse('Note hors bareme'),
        );
      });

      test('un élève d\'une autre classe ne peut pas être noté', () async {
        final ev = await evaluation();
        await expectLater(noteEval(ev, inscB, brut: 1000), refuse('Eleve hors classe'));
      });

      test('une seule note par élève et par évaluation', () async {
        final ev = await evaluation();
        await noteEval(ev, insc, brut: 1000);
        await expectLater(
            noteEval(ev, insc, brut: 1100), throwsA(isA<DatabaseException>()));
      });

      test('absent et dispensé n\'ont pas de note ; saisie sans note refusée', () async {
        final ev = await evaluation();
        await noteEval(ev, insc, etat: 'absent');
        await expectLater(noteEval(ev, insc2, etat: 'saisie'),
            throwsA(isA<DatabaseException>()));
        await expectLater(noteEval(ev, insc2, etat: 'dispense', brut: 500),
            throwsA(isA<DatabaseException>()));
      });

      test('une évaluation validée est verrouillée', () async {
        final ev = await evaluation();
        final n = await noteEval(ev, insc, brut: 1000);
        await db.update('evaluation', {'valide': 1}, where: 'id = ?', whereArgs: [ev]);
        await expectLater(
          db.update('evaluation_note', {'brut': 1500}, where: 'id = ?', whereArgs: [n]),
          refuse('Evaluation validee'),
        );
        await expectLater(
          db.delete('evaluation_note', where: 'id = ?', whereArgs: [n]),
          refuse('Evaluation validee'),
        );
        await db.update('evaluation', {'valide': 0}, where: 'id = ?', whereArgs: [ev]);
        await db.update('evaluation_note', {'brut': 1500},
            where: 'id = ?', whereArgs: [n]);
      });

      test('le verrou du mois s\'applique aux notes d\'évaluation', () async {
        final ev = await evaluation(mois: 11);
        await db.insert('verrou_notes',
            {'classe_id': classe, 'mois': 11, 'verrouille_le': '2026-11-30'});
        await expectLater(noteEval(ev, insc, brut: 1000), refuse('Mois verrouille'));
      });

      test('on ne change pas le barème ni le mois d\'une évaluation notée', () async {
        final ev = await evaluation();
        await db.update('evaluation', {'bareme': 40}, where: 'id = ?', whereArgs: [ev]);
        await noteEval(ev, insc, brut: 1000);
        await expectLater(
          db.update('evaluation', {'bareme': 10}, where: 'id = ?', whereArgs: [ev]),
          refuse('Evaluation avec notes'),
        );
        await expectLater(
          db.update('evaluation', {'mois': 11}, where: 'id = ?', whereArgs: [ev]),
          refuse('Evaluation avec notes'),
        );
        await db.update('evaluation', {'titre': 'Devoir n°1', 'coefficient': 200},
            where: 'id = ?', whereArgs: [ev]);
      });

      test('une évaluation qui a des notes ne peut pas être supprimée directement',
          () async {
        final ev = await evaluation();
        final n = await noteEval(ev, insc, brut: 1000);
        await expectLater(
          db.delete('evaluation', where: 'id = ?', whereArgs: [ev]),
          refuse('Evaluation avec notes'),
        );
        await db.delete('evaluation_note', where: 'id = ?', whereArgs: [n]);
        await db.delete('evaluation', where: 'id = ?', whereArgs: [ev]);
        expect(await db.query('evaluation'), isEmpty);
      });

      test('une matière ou une classe qui a des évaluations ne peut pas être supprimée',
          () async {
        final classeC = await db.insert('classe', {'annee_id': annee, 'nom': '10e C'});
        final mathsC = await db.insert('matiere_classe',
            {'classe_id': classeC, 'nom': 'Maths', 'coefficient': 400});
        final ev = await evaluation(classeId: classeC, matiereId: mathsC);
        await expectLater(
          db.delete('matiere_classe', where: 'id = ?', whereArgs: [mathsC]),
          throwsA(isA<DatabaseException>()),
        );
        await expectLater(
          db.delete('classe', where: 'id = ?', whereArgs: [classeC]),
          throwsA(isA<DatabaseException>()),
        );
        await db.delete('evaluation', where: 'id = ?', whereArgs: [ev]);
        await db.delete('classe', where: 'id = ?', whereArgs: [classeC]);
        expect(await db.query('matiere_classe', where: 'id = ?', whereArgs: [mathsC]),
            isEmpty);
      });

      test('un élève qui a des notes d\'évaluation ne change pas de classe', () async {
        final ev = await evaluation();
        await noteEval(ev, insc, brut: 1000);
        await expectLater(
          db.update('inscription', {'classe_id': classeB},
              where: 'id = ?', whereArgs: [insc]),
          refuse('Classe verrouillee'),
        );
      });

      test('l\'historique des notes d\'évaluation garde le barème et le mois', () async {
        await db.update('contexte', {'utilisateur_nom': 'Bob'});
        final ev = await evaluation(bareme: 40, mois: 12);
        final n = await noteEval(ev, insc, brut: 3000);
        await db.update('evaluation_note', {'brut': 3500}, where: 'id = ?', whereArgs: [n]);
        final h = await db.query('historique_note', orderBy: 'id');
        expect(h.length, 2);
        expect(h.every((l) => l['source'] == 'evaluation'), isTrue);
        expect(h.every((l) => l['bareme'] == 40), isTrue);
        expect(h.every((l) => l['mois'] == 12), isTrue);
        expect(h.every((l) => l['evaluation_id'] == ev), isTrue);
        expect(h.every((l) => l['matiere_nom'] == 'Maths'), isTrue);
        expect(h.every((l) => l['utilisateur_nom'] == 'Bob'), isTrue);
        expect(h.last['ancienne_valeur'], 3000);
        expect(h.last['nouvelle_valeur'], 3500);
      });
    });

    group('journaux, sauvegardes, calendrier', () {
      test('journal et journal de connexion acceptent des lignes simples', () async {
        await db.insert('journal', {
          'date_heure': '2026-11-17T08:00:00',
          'action': 'creation',
          'entite': 'classe',
          'entite_id': classe,
          'details': '10e A',
        });
        await db.insert('journal_connexion', {
          'date_heure': '2026-11-17T08:00:01',
          'identifiant': 'admin',
          'evenement': 'connexion',
        });
        expect((await db.query('journal')).length, 1);
        expect((await db.query('journal_connexion')).length, 1);
      });

      test('sauvegarde : type connu seulement', () async {
        for (final t in ['manuelle', 'automatique', 'securite']) {
          await db.insert('sauvegarde', {'chemin': 'x', 'cree_le': 'd', 'type': t});
        }
        await expectLater(
          db.insert('sauvegarde', {'chemin': 'x', 'cree_le': 'd', 'type': 'rumeur'}),
          throwsA(isA<DatabaseException>()),
        );
      });

      test('calendrier supprimé avec son année', () async {
        final a2 = await db.insert('annee_scolaire',
            {'libelle': '2027-2028', 'active': 0, 'cree_le': '2027-10-01'});
        await db.insert('config_calendrier', {'annee_id': a2, 'json': '{}'});
        await db.delete('annee_scolaire', where: 'id = ?', whereArgs: [a2]);
        expect(await db.query('config_calendrier'), isEmpty);
      });

      test('contrôle d\'intégrité de la base neuve : rien à signaler', () async {
        expect(await gdb.verifierIntegrite(), isEmpty);
      });

      test('une seule ligne de contexte', () async {
        expect((await db.query('contexte')).length, 1);
        await expectLater(
          db.insert('contexte', {'id': 2}),
          throwsA(isA<DatabaseException>()),
        );
      });
    });
  });
}
