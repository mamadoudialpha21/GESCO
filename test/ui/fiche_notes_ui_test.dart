import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_notation.dart';
import 'package:gesco/data/modeles_securite.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:gesco/ui/evaluations/vue_evaluations.dart';
import 'package:gesco/ui/notes/dialogue_fiche_notes.dart';
import 'package:gesco/ui/notes/page_notes.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/niveaux.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../documents/exemples.dart' as exemples;

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Services services;
  late EtatApp etat;
  late Directory dossier;
  late int annee;
  late int classe;
  late int classeVide;
  late int maths;
  late int evaluationId;
  final ouverts = <String>[];

  Future<bool> ouvreur(String chemin) async {
    ouverts.add(chemin);
    return true;
  }

  Future<void> demarrer(WidgetTester tester, {Session? session}) async {
    tester.view.physicalSize = const Size(1500, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    ouverts.clear();
    dossier = Directory.systemTemp.createTempSync('gesco_fiche_ui_');
    addTearDown(() {
      if (dossier.existsSync()) dossier.deleteSync(recursive: true);
    });

    gdb = (await tester.runAsync(() => GescoDatabase.ouvrir(
          fabrique: databaseFactoryFfi,
          chemin: inMemoryDatabasePath,
        )))!;
    final admin = Services(gdb, session: Session.sansControle(), iterations: 2);
    await tester.runAsync(() async {
      await admin.etablissements.enregistrer(const Etablissement(nom: 'Groupe Scolaire Test'));
      annee = (await admin.annees.creer('2026-2027', activer: true)).id;
      // Ces tests portent sur l'ancien modèle (trimestres) : on le fixe explicitement.
      await admin.calendriers.enregistrer(annee, Calendrier.deuxTrimestres, cycle: Cycle.college);
      classe = (await admin.classes.creer(anneeId: annee, nom: '10e A', niveauCode: 10)).id;
      classeVide = (await admin.classes.creer(anneeId: annee, nom: '9e B', niveauCode: 9)).id;
      final kante = await admin.enseignants.creer(const Enseignant(nom: 'Kante', prenom: 'Moussa'));
      maths = (await admin.matieres.ajouter(
        classeId: classe,
        nom: 'Maths',
        coefficient: 100,
        enseignantId: kante,
      ))
          .id;
      await admin.matieres.ajouter(classeId: classe, nom: 'Français', coefficient: 100);
      for (final (matricule, nom, prenom, sexe) in [
        ('2026-0001', 'BARRY', 'Mamadou', 'M'),
        ('2026-0002', 'DIALLO', 'Aminata', 'F'),
        ('2026-0003', 'CAMARA', 'Fatoumata', 'F'),
      ]) {
        await admin.eleves.inscrire(
          Eleve(matricule: matricule, nom: nom, prenom: prenom, sexe: sexe),
          anneeId: annee,
          classeId: classe,
        );
      }
      evaluationId = (await admin.evaluations.creer(
        classeId: classe,
        matiereId: maths,
        mois: 11,
        titre: 'Devoir 1',
        type: TypeEvaluation.devoir,
        date: '2026-11-17',
        bareme: 40,
      ))
          .id;
    });
    services = session == null ? admin : Services(gdb, session: session, iterations: 2);
    etat = EtatApp(services, chemin: 'en mémoire');
    await tester.runAsync(() => etat.charger());
  }

  Future<void> attendre(WidgetTester tester, Finder f, {int essais = 100}) async {
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

  /// Ouvre la fenêtre d'impression au-dessus d'une page vide.
  Future<void> ouvrirDialogue(
    WidgetTester tester, {
    int? classeId,
    Evaluation? evaluation,
  }) async {
    final classes = await tester.runAsync(() => services.classes.lister(annee));
    final resume = classes!.firstWhere((c) => c.classe.id == (classeId ?? classe));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => DialogueFicheNotes(
                    etat: etat,
                    classe: resume,
                    evaluation: evaluation,
                    periodeInitiale: 'Novembre',
                    ouvreur: ouvreur,
                    dossier: dossier,
                    chargerPolices: () async => exemples.polices(),
                    maintenant: () => DateTime(2026, 11, 22),
                  ),
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    await attendre(tester, find.byKey(const Key('fiche_generer')));
    await attendre(tester, find.byKey(const Key('fiche_intro')));
  }

  Future<void> choisir(WidgetTester tester, String cle, String libelle) async {
    await tester.tap(find.byKey(Key(cle)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(libelle).last);
    await tester.pumpAndSettle();
  }

  Future<void> generer(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('fiche_generer')));
    await tester.pump();
    await attendre(tester, find.byKey(const Key('fiche_resultat')));
  }

  String texte(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  List<File> pdfs() => [
        for (final f in dossier.listSync())
          if (f is File && f.path.endsWith('.pdf')) f,
      ];

  group('fenêtre d\'impression', () {
    testWidgets('propose les matières avec leur enseignant, toutes les matières et la liste',
        (tester) async {
      await demarrer(tester);
      await ouvrirDialogue(tester);

      expect(texte(tester, 'fiche_intro'), contains('3 élèves'));
      expect(texte(tester, 'fiche_intro'), contains('10e A'));
      await tester.tap(find.byKey(const Key('fiche_contenu')));
      await tester.pumpAndSettle();
      expect(find.text('Maths  ·  KANTE Moussa'), findsWidgets);
      expect(find.text('Français'), findsWidgets);
      expect(find.text('Toutes les matières (2 fiches)'), findsOneWidget);
      expect(find.text('Liste de classe seule (sans matière)'), findsOneWidget);
      await tester.tap(find.text('Français').last);
      await tester.pumpAndSettle();
      await fin(tester);
    });

    testWidgets('une matière : PDF enregistré, ouvert, nommé d\'après la classe et la matière',
        (tester) async {
      await demarrer(tester);
      await ouvrirDialogue(tester);
      expect(tester.widget<TextField>(find.byKey(const Key('fiche_periode'))).controller!.text,
          'Novembre');

      await generer(tester);

      final fichiers = pdfs();
      expect(fichiers, hasLength(1));
      expect(p.basename(fichiers.single.path), startsWith('Fiche_de_notes_10e_A_Maths_'));
      expect(String.fromCharCodes(fichiers.single.readAsBytesSync().take(5)), '%PDF-');
      expect(ouverts, [fichiers.single.path]);
      expect(texte(tester, 'fiche_resultat'), contains('PDF enregistré et ouvert (1 page)'));
      expect(tester.widget<SelectableText>(find.byKey(const Key('fiche_chemin'))).data,
          fichiers.single.path);
      await fin(tester);
    });

    testWidgets('toutes les matières : une page par fiche', (tester) async {
      await demarrer(tester);
      await ouvrirDialogue(tester);
      await choisir(tester, 'fiche_contenu', 'Toutes les matières (2 fiches)');

      await generer(tester);

      final fichiers = pdfs();
      expect(fichiers, hasLength(1));
      expect(p.basename(fichiers.single.path), startsWith('Fiches_de_notes_10e_A_'));
      expect(texte(tester, 'fiche_resultat'), contains('2 fiches de notes de la classe 10e A'));
      expect(texte(tester, 'fiche_resultat'), contains('(2 pages)'));
      await fin(tester);
    });

    testWidgets('liste de classe : plus de colonnes de notes à régler', (tester) async {
      await demarrer(tester);
      await ouvrirDialogue(tester);
      expect(find.byKey(const Key('fiche_nombre')), findsOneWidget);

      await choisir(tester, 'fiche_contenu', 'Liste de classe seule (sans matière)');
      expect(find.byKey(const Key('fiche_nombre')), findsNothing);
      expect(find.byKey(const Key('fiche_intitules')), findsNothing);
      expect(find.byKey(const Key('fiche_periode')), findsNothing);

      await generer(tester);
      final fichiers = pdfs();
      expect(fichiers, hasLength(1));
      expect(p.basename(fichiers.single.path), startsWith('Liste_de_classe_10e_A_'));
      expect(texte(tester, 'fiche_resultat'), contains('Liste de la classe 10e A'));
      await fin(tester);
    });

    testWidgets('titres de colonnes saisis et options décochées : PDF produit', (tester) async {
      await demarrer(tester);
      await ouvrirDialogue(tester);
      await tester.enterText(
          find.byKey(const Key('fiche_intitules')), 'Interro 1, Devoir, Composition');
      await tester.tap(find.byKey(const Key('fiche_matricule')));
      await tester.tap(find.byKey(const Key('fiche_sexe')));
      await tester.tap(find.byKey(const Key('fiche_observations')));
      await tester.pump();

      await generer(tester);
      expect(pdfs(), hasLength(1));
      await fin(tester);
    });

    testWidgets('fiche d\'une évaluation : barème et mois de l\'évaluation, réglages masqués',
        (tester) async {
      await demarrer(tester);
      final evaluation = (await tester.runAsync(() => services.evaluations.lister(classeId: classe)))!
          .firstWhere((r) => r.evaluation.id == evaluationId)
          .evaluation;
      await ouvrirDialogue(tester, evaluation: evaluation);

      expect(texte(tester, 'fiche_evaluation'), 'Évaluation : Devoir 1 (sur 40)');
      expect(find.byKey(const Key('fiche_contenu')), findsNothing);
      expect(find.byKey(const Key('fiche_nombre')), findsNothing);
      expect(find.byKey(const Key('fiche_intitules')), findsNothing);

      await generer(tester);
      final fichiers = pdfs();
      expect(fichiers, hasLength(1));
      expect(p.basename(fichiers.single.path), startsWith('Fiche_de_notes_10e_A_Maths_Devoir_1_'));
      expect(texte(tester, 'fiche_resultat'), contains('« Devoir 1 »'));
      await fin(tester);
    });

    testWidgets('classe sans élève : message clair et aucun fichier', (tester) async {
      await demarrer(tester);
      await ouvrirDialogue(tester, classeId: classeVide);
      // Une classe sans matière ne propose que la liste.
      expect(texte(tester, 'fiche_intro'), contains('0 élève'));

      await tester.tap(find.byKey(const Key('fiche_generer')));
      await tester.pump();
      await attendre(tester, find.textContaining('Aucun élève ne suit la classe 9e B'));

      expect(pdfs(), isEmpty);
      expect(ouverts, isEmpty);
      expect(find.byKey(const Key('fiche_resultat')), findsNothing);
      await fin(tester);
    });

    testWidgets('sans l\'autorisation de générer les documents : bouton désactivé',
        (tester) async {
      final session = Session()
        ..ouvrir(const Utilisateur(
          id: 1,
          identifiant: 'lecteur',
          nomComplet: 'Lecteur',
          role: RoleUtilisateur.consultation,
          actif: true,
          creeLe: '2026-01-01',
          permissionsPersonnalisees: {
            Permission.tableauDeBord,
            Permission.etablissementVoir,
            Permission.anneesVoir,
            Permission.classesVoir,
            Permission.enseignantsVoir,
            Permission.elevesVoir,
            Permission.notesVoir,
            Permission.resultatsVoir,
          },
        ));
      await demarrer(tester, session: session);
      await ouvrirDialogue(tester);

      expect(find.byKey(const Key('fiche_refus')), findsOneWidget);
      expect(
          tester.widget<ButtonStyleButton>(find.byKey(const Key('fiche_generer'))).onPressed,
          isNull);
      await fin(tester);
    });
  });

  group('boutons d\'accès', () {
    testWidgets('page Notes : « Fiche de notes » ouvre la fenêtre avec le mois affiché',
        (tester) async {
      await demarrer(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: etat,
              // La classe est imposée : la page Notes propose d'abord la
              // première classe de la liste, qui peut être la classe vide.
              builder: (context, _) => VueSaisie(
                etat: etat,
                classeId: classe,
                surClasse: (_) {},
                allerAuxParametres: () {},
                allerAuxInscriptions: () {},
                maintenant: () => DateTime(2026, 11, 5),
              ),
            ),
          ),
        ),
      );
      await attendre(tester, find.byKey(const Key('bouton_fiche_notes')));
      await tester.tap(find.byKey(const Key('bouton_fiche_notes')));
      await tester.pump();
      await attendre(tester, find.byKey(const Key('fiche_generer')));
      await attendre(tester, find.byKey(const Key('fiche_periode')));

      expect(tester.widget<TextField>(find.byKey(const Key('fiche_periode'))).controller!.text,
          'Novembre');
      await fin(tester);
    });

    testWidgets('onglet Évaluations : bouton de classe et bouton de chaque évaluation',
        (tester) async {
      await demarrer(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: etat,
              builder: (context, _) => VueEvaluations(
                etat: etat,
                classeId: classe,
                surClasse: (_) {},
                allerAuxParametres: () {},
                maintenant: () => DateTime(2026, 11, 5),
              ),
            ),
          ),
        ),
      );
      await attendre(tester, find.byKey(Key('fiche_$evaluationId')));
      expect(find.byKey(const Key('fiche_notes_classe')), findsOneWidget);

      await tester.tap(find.byKey(Key('fiche_$evaluationId')));
      await tester.pump();
      await attendre(tester, find.byKey(const Key('fiche_evaluation')));
      expect(texte(tester, 'fiche_evaluation'), contains('Devoir 1'));
      await fin(tester);
    });
  });
}
