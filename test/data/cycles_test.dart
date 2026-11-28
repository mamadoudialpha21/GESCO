import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/depots/annee_depot.dart';
import 'package:gesco/data/depots/calendrier_depot.dart';
import 'package:gesco/data/depots/classe_depot.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/schema.dart';
import 'package:gesco/data/schema_v2.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/niveaux.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher refus(String texte) =>
    throwsA(isA<ErreurGesco>().having((e) => e.message, 'message', contains(texte)));

void main() {
  sqfliteFfiInit();

  group('classes rattachées au catalogue', () {
    late GescoDatabase gdb;
    late ClasseDepot classes;
    late AnneeDepot annees;
    late CalendrierDepot calendriers;
    late int a1;

    setUp(() async {
      gdb = await GescoDatabase.ouvrir(
        fabrique: databaseFactoryFfi,
        chemin: inMemoryDatabasePath,
      );
      classes = ClasseDepot(gdb.db);
      annees = AnneeDepot(gdb.db);
      calendriers = CalendrierDepot(gdb.db);
      a1 = (await annees.creer('2026-2027')).id;
    });

    tearDown(() async => gdb.fermer());

    test('créer une classe de chaque cycle', () async {
      final p3 = await classes.creer(anneeId: a1, nom: '3e A', niveauCode: 3);
      final c8 = await classes.creer(anneeId: a1, nom: '8e B', niveauCode: 8);
      final l13 = await classes.creer(
        anneeId: a1,
        nom: 'Tle SM',
        niveauCode: 13,
        serie: SerieLycee.sciencesMathematiques,
      );
      expect(p3.cycle, Cycle.primaire);
      expect(c8.cycle, Cycle.college);
      expect(l13.cycle, Cycle.lycee);
      expect(p3.niveau, '3ème année');
      expect(l13.niveau, 'Terminale');
      expect(l13.serie, SerieLycee.sciencesMathematiques);
      expect(l13.libelleNiveau, 'Terminale · Sciences mathématiques');

      // Relues depuis la base.
      final relues = {for (final r in await classes.lister(a1)) r.classe.nom: r.classe};
      expect(relues['3e A']!.cycle, Cycle.primaire);
      expect(relues['8e B']!.niveauCode, 8);
      expect(relues['8e B']!.serie, isNull);
      expect(relues['Tle SM']!.serie, SerieLycee.sciencesMathematiques);
      expect(relues['Tle SM']!.niveauScolaire!.libelle, 'Terminale');
    });

    test('les trois options du lycée', () async {
      for (final s in SerieLycee.values) {
        final c = await classes.creer(
          anneeId: a1,
          nom: '11e ${s.code}',
          niveauCode: 11,
          serie: s,
        );
        expect((await classes.obtenir(c.id))!.serie, s);
      }
      // Une même option peut exister dans plusieurs niveaux.
      await classes.creer(
        anneeId: a1,
        nom: '12e SM',
        niveauCode: 12,
        serie: SerieLycee.sciencesMathematiques,
      );
    });

    test('lycée sans option : accepté', () async {
      final c = await classes.creer(anneeId: a1, nom: '11e A', niveauCode: 11);
      expect(c.serie, isNull);
      expect(c.libelleNiveau, '11ème année');
    });

    test('une option est refusée hors du lycée', () async {
      await expectLater(
        classes.creer(
          anneeId: a1,
          nom: '9e A',
          niveauCode: 9,
          serie: SerieLycee.sciencesSociales,
        ),
        refus('n\'existe que pour le lycée'),
      );
      await expectLater(
        classes.creer(anneeId: a1, nom: '2e A', niveauCode: 2, serie: SerieLycee.sciencesSociales),
        refus('n\'existe que pour le lycée'),
      );
      expect(await classes.lister(a1), isEmpty);
    });

    test('une option sans niveau du catalogue est refusée', () async {
      await expectLater(
        classes.creer(anneeId: a1, nom: 'X', niveau: 'Terminale', serie: SerieLycee.sciencesSociales),
        refus('Choisissez le niveau'),
      );
    });

    test('niveau inconnu refusé', () async {
      await expectLater(classes.creer(anneeId: a1, nom: 'X', niveauCode: 0), refus('Niveau inconnu'));
      await expectLater(classes.creer(anneeId: a1, nom: 'X', niveauCode: 17), refus('Niveau inconnu'));
    });

    test('le niveau du catalogue remplace le texte saisi', () async {
      final c = await classes.creer(anneeId: a1, nom: 'A', niveau: 'n\'importe quoi', niveauCode: 5);
      expect(c.niveau, '5ème année');
    });

    test('classe hors catalogue : texte libre, aucun cycle', () async {
      final c = await classes.creer(anneeId: a1, nom: 'Maternelle', niveau: 'Maternelle');
      expect(c.niveauCode, isNull);
      expect(c.cycle, isNull);
      expect(c.libelleNiveau, 'Maternelle');
    });

    test('modifier : changer de niveau et d\'option', () async {
      final c = await classes.creer(anneeId: a1, nom: 'Tle', niveauCode: 13, serie: SerieLycee.sciencesSociales);
      await classes.modifier(
        c.id,
        nom: 'Tle SE',
        niveau: '',
        niveauCode: 13,
        serie: SerieLycee.sciencesExperimentales,
      );
      expect((await classes.obtenir(c.id))!.serie, SerieLycee.sciencesExperimentales);

      await classes.modifier(c.id, nom: 'Tle SE', niveau: '', niveauCode: 10);
      final apres = (await classes.obtenir(c.id))!;
      expect(apres.cycle, Cycle.college);
      expect(apres.serie, isNull, reason: 'l\'option disparaît hors du lycée');

      await expectLater(
        classes.modifier(c.id, nom: 'Tle SE', niveau: '', niveauCode: 10, serie: SerieLycee.sciencesSociales),
        refus('n\'existe que pour le lycée'),
      );

      await classes.modifier(c.id, nom: 'Libre', niveau: 'Autre');
      final libre = (await classes.obtenir(c.id))!;
      expect(libre.niveauCode, isNull);
      expect(libre.niveau, 'Autre');
    });

    test('la liste est triée par niveau (pas par ordre alphabétique du texte)', () async {
      await classes.creer(anneeId: a1, nom: 'Tle SM', niveauCode: 13, serie: SerieLycee.sciencesMathematiques);
      await classes.creer(anneeId: a1, nom: '10e A', niveauCode: 10);
      await classes.creer(anneeId: a1, nom: 'Libre', niveau: 'Crèche');
      await classes.creer(anneeId: a1, nom: '2e A', niveauCode: 2);
      await classes.creer(anneeId: a1, nom: '7e A', niveauCode: 7);
      await classes.creer(anneeId: a1, nom: 'Tle SE', niveauCode: 13, serie: SerieLycee.sciencesExperimentales);
      final noms = [for (final r in await classes.lister(a1)) r.classe.nom];
      expect(noms, ['2e A', '7e A', '10e A', 'Tle SE', 'Tle SM', 'Libre']);
    });

    test('copie d\'une année : niveaux, options et calendriers par cycle', () async {
      await classes.creer(anneeId: a1, nom: '12e SS', niveauCode: 12, serie: SerieLycee.sciencesSociales);
      await classes.creer(anneeId: a1, nom: '4e A', niveauCode: 4);
      await calendriers.enregistrer(a1, Calendrier.semestres, cycle: Cycle.college);
      final a2 = (await annees.creer('2027-2028', copierDepuisAnneeId: a1)).id;

      final copiees = {for (final r in await classes.lister(a2)) r.classe.nom: r.classe};
      expect(copiees['12e SS']!.niveauCode, 12);
      expect(copiees['12e SS']!.serie, SerieLycee.sciencesSociales);
      expect(copiees['4e A']!.cycle, Cycle.primaire);

      expect(await calendriers.lire(a2, cycle: Cycle.college), Calendrier.semestres);
      expect(await calendriers.lire(a2, cycle: Cycle.primaire), Calendrier.compositions);
      expect(await calendriers.lire(a2, cycle: Cycle.lycee), Calendrier.semestresCompo);
    });

    test('la base refuse une option inconnue ou un niveau hors catalogue', () async {
      final db = gdb.db;
      await expectLater(
        db.insert('classe', {'annee_id': a1, 'nom': 'X', 'serie': 'ZZ'}),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.insert('classe', {'annee_id': a1, 'nom': 'Y', 'niveau_code': 17}),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('calendrier par cycle', () {
    late GescoDatabase gdb;
    late CalendrierDepot calendriers;
    late AnneeDepot annees;
    late int a1;

    setUp(() async {
      gdb = await GescoDatabase.ouvrir(
        fabrique: databaseFactoryFfi,
        chemin: inMemoryDatabasePath,
      );
      calendriers = CalendrierDepot(gdb.db);
      annees = AnneeDepot(gdb.db);
      a1 = (await annees.creer('2026-2027')).id;
    });

    tearDown(() async => gdb.fermer());

    test('sans configuration : maternelle et primaire 3 compositions, collège et lycée 2 semestres', () async {
      expect((await calendriers.lire(a1, cycle: Cycle.maternelle)).periodes.length, 3);
      expect((await calendriers.lire(a1, cycle: Cycle.primaire)).periodes.length, 3);
      expect((await calendriers.lire(a1, cycle: Cycle.college)).periodes.length, 2);
      expect((await calendriers.lire(a1, cycle: Cycle.lycee)).periodes.length, 2);
      expect((await calendriers.lire(a1)).periodes.length, 3, reason: 'calendrier général');
    });

    test('chaque cycle a son calendrier, indépendant des autres', () async {
      await calendriers.enregistrer(a1, Calendrier.semestres, cycle: Cycle.lycee);
      expect(await calendriers.lire(a1, cycle: Cycle.lycee), Calendrier.semestres);
      expect(await calendriers.lire(a1, cycle: Cycle.college), Calendrier.semestresCompo);
      expect(await calendriers.lire(a1, cycle: Cycle.primaire), Calendrier.compositions);
      expect(await calendriers.lire(a1), Calendrier.trimestres);

      await calendriers.enregistrer(a1, Calendrier.semestres);
      expect(await calendriers.lire(a1), Calendrier.semestres);
      expect(await calendriers.lire(a1, cycle: Cycle.primaire), Calendrier.compositions);
    });

    test('réenregistrer remplace, réinitialiser revient au modèle du cycle', () async {
      await calendriers.enregistrer(a1, Calendrier.trimestres, cycle: Cycle.college);
      expect((await calendriers.lire(a1, cycle: Cycle.college)).periodes.length, 3);
      await calendriers.enregistrer(a1, Calendrier.semestres, cycle: Cycle.college);
      expect(await calendriers.lire(a1, cycle: Cycle.college), Calendrier.semestres);
      await calendriers.reinitialiser(a1, cycle: Cycle.college);
      expect(await calendriers.lire(a1, cycle: Cycle.college), Calendrier.semestresCompo);
    });

    test('lireTous regroupe tout en une fois', () async {
      await calendriers.enregistrer(a1, Calendrier.semestres, cycle: Cycle.college);
      await calendriers.enregistrer(a1, Calendrier.semestres);
      final tous = await calendriers.lireTous(a1);
      expect(tous.pour(Cycle.college), Calendrier.semestres);
      expect(tous.pour(Cycle.primaire), Calendrier.compositions);
      expect(tous.pour(Cycle.maternelle), Calendrier.compositions);
      expect(tous.pour(Cycle.lycee), Calendrier.semestresCompo);
      expect(tous.pour(null), Calendrier.semestres);
    });

    test('un calendrier invalide est refusé', () async {
      const mauvais = Calendrier(type: TypePeriodes.personnalise, periodes: []);
      await expectLater(
        calendriers.enregistrer(a1, mauvais, cycle: Cycle.primaire),
        throwsA(isA<ErreurGesco>()),
      );
      expect((await calendriers.lire(a1, cycle: Cycle.primaire)).periodes.length, 3);
    });

    test('année inconnue refusée', () async {
      await expectLater(
        calendriers.enregistrer(999, Calendrier.semestres, cycle: Cycle.college),
        refus('Année scolaire introuvable'),
      );
    });

    test('contenu illisible : message clair avec le cycle', () async {
      await gdb.db.insert('config_calendrier_cycle',
          {'annee_id': a1, 'cycle': 'college', 'json': '{pas du json'});
      await expectLater(
        calendriers.lire(a1, cycle: Cycle.college),
        refus('(Collège)'),
      );
      await expectLater(calendriers.lireTous(a1), refus('illisible'));
      // Les autres cycles restent lisibles.
      expect(await calendriers.lire(a1, cycle: Cycle.primaire), Calendrier.compositions);
    });

    test('supprimer l\'année supprime ses calendriers par cycle', () async {
      final a2 = (await annees.creer('2027-2028')).id;
      await calendriers.enregistrer(a2, Calendrier.semestres, cycle: Cycle.college);
      await annees.supprimer(a2);
      expect(await gdb.db.query('config_calendrier_cycle', where: 'annee_id = ?', whereArgs: [a2]),
          isEmpty);
    });
  });

  group('mise à jour d\'une base de la version 2', () {
    late Directory dossier;
    late String chemin;

    Future<void> creerBaseV2() async {
      final v2 = await databaseFactoryFfi.openDatabase(
        chemin,
        options: OpenDatabaseOptions(
          version: 2,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, v) async {
            for (final instruction in schemaV1) {
              await db.execute(instruction);
            }
            await db.insert('etablissement', {'id': 1});
            for (final instruction in migrationV2) {
              await db.execute(instruction);
            }
          },
        ),
      );
      final a1 = await v2.insert('annee_scolaire',
          {'libelle': '2025-2026', 'active': 0, 'cree_le': '2025-10-01', 'archivee': 1});
      final a2 = await v2.insert(
          'annee_scolaire', {'libelle': '2026-2027', 'active': 1, 'cree_le': '2026-10-01'});
      // Calendrier personnalisé de la première année seulement.
      await v2.insert('config_calendrier',
          {'annee_id': a1, 'json': Calendrier.semestres.toJsonString()});
      for (final (nom, niveau) in [
        ('10e A', '10e année'),
        ('6e B', 'Sixième'),
        ('Tle SM', 'Terminale'),
        ('12e SS', '12ème année'),
        ('Maternelle', 'Maternelle'),
        ('Sans niveau', ''),
      ]) {
        await v2.insert('classe', {'annee_id': a2, 'niveau': niveau, 'nom': nom});
      }
      await v2.close();
    }

    setUp(() async {
      dossier = await Directory.systemTemp.createTemp('gesco_migration3_');
      chemin = p.join(dossier.path, 'gesco.db');
      await creerBaseV2();
    });

    tearDown(() async {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    });

    test('niveaux reconnus, calendriers existants conservés pour chaque cycle', () async {
      final gdb = await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
      expect(await gdb.version(), GescoDatabase.versionSchema);
      expect(await gdb.verifierIntegrite(), isEmpty);

      final classes = ClasseDepot(gdb.db);
      final a2 = (await AnneeDepot(gdb.db).lister()).firstWhere((a) => a.libelle == '2026-2027');
      final c = {for (final r in await classes.lister(a2.id)) r.classe.nom: r.classe};
      expect(c['10e A']!.niveauCode, 10);
      expect(c['10e A']!.cycle, Cycle.college);
      expect(c['6e B']!.niveauCode, 6);
      expect(c['6e B']!.cycle, Cycle.primaire);
      expect(c['Tle SM']!.niveauCode, 13);
      expect(c['Tle SM']!.serie, SerieLycee.sciencesMathematiques,
          reason: 'l\'option est lue dans le nom de la classe');
      expect(c['12e SS']!.serie, SerieLycee.sciencesSociales);
      expect(c['Maternelle']!.niveauCode, isNull);
      expect(c['Sans niveau']!.niveauCode, isNull);
      // Le texte saisi n'est pas modifié.
      expect(c['10e A']!.niveau, '10e année');
      expect(c['Maternelle']!.niveau, 'Maternelle');

      // Année déjà configurée : son calendrier reste le même pour tous les cycles.
      final calendriers = CalendrierDepot(gdb.db);
      final a1 = (await AnneeDepot(gdb.db).lister()).firstWhere((a) => a.libelle == '2025-2026');
      for (final cycle in [Cycle.primaire, Cycle.college, Cycle.lycee]) {
        expect(await calendriers.lire(a1.id, cycle: cycle), Calendrier.semestres,
            reason: cycle.libelle);
      }
      expect(await calendriers.lire(a1.id), Calendrier.semestres);
      // Année jamais configurée : modèles par cycle.
      expect(await calendriers.lire(a2.id, cycle: Cycle.primaire), Calendrier.compositions);
      expect(await calendriers.lire(a2.id, cycle: Cycle.college), Calendrier.semestresCompo);
      await gdb.fermer();
    });

    test('rouvrir la base ne refait pas la migration', () async {
      var gdb = await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
      await gdb.fermer();
      gdb = await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: chemin);
      expect(await gdb.version(), GescoDatabase.versionSchema);
      final n = await gdb.db.rawQuery('SELECT COUNT(*) AS n FROM config_calendrier_cycle');
      expect(n.first['n'], 3, reason: 'un seul calendrier existant, copié trois fois');
      await gdb.fermer();
    });
  });
}
