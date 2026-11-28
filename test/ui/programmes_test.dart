import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/depots/programme_depot.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/domain/niveaux.dart';
import 'package:gesco/ui/parametres/onglet_programmes.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late EtatApp etat;
  late int annee;

  /// Démarre l'onglet avec une année et, selon [classes], des classes
  /// (nom -> niveau, option) déjà créées.
  Future<void> demarrer(
    WidgetTester tester, {
    Map<String, (int, SerieLycee?)> classes = const {},
  }) async {
    tester.view.physicalSize = const Size(1500, 2800);
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
      annee = (await s.annees.creer('2026-2027', activer: true)).id;
      for (final e in classes.entries) {
        await s.classes.creer(
          anneeId: annee,
          nom: e.key,
          niveauCode: e.value.$1,
          serie: e.value.$2,
        );
      }
      await etat.charger();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: etat,
            builder: (context, _) => OngletProgrammes(etat: etat),
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

  Future<List<MatiereProgramme>> programme(WidgetTester tester, Cycle cycle,
          {SerieLycee? serie}) async =>
      (await tester.runAsync(
          () => etat.services.programmes.lister(annee, cycle, serie: serie)))!;

  /// Matières d'une classe (nom -> coefficient en centièmes), dans l'ordre.
  Future<List<(String, int)>> matieres(WidgetTester tester, String classe) async =>
      (await tester.runAsync(() async {
        final c = (await etat.services.classes.lister(annee))
            .firstWhere((r) => r.classe.nom == classe)
            .classe;
        return [
          for (final m in await etat.services.matieres.lister(c.id)) (m.nom, m.coefficient),
        ];
      }))!;

  Future<void> ouvrirDialogue(WidgetTester tester, String cleBouton, String cleChamp) async {
    await tester.tap(find.byKey(Key(cleBouton)));
    await tester.pump();
    await attendre(tester, find.byKey(Key(cleChamp)));
  }

  Future<void> ajouterMatiere(WidgetTester tester, String nom, String coefficient) async {
    await ouvrirDialogue(tester, 'ajouter_matiere_programme', 'programme_nom');
    await tester.enterText(find.byKey(const Key('programme_nom')), nom);
    await tester.enterText(find.byKey(const Key('programme_coefficient')), coefficient);
    await tester.tap(find.byKey(const Key('programme_enregistrer')));
    await tester.pump();
    await attendre(tester, find.text(nom));
  }

  testWidgets('primaire : programme vide au départ, une matière ajoutée arrive dans les classes',
      (tester) async {
    await demarrer(tester, classes: {'CE1 A': (3, null), 'CE2 A': (4, null), '7e A': (7, null)});
    await attendre(tester, find.byKey(const Key('programme_vide')));
    expect(find.byKey(const Key('methode_programme')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('methode_programme'))).data,
      contains('3 compositions'),
    );
    expect(find.text('CE1 A'), findsOneWidget);
    expect(find.text('CE2 A'), findsOneWidget);
    expect(find.text('7e A'), findsNothing, reason: 'collège : un autre cycle');

    await ajouterMatiere(tester, 'Mathématiques', '3');
    expect(find.byKey(const Key('programme_vide')), findsNothing);
    expect(find.text('Coefficient 3 · sur 20'), findsOneWidget);
    expect((await programme(tester, Cycle.primaire)).single.coefficient, 300);
    expect(await matieres(tester, 'CE1 A'), [('Mathématiques', 300)]);
    expect(await matieres(tester, 'CE2 A'), [('Mathématiques', 300)]);
    expect(await matieres(tester, '7e A'), isEmpty);
    await fin(tester);
  });

  testWidgets('lycée : un programme par option', (tester) async {
    await demarrer(tester, classes: {
      'Tle SM': (13, SerieLycee.sciencesMathematiques),
      'Tle SE': (13, SerieLycee.sciencesExperimentales),
    });
    await attendre(tester, find.byKey(const Key('cycle_prog_lycee')));
    await tester.tap(find.byKey(const Key('cycle_prog_lycee')));
    await tester.pump();
    await attendre(tester, find.byKey(const Key('serie_prog_SM')));
    await attendre(tester, find.byKey(const Key('programme_vide')));
    // SM est l'option affichée au départ.
    expect(find.text('Tle SM'), findsOneWidget);
    expect(find.text('Tle SE'), findsNothing);

    await ajouterMatiere(tester, 'Physique', '5');
    expect(await matieres(tester, 'Tle SM'), [('Physique', 500)]);
    expect(await matieres(tester, 'Tle SE'), isEmpty);

    await tester.tap(find.byKey(const Key('serie_prog_SE')));
    await tester.pump();
    await attendre(tester, find.byKey(const Key('programme_vide')));
    expect(find.text('Physique'), findsNothing);
    expect(find.text('Tle SE'), findsOneWidget);
    expect(find.text('Tle SM'), findsNothing);

    await ajouterMatiere(tester, 'SVT', '4');
    expect(await matieres(tester, 'Tle SE'), [('SVT', 400)]);
    expect(await matieres(tester, 'Tle SM'), [('Physique', 500)]);
    expect((await programme(tester, Cycle.lycee, serie: SerieLycee.sciencesExperimentales))
        .map((m) => m.nom), ['SVT']);
    await fin(tester);
  });

  testWidgets('une classe ajoutée depuis l\'écran reçoit les matières du programme',
      (tester) async {
    await demarrer(tester);
    await attendre(tester, find.byKey(const Key('classes_programme_vide')));
    await ajouterMatiere(tester, 'Lecture', '2');

    await ouvrirDialogue(tester, 'ajouter_classe_programme', 'programme_nom_classe');
    // Le nom du niveau est proposé, puis remplacé par celui de l'utilisateur.
    await tester.enterText(find.byKey(const Key('programme_nom_classe')), 'CP A');
    await tester.tap(find.byKey(const Key('programme_creer_classe')));
    await tester.pump();
    await attendre(tester, find.text('CP A'));
    expect(find.byKey(const Key('classes_programme_vide')), findsNothing);
    expect(await matieres(tester, 'CP A'), [('Lecture', 200)]);
    await fin(tester);
  });

  testWidgets('le nom de la classe est obligatoire', (tester) async {
    await demarrer(tester);
    await attendre(tester, find.byKey(const Key('classes_programme_vide')));
    await ouvrirDialogue(tester, 'ajouter_classe_programme', 'programme_nom_classe');
    await tester.enterText(find.byKey(const Key('programme_nom_classe')), '   ');
    await tester.tap(find.byKey(const Key('programme_creer_classe')));
    await tester.pump();
    expect(find.text('Le nom de la classe est obligatoire.'), findsOneWidget);
    expect(find.byKey(const Key('programme_nom_classe')), findsOneWidget);
    await fin(tester);
  });

  testWidgets('modifier le coefficient, puis retirer la matière du programme', (tester) async {
    await demarrer(tester, classes: {'CE1 A': (3, null)});
    await attendre(tester, find.byKey(const Key('programme_vide')));
    await ajouterMatiere(tester, 'Lecture', '2');
    final id = (await programme(tester, Cycle.primaire)).single.id;

    await ouvrirDialogue(tester, 'modifier_programme_$id', 'programme_coefficient');
    await tester.enterText(find.byKey(const Key('programme_coefficient')), '4,5');
    await tester.tap(find.byKey(const Key('programme_enregistrer')));
    await tester.pump();
    await attendre(tester, find.text('Coefficient 4,5 · sur 20'));
    expect(await matieres(tester, 'CE1 A'), [('Lecture', 450)]);

    await tester.tap(find.byKey(Key('supprimer_programme_$id')));
    await tester.pump();
    await attendre(tester, find.widgetWithText(FilledButton, 'Retirer'));
    await tester.tap(find.widgetWithText(FilledButton, 'Retirer'));
    await tester.pump();
    await attendre(tester, find.byKey(const Key('programme_vide')));
    expect(await programme(tester, Cycle.primaire), isEmpty);
    expect(await matieres(tester, 'CE1 A'), isEmpty);
    await fin(tester);
  });

  testWidgets('une saisie invalide est refusée dans la fenêtre', (tester) async {
    await demarrer(tester);
    await attendre(tester, find.byKey(const Key('programme_vide')));
    await ouvrirDialogue(tester, 'ajouter_matiere_programme', 'programme_nom');
    await tester.enterText(find.byKey(const Key('programme_coefficient')), 'abc');
    await tester.enterText(find.byKey(const Key('programme_bareme')), '0');
    await tester.tap(find.byKey(const Key('programme_enregistrer')));
    await tester.pump();
    expect(find.text('Le nom de la matière est obligatoire.'), findsOneWidget);
    expect(find.textContaining('Coefficient invalide'), findsOneWidget);
    expect(find.textContaining('Barème invalide'), findsOneWidget);
    expect(await programme(tester, Cycle.primaire), isEmpty);
    await fin(tester);
  });

  testWidgets('monter et descendre une matière change l\'ordre du programme', (tester) async {
    await demarrer(tester, classes: {'CE1 A': (3, null)});
    await attendre(tester, find.byKey(const Key('programme_vide')));
    await ajouterMatiere(tester, 'Lecture', '2');
    await ajouterMatiere(tester, 'Calcul', '3');
    var liste = await programme(tester, Cycle.primaire);
    expect([for (final m in liste) m.nom], ['Lecture', 'Calcul']);

    await tester.tap(find.byKey(Key('descendre_programme_${liste.first.id}')));
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      liste = await programme(tester, Cycle.primaire);
      if (liste.first.nom == 'Calcul') break;
    }
    expect([for (final m in liste) m.nom], ['Calcul', 'Lecture']);
    // L'écran suit : « Calcul » est maintenant au-dessus de « Lecture ».
    await attendre(tester, find.byKey(Key('matiere_programme_${liste.first.id}')));
    final haut = tester.getTopLeft(find.text('Calcul')).dy;
    final bas = tester.getTopLeft(find.text('Lecture')).dy;
    expect(haut, lessThan(bas));
    await fin(tester);
  });

  testWidgets('appliquer le programme remet une matière retirée à la main', (tester) async {
    await demarrer(tester, classes: {'CE1 A': (3, null)});
    await attendre(tester, find.byKey(const Key('programme_vide')));
    await ajouterMatiere(tester, 'Lecture', '2');
    await ajouterMatiere(tester, 'Calcul', '3');
    await tester.runAsync(() async {
      final c = (await etat.services.classes.lister(annee)).single.classe;
      final calcul = (await etat.services.matieres.lister(c.id)).firstWhere((m) => m.nom == 'Calcul');
      await etat.services.matieres.supprimer(calcul.id);
    });
    expect(await matieres(tester, 'CE1 A'), [('Lecture', 200)]);

    await tester.tap(find.byKey(const Key('appliquer_programme')));
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      if ((await matieres(tester, 'CE1 A')).length == 2) break;
    }
    expect(await matieres(tester, 'CE1 A'), [('Lecture', 200), ('Calcul', 300)]);
    await fin(tester);
  });

  testWidgets('la maternelle a son propre programme et sa méthode de calcul', (tester) async {
    await demarrer(tester, classes: {'PS A': (14, null), 'CE1 A': (3, null)});
    await attendre(tester, find.byKey(const Key('cycle_prog_maternelle')));
    await tester.tap(find.byKey(const Key('cycle_prog_maternelle')));
    await tester.pump();
    await attendre(tester, find.text('PS A'));
    expect(find.text('CE1 A'), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('methode_programme'))).data,
      contains('3 compositions'),
    );
    await ajouterMatiere(tester, 'Éveil', '1');
    expect(await matieres(tester, 'PS A'), [('Éveil', 100)]);
    expect(await matieres(tester, 'CE1 A'), isEmpty);

    await tester.tap(find.byKey(const Key('cycle_prog_college')));
    await tester.pump();
    await attendre(tester, find.byKey(const Key('programme_vide')));
    expect(
      tester.widget<Text>(find.byKey(const Key('methode_programme'))).data,
      contains('2 semestres avec compositions'),
    );
    await fin(tester);
  });
}
