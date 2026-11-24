import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/depots/annee_depot.dart';
import 'package:gesco/data/depots/classe_depot.dart';
import 'package:gesco/data/depots/eleve_depot.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_securite.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher erreurContenant(String texte) => throwsA(
      isA<ErreurGesco>().having((e) => e.message, 'message', contains(texte)),
    );

EleveAImporter aImporter(
  String matricule,
  int classeId, {
  int ligne = 2,
  String nom = 'DIALLO',
  String prenom = 'Aminata',
  String sexe = 'F',
  String? naissance,
}) =>
    EleveAImporter(
      eleve: Eleve(
        matricule: matricule,
        nom: nom,
        prenom: prenom,
        sexe: sexe,
        dateNaissance: naissance,
        lieuNaissance: 'Conakry',
        telephone: '622000001',
      ),
      classeId: classeId,
      ligne: ligne,
    );

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Database db;
  late AnneeDepot annees;
  late ClasseDepot classes;
  late EleveDepot eleves;
  late int anneeId;
  late Classe classeA;
  late Classe classeB;

  setUp(() async {
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    db = gdb.db;
    final horloge = DateTime(2026, 10, 1, 8);
    annees = AnneeDepot(db, maintenant: () => horloge);
    classes = ClasseDepot(db);
    eleves = EleveDepot(db, maintenant: () => horloge);
    anneeId = (await annees.creer('2026-2027')).id;
    classeA = await classes.creer(anneeId: anneeId, nom: '10e A');
    classeB = await classes.creer(anneeId: anneeId, nom: '10e B');
  });

  tearDown(() async {
    await gdb.fermer();
  });

  Future<int> compterEleves() async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM eleve')).first['n'] as int;

  Future<int> compterInscriptions() async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM inscription')).first['n'] as int;

  Future<int> compterMouvements() async => (await db.rawQuery(
        "SELECT COUNT(*) AS n FROM mouvement_inscription WHERE type = 'inscription'",
      ))
          .first['n'] as int;

  group('importerLot', () {
    test('crée les élèves, leurs inscriptions et leurs mouvements', () async {
      final n = await eleves.importerLot(
        [
          aImporter('2026-0001', classeA.id, ligne: 6, nom: 'BARRY', prenom: 'Mamadou', sexe: 'M', naissance: '2011-03-05'),
          aImporter('2026-0002', classeA.id, ligne: 7),
          aImporter('2026-0003', classeB.id, ligne: 8, nom: 'SOW', prenom: 'Ali', sexe: 'M'),
        ],
        anneeId: anneeId,
        source: 'eleves.xlsx',
      );
      expect(n, 3);
      expect(await compterEleves(), 3);
      expect(await compterInscriptions(), 3);
      expect(await compterMouvements(), 3);

      final a = await eleves.lister(anneeId, classeId: classeA.id);
      expect(a.map((e) => e.matricule), ['2026-0001', '2026-0002']);
      expect(a.first.nom, 'BARRY');
      expect(a.first.dateNaissance, '2011-03-05');
      expect(a.first.statut, StatutInscription.inscrit);
      final b = await eleves.lister(anneeId, classeId: classeB.id);
      expect(b.single.nom, 'SOW');

      final fiches = await eleves.fichesInscrits(anneeId);
      final barry = fiches.firstWhere((f) => f.$1.matricule == '2026-0001').$1;
      expect(barry.lieuNaissance, 'Conakry');
      expect(barry.telephone, '622000001');
    });

    test('une erreur annule tout : aucun élève du lot n\'est enregistré', () async {
      await eleves.inscrire(
        const Eleve(matricule: '2026-0003', nom: 'EXISTANT', prenom: 'Deja', sexe: 'M'),
        anneeId: anneeId,
        classeId: classeA.id,
      );
      await expectLater(
        eleves.importerLot(
          [
            aImporter('2026-0001', classeA.id, ligne: 2),
            aImporter('2026-0002', classeA.id, ligne: 3, nom: 'BAH'),
            aImporter('2026-0003', classeA.id, ligne: 4, nom: 'SOW'),
          ],
          anneeId: anneeId,
        ),
        erreurContenant('Ligne 4 : Le matricule « 2026-0003 » est déjà utilisé.'),
      );
      expect(await compterEleves(), 1, reason: 'seul l\'élève déjà présent');
      expect(await compterInscriptions(), 1);
      expect(await compterMouvements(), 1);
    });

    test('le message annonce qu\'aucun élève n\'a été importé', () async {
      await expectLater(
        eleves.importerLot([aImporter('', classeA.id)], anneeId: anneeId),
        erreurContenant('Aucun élève n\'a été importé.'),
      );
    });

    test('matricule en double dans le lot (majuscules ignorées)', () async {
      await expectLater(
        eleves.importerLot(
          [
            aImporter('abc-1', classeA.id, ligne: 2),
            aImporter('ABC-1', classeA.id, ligne: 3, nom: 'BAH'),
          ],
          anneeId: anneeId,
        ),
        erreurContenant('Ligne 3'),
      );
      expect(await compterEleves(), 0);
    });

    test('fiche invalide : même règles que la saisie manuelle', () async {
      await expectLater(
        eleves.importerLot(
          [aImporter('2026-0001', classeA.id, ligne: 9, sexe: '')],
          anneeId: anneeId,
        ),
        erreurContenant('Ligne 9 : Le sexe'),
      );
      await expectLater(
        eleves.importerLot(
          [aImporter('2026-0001', classeA.id, ligne: 9, naissance: '2030-01-01')],
          anneeId: anneeId,
        ),
        erreurContenant('futur'),
      );
      expect(await compterEleves(), 0);
    });

    test('classe d\'une autre année : refusée', () async {
      final autre = await annees.creer('2027-2028');
      final classeAutre = await classes.creer(anneeId: autre.id, nom: '11e A');
      await expectLater(
        eleves.importerLot([aImporter('2026-0001', classeAutre.id)], anneeId: anneeId),
        erreurContenant('n\'existe pas pour l\'année scolaire'),
      );
      expect(await compterEleves(), 0);
    });

    test('année archivée : refusée', () async {
      final autre = await annees.creer('2027-2028');
      final classeAutre = await classes.creer(anneeId: autre.id, nom: '11e A');
      await annees.archiver(autre.id);
      await expectLater(
        eleves.importerLot([aImporter('2026-0001', classeAutre.id)], anneeId: autre.id),
        erreurContenant('archivée'),
      );
      expect(await compterEleves(), 0);
    });

    test('capacité : refusée, sauf dépassement demandé', () async {
      final petite = await classes.creer(
        anneeId: anneeId,
        nom: '9e A',
        reglages: const ReglagesClasse(capacite: 1),
      );
      await expectLater(
        eleves.importerLot(
          [
            aImporter('2026-0001', petite.id, ligne: 2),
            aImporter('2026-0002', petite.id, ligne: 3, nom: 'BAH'),
          ],
          anneeId: anneeId,
        ),
        erreurContenant('Ligne 3 : La classe « 9e A » est pleine'),
      );
      expect(await compterEleves(), 0, reason: 'le premier élève n\'est pas gardé non plus');

      final n = await eleves.importerLot(
        [
          aImporter('2026-0001', petite.id, ligne: 2),
          aImporter('2026-0002', petite.id, ligne: 3, nom: 'BAH'),
        ],
        anneeId: anneeId,
        depasserCapacite: true,
      );
      expect(n, 2);
      expect(await compterEleves(), 2);
    });

    test('lot vide : refusé', () async {
      await expectLater(
        eleves.importerLot(const [], anneeId: anneeId),
        erreurContenant('Aucun élève à importer'),
      );
    });

    test('un gros lot est enregistré en entier', () async {
      final lot = [
        for (var i = 1; i <= 300; i++)
          aImporter('2026-${i.toString().padLeft(4, '0')}', i.isEven ? classeA.id : classeB.id,
              ligne: i + 1, nom: 'ELEVE$i', prenom: 'Prénom$i'),
      ];
      expect(await eleves.importerLot(lot, anneeId: anneeId), 300);
      expect(await compterEleves(), 300);
      expect((await eleves.lister(anneeId, classeId: classeA.id)).length, 150);
    });
  });

  group('identites', () {
    test('tous les élèves, dossiers archivés compris, sans la photo', () async {
      final id = await eleves.inscrire(
        const Eleve(
          matricule: '2026-0001',
          nom: 'BARRY',
          prenom: 'Mamadou',
          sexe: 'M',
          dateNaissance: '2011-03-05',
        ),
        anneeId: anneeId,
        classeId: classeA.id,
      );
      await eleves.inscrire(
        const Eleve(matricule: '2026-0002', nom: 'DIALLO', prenom: 'Aminata', sexe: 'F'),
        anneeId: anneeId,
        classeId: classeB.id,
      );
      final liste = await eleves.lister(anneeId);
      final barry = liste.firstWhere((e) => e.inscriptionId == id);
      await db.update('eleve', {'archive': 1}, where: 'id = ?', whereArgs: [barry.eleveId]);

      final identites = await eleves.identites();
      expect(identites.map((i) => i.matricule).toSet(), {'2026-0001', '2026-0002'});
      final b = identites.firstWhere((i) => i.matricule == '2026-0001');
      expect(b.nom, 'BARRY');
      expect(b.dateNaissance, '2011-03-05');
      expect(b.archive, isTrue);
      expect(identites.firstWhere((i) => i.matricule == '2026-0002').archive, isFalse);
    });
  });

  group('droits d\'accès', () {
    Utilisateur compte(RoleUtilisateur role) => Utilisateur(
          id: 1,
          identifiant: 'u1',
          nomComplet: 'Compte test',
          role: role,
          actif: true,
          creeLe: '2026-01-01T00:00:00',
        );

    test('un compte sans le droit d\'importer est refusé, rien n\'est écrit', () async {
      final session = Session();
      final s = Services(gdb, session: session, iterations: 2);
      session.ouvrir(compte(RoleUtilisateur.administrateur));
      final a = (await s.annees.creer('2028-2029')).id;
      final c = await s.classes.creer(anneeId: a, nom: '6e A');

      session.ouvrir(compte(RoleUtilisateur.consultation));
      await expectLater(
        s.eleves.importerLot([aImporter('2028-0001', c.id)], anneeId: a),
        erreurContenant('pas l\'autorisation'),
      );
      expect(await compterEleves(), 0);

      session.ouvrir(compte(RoleUtilisateur.direction));
      expect(await s.eleves.importerLot([aImporter('2028-0001', c.id)], anneeId: a), 1);
      expect(await compterEleves(), 1);
    });
  });
}
