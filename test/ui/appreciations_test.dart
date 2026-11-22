import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/depots/appreciation_depot.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/ui/resultats/page_resultats.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late EtatApp etat;
  late int classeA;
  late int mathsA;
  late int francaisA;
  late int barry;
  late int diallo;
  late int camara;
  late int sow;

  Future<void> demarrer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 3000);
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
      final a = await s.classes.creer(anneeId: annee.id, nom: '10e A', niveau: '10e année');
      classeA = a.id;
      mathsA = (await s.matieres.ajouter(classeId: a.id, nom: 'Maths', coefficient: 100)).id;
      francaisA =
          (await s.matieres.ajouter(classeId: a.id, nom: 'Français', coefficient: 100)).id;

      Future<int> inscrire(String matricule, String nom, String prenom, String sexe) =>
          s.eleves.inscrire(
            Eleve(matricule: matricule, nom: nom, prenom: prenom, sexe: sexe),
            anneeId: annee.id,
            classeId: a.id,
          );
      barry = await inscrire('2026-0001', 'BARRY', 'Mamadou', 'M');
      diallo = await inscrire('2026-0002', 'DIALLO', 'Aminata', 'F');
      camara = await inscrire('2026-0003', 'CAMARA', 'Fatou', 'F');
      sow = await inscrire('2026-0004', 'SOW', 'Ibrahima', 'M');

      Future<void> note(int inscription, int matiere, int centiemes) => s.notes.enregistrer(
            inscriptionId: inscription,
            matiereId: matiere,
            mois: 11,
            saisie: Saisie.valeur(centiemes),
          );
      await note(barry, mathsA, 1600);
      await note(diallo, mathsA, 1600);
      await note(sow, mathsA, 1800);
      await s.eleves.enregistrerSortie(sow, StatutInscription.depart, motif: 'Déménagement');
      await etat.charger();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: etat,
            builder: (context, _) => PageResultats(
              etat: etat,
              allerAuxParametres: () {},
              maintenant: () => DateTime(2026, 11, 5),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> attendre(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      if (f.evaluate().isNotEmpty) return;
    }
    fail('Élément introuvable : $f');
  }

  /// Laisse passer du temps réel tant que [condition] est fausse.
  Future<void> jusqua(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 60 && !condition(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(condition(), isTrue, reason: 'la condition attendue n\'est jamais arrivée');
  }

  Future<void> fin(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => gdb.fermer());
  }

  Future<void> ouvrirOnglet(WidgetTester tester) async {
    await attendre(tester, find.byKey(const Key('vue_appreciations')));
    await tester.tap(find.byKey(const Key('vue_appreciations')));
    await tester.pump();
    await attendre(tester, find.byKey(Key('appr_nom_$barry')));
  }

  String texte(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  String saisi(WidgetTester tester, String cle) =>
      tester.widget<TextField>(find.byKey(Key(cle))).controller!.text;

  Future<Map<int, AppreciationEleve>> enBase(WidgetTester tester, String periode) async =>
      (await tester.runAsync(() => etat.services.appreciations.eleves(classeA, periode)))!;

  bool enregistrerActif(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('enregistrer_appreciations'))).onPressed !=
      null;

  /// Vrai si le champ existe et contient [valeur].
  bool contient(WidgetTester tester, String cle, String valeur) =>
      find.byKey(Key(cle)).evaluate().isNotEmpty && saisi(tester, cle) == valeur;

  testWidgets('élèves actifs listés avec leur moyenne, élève parti absent', (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);

    expect(texte(tester, 'appr_nom_$barry'), 'BARRY Mamadou');
    expect(find.byKey(Key('appr_nom_$diallo')), findsOneWidget);
    expect(find.byKey(Key('appr_nom_$camara')), findsOneWidget);
    expect(find.byKey(Key('appr_nom_$sow')), findsNothing);
    expect(texte(tester, 'appr_moyenne_$barry'), 'Moyenne 16,00 · 1er');
    expect(texte(tester, 'appr_moyenne_$camara'), 'Pas de moyenne');
    expect(enregistrerActif(tester), isFalse, reason: 'rien à enregistrer au départ');
    expect(find.byKey(const Key('appr_modifications')), findsNothing);
    await fin(tester);
  });

  testWidgets('saisir une appréciation et une décision, puis enregistrer', (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);

    await tester.enterText(find.byKey(Key('appr_$barry')), 'Très bon trimestre.');
    await tester.pump();
    expect(find.text('1 modification non enregistrée'), findsOneWidget);
    expect(enregistrerActif(tester), isTrue);

    await tester.tap(find.byKey(Key('suggestions_$barry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('suggestion_0')));
    await tester.pumpAndSettle();
    expect(saisi(tester, 'decision_conseil_$barry'), 'Félicitations du conseil');

    await tester.enterText(find.byKey(Key('appr_$diallo')), 'Peut mieux faire.');
    await tester.pump();
    expect(find.text('2 modifications non enregistrées'), findsOneWidget);

    await tester.tap(find.byKey(const Key('enregistrer_appreciations')));
    await tester.pump();
    await jusqua(tester, () => find.byKey(const Key('appr_modifications')).evaluate().isEmpty);

    final t1 = await enBase(tester, 't1');
    expect(t1[barry]!.appreciation, 'Très bon trimestre.');
    expect(t1[barry]!.decision, 'Félicitations du conseil');
    expect(t1[diallo]!.appreciation, 'Peut mieux faire.');
    expect(t1[diallo]!.decision, '');
    expect(t1.containsKey(camara), isFalse);
    // Après la relecture, l'écran affiche ce qui est enregistré.
    expect(saisi(tester, 'appr_$barry'), 'Très bon trimestre.');
    expect(enregistrerActif(tester), isFalse);
    await fin(tester);
  });

  testWidgets('vider un champ efface l\'appréciation enregistrée', (tester) async {
    await demarrer(tester);
    await tester.runAsync(() => etat.services.appreciations.enregistrerEleves({
          barry: const AppreciationEleve(appreciation: 'À effacer', decision: 'Blâme'),
        }, 't1'));
    etat.donneesModifiees();
    await ouvrirOnglet(tester);
    await jusqua(tester, () => contient(tester, 'appr_$barry', 'À effacer'));

    await tester.enterText(find.byKey(Key('appr_$barry')), '');
    await tester.enterText(find.byKey(Key('decision_conseil_$barry')), '');
    await tester.pump();
    await tester.tap(find.byKey(const Key('enregistrer_appreciations')));
    await tester.pump();
    await jusqua(tester, () => find.byKey(const Key('appr_modifications')).evaluate().isEmpty);
    expect(await enBase(tester, 't1'), isEmpty);
    await fin(tester);
  });

  testWidgets('chaque période a ses propres appréciations', (tester) async {
    await demarrer(tester);
    await tester.runAsync(() => etat.services.appreciations.enregistrerEleves({
          barry: const AppreciationEleve(appreciation: 'Avis du trimestre 1'),
        }, 't1'));
    etat.donneesModifiees();
    await ouvrirOnglet(tester);
    await jusqua(tester, () => contient(tester, 'appr_$barry', 'Avis du trimestre 1'));

    await tester.tap(find.byKey(const Key('choix_portee')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Trimestre 2').last);
    await tester.pump(const Duration(milliseconds: 500));
    // Pas d'appréciation du trimestre 1 affichée pendant le chargement du 2.
    expect(find.text('Avis du trimestre 1'), findsNothing);
    await jusqua(tester, () => contient(tester, 'appr_$barry', ''));

    await tester.enterText(find.byKey(Key('appr_$barry')), 'Avis du trimestre 2');
    await tester.pump();
    await tester.tap(find.byKey(const Key('enregistrer_appreciations')));
    await tester.pump();
    await jusqua(tester, () => find.byKey(const Key('appr_modifications')).evaluate().isEmpty);
    expect((await enBase(tester, 't2'))[barry]!.appreciation, 'Avis du trimestre 2');
    expect((await enBase(tester, 't1'))[barry]!.appreciation, 'Avis du trimestre 1');
    await fin(tester);
  });

  testWidgets('appréciations par matière : saisie puis relecture', (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);
    expect(find.text('Par matière'), findsWidgets);

    await tester.tap(find.byKey(Key('par_matiere_$barry')));
    await tester.pumpAndSettle();
    expect(find.text('Appréciations par matière'), findsOneWidget);
    await tester.enterText(find.byKey(Key('appr_matiere_$mathsA')), 'Bon travail en algèbre.');
    await tester.pump();
    await tester.tap(find.byKey(const Key('enregistrer_appr_matieres')));
    await tester.pumpAndSettle();

    await jusqua(tester, () => find.text('Par matière (1)').evaluate().isNotEmpty);
    final lues = (await tester.runAsync(
        () => etat.services.appreciations.matieres(classeA, 't1')))!;
    expect(lues[barry], {mathsA: 'Bon travail en algèbre.'});

    // Réouverture : le texte est prérempli, l'autre matière est vide.
    await tester.tap(find.byKey(Key('par_matiere_$barry')));
    await tester.pumpAndSettle();
    expect(saisi(tester, 'appr_matiere_$mathsA'), 'Bon travail en algèbre.');
    expect(saisi(tester, 'appr_matiere_$francaisA'), '');
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    await fin(tester);
  });

  testWidgets('appréciations par matière : fermer sans rien changer n\'enregistre rien',
      (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);
    await tester.tap(find.byKey(Key('par_matiere_$barry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('enregistrer_appr_matieres')));
    await tester.pumpAndSettle();
    expect(find.text('Appréciations par matière'), findsNothing);
    final lues = (await tester.runAsync(
        () => etat.services.appreciations.matieres(classeA, 't1')))!;
    expect(lues, isEmpty);
    await fin(tester);
  });

  group('appréciation automatique', () {
    const texteAuto = 'Très bons résultats, il faut continuer ainsi. Points forts : Maths.';

    /// Attend (temps réel) que le réglage enregistré vaille [attendu].
    Future<void> reglage(WidgetTester tester, bool attendu) async {
      var actuel = !attendu;
      for (var i = 0; i < 60 && actuel != attendu; i++) {
        actuel = (await tester.runAsync(
            () => etat.services.parametres.appreciationsAutomatiques()))!;
        if (actuel != attendu) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        }
      }
      expect(actuel, attendu, reason: 'le réglage enregistré n\'a pas la valeur attendue');
    }

    testWidgets('proposée aux élèves qui ont une moyenne et pas d\'appréciation', (tester) async {
      await demarrer(tester);
      await ouvrirOnglet(tester);

      expect(texte(tester, 'appr_auto_$barry'), texteAuto);
      expect(texte(tester, 'appr_auto_$diallo'), texteAuto);
      // Pas de moyenne : rien à proposer. Élève parti : pas de carte.
      expect(find.byKey(Key('appr_auto_$camara')), findsNothing);
      expect(find.byKey(Key('appr_auto_$sow')), findsNothing);
      expect(tester.widget<Switch>(find.byKey(const Key('appr_auto_actif'))).value, isTrue);
      expect(find.text('Utiliser pour 2 élèves'), findsOneWidget);
      // Une proposition n'est pas une saisie : rien à enregistrer.
      expect(saisi(tester, 'appr_$barry'), '');
      expect(enregistrerActif(tester), isFalse);
      await fin(tester);
    });

    testWidgets('« Utiliser » recopie le texte, modifiable puis enregistré', (tester) async {
      await demarrer(tester);
      await ouvrirOnglet(tester);

      await tester.tap(find.byKey(Key('appr_utiliser_$barry')));
      await tester.pump();
      expect(saisi(tester, 'appr_$barry'), texteAuto);
      expect(find.byKey(Key('appr_auto_$barry')), findsNothing);
      expect(find.text('1 modification non enregistrée'), findsOneWidget);
      expect(find.text('Utiliser pour 1 élève'), findsOneWidget);

      await tester.tap(find.byKey(const Key('enregistrer_appreciations')));
      await tester.pump();
      await jusqua(tester, () => find.byKey(const Key('appr_modifications')).evaluate().isEmpty);
      expect((await enBase(tester, 't1'))[barry]!.appreciation, texteAuto);
      expect(find.byKey(Key('appr_auto_$barry')), findsNothing);
      await fin(tester);
    });

    testWidgets('« Utiliser pour N élèves » remplit tous les champs vides', (tester) async {
      await demarrer(tester);
      await ouvrirOnglet(tester);

      await tester.tap(find.byKey(const Key('appr_tout_utiliser')));
      await tester.pump();
      expect(saisi(tester, 'appr_$barry'), texteAuto);
      expect(saisi(tester, 'appr_$diallo'), texteAuto);
      expect(saisi(tester, 'appr_$camara'), '');
      expect(find.text('2 modifications non enregistrées'), findsOneWidget);
      expect(find.byKey(const Key('appr_tout_utiliser')), findsNothing);
      await fin(tester);
    });

    testWidgets('un texte saisi remplace la proposition', (tester) async {
      await demarrer(tester);
      await ouvrirOnglet(tester);
      await tester.enterText(find.byKey(Key('appr_$barry')), 'Mon avis.');
      await tester.pump();
      expect(find.byKey(Key('appr_auto_$barry')), findsNothing);
      expect(find.byKey(Key('appr_auto_$diallo')), findsOneWidget);
      // Le texte saisi est effacé : la proposition revient.
      await tester.enterText(find.byKey(Key('appr_$barry')), '');
      await tester.pump();
      expect(find.byKey(Key('appr_auto_$barry')), findsOneWidget);
      await fin(tester);
    });

    testWidgets('désactiver : plus de proposition, réglage mémorisé', (tester) async {
      await demarrer(tester);
      await ouvrirOnglet(tester);

      await tester.tap(find.byKey(const Key('appr_auto_actif')));
      await tester.pump();
      await jusqua(tester, () => find.byKey(Key('appr_auto_$barry')).evaluate().isEmpty);
      expect(texte(tester, 'appr_auto_texte'), contains('désactivée'));
      expect(find.byKey(const Key('appr_tout_utiliser')), findsNothing);
      await reglage(tester, false);

      await tester.tap(find.byKey(const Key('appr_auto_actif')));
      await tester.pump();
      await jusqua(tester, () => find.byKey(Key('appr_auto_$barry')).evaluate().isNotEmpty);
      await reglage(tester, true);
      await fin(tester);
    });

    testWidgets('par matière : propositions grisées, recopiables', (tester) async {
      await demarrer(tester);
      await ouvrirOnglet(tester);

      await tester.tap(find.byKey(Key('par_matiere_$barry')));
      await tester.pumpAndSettle();
      // Maths 16/20 : proposition ; Français sans note : aucune.
      expect(find.text('Très bon travail'), findsOneWidget);
      expect(saisi(tester, 'appr_matiere_$mathsA'), '');

      await tester.tap(find.byKey(const Key('appr_matieres_utiliser')));
      await tester.pump();
      expect(saisi(tester, 'appr_matiere_$mathsA'), 'Très bon travail');
      expect(saisi(tester, 'appr_matiere_$francaisA'), '');
      expect(find.byKey(const Key('appr_matieres_utiliser')), findsNothing);

      await tester.tap(find.byKey(const Key('enregistrer_appr_matieres')));
      await tester.pumpAndSettle();
      await jusqua(tester, () => find.text('Par matière (1)').evaluate().isNotEmpty);
      final lues = (await tester.runAsync(
          () => etat.services.appreciations.matieres(classeA, 't1')))!;
      expect(lues[barry], {mathsA: 'Très bon travail'});
      await fin(tester);
    });

    testWidgets('par matière, désactivé : aucune proposition', (tester) async {
      await demarrer(tester);
      await tester.runAsync(() => etat.services.parametres.definirAppreciationsAutomatiques(false));
      await ouvrirOnglet(tester);
      expect(tester.widget<Switch>(find.byKey(const Key('appr_auto_actif'))).value, isFalse);
      await tester.tap(find.byKey(Key('par_matiere_$barry')));
      await tester.pumpAndSettle();
      expect(find.text('Très bon travail'), findsNothing);
      expect(find.byKey(const Key('appr_matieres_utiliser')), findsNothing);
      await fin(tester);
    });
  });
}
