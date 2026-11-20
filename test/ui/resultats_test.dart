import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
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
  late int classeB;
  late int barry;
  late int diallo;
  late int camara;
  late int sow;
  late int bah;
  var versParametres = 0;

  Future<void> demarrer(WidgetTester tester, {bool avecDonnees = true}) async {
    tester.view.physicalSize = const Size(1500, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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
      final annee = await s.annees.creer('2026-2027', activer: true);
      if (avecDonnees) {
        final a = await s.classes.creer(anneeId: annee.id, nom: '10e A', niveau: '10e année');
        final b = await s.classes.creer(anneeId: annee.id, nom: '10e B', niveau: '10e année');
        classeA = a.id;
        classeB = b.id;
        final mathsA = (await s.matieres.ajouter(classeId: a.id, nom: 'Maths', coefficient: 100)).id;
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

        Future<void> note(int inscription, int matiere, int centiemes) => s.notes.enregistrer(
              inscriptionId: inscription,
              matiereId: matiere,
              mois: 11,
              saisie: Saisie.valeur(centiemes),
            );
        await note(barry, mathsA, 1600);
        await note(diallo, mathsA, 1600);
        await note(sow, mathsA, 1800);
        await note(bah, mathsB, 1000);
        await s.eleves.enregistrerSortie(sow, StatutInscription.depart, motif: 'Déménagement');
      }
      await etat.charger();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: etat,
            builder: (context, _) => PageResultats(
              etat: etat,
              allerAuxParametres: () => versParametres++,
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

  Future<void> fin(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => gdb.fermer());
  }

  String texte(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  Future<void> choisir(WidgetTester tester, String cleListe, String libelle) async {
    await tester.tap(find.byKey(Key(cleListe)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(libelle).last);
    await tester.pumpAndSettle();
  }

  testWidgets('classement : rangs, ex æquo, élève parti et élève sans note', (tester) async {
    await demarrer(tester);
    await attendre(tester, find.byKey(Key('rang_$barry')));

    expect(texte(tester, 'rang_$barry'), '1er');
    expect(texte(tester, 'rang_$diallo'), '1er');
    expect(find.byKey(Key('exaequo_$barry')), findsOneWidget);
    expect(find.byKey(Key('exaequo_$diallo')), findsOneWidget);
    expect(texte(tester, 'moyenne_$barry'), '16,00');
    expect(texte(tester, 'mention_$barry'), 'Très bien');
    expect(texte(tester, 'decision_$barry'), 'Admis(e)');

    // Sans note : ni rang ni moyenne, signalé.
    expect(texte(tester, 'rang_$camara'), '—');
    expect(texte(tester, 'moyenne_$camara'), '—');
    expect(find.byKey(Key('sans_moyenne_$camara')), findsOneWidget);

    // Parti : sa moyenne reste visible mais il n'est pas classé.
    expect(texte(tester, 'rang_$sow'), '—');
    expect(texte(tester, 'moyenne_$sow'), '18,00');
    expect(find.byKey(Key('statut_$sow')), findsOneWidget);
    expect(find.text('Parti'), findsOneWidget);

    // Classés d'abord, puis les autres par ordre alphabétique.
    double haut(int id) => tester.getTopLeft(find.byKey(Key('nom_$id'))).dy;
    expect(haut(barry), lessThan(haut(diallo)));
    expect(haut(diallo), lessThan(haut(camara)));
    expect(haut(camara), lessThan(haut(sow)));

    // Synthèse : l'élève parti ne compte pas.
    expect(texte(tester, 'stat_effectif'), '3');
    expect(texte(tester, 'stat_evalues'), '2');
    expect(texte(tester, 'stat_moyenne'), '16,00');
    expect(texte(tester, 'stat_meilleure'), '16,00');
    expect(texte(tester, 'stat_faible'), '16,00');
    expect(texte(tester, 'stat_reussite'), '100,00 %');
    expect(texte(tester, 'stat_admis'), '2 / 0');
    await fin(tester);
  });

  testWidgets('changer de période : décembre n\'a aucune note', (tester) async {
    await demarrer(tester);
    await attendre(tester, find.byKey(Key('rang_$barry')));

    await choisir(tester, 'choix_portee', 'Décembre');
    expect(texte(tester, 'moyenne_$barry'), '—');
    expect(find.byKey(Key('sans_moyenne_$barry')), findsOneWidget);
    expect(texte(tester, 'stat_evalues'), '0');
    expect(texte(tester, 'stat_moyenne'), '—');
    expect(texte(tester, 'stat_reussite'), '—');

    await choisir(tester, 'choix_portee', 'Novembre');
    expect(texte(tester, 'moyenne_$barry'), '16,00');

    await choisir(tester, 'choix_portee', 'Année entière');
    expect(texte(tester, 'moyenne_$barry'), '16,00');
    expect(texte(tester, 'decision_$barry'), 'Admis(e) en classe supérieure');
    await fin(tester);
  });

  testWidgets('classement dans une matière : sans décision', (tester) async {
    await demarrer(tester);
    await attendre(tester, find.byKey(Key('rang_$barry')));
    expect(find.byKey(Key('decision_$barry')), findsOneWidget);

    await choisir(tester, 'choix_classement', 'Maths');
    expect(find.byKey(const Key('classement_matiere')), findsOneWidget);
    expect(find.byKey(Key('decision_$barry')), findsNothing);
    expect(find.byKey(const Key('stat_effectif')), findsNothing);
    expect(texte(tester, 'rang_$barry'), '1er');
    expect(texte(tester, 'rang_$diallo'), '1er');
    expect(texte(tester, 'moyenne_$sow'), '18,00');
    expect(texte(tester, 'rang_$sow'), '—');

    await choisir(tester, 'choix_classement', 'Moyenne générale');
    expect(find.byKey(const Key('classement_matiere')), findsNothing);
    expect(find.byKey(Key('decision_$barry')), findsOneWidget);
    await fin(tester);
  });

  testWidgets('changer de classe affiche ses élèves', (tester) async {
    await demarrer(tester);
    await attendre(tester, find.byKey(Key('rang_$barry')));
    expect(find.byKey(Key('rang_$bah')), findsNothing);

    await choisir(tester, 'choix_classe', '10e B');
    expect(texte(tester, 'rang_$bah'), '1er');
    expect(texte(tester, 'moyenne_$bah'), '10,00');
    expect(texte(tester, 'mention_$bah'), 'Passable');
    expect(find.byKey(Key('rang_$barry')), findsNothing);
    await fin(tester);
  });

  testWidgets('comparaison des classes', (tester) async {
    await demarrer(tester);
    await attendre(tester, find.byKey(Key('rang_$barry')));

    await tester.tap(find.byKey(const Key('vue_classes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('choix_classe')), findsNothing);
    expect(texte(tester, 'classe_rang_$classeA'), '1er');
    expect(texte(tester, 'classe_moyenne_$classeA'), '16,00');
    expect(texte(tester, 'classe_effectif_$classeA'), '3');
    expect(texte(tester, 'classe_evalues_$classeA'), '2');
    expect(texte(tester, 'classe_reussite_$classeA'), '100,00 %');
    expect(texte(tester, 'classe_rang_$classeB'), '2e');
    expect(texte(tester, 'classe_moyenne_$classeB'), '10,00');
    expect(texte(tester, 'classe_reussite_$classeB'), '100,00 %');

    // Retour à la liste des élèves.
    await tester.tap(find.byKey(const Key('vue_eleves')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('rang_$barry')), findsOneWidget);
    await fin(tester);
  });

  testWidgets('une note saisie ailleurs met le classement à jour', (tester) async {
    await demarrer(tester);
    await attendre(tester, find.byKey(Key('rang_$barry')));
    expect(texte(tester, 'rang_$camara'), '—');

    await tester.runAsync(() async {
      final maths = (await etat.services.matieres.lister(classeA)).first.id;
      await etat.services.notes.enregistrer(
        inscriptionId: camara,
        matiereId: maths,
        mois: 11,
        saisie: const Saisie.valeur(1800),
      );
    });
    etat.donneesModifiees();
    // CAMARA (18) passe devant BARRY et DIALLO (16) dès que la page a relu les notes.
    for (var i = 0; i < 60 && texte(tester, 'rang_$camara') == '—'; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(texte(tester, 'rang_$camara'), '1er');
    expect(texte(tester, 'rang_$barry'), '2e');
    expect(texte(tester, 'rang_$diallo'), '2e');
    await fin(tester);
  });

  testWidgets('sans classe : message et accès aux paramètres', (tester) async {
    await demarrer(tester, avecDonnees: false);
    await attendre(tester, find.text('Ouvrir les paramètres'));
    expect(find.textContaining('Aucune classe'), findsOneWidget);
    await tester.tap(find.text('Ouvrir les paramètres'));
    await tester.pump();
    expect(versParametres, 1);
    await fin(tester);
  });

  testWidgets('sans le droit de voir les résultats : page refusée', (tester) async {
    tester.view.physicalSize = const Size(1500, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    gdb = (await tester.runAsync(() => GescoDatabase.ouvrir(
          fabrique: databaseFactoryFfi,
          chemin: inMemoryDatabasePath,
        )))!;
    // Session avec contrôle, personne n'est connecté : rien n'est permis.
    etat = EtatApp(
      Services(gdb, session: Session(), iterations: 2),
      chemin: 'en mémoire',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageResultats(etat: etat, allerAuxParametres: () {}),
        ),
      ),
    );
    expect(find.text('Votre compte n\'a pas le droit de consulter les résultats.'),
        findsOneWidget);
    await fin(tester);
  });
}
