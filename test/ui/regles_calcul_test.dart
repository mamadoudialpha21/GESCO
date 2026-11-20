import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/ui/parametres/onglet_resultats.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late EtatApp etat;

  Future<void> demarrer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 2600);
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
      await etat.services.annees.creer('2026-2027', activer: true);
      await etat.charger();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: etat,
            builder: (context, _) => OngletResultats(etat: etat),
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

  Future<void> fin(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => gdb.fermer());
  }

  bool actif(WidgetTester tester, String cle) =>
      tester.widget<SwitchListTile>(find.byKey(Key(cle))).value;

  testWidgets('les règles de calcul sont désactivées par défaut puis enregistrées',
      (tester) async {
    await demarrer(tester);
    await attendre(tester, find.byKey(const Key('option_absence_zero')));
    expect(actif(tester, 'option_absence_zero'), isFalse);
    expect(actif(tester, 'option_periode_complete'), isFalse);
    expect(find.text('Une absence compte pour zéro'), findsOneWidget);
    expect(find.text('Exiger les trois mois pour calculer un trimestre'), findsOneWidget);

    await tester.tap(find.byKey(const Key('option_absence_zero')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('option_periode_complete')));
    await tester.pump();
    expect(actif(tester, 'option_absence_zero'), isTrue);
    expect(actif(tester, 'option_periode_complete'), isTrue);

    await tester.ensureVisible(find.byKey(const Key('enregistrer_resultats')));
    await tester.tap(find.byKey(const Key('enregistrer_resultats')));
    await tester.pump();
    await attendre(tester, find.text('Seuils enregistrés pour cette année scolaire.'));

    final config = await tester.runAsync(() => etat.services.configs.lire(etat.anneeId!));
    expect(config!.absenceEgaleZero, isTrue);
    expect(config.exigerPeriodeComplete, isTrue);
    await fin(tester);
  });

  testWidgets('les règles enregistrées sont relues à la réouverture', (tester) async {
    await demarrer(tester);
    await attendre(tester, find.byKey(const Key('option_absence_zero')));
    await tester.runAsync(() async {
      final config = (await etat.services.configs.lire(etat.anneeId!))
          .avecRegles(absenceEgaleZero: true);
      await etat.services.configs.enregistrer(etat.anneeId!, config);
    });
    // On rouvre l'onglet : les règles enregistrées sont relues de la base.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: OngletResultats(etat: etat))),
    );
    await attendre(tester, find.byKey(const Key('option_absence_zero')));
    expect(actif(tester, 'option_absence_zero'), isTrue);
    expect(actif(tester, 'option_periode_complete'), isFalse);

    // « Valeurs par défaut » remet les règles à leur état d'origine (sans enregistrer).
    await tester.ensureVisible(find.byKey(const Key('valeurs_par_defaut')));
    await tester.tap(find.byKey(const Key('valeurs_par_defaut')));
    await tester.pump();
    expect(actif(tester, 'option_absence_zero'), isFalse);
    final enBase = await tester.runAsync(() => etat.services.configs.lire(etat.anneeId!));
    expect(enBase!.absenceEgaleZero, isTrue, reason: 'rien n\'est enregistré sans clic');
    await fin(tester);
  });
}
