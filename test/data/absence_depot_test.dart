import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/controle.dart';
import 'package:gesco/data/depots/absence_depot.dart';
import 'package:gesco/data/depots/annee_depot.dart';
import 'package:gesco/data/depots/classe_depot.dart';
import 'package:gesco/data/depots/eleve_depot.dart';
import 'package:gesco/data/depots/journal_depot.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_absences.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher erreurContenant(String texte) => throwsA(
      isA<ErreurGesco>().having((e) => e.message, 'message', contains(texte)),
    );

class _Autorisations implements Autorisations {
  const _Autorisations(this.permissions);
  final Set<Permission> permissions;

  @override
  bool peut(Permission p) => permissions.contains(p);

  @override
  bool get aUtilisateur => true;

  @override
  int? get enseignantLimite => null;
}

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late AbsenceDepot absences;
  late EleveDepot eleves;
  late int anneeId;
  late int classeA;
  late int classeB;
  late int insBarry;
  late int insDiallo;
  late int insCamara;

  setUp(() async {
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    final db = gdb.db;
    absences = AbsenceDepot(db, maintenant: () => DateTime(2026, 11, 20, 9));
    eleves = EleveDepot(db);
    anneeId = (await AnneeDepot(db).creer('2026-2027', activer: true)).id;
    final classes = ClasseDepot(db);
    classeA = (await classes.creer(anneeId: anneeId, nom: '10e A', niveauCode: 10)).id;
    classeB = (await classes.creer(anneeId: anneeId, nom: '10e B', niveauCode: 10)).id;
    Future<int> inscrire(String nom, String prenom, String matricule, int classe) =>
        eleves.inscrire(
          Eleve(matricule: matricule, nom: nom, prenom: prenom, sexe: 'M'),
          anneeId: anneeId,
          classeId: classe,
        );
    insBarry = await inscrire('Barry', 'Alpha', 'M1', classeA);
    insDiallo = await inscrire('Diallo', 'Aminata', 'M2', classeA);
    insCamara = await inscrire('Camara', 'Fatou', 'M3', classeB);
  });

  tearDown(() => gdb.fermer());

  Absence abs(int ins, String date, {TypeAbsence type = TypeAbsence.absence, int? minutes,
          bool justifiee = false, String motif = ''}) =>
      Absence(
        inscriptionId: ins,
        date: date,
        type: type,
        dureeMinutes: minutes,
        justifiee: justifiee,
        motif: motif,
      );

  group('ajout et lecture', () {
    test('une absence et un retard sont enregistrés avec tous leurs champs', () async {
      final a = await absences.ajouter(
          abs(insBarry, '2026-11-03', justifiee: true, motif: '  Paludisme  '));
      final r = await absences.ajouter(
          abs(insBarry, '2026-11-05', type: TypeAbsence.retard, minutes: 15));
      final liste = await absences.lister(insBarry);
      expect(liste.map((x) => x.id), [r, a], reason: 'du plus récent au plus ancien');
      final premiere = liste.last;
      expect(premiere.type, TypeAbsence.absence);
      expect(premiere.justifiee, isTrue);
      expect(premiere.motif, 'Paludisme');
      expect(premiere.dureeMinutes, isNull);
      expect(liste.first.type, TypeAbsence.retard);
      expect(liste.first.dureeMinutes, 15);
      expect(liste.first.justifiee, isFalse);
    });

    test('la durée est ignorée pour une absence', () async {
      await absences.ajouter(abs(insBarry, '2026-11-03', minutes: 30));
      expect((await absences.lister(insBarry)).single.dureeMinutes, isNull);
    });

    test('un retard sans durée est accepté', () async {
      await absences.ajouter(abs(insBarry, '2026-11-03', type: TypeAbsence.retard));
      expect((await absences.lister(insBarry)).single.dureeMinutes, isNull);
    });

    test('date invalide, motif trop long, durée hors limites : refusés', () async {
      expect(() => absences.ajouter(abs(insBarry, '2026-02-30')),
          erreurContenant('date est invalide'));
      expect(() => absences.ajouter(abs(insBarry, '03/11/2026')),
          erreurContenant('date est invalide'));
      expect(() => absences.ajouter(abs(insBarry, '2026-11-03', motif: 'x' * 201)),
          erreurContenant('motif est trop long'));
      expect(
          () => absences.ajouter(
              abs(insBarry, '2026-11-03', type: TypeAbsence.retard, minutes: 0)),
          erreurContenant('entre 1 et 600'));
      expect(
          () => absences.ajouter(
              abs(insBarry, '2026-11-03', type: TypeAbsence.retard, minutes: 601)),
          erreurContenant('entre 1 et 600'));
      expect(await absences.lister(insBarry), isEmpty);
    });

    test('élève inconnu : refusé', () async {
      expect(() => absences.ajouter(abs(99999, '2026-11-03')),
          erreurContenant('n\'est plus inscrit'));
    });

    test('pas deux absences le même jour, mais une absence et un retard sont permis',
        () async {
      await absences.ajouter(abs(insBarry, '2026-11-03'));
      expect(() => absences.ajouter(abs(insBarry, '2026-11-03')),
          erreurContenant('absence est déjà enregistrée'));
      await absences.ajouter(abs(insBarry, '2026-11-03', type: TypeAbsence.retard));
      expect(() => absences.ajouter(abs(insBarry, '2026-11-03', type: TypeAbsence.retard)),
          erreurContenant('retard est déjà enregistré'));
      // Un autre élève le même jour : permis.
      await absences.ajouter(abs(insDiallo, '2026-11-03'));
    });
  });

  group('modification et suppression', () {
    test('modifier change les champs, sans créer de doublon', () async {
      final id = await absences.ajouter(abs(insBarry, '2026-11-03'));
      await absences.modifier(Absence(
        id: id,
        inscriptionId: insBarry,
        date: '2026-11-04',
        justifiee: true,
        motif: 'Certificat',
      ));
      final l = (await absences.lister(insBarry)).single;
      expect(l.date, '2026-11-04');
      expect(l.justifiee, isTrue);
      expect(l.motif, 'Certificat');
    });

    test('modifier sans changer la date n\'est pas un doublon', () async {
      final id = await absences.ajouter(abs(insBarry, '2026-11-03'));
      await absences.modifier(Absence(
          id: id, inscriptionId: insBarry, date: '2026-11-03', justifiee: true));
      expect((await absences.lister(insBarry)).single.justifiee, isTrue);
    });

    test('modifier vers une date déjà prise : refusé', () async {
      await absences.ajouter(abs(insBarry, '2026-11-03'));
      final id = await absences.ajouter(abs(insBarry, '2026-11-04'));
      expect(
          () => absences.modifier(
              Absence(id: id, inscriptionId: insBarry, date: '2026-11-03')),
          erreurContenant('déjà enregistrée'));
    });

    test('supprimer, puis supprimer encore : message clair', () async {
      final id = await absences.ajouter(abs(insBarry, '2026-11-03'));
      await absences.supprimer(id);
      expect(await absences.lister(insBarry), isEmpty);
      expect(() => absences.supprimer(id), erreurContenant('n\'existe plus'));
      expect(() => absences.modifier(Absence(id: id, inscriptionId: insBarry, date: '2026-11-03')),
          erreurContenant('n\'existe plus'));
    });

    test('supprimer l\'inscription d\'un élève supprime ses absences', () async {
      await absences.ajouter(abs(insBarry, '2026-11-03'));
      await absences.ajouter(abs(insDiallo, '2026-11-03'));
      await eleves.supprimerInscription(insBarry);
      expect(await absences.lister(insBarry), isEmpty);
      expect(await absences.lister(insDiallo), hasLength(1));
    });
  });

  group('totaux et listes', () {
    setUp(() async {
      await absences.ajouter(abs(insBarry, '2026-11-03', justifiee: true));
      await absences.ajouter(abs(insBarry, '2026-11-04'));
      await absences.ajouter(abs(insBarry, '2026-11-05', type: TypeAbsence.retard, minutes: 10));
      await absences.ajouter(abs(insBarry, '2026-11-06',
          type: TypeAbsence.retard, minutes: 20, justifiee: true));
      await absences.ajouter(abs(insDiallo, '2026-11-03'));
      await absences.ajouter(abs(insCamara, '2026-11-10', type: TypeAbsence.retard));
    });

    test('totaux d\'une inscription', () async {
      final t = await absences.totaux(insBarry);
      expect(t.absences, 2);
      expect(t.absencesJustifiees, 1);
      expect(t.absencesInjustifiees, 1);
      expect(t.retards, 2);
      expect(t.retardsJustifies, 1);
      expect(t.retardsInjustifies, 1);
      expect(t.minutesRetard, 30);
      expect(t.vide, isFalse);
    });

    test('un élève sans absence a des totaux vides', () async {
      await absences.supprimer((await absences.lister(insDiallo)).single.id);
      expect((await absences.totaux(insDiallo)).vide, isTrue);
    });

    test('totaux de l\'année : une ligne par élève concerné', () async {
      final t = await absences.totauxAnnee(anneeId);
      expect(t.keys.toSet(), {insBarry, insDiallo, insCamara});
      expect(t[insBarry]!.absences, 2);
      expect(t[insBarry]!.minutesRetard, 30);
      expect(t[insDiallo]!.absences, 1);
      expect(t[insCamara]!.retards, 1);
      expect(t[insCamara]!.minutesRetard, 0, reason: 'durée non renseignée');
      expect((await absences.totauxAnnee(anneeId, classeId: classeB)).keys, [insCamara]);
    });

    test('liste de l\'année : classe, élève puis date, avec les noms', () async {
      final l = await absences.listerAnnee(anneeId);
      expect([for (final a in l) '${a.classeNom}|${a.eleveNom}|${a.date}'], [
        '10e A|BARRY Alpha|2026-11-03',
        '10e A|BARRY Alpha|2026-11-04',
        '10e A|BARRY Alpha|2026-11-05',
        '10e A|BARRY Alpha|2026-11-06',
        '10e A|DIALLO Aminata|2026-11-03',
        '10e B|CAMARA Fatou|2026-11-10',
      ]);
      expect(l.first.matricule, 'M1');
      expect(await absences.listerAnnee(anneeId, classeId: classeB), hasLength(1));
    });
  });

  group('droits et journal', () {
    test('sans le droit de gérer les élèves : refusé, rien n\'est écrit', () async {
      final lecteur = AbsenceDepot(
        gdb.db,
        controle: const Controle(
          autorisations: _Autorisations({Permission.elevesVoir}),
        ),
      );
      expect(() => lecteur.ajouter(abs(insBarry, '2026-11-03')),
          erreurContenant('n\'avez pas l\'autorisation'));
      expect(await absences.lister(insBarry), isEmpty);
      // La lecture reste libre.
      expect(await lecteur.lister(insBarry), isEmpty);
    });

    test('chaque écriture est inscrite au journal', () async {
      final journal = JournalDepot(gdb.db);
      final avecJournal = AbsenceDepot(
        gdb.db,
        controle: Controle(journal: journal),
        maintenant: () => DateTime(2026, 11, 20, 9),
      );
      final id = await avecJournal.ajouter(abs(insBarry, '2026-11-03', justifiee: true));
      await avecJournal.modifier(Absence(id: id, inscriptionId: insBarry, date: '2026-11-03'));
      await avecJournal.supprimer(id);
      final lignes = await gdb.db.query('journal', where: "entite = 'absence'", orderBy: 'id');
      expect([for (final l in lignes) l['action']], ['creation', 'modification', 'suppression']);
      expect(lignes.first['details'], 'Absence du 03/11/2026 (justifiée)');
      expect(lignes.first['entite_id'], id);
    });
  });

  group('migration', () {
    test('la table et son index existent dans une base neuve', () async {
      final t = await gdb.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name IN ('absence', 'idx_absence_inscription')");
      expect(t.map((l) => l['name']).toSet(), {'absence', 'idx_absence_inscription'});
      expect(await gdb.version(), GescoDatabase.versionSchema);
      expect(await gdb.verifierIntegrite(), isEmpty);
    });
  });
}
