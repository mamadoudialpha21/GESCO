import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Aides : création rapide d'une année, d'une classe, etc.
Future<int> creerAnnee(Database db, String libelle, {bool active = false}) =>
    db.insert('annee_scolaire', {
      'libelle': libelle,
      'active': active ? 1 : 0,
      'cree_le': '2026-10-01',
    });

Future<int> creerClasse(Database db, int anneeId, String nom) =>
    db.insert('classe', {'annee_id': anneeId, 'niveau': '10e', 'nom': nom});

Future<int> creerMatiere(Database db, int classeId, String nom, int coef) =>
    db.insert('matiere_classe', {
      'classe_id': classeId,
      'nom': nom,
      'coefficient': coef,
      'ordre': 0,
    });

Future<int> creerEleve(Database db, String matricule, {String sexe = 'F'}) =>
    db.insert('eleve', {
      'matricule': matricule,
      'nom': 'DIALLO',
      'prenom': 'Aminata',
      'sexe': sexe,
    });

Future<int> inscrire(Database db, int eleveId, int classeId, int anneeId) =>
    db.insert('inscription', {
      'eleve_id': eleveId,
      'classe_id': classeId,
      'annee_id': anneeId,
      'date_inscription': '2026-10-01',
    });

Future<int> noter(
  Database db,
  int inscriptionId,
  int matiereId,
  int mois, {
  String etat = 'saisie',
  int? valeur,
}) =>
    db.insert('note', {
      'inscription_id': inscriptionId,
      'matiere_id': matiereId,
      'mois': mois,
      'etat': etat,
      'valeur': valeur,
      'modifie_le': '2026-10-02',
    });

/// Jeu de données minimal : 1 année, 1 classe, 1 matière, 1 élève inscrit.
class Jeu {
  Jeu(this.annee, this.classe, this.matiere, this.eleve, this.inscription);
  final int annee;
  final int classe;
  final int matiere;
  final int eleve;
  final int inscription;
}

