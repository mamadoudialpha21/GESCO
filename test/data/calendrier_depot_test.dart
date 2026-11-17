import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/depots/annee_depot.dart';
import 'package:gesco/data/depots/calendrier_depot.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Database db;
  late AnneeDepot annees;
  late CalendrierDepot calendriers;
  late int a1;

  setUp(() async {
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    db = gdb.db;
    annees = AnneeDepot(db);
    calendriers = CalendrierDepot(db);
    a1 = (await annees.creer('2026-2027')).id;
  });

  tearDown(() async => gdb.fermer());

  test('sans configuration : trois trimestres', () async {
    expect(await calendriers.lire(a1), Calendrier.trimestres);
  });

  test('enregistrer puis relire des semestres', () async {
    await calendriers.enregistrer(a1, Calendrier.semestres);
    final lu = await calendriers.lire(a1);
    expect(lu, Calendrier.semestres);
    expect(lu.periodes.length, 2);
  });

  test('enregistrer deux fois remplace la configuration', () async {
    await calendriers.enregistrer(a1, Calendrier.semestres);
    await calendriers.enregistrer(a1, Calendrier.trimestres);
    expect(await calendriers.lire(a1), Calendrier.trimestres);
    expect((await db.query('config_calendrier')).length, 1);
  });

  test('séquences et moyenne mensuelle sont conservées', () async {
    final c = Calendrier.trimestres.copyWith(
      sequences: Calendrier.sequencesProposees,
      moyenneMensuelle: false,
    );
    await calendriers.enregistrer(a1, c);
    final lu = await calendriers.lire(a1);
    expect(lu.sequencesActives, isTrue);
    expect(lu.moyenneMensuelle, isFalse);
    expect(lu, c);
  });

  test('un calendrier invalide est refusé avec la liste des problèmes', () async {
    const faux = Calendrier(
      type: TypePeriodes.personnalise,
      periodes: [PeriodeScolaire(cle: 'a', libelle: 'A', mois: [10, 11, 12])],
    );
    await expectLater(
      calendriers.enregistrer(a1, faux),
      throwsA(isA<ErreurGesco>()
          .having((e) => e.message, 'message', contains('Janvier n\'appartient'))),
    );
    expect(await db.query('config_calendrier'), isEmpty);
  });

  test('année inconnue refusée', () async {
    await expectLater(
      calendriers.enregistrer(999, Calendrier.semestres),
      throwsA(isA<ErreurGesco>()),
    );
  });

  test('réinitialiser revient aux trimestres', () async {
    await calendriers.enregistrer(a1, Calendrier.semestres);
    await calendriers.reinitialiser(a1);
    expect(await calendriers.lire(a1), Calendrier.trimestres);
  });

  test('un calendrier enregistré illisible donne un message clair', () async {
    await db.insert('config_calendrier', {'annee_id': a1, 'json': 'abîmé'});
    await expectLater(
      calendriers.lire(a1),
      throwsA(isA<ErreurGesco>().having((e) => e.message, 'message', contains('illisible'))),
    );
  });

  test('un calendrier qui ne passe plus la validation est signalé illisible', () async {
    await db.insert('config_calendrier', {
      'annee_id': a1,
      'json': '{"periodes":[{"cle":"a","libelle":"A","mois":[10]}]}',
    });
    await expectLater(calendriers.lire(a1), throwsA(isA<ErreurGesco>()));
  });

  test('créer une année en copiant une autre recopie le calendrier', () async {
    await calendriers.enregistrer(a1, Calendrier.semestres);
    final a2 = await annees.creer('2027-2028', copierDepuisAnneeId: a1);
    expect(await calendriers.lire(a2.id), Calendrier.semestres);
    // Les deux années sont indépendantes ensuite.
    await calendriers.enregistrer(a2.id, Calendrier.trimestres);
    expect(await calendriers.lire(a1), Calendrier.semestres);
  });

  test('créer une année sans copie : calendrier par défaut', () async {
    await calendriers.enregistrer(a1, Calendrier.semestres);
    final a2 = await annees.creer('2027-2028');
    expect(await calendriers.lire(a2.id), Calendrier.trimestres);
  });

  test('copier une année sans calendrier enregistré ne crée rien', () async {
    final a2 = await annees.creer('2027-2028', copierDepuisAnneeId: a1);
    expect(await db.query('config_calendrier', where: 'annee_id = ?', whereArgs: [a2.id]),
        isEmpty);
  });
}
