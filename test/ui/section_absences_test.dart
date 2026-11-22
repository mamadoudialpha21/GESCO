import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_absences.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_securite.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:gesco/ui/inscriptions/section_absences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Services admin;
  late EtatApp etat;
  late int inscription;

  Future<void> demarrer(WidgetTester tester, {Session? session}) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    gdb = (await tester.runAsync(() => GescoDatabase.ouvrir(
          fabrique: databaseFactoryFfi,
          chemin: inMemoryDatabasePath,
        )))!;
    admin = Services(gdb, session: Session.sansControle(), iterations: 2);
    await tester.runAsync(() async {
      final annee = (await admin.annees.creer('2026-2027', activer: true)).id;
      final classe = (await admin.classes.creer(anneeId: annee, nom: '10e A', niveauCode: 10)).id;
      inscription = await admin.eleves.inscrire(
        const Eleve(matricule: 'M1', nom: 'Barry', prenom: 'Alpha', sexe: 'M'),
        anneeId: annee,
        classeId: classe,
      );
    });
    final services = session == null ? admin : Services(gdb, session: session, iterations: 2);
    etat = EtatApp(services, chemin: 'en mémoire');
    await tester.runAsync(() => etat.charger());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SectionAbsences(
              etat: etat,
              inscriptionId: inscription,
              maintenant: () => DateTime(2026, 11, 20),
            ),
          ),
        ),
      ),
    );
    await attendre(tester, find.byKey(const Key('absences_resume')));
  }

  Future<void> fin(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => gdb.fermer());
  }

  String resume(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('absences_resume'))).data!;

  Future<void> ouvrirDialogue(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('absence_ajouter')));
    await tester.pumpAndSettle();
  }

  Future<void> valider(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('absence_valider')));
    await tester.pump();
  }

  group('saisie', () {
    testWidgets('liste vide : message et date du jour proposée', (tester) async {
      await demarrer(tester);
      expect(resume(tester), 'Aucune absence ni retard enregistré.');
      await ouvrirDialogue(tester);
      expect(tester.widget<TextField>(find.byKey(const Key('absence_date'))).controller!.text,
          '20/11/2026');
      expect(find.byKey(const Key('absence_duree')), findsNothing,
          reason: 'la durée ne concerne que les retards');
      await tester.tap(find.byKey(const Key('absence_annuler')));
      await tester.pumpAndSettle();
      await fin(tester);
    });

    testWidgets('une absence justifiée avec motif apparaît dans la liste et le résumé',
        (tester) async {
      await demarrer(tester);
      await ouvrirDialogue(tester);
      await tester.enterText(find.byKey(const Key('absence_date')), '03/11/2026');
      await tester.tap(find.byKey(const Key('absence_justifiee')));
      await tester.enterText(find.byKey(const Key('absence_motif')), 'Paludisme');
      await valider(tester);
      await attendre(tester, find.textContaining('1 absence (dont 1 justifiée)'));

      expect(find.text('03/11/2026 — Absence (justifiée)'), findsOneWidget);
      expect(find.text('Paludisme'), findsOneWidget);
      final stockees = (await tester.runAsync(() => admin.absences.lister(inscription)))!;
      expect(stockees.single.date, '2026-11-03');
      await fin(tester);
    });

    testWidgets('un retard avec durée', (tester) async {
      await demarrer(tester);
      await ouvrirDialogue(tester);
      await tester.tap(find.byKey(const Key('absence_type_retard')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('absence_duree')), '15');
      await valider(tester);
      await attendre(tester, find.textContaining('1 retard (15 min au total)'));
      expect(find.text('20/11/2026 — Retard de 15 min (non justifiée)'), findsOneWidget);
      await fin(tester);
    });

    testWidgets('date invalide : message dans la fenêtre, rien d\'enregistré', (tester) async {
      await demarrer(tester);
      await ouvrirDialogue(tester);
      await tester.enterText(find.byKey(const Key('absence_date')), '31/02/2026');
      await valider(tester);
      await tester.pump();
      expect(find.text('Date invalide (format jj/mm/aaaa).'), findsOneWidget);
      expect(find.byKey(const Key('absence_valider')), findsOneWidget);
      expect(resume(tester), 'Aucune absence ni retard enregistré.');
      await fin(tester);
    });

    testWidgets('durée invalide : message dans la fenêtre', (tester) async {
      await demarrer(tester);
      await ouvrirDialogue(tester);
      await tester.tap(find.byKey(const Key('absence_type_retard')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('absence_duree')), '9999');
      await valider(tester);
      await tester.pump();
      expect(find.text('Entre 1 et 600 minutes.'), findsOneWidget);
      await fin(tester);
    });

    testWidgets('doublon : le message du dépôt s\'affiche', (tester) async {
      await demarrer(tester);
      await tester.runAsync(() => admin.absences.ajouter(
          Absence(inscriptionId: inscription, date: '2026-11-20')));
      await ouvrirDialogue(tester); // date du jour : 20/11/2026
      await valider(tester);
      await attendre(tester, find.textContaining('absence est déjà enregistrée'));
      await fin(tester);
    });
  });

  group('correction et suppression', () {
    testWidgets('modifier le motif', (tester) async {
      await demarrer(tester);
      final id = (await tester.runAsync(() => admin.absences.ajouter(
          Absence(inscriptionId: inscription, date: '2026-11-03', motif: 'Ancien'))))!;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SectionAbsences(etat: etat, inscriptionId: inscription),
        ),
      ));
      await attendre(tester, find.byKey(Key('absence_$id')));

      await tester.tap(find.byKey(Key('absence_modifier_$id')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('absence_date'))).controller!.text,
          '03/11/2026');
      await tester.enterText(find.byKey(const Key('absence_motif')), 'Nouveau');
      await valider(tester);
      await attendre(tester, find.text('Nouveau'));
      expect(find.text('Ancien'), findsNothing);
      await fin(tester);
    });

    testWidgets('supprimer demande confirmation', (tester) async {
      await demarrer(tester);
      final id = (await tester.runAsync(() => admin.absences.ajouter(
          Absence(inscriptionId: inscription, date: '2026-11-03'))))!;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SectionAbsences(etat: etat, inscriptionId: inscription)),
      ));
      await attendre(tester, find.byKey(Key('absence_$id')));

      await tester.tap(find.byKey(Key('absence_supprimer_$id')));
      await tester.pumpAndSettle();
      expect(find.text('Supprimer cette ligne ?'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('absence_$id')), findsOneWidget, reason: 'annulé : rien ne change');

      await tester.tap(find.byKey(Key('absence_supprimer_$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pump();
      await attendre(tester, find.textContaining('Aucune absence ni retard'));
      expect(find.byKey(Key('absence_$id')), findsNothing);
      await fin(tester);
    });
  });

  testWidgets('sans le droit de gérer les élèves : lecture seule', (tester) async {
    final session = Session()
      ..ouvrir(const Utilisateur(
        id: 1,
        identifiant: 'lecteur',
        nomComplet: 'Lecteur',
        role: RoleUtilisateur.consultation,
        actif: true,
        creeLe: '2026-01-01',
        permissionsPersonnalisees: {Permission.tableauDeBord, Permission.elevesVoir},
      ));
    await demarrer(tester, session: session);
    final id = (await tester.runAsync(() => admin.absences.ajouter(
        Absence(inscriptionId: inscription, date: '2026-11-03'))))!;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SectionAbsences(etat: etat, inscriptionId: inscription)),
    ));
    await attendre(tester, find.byKey(Key('absence_$id')));
    expect(find.byKey(const Key('absence_ajouter')), findsNothing);
    expect(find.byKey(Key('absence_supprimer_$id')), findsNothing);
    expect(find.byKey(Key('absence_modifier_$id')), findsNothing);
    await fin(tester);
  });
}

Future<void> attendre(WidgetTester tester, Finder f, {int essais = 100}) async {
  for (var i = 0; i < essais; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
    if (f.evaluate().isNotEmpty) return;
  }
  fail('Élément introuvable : $f');
}