Future<Jeu> creerJeu(Database db) async {
  final annee = await creerAnnee(db, '2026-2027', active: true);
  final classe = await creerClasse(db, annee, '10e A');
  final matiere = await creerMatiere(db, classe, 'Mathématiques', 400);
  final eleve = await creerEleve(db, 'M001');
  final inscription = await inscrire(db, eleve, classe, annee);
  return Jeu(annee, classe, matiere, eleve, inscription);
}

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Database db;

  setUp(() async {
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    db = gdb.db;
  });

  tearDown(() async {
    await gdb.fermer();
  });

  group('création de la base', () {
    test('toutes les tables existent, en version 1', () async {
      final lignes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      );
      final noms = lignes.map((l) => l['name']).toSet();
      expect(
        noms,
        containsAll(<String>{
          'etablissement',
          'parametre',
          'annee_scolaire',
          'config_resultats',
          'classe',
          'matiere_classe',
          'eleve',
          'inscription',
          'note',
        }),
      );
      expect(await gdb.version(), GescoDatabase.versionSchema);
    });

    test('la fiche établissement existe dès la création', () async {
      final lignes = await db.query('etablissement');
      expect(lignes.length, 1);
      expect(lignes.first['id'], 1);
      expect(lignes.first['nom'], '');
    });

    test('contrôle d\'intégrité : aucun problème sur une base neuve', () async {
      expect(await gdb.verifierIntegrite(), isEmpty);
    });

    test('les clés étrangères sont activées', () async {
      final lignes = await db.rawQuery('PRAGMA foreign_keys');
      expect(lignes.first.values.first, 1);
    });
  });

  group('années scolaires', () {
    test('une seule année active à la fois', () async {
      await creerAnnee(db, '2025-2026', active: true);
      await expectLater(
        creerAnnee(db, '2026-2027', active: true),
        throwsA(isA<DatabaseException>()),
      );
      // Plusieurs années inactives sont permises.
      await creerAnnee(db, '2026-2027');
      await creerAnnee(db, '2027-2028');
    });

    test('le libellé d\'une année est unique', () async {
      await creerAnnee(db, '2026-2027');
      await expectLater(
        creerAnnee(db, '2026-2027'),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('classes et matières', () {
    test('une même classe peut exister dans deux années différentes', () async {
      final a1 = await creerAnnee(db, '2025-2026');
      final a2 = await creerAnnee(db, '2026-2027');
      await creerClasse(db, a1, '10e A');
      await creerClasse(db, a2, '10e A');
      await expectLater(
        creerClasse(db, a1, '10e A'),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('chaque classe a ses propres matières et coefficients', () async {
      final annee = await creerAnnee(db, '2026-2027');
      final c1 = await creerClasse(db, annee, '10e A');
      final c2 = await creerClasse(db, annee, '11e B');
      await creerMatiere(db, c1, 'Mathématiques', 400);
      await creerMatiere(db, c2, 'Mathématiques', 250);
      await creerMatiere(db, c2, 'Physique', 200);
      final m1 = await db.query('matiere_classe', where: 'classe_id = ?', whereArgs: [c1]);
      final m2 = await db.query('matiere_classe', where: 'classe_id = ?', whereArgs: [c2]);
      expect(m1.length, 1);
      expect(m2.length, 2);
    });

    test('coefficient nul ou négatif refusé', () async {
      final annee = await creerAnnee(db, '2026-2027');
      final classe = await creerClasse(db, annee, '10e A');
      await expectLater(
        creerMatiere(db, classe, 'Maths', 0),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        creerMatiere(db, classe, 'Maths', -100),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('inscriptions', () {
    test('un élève n\'a qu\'une inscription par année', () async {
      final jeu = await creerJeu(db);
      final autreClasse = await creerClasse(db, jeu.annee, '10e B');
      await expectLater(
        inscrire(db, jeu.eleve, autreClasse, jeu.annee),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('un élève peut être inscrit dans des années différentes', () async {
      final jeu = await creerJeu(db);
      final annee2 = await creerAnnee(db, '2027-2028');
      final classe2 = await creerClasse(db, annee2, '11e A');
      await inscrire(db, jeu.eleve, classe2, annee2);
    });

    test('la classe doit appartenir à la même année que l\'inscription',
        () async {
      final a1 = await creerAnnee(db, '2025-2026');
      final a2 = await creerAnnee(db, '2026-2027');
      final classeA1 = await creerClasse(db, a1, '10e A');
      final eleve = await creerEleve(db, 'M002');
      await expectLater(
        inscrire(db, eleve, classeA1, a2),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('le matricule est unique', () async {
      await creerEleve(db, 'M001');
      await expectLater(
        creerEleve(db, 'M001'),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('la classe d\'une inscription ne peut pas changer si elle a des notes',
        () async {
      final jeu = await creerJeu(db);
      final autreClasse = await creerClasse(db, jeu.annee, '10e B');
      await noter(db, jeu.inscription, jeu.matiere, 10, valeur: 1000);
      await expectLater(
        db.update(
          'inscription',
          {'classe_id': autreClasse},
          where: 'id = ?',
          whereArgs: [jeu.inscription],
        ),
        throwsA(isA<DatabaseException>()),
      );
      final ligne = (await db.query(
        'inscription',
        where: 'id = ?',
        whereArgs: [jeu.inscription],
      ))
          .first;
      expect(ligne['classe_id'], jeu.classe);

      // Mettre la même classe (sans changement réel) reste permis.
      await db.update(
        'inscription',
        {'classe_id': jeu.classe},
        where: 'id = ?',
        whereArgs: [jeu.inscription],
      );
    });

    test('la classe d\'une inscription sans note peut changer', () async {
      final jeu = await creerJeu(db);
      final autreClasse = await creerClasse(db, jeu.annee, '10e B');
      await db.update(
        'inscription',
        {'classe_id': autreClasse},
        where: 'id = ?',
        whereArgs: [jeu.inscription],
      );
      final ligne = (await db.query(
        'inscription',
        where: 'id = ?',
        whereArgs: [jeu.inscription],
      ))
          .first;
      expect(ligne['classe_id'], autreClasse);
    });

    test('le sexe doit être M ou F', () async {
      await expectLater(
        creerEleve(db, 'M009', sexe: 'X'),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('notes', () {
    test('saisie valide, absent et dispensé', () async {
      final jeu = await creerJeu(db);
      final autre = await creerMatiere(db, jeu.classe, 'Français', 300);
      final dispense = await creerMatiere(db, jeu.classe, 'Anglais', 200);
      await noter(db, jeu.inscription, jeu.matiere, 10, valeur: 1475);
      await noter(db, jeu.inscription, autre, 10, etat: 'absent');
      await noter(db, jeu.inscription, dispense, 10, etat: 'dispense');
      final lignes = await db.query('note', orderBy: 'id');
      expect(lignes.length, 3);
      expect(lignes[0]['valeur'], 1475);
      expect(lignes[1]['valeur'], isNull);
      expect(lignes[2]['valeur'], isNull);
    });

    test('les bornes 0,00 et 20,00 sont acceptées', () async {
      final jeu = await creerJeu(db);
      final autre = await creerMatiere(db, jeu.classe, 'Français', 300);
      await noter(db, jeu.inscription, jeu.matiere, 10, valeur: 0);
      await noter(db, jeu.inscription, autre, 10, valeur: 2000);
    });

    test('une note hors de 0 à 20 est refusée', () async {
      final jeu = await creerJeu(db);
      await expectLater(
        noter(db, jeu.inscription, jeu.matiere, 10, valeur: 2001),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        noter(db, jeu.inscription, jeu.matiere, 10, valeur: -1),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('état « saisie » sans valeur refusé ; « absent » avec valeur refusé',
        () async {
      final jeu = await creerJeu(db);
      await expectLater(
        noter(db, jeu.inscription, jeu.matiere, 10),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        noter(db, jeu.inscription, jeu.matiere, 10, etat: 'absent', valeur: 500),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('état inconnu refusé', () async {
      final jeu = await creerJeu(db);
      await expectLater(
        noter(db, jeu.inscription, jeu.matiere, 10, etat: 'zero', valeur: 0),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('mois hors année scolaire refusés (juillet, août, septembre)',
        () async {
      final jeu = await creerJeu(db);
      for (final mois in [0, 7, 8, 9, 13]) {
        await expectLater(
          noter(db, jeu.inscription, jeu.matiere, mois, valeur: 1000),
          throwsA(isA<DatabaseException>()),
          reason: 'mois $mois',
        );
      }
      // Tous les mois scolaires sont acceptés.
      for (final mois in [10, 11, 12, 1, 2, 3, 4, 5, 6]) {
        await noter(db, jeu.inscription, jeu.matiere, mois, valeur: 1000);
      }
    });

    test('une seule note par élève, matière et mois', () async {
      final jeu = await creerJeu(db);
      await noter(db, jeu.inscription, jeu.matiere, 10, valeur: 1000);
      await expectLater(
        noter(db, jeu.inscription, jeu.matiere, 10, valeur: 1100),
        throwsA(isA<DatabaseException>()),
      );
      // Un autre mois est permis.
      await noter(db, jeu.inscription, jeu.matiere, 11, valeur: 1100);
    });

    test('une matière d\'une autre classe est refusée', () async {
      final jeu = await creerJeu(db);
      final autreClasse = await creerClasse(db, jeu.annee, '11e B');
      final matiereAutreClasse = await creerMatiere(db, autreClasse, 'Physique', 200);
      await expectLater(
        noter(db, jeu.inscription, matiereAutreClasse, 10, valeur: 1000),
        throwsA(isA<DatabaseException>()),
      );
      // Contrôle : la matière de la bonne classe fonctionne.
      await noter(db, jeu.inscription, jeu.matiere, 10, valeur: 1000);
    });

    test('modifier une note existante', () async {
      final jeu = await creerJeu(db);
      final id = await noter(db, jeu.inscription, jeu.matiere, 10, valeur: 1000);
      await db.update('note', {'valeur': 1250}, where: 'id = ?', whereArgs: [id]);
      final ligne = (await db.query('note', where: 'id = ?', whereArgs: [id])).first;
      expect(ligne['valeur'], 1250);
    });
  });

  group('protection contre les suppressions dangereuses', () {
    test('une classe qui possède des notes ne peut pas être supprimée',
        () async {
      final jeu = await creerJeu(db);
      await noter(db, jeu.inscription, jeu.matiere, 10, valeur: 1200);
      await expectLater(
        db.delete('classe', where: 'id = ?', whereArgs: [jeu.classe]),
        throwsA(isA<DatabaseException>()),
      );
      // Rien n'a été perdu.
      expect((await db.query('note')).length, 1);
      expect((await db.query('matiere_classe')).length, 1);
      expect((await db.query('classe')).length, 1);
    });

    test('une classe sans notes ni élèves peut être supprimée avec ses matières',
        () async {
      final annee = await creerAnnee(db, '2026-2027');
      final classe = await creerClasse(db, annee, '10e A');
      await creerMatiere(db, classe, 'Mathématiques', 400);
      await db.delete('classe', where: 'id = ?', whereArgs: [classe]);
      expect(await db.query('classe'), isEmpty);
      expect(await db.query('matiere_classe'), isEmpty);
    });

    test('une classe qui a des inscrits ne peut pas être supprimée', () async {
      final jeu = await creerJeu(db);
      await expectLater(
        db.delete('classe', where: 'id = ?', whereArgs: [jeu.classe]),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('une matière qui a des notes ne peut pas être supprimée', () async {
      final jeu = await creerJeu(db);
      await noter(db, jeu.inscription, jeu.matiere, 10, valeur: 1200);
      await expectLater(
        db.delete('matiere_classe', where: 'id = ?', whereArgs: [jeu.matiere]),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('une inscription qui a des notes ne peut pas être supprimée',
        () async {
      final jeu = await creerJeu(db);
      await noter(db, jeu.inscription, jeu.matiere, 10, valeur: 1200);
      await expectLater(
        db.delete('inscription', where: 'id = ?', whereArgs: [jeu.inscription]),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('une inscription sans note peut être supprimée', () async {
      final jeu = await creerJeu(db);
      await db.delete('inscription', where: 'id = ?', whereArgs: [jeu.inscription]);
      expect(await db.query('inscription'), isEmpty);
      // L'élève lui-même reste dans la base.
      expect((await db.query('eleve')).length, 1);
    });

    test('une année qui contient des classes ne peut pas être supprimée',
        () async {
      final jeu = await creerJeu(db);
      await expectLater(
        db.delete('annee_scolaire', where: 'id = ?', whereArgs: [jeu.annee]),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('persistance sur disque', () {
    test('les données survivent à la fermeture et à la réouverture', () async {
      final dossier = await Directory.systemTemp.createTemp('gesco_test_');
      addTearDown(() async {
        if (await dossier.exists()) await dossier.delete(recursive: true);
      });
      final chemin = p.join(dossier.path, 'gesco.db');

      final premiere = await GescoDatabase.ouvrir(
        fabrique: databaseFactoryFfi,
        chemin: chemin,
      );
      final jeu = await creerJeu(premiere.db);
      await noter(premiere.db, jeu.inscription, jeu.matiere, 10, valeur: 1475);
      await premiere.fermer();

      final seconde = await GescoDatabase.ouvrir(
        fabrique: databaseFactoryFfi,
        chemin: chemin,
      );
      final notes = await seconde.db.query('note');
      expect(notes.length, 1);
      expect(notes.first['valeur'], 1475);
      expect((await seconde.db.query('eleve')).first['matricule'], 'M001');
      expect(await seconde.verifierIntegrite(), isEmpty);
      expect(await seconde.version(), GescoDatabase.versionSchema);
      await seconde.fermer();
    });

    test('un logo enregistré est relu à l\'identique', () async {
      // SQLite attend un Uint8List pour un BLOB (c'est ce que fournit l'application).
      final logo = Uint8List.fromList(List<int>.generate(256, (i) => i));
      await db.update('etablissement', {'nom': 'Lycée Test', 'logo': logo});
      final ligne = (await db.query('etablissement')).first;
      expect(ligne['nom'], 'Lycée Test');
      expect(ligne['logo'], logo);
    });
  });
}
