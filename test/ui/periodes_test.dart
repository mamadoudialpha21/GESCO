import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/ui/notes/page_notes.dart';
import 'package:gesco/ui/parametres/onglet_periodes.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late EtatApp etat;

  Future<void> demarrer(
    WidgetTester tester,
    Widget Function(EtatApp) page, {
    bool avecClasse = false,
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
      final annee = await s.annees.creer('2026-2027', activer: true);
      if (avecClasse) {
        final classe = await s.classes.creer(anneeId: annee.id, nom: '10e A');
        await s.matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
        await s.eleves.inscrire(
          Eleve(matricule: '2026-0001', nom: 'DIALLO', prenom: 'Aminata', sexe: 'F'),
          anneeId: annee.id,
          classeId: classe.id,
        );
      }
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

  Future<void> attendre(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      if (f.evaluate().isNotEmpty) return;
    }
    fail('Élément introuvable : $f');
  }

  /// Attend que le calendrier enregistré vérifie [condition].
  Future<Calendrier> attendreCalendrier(
    WidgetTester tester,
    bool Function(Calendrier) condition,
  ) async {
    for (var i = 0; i < 60; i++) {
      final c = (await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return etat.services.calendriers.lire(etat.anneeId!);
      }))!;
      await tester.pump(const Duration(milliseconds: 100));
      if (condition(c)) return c;
    }
    fail('Le calendrier enregistré n\'a pas la valeur attendue.');
  }

  Future<void> fin(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => gdb.fermer());
  }

  Future<void> enregistrer(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('enregistrer_periodes')));
    await tester.tap(find.byKey(const Key('enregistrer_periodes')));
    await tester.pump();
  }

  String nom(WidgetTester tester, String cle) =>
      tester.widget<TextField>(find.byKey(Key(cle))).controller!.text;

  Widget onglet(EtatApp e) => OngletPeriodes(etat: e);

  testWidgets('trois trimestres par défaut, puis deux semestres', (tester) async {
    await demarrer(tester, onglet);
    await attendre(tester, find.byKey(const Key('periode_nom_0')));
    expect(nom(tester, 'periode_nom_0'), 'Trimestre 1');
    expect(nom(tester, 'periode_nom_2'), 'Trimestre 3');
    expect(find.byKey(const Key('periode_nom_3')), findsNothing);
    expect(find.byKey(const Key('periode_mois_libres')), findsNothing);

    await tester.tap(find.byKey(const Key('type_semestres')));
    await tester.pump();
    expect(nom(tester, 'periode_nom_0'), 'Semestre 1');
    expect(nom(tester, 'periode_nom_1'), 'Semestre 2');
    expect(find.byKey(const Key('periode_nom_2')), findsNothing);

    await enregistrer(tester);
    final c = await attendreCalendrier(tester, (c) => c.type == TypePeriodes.semestres);
    expect(c, Calendrier.semestres);
    await fin(tester);
  });

  testWidgets('déplacer un mois d\'une période à l\'autre', (tester) async {
    await demarrer(tester, onglet);
    await attendre(tester, find.byKey(const Key('periode_nom_0')));

    // Janvier passe du trimestre 2 au trimestre 1.
    await tester.ensureVisible(find.byKey(const Key('periode_0_mois_1')));
    await tester.tap(find.byKey(const Key('periode_0_mois_1')));
    await tester.pump();
    expect(tester.widget<FilterChip>(find.byKey(const Key('periode_0_mois_1'))).selected, isTrue);
    expect(tester.widget<FilterChip>(find.byKey(const Key('periode_1_mois_1'))).selected, isFalse);

    await enregistrer(tester);
    final c = await attendreCalendrier(tester, (c) => c.type == TypePeriodes.personnalise);
    expect(c.periodes[0].mois, [10, 11, 12, 1]);
    expect(c.periodes[1].mois, [2, 3]);
    expect(c.periodes[2].mois, [4, 5, 6]);
    await fin(tester);
  });

  testWidgets('un mois sans période est signalé et bloque l\'enregistrement',
      (tester) async {
    await demarrer(tester, onglet);
    await attendre(tester, find.byKey(const Key('periode_nom_0')));

    await tester.ensureVisible(find.byKey(const Key('periode_0_mois_10')));
    await tester.tap(find.byKey(const Key('periode_0_mois_10')));
    await tester.pump();
    expect(find.text('Mois sans période : Octobre.'), findsOneWidget);

    await enregistrer(tester);
    await tester.pump();
    expect(find.textContaining('Octobre n\'appartient à aucune période'), findsOneWidget);
    final c = (await tester.runAsync(() => etat.services.calendriers.lire(etat.anneeId!)))!;
    expect(c, Calendrier.defaut, reason: 'rien n\'est enregistré');
    await fin(tester);
  });

  testWidgets('ajouter une période vide est refusé, la retirer rétablit l\'état',
      (tester) async {
    await demarrer(tester, onglet);
    await attendre(tester, find.byKey(const Key('periode_nom_0')));

    await tester.ensureVisible(find.byKey(const Key('ajouter_periode')));
    await tester.tap(find.byKey(const Key('ajouter_periode')));
    await tester.pump();
    expect(nom(tester, 'periode_nom_3'), 'Période 4');

    await enregistrer(tester);
    await tester.pump();
    expect(find.textContaining('ne contient aucun mois'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('retirer_periode_3')));
    await tester.tap(find.byKey(const Key('retirer_periode_3')));
    await tester.pump();
    expect(find.byKey(const Key('periode_nom_3')), findsNothing);

    await enregistrer(tester);
    final c = await attendreCalendrier(tester, (c) => c.type == TypePeriodes.personnalise);
    expect(c.periodes, hasLength(3));
    await fin(tester);
  });

  testWidgets('séquences : activation, enregistrement puis désactivation',
      (tester) async {
    await demarrer(tester, onglet);
    await attendre(tester, find.byKey(const Key('option_sequences')));
    expect(find.byKey(const Key('sequence_nom_0')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('option_sequences')));
    await tester.tap(find.byKey(const Key('option_sequences')));
    await tester.pump();
    expect(nom(tester, 'sequence_nom_0'), 'Séquence 1');
    expect(nom(tester, 'sequence_nom_5'), 'Séquence 6');
    expect(find.byKey(const Key('sequence_nom_6')), findsNothing);

    await enregistrer(tester);
    final c = await attendreCalendrier(tester, (c) => c.sequencesActives);
    expect(c.sequences, Calendrier.sequencesProposees);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('option_sequences')));
    await tester.tap(find.byKey(const Key('option_sequences')));
    await tester.pump();
    await enregistrer(tester);
    final sans = await attendreCalendrier(tester, (c) => !c.sequencesActives);
    expect(sans.periodes, Calendrier.defaut.periodes);
    await fin(tester);
  });

  testWidgets('séquences sur des semestres : coupées par groupes de deux mois',
      (tester) async {
    await demarrer(tester, onglet);
    await attendre(tester, find.byKey(const Key('type_semestres')));
    await tester.tap(find.byKey(const Key('type_semestres')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('option_sequences')));
    await tester.tap(find.byKey(const Key('option_sequences')));
    await tester.pump();

    await enregistrer(tester);
    final c = await attendreCalendrier(tester, (c) => c.sequencesActives);
    // Semestre 1 : octobre-novembre, décembre-janvier ; semestre 2 : février-mars, avril-mai, juin.
    expect([for (final s in c.sequences) s.mois], [
      [10, 11],
      [12, 1],
      [2, 3],
      [4, 5],
      [6],
    ]);
    expect(c.erreurs(), isEmpty);
    await fin(tester);
  });

  testWidgets('moyennes mensuelles : l\'option est enregistrée', (tester) async {
    await demarrer(tester, onglet);
    await attendre(tester, find.byKey(const Key('option_moyenne_mensuelle')));
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('option_moyenne_mensuelle'))).value,
        isTrue);
    await tester.ensureVisible(find.byKey(const Key('option_moyenne_mensuelle')));
    await tester.tap(find.byKey(const Key('option_moyenne_mensuelle')));
    await tester.pump();
    await enregistrer(tester);
    final c = await attendreCalendrier(tester, (c) => !c.moyenneMensuelle);
    expect(c.moyenneMensuelle, isFalse);
    await fin(tester);
  });

  testWidgets('la page Notes suit le calendrier : deux semestres', (tester) async {
    await demarrer(
      tester,
      (e) => PageNotes(
        etat: e,
        allerAuxParametres: () {},
        allerAuxInscriptions: () {},
        maintenant: () => DateTime(2026, 11, 5),
      ),
      avecClasse: true,
    );
    await attendre(tester, find.byKey(const Key('periode_t3')));
    expect(find.text('Trimestre 3'), findsOneWidget);

    await tester.runAsync(() => etat.services.calendriers.enregistrer(
          etat.anneeId!,
          Calendrier.semestres,
        ));
    etat.donneesModifiees();
    await attendre(tester, find.text('Semestre 2'));
    expect(find.text('Trimestre 3'), findsNothing);
    expect(find.byKey(const Key('periode_t3')), findsNothing);
    expect(find.byKey(const Key('periode_t2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('periode_t1')));
    await tester.pump();
    expect(find.textContaining('Semestre 1 : lecture seule'), findsOneWidget);
    await fin(tester);
  });
}
