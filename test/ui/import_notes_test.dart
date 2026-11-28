import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_securite.dart';
import 'package:gesco/domain/modeles.dart' show Saisie;
import 'package:gesco/domain/permissions.dart';
import 'package:gesco/import_export/liste_vierge.dart';
import 'package:gesco/import_export/modele_export.dart';
import 'package:gesco/import_export/service_import_eleves.dart';
import 'package:gesco/tableur/classeur.dart';
import 'package:gesco/tableur/xlsx.dart';
import 'package:gesco/ui/excel/page_excel.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/niveaux.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const titresLibres = [
  'N°',
  'Matricule',
  'Nom et prénom',
  'Interrogation 1 (sur 20)',
  'Devoir 1 (sur 10)',
  'Moyenne',
  'Observations',
];

/// Tableau quelconque (pas une liste GESCO) : une ligne de titres puis [lignes].
FichierChoisi tableauLibre(
  List<List<Object?>> lignes, {
  List<String> titres = titresLibres,
  String nom = 'notes_libres.xlsx',
}) =>
    FichierChoisi(
      nom: nom,
      octets: ecrireClasseur([
        FeuilleEcrite('Notes', [
          [for (final t in titres) CelluleEcrite(t, StyleCellule.entete)],
          for (final l in lignes)
            [
              for (final v in l)
                (v == null || v == '') ? null : CelluleEcrite(v),
            ],
        ]),
      ]),
    );

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Services admin;
  late Services services;
  late EtatApp etat;
  late Directory dossier;
  late int annee;
  late int classe;
  late Classe classeObj;
  late MatiereClasse maths;
  late int barry, diallo, camara;
  FichierChoisi? fichier;
  final ouverts = <String>[];

  Future<bool> ouvreur(String chemin) async {
    ouverts.add(chemin);
    return true;
  }

  Future<void> demarrer(WidgetTester tester, {Session? session}) async {
    tester.view.physicalSize = const Size(1500, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    ouverts.clear();
    fichier = null;
    dossier = Directory.systemTemp.createTempSync('gesco_import_notes_ui_');
    addTearDown(() {
      if (dossier.existsSync()) dossier.deleteSync(recursive: true);
    });

    gdb = (await tester.runAsync(() => GescoDatabase.ouvrir(
          fabrique: databaseFactoryFfi,
          chemin: inMemoryDatabasePath,
        )))!;
    admin = Services(gdb, session: Session.sansControle(), iterations: 2);
    await tester.runAsync(() async {
      await admin.etablissements.enregistrer(const Etablissement(nom: 'Groupe Scolaire Test'));
      annee = (await admin.annees.creer('2026-2027', activer: true)).id;
      // Ces tests portent sur l'ancien modèle (trimestres) : on le fixe explicitement.
      await admin.calendriers.enregistrer(annee, Calendrier.deuxTrimestres, cycle: Cycle.college);
      classe = (await admin.classes.creer(anneeId: annee, nom: '10e A', niveauCode: 10)).id;
      classeObj = (await admin.classes.obtenir(classe))!;
      maths = await admin.matieres.ajouter(classeId: classe, nom: 'Maths', coefficient: 100);
      await admin.matieres.ajouter(classeId: classe, nom: 'Français', coefficient: 100);
      Future<int> inscrire(String matricule, String nom, String prenom) => admin.eleves.inscrire(
            Eleve(matricule: matricule, nom: nom, prenom: prenom, sexe: 'M'),
            anneeId: annee,
            classeId: classe,
          );
      barry = await inscrire('2026-0001', 'BARRY', 'Mamadou');
      diallo = await inscrire('2026-0002', 'DIALLO', 'Aminata');
      camara = await inscrire('2026-0003', 'CAMARA', 'Fatou');
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
              allerAuxParametres: () {},
              ouvreur: ouvreur,
              dossier: dossier,
              maintenant: () => DateTime(2026, 11, 22, 10, 30, 15),
              selecteur: () async => fichier,
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

  Future<void> ouvrirImport(WidgetTester tester) async {
    final onglet = find.byKey(const Key('excel_vue_import_notes'));
    await attendre(tester, onglet);
    await tester.tap(onglet);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vue_import_notes')), findsOneWidget);
  }

  Future<void> choisirDansListe(WidgetTester tester, String cle, String libelle) async {
    await tester.ensureVisible(find.byKey(Key(cle)));
    await tester.tap(find.byKey(Key(cle)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(libelle).last);
    await tester.pumpAndSettle();
  }

  Future<void> choisirSelection(WidgetTester tester, {String matiere = 'Maths'}) async {
    await choisirDansListe(tester, 'notes_import_classe', '10e A');
    await choisirDansListe(tester, 'notes_import_matiere', matiere);
  }

  Future<void> toucher(WidgetTester tester, String cle) async {
    await tester.ensureVisible(find.byKey(Key(cle)));
    await tester.tap(find.byKey(Key(cle)));
  }

  bool actif(WidgetTester tester, String cle) =>
      tester.widget<FilledButton>(find.byKey(Key(cle))).onPressed != null;

  String texte(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  /// Choisit le fichier et attend la carte d'association des colonnes.
  Future<void> choisirFichier(WidgetTester tester, FichierChoisi f) async {
    fichier = f;
    await toucher(tester, 'notes_import_choisir');
    await tester.pump();
    await attendre(tester, find.byKey(const Key('notes_import_association')));
    await tester.pumpAndSettle();
  }

  Future<void> verifier(WidgetTester tester) async {
    await toucher(tester, 'notes_import_verifier');
    await tester.pump();
    await attendre(tester, find.byKey(const Key('notes_import_rapport_carte')));
    await tester.pumpAndSettle();
  }

  Future<void> importer(WidgetTester tester) async {
    await toucher(tester, 'notes_import_lancer');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_import_confirmer_oui')));
    await tester.pump();
    await attendre(tester, find.byKey(const Key('notes_import_resultat')));
    await tester.pumpAndSettle();
  }

  /// Liste vierge de Maths (octobre) telle que GESCO la produit, remplie comme
  /// le ferait un enseignant : (matricule, colonne de notes, valeur).
  Future<FichierChoisi> listeGesco(
    WidgetTester tester,
    List<(String, int, Object?)> valeurs, {
    String nom = 'maths_octobre.xlsx',
  }) async =>
      (await tester.runAsync(() async {
        final evals = [
          for (final r in await admin.evaluations.lister(classeId: classe)) r.evaluation,
        ];
        final colonnes = planifierColonnes(
          matiere: maths,
          evaluations: evals,
          options: const OptionsListeVierge(mois: 10),
        );
        final eleves = [
          for (final e in await admin.eleves.lister(annee, classeId: classe))
            if (e.actif) e,
        ];
        final feuilles = construireListeVierge(
          ContexteExport(
            etablissement: 'Groupe Scolaire Test',
            annee: '2026-2027',
            date: DateTime(2026, 11, 22, 10, 30, 15),
          ),
          ListeVierge(
            classe: classeObj,
            matieres: [MatiereVierge(matiere: maths, colonnes: colonnes)],
            eleves: eleves,
          ),
          mois: 10,
        );
        for (final (matricule, c, v) in valeurs) {
          final i = eleves.indexWhere((e) => e.matricule == matricule);
          feuilles[0].lignes[premiereLigneEleves + i][premiereColonneNotes + c] =
              CelluleEcrite(v, StyleCellule.note);
        }
        return FichierChoisi(nom: nom, octets: ecrireClasseur(feuilles));
      }))!;

  Future<Map<String, Map<int, Saisie>>> notesParTitre(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final liste = await admin.evaluations.lister(classeId: classe, matiereId: maths.id);
        return {
          for (final r in liste) r.evaluation.titre: await admin.evaluations.lireNotes(r.evaluation.id),
        };
      }))!;

  List<File> classeurs() => [
        for (final f in dossier.listSync())
          if (f is File && f.path.endsWith('.xlsx')) f,
      ];

  group('import des notes', () {
    testWidgets('liste GESCO remplie : vérification, import, notes relues dans la base',
        (tester) async {
      await demarrer(tester);
      await ouvrirImport(tester);

      // Tant que la classe et la matière ne sont pas choisies, rien ne part.
      expect(actif(tester, 'notes_import_choisir'), isFalse);
      await choisirSelection(tester);
      expect(actif(tester, 'notes_import_choisir'), isTrue);

      await choisirFichier(tester, await listeGesco(tester, [
        ('2026-0001', 0, 14.5),
        ('2026-0001', 1, 'ABS'),
        ('2026-0002', 0, 8),
        ('2026-0002', 1, 12.25),
      ]));
      expect(texte(tester, 'notes_import_fichier'), contains('maths_octobre.xlsx'));
      expect(texte(tester, 'notes_import_gesco_reconnue_0'), contains('Liste GESCO reconnue'));
      expect(find.byKey(const Key('notes_import_cible_3')), findsOneWidget);
      expect(find.byKey(const Key('notes_import_cible_4')), findsOneWidget);

      await verifier(tester);
      expect(find.text('Toutes (3)'), findsOneWidget);
      expect(find.text('À importer (2)'), findsOneWidget);
      expect(find.text('Sans note (1)'), findsOneWidget);
      expect(find.text('En erreur (0)'), findsOneWidget);
      expect(find.textContaining('évaluation à créer'), findsNWidgets(2));
      // Vérifier n'écrit rien.
      expect(await notesParTitre(tester), isEmpty);

      await importer(tester);
      expect(
        texte(tester, 'notes_import_resultat_titre'),
        '4 notes importées et retrouvées dans la base.',
      );
      expect(find.text('2 évaluations créées'), findsOneWidget);
      // Le fichier est oublié : on ne peut pas réimporter d'un simple clic.
      expect(find.byKey(const Key('notes_import_association')), findsNothing);
      expect(find.byKey(const Key('notes_import_rapport_carte')), findsNothing);

      expect(await notesParTitre(tester), {
        'Interrogation 1': {barry: const Saisie.valeur(1450), diallo: const Saisie.valeur(800)},
        'Interrogation 2': {barry: const Saisie.absent(), diallo: const Saisie.valeur(1225)},
      });
      await fin(tester);
    });

    testWidgets('tableau libre : colonnes reconnues, titre et mois modifiés avant l\'import',
        (tester) async {
      await demarrer(tester);
      await ouvrirImport(tester);
      await choisirSelection(tester);
      await choisirFichier(tester, tableauLibre([
        [1, '2026-0001', 'BARRY Mamadou', 14.5, 'ABS', 12.0, 'Bien'],
        [2, '2026-0002', 'DIALLO Aminata', 12, 7, 9.5, ''],
        [3, '2026-0003', 'CAMARA Fatou', 9, '', 9.0, 'Passable'],
      ]));
      expect(find.byKey(const Key('notes_import_gesco_reconnue_0')), findsNothing);
      expect(
        tester.widget<TextFormField>(find.byKey(const Key('notes_import_titre_3'))).initialValue,
        'Interrogation 1',
      );
      expect(
        tester.widget<TextFormField>(find.byKey(const Key('notes_import_titre_4'))).initialValue,
        'Devoir 1',
      );
      // « N° », « Moyenne » et « Observations » ne sont pas des notes à importer.
      expect(find.byKey(const Key('notes_import_titre_5')), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('notes_import_titre_3')));
      await tester.enterText(find.byKey(const Key('notes_import_titre_3')), 'Interro de novembre');
      await choisirDansListe(tester, 'notes_import_mois_4', 'Décembre');

      await verifier(tester);
      expect(find.text('À importer (3)'), findsOneWidget);
      expect(find.textContaining('Interro de novembre'), findsWidgets);
      expect(await notesParTitre(tester), isEmpty);

      await importer(tester);
      expect(
        texte(tester, 'notes_import_resultat_titre'),
        '5 notes importées et retrouvées dans la base.',
      );

      final evaluations = (await tester.runAsync(
        () => admin.evaluations.lister(classeId: classe, matiereId: maths.id),
      ))!;
      final parTitre = {for (final r in evaluations) r.evaluation.titre: r.evaluation};
      expect(parTitre.keys.toSet(), {'Interro de novembre', 'Devoir 1'});
      expect(parTitre['Interro de novembre']!.mois, 11);
      expect(parTitre['Interro de novembre']!.bareme, 20);
      expect(parTitre['Devoir 1']!.mois, 12);
      expect(parTitre['Devoir 1']!.bareme, 10);
      final notes = await notesParTitre(tester);
      expect(notes['Interro de novembre'], {
        barry: const Saisie.valeur(1450),
        diallo: const Saisie.valeur(1200),
        camara: const Saisie.valeur(900),
      });
      expect(notes['Devoir 1']!.keys.toSet(), {barry, diallo});
      expect(notes['Devoir 1']![barry], const Saisie.absent());
      await fin(tester);
    });

    testWidgets('lignes en erreur : import bloqué tant qu\'on ne choisit pas de les ignorer',
        (tester) async {
      await demarrer(tester);
      await ouvrirImport(tester);
      await choisirSelection(tester);
      await choisirFichier(tester, await listeGesco(tester, [
        ('2026-0001', 0, 25), // au-dessus du barème
        ('2026-0002', 0, 12),
        ('2026-0003', 0, 'bien'),
      ]));
      await verifier(tester);
      expect(find.text('En erreur (2)'), findsOneWidget);
      expect(find.text('À importer (1)'), findsOneWidget);
      expect(actif(tester, 'notes_import_lancer'), isFalse);
      expect(texte(tester, 'notes_import_explication'), contains('Ignorer les lignes en erreur'));

      await toucher(tester, 'notes_import_filtre_erreurs');
      await tester.pumpAndSettle();
      expect(find.textContaining('CAMARA'), findsWidgets);
      expect(await notesParTitre(tester), isEmpty);

      await toucher(tester, 'notes_import_ignorer');
      await tester.pumpAndSettle();
      expect(actif(tester, 'notes_import_lancer'), isTrue);
      await importer(tester);
      expect(
        texte(tester, 'notes_import_resultat_titre'),
        '1 note importée et retrouvée dans la base.',
      );
      expect(find.textContaining('2 lignes en erreur ignorées'), findsOneWidget);
      expect(await notesParTitre(tester), {
        'Interrogation 1': {diallo: const Saisie.valeur(1200)},
      });
      await fin(tester);
    });

    testWidgets('pas de doublon ni d\'écrasement : réimport, note différente, remplacement',
        (tester) async {
      await demarrer(tester);
      await ouvrirImport(tester);
      await choisirSelection(tester);

      final premier = await listeGesco(tester, [('2026-0001', 0, 10), ('2026-0002', 0, 11)]);
      await choisirFichier(tester, premier);
      await verifier(tester);
      await importer(tester);
      expect((await notesParTitre(tester)).keys, ['Interrogation 1']);

      // Même fichier de nouveau : rien à écrire, aucune évaluation en double.
      await choisirFichier(tester, premier);
      await verifier(tester);
      expect(texte(tester, 'notes_import_explication'), contains('Aucune note à importer'));
      expect(actif(tester, 'notes_import_lancer'), isFalse);
      expect((await notesParTitre(tester)).keys, ['Interrogation 1']);
      await toucher(tester, 'notes_import_annuler');
      await tester.pumpAndSettle();

      // Autre version du fichier : 15 pour BARRY (déjà 10), 11 inchangé, 9 en plus.
      final autre = await listeGesco(tester, [
        ('2026-0001', 0, 15),
        ('2026-0002', 0, 11),
        ('2026-0003', 0, 9),
      ]);
      await choisirFichier(tester, autre);
      await verifier(tester);
      await toucher(tester, 'notes_import_lancer');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notes_import_confirmer_remplace')), findsNothing);
      await tester.tap(find.byKey(const Key('notes_import_confirmer_oui')));
      await tester.pump();
      await attendre(tester, find.byKey(const Key('notes_import_resultat')));
      await tester.pumpAndSettle();
      expect(
        texte(tester, 'notes_import_resultat_titre'),
        '1 note importée et retrouvée dans la base.',
      );
      expect((await notesParTitre(tester))['Interrogation 1'], {
        barry: const Saisie.valeur(1000),
        diallo: const Saisie.valeur(1100),
        camara: const Saisie.valeur(900),
      });

      // L'utilisateur demande de remplacer : confirmation explicite, historique gardé.
      await toucher(tester, 'notes_import_remplacer');
      await tester.pumpAndSettle();
      await choisirFichier(tester, autre);
      await verifier(tester);
      await toucher(tester, 'notes_import_lancer');
      await tester.pumpAndSettle();
      expect(
        texte(tester, 'notes_import_confirmer_remplace'),
        contains('1 note déjà enregistrée sera remplacée'),
      );
      await tester.tap(find.byKey(const Key('notes_import_confirmer_oui')));
      await tester.pump();
      await attendre(tester, find.byKey(const Key('notes_import_resultat')));
      await tester.pumpAndSettle();
      expect((await notesParTitre(tester))['Interrogation 1']![barry], const Saisie.valeur(1500));
      final historique = (await tester.runAsync(
        () => admin.notes.historique(classeId: classe, inscriptionId: barry),
      ))!;
      expect(historique.first.ancienTexte, '10,00 / 20');
      expect(historique.first.nouveauTexte, '15,00 / 20');
      await fin(tester);
    });

    testWidgets('rapport Excel enregistré, annulation sans rien écrire, changement de matière',
        (tester) async {
      await demarrer(tester);
      await ouvrirImport(tester);
      await choisirSelection(tester);
      await choisirFichier(tester, await listeGesco(tester, [('2026-0001', 0, 14)]));
      await verifier(tester);

      await toucher(tester, 'notes_import_rapport');
      await tester.pump();
      await attendre(tester, find.byKey(const Key('excel_resultat')));
      await tester.pumpAndSettle();
      expect(classeurs().length, 1);
      expect(ouverts, [classeurs().single.path]);
      final rapport = lireClasseur(classeurs().single.readAsBytesSync());
      expect(
        rapport.feuille('Rapport')!.cellule(1, 0).texte,
        'Rapport de vérification de l\'import des notes',
      );
      expect(rapport.feuille('Colonnes'), isNotNull);

      await toucher(tester, 'notes_import_annuler');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notes_import_rapport_carte')), findsNothing);
      expect(find.byKey(const Key('notes_import_association')), findsNothing);
      expect(await notesParTitre(tester), isEmpty);

      // Changer de matière oublie le fichier : ses colonnes ne conviennent plus.
      await choisirFichier(tester, await listeGesco(tester, [('2026-0001', 0, 14)]));
      expect(find.byKey(const Key('notes_import_association')), findsOneWidget);
      await choisirDansListe(tester, 'notes_import_matiere', 'Français');
      expect(find.byKey(const Key('notes_import_association')), findsNothing);
      await fin(tester);
    });

    testWidgets('sans le droit de saisir des notes : import désactivé', (tester) async {
      final session = Session()
        ..ouvrir(Utilisateur(
          id: 1,
          identifiant: 'secretaire',
          nomComplet: 'Secrétaire',
          role: RoleUtilisateur.consultation,
          actif: true,
          creeLe: '2026-01-01',
          permissionsPersonnalisees:
              Permission.values.where((p) => p != Permission.notesSaisir).toSet(),
        ));
      await demarrer(tester, session: session);
      await ouvrirImport(tester);
      expect(
        texte(tester, 'notes_import_refus'),
        contains('pas le droit de saisir des notes'),
      );
      await choisirSelection(tester);
      expect(actif(tester, 'notes_import_choisir'), isFalse);
      await fin(tester);
    });
  });
}
