import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_notation.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/ui/evaluations/dialogue_evaluation.dart';
import 'package:gesco/ui/evaluations/dialogue_saisie_collective.dart';
import 'package:gesco/ui/evaluations/vue_evaluations.dart';
import 'package:gesco/ui/notes/page_notes.dart';
import 'package:gesco/ui/parametres/onglet_notation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ce que la fenêtre a renvoyé en se fermant.
class Retour<T> {
  T? valeur;
  bool ferme = false;
}

/// Affiche [dialogue] au-dessus d'une page vide, sur un grand écran de test.
Future<Retour<T>> ouvrir<T>(WidgetTester tester, Widget dialogue) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final retour = Retour<T>();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                retour.valeur = await showDialog<T>(
                  context: context,
                  builder: (_) => dialogue,
                );
                retour.ferme = true;
              },
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
  return retour;
}

const List<MatiereClasse> matieres = [
  MatiereClasse(id: 1, classeId: 10, nom: 'Maths', coefficient: 400, ordre: 1),
  MatiereClasse(id: 2, classeId: 10, nom: 'Sciences', coefficient: 200, ordre: 2, bareme: 40),
];

const List<EleveInscrit> eleves = [
  EleveInscrit(
    inscriptionId: 1,
    eleveId: 1,
    classeId: 10,
    classeNom: '10e A',
    matricule: '2026-0001',
    nom: 'DIALLO',
    prenom: 'Aminata',
    sexe: 'F',
  ),
  EleveInscrit(
    inscriptionId: 2,
    eleveId: 2,
    classeId: 10,
    classeNom: '10e A',
    matricule: '2026-0002',
    nom: 'BARRY',
    prenom: 'Ibrahima',
    sexe: 'M',
  ),
];

Evaluation evaluationDe({int bareme = 20, bool valide = false}) => Evaluation(
      id: 5,
      classeId: 10,
      matiereId: 1,
      mois: 11,
      type: TypeEvaluation.devoir,
      titre: 'Devoir 1',
      coefficient: 100,
      bareme: bareme,
      valide: valide,
    );

