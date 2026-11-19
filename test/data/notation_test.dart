import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/data/controle.dart';
import 'package:gesco/data/depots/annee_depot.dart';
import 'package:gesco/data/depots/classe_depot.dart';
import 'package:gesco/data/depots/eleve_depot.dart';
import 'package:gesco/data/depots/enseignant_depot.dart';
import 'package:gesco/data/depots/evaluation_depot.dart';
import 'package:gesco/data/depots/matiere_depot.dart';
import 'package:gesco/data/depots/note_depot.dart';
import 'package:gesco/data/depots/parametre_depot.dart';
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

/// Utilisateur connecté avec une liste précise de permissions.
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
  late MatiereClasse maths; // sur 20
  late MatiereClasse sciences; // sur 40
  late MatiereClasse matiereB;
  late int aminata;
  late int ibrahima;
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
    sciences = await matieres.ajouter(
      classeId: classeA.id,
      nom: 'Sciences',
      coefficient: 200,
      bareme: 40,
    );
    matiereB = await matieres.ajouter(classeId: classeB.id, nom: 'Maths', coefficient: 400);

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

  Future<void> noter(int inscription, int matiere, int mois, Saisie? s) => notes.enregistrer(
        inscriptionId: inscription,
        matiereId: matiere,
        mois: mois,
        saisie: s,
      );

  Future<Evaluation> evaluer({
    int? matiereId,
    int mois = 10,
    String titre = 'Devoir 1',
    int coefficient = 100,
    int? bareme,
    TypeEvaluation type = TypeEvaluation.devoir,
  }) =>
      evaluations.creer(
        classeId: classeA.id,
        matiereId: matiereId ?? maths.id,
        mois: mois,
        titre: titre,
        coefficient: coefficient,
        bareme: bareme,
        type: type,
      );

  group('notes mensuelles et barème de la matière', () {
    test('matière sur 40 : la note d\'origine et la note sur 20 sont conservées', () async {
      await noter(aminata, sciences.id, 10, const Saisie.surBareme(3100, 40));
      final s = (await notes.lireClasse(classeA.id))[aminata]![sciences.id]![10]!;
      expect(s.brut, 3100);
      expect(s.bareme, 40);
      expect(s.centiemes, 1550);
      final ligne = (await db.query('note')).single;
      expect(ligne['valeur'], 1550);
      expect(ligne['brut'], 3100);
      expect(ligne['bareme'], 40);
    });

    test('matière sur 20 : ni note d\'origine ni barème en base', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1475));
      final ligne = (await db.query('note')).single;
      expect(ligne['valeur'], 1475);
      expect(ligne['brut'], isNull);
      expect(ligne['bareme'], isNull);
      final s = (await notes.lireClasse(classeA.id))[aminata]![maths.id]![10]!;
      expect(s, const Saisie.valeur(1475));
    });

    test('une note sur 20 est refusée dans une matière sur 40', () async {
      await expectLater(
        noter(aminata, sciences.id, 10, const Saisie.valeur(1500)),
        erreurContenant('notée sur 40'),
      );
      expect(await notes.compterClasse(classeA.id), 0);
    });

    test('une note sur 10 est refusée dans une matière sur 20 ou sur 40', () async {
      await expectLater(
        noter(aminata, maths.id, 10, const Saisie.surBareme(700, 10)),
        erreurContenant('notée sur 20'),
      );
      await expectLater(
        noter(aminata, sciences.id, 10, const Saisie.surBareme(700, 10)),
        erreurContenant('notée sur 40'),
      );
    });

    test('absent et dispensé fonctionnent sur tous les barèmes', () async {
      await noter(aminata, sciences.id, 10, const Saisie.absent());
      await noter(ibrahima, sciences.id, 10, const Saisie.dispense());
      final lu = await notes.lireClasse(classeA.id);
      expect(lu[aminata]![sciences.id]![10], const Saisie.absent());
      expect(lu[ibrahima]![sciences.id]![10], const Saisie.dispense());
    });

    test('le même arrondi que la conversion : 31,25 sur 40 -> 15,63', () async {
      await noter(aminata, sciences.id, 11, const Saisie.surBareme(3125, 40));
      final s = (await notes.lireClasse(classeA.id))[aminata]![sciences.id]![11]!;
      expect(s.centiemes, 1563);
    });

    test('corriger une note sur 40 remplace la note d\'origine', () async {
      await noter(aminata, sciences.id, 10, const Saisie.surBareme(3100, 40));
      await noter(aminata, sciences.id, 10, const Saisie.surBareme(2000, 40));
      final s = (await notes.lireClasse(classeA.id))[aminata]![sciences.id]![10]!;
      expect(s.brut, 2000);
      expect(s.centiemes, 1000);
      expect(await notes.compterClasse(classeA.id), 1);
    });
  });

  group('verrouillage des mois', () {
    test('un mois verrouillé refuse toute modification, le déverrouiller la rend possible',
        () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      await notes.verrouiller(classeA.id, 10);
      await expectLater(
        noter(aminata, maths.id, 10, const Saisie.valeur(1200)),
        erreurContenant('verrouillé'),
      );
      await expectLater(
        noter(ibrahima, maths.id, 10, const Saisie.valeur(1200)),
        erreurContenant('verrouillé'),
      );
      await expectLater(noter(aminata, maths.id, 10, null), erreurContenant('verrouillé'));
      // Les autres mois et les autres classes ne sont pas touchés.
      await noter(aminata, maths.id, 11, const Saisie.valeur(1200));
      await noter(eleveB, matiereB.id, 10, const Saisie.valeur(1200));

      await notes.deverrouiller(classeA.id, 10);
      await noter(aminata, maths.id, 10, const Saisie.valeur(1200));
      final s = (await notes.lireClasse(classeA.id))[aminata]![maths.id]![10]!;
      expect(s.centiemes, 1200);
    });

    test('la liste des verrous est dans l\'ordre de l\'année et garde l\'horodatage', () async {
      await notes.verrouiller(classeA.id, 2);
      await notes.verrouiller(classeA.id, 11);
      await notes.verrouiller(classeA.id, 10);
      final verrous = await notes.verrous(classeA.id);
      expect([for (final v in verrous) v.mois], [10, 11, 2]);
      expect(verrous.first.verrouilleLe, '2026-11-05T09:30:00');
      expect(await notes.moisVerrouilles(classeA.id), {10, 11, 2});
      expect(await notes.moisVerrouilles(classeB.id), isEmpty);
    });

    test('verrouiller deux fois est sans effet, déverrouiller un mois libre aussi', () async {
      await notes.verrouiller(classeA.id, 10);
      await notes.verrouiller(classeA.id, 10);
      expect(await notes.verrous(classeA.id), hasLength(1));
      await notes.deverrouiller(classeA.id, 12);
      expect(await notes.verrous(classeA.id), hasLength(1));
    });

    test('mois invalide ou classe inconnue', () async {
      await expectLater(notes.verrouiller(classeA.id, 7), erreurContenant('hors de l\'année'));
      await expectLater(notes.verrouiller(9999, 10), erreurContenant('Classe introuvable'));
    });

    test('un mois verrouillé bloque aussi les notes d\'évaluation', () async {
      final e = await evaluer();
      await evaluations.enregistrerNote(
        evaluationId: e.id,
        inscriptionId: aminata,
        saisie: const Saisie.valeur(1200),
      );
      await notes.verrouiller(classeA.id, 10);
      await expectLater(
        evaluations.enregistrerNote(
          evaluationId: e.id,
          inscriptionId: ibrahima,
          saisie: const Saisie.valeur(900),
        ),
        erreurContenant('verrouillé'),
      );
      await expectLater(
        evaluations.enregistrerNote(
          evaluationId: e.id,
          inscriptionId: aminata,
          saisie: null,
        ),
        erreurContenant('verrouillé'),
      );
    });

    test('une année archivée refuse les notes avec un message clair', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      await annees.creer('2027-2028', activer: true);
      await annees.archiver(anneeId);
      await expectLater(
        noter(aminata, maths.id, 10, const Saisie.valeur(1200)),
        erreurContenant('archivée'),
      );
      await expectLater(noter(aminata, maths.id, 10, null), erreurContenant('archivée'));
    });

    test('sans permission, on ne peut ni verrouiller ni déverrouiller', () async {
      final sans = NoteDepot(
        db,
        controle: const Controle(autorisations: _Autorisations({})),
      );
      await expectLater(
        sans.verrouiller(classeA.id, 10),
        erreurContenant('pas l\'autorisation'),
      );
      await notes.verrouiller(classeA.id, 10);
      await expectLater(
        sans.deverrouiller(classeA.id, 10),
        erreurContenant('pas l\'autorisation'),
      );
      final avec = NoteDepot(
        db,
        controle: const Controle(
          autorisations: _Autorisations({Permission.notesVerrouiller}),
        ),
      );
      await avec.deverrouiller(classeA.id, 10);
      expect(await notes.verrous(classeA.id), isEmpty);
    });
  });

  group('historique des notes', () {
    test('saisie, modification et suppression sont enregistrées avec les valeurs', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      horloge = DateTime(2026, 11, 5, 9, 31);
      await noter(aminata, maths.id, 10, const Saisie.valeur(1250));
      await noter(aminata, maths.id, 10, null);

      final h = await notes.historique(classeId: classeA.id);
      expect(h, hasLength(3));
      // Le plus récent d'abord.
      expect([for (final e in h) e.operation], ['suppression', 'modification', 'creation']);
      expect(h[2].nouveauTexte, '10,00 / 20');
      expect(h[2].ancienTexte, '—');
      expect(h[1].ancienTexte, '10,00 / 20');
      expect(h[1].nouveauTexte, '12,50 / 20');
      expect(h[0].ancienTexte, '12,50 / 20');
      expect(h[0].nouveauTexte, '—');
      expect(h.first.eleveNom, contains('DIALLO'));
      expect(h.first.matiereNom, 'Maths');
      expect(h.first.classeNom, '10e A');
      expect(h.first.libelleOperation, 'Suppression');
      expect(h.first.source, 'mensuelle');
      expect(h.first.nomMois, 'Octobre');
    });

    test('enregistrer la même note deux fois ne crée pas de ligne', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      expect(await notes.compterHistorique(), 1);
    });

    test('absent et dispensé sont lisibles dans l\'historique', () async {
      await noter(aminata, maths.id, 10, const Saisie.absent());
      await noter(aminata, maths.id, 10, const Saisie.dispense());
      final h = await notes.historique();
      expect(h.first.ancienTexte, 'Absent');
      expect(h.first.nouveauTexte, 'Dispensé');
    });

    test('les filtres classe, élève, matière, mois et source', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      await noter(ibrahima, maths.id, 11, const Saisie.valeur(1100));
      await noter(eleveB, matiereB.id, 10, const Saisie.valeur(1200));
      final e = await evaluer();
      await evaluations.enregistrerNote(
        evaluationId: e.id,
        inscriptionId: aminata,
        saisie: const Saisie.valeur(1300),
      );

      expect(await notes.compterHistorique(), 4);
      expect(await notes.compterHistorique(classeId: classeA.id), 3);
      expect(await notes.compterHistorique(classeId: classeB.id), 1);
      expect(await notes.compterHistorique(inscriptionId: ibrahima), 1);
      expect(await notes.compterHistorique(matiereId: matiereB.id), 1);
      expect(await notes.compterHistorique(mois: 10), 3);
      expect(await notes.compterHistorique(source: 'evaluation'), 1);
      expect(await notes.compterHistorique(classeId: classeA.id, mois: 10, source: 'mensuelle'), 1);
    });

    test('pagination', () async {
      for (var i = 0; i < 5; i++) {
        await noter(aminata, maths.id, 10, Saisie.valeur(1000 + i));
      }
      final page1 = await notes.historique(limite: 2);
      final page2 = await notes.historique(limite: 2, decalage: 2);
      final page3 = await notes.historique(limite: 2, decalage: 4);
      expect([page1.length, page2.length, page3.length], [2, 2, 1]);
      expect(await notes.compterHistorique(), 5);
      expect({for (final e in [...page1, ...page2, ...page3]) e.id}, hasLength(5));
    });

    test('l\'historique garde le nom de l\'auteur', () async {
      await db.update('contexte', {'utilisateur_nom': 'Directeur Test'});
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      final h = await notes.historique();
      expect(h.single.utilisateurNom, 'Directeur Test');
    });

    test('consulter l\'historique demande la permission du journal', () async {
      final sans = NoteDepot(
        db,
        controle: const Controle(autorisations: _Autorisations({})),
      );
      await expectLater(sans.historique(), erreurContenant('pas l\'autorisation'));
      await expectLater(sans.compterHistorique(), throwsA(isA<ErreurGesco>()));
    });
  });

  group('créer et modifier une évaluation', () {
    test('le barème par défaut est celui de la matière', () async {
      final sur20 = await evaluer(titre: '  Interro 1  ', type: TypeEvaluation.interrogation);
      final sur40 = await evaluer(matiereId: sciences.id, titre: 'Devoir sciences');
      expect(sur20.bareme, 20);
      expect(sur20.titre, 'Interro 1');
      expect(sur20.type, TypeEvaluation.interrogation);
      expect(sur20.coefficient, 100);
      expect(sur20.valide, isFalse);
      expect(sur40.bareme, 40);
      final choisi = await evaluer(matiereId: sciences.id, titre: 'Quiz', bareme: 10);
      expect(choisi.bareme, 10);
    });

    test('titre, mois, coefficient, barème et date sont contrôlés', () async {
      await expectLater(evaluer(titre: '  '), erreurContenant('titre'));
      await expectLater(evaluer(titre: 'x' * 81), erreurContenant('trop long'));
      await expectLater(evaluer(mois: 7), erreurContenant('hors de l\'année'));
      await expectLater(evaluer(coefficient: 0), erreurContenant('coefficient'));
      await expectLater(evaluer(coefficient: 10000), erreurContenant('coefficient'));
      await expectLater(evaluer(bareme: 0), erreurContenant('barème'));
      await expectLater(evaluer(bareme: 1001), erreurContenant('barème'));
      await expectLater(
        evaluations.creer(
          classeId: classeA.id,
          matiereId: maths.id,
          mois: 10,
          titre: 'X',
          date: '31/02/2026',
        ),
        erreurContenant('date'),
      );
      expect(await evaluations.lister(classeId: classeA.id), isEmpty);
    });

    test('la matière doit appartenir à la classe', () async {
      await expectLater(
        evaluations.creer(
          classeId: classeA.id,
          matiereId: matiereB.id,
          mois: 10,
          titre: 'X',
        ),
        erreurContenant('n\'appartient pas'),
      );
      await expectLater(
        evaluations.creer(classeId: classeA.id, matiereId: 9999, mois: 10, titre: 'X'),
        erreurContenant('Matière introuvable'),
      );
    });

    test('la date valide est enregistrée au format ISO', () async {
      final e = await evaluations.creer(
        classeId: classeA.id,
        matiereId: maths.id,
        mois: 10,
        titre: 'Composition',
        type: TypeEvaluation.composition,
        date: '2026-10-20',
      );
      expect(e.date, '2026-10-20');
      await evaluations.modifier(e.id, effacerDate: true);
      expect((await evaluations.obtenir(e.id))!.date, isNull);
      await evaluations.modifier(e.id, date: '2026-10-21');
      expect((await evaluations.obtenir(e.id))!.date, '2026-10-21');
    });

    test('modifier le titre, le type et le coefficient', () async {
      final e = await evaluer();
      await evaluations.modifier(
        e.id,
        titre: 'Devoir surveillé',
        type: TypeEvaluation.examen,
        coefficient: 250,
      );
      final lu = (await evaluations.obtenir(e.id))!;
      expect(lu.titre, 'Devoir surveillé');
      expect(lu.type, TypeEvaluation.examen);
      expect(lu.coefficient, 250);
      await expectLater(evaluations.modifier(9999, titre: 'x'), erreurContenant('introuvable'));
    });

    test('le barème et le mois ne changent plus dès qu\'une note existe', () async {
      final e = await evaluer(bareme: 20);
      await evaluations.modifier(e.id, bareme: 10, mois: 11);
      var lu = (await evaluations.obtenir(e.id))!;
      expect((lu.bareme, lu.mois), (10, 11));

      await evaluations.enregistrerNote(
        evaluationId: e.id,
        inscriptionId: aminata,
        saisie: const Saisie.surBareme(700, 10),
      );
      await expectLater(evaluations.modifier(e.id, bareme: 20), erreurContenant('barème'));
      await expectLater(evaluations.modifier(e.id, mois: 12), erreurContenant('mois'));
      await evaluations.modifier(e.id, coefficient: 300);
      lu = (await evaluations.obtenir(e.id))!;
      expect((lu.bareme, lu.mois, lu.coefficient), (10, 11, 300));
    });

    test('la liste suit l\'ordre de l\'année scolaire (novembre avant janvier)', () async {
      await evaluer(mois: 1, titre: 'Janvier');
      await evaluer(mois: 11, titre: 'Novembre');
      await evaluer(mois: 10, titre: 'Octobre');
      await evaluer(mois: 10, titre: 'Octobre bis');
      final liste = await evaluations.lister(classeId: classeA.id);
      expect([for (final r in liste) r.evaluation.titre], [
        'Octobre',
        'Octobre bis',
        'Novembre',
        'Janvier',
      ]);
      expect(liste.first.matiereNom, 'Maths');
      expect(liste.first.nbEleves, 2);
      expect(liste.first.nbNotes, 0);
    });

    test('filtres de la liste : matière et mois', () async {
      await evaluer(mois: 10, titre: 'M10');
      await evaluer(mois: 11, titre: 'M11');
      await evaluer(matiereId: sciences.id, mois: 10, titre: 'S10');
      expect(await evaluations.lister(classeId: classeA.id), hasLength(3));
      expect(await evaluations.lister(classeId: classeA.id, mois: 10), hasLength(2));
      expect(await evaluations.lister(classeId: classeA.id, matiereId: sciences.id), hasLength(1));
      expect(
        await evaluations.lister(classeId: classeA.id, matiereId: maths.id, mois: 11),
        hasLength(1),
      );
      expect(await evaluations.lister(classeId: classeB.id), isEmpty);
    });

    test('un mois verrouillé interdit de créer, modifier ou supprimer', () async {
      final e = await evaluer(mois: 10);
      await notes.verrouiller(classeA.id, 10);
      await expectLater(evaluer(mois: 10, titre: 'Autre'), erreurContenant('verrouillé'));
      await expectLater(evaluations.modifier(e.id, titre: 'Nouveau'), erreurContenant('verrouillé'));
      await expectLater(evaluations.supprimer(e.id), erreurContenant('verrouillé'));
      // Un autre mois reste libre.
      await evaluer(mois: 11, titre: 'Novembre');
    });

    test('une année archivée interdit de créer une évaluation', () async {
      await annees.creer('2027-2028', activer: true);
      await annees.archiver(anneeId);
      await expectLater(evaluer(), erreurContenant('archivée'));
    });
  });

  group('notes d\'une évaluation', () {
    test('sur 20 : enregistrer, relire, corriger, effacer', () async {
      final e = await evaluer();
      await evaluations.enregistrerNote(
        evaluationId: e.id,
        inscriptionId: aminata,
        saisie: const Saisie.valeur(1475),
      );
      var lu = await evaluations.lireNotes(e.id);
      expect(lu[aminata], const Saisie.valeur(1475));
      expect((await db.query('evaluation_note')).single['brut'], 1475);

      await evaluations.enregistrerNote(
        evaluationId: e.id,
        inscriptionId: aminata,
        saisie: const Saisie.valeur(1500),
      );
      lu = await evaluations.lireNotes(e.id);
      expect(lu[aminata]!.centiemes, 1500);
      expect(lu, hasLength(1));

      await evaluations.enregistrerNote(
        evaluationId: e.id,
        inscriptionId: aminata,
        saisie: null,
      );
      expect(await evaluations.lireNotes(e.id), isEmpty);
    });

    test('sur 10 : la note est gardée sur 10 et ramenée sur 20 à la lecture', () async {
      final e = await evaluer(bareme: 10);
      await evaluations.enregistrerNote(
        evaluationId: e.id,
        inscriptionId: aminata,
        saisie: const Saisie.surBareme(700, 10),
      );
      final s = (await evaluations.lireNotes(e.id))[aminata]!;
      expect(s.brut, 700);
      expect(s.bareme, 10);
      expect(s.centiemes, 1400);
      expect((await db.query('evaluation_note')).single['brut'], 700);
    });

    test('zéro, absent et dispensé', () async {
      final e = await evaluer();
      await evaluations.enregistrerLot(e.id, {
        aminata: const Saisie.valeur(0),
        ibrahima: const Saisie.absent(),
      });
      final lu = await evaluations.lireNotes(e.id);
      expect(lu[aminata]!.estNumerique, isTrue);
      expect(lu[aminata]!.centiemes, 0);
      expect(lu[ibrahima], const Saisie.absent());
      await evaluations.enregistrerNote(
        evaluationId: e.id,
        inscriptionId: ibrahima,
        saisie: const Saisie.dispense(),
      );
      expect((await evaluations.lireNotes(e.id))[ibrahima], const Saisie.dispense());
    });

    test('le barème de la note doit être celui de l\'évaluation', () async {
      final sur20 = await evaluer();
      final sur40 = await evaluer(matiereId: sciences.id, titre: 'Sciences');
      await expectLater(
        evaluations.enregistrerNote(
          evaluationId: sur40.id,
          inscriptionId: aminata,
          saisie: const Saisie.valeur(1500),
        ),
        erreurContenant('notée sur 40'),
      );
      await expectLater(
        evaluations.enregistrerNote(
          evaluationId: sur20.id,
          inscriptionId: aminata,
          saisie: const Saisie.surBareme(1500, 40),
        ),
        erreurContenant('notée sur 20'),
      );
      expect(await db.query('evaluation_note'), isEmpty);
    });

    test('saisie collective : tout est enregistré en une fois', () async {
      final e = await evaluer(bareme: 40, matiereId: sciences.id);
      await evaluations.enregistrerLot(e.id, {
        aminata: const Saisie.surBareme(3500, 40),
        ibrahima: const Saisie.surBareme(1200, 40),
      });
      final lu = await evaluations.lireNotes(e.id);
      expect(lu[aminata]!.centiemes, 1750);
      expect(lu[ibrahima]!.centiemes, 600);
    });

    test('saisie collective : tout ou rien en cas d\'erreur', () async {
      final e = await evaluer();
      await expectLater(
        evaluations.enregistrerLot(e.id, {
          aminata: const Saisie.valeur(1500),
          eleveB: const Saisie.valeur(1000), // élève d'une autre classe
        }),
        erreurContenant('pas inscrit'),
      );
      expect(await db.query('evaluation_note'), isEmpty);
    });

    test('un élève inconnu est refusé', () async {
      final e = await evaluer();
      await expectLater(
        evaluations.enregistrerNote(
          evaluationId: e.id,
          inscriptionId: 9999,
          saisie: const Saisie.valeur(1000),
        ),
        throwsA(isA<ErreurGesco>()),
      );
    });

    test('évaluation inconnue', () async {
      await expectLater(evaluations.lireNotes(9999), erreurContenant('introuvable'));
      await expectLater(
        evaluations.enregistrerNote(
          evaluationId: 9999,
          inscriptionId: aminata,
          saisie: const Saisie.valeur(1000),
        ),
        erreurContenant('introuvable'),
      );
    });

    test('le nombre de notes de la liste ne compte que les élèves qui suivent la classe', () async {
      final e = await evaluer();
      await evaluations.enregistrerLot(e.id, {
        aminata: const Saisie.valeur(1000),
        ibrahima: const Saisie.valeur(1200),
      });
      var r = (await evaluations.lister(classeId: classeA.id)).single;
      expect((r.nbEleves, r.nbNotes, r.complete), (2, 2, true));
      await eleves.enregistrerSortie(ibrahima, StatutInscription.depart);
      r = (await evaluations.lister(classeId: classeA.id)).single;
      expect((r.nbEleves, r.nbNotes, r.complete), (1, 1, true));
    });

    test('les notes d\'évaluation sont dans l\'historique, avec leur barème', () async {
      final e = await evaluer(bareme: 10);
      await evaluations.enregistrerNote(
        evaluationId: e.id,
        inscriptionId: aminata,
        saisie: const Saisie.surBareme(700, 10),
      );
      await evaluations.enregistrerNote(
        evaluationId: e.id,
        inscriptionId: aminata,
        saisie: const Saisie.surBareme(850, 10),
      );
      final h = await notes.historique(source: 'evaluation');
      expect(h, hasLength(2));
      expect(h.first.ancienTexte, '7,00 / 10');
      expect(h.first.nouveauTexte, '8,50 / 10');
      expect(h.first.evaluationId, e.id);
      expect(h.first.libelleSource, 'Évaluation');
      expect(h.first.matiereNom, 'Maths');
    });
  });

  group('validation et suppression', () {
    test('une évaluation validée n\'accepte plus aucune modification', () async {
      final e = await evaluer();
      await evaluations.enregistrerNote(
        evaluationId: e.id,
        inscriptionId: aminata,
        saisie: const Saisie.valeur(1000),
      );
      await evaluations.valider(e.id);
      expect((await evaluations.obtenir(e.id))!.valide, isTrue);

      await expectLater(
        evaluations.enregistrerNote(
          evaluationId: e.id,
          inscriptionId: ibrahima,
          saisie: const Saisie.valeur(1200),
        ),
        erreurContenant('validée'),
      );
      await expectLater(
        evaluations.enregistrerNote(
          evaluationId: e.id,
          inscriptionId: aminata,
          saisie: null,
        ),
        erreurContenant('validée'),
      );
      await expectLater(evaluations.modifier(e.id, titre: 'X'), erreurContenant('validée'));
      await expectLater(evaluations.supprimer(e.id, avecNotes: true), erreurContenant('validée'));

      await evaluations.valider(e.id, valide: false);
      await evaluations.enregistrerNote(
        evaluationId: e.id,
        inscriptionId: ibrahima,
        saisie: const Saisie.valeur(1200),
      );
      expect(await evaluations.lireNotes(e.id), hasLength(2));
    });

    test('valider deux fois est sans effet, évaluation inconnue refusée', () async {
      final e = await evaluer();
      await evaluations.valider(e.id);
      await evaluations.valider(e.id);
      await expectLater(evaluations.valider(9999), erreurContenant('introuvable'));
    });

    test('supprimer une évaluation sans note', () async {
      final e = await evaluer();
      await evaluations.supprimer(e.id);
      expect(await evaluations.obtenir(e.id), isNull);
      await expectLater(evaluations.supprimer(e.id), erreurContenant('introuvable'));
    });

    test('avec des notes : confirmation demandée, puis suppression gardée dans l\'historique',
        () async {
      final e = await evaluer();
      await evaluations.enregistrerLot(e.id, {
        aminata: const Saisie.valeur(1000),
        ibrahima: const Saisie.valeur(1200),
      });
      await expectLater(
        evaluations.supprimer(e.id),
        throwsA(
          isA<ErreurAConfirmer>()
              .having((x) => x.sujet, 'sujet', 'pertes')
              .having((x) => x.message, 'message', contains('2 notes')),
        ),
      );
      expect(await evaluations.obtenir(e.id), isNotNull);
      expect(await evaluations.lireNotes(e.id), hasLength(2));

      await evaluations.supprimer(e.id, avecNotes: true);
      expect(await evaluations.obtenir(e.id), isNull);
      expect(await db.query('evaluation_note'), isEmpty);
      final h = await notes.historique(source: 'evaluation');
      expect(h.where((x) => x.operation == 'suppression'), hasLength(2));
    });

    test('sans permission de gestion, rien n\'est modifié', () async {
      final e = await evaluer();
      final sans = EvaluationDepot(
        db,
        notes: notes,
        controle: const Controle(autorisations: _Autorisations({Permission.notesSaisir})),
      );
      await expectLater(
        sans.creer(classeId: classeA.id, matiereId: maths.id, mois: 10, titre: 'X'),
        erreurContenant('pas l\'autorisation'),
      );
      await expectLater(sans.supprimer(e.id), erreurContenant('pas l\'autorisation'));
      await expectLater(sans.valider(e.id), erreurContenant('pas l\'autorisation'));
      // Mais la saisie est permise.
      await sans.enregistrerNote(
        evaluationId: e.id,
        inscriptionId: aminata,
        saisie: const Saisie.valeur(1000),
      );
      final sansSaisie = EvaluationDepot(
        db,
        notes: notes,
        controle: const Controle(autorisations: _Autorisations({})),
      );
      await expectLater(
        sansSaisie.enregistrerNote(
          evaluationId: e.id,
          inscriptionId: ibrahima,
          saisie: const Saisie.valeur(1000),
        ),
        erreurContenant('pas l\'autorisation'),
      );
    });

    test('un compte lié à un enseignant ne gère que les évaluations de ses matières', () async {
      final enseignants = EnseignantDepot(db);
      final prof = await enseignants.creer(const Enseignant(nom: 'Barry', prenom: 'Oumar'));
      await matieres.modifier(maths.id, enseignantId: prof);
      final limite = EvaluationDepot(
        db,
        notes: notes,
        controle: Controle(
          autorisations: _Autorisations(
            {Permission.evaluationsGerer, Permission.notesSaisir},
            limite: prof,
          ),
        ),
      );
      final e = await limite.creer(
        classeId: classeA.id,
        matiereId: maths.id,
        mois: 10,
        titre: 'Mon devoir',
      );
      await limite.enregistrerNote(
        evaluationId: e.id,
        inscriptionId: aminata,
        saisie: const Saisie.valeur(1000),
      );
      await expectLater(
        limite.creer(classeId: classeA.id, matiereId: sciences.id, mois: 10, titre: 'Autre'),
        erreurContenant('vous sont confiées'),
      );
      final autre = await evaluer(matiereId: sciences.id, titre: 'Sciences');
      await expectLater(
        limite.enregistrerNote(
          evaluationId: autre.id,
          inscriptionId: aminata,
          saisie: const Saisie.surBareme(1000, 40),
        ),
        erreurContenant('vous sont confiées'),
      );
      await expectLater(limite.supprimer(autre.id), erreurContenant('vous sont confiées'));
    });
  });

  group('statistiques d\'une évaluation', () {
    test('moyenne, extrêmes, réussite, absents', () async {
      final e = await evaluer(bareme: 10);
      final troisieme = await eleves.inscrire(
        const Eleve(matricule: '2026-0004', nom: 'CAMARA', prenom: 'X', sexe: 'F'),
        anneeId: anneeId,
        classeId: classeA.id,
      );
      await eleves.inscrire(
        const Eleve(matricule: '2026-0005', nom: 'TOURE', prenom: 'X', sexe: 'F'),
        anneeId: anneeId,
        classeId: classeA.id,
      );
      await evaluations.enregistrerLot(e.id, {
        aminata: const Saisie.surBareme(800, 10), // 16/20 : réussite
        ibrahima: const Saisie.surBareme(400, 10), // 8/20 : échec
        troisieme: const Saisie.absent(),
      });
      final s = await evaluations.statistiques(e.id);
      expect(s.bareme, 10);
      expect(s.nbEleves, 4);
      expect(s.nbSaisies, 2);
      expect(s.nbAbsents, 1);
      expect(s.nbDispenses, 0);
      expect(s.nbNonSaisis, 1);
      expect(s.moyenne, 600); // 6 sur 10
      expect(s.moyenneSur20, 1200);
      expect(s.minimum, 400);
      expect(s.maximum, 800);
      expect(s.nbReussites, 1);
      expect(s.tauxReussite, 50.0);
    });

    test('le seuil de réussite est réglable', () async {
      final e = await evaluer();
      await evaluations.enregistrerLot(e.id, {
        aminata: const Saisie.valeur(1000),
        ibrahima: const Saisie.valeur(1400),
      });
      expect((await evaluations.statistiques(e.id)).nbReussites, 2);
      expect((await evaluations.statistiques(e.id, seuilAdmission: 1200)).nbReussites, 1);
      expect((await evaluations.statistiques(e.id, seuilAdmission: 1500)).nbReussites, 0);
    });

    test('sans note : pas de moyenne ni de taux', () async {
      final e = await evaluer();
      final s = await evaluations.statistiques(e.id);
      expect((s.moyenne, s.moyenneSur20, s.minimum, s.maximum), (null, null, null, null));
      expect(s.tauxReussite, isNull);
      expect(s.nbNonSaisis, 2);
      await expectLater(evaluations.statistiques(9999), erreurContenant('introuvable'));
    });

    test('les élèves partis ne comptent pas', () async {
      final e = await evaluer();
      await evaluations.enregistrerLot(e.id, {
        aminata: const Saisie.valeur(1000),
        ibrahima: const Saisie.valeur(2000),
      });
      await eleves.enregistrerSortie(ibrahima, StatutInscription.abandon);
      final s = await evaluations.statistiques(e.id);
      expect(s.nbEleves, 1);
      expect(s.nbSaisies, 1);
      expect(s.moyenne, 1000);
    });
  });

  group('notes du mois d\'après les évaluations', () {
    test('sans évaluation : les notes mensuelles sont rendues telles quelles', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      final r = await evaluations.saisiesEffectives(classeA.id);
      expect(r.saisies[aminata]![maths.id]![10], const Saisie.valeur(1000));
      expect(r.casesEvaluees, isEmpty);
      expect(r.estEvaluee(maths.id, 10), isFalse);
    });

    test('moyenne pondérée par les coefficients, barèmes mélangés', () async {
      final d1 = await evaluer(titre: 'D1', coefficient: 100); // sur 20
      final d2 = await evaluer(titre: 'D2', coefficient: 200, bareme: 10);
      await evaluations.enregistrerNote(
        evaluationId: d1.id,
        inscriptionId: aminata,
        saisie: const Saisie.valeur(1000), // 10
      );
      await evaluations.enregistrerNote(
        evaluationId: d2.id,
        inscriptionId: aminata,
        saisie: const Saisie.surBareme(800, 10), // 16/20
      );
      // (10 x 1 + 16 x 2) / 3 = 14
      final r = await evaluations.saisiesEffectives(classeA.id);
      expect(r.saisies[aminata]![maths.id]![10], const Saisie.valeur(1400));
      expect(r.estEvaluee(maths.id, 10), isTrue);
      expect(r.estEvaluee(maths.id, 11), isFalse);
      expect(r.estEvaluee(sciences.id, 10), isFalse);
    });

    test('un élève sans note d\'évaluation reste non saisi, même avec une ancienne note directe',
        () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1800));
      await noter(ibrahima, maths.id, 10, const Saisie.valeur(1100));
      final e = await evaluer();
      await evaluations.enregistrerNote(
        evaluationId: e.id,
        inscriptionId: aminata,
        saisie: const Saisie.valeur(1200),
      );
      final r = await evaluations.saisiesEffectives(classeA.id);
      expect(r.saisies[aminata]![maths.id]![10], const Saisie.valeur(1200));
      expect(r.saisies[ibrahima]?[maths.id]?[10], isNull);
      // L'ancienne note directe n'est pas supprimée de la base.
      expect(await notes.compterClasse(classeA.id), 2);
    });

    test('les autres mois et matières gardent leurs notes directes', () async {
      await noter(aminata, maths.id, 11, const Saisie.valeur(1500));
      await noter(aminata, sciences.id, 10, const Saisie.surBareme(3000, 40));
      final e = await evaluer(mois: 10);
      await evaluations.enregistrerNote(
        evaluationId: e.id,
        inscriptionId: aminata,
        saisie: const Saisie.valeur(1000),
      );
      final r = await evaluations.saisiesEffectives(classeA.id);
      expect(r.saisies[aminata]![maths.id]![11], const Saisie.valeur(1500));
      expect(r.saisies[aminata]![sciences.id]![10], const Saisie.surBareme(3000, 40));
      expect(r.saisies[aminata]![maths.id]![10], const Saisie.valeur(1000));
    });

    test('absent ignoré, ou compté zéro avec l\'option', () async {
      final d1 = await evaluer(titre: 'D1');
      final d2 = await evaluer(titre: 'D2');
      await evaluations.enregistrerNote(
        evaluationId: d1.id,
        inscriptionId: aminata,
        saisie: const Saisie.valeur(1200),
      );
      await evaluations.enregistrerNote(
        evaluationId: d2.id,
        inscriptionId: aminata,
        saisie: const Saisie.absent(),
      );
      var r = await evaluations.saisiesEffectives(classeA.id);
      expect(r.saisies[aminata]![maths.id]![10], const Saisie.valeur(1200));
      r = await evaluations.saisiesEffectives(classeA.id, absenceEgaleZero: true);
      expect(r.saisies[aminata]![maths.id]![10], const Saisie.valeur(600));
    });

    test('absent partout : la case est absente', () async {
      final e = await evaluer();
      await evaluations.enregistrerNote(
        evaluationId: e.id,
        inscriptionId: aminata,
        saisie: const Saisie.absent(),
      );
      final r = await evaluations.saisiesEffectives(classeA.id);
      expect(r.saisies[aminata]![maths.id]![10], const Saisie.absent());
    });

    test('une évaluation sans aucune note rend la case non saisie', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1800));
      await evaluer();
      final r = await evaluations.saisiesEffectives(classeA.id);
      expect(r.saisies[aminata]?[maths.id]?[10], isNull);
      expect(r.estEvaluee(maths.id, 10), isTrue);
    });

    test('la saisie directe est refusée dans un mois évalué, mais on peut vider la case',
        () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1800));
      await evaluer();
      await expectLater(
        noter(ibrahima, maths.id, 10, const Saisie.valeur(1000)),
        erreurContenant('1 évaluation'),
      );
      await expectLater(
        noter(aminata, maths.id, 10, const Saisie.valeur(1000)),
        erreurContenant('calculée'),
      );
      await noter(aminata, maths.id, 10, null);
      expect(await notes.compterClasse(classeA.id), 0);
    });

    test('le mois redevient en saisie directe quand la dernière évaluation est supprimée',
        () async {
      final e = await evaluer();
      await evaluations.supprimer(e.id);
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      final r = await evaluations.saisiesEffectives(classeA.id);
      expect(r.estEvaluee(maths.id, 10), isFalse);
      expect(r.saisies[aminata]![maths.id]![10], const Saisie.valeur(1000));
    });
  });

  group('barème par défaut', () {
    test('20 tant qu\'on n\'a rien choisi, modifiable, contrôlé et journalisé', () async {
      final p = ParametreDepot(db);
      expect(await p.baremeDefaut(), 20);
      await p.definirBaremeDefaut(40);
      expect(await p.baremeDefaut(), 40);
      await expectLater(p.definirBaremeDefaut(0), erreurContenant('barème'));
      await expectLater(p.definirBaremeDefaut(1001), erreurContenant('barème'));
      expect(await p.baremeDefaut(), 40);
    });

    test('une valeur illisible en base retombe sur 20', () async {
      final p = ParametreDepot(db);
      await p.ecrire(CleParametre.baremeDefaut, 'abc');
      expect(await p.baremeDefaut(), 20);
      await p.ecrire(CleParametre.baremeDefaut, '5000');
      expect(await p.baremeDefaut(), 20);
    });

    test('sans la permission des paramètres, le barème ne change pas', () async {
      final p = ParametreDepot(
        db,
        controle: const Controle(autorisations: _Autorisations({})),
      );
      await expectLater(p.definirBaremeDefaut(10), erreurContenant('pas l\'autorisation'));
      expect(await p.baremeDefaut(), 20);
    });
  });
}
