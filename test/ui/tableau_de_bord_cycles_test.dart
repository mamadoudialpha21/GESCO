import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/niveaux.dart';
import 'package:gesco/ui/tableau_de_bord.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late EtatApp etat;
  final ids = <String, int>{};

  /// Crée les classes demandées : (nom, niveau, option).
  Future<void> demarrer(
    WidgetTester tester,
    List<(String, int?, SerieLycee?)> classes,
  ) async {
    tester.view.physicalSize = const Size(1500, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    ids.clear();
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
      await s.etablissements.enregistrer(const Etablissement(nom: 'Groupe Scolaire Test'));
      final annee = await s.annees.creer('2026-2027', activer: true);
      var n = 0;
      for (final (nom, niveau, serie) in classes) {
        final c = await s.classes.creer(
          anneeId: annee.id,
          nom: nom,
          niveau: niveau == null ? 'Maternelle' : '',
          niveauCode: niveau,
          serie: serie,
        );
        ids[nom] = c.id;
        final maths = (await s.matieres.ajouter(classeId: c.id, nom: 'Maths', coefficient: 100)).id;
        final eleve = await s.eleves.inscrire(
          Eleve(matricule: '2026-000${++n}', nom: 'ELEVE$n', prenom: 'Test', sexe: 'F'),
          anneeId: annee.id,
          classeId: c.id,
        );
        // Janvier : 2e trimestre au primaire, 1er trimestre au collège et au lycée.
        await s.notes.enregistrer(
          inscriptionId: eleve,
          matiereId: maths,
          mois: 1,
          saisie: const Saisie.valeur(1400),
        );
      }
      await etat.charger();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: etat,
            builder: (context, _) => PageTableauDeBord(
              etat: etat,
              allerAuxParametres: () {},
              allerAuxInscriptions: () {},
              allerAuxNotes: () {},
              allerAuxResultats: () {},
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

  String texte(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  testWidgets('moyennes par classe : un tableau par cycle, avec ses propres périodes',
      (tester) async {
    await demarrer(tester, [
      ('CE2 A', 3, null),
      ('8e A', 8, null),
      ('Tle SM', 13, SerieLycee.sciencesMathematiques),
    ]);
    await attendre(tester, find.byKey(Key('dash_nom_${ids['CE2 A']}')));

    expect(texte(tester, 'dash_cycle_primaire'), 'Primaire');
    expect(texte(tester, 'dash_cycle_college'), 'Collège');
    expect(texte(tester, 'dash_cycle_lycee'), 'Lycée');
    expect(find.byKey(const Key('dash_cycle_autres')), findsNothing);

    // Primaire : trois trimestres ; janvier tombe dans le 2e.
    final ce2 = ids['CE2 A']!;
    expect(find.byKey(Key('dash_periode_${ce2}_t3')), findsOneWidget);
    expect(texte(tester, 'dash_periode_${ce2}_t1'), '—');
    expect(texte(tester, 'dash_periode_${ce2}_t2'), '14,00');

    // Collège et lycée : deux trimestres ; janvier tombe dans le 1er.
    for (final nom in ['8e A', 'Tle SM']) {
      final id = ids[nom]!;
      expect(find.byKey(Key('dash_periode_${id}_t3')), findsNothing, reason: nom);
      expect(texte(tester, 'dash_periode_${id}_t1'), '14,00', reason: nom);
      expect(texte(tester, 'dash_periode_${id}_t2'), '—', reason: nom);
    }
    await fin(tester);
  });

  testWidgets('un seul cycle : pas d\'intertitre', (tester) async {
    await demarrer(tester, [
      ('7e A', 7, null),
      ('7e B', 7, null),
    ]);
    await attendre(tester, find.byKey(Key('dash_nom_${ids['7e A']}')));
    expect(find.byKey(Key('dash_nom_${ids['7e B']}')), findsOneWidget);
    expect(find.byKey(const Key('dash_cycle_college')), findsNothing);
    expect(find.byKey(const Key('dash_cycle_primaire')), findsNothing);
    await fin(tester);
  });

  testWidgets('une classe hors catalogue est rangée sous « Autres classes »', (tester) async {
    await demarrer(tester, [
      ('8e A', 8, null),
      ('Maternelle A', null, null),
    ]);
    await attendre(tester, find.byKey(Key('dash_nom_${ids['8e A']}')));
    expect(texte(tester, 'dash_cycle_college'), 'Collège');
    expect(texte(tester, 'dash_cycle_autres'), 'Autres classes');
    expect(find.byKey(Key('dash_nom_${ids['Maternelle A']}')), findsOneWidget);
    await fin(tester);
  });
}
