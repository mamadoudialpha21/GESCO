import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/ui/tableau_de_bord.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late EtatApp etat;
  late int classeA;
  late int classeB;
  late int barry;
  late int diallo;
  late int camara;
  late int sow;
  late int bah;
  var versResultats = 0;
  var versNotes = 0;
  var versInscriptions = 0;
  var versParametres = 0;

  Future<void> demarrer(
    WidgetTester tester, {
    bool avecNotes = true,
    Size taille = const Size(1500, 3200),
  }) async {
    tester.view.physicalSize = taille;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    versResultats = 0;
    versNotes = 0;
    versInscriptions = 0;
    versParametres = 0;

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
      final a = await s.classes.creer(anneeId: annee.id, nom: '10e A', niveau: '10e année');
      final b = await s.classes.creer(anneeId: annee.id, nom: '10e B', niveau: '10e année');
      classeA = a.id;
      classeB = b.id;
      final maths = (await s.matieres.ajouter(classeId: a.id, nom: 'Maths', coefficient: 100)).id;
      final francais =
          (await s.matieres.ajouter(classeId: a.id, nom: 'Français', coefficient: 100)).id;
      final mathsB = (await s.matieres.ajouter(classeId: b.id, nom: 'Maths', coefficient: 100)).id;

      Future<int> inscrire(String matricule, String nom, String prenom, String sexe, int classe) =>
          s.eleves.inscrire(
            Eleve(matricule: matricule, nom: nom, prenom: prenom, sexe: sexe),
            anneeId: annee.id,
            classeId: classe,
          );
      barry = await inscrire('2026-0001', 'BARRY', 'Mamadou', 'M', a.id);
      diallo = await inscrire('2026-0002', 'DIALLO', 'Aminata', 'F', a.id);
      camara = await inscrire('2026-0003', 'CAMARA', 'Fatou', 'F', a.id);
      sow = await inscrire('2026-0004', 'SOW', 'Ibrahima', 'M', a.id);
      bah = await inscrire('2026-0005', 'BAH', 'Oumar', 'M', b.id);

      if (avecNotes) {
        Future<void> note(int inscription, int matiere, int mois, int centiemes) =>
            s.notes.enregistrer(
              inscriptionId: inscription,
              matiereId: matiere,
              mois: mois,
              saisie: Saisie.valeur(centiemes),
            );
        // Novembre (trimestre 1).
        await note(barry, maths, 11, 1600);
        await note(barry, francais, 11, 1600);
        await note(diallo, maths, 11, 1400);
        await note(diallo, francais, 11, 1800);
        await note(sow, maths, 11, 1900);
        await note(bah, mathsB, 11, 1000);
        // Janvier (trimestre 2).
        await note(barry, maths, 1, 1800);
        await note(barry, francais, 1, 1800);
        await note(diallo, maths, 1, 1000);
        await note(diallo, francais, 1, 1000);
        await note(bah, mathsB, 1, 1200);
        await s.eleves.enregistrerSortie(sow, StatutInscription.depart, motif: 'Déménagement');
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
              allerAuxParametres: () => versParametres++,
              allerAuxInscriptions: () => versInscriptions++,
              allerAuxNotes: () => versNotes++,
              allerAuxResultats: () => versResultats++,
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

  Future<void> fin(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => gdb.fermer());
  }

  String texte(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  testWidgets('totaux : classes, matières, élèves, filles et garçons, notes', (tester) async {
    await demarrer(tester);
    await attendre(tester, find.byKey(const Key('tuile_classes')));

    expect(texte(tester, 'tuile_classes'), '2');
    expect(texte(tester, 'tuile_matieres'), '3');
    expect(texte(tester, 'tuile_eleves'), '5');
    expect(texte(tester, 'tuile_eleves_detail'), '3 garçons  ·  2 filles');
    expect(texte(tester, 'tuile_notes'), '11');
    // L'année consultée figure dans le bandeau.
    expect(find.textContaining('2026-2027'), findsWidgets);
    await fin(tester);
  });

  testWidgets('effectif et matières de chaque classe', (tester) async {
    await demarrer(tester);
    await attendre(tester, find.text('Répartition par classe'));
    expect(find.text('4 élèves'), findsOneWidget);
    expect(find.text('3 matières'), findsNothing);
    expect(find.text('2 matières'), findsOneWidget);
    expect(find.text('1 élève'), findsOneWidget);
    expect(find.text('1 matière'), findsOneWidget);
    await fin(tester);
  });

  testWidgets('raccourcis : saisir les notes, inscrire un élève, paramètres', (tester) async {
    await demarrer(tester);
    await attendre(tester, find.byKey(const Key('action_notes')));
    for (final cle in ['action_notes', 'action_inscrire', 'action_parametres']) {
      await tester.ensureVisible(find.byKey(Key(cle)));
      await tester.tap(find.byKey(Key(cle)));
      await tester.pump();
    }
    expect(versNotes, 1);
    expect(versInscriptions, 1);
    expect(versParametres, 1);
    await fin(tester);
  });

  testWidgets('indicateurs de l\'année : moyenne générale et taux de réussite', (tester) async {
    await demarrer(tester);
    await attendre(tester, find.byKey(const Key('dash_moyenne_generale')));

    // BARRY 17, DIALLO 13, BAH 11 : le parti et l'élève sans note sont ignorés.
    expect(texte(tester, 'dash_moyenne_generale'), '13,67');
    expect(texte(tester, 'dash_taux_reussite'), '100,00 %');
    expect(find.text('3 admis sur 3 évalués'), findsOneWidget);
    await fin(tester);
  });

  testWidgets('moyennes par classe : périodes, année et taux de réussite', (tester) async {
    await demarrer(tester);
    await attendre(tester, find.byKey(Key('dash_annee_$classeA')));

    expect(texte(tester, 'dash_nom_$classeA'), '10e A');
    expect(texte(tester, 'dash_periode_${classeA}_t1'), '16,00');
    expect(texte(tester, 'dash_periode_${classeA}_t2'), '14,00');
    expect(texte(tester, 'dash_periode_${classeA}_t3'), '—');
    expect(texte(tester, 'dash_annee_$classeA'), '15,00');
    expect(texte(tester, 'dash_reussite_$classeA'), '100,00 %');

    expect(texte(tester, 'dash_periode_${classeB}_t1'), '10,00');
    expect(texte(tester, 'dash_periode_${classeB}_t2'), '12,00');
    expect(texte(tester, 'dash_periode_${classeB}_t3'), '—');
    expect(texte(tester, 'dash_annee_$classeB'), '11,00');
    await fin(tester);
  });

  testWidgets('les cinq meilleurs élèves, sans l\'élève parti', (tester) async {
    await demarrer(tester);
    await attendre(tester, find.byKey(Key('top_nom_$barry')));

    expect(texte(tester, 'top_rang_$barry'), '1er');
    expect(texte(tester, 'top_nom_$barry'), 'BARRY Mamadou');
    expect(texte(tester, 'top_moyenne_$barry'), '17,00');
    expect(texte(tester, 'top_rang_$diallo'), '2e');
    expect(texte(tester, 'top_moyenne_$diallo'), '13,00');
    expect(texte(tester, 'top_rang_$bah'), '3e');
    expect(texte(tester, 'top_moyenne_$bah'), '11,00');
    expect(find.byKey(Key('top_nom_$sow')), findsNothing);
    expect(find.byKey(Key('top_nom_$camara')), findsNothing);
    await fin(tester);
  });

  testWidgets('graphique de progression : une courbe et une légende par classe',
      (tester) async {
    await demarrer(tester);
    await attendre(tester, find.byKey(const Key('graphique_progression')));

    expect(find.byKey(Key('legende_$classeA')), findsOneWidget);
    expect(find.byKey(Key('legende_$classeB')), findsOneWidget);
    expect(find.text('10e A'), findsWidgets);
    await fin(tester);
  });

  testWidgets('le bouton mène à la page Résultats', (tester) async {
    await demarrer(tester);
    await attendre(tester, find.byKey(const Key('voir_resultats')));
    await tester.ensureVisible(find.byKey(const Key('voir_resultats')));
    await tester.tap(find.byKey(const Key('voir_resultats')));
    await tester.pump();
    expect(versResultats, 1);
    await fin(tester);
  });

  testWidgets('sans note : pas de section de résultats', (tester) async {
    await demarrer(tester, avecNotes: false);
    await attendre(tester, find.text('Répartition par classe'));
    expect(find.byKey(const Key('dash_moyenne_generale')), findsNothing);
    expect(find.byKey(const Key('graphique_progression')), findsNothing);
    await fin(tester);
  });

  testWidgets('fenêtre étroite : les résultats restent affichés sans débordement',
      (tester) async {
    await demarrer(tester, taille: const Size(820, 4200));
    await attendre(tester, find.byKey(const Key('dash_moyenne_generale')));
    expect(texte(tester, 'dash_moyenne_generale'), '13,67');
    expect(find.byKey(Key('top_nom_$barry')), findsOneWidget);
    expect(find.byKey(const Key('graphique_progression')), findsOneWidget);
    await fin(tester);
  });
}