void main() {
  sqfliteFfiInit();

  group('DialogueEvaluation', () {
    testWidgets('renvoie la fiche saisie', (tester) async {
      final retour = await ouvrir<SaisieEvaluation>(
        tester,
        const DialogueEvaluation(matieres: matieres, moisInitial: 11),
      );
      await tester.enterText(find.byKey(const Key('champ_titre')), '  Devoir 1 ');
      await tester.enterText(find.byKey(const Key('champ_coefficient')), '2,5');
      await tester.enterText(find.byKey(const Key('champ_date')), '17/11/2026');
      await tester.tap(find.byKey(const Key('enregistrer_evaluation')));
      await tester.pumpAndSettle();

      expect(retour.ferme, isTrue);
      final f = retour.valeur!;
      expect(f.titre, 'Devoir 1');
      expect(f.type, TypeEvaluation.evaluation);
      expect(f.matiereId, 1);
      expect(f.mois, 11);
      expect(f.coefficient, 250);
      expect(f.bareme, 20);
      expect(f.date, '2026-11-17');
    });

    testWidgets('le barème suit la matière tant qu\'on n\'a pas choisi le sien',
        (tester) async {
      final retour = await ouvrir<SaisieEvaluation>(
        tester,
        const DialogueEvaluation(matieres: matieres, moisInitial: 10),
      );
      expect(tester.widget<TextField>(find.byKey(const Key('champ_bareme'))).controller!.text,
          '20');

      await tester.tap(find.byKey(const Key('choix_matiere')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sciences').last);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('champ_bareme'))).controller!.text,
          '40');

      await tester.enterText(find.byKey(const Key('champ_titre')), 'Composition');
      await tester.tap(find.byKey(const Key('enregistrer_evaluation')));
      await tester.pumpAndSettle();
      expect(retour.valeur!.matiereId, 2);
      expect(retour.valeur!.bareme, 40);
    });

    testWidgets('titre, coefficient, barème et date invalides sont refusés',
        (tester) async {
      final retour = await ouvrir<SaisieEvaluation>(
        tester,
        const DialogueEvaluation(matieres: matieres, moisInitial: 10),
      );
      await tester.enterText(find.byKey(const Key('champ_coefficient')), '0');
      await tester.enterText(find.byKey(const Key('champ_bareme')), '2000');
      await tester.enterText(find.byKey(const Key('champ_date')), '31/02/2026');
      await tester.tap(find.byKey(const Key('enregistrer_evaluation')));
      await tester.pumpAndSettle();

      expect(find.text('Le titre est obligatoire.'), findsOneWidget);
      expect(find.textContaining('Coefficient invalide'), findsOneWidget);
      expect(find.textContaining('Barème invalide'), findsOneWidget);
      expect(find.textContaining('Date invalide'), findsOneWidget);
      expect(retour.ferme, isFalse);
    });

    testWidgets('modification : mois et barème figés quand des notes existent',
        (tester) async {
      await ouvrir<SaisieEvaluation>(
        tester,
        DialogueEvaluation(
          matieres: matieres,
          moisInitial: 11,
          existante: evaluationDe(),
          verrouillerMoisEtBareme: true,
        ),
      );
      expect(tester.widget<TextField>(find.byKey(const Key('champ_bareme'))).enabled, isFalse);
      expect(find.text('Des notes existent déjà.'), findsWidgets);
      // La matière ne se change pas : pas de liste déroulante.
      expect(find.byKey(const Key('choix_matiere')), findsNothing);
      expect(find.text('Modifier l\'évaluation'), findsOneWidget);
    });
  });

  group('DialogueSaisieCollective', () {
    Widget dialogue({
      Map<int, Saisie> notes = const {},
      String? motif,
      int bareme = 20,
    }) =>
        DialogueSaisieCollective(
          evaluation: evaluationDe(bareme: bareme),
          matiereNom: 'Maths',
          eleves: eleves,
          notes: notes,
          motifLecture: motif,
        );

    testWidgets('ne renvoie que les notes modifiées', (tester) async {
      final retour = await ouvrir<Map<int, Saisie?>>(
        tester,
        dialogue(notes: {1: const Saisie.valeur(1400)}),
      );
      // La note existante est affichée.
      expect(tester.widget<TextField>(find.byKey(const Key('note_1'))).controller!.text,
          '14,00');
      await tester.enterText(find.byKey(const Key('note_2')), '9,5');
      await tester.tap(find.byKey(const Key('enregistrer_notes')));
      await tester.pumpAndSettle();

      expect(retour.ferme, isTrue);
      expect(retour.valeur!.keys, [2]);
      expect(retour.valeur![2]!.centiemes, 950);
    });

    testWidgets('A = absent, D = dispensé, champ vidé = note effacée', (tester) async {
      final retour = await ouvrir<Map<int, Saisie?>>(
        tester,
        dialogue(notes: {1: const Saisie.valeur(1400)}),
      );
      await tester.enterText(find.byKey(const Key('note_1')), '');
      await tester.enterText(find.byKey(const Key('note_2')), 'a');
      await tester.tap(find.byKey(const Key('enregistrer_notes')));
      await tester.pumpAndSettle();

      expect(retour.valeur!.keys.toSet(), {1, 2});
      expect(retour.valeur![1], isNull);
      expect(retour.valeur![2]!.etat, EtatNote.absent);
    });

    testWidgets('une note invalide bloque l\'enregistrement et est signalée',
        (tester) async {
      final retour = await ouvrir<Map<int, Saisie?>>(tester, dialogue());
      await tester.enterText(find.byKey(const Key('note_1')), '25');
      await tester.enterText(find.byKey(const Key('note_2')), '12');
      await tester.tap(find.byKey(const Key('enregistrer_notes')));
      await tester.pumpAndSettle();

      expect(retour.ferme, isFalse);
      expect(find.textContaining('dépasse 20'), findsOneWidget);
      expect(find.textContaining('1 note est invalide'), findsOneWidget);

      // Corriger efface le message d'erreur de la ligne.
      await tester.enterText(find.byKey(const Key('note_1')), '15');
      await tester.pump();
      expect(find.textContaining('dépasse 20'), findsNothing);
      await tester.tap(find.byKey(const Key('enregistrer_notes')));
      await tester.pumpAndSettle();
      expect(retour.valeur!.keys.toSet(), {1, 2});
    });

    testWidgets('sur un barème de 40, 31 est accepté et converti sur 20', (tester) async {
      final retour = await ouvrir<Map<int, Saisie?>>(tester, dialogue(bareme: 40));
      await tester.enterText(find.byKey(const Key('note_1')), '31');
      await tester.tap(find.byKey(const Key('enregistrer_notes')));
      await tester.pumpAndSettle();
      expect(retour.valeur![1]!.brut, 3100);
      expect(retour.valeur![1]!.bareme, 40);
      expect(retour.valeur![1]!.centiemes, 1550);
    });

    testWidgets('aucune modification : la fenêtre reste ouverte avec un message',
        (tester) async {
      final retour = await ouvrir<Map<int, Saisie?>>(tester, dialogue());
      await tester.tap(find.byKey(const Key('enregistrer_notes')));
      await tester.pumpAndSettle();
      expect(retour.ferme, isFalse);
      expect(find.text('Aucune note n\'a changé.'), findsOneWidget);
    });

    testWidgets('Entrée passe à l\'élève suivant', (tester) async {
      await ouvrir<Map<int, Saisie?>>(tester, dialogue());
      await tester.tap(find.byKey(const Key('note_1')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('note_1')), '12');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.enterText(find.byKey(const Key('note_2')), '8');
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const Key('note_2'))).focusNode!.hasFocus,
          isTrue);
    });

    testWidgets('lecture seule : motif affiché, champs désactivés, pas d\'enregistrement',
        (tester) async {
      await ouvrir<Map<int, Saisie?>>(
        tester,
        dialogue(
          notes: {1: const Saisie.valeur(1400)},
          motif: 'Évaluation validée : annulez la validation pour modifier les notes.',
        ),
      );
      expect(find.textContaining('Évaluation validée'), findsOneWidget);
      expect(find.byKey(const Key('enregistrer_notes')), findsNothing);
      expect(tester.widget<TextField>(find.byKey(const Key('note_1'))).enabled, isFalse);
      expect(find.text('Fermer'), findsOneWidget);
    });
  });

  group('avec la base de données', () {
    late GescoDatabase gdb;
    late EtatApp etat;
    late int classeId;
    late int maths;
    late int sciences;
    late int aminata;
    late int ibrahima;

    Future<void> demarrer(WidgetTester tester, Widget Function(EtatApp) page) async {
      tester.view.physicalSize = const Size(1500, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      gdb = (await tester.runAsync(() => GescoDatabase.ouvrir(
            fabrique: databaseFactoryFfi,
            chemin: inMemoryDatabasePath,
          )))!;
      etat = EtatApp(
        Services(gdb, session: Session.sansControle(), iterations: 2),
        chemin: 'en mémoire',
      );
      await tester.runAsync(() async {
        final s = etat.services;
        final annee = await s.annees.creer('2026-2027', activer: true);
        final classe = await s.classes.creer(anneeId: annee.id, nom: '10e A');
        classeId = classe.id;
        maths = (await s.matieres.ajouter(classeId: classeId, nom: 'Maths', coefficient: 400)).id;
        sciences = (await s.matieres.ajouter(
          classeId: classeId,
          nom: 'Sciences',
          coefficient: 200,
          bareme: 40,
        ))
            .id;
        Future<int> inscrire(String matricule, String nom) => s.eleves.inscrire(
              Eleve(matricule: matricule, nom: nom, prenom: 'X', sexe: 'F'),
              anneeId: annee.id,
              classeId: classeId,
            );
        aminata = await inscrire('2026-0001', 'DIALLO');
        ibrahima = await inscrire('2026-0002', 'BARRY');
        await etat.charger();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: etat,
              builder: (context, _) => page(etat),
            ),
          ),
        ),
      );
    }

    Future<void> fin(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => gdb.fermer());
    }

    /// Attend (en temps réel, pour laisser la base répondre) qu'un élément apparaisse.
    Future<void> attendre(WidgetTester tester, Finder f) async {
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
        if (f.evaluate().isNotEmpty) return;
      }
      fail('Élément introuvable : $f');
    }

    Widget vueEvaluations(EtatApp e) => VueEvaluations(
          etat: e,
          classeId: null,
          surClasse: (_) {},
          allerAuxParametres: () {},
          maintenant: () => DateTime(2026, 11, 5),
        );

    Widget pageNotes(EtatApp e) => PageNotes(
          etat: e,
          allerAuxParametres: () {},
          allerAuxInscriptions: () {},
          maintenant: () => DateTime(2026, 11, 5),
        );

    Future<int> creerEvaluation({int? matiere, String titre = 'Devoir 1', int mois = 11}) async {
      final e = await etat.services.evaluations.creer(
        classeId: classeId,
        matiereId: matiere ?? maths,
        mois: mois,
        titre: titre,
      );
      return e.id;
    }

    testWidgets('liste vide, puis création d\'une évaluation', (tester) async {
      await demarrer(tester, vueEvaluations);
      await attendre(tester, find.textContaining('Aucune évaluation pour la classe 10e A'));

      await tester.tap(find.byKey(const Key('nouvelle_evaluation')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('champ_titre')), 'Devoir 1');
      await tester.tap(find.byKey(const Key('enregistrer_evaluation')));
      await tester.pump();
      // (« Devoir 1 » se trouve aussi dans le champ de la fenêtre : on attend
      // la ligne de détail de la carte.)
      await attendre(tester, find.text('Maths · Novembre · coef 1 · sur 20'));
      await tester.pumpAndSettle();

      final lignes = await tester.runAsync(() => gdb.db.query('evaluation'));
      expect(lignes, hasLength(1));
      expect(lignes!.first['titre'], 'Devoir 1');
      expect(lignes.first['mois'], 11, reason: 'le mois proposé est celui de la date du jour');
      expect(lignes.first['bareme'], 20);
      expect(find.text('Maths · Novembre · coef 1 · sur 20'), findsOneWidget);
      expect(find.text('0 / 2 notes'), findsOneWidget);
      await fin(tester);
    });

    testWidgets('saisie collective : notes enregistrées et avancement mis à jour',
        (tester) async {
      await demarrer(tester, vueEvaluations);
      final id = (await tester.runAsync(creerEvaluation))!;
      etat.donneesModifiees();
      await attendre(tester, find.byKey(Key('saisir_$id')));

      await tester.tap(find.byKey(Key('saisir_$id')));
      await tester.pump();
      await attendre(tester, find.byKey(const Key('enregistrer_notes')));
      await tester.enterText(find.byKey(Key('note_$aminata')), '15');
      await tester.enterText(find.byKey(Key('note_$ibrahima')), 'a');
      await tester.tap(find.byKey(const Key('enregistrer_notes')));
      await tester.pump();
      await attendre(tester, find.text('2 / 2 notes'));
      await tester.pumpAndSettle();

      final notes = await tester.runAsync(() => gdb.db.query('evaluation_note'));
      expect(notes, hasLength(2));
      final parEleve = {for (final n in notes!) n['inscription_id'] as int: n};
      expect(parEleve[aminata]!['etat'], 'saisie');
      expect(parEleve[aminata]!['brut'], 1500);
      expect(parEleve[ibrahima]!['etat'], 'absent');
      await fin(tester);
    });

    testWidgets('validation : les notes deviennent consultables sans modification',
        (tester) async {
      await demarrer(tester, vueEvaluations);
      final id = (await tester.runAsync(creerEvaluation))!;
      etat.donneesModifiees();
      await attendre(tester, find.byKey(Key('valider_$id')));

      await tester.tap(find.byKey(Key('valider_$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Valider'));
      await tester.pump();
      await attendre(tester, find.text('Validée'));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      final lignes = await tester.runAsync(() => gdb.db.query('evaluation'));
      expect(lignes!.first['valide'], 1);

      await tester.tap(find.byKey(Key('saisir_$id')));
      await tester.pump();
      await attendre(tester, find.byKey(const Key('aide_saisie_collective')));
      expect(find.textContaining('Évaluation validée'), findsWidgets);
      expect(find.byKey(const Key('enregistrer_notes')), findsNothing);
      await fin(tester);
    });

    testWidgets('suppression d\'une évaluation notée : deux confirmations',
        (tester) async {
      await demarrer(tester, vueEvaluations);
      final id = (await tester.runAsync(() async {
        final id = await creerEvaluation();
        await etat.services.evaluations.enregistrerNote(
          evaluationId: id,
          inscriptionId: aminata,
          saisie: const Saisie.valeur(1200),
        );
        return id;
      }))!;
      etat.donneesModifiees();
      await attendre(tester, find.byKey(Key('supprimer_$id')));
      expect(find.text('1 / 2 notes'), findsOneWidget);

      await tester.tap(find.byKey(Key('supprimer_$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pump();
      await attendre(tester, find.text('Supprimer les notes ?'));
      expect(find.textContaining('contient 1 note'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Tout supprimer'));
      await tester.pump();
      await attendre(tester, find.textContaining('Aucune évaluation pour la classe 10e A'));

      expect(await tester.runAsync(() => gdb.db.query('evaluation')), isEmpty);
      expect(await tester.runAsync(() => gdb.db.query('evaluation_note')), isEmpty);
      await fin(tester);
    });

    testWidgets('les filtres par matière et par mois restreignent la liste',
        (tester) async {
      await demarrer(tester, vueEvaluations);
      await tester.runAsync(() async {
        await creerEvaluation(titre: 'Devoir maths');
        await creerEvaluation(matiere: sciences, titre: 'Test sciences', mois: 12);
      });
      etat.donneesModifiees();
      await attendre(tester, find.text('Test sciences'));
      expect(find.text('Devoir maths'), findsOneWidget);

      await tester.tap(find.byKey(const Key('filtre_matiere')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sciences').last);
      await tester.pump();
      await attendre(tester, find.text('Test sciences'));
      await tester.pumpAndSettle();
      expect(find.text('Devoir maths'), findsNothing);
      // Barème hérité de la matière : sur 40.
      expect(find.textContaining('sur 40'), findsOneWidget);

      await tester.tap(find.byKey(const Key('filtre_mois')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Novembre').last);
      await tester.pump();
      await attendre(tester, find.textContaining('Aucune évaluation ne correspond'));
      await fin(tester);
    });

    testWidgets('statistiques d\'une évaluation', (tester) async {
      await demarrer(tester, vueEvaluations);
      final id = (await tester.runAsync(() async {
        final id = await creerEvaluation();
        await etat.services.evaluations.enregistrerLot(id, {
          aminata: const Saisie.valeur(1500),
          ibrahima: const Saisie.valeur(500),
        });
        return id;
      }))!;
      etat.donneesModifiees();
      await attendre(tester, find.byKey(Key('stats_$id')));

      await tester.tap(find.byKey(Key('stats_$id')));
      await tester.pump();
      await attendre(tester, find.textContaining('Statistiques'));
      await tester.pumpAndSettle();
      expect(find.text('10,00 / 20'), findsOneWidget, reason: 'moyenne de la classe');
      expect(find.text('15,00 / 20'), findsOneWidget, reason: 'meilleure note');
      expect(find.text('5,00 / 20'), findsOneWidget, reason: 'note la plus basse');
      expect(find.text('50,0 % (1 / 2)'), findsOneWidget, reason: 'taux de réussite');
      await fin(tester);
    });

    testWidgets('la page Notes : vues, verrouillage d\'un mois et historique',
        (tester) async {
      await demarrer(tester, pageNotes);
      await attendre(tester, find.byKey(const Key('bouton_verrou')));
      expect(find.byKey(const Key('vue_historique')), findsOneWidget);

      // Verrouiller novembre.
      await tester.tap(find.byKey(const Key('bouton_verrou')));
      await tester.pump();
      await attendre(tester, find.text('Verrouiller Novembre ?'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Verrouiller'));
      await tester.pump();
      await attendre(tester, find.text('Mois verrouillé'));
      expect(await tester.runAsync(() => gdb.db.query('verrou_notes')), hasLength(1));
      expect(find.byKey(const Key('case_lecture_0_0')), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Déverrouiller.
      await tester.tap(find.byKey(const Key('bouton_verrou')));
      await tester.pump();
      await attendre(tester, find.text('Déverrouiller Novembre ?'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Déverrouiller'));
      await tester.pump();
      await attendre(tester, find.byKey(const Key('case_0_0')));
      expect(await tester.runAsync(() => gdb.db.query('verrou_notes')), isEmpty);
      await fin(tester);
    });

    testWidgets('historique : saisie puis modification, avec filtres', (tester) async {
      await demarrer(tester, pageNotes);
      await tester.runAsync(() async {
        final notes = etat.services.notes;
        await notes.enregistrer(
          inscriptionId: aminata,
          matiereId: maths,
          mois: 11,
          saisie: const Saisie.valeur(1400),
        );
        await notes.enregistrer(
          inscriptionId: aminata,
          matiereId: maths,
          mois: 11,
          saisie: const Saisie.valeur(1600),
        );
      });
      etat.donneesModifiees();
      await attendre(tester, find.byKey(const Key('vue_historique')));

      await tester.tap(find.byKey(const Key('vue_historique')));
      await tester.pump();
      await attendre(tester, find.byKey(const Key('histo_total')));
      expect(find.textContaining('2 modifications'), findsOneWidget);
      expect(find.text('Saisie (Note du mois) : — → 14,00 / 20'), findsOneWidget);
      expect(find.text('Modification (Note du mois) : 14,00 / 20 → 16,00 / 20'),
          findsOneWidget);
      expect(find.text('DIALLO X · Maths · Novembre'), findsNWidgets(2));

      // Filtre « Évaluations » : aucune ligne.
      await tester.tap(find.byKey(const Key('histo_filtre_source')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Évaluations').last);
      await tester.pump();
      await attendre(tester, find.textContaining('Aucune modification de note ne correspond'));
      await fin(tester);
    });

    testWidgets('la saisie du mois reste libre sans évaluation, interdite avec',
        (tester) async {
      await demarrer(tester, pageNotes);
      await tester.runAsync(() async {
        final id = await creerEvaluation(mois: 11);
        await etat.services.evaluations.enregistrerNote(
          evaluationId: id,
          inscriptionId: aminata,
          saisie: const Saisie.valeur(1800),
        );
      });
      etat.donneesModifiees();
      // Maths (colonne 0) est calculé d'après l'évaluation ; Sciences (colonne 1) reste libre.
      await attendre(tester, find.byKey(const Key('case_lecture_0_0')));
      expect(find.byKey(const Key('case_lecture_0_1')), findsNothing);
      expect(find.byKey(const Key('case_0_1')), findsOneWidget);
      // Les élèves sont triés par nom : BARRY (ligne 0), DIALLO (ligne 1). La
      // note de l'évaluation (18) est la note du mois de DIALLO en maths.
      expect(find.descendant(of: find.byKey(const Key('case_lecture_1_0')), matching: find.text('18,00')),
          findsOneWidget);
      await fin(tester);
    });

    testWidgets('onglet Notation : barème par défaut et convertisseur', (tester) async {
      await demarrer(tester, (e) => OngletNotation(etat: e));
      await attendre(tester, find.byKey(const Key('champ_bareme_defaut')));
      expect(
        tester.widget<TextField>(find.byKey(const Key('champ_bareme_defaut'))).controller!.text,
        '20',
      );

      await tester.tap(find.byKey(const Key('bareme_usuel_40')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('enregistrer_bareme_defaut')));
      await tester.pump();
      await attendre(tester, find.text('Barème par défaut : sur 40.'));
      expect(await tester.runAsync(() => etat.services.parametres.baremeDefaut()), 40);

      // Barème invalide.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('champ_bareme_defaut')), '5000');
      await tester.tap(find.byKey(const Key('enregistrer_bareme_defaut')));
      await tester.pump();
      expect(find.textContaining('Barème invalide'), findsOneWidget);

      // Convertisseur : 7 sur 10 = 14 sur 20 ; 31 sur 40 = 15,5 sur 20.
      await tester.enterText(find.byKey(const Key('conv_note')), '7');
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('conv_resultat'))).data,
          '7,00 sur 10 = 14,00 sur 20');
      await tester.enterText(find.byKey(const Key('conv_de')), '40');
      await tester.enterText(find.byKey(const Key('conv_note')), '31');
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('conv_resultat'))).data,
          '31,00 sur 40 = 15,50 sur 20');
      await tester.enterText(find.byKey(const Key('conv_note')), '45');
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('conv_resultat'))).data,
          'La note doit être un nombre de 0 à 40 (2 décimales au plus).');
      await fin(tester);
    });
  });
}
