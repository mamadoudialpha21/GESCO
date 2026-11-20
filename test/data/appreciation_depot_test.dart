import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/controle.dart';
import 'package:gesco/data/depots/annee_depot.dart';
import 'package:gesco/data/depots/appreciation_depot.dart';
import 'package:gesco/data/depots/classe_depot.dart';
import 'package:gesco/data/depots/eleve_depot.dart';
import 'package:gesco/data/depots/matiere_depot.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher erreurContenant(String texte) => throwsA(
      isA<ErreurGesco>().having((e) => e.message, 'message', contains(texte)),
    );

class _Autorisations implements Autorisations {
  const _Autorisations(this.permises);

  final Set<Permission> permises;

  @override
  bool peut(Permission p) => permises.contains(p);

  @override
  bool get aUtilisateur => true;

  @override
  int? get enseignantLimite => null;
}

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Database db;
  late AppreciationDepot app;
  late AnneeDepot annees;
  late int anneeId;
  late Classe classeA;
  late Classe classeB;
  late MatiereClasse maths;
  late MatiereClasse francais;
  late MatiereClasse mathsB;
  late int aminata;
  late int ibrahima;
  late int eleveB;

  setUp(() async {
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    db = gdb.db;
    annees = AnneeDepot(db);
    final classes = ClasseDepot(db);
    final matieres = MatiereDepot(db);
    final eleves = EleveDepot(db);
    app = AppreciationDepot(db);

    anneeId = (await annees.creer('2026-2027')).id;
    classeA = await classes.creer(anneeId: anneeId, nom: '10e A');
    classeB = await classes.creer(anneeId: anneeId, nom: '10e B');
    maths = await matieres.ajouter(classeId: classeA.id, nom: 'Maths', coefficient: 400);
    francais = await matieres.ajouter(classeId: classeA.id, nom: 'Français', coefficient: 300);
    mathsB = await matieres.ajouter(classeId: classeB.id, nom: 'Maths', coefficient: 400);

    Future<int> inscrire(String matricule, String nom, int classeId) => eleves.inscrire(
          Eleve(matricule: matricule, nom: nom, prenom: 'X', sexe: 'F'),
          anneeId: anneeId,
          classeId: classeId,
        );
    aminata = await inscrire('2026-0001', 'DIALLO', classeA.id);
    ibrahima = await inscrire('2026-0002', 'BARRY', classeA.id);
    eleveB = await inscrire('2026-0003', 'SOW', classeB.id);
  });

  tearDown(() async => gdb.fermer());

  group('appréciation générale et décision du conseil', () {
    test('enregistrer puis relire, par période et par classe', () async {
      await app.enregistrerEleves({
        aminata: const AppreciationEleve(
          appreciation: 'Élève sérieuse, bons résultats.',
          decision: 'Félicitations du conseil',
        ),
        ibrahima: const AppreciationEleve(appreciation: 'Peut mieux faire.'),
      }, 't1');
      await app.enregistrerEleves({
        aminata: const AppreciationEleve(appreciation: 'Trimestre 2 : en progrès.'),
      }, 't2');

      final t1 = await app.eleves(classeA.id, 't1');
      expect(t1.length, 2);
      expect(t1[aminata]!.appreciation, 'Élève sérieuse, bons résultats.');
      expect(t1[aminata]!.decision, 'Félicitations du conseil');
      expect(t1[ibrahima]!.decision, '');
      final t2 = await app.eleves(classeA.id, 't2');
      expect(t2.keys, [aminata]);
      expect(await app.eleves(classeB.id, 't1'), isEmpty);
      expect(await app.eleves(classeA.id, 'annee'), isEmpty);
    });

    test('modifier remplace, les espaces autour sont retirés', () async {
      await app.enregistrerEleves({
        aminata: const AppreciationEleve(appreciation: 'Premier avis'),
      }, 't1');
      await app.enregistrerEleves({
        aminata: const AppreciationEleve(appreciation: '  Nouvel avis  ', decision: ' Encouragements '),
      }, 't1');
      final v = (await app.eleves(classeA.id, 't1'))[aminata]!;
      expect(v.appreciation, 'Nouvel avis');
      expect(v.decision, 'Encouragements');
    });

    test('un texte vide efface la ligne', () async {
      await app.enregistrerEleves({
        aminata: const AppreciationEleve(appreciation: 'Avis', decision: 'Décision'),
      }, 't1');
      await app.enregistrerEleves({aminata: const AppreciationEleve()}, 't1');
      expect(await app.eleves(classeA.id, 't1'), isEmpty);
      expect(await db.query('appreciation_eleve'), isEmpty);
    });

    test('liste vide : rien à faire', () async {
      await app.enregistrerEleves({}, 't1');
      expect(await db.query('appreciation_eleve'), isEmpty);
    });

    test('textes trop longs refusés, rien n\'est enregistré', () async {
      await expectLater(
        app.enregistrerEleves({
          aminata: const AppreciationEleve(appreciation: 'bon'),
          ibrahima: AppreciationEleve(appreciation: 'x' * (AppreciationDepot.longueurMaxGenerale + 1)),
        }, 't1'),
        erreurContenant('trop longue'),
      );
      await expectLater(
        app.enregistrerEleves({
          aminata: AppreciationEleve(decision: 'x' * (AppreciationDepot.longueurMaxDecision + 1)),
        }, 't1'),
        erreurContenant('décision'),
      );
      expect(await db.query('appreciation_eleve'), isEmpty);
    });

    test('les longueurs maximales exactes sont acceptées', () async {
      await app.enregistrerEleves({
        aminata: AppreciationEleve(
          appreciation: 'x' * AppreciationDepot.longueurMaxGenerale,
          decision: 'y' * AppreciationDepot.longueurMaxDecision,
        ),
      }, 'annee');
      expect((await app.eleves(classeA.id, 'annee'))[aminata]!.appreciation.length,
          AppreciationDepot.longueurMaxGenerale);
    });

    test('élève inconnu : tout est refusé (opération atomique)', () async {
      await expectLater(
        app.enregistrerEleves({
          aminata: const AppreciationEleve(appreciation: 'Avis'),
          9999: const AppreciationEleve(appreciation: 'Fantôme'),
        }, 't1'),
        erreurContenant('introuvable'),
      );
      expect(await db.query('appreciation_eleve'), isEmpty);
    });

    test('clé de période invalide refusée', () async {
      for (final cle in ['', 'T1', 'à', 'x y', 'a' * 21, '1t']) {
        await expectLater(
          app.enregistrerEleves({aminata: const AppreciationEleve(appreciation: 'a')}, cle),
          erreurContenant('Période'),
          reason: 'clé « $cle »',
        );
      }
    });

    test('clés usuelles acceptées : mois, trimestre, séquence, année', () async {
      for (final cle in ['m10', 't1', 's2', 'q3', 'annee']) {
        await app.enregistrerEleves({aminata: AppreciationEleve(appreciation: cle)}, cle);
      }
      expect((await db.query('appreciation_eleve')).length, 5);
    });
  });

  group('appréciations par matière', () {
    test('enregistrer plusieurs matières puis relire', () async {
      await app.enregistrerMatieres(aminata, 't1', {
        maths.id: 'Très bon travail.',
        francais.id: 'Doit lire davantage.',
      });
      await app.enregistrerMatieres(ibrahima, 't1', {maths.id: 'Moyen.'});
      final lues = await app.matieres(classeA.id, 't1');
      expect(lues[aminata], {maths.id: 'Très bon travail.', francais.id: 'Doit lire davantage.'});
      expect(lues[ibrahima], {maths.id: 'Moyen.'});
      expect(await app.matieres(classeA.id, 't2'), isEmpty);
      expect(await app.matieres(classeB.id, 't1'), isEmpty);
    });

    test('un texte vide efface seulement cette matière', () async {
      await app.enregistrerMatieres(aminata, 't1', {maths.id: 'Bien', francais.id: 'Assez bien'});
      await app.enregistrerMatieres(aminata, 't1', {maths.id: '   '});
      expect((await app.matieres(classeA.id, 't1'))[aminata], {francais.id: 'Assez bien'});
    });

    test('une matière d\'une autre classe est refusée, rien n\'est enregistré', () async {
      await expectLater(
        app.enregistrerMatieres(aminata, 't1', {maths.id: 'ok', mathsB.id: 'intrus'}),
        erreurContenant('n\'appartient pas'),
      );
      expect(await db.query('appreciation_matiere'), isEmpty);
    });

    test('matière inconnue ou élève inconnu refusés', () async {
      await expectLater(app.enregistrerMatieres(aminata, 't1', {9999: 'x'}),
          erreurContenant('n\'appartient pas'));
      await expectLater(app.enregistrerMatieres(9999, 't1', {maths.id: 'x'}),
          erreurContenant('introuvable'));
    });

    test('texte trop long refusé', () async {
      await expectLater(
        app.enregistrerMatieres(
            aminata, 't1', {maths.id: 'x' * (AppreciationDepot.longueurMaxMatiere + 1)}),
        erreurContenant('trop longue'),
      );
    });

    test('supprimer un élève supprime ses appréciations', () async {
      await app.enregistrerMatieres(eleveB, 't1', {mathsB.id: 'Bien'});
      await app.enregistrerEleves({eleveB: const AppreciationEleve(appreciation: 'Avis')}, 't1');
      await db.delete('inscription', where: 'id = ?', whereArgs: [eleveB]);
      expect(await db.query('appreciation_matiere'), isEmpty);
      expect(await db.query('appreciation_eleve'), isEmpty);
    });
  });

  group('droits et année archivée', () {
    test('sans la permission, rien n\'est enregistré', () async {
      final sans = AppreciationDepot(
        db,
        controle: const Controle(autorisations: _Autorisations({})),
      );
      await expectLater(
        sans.enregistrerEleves({aminata: const AppreciationEleve(appreciation: 'a')}, 't1'),
        erreurContenant('autorisation'),
      );
      await expectLater(
        sans.enregistrerMatieres(aminata, 't1', {maths.id: 'a'}),
        erreurContenant('autorisation'),
      );
      expect(await db.query('appreciation_eleve'), isEmpty);
      expect(await db.query('appreciation_matiere'), isEmpty);
    });

    test('avec la permission, c\'est accepté', () async {
      final avec = AppreciationDepot(
        db,
        controle: const Controle(
          autorisations: _Autorisations({Permission.appreciationsSaisir}),
        ),
      );
      await avec.enregistrerEleves({aminata: const AppreciationEleve(appreciation: 'a')}, 't1');
      expect((await avec.eleves(classeA.id, 't1')).length, 1);
    });

    test('année archivée : les appréciations ne se modifient plus', () async {
      await app.enregistrerEleves({aminata: const AppreciationEleve(appreciation: 'Avant')}, 't1');
      // Une autre année doit être active avant d'archiver la première.
      final autre = await annees.creer('2027-2028');
      await annees.activer(autre.id);
      await annees.archiver(anneeId);

      await expectLater(
        app.enregistrerEleves({aminata: const AppreciationEleve(appreciation: 'Après')}, 't1'),
        erreurContenant('archivée'),
      );
      await expectLater(
        app.enregistrerMatieres(aminata, 't1', {maths.id: 'Après'}),
        erreurContenant('archivée'),
      );
      // La lecture reste possible et l'ancien texte est intact.
      expect((await app.eleves(classeA.id, 't1'))[aminata]!.appreciation, 'Avant');

      await annees.archiver(anneeId, archivee: false);
      await app.enregistrerEleves({aminata: const AppreciationEleve(appreciation: 'Rouverte')}, 't1');
      expect((await app.eleves(classeA.id, 't1'))[aminata]!.appreciation, 'Rouverte');
    });
  });
}
