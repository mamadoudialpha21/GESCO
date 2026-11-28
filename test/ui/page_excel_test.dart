import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_securite.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:gesco/tableur/xlsx.dart';
import 'package:gesco/ui/excel/page_excel.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/niveaux.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Services services;
  late EtatApp etat;
  late Directory dossier;
  final ouverts = <String>[];
  var parametresOuverts = 0;

  Future<bool> ouvreur(String chemin) async {
    ouverts.add(chemin);
    return true;
  }

  Future<void> demarrer(
    WidgetTester tester, {
    Session? session,
    bool classes = true,
    bool eleves = true,
  }) async {
    tester.view.physicalSize = const Size(1500, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    ouverts.clear();
    parametresOuverts = 0;
    dossier = Directory.systemTemp.createTempSync('gesco_excel_ui_');
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
      final annee = (await admin.annees.creer('2026-2027', activer: true)).id;
      // Ces tests portent sur l'ancien modèle (trimestres) : on le fixe explicitement.
      await admin.calendriers.enregistrer(annee, Calendrier.deuxTrimestres, cycle: Cycle.college);
      if (!classes) return;
      final classe = (await admin.classes.creer(anneeId: annee, nom: '10e A', niveauCode: 10)).id;
      final kante = await admin.enseignants.creer(const Enseignant(nom: 'Kante', prenom: 'Moussa'));
      await admin.matieres.ajouter(
        classeId: classe,
        nom: 'Maths',
        coefficient: 100,
        enseignantId: kante,
      );
      await admin.matieres.ajouter(classeId: classe, nom: 'Français', coefficient: 100);
      if (!eleves) return;
      for (final (matricule, nom, prenom, sexe) in [
        ('2026-0001', 'BARRY', 'Mamadou', 'M'),
        ('2026-0002', 'DIALLO', 'Aminata', 'F'),
      ]) {
        await admin.eleves.inscrire(
          Eleve(matricule: matricule, nom: nom, prenom: prenom, sexe: sexe),
          anneeId: annee,
          classeId: classe,
        );
      }
    });
    services = session == null ? admin : Services(gdb, session: session, iterations: 2);
    etat = EtatApp(services, chemin: 'en mémoire');
    await tester.runAsync(() => etat.charger());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: etat,
            builder: (context, _) => PageExcel(
              etat: etat,
              allerAuxParametres: () => parametresOuverts++,
              ouvreur: ouvreur,
              dossier: dossier,
              maintenant: () => DateTime(2026, 11, 22, 10, 30, 15),
            ),
          ),
        ),
      ),
    );
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

  Future<void> choisir(WidgetTester tester, String cle, String libelle) async {
    await tester.tap(find.byKey(Key(cle)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(libelle).last);
    await tester.pumpAndSettle();
  }

  String texte(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  String texteSelectionnable(WidgetTester tester, String cle) =>
      tester.widget<SelectableText>(find.byKey(Key(cle))).data!;

  List<File> classeurs() => [
        for (final f in dossier.listSync())
          if (f is File && f.path.endsWith('.xlsx')) f,
      ];

  group('exporter', () {
    testWidgets('liste des élèves : fichier créé, relu, ouvert', (tester) async {
      await demarrer(tester);
      await attendre(tester, find.byKey(const Key('excel_creer')));
      expect(find.byKey(const Key('excel_classe')), findsNothing,
          reason: 'la liste complète n\'a pas de classe à choisir');

      await tester.tap(find.byKey(const Key('excel_creer')));
      await tester.pump();
      await attendre(tester, find.byKey(const Key('excel_resultat')));

      expect(texte(tester, 'excel_resultat_titre'),
          'Fichier créé : Liste complète des élèves (1 feuille).');
      final fichiers = classeurs();
      expect(fichiers, hasLength(1));
      expect(texteSelectionnable(tester, 'excel_fichier_0'), fichiers.single.path);
      expect(ouverts, [fichiers.single.path], reason: 'le fichier s\'ouvre dans Excel');
      expect(find.byKey(const Key('excel_non_ouvert')), findsNothing);

      final classeur = lireClasseur(fichiers.single.readAsBytesSync());
      final feuille = classeur.feuille('Élèves')!;
      expect(feuille.cellule(0, 0).texte, 'Groupe Scolaire Test');
      expect(feuille.cellule(5, 2).texte, 'BARRY');
      expect(feuille.cellule(6, 2).texte, 'DIALLO');

      // Boutons du résultat : le fichier, puis son dossier.
      await tester.tap(find.byKey(const Key('excel_ouvrir_dossier')));
      await tester.pump();
      expect(ouverts.last, dossier.path);
      await fin(tester);
    });

    testWidgets('fichier non ouvrable : le résultat l\'indique et donne l\'emplacement',
        (tester) async {
      await demarrer(tester);
      await attendre(tester, find.byKey(const Key('excel_creer')));
      final propre = tester.widget<PageExcel>(find.byType(PageExcel));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageExcel(
              etat: etat,
              allerAuxParametres: propre.allerAuxParametres,
              ouvreur: (_) async => false,
              dossier: dossier,
              maintenant: propre.maintenant,
            ),
          ),
        ),
      );
      await attendre(tester, find.byKey(const Key('excel_creer')));
      await tester.tap(find.byKey(const Key('excel_creer')));
      await tester.pump();
      await attendre(tester, find.byKey(const Key('excel_resultat')));
      expect(find.byKey(const Key('excel_non_ouvert')), findsOneWidget);
      expect(classeurs(), hasLength(1));
      await fin(tester);
    });

    testWidgets('les choix proposés suivent le type d\'export', (tester) async {
      await demarrer(tester);
      await attendre(tester, find.byKey(const Key('excel_type')));
      expect(find.byKey(const Key('excel_periode')), findsNothing);

      // Notes par matière : classe obligatoire, matière au choix.
      await choisir(tester, 'excel_type', 'Notes par matière');
      expect(find.byKey(const Key('excel_classe')), findsOneWidget);
      expect(find.byKey(const Key('excel_matiere')), findsOneWidget);
      expect(find.byKey(const Key('excel_periode')), findsNothing);
      await tester.tap(find.byKey(const Key('excel_classe')));
      await tester.pumpAndSettle();
      expect(find.text('Toutes les classes'), findsNothing,
          reason: 'une classe est obligatoire pour cet export');
      await tester.tap(find.text('10e A').last);
      await tester.pumpAndSettle();

      // Résultats trimestriels : seulement des trimestres, ni mois ni année.
      await choisir(tester, 'excel_type', 'Résultats trimestriels');
      expect(find.byKey(const Key('excel_periode')), findsOneWidget);
      await tester.tap(find.byKey(const Key('excel_periode')));
      await tester.pumpAndSettle();
      expect(find.text('Trimestre 1'), findsWidgets);
      expect(find.text('Trimestre 2'), findsWidgets);
      expect(find.text('Année entière'), findsNothing);
      expect(find.text('Novembre'), findsNothing);
      await tester.tap(find.text('Trimestre 2').last);
      await tester.pumpAndSettle();

      // Notes par classe : mois et année acceptés.
      await choisir(tester, 'excel_type', 'Notes par classe');
      await tester.tap(find.byKey(const Key('excel_periode')));
      await tester.pumpAndSettle();
      expect(find.text('Année entière'), findsWidgets);
      expect(find.text('Novembre'), findsWidgets);
      await tester.tap(find.text('Novembre').last);
      await tester.pumpAndSettle();

      // Classements : la matière n'apparaît qu'avec une classe.
      await choisir(tester, 'excel_type', 'Classements');
      await choisir(tester, 'excel_classe', 'Toutes les classes');
      expect(find.byKey(const Key('excel_matiere')), findsNothing);
      await choisir(tester, 'excel_classe', '10e A');
      expect(find.byKey(const Key('excel_matiere')), findsOneWidget);
      await tester.tap(find.byKey(const Key('excel_matiere')));
      await tester.pumpAndSettle();
      expect(find.text('Moyenne générale'), findsWidgets);
      await tester.tap(find.text('Maths').last);
      await tester.pumpAndSettle();
      await fin(tester);
    });

    testWidgets('résultats trimestriels sur le trimestre choisi', (tester) async {
      await demarrer(tester);
      await attendre(tester, find.byKey(const Key('excel_type')));
      await choisir(tester, 'excel_type', 'Résultats trimestriels');
      await choisir(tester, 'excel_periode', 'Trimestre 2');
      await tester.tap(find.byKey(const Key('excel_creer')));
      await tester.pump();
      await attendre(tester, find.byKey(const Key('excel_resultat')));

      final classeur = lireClasseur(classeurs().single.readAsBytesSync());
      expect(classeur.feuille('Résultats 10e A')!.cellule(1, 0).texte, 'Résultats : Trimestre 2');
      await fin(tester);
    });

    testWidgets('rien à exporter : message d\'erreur et aucun fichier', (tester) async {
      await demarrer(tester, eleves: false);
      await attendre(tester, find.byKey(const Key('excel_creer')));
      await tester.tap(find.byKey(const Key('excel_creer')));
      await tester.pump();
      await attendre(tester, find.text('Aucun élève n\'est inscrit pour cette année scolaire.'));
      expect(find.byKey(const Key('excel_resultat')), findsNothing);
      expect(classeurs(), isEmpty);
      expect(ouverts, isEmpty);
      await fin(tester);
    });
  });

  group('listes pour les enseignants', () {
    Future<void> versListes(WidgetTester tester) async {
      await attendre(tester, find.byKey(const Key('excel_vue_listes')));
      await tester.tap(find.byKey(const Key('excel_vue_listes')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vue_listes')), findsOneWidget);
    }

    testWidgets('un fichier par enseignant, plus un pour les matières sans enseignant',
        (tester) async {
      await demarrer(tester);
      await versListes(tester);
      expect(texte(tester, 'listes_intro'), contains('une feuille par matière'));

      await tester.tap(find.byKey(const Key('liste_creer')));
      await tester.pump();
      await attendre(tester, find.byKey(const Key('excel_resultat')));

      expect(texte(tester, 'excel_resultat_titre'), '2 listes créées pour Novembre.');
      expect(classeurs(), hasLength(2));
      expect(find.byKey(const Key('excel_fichier_0')), findsOneWidget);
      expect(find.byKey(const Key('excel_fichier_1')), findsOneWidget);
      expect(find.byKey(const Key('excel_ouvrir_fichier')), findsNothing,
          reason: 'plusieurs fichiers : on ouvre le dossier');
      expect(ouverts, isEmpty, reason: 'les listes sont envoyées, pas ouvertes');
      await tester.tap(find.byKey(const Key('excel_ouvrir_dossier')));
      await tester.pump();
      expect(ouverts.single, dossier.path);

      final noms = [for (final f in classeurs()) f.uri.pathSegments.last];
      expect(noms.any((n) => n.contains('KANTE_Moussa')), isTrue);
      expect(noms.any((n) => n.contains('sans_enseignant')), isTrue);
      await fin(tester);
    });

    testWidgets('mois, composition et enseignant choisis se retrouvent dans le fichier',
        (tester) async {
      await demarrer(tester);
      await versListes(tester);

      await choisir(tester, 'liste_mois', 'Décembre');
      await choisir(tester, 'liste_enseignant', 'KANTE Moussa');
      await choisir(tester, 'liste_interros', '1');
      await tester.tap(find.byKey(const Key('liste_composition')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('liste_creer')));
      await tester.pump();
      await attendre(tester, find.byKey(const Key('excel_resultat')));

      expect(texte(tester, 'excel_resultat_titre'), 'Liste créée pour Décembre.');
      expect(find.byKey(const Key('excel_ouvrir_fichier')), findsOneWidget);
      final fichier = classeurs().single;
      final maths = lireClasseur(fichier.readAsBytesSync()).feuille('Maths')!;
      expect(maths.cellule(6, 2).texte, 'Décembre');
      expect(maths.cellule(5, 2).texte, 'KANTE Moussa');
      expect(maths.cellule(9, 3).texte, startsWith('Interrogation'));
      expect(maths.cellule(9, 4).texte, startsWith('Composition'));
      expect(maths.cellule(10, 2).texte, 'BARRY Mamadou');
      await fin(tester);
    });
  });

  group('accès', () {
    testWidgets('sans le droit d\'importer ou d\'exporter : écran refusé', (tester) async {
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
      await tester.pump();
      expect(find.textContaining('n\'a pas le droit'), findsOneWidget);
      expect(find.byKey(const Key('excel_creer')), findsNothing);
      await fin(tester);
    });

    testWidgets('sans classe : on renvoie vers les paramètres', (tester) async {
      await demarrer(tester, classes: false);
      await attendre(tester, find.textContaining('Aucune classe'));
      expect(find.byKey(const Key('excel_creer')), findsNothing);
      await tester.tap(find.text('Ouvrir les paramètres'));
      expect(parametresOuverts, 1);
      await fin(tester);
    });
  });
}
