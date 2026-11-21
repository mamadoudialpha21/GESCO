import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/niveaux.dart';
import 'package:gesco/ui/resultats/page_resultats.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late EtatApp etat;
  late int primaire;
  late int college;
  late int lycee;

  Future<void> demarrer(WidgetTester tester, {required DateTime date}) async {
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
      final annee = await s.annees.creer('2026-2027', activer: true);
      Future<int> classe(String nom, int niveau, SerieLycee? serie, String matricule) async {
        final c = await s.classes.creer(
          anneeId: annee.id,
          nom: nom,
          niveauCode: niveau,
          serie: serie,
        );
        final maths = (await s.matieres.ajouter(classeId: c.id, nom: 'Maths', coefficient: 100)).id;
        final eleve = await s.eleves.inscrire(
          Eleve(matricule: matricule, nom: 'ELEVE$matricule', prenom: 'Test', sexe: 'M'),
          anneeId: annee.id,
          classeId: c.id,
        );
        // Note de janvier : 2e trimestre au primaire, 1er trimestre au collège.
        await s.notes.enregistrer(
          inscriptionId: eleve,
          matiereId: maths,
          mois: 1,
          saisie: const Saisie.valeur(1400),
        );
        return c.id;
      }

      primaire = await classe('CE2 A', 3, null, '2026-0001');
      college = await classe('8e A', 8, null, '2026-0002');
      lycee = await classe('Tle SM', 13, SerieLycee.sciencesMathematiques, '2026-0003');
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
              maintenant: () => date,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> attendre(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 80; i++) {
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

  String periodeChoisie(WidgetTester tester) =>
      tester.widget<DropdownButton<String>>(find.byKey(const Key('choix_portee'))).value!;

  /// Périodes proposées (trimestres) quand on ouvre la liste « Période ».
  Future<List<String>> trimestresProposes(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('choix_portee')));
    await tester.pumpAndSettle();
    final trouves = [
      for (final t in ['Trimestre 1', 'Trimestre 2', 'Trimestre 3'])
        if (find.text(t).evaluate().isNotEmpty) t,
    ];
    // Referme la liste sans changer de période.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    return trouves;
  }

  testWidgets('la liste des périodes suit le cycle de la classe choisie', (tester) async {
    await demarrer(tester, date: DateTime(2026, 11, 5));
    await attendre(tester, find.byKey(const Key('choix_classe')));

    // Première classe : CE2 A (primaire) -> trois trimestres.
    expect(await trimestresProposes(tester), ['Trimestre 1', 'Trimestre 2', 'Trimestre 3']);

    await choisir(tester, 'choix_classe', '8e A');
    await attendre(tester, find.byKey(const Key('choix_portee')));
    expect(await trimestresProposes(tester), ['Trimestre 1', 'Trimestre 2']);

    await choisir(tester, 'choix_classe', 'Tle SM');
    await attendre(tester, find.byKey(const Key('choix_portee')));
    expect(await trimestresProposes(tester), ['Trimestre 1', 'Trimestre 2']);
    await fin(tester);
  });

  testWidgets('en janvier : 2e trimestre au primaire, 1er trimestre au collège',
      (tester) async {
    await demarrer(tester, date: DateTime(2026, 1, 15));
    await attendre(tester, find.byKey(const Key('choix_classe')));
    expect(periodeChoisie(tester), 't2'); // CE2 A

    await choisir(tester, 'choix_classe', '8e A');
    await attendre(tester, find.byKey(const Key('choix_portee')));
    expect(periodeChoisie(tester), 't1');
    await fin(tester);
  });

  testWidgets('la vue Classes ne compare que les classes d\'un même cycle', (tester) async {
    await demarrer(tester, date: DateTime(2026, 1, 15));
    await attendre(tester, find.byKey(const Key('vue_classes')));
    await tester.tap(find.byKey(const Key('vue_classes')));
    await tester.pump();
    await attendre(tester, find.byKey(const Key('choix_cycle_classes')));

    // Primaire d'abord : seule CE2 A est comparée, avec son calendrier (T2).
    await attendre(tester, find.byKey(Key('classe_nom_$primaire')));
    expect(find.byKey(Key('classe_nom_$college')), findsNothing);
    expect(find.byKey(Key('classe_nom_$lycee')), findsNothing);
    expect(periodeChoisie(tester), 't2');
    expect(tester.widget<Text>(find.byKey(Key('classe_moyenne_$primaire'))).data, '14,00');

    await choisir(tester, 'choix_cycle_classes', 'Collège');
    await attendre(tester, find.byKey(Key('classe_nom_$college')));
    expect(find.byKey(Key('classe_nom_$primaire')), findsNothing);
    expect(find.byKey(Key('classe_nom_$lycee')), findsNothing);
    expect(periodeChoisie(tester), 't1');

    await choisir(tester, 'choix_cycle_classes', 'Lycée');
    await attendre(tester, find.byKey(Key('classe_nom_$lycee')));
    expect(find.byKey(Key('classe_nom_$college')), findsNothing);
    expect(find.text('Terminale · Sciences mathématiques'), findsOneWidget);
    await fin(tester);
  });
}
