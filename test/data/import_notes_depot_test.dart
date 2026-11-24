import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/data/controle.dart';
import 'package:gesco/data/depots/annee_depot.dart';
import 'package:gesco/data/depots/classe_depot.dart';
import 'package:gesco/data/depots/eleve_depot.dart';
import 'package:gesco/data/depots/evaluation_depot.dart';
import 'package:gesco/data/depots/journal_depot.dart';
import 'package:gesco/data/depots/matiere_depot.dart';
import 'package:gesco/data/depots/note_depot.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_notation.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher erreurContenant(String texte) => throwsA(
      isA<ErreurGesco>().having((e) => e.message, 'message', contains(texte)),
    );

class _Autorisations implements Autorisations {
  const _Autorisations(this.permises, {this.limite});

  final Set<Permission> permises;
  final int? limite;

  @override
  bool peut(Permission p) => permises.contains(p);

  @override
  bool get aUtilisateur => true;

  @override
  int? get enseignantLimite => limite;
}

ColonneNotesAImporter colonne(
  Map<int, Saisie> notes, {
  int? evaluationId,
  String titre = 'Interrogation 1',
  TypeEvaluation type = TypeEvaluation.interrogation,
  int mois = 10,
  int bareme = 20,
  int coefficient = 100,
}) =>
    ColonneNotesAImporter(
      evaluationId: evaluationId,
      titre: titre,
      type: type,
      mois: mois,
      bareme: bareme,
      coefficient: coefficient,
      notes: notes,
    );

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Database db;
  late DateTime horloge;
  late AnneeDepot annees;
  late ClasseDepot classes;
  late MatiereDepot matieres;
  late EleveDepot eleves;
  late NoteDepot notes;
  late EvaluationDepot evaluations;
  late int anneeId;
  late Classe classeA;
  late Classe classeB;
  late MatiereClasse maths;
  late MatiereClasse matiereB;
  late int aminata;
  late int ibrahima;
  late int fatou;
  late int eleveB;

  setUp(() async {
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    db = gdb.db;
    horloge = DateTime(2026, 11, 5, 9, 30);
    annees = AnneeDepot(db, maintenant: () => horloge);
    classes = ClasseDepot(db);
    matieres = MatiereDepot(db);
    eleves = EleveDepot(db, maintenant: () => horloge);
    notes = NoteDepot(db, maintenant: () => horloge);
    evaluations = EvaluationDepot(db, notes: notes, maintenant: () => horloge);

    anneeId = (await annees.creer('2026-2027', activer: true)).id;
    classeA = await classes.creer(anneeId: anneeId, nom: '10e A');
    classeB = await classes.creer(anneeId: anneeId, nom: '10e B');
    maths = await matieres.ajouter(classeId: classeA.id, nom: 'Maths', coefficient: 400);
    matiereB = await matieres.ajouter(classeId: classeB.id, nom: 'Maths', coefficient: 400);

    Future<int> inscrire(String matricule, String nom, int classeId) => eleves.inscrire(
          Eleve(matricule: matricule, nom: nom, prenom: 'X', sexe: 'F'),
          anneeId: anneeId,
          classeId: classeId,
        );
    aminata = await inscrire('2026-0001', 'DIALLO', classeA.id);
    ibrahima = await inscrire('2026-0002', 'BARRY', classeA.id);
    fatou = await inscrire('2026-0004', 'CAMARA', classeA.id);
    eleveB = await inscrire('2026-0003', 'SOW', classeB.id);
  });

  tearDown(() async => gdb.fermer());

  Future<int> compterEvaluations() async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM evaluation')).first['n'] as int;

  Future<int> compterNotes() async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM evaluation_note')).first['n'] as int;

  Future<Evaluation> evaluer({String titre = 'Devoir 1', int mois = 10, int? bareme}) =>
      evaluations.creer(
        classeId: classeA.id,
        matiereId: maths.id,
        mois: mois,
        titre: titre,
        bareme: bareme,
        type: TypeEvaluation.devoir,
      );

  Future<ResultatImportNotes> importer(
    List<ColonneNotesAImporter> colonnes, {
    EvaluationDepot? depot,
  }) =>
      (depot ?? evaluations).importerNotes(
        classeId: classeA.id,
        matiereId: maths.id,
        colonnes: colonnes,
      );

  group('importerNotes : écriture', () {
    test('crée les évaluations et enregistre les notes en une opération', () async {
      final r = await importer([
        colonne({
          aminata: const Saisie.valeur(1450),
          ibrahima: const Saisie.absent(),
        }, coefficient: 200),
        colonne({
          aminata: const Saisie.surBareme(750, 10),
          fatou: const Saisie.dispense(),
        }, titre: 'Devoir 1', type: TypeEvaluation.devoir, mois: 11, bareme: 10),
      ]);
      expect(r.nbEvaluationsCreees, 2);
      expect(r.nbNotes, 4);
      expect(r.nbNotesRemplacees, 0);
      expect(r.evaluationIds, hasLength(2));

      final liste = await evaluations.lister(classeId: classeA.id, matiereId: maths.id);
      expect(liste, hasLength(2));
      final e1 = liste[0].evaluation;
      expect([e1.titre, e1.mois, e1.bareme, e1.coefficient, e1.type, e1.valide],
          ['Interrogation 1', 10, 20, 200, TypeEvaluation.interrogation, false]);
      final e2 = liste[1].evaluation;
      expect([e2.titre, e2.mois, e2.bareme, e2.coefficient, e2.type],
          ['Devoir 1', 11, 10, 100, TypeEvaluation.devoir]);

      expect(await evaluations.lireNotes(r.evaluationIds[0]), {
        aminata: const Saisie.valeur(1450),
        ibrahima: const Saisie.absent(),
      });
      expect(await evaluations.lireNotes(r.evaluationIds[1]), {
        aminata: const Saisie.surBareme(750, 10),
        fatou: const Saisie.dispense(),
      });
      expect(await compterNotes(), 4);
    });

    test('dans une évaluation existante : ajoute, et remplace seulement ce qui est donné', () async {
      final e = await evaluer();
      await evaluations.enregistrerLot(e.id, {
        aminata: const Saisie.valeur(1000),
        ibrahima: const Saisie.valeur(1100),
      });
      final r = await importer([
        colonne({
          aminata: const Saisie.valeur(1500),
          fatou: const Saisie.valeur(800),
        }, evaluationId: e.id),
      ]);
      expect(r.nbEvaluationsCreees, 0);
      expect(r.nbNotes, 2);
      expect(r.nbNotesRemplacees, 1);
      expect(r.evaluationIds, [e.id]);
      expect(await evaluations.lireNotes(e.id), {
        aminata: const Saisie.valeur(1500),
        ibrahima: const Saisie.valeur(1100),
        fatou: const Saisie.valeur(800),
      });
      expect(await compterEvaluations(), 1);
    });

    test('les remplacements restent dans l\'historique des notes', () async {
      final e = await evaluer();
      await evaluations.enregistrerLot(e.id, {aminata: const Saisie.valeur(1000)});
      await importer([
        colonne({aminata: const Saisie.valeur(1500)}, evaluationId: e.id),
      ]);
      final h = await notes.historique(classeId: classeA.id, source: 'evaluation');
      expect([for (final x in h) x.operation], ['modification', 'creation']);
      expect(h.first.ancienTexte, '10,00 / 20');
      expect(h.first.nouveauTexte, '15,00 / 20');
    });

    test('réimporter les mêmes notes ne change rien', () async {
      final premier = await importer([
        colonne({aminata: const Saisie.valeur(1450)}),
      ]);
      final id = premier.evaluationIds.single;
      final avant = await notes.compterHistorique();
      await importer([
        colonne({aminata: const Saisie.valeur(1450)}, evaluationId: id),
      ]);
      expect(await compterEvaluations(), 1);
      expect(await compterNotes(), 1);
      expect(await notes.compterHistorique(), avant);
    });
  });

  group('importerNotes : tout ou rien', () {
    test('une évaluation validée refuse tout, même les colonnes valides avant elle', () async {
      final validee = await evaluer(titre: 'Validée');
      await evaluations.enregistrerLot(validee.id, {aminata: const Saisie.valeur(1000)});
      await evaluations.valider(validee.id);
      final avant = await compterEvaluations();
      await expectLater(
        importer([
          colonne({aminata: const Saisie.valeur(1450)}),
          colonne({aminata: const Saisie.valeur(1200)}, evaluationId: validee.id),
        ]),
        erreurContenant('est validée'),
      );
      expect(await compterEvaluations(), avant);
      expect(await compterNotes(), 1);
      expect(await evaluations.lireNotes(validee.id), {aminata: const Saisie.valeur(1000)});
    });

    test('un mois verrouillé refuse la création et l\'écriture', () async {
      await notes.verrouiller(classeA.id, 11);
      await expectLater(
        importer([
          colonne({aminata: const Saisie.valeur(1450)}),
          colonne({aminata: const Saisie.valeur(1200)}, titre: 'Devoir 1', mois: 11),
        ]),
        erreurContenant('Novembre est verrouillé'),
      );
      expect(await compterEvaluations(), 0);
      expect(await compterNotes(), 0);

      final e = await evaluer(titre: 'En octobre');
      await notes.verrouiller(classeA.id, 10);
      await expectLater(
        importer([colonne({aminata: const Saisie.valeur(900)}, evaluationId: e.id)]),
        erreurContenant('Octobre est verrouillé'),
      );
      expect(await compterNotes(), 0);
    });

    test('un élève parti, ou d\'une autre classe, refuse tout le fichier', () async {
      await eleves.enregistrerSortie(fatou, StatutInscription.depart);
      await expectLater(
        importer([
          colonne({aminata: const Saisie.valeur(1450), fatou: const Saisie.valeur(900)}),
        ]),
        erreurContenant('ne suit pas (ou plus) cette classe'),
      );
      await expectLater(
        importer([
          colonne({aminata: const Saisie.valeur(1450), eleveB: const Saisie.valeur(900)}),
        ]),
        erreurContenant('ne suit pas (ou plus) cette classe'),
      );
      expect(await compterEvaluations(), 0);
      expect(await compterNotes(), 0);
    });

    test('une évaluation de même titre et de même mois existe déjà : refusé', () async {
      await evaluer(titre: 'Interrogation 1');
      await expectLater(
        importer([colonne({aminata: const Saisie.valeur(1450)}, titre: 'interrogation 1')]),
        erreurContenant('existe déjà'),
      );
      expect(await compterEvaluations(), 1);
      expect(await compterNotes(), 0);
    });

    test('deux colonnes pour la même évaluation : refusé', () async {
      final e = await evaluer();
      await expectLater(
        importer([
          colonne({aminata: const Saisie.valeur(1000)}, evaluationId: e.id),
          colonne({aminata: const Saisie.valeur(1100)}, evaluationId: e.id),
        ]),
        erreurContenant('même évaluation'),
      );
      expect(await compterNotes(), 0);
    });

    test('une note sur un autre barème que celui de l\'évaluation est refusée', () async {
      final sur10 = await evaluer(titre: 'Sur 10', bareme: 10);
      await expectLater(
        importer([
          colonne({aminata: const Saisie.valeur(1450)}),
          colonne({aminata: const Saisie.valeur(1450)}, evaluationId: sur10.id),
        ]),
        erreurContenant('notée sur 10'),
      );
      expect(await compterEvaluations(), 1);
      expect(await compterNotes(), 0);
    });

    test('une évaluation d\'une autre matière ou d\'une autre classe est refusée', () async {
      final autre = await evaluations.creer(
        classeId: classeB.id,
        matiereId: matiereB.id,
        mois: 10,
        titre: 'Autre classe',
      );
      await expectLater(
        importer([colonne({aminata: const Saisie.valeur(1000)}, evaluationId: autre.id)]),
        erreurContenant('n\'appartient pas à cette matière'),
      );
      await expectLater(
        evaluations.importerNotes(
          classeId: classeA.id,
          matiereId: matiereB.id,
          colonnes: [colonne({aminata: const Saisie.valeur(1000)})],
        ),
        erreurContenant('n\'appartient pas à la classe'),
      );
      expect(await compterNotes(), 0);
    });

    test('titre, mois, coefficient et barème invalides ; rien à importer', () async {
      final n = {aminata: const Saisie.valeur(1000)};
      await expectLater(importer([colonne(n, titre: '  ')]), erreurContenant('titre'));
      await expectLater(importer([colonne(n, mois: 7)]), erreurContenant('hors de l\'année'));
      await expectLater(importer([colonne(n, coefficient: 0)]), erreurContenant('coefficient'));
      await expectLater(importer([colonne(n, bareme: 0)]), erreurContenant('barème'));
      await expectLater(importer(const []), erreurContenant('Aucune note à importer'));
      await expectLater(importer([colonne(const {})]), erreurContenant('Aucune note à importer'));
      expect(await compterEvaluations(), 0);
    });
  });

  group('importerNotes : droits et journal', () {
    EvaluationDepot avec(Set<Permission> permises, {int? limite, Controle? controle}) =>
        EvaluationDepot(
          db,
          notes: notes,
          controle: controle ?? Controle(autorisations: _Autorisations(permises, limite: limite)),
          maintenant: () => horloge,
        );

    test('il faut la permission d\'importer, de saisir et, pour créer, de gérer les évaluations',
        () async {
      final n = {aminata: const Saisie.valeur(1000)};
      await expectLater(
        importer([colonne(n)], depot: avec({Permission.notesSaisir})),
        erreurContenant('pas l\'autorisation'),
      );
      await expectLater(
        importer([colonne(n)], depot: avec({Permission.importExport})),
        erreurContenant('pas l\'autorisation'),
      );
      await expectLater(
        importer(
          [colonne(n)],
          depot: avec({Permission.importExport, Permission.notesSaisir}),
        ),
        erreurContenant('pas l\'autorisation'),
      );
      expect(await compterEvaluations(), 0);

      // Sans création, importer et saisir suffisent.
      final e = await evaluer();
      final r = await importer(
        [colonne(n, evaluationId: e.id)],
        depot: avec({Permission.importExport, Permission.notesSaisir}),
      );
      expect(r.nbNotes, 1);
      // Avec les trois permissions, la création est possible.
      final r2 = await importer(
        [colonne(n, titre: 'Nouvelle')],
        depot: avec({
          Permission.importExport,
          Permission.notesSaisir,
          Permission.evaluationsGerer,
        }),
      );
      expect(r2.nbEvaluationsCreees, 1);
    });

    test('un enseignant limité à d\'autres matières est refusé', () async {
      await expectLater(
        importer(
          [colonne({aminata: const Saisie.valeur(1000)})],
          depot: avec({
            Permission.importExport,
            Permission.notesSaisir,
            Permission.evaluationsGerer,
          }, limite: 99),
        ),
        erreurContenant('matières qui vous sont confiées'),
      );
      expect(await compterEvaluations(), 0);
    });

    test('la création des évaluations et l\'import sont inscrits au journal', () async {
      final journal = JournalDepot(db);
      final depot = avec(const {}, controle: Controle(journal: journal));
      await importer([
        colonne({aminata: const Saisie.valeur(1450), ibrahima: const Saisie.valeur(1000)}),
      ], depot: depot);
      final lignes = await db.query('journal', where: "entite = 'evaluation'", orderBy: 'id');
      expect([for (final l in lignes) l['action']], ['creation', 'import_notes']);
      expect(lignes.first['details'], 'Interrogation 1 (Octobre)');
      expect(lignes.last['details'], '2 notes importées dans 1 évaluation');
    });
  });
}
