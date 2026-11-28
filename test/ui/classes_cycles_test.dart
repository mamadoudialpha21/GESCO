import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/niveaux.dart';
import 'package:gesco/ui/parametres/onglet_classes_matieres.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late EtatApp etat;
  late int annee;

  Future<void> demarrer(WidgetTester tester, {Future<void> Function(Services)? prealable}) async {
    tester.view.physicalSize = const Size(1500, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    gdb = (await tester.runAsync(() => GescoDatabase.ouvrir(
          fabrique: databaseFactoryFfi,
          chemin: inMemoryDatabasePath,
        )))!;
    final services = Services(gdb, session: Session.sansControle(), iterations: 2);
    await tester.runAsync(() async {
      annee = (await services.annees.creer('2026-2027', activer: true)).id;
      if (prealable != null) await prealable(services);
    });
    etat = EtatApp(services, chemin: 'en mémoire');
    await tester.runAsync(() => etat.charger());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: etat,
            builder: (context, _) => OngletClassesMatieres(etat: etat),
          ),
        ),
      ),
    );
  }

  Future<void> attendre(WidgetTester tester, Finder f, {int essais = 80}) async {
    for (var i = 0; i < essais; i++) {
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

  Future<void> choisir(WidgetTester tester, String cleListe, String libelle) async {
    await tester.tap(find.byKey(Key(cleListe)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(libelle).last);
    await tester.pumpAndSettle();
  }

  Finder champNom() => find.widgetWithText(TextField, 'Nom de la classe');

  String nomSaisi(WidgetTester tester) => tester.widget<TextField>(champNom()).controller!.text;

  Future<void> ouvrirAjout(WidgetTester tester) async {
    await attendre(tester, find.text('Ajouter'));
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(find.text('Ajouter une classe'), findsOneWidget);
  }

  Future<void> enregistrer(WidgetTester tester, String nomAttendu) async {
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();
    await attendre(
      tester,
      find.descendant(of: find.byType(ListTile), matching: find.text(nomAttendu)),
    );
  }

  Future<List<Classe>> classes(WidgetTester tester) async => [
        for (final r in (await tester.runAsync(() => etat.services.classes.lister(annee)))!)
          r.classe,
      ];

  testWidgets('classe de collège : niveau du catalogue, pas d\'option, nom proposé',
      (tester) async {
    await demarrer(tester);
    await ouvrirAjout(tester);

    // Sans niveau choisi : saisie libre proposée, pas d'option de lycée.
    expect(find.byKey(const Key('niveau_libre_classe')), findsOneWidget);
    expect(find.byKey(const Key('choix_serie_classe')), findsNothing);

    await choisir(tester, 'choix_niveau_classe', '7ème année · Collège');
    expect(find.byKey(const Key('niveau_libre_classe')), findsNothing);
    expect(find.byKey(const Key('choix_serie_classe')), findsNothing);
    expect(nomSaisi(tester), '7e');
    expect(find.textContaining('Cycle Collège : 2 semestres avec compositions par défaut.'), findsOneWidget);

    await tester.enterText(champNom(), '7e A');
    await enregistrer(tester, '7e A');

    final liste = await classes(tester);
    expect(liste.single.nom, '7e A');
    expect(liste.single.niveauCode, 7);
    expect(liste.single.serie, isNull);
    expect(liste.single.cycle, Cycle.college);
    expect(liste.single.niveau, '7ème année');
    expect(find.textContaining('Collège · 7ème année'), findsOneWidget);
    await fin(tester);
  });

  testWidgets('classe de primaire : trois compositions annoncées', (tester) async {
    await demarrer(tester);
    await ouvrirAjout(tester);
    await choisir(tester, 'choix_niveau_classe', '3ème année · Primaire');
    expect(find.textContaining('Cycle Primaire : 3 compositions par défaut.'), findsOneWidget);
    expect(find.byKey(const Key('choix_serie_classe')), findsNothing);
    expect(nomSaisi(tester), '3e');
    await enregistrer(tester, '3e');

    final c = (await classes(tester)).single;
    expect(c.cycle, Cycle.primaire);
    expect(c.niveauCode, 3);
    await fin(tester);
  });

  testWidgets('classe de maternelle : trois compositions annoncées, pas d\'option', (tester) async {
    await demarrer(tester);
    await ouvrirAjout(tester);
    await choisir(tester, 'choix_niveau_classe', 'Moyenne section · Maternelle');
    expect(find.textContaining('Cycle Maternelle : 3 compositions par défaut.'), findsOneWidget);
    expect(find.byKey(const Key('choix_serie_classe')), findsNothing);
    await tester.enterText(champNom(), 'MS A');
    await enregistrer(tester, 'MS A');

    final c = (await classes(tester)).single;
    expect(c.cycle, Cycle.maternelle);
    expect(c.niveauCode, 15);
    expect(c.niveau, 'Moyenne section');
    await fin(tester);
  });

  testWidgets('classe de lycée : option choisie, nom proposé avec l\'option', (tester) async {
    await demarrer(tester);
    await ouvrirAjout(tester);
    await choisir(tester, 'choix_niveau_classe', '12ème année · Lycée');
    expect(find.byKey(const Key('choix_serie_classe')), findsOneWidget);
    expect(nomSaisi(tester), '12e');

    await choisir(tester, 'choix_serie_classe', 'Sciences mathématiques');
    expect(nomSaisi(tester), '12e SM');
    await choisir(tester, 'choix_serie_classe', 'Sciences sociales');
    expect(nomSaisi(tester), '12e SS');
    await choisir(tester, 'choix_serie_classe', 'Sciences expérimentales');
    expect(nomSaisi(tester), '12e SE');
    await enregistrer(tester, '12e SE');

    final c = (await classes(tester)).single;
    expect(c.cycle, Cycle.lycee);
    expect(c.niveauCode, 12);
    expect(c.serie, SerieLycee.sciencesExperimentales);
    expect(find.textContaining('Lycée · 12ème année · Sciences expérimentales'), findsOneWidget);
    await fin(tester);
  });

  testWidgets('un nom saisi à la main n\'est pas écrasé par la proposition', (tester) async {
    await demarrer(tester);
    await ouvrirAjout(tester);
    await choisir(tester, 'choix_niveau_classe', 'Terminale · Lycée');
    expect(nomSaisi(tester), 'Tle');
    await tester.enterText(champNom(), 'Tle Excellence');

    await choisir(tester, 'choix_serie_classe', 'Sciences mathématiques');
    expect(nomSaisi(tester), 'Tle Excellence');
    await fin(tester);
  });

  testWidgets('changer de niveau retire l\'option du lycée', (tester) async {
    await demarrer(tester);
    await ouvrirAjout(tester);
    await choisir(tester, 'choix_niveau_classe', 'Terminale · Lycée');
    await choisir(tester, 'choix_serie_classe', 'Sciences sociales');
    expect(nomSaisi(tester), 'Tle SS');

    await choisir(tester, 'choix_niveau_classe', '9ème année · Collège');
    expect(find.byKey(const Key('choix_serie_classe')), findsNothing);
    expect(nomSaisi(tester), '9e');
    await enregistrer(tester, '9e');

    final c = (await classes(tester)).single;
    expect(c.niveauCode, 9);
    expect(c.serie, isNull);
    await fin(tester);
  });

  testWidgets('autre niveau : saisie libre, classe sans cycle', (tester) async {
    await demarrer(tester);
    await ouvrirAjout(tester);
    await tester.enterText(find.byKey(const Key('niveau_libre_classe')), 'Maternelle');
    await tester.enterText(champNom(), 'Maternelle A');
    await enregistrer(tester, 'Maternelle A');

    final c = (await classes(tester)).single;
    expect(c.niveauCode, isNull);
    expect(c.cycle, isNull);
    expect(c.niveau, 'Maternelle');
    await fin(tester);
  });

  testWidgets('une classe créée avant le catalogue : niveau reconnu à la modification',
      (tester) async {
    await demarrer(tester, prealable: (s) async {
      await s.classes.creer(anneeId: annee, nom: '10e A', niveau: '10e année');
    });
    await attendre(tester, find.text('10e A'));
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();

    expect(find.text('Modifier la classe'), findsOneWidget);
    // Le niveau « 10e année » est reconnu : 10ème année du collège.
    expect(find.text('10ème année · Collège'), findsOneWidget);
    expect(find.byKey(const Key('niveau_libre_classe')), findsNothing);

    await tester.tap(find.text('Enregistrer'));
    await tester.pump();
    await attendre(tester, find.textContaining('Collège · 10ème année'));
    final c = (await classes(tester)).single;
    expect(c.niveauCode, 10);
    expect(c.cycle, Cycle.college);
    await fin(tester);
  });
}
