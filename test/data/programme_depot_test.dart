import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/depots/programme_depot.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/niveaux.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher refus(String texte) =>
    throwsA(isA<ErreurGesco>().having((e) => e.message, 'message', contains(texte)));

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Services s;
  late int annee;

  /// Classes de l'année : primaire (CE1 A, CE2 A), collège (7e A), maternelle
  /// (PS A), lycée (Tle SM, Tle SE, Tle SS) et une classe hors catalogue.
  late Map<String, int> classe;

  Future<List<String>> noms(String classeNom) async =>
      [for (final m in await s.matieres.lister(classe[classeNom]!)) m.nom];

  Future<MatiereClasse> matiere(String classeNom, String nom) async =>
      (await s.matieres.lister(classe[classeNom]!)).firstWhere((m) => m.nom == nom);

  setUp(() async {
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    s = Services(gdb, session: Session.sansControle(), iterations: 2);
    annee = (await s.annees.creer('2026-2027', activer: true)).id;
    classe = {};
    Future<void> creer(String nom, int? niveau, [SerieLycee? serie]) async {
      classe[nom] = (await s.classes.creer(
        anneeId: annee,
        nom: nom,
        niveau: niveau == null ? 'Divers' : '',
        niveauCode: niveau,
        serie: serie,
      ))
          .id;
    }

    await creer('CE1 A', 3);
    await creer('CE2 A', 4);
    await creer('7e A', 7);
    await creer('PS A', 14);
    await creer('Tle SM', 13, SerieLycee.sciencesMathematiques);
    await creer('Tle SE', 13, SerieLycee.sciencesExperimentales);
    await creer('Tle SS', 13, SerieLycee.sciencesSociales);
    await creer('11e libre', 11);
    await creer('Autre', null);
  });

  tearDown(() async => gdb.fermer());

  group('ajout au programme', () {
    test('la matière est ajoutée à toutes les classes du cycle, et à elles seules', () async {
      final (m, r) = await s.programmes.ajouter(
        anneeId: annee,
        cycle: Cycle.primaire,
        nom: 'Mathématiques',
        coefficient: 300,
      );
      expect(m.nom, 'Mathématiques');
      expect(m.coefficient, 300);
      expect(r.classesConcernees, 2);
      expect(r.ajoutees, 2);
      expect(await noms('CE1 A'), ['Mathématiques']);
      expect(await noms('CE2 A'), ['Mathématiques']);
      expect((await matiere('CE1 A', 'Mathématiques')).coefficient, 300);
      for (final autre in ['7e A', 'PS A', 'Tle SM', 'Tle SE', 'Tle SS', '11e libre', 'Autre']) {
        expect(await noms(autre), isEmpty, reason: autre);
      }
    });

    test('maternelle et collège ont chacun leur programme', () async {
      await s.programmes.ajouter(anneeId: annee, cycle: Cycle.maternelle, nom: 'Éveil', coefficient: 100);
      await s.programmes.ajouter(anneeId: annee, cycle: Cycle.college, nom: 'Anglais', coefficient: 200);
      expect(await noms('PS A'), ['Éveil']);
      expect(await noms('7e A'), ['Anglais']);
      expect(await noms('CE1 A'), isEmpty);
    });

    test('lycée : une option à la fois, et pas de classe sans option', () async {
      final (_, r) = await s.programmes.ajouter(
        anneeId: annee,
        cycle: Cycle.lycee,
        serie: SerieLycee.sciencesMathematiques,
        nom: 'Physique',
        coefficient: 500,
        bareme: 40,
      );
      expect(r.classesConcernees, 1);
      expect(await noms('Tle SM'), ['Physique']);
      expect((await matiere('Tle SM', 'Physique')).bareme, 40);
      expect(await noms('Tle SE'), isEmpty);
      expect(await noms('Tle SS'), isEmpty);
      expect(await noms('11e libre'), isEmpty, reason: 'lycée sans option : aucun programme');

      await s.programmes.ajouter(
        anneeId: annee,
        cycle: Cycle.lycee,
        serie: SerieLycee.sciencesSociales,
        nom: 'Histoire',
        coefficient: 400,
      );
      expect(await noms('Tle SS'), ['Histoire']);
      expect(await noms('Tle SM'), ['Physique']);
    });

    test('un programme par option : même nom possible dans deux options', () async {
      for (final serie in [SerieLycee.sciencesMathematiques, SerieLycee.sciencesExperimentales]) {
        await s.programmes.ajouter(
          anneeId: annee,
          cycle: Cycle.lycee,
          serie: serie,
          nom: 'Philosophie',
          coefficient: serie == SerieLycee.sciencesMathematiques ? 200 : 300,
        );
      }
      expect((await matiere('Tle SM', 'Philosophie')).coefficient, 200);
      expect((await matiere('Tle SE', 'Philosophie')).coefficient, 300);
    });

    test('le lycée exige une option, les autres cycles n\'en ont pas', () async {
      await expectLater(
        s.programmes.ajouter(anneeId: annee, cycle: Cycle.lycee, nom: 'X', coefficient: 100),
        refus('option du lycée'),
      );
      await expectLater(
        s.programmes.ajouter(
          anneeId: annee,
          cycle: Cycle.college,
          serie: SerieLycee.sciencesSociales,
          nom: 'X',
          coefficient: 100,
        ),
        refus('Une option n\'existe que pour le lycée'),
      );
    });

    test('une matière déjà présente dans une classe n\'est pas dupliquée', () async {
      await s.matieres.ajouter(classeId: classe['CE1 A']!, nom: 'mathématiques', coefficient: 100);
      final (_, r) = await s.programmes.ajouter(
        anneeId: annee,
        cycle: Cycle.primaire,
        nom: 'Mathématiques',
        coefficient: 300,
      );
      expect(r.ajoutees, 1, reason: 'seule CE2 A la reçoit');
      expect(await noms('CE1 A'), ['mathématiques']);
      expect((await matiere('CE1 A', 'mathématiques')).coefficient, 100,
          reason: 'la matière existante n\'est pas modifiée par un ajout');
      expect(await noms('CE2 A'), ['Mathématiques']);
    });

    test('validations : nom, doublon, coefficient, barème, année', () async {
      Future<void> ajouter(String nom, int coef, {int bareme = 20, int an = -1}) async {
        await s.programmes.ajouter(
          anneeId: an == -1 ? annee : an,
          cycle: Cycle.primaire,
          nom: nom,
          coefficient: coef,
          bareme: bareme,
        );
      }

      await ajouter('Lecture', 200);
      await expectLater(ajouter('  ', 100), refus('nom de la matière est obligatoire'));
      await expectLater(ajouter('lecture', 100), refus('existe déjà'));
      await expectLater(ajouter('Écriture', 0), refus('coefficient'));
      await expectLater(ajouter('Écriture', -5), refus('coefficient'));
      await expectLater(ajouter('Écriture', 100, bareme: 0), refus('barème'));
      await expectLater(ajouter('Écriture', 100, bareme: 1001), refus('barème'));
      await expectLater(ajouter('Écriture', 100, an: 9999), refus('Année scolaire introuvable'));
      expect((await s.programmes.lister(annee, Cycle.primaire)).length, 1);
    });

    test('l\'ordre du programme est celui des ajouts, repris dans les classes', () async {
      for (final nom in ['Lecture', 'Calcul', 'Dessin']) {
        await s.programmes.ajouter(anneeId: annee, cycle: Cycle.primaire, nom: nom, coefficient: 100);
      }
      expect([for (final m in await s.programmes.lister(annee, Cycle.primaire)) m.nom],
          ['Lecture', 'Calcul', 'Dessin']);
      expect(await noms('CE1 A'), ['Lecture', 'Calcul', 'Dessin']);
    });
  });

  group('classes créées ou modifiées après le programme', () {
    setUp(() async {
      await s.programmes.ajouter(anneeId: annee, cycle: Cycle.primaire, nom: 'Lecture', coefficient: 200);
      await s.programmes.ajouter(
        anneeId: annee,
        cycle: Cycle.primaire,
        nom: 'Dessin',
        coefficient: 50,
        facultative: true,
      );
    });

    test('une nouvelle classe reçoit tout le programme de son cycle', () async {
      final c = await s.classes.creer(anneeId: annee, nom: 'CM1 A', niveauCode: 5);
      final liste = await s.matieres.lister(c.id);
      expect([for (final m in liste) m.nom], ['Lecture', 'Dessin']);
      expect([for (final m in liste) m.coefficient], [200, 50]);
      expect([for (final m in liste) m.facultative], [false, true]);
    });

    test('une classe d\'un autre cycle ou hors catalogue ne reçoit rien', () async {
      final college = await s.classes.creer(anneeId: annee, nom: '8e A', niveauCode: 8);
      final libre = await s.classes.creer(anneeId: annee, nom: 'Libre', niveau: 'Primaire');
      final lyceeSansOption = await s.classes.creer(anneeId: annee, nom: '12e', niveauCode: 12);
      expect(await s.matieres.lister(college.id), isEmpty);
      expect(await s.matieres.lister(libre.id), isEmpty);
      expect(await s.matieres.lister(lyceeSansOption.id), isEmpty);
    });

    test('changer une classe de niveau lui ajoute le programme de son nouveau cycle', () async {
      final id = classe['7e A']!;
      expect(await s.matieres.lister(id), isEmpty);
      await s.classes.modifier(id, nom: '6e A', niveau: '', niveauCode: 6);
      expect([for (final m in await s.matieres.lister(id)) m.nom], ['Lecture', 'Dessin']);
    });

    test('une simple modification du nom ne remet pas une matière retirée à la main', () async {
      final id = classe['CE1 A']!;
      await s.matieres.supprimer((await matiere('CE1 A', 'Dessin')).id);
      expect(await noms('CE1 A'), ['Lecture']);
      await s.classes.modifier(id, nom: 'CE1 B', niveau: '', niveauCode: 3);
      expect(await noms('CE1 A'), ['Lecture']);
    });

    test('la copie d\'une année reprend le programme, sans doubler les matières des classes',
        () async {
      final suivante = await s.annees.creer('2027-2028', copierDepuisAnneeId: annee);
      final prog = await s.programmes.lister(suivante.id, Cycle.primaire);
      expect([for (final m in prog) m.nom], ['Lecture', 'Dessin']);
      expect([for (final m in prog) m.coefficient], [200, 50]);
      expect(prog.every((m) => m.anneeId == suivante.id), isTrue);
      final copiees = await s.classes.lister(suivante.id);
      final ce1 = copiees.firstWhere((c) => c.classe.nom == 'CE1 A');
      expect([for (final m in await s.matieres.lister(ce1.classe.id)) m.nom],
          ['Lecture', 'Dessin']);
      // Le programme de l'année copiée reste indépendant de l'original.
      await s.programmes.ajouter(
          anneeId: suivante.id, cycle: Cycle.primaire, nom: 'Chant', coefficient: 100);
      expect((await s.programmes.lister(annee, Cycle.primaire)).length, 2);
    });

    test('supprimer l\'année supprime son programme', () async {
      final suivante = await s.annees.creer('2027-2028');
      await s.programmes.ajouter(
          anneeId: suivante.id, cycle: Cycle.college, nom: 'Anglais', coefficient: 100);
      await s.annees.supprimer(suivante.id);
      final n = await gdb.db.rawQuery(
          'SELECT COUNT(*) AS n FROM programme_matiere WHERE annee_id = ?', [suivante.id]);
      expect(n.first['n'], 0);
      expect((await s.programmes.lister(annee, Cycle.primaire)).length, 2);
    });
  });

  group('modification du programme', () {
    late int lecture;

    setUp(() async {
      lecture = (await s.programmes.ajouter(
              anneeId: annee, cycle: Cycle.primaire, nom: 'Lecture', coefficient: 200))
          .$1
          .id;
    });

    test('le coefficient et le nom sont répercutés dans les classes du cycle', () async {
      final r = await s.programmes.modifier(lecture, nom: 'Lecture et écriture', coefficient: 350);
      expect(r.classesConcernees, 2);
      expect(r.modifiees, 2);
      expect(await noms('CE1 A'), ['Lecture et écriture']);
      expect((await matiere('CE2 A', 'Lecture et écriture')).coefficient, 350);
      final prog = await s.programmes.lister(annee, Cycle.primaire);
      expect(prog.single.nom, 'Lecture et écriture');
    });

    test('une matière retirée à la main d\'une classe n\'y est pas remise', () async {
      await s.matieres.supprimer((await matiere('CE1 A', 'Lecture')).id);
      final r = await s.programmes.modifier(lecture, coefficient: 300);
      expect(r.modifiees, 1);
      expect(await noms('CE1 A'), isEmpty);
      expect((await matiere('CE2 A', 'Lecture')).coefficient, 300);
    });

    test('les notes déjà saisies sont conservées et le barème ne change pas là où il y en a',
        () async {
      final eleve = await s.eleves.inscrire(
        Eleve(matricule: '2026-0001', nom: 'DIALLO', prenom: 'Aminata', sexe: 'F'),
        anneeId: annee,
        classeId: classe['CE1 A']!,
      );
      final m = await matiere('CE1 A', 'Lecture');
      await s.notes.enregistrer(
        inscriptionId: eleve,
        matiereId: m.id,
        mois: 12,
        saisie: const Saisie.valeur(1500),
      );
      final r = await s.programmes.modifier(lecture, bareme: 40, coefficient: 400);
      expect(r.modifiees, 2);
      expect(r.conservees, hasLength(1));
      expect(r.conservees.single, contains('reste 20 dans la classe CE1 A'));
      expect(r.resume, contains('mise à jour dans 2 classes'));
      // CE1 A : coefficient changé, barème et note inchangés.
      final apres = await matiere('CE1 A', 'Lecture');
      expect(apres.id, m.id);
      expect(apres.coefficient, 400);
      expect(apres.bareme, 20);
      // CE2 A, sans donnée : barème changé.
      expect((await matiere('CE2 A', 'Lecture')).bareme, 40);
      final notes = await gdb.db.query('note', where: 'matiere_id = ?', whereArgs: [m.id]);
      expect(notes.single['valeur'], 1500);
    });

    test('un nom déjà pris dans une classe y est signalé, la matière garde son nom', () async {
      await s.matieres.ajouter(classeId: classe['CE2 A']!, nom: 'Français', coefficient: 100);
      final r = await s.programmes.modifier(lecture, nom: 'Français');
      expect(r.conservees, hasLength(1));
      expect(r.conservees.single, contains('garde son nom'));
      expect(await noms('CE1 A'), ['Français']);
      expect(await noms('CE2 A'), ['Lecture', 'Français']);
    });

    test('nom déjà utilisé dans le programme, coefficient invalide, matière inconnue', () async {
      await s.programmes.ajouter(anneeId: annee, cycle: Cycle.primaire, nom: 'Calcul', coefficient: 100);
      await expectLater(s.programmes.modifier(lecture, nom: 'calcul'), refus('existe déjà'));
      await expectLater(s.programmes.modifier(lecture, coefficient: 0), refus('coefficient'));
      await expectLater(s.programmes.modifier(9999, coefficient: 100), refus('introuvable'));
      // Le même nom, avec une autre casse, reste possible pour la même matière.
      await s.programmes.modifier(lecture, nom: 'LECTURE');
      expect((await s.programmes.lister(annee, Cycle.primaire)).first.nom, 'LECTURE');
    });
  });

  group('retrait du programme', () {
    test('retirée des classes sans donnée, conservée là où des notes existent', () async {
      final (m, _) = await s.programmes.ajouter(
          anneeId: annee, cycle: Cycle.primaire, nom: 'Lecture', coefficient: 200);
      final eleve = await s.eleves.inscrire(
        Eleve(matricule: '2026-0002', nom: 'BAH', prenom: 'Oumar', sexe: 'M'),
        anneeId: annee,
        classeId: classe['CE2 A']!,
      );
      await s.notes.enregistrer(
        inscriptionId: eleve,
        matiereId: (await matiere('CE2 A', 'Lecture')).id,
        mois: 3,
        saisie: const Saisie.valeur(1200),
      );
      final r = await s.programmes.supprimer(m.id);
      expect(r.classesConcernees, 2);
      expect(r.retirees, 1);
      expect(r.conservees.single, contains('reste dans la classe CE2 A'));
      expect(await noms('CE1 A'), isEmpty);
      expect(await noms('CE2 A'), ['Lecture']);
      expect(await s.programmes.lister(annee, Cycle.primaire), isEmpty);
      await expectLater(s.programmes.supprimer(m.id), refus('introuvable'));
    });

    test('une évaluation empêche aussi le retrait de la classe', () async {
      final (m, _) = await s.programmes.ajouter(
          anneeId: annee, cycle: Cycle.college, nom: 'Anglais', coefficient: 200);
      final matiereId = (await matiere('7e A', 'Anglais')).id;
      await gdb.db.insert('evaluation', {
        'classe_id': classe['7e A'],
        'matiere_id': matiereId,
        'mois': 11,
        'type': 'devoir',
        'titre': 'Devoir 1',
        'coefficient': 100,
        'bareme': 20,
        'cree_le': '2026-11-10T08:00:00',
      });
      final r = await s.programmes.supprimer(m.id);
      expect(r.retirees, 0);
      expect(r.conservees, hasLength(1));
      expect(await noms('7e A'), ['Anglais']);
    });
  });

  group('ordre, application et décompte', () {
    test('réordonner le programme', () async {
      final ids = <int>[];
      for (final nom in ['A', 'B', 'C']) {
        ids.add((await s.programmes.ajouter(
                anneeId: annee, cycle: Cycle.college, nom: nom, coefficient: 100))
            .$1
            .id);
      }
      await s.programmes.reordonner(annee, Cycle.college, [ids[2], ids[0], ids[1]]);
      expect([for (final m in await s.programmes.lister(annee, Cycle.college)) m.nom],
          ['C', 'A', 'B']);
      await expectLater(
        s.programmes.reordonner(annee, Cycle.college, [ids[0], ids[1]]),
        refus('ne correspond pas'),
      );
      await expectLater(
        s.programmes.reordonner(annee, Cycle.college, [ids[0], ids[0], ids[1]]),
        refus('ne correspond pas'),
      );
    });

    test('appliquer remet les matières manquantes sans toucher aux autres', () async {
      await s.programmes.ajouter(anneeId: annee, cycle: Cycle.primaire, nom: 'Lecture', coefficient: 200);
      await s.programmes.ajouter(anneeId: annee, cycle: Cycle.primaire, nom: 'Calcul', coefficient: 300);
      await s.matieres.supprimer((await matiere('CE1 A', 'Calcul')).id);
      // Coefficient modifié à la main dans CE2 A : il n'est pas écrasé.
      final lectureCe2 = await matiere('CE2 A', 'Lecture');
      await s.matieres.modifier(lectureCe2.id, nom: 'Lecture', coefficient: 999);
      final r = await s.programmes.appliquer(annee, Cycle.primaire);
      expect(r.classesConcernees, 2);
      expect(r.ajoutees, 1);
      expect(await noms('CE1 A'), ['Lecture', 'Calcul']);
      expect((await matiere('CE2 A', 'Lecture')).coefficient, 999);
    });

    test('appliquer à une option : seules les classes de l\'option', () async {
      await s.programmes.ajouter(
          anneeId: annee,
          cycle: Cycle.lycee,
          serie: SerieLycee.sciencesExperimentales,
          nom: 'SVT',
          coefficient: 400);
      await s.matieres.supprimer((await matiere('Tle SE', 'SVT')).id);
      final r = await s.programmes
          .appliquer(annee, Cycle.lycee, serie: SerieLycee.sciencesExperimentales);
      expect(r.classesConcernees, 1);
      expect(r.ajoutees, 1);
      expect(await noms('Tle SE'), ['SVT']);
      expect(await noms('Tle SM'), isEmpty);
      await expectLater(s.programmes.appliquer(annee, Cycle.lycee), refus('option du lycée'));
    });

    test('décompte par cycle et par option', () async {
      await s.programmes.ajouter(anneeId: annee, cycle: Cycle.primaire, nom: 'A', coefficient: 100);
      await s.programmes.ajouter(anneeId: annee, cycle: Cycle.primaire, nom: 'B', coefficient: 100);
      await s.programmes.ajouter(
          anneeId: annee,
          cycle: Cycle.lycee,
          serie: SerieLycee.sciencesMathematiques,
          nom: 'C',
          coefficient: 100);
      final comptes = await s.programmes.comptes(annee);
      expect(comptes[ProgrammeDepot.cleProgramme(Cycle.primaire, null)], 2);
      expect(comptes[ProgrammeDepot.cleProgramme(Cycle.lycee, SerieLycee.sciencesMathematiques)], 1);
      expect(comptes.containsKey('college'), isFalse);
      expect(ProgrammeDepot.cleProgramme(Cycle.lycee, SerieLycee.sciencesSociales), 'lycee:SS');
    });

    test('classes d\'un cycle ou d\'une option', () async {
      expect([for (final c in await s.programmes.classes(annee, Cycle.primaire)) c.nom],
          ['CE1 A', 'CE2 A']);
      expect(
          [
            for (final c in await s.programmes
                .classes(annee, Cycle.lycee, serie: SerieLycee.sciencesSociales))
              c.nom
          ],
          ['Tle SS']);
    });
  });

  group('droits d\'accès', () {
    test('sans connexion, le programme ne peut pas être modifié', () async {
      final protege = Services(gdb, session: Session(), iterations: 2);
      await expectLater(
        protege.programmes
            .ajouter(anneeId: annee, cycle: Cycle.primaire, nom: 'Lecture', coefficient: 100),
        refus('Connectez-vous'),
      );
      await expectLater(protege.programmes.appliquer(annee, Cycle.primaire), refus('Connectez-vous'));
      expect(await s.programmes.lister(annee, Cycle.primaire), isEmpty);
    });
  });
}
