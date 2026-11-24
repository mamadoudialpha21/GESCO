import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_securite.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:gesco/import_export/service_import_eleves.dart';
import 'package:gesco/tableur/classeur.dart';
import 'package:gesco/tableur/xlsx.dart';
import 'package:gesco/ui/excel/page_excel.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const titresStandard = ['Matricule', 'Nom', 'Prénom', 'Sexe', 'Date de naissance', 'Classe'];

/// Classeur d'une feuille : une ligne de titres puis les [lignes] (la première
/// ligne de données est donc la ligne 2 d'Excel).
FichierChoisi classeurEleves(
  List<List<Object?>> lignes, {
  List<String> titres = titresStandard,
  String nom = 'eleves.xlsx',
}) =>
    FichierChoisi(
      nom: nom,
      octets: ecrireClasseur([
        FeuilleEcrite('Élèves', [
          [for (final t in titres) CelluleEcrite(t, StyleCellule.entete)],
          for (final l in lignes)
            [
              for (final v in l)
                v == null
                    ? null
                    : v is DateTime
                        ? CelluleEcrite(v, StyleCellule.date)
                        : CelluleEcrite(v),
            ],
        ]),
      ]),
    );

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Services services;
  late EtatApp etat;
  late Directory dossier;
  FichierChoisi? fichier;
  final ouverts = <String>[];

  Future<bool> ouvreur(String chemin) async {
    ouverts.add(chemin);
    return true;
  }

  Future<void> demarrer(WidgetTester tester, {Session? session}) async {
    tester.view.physicalSize = const Size(1500, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    ouverts.clear();
    fichier = null;
    dossier = Directory.systemTemp.createTempSync('gesco_import_ui_');
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
      final a = (await admin.classes.creer(anneeId: annee, nom: '10e A', niveauCode: 10)).id;
      await admin.classes.creer(anneeId: annee, nom: '10e B', niveauCode: 10);
      await admin.eleves.inscrire(
        const Eleve(matricule: '2026-0001', nom: 'BARRY', prenom: 'Mamadou', sexe: 'M'),
        anneeId: annee,
        classeId: a,
      );
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
    final onglet = find.byKey(const Key('excel_vue_import_eleves'));
    await attendre(tester, onglet);
    await tester.tap(onglet);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vue_import_eleves')), findsOneWidget);
  }

  /// Choisit le fichier et attend la carte d'association des colonnes.
  Future<void> choisirFichier(WidgetTester tester, FichierChoisi f) async {
    fichier = f;
    await tester.tap(find.byKey(const Key('import_choisir')));
    await tester.pump();
    await attendre(tester, find.byKey(const Key('import_association')));
    await tester.pumpAndSettle();
  }

  Future<void> verifier(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('import_verifier')));
    await tester.tap(find.byKey(const Key('import_verifier')));
    await tester.pump();
    await attendre(tester, find.byKey(const Key('import_rapport_carte')));
    await tester.pumpAndSettle();
  }

  Future<void> toucher(WidgetTester tester, String cle) async {
    await tester.ensureVisible(find.byKey(Key(cle)));
    await tester.tap(find.byKey(Key(cle)));
  }

  Future<void> importer(WidgetTester tester) async {
    await toucher(tester, 'import_lancer');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import_confirmer_oui')));
    await tester.pump();
    await attendre(tester, find.byKey(const Key('import_resultat')));
    await tester.pumpAndSettle();
  }

  Future<void> choisirDansListe(WidgetTester tester, String cle, String libelle) async {
    await tester.ensureVisible(find.byKey(Key(cle)));
    await tester.tap(find.byKey(Key(cle)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(libelle).last);
    await tester.pumpAndSettle();
  }

  String texte(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  Future<List<EleveInscrit>> elevesDeLaBase(WidgetTester tester, {int? classeId}) async =>
      (await tester.runAsync(
        () => services.eleves.lister(etat.anneeId!, classeId: classeId),
      ))!;

  List<File> classeurs() => [
        for (final f in dossier.listSync())
          if (f is File && f.path.endsWith('.xlsx')) f,
      ];

  group('import des élèves', () {
    testWidgets('fichier correct : vérification, import, relecture de la base', (tester) async {
      await demarrer(tester);
      await ouvrirImport(tester);
      await choisirFichier(tester, classeurEleves([
        ['2026-0010', 'SOW', 'Ali', 'M', DateTime(2012, 5, 1), '10e A'],
        [null, 'DIALLO', 'Aminata', 'F', '05/03/2011', '10e B'],
        ['2026-0001', 'BARRY', 'Mamadou', 'M', null, '10e A'],
      ]));
      expect(texte(tester, 'import_fichier'), contains('eleves.xlsx'));
      expect(texte(tester, 'import_fichier'), contains('3 lignes'));

      await verifier(tester);
      expect(find.text('À importer (2)'), findsOneWidget);
      expect(find.text('Déjà présents (1)'), findsOneWidget);
      expect(find.text('En erreur (0)'), findsOneWidget);
      expect(find.text('À importer'), findsNWidgets(2));
      expect(find.text('Déjà présent'), findsOneWidget);
      expect(find.textContaining('2026-0011'), findsOneWidget,
          reason: 'matricule attribué à la ligne sans matricule');
      expect((await elevesDeLaBase(tester)).length, 1, reason: 'rien n\'est écrit avant la confirmation');

      await importer(tester);
      expect(texte(tester, 'import_resultat_titre'), '2 élèves importés et retrouvés dans la base.');
      expect(find.textContaining('1 ligne ignorée'), findsOneWidget);
      expect(find.byKey(const Key('import_association')), findsNothing,
          reason: 'le fichier est oublié : pas de réimport par erreur');

      final base = await elevesDeLaBase(tester);
      expect(base.map((e) => e.nom), ['BARRY', 'DIALLO', 'SOW']);
      expect(base.map((e) => e.matricule).toSet(), {'2026-0001', '2026-0010', '2026-0011'});
      final sow = base.firstWhere((e) => e.nom == 'SOW');
      expect(sow.dateNaissance, '2012-05-01');
      expect(base.firstWhere((e) => e.nom == 'DIALLO').dateNaissance, '2011-03-05');
      expect(base.firstWhere((e) => e.nom == 'DIALLO').classeNom, '10e B');
      await fin(tester);
    });

    testWidgets('lignes en erreur : refus tant qu\'elles ne sont pas ignorées', (tester) async {
      await demarrer(tester);
      await ouvrirImport(tester);
      await choisirFichier(tester, classeurEleves([
        ['2026-0020', 'SOW', 'Ali', 'M', null, '10e A'],
        ['2026-0021', 'BAH', 'Fatou', 'X', null, '10e A'],
        ['2026-0022', 'CAMARA', 'Moussa', 'M', null, '11e Z'],
      ]));
      await verifier(tester);
      expect(find.text('En erreur (2)'), findsOneWidget);
      expect(find.text('À importer (1)'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('import_lancer'))).onPressed, isNull);
      expect(find.byKey(const Key('import_explication')), findsOneWidget);
      expect(texte(tester, 'import_explication'), contains('Corrigez le fichier Excel'));

      await toucher(tester, 'import_filtre_erreurs');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import_ligne_2')), findsNothing);
      expect(find.byKey(const Key('import_ligne_3')), findsOneWidget);
      expect(find.byKey(const Key('import_ligne_4')), findsOneWidget);
      expect(find.textContaining('« X » non reconnu'), findsOneWidget);
      expect(find.textContaining('« 11e Z » inconnue'), findsOneWidget);

      await toucher(tester, 'import_ignorer');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byKey(const Key('import_lancer'))).onPressed,
          isNotNull);
      expect(find.text('Importer 1 élève'), findsOneWidget);

      await importer(tester);
      expect(texte(tester, 'import_resultat_titre'), '1 élève importé et retrouvé dans la base.');
      expect(find.textContaining('2 lignes en erreur ignorées'), findsOneWidget);
      expect((await elevesDeLaBase(tester)).map((e) => e.nom), ['BARRY', 'SOW']);
      await fin(tester);
    });

    testWidgets('annuler : rien n\'est enregistré', (tester) async {
      await demarrer(tester);
      await ouvrirImport(tester);
      await choisirFichier(tester, classeurEleves([
        ['2026-0030', 'SOW', 'Ali', 'M', null, '10e A'],
      ]));
      await verifier(tester);
      await toucher(tester, 'import_annuler');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import_association')), findsNothing);
      expect(find.byKey(const Key('import_rapport_carte')), findsNothing);
      expect((await elevesDeLaBase(tester)).length, 1);
      await fin(tester);
    });

    testWidgets('refuser la confirmation n\'enregistre rien', (tester) async {
      await demarrer(tester);
      await ouvrirImport(tester);
      await choisirFichier(tester, classeurEleves([
        ['2026-0030', 'SOW', 'Ali', 'M', null, '10e A'],
      ]));
      await verifier(tester);
      await toucher(tester, 'import_lancer');
      await tester.pumpAndSettle();
      expect(find.text('Importer 1 élève ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('import_confirmer_non')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import_resultat')), findsNothing);
      expect((await elevesDeLaBase(tester)).length, 1);
      await fin(tester);
    });

    testWidgets('rapport enregistré en Excel avec les lignes à signaler', (tester) async {
      await demarrer(tester);
      await ouvrirImport(tester);
      await choisirFichier(tester, classeurEleves([
        ['2026-0020', 'SOW', 'Ali', 'M', null, '10e A'],
        ['2026-0021', 'BAH', 'Fatou', 'X', null, '10e A'],
      ]));
      await verifier(tester);
      await toucher(tester, 'import_rapport');
      await tester.pump();
      await attendre(tester, find.byKey(const Key('excel_resultat')));

      final fichiers = classeurs();
      expect(fichiers, hasLength(1));
      expect(ouverts, [fichiers.single.path]);
      final feuille = lireClasseur(fichiers.single.readAsBytesSync()).feuille('Rapport')!;
      expect(feuille.cellule(0, 0).texte, 'Groupe Scolaire Test');
      expect(feuille.cellule(1, 0).texte, 'Rapport de vérification de l\'import des élèves');
      final textes = [
        for (final l in feuille.lignes)
          for (final c in l) c.texte,
      ];
      expect(textes, contains('Erreur'));
      expect(textes.any((t) => t.contains('« X » non reconnu')), isTrue);
      expect(textes, isNot(contains('À importer')), reason: 'les lignes sans souci ne sont pas listées');
      await fin(tester);
    });

    testWidgets('modèle à remplir enregistré', (tester) async {
      await demarrer(tester);
      await ouvrirImport(tester);
      await tester.tap(find.byKey(const Key('import_modele')));
      await tester.pump();
      await attendre(tester, find.byKey(const Key('excel_resultat')));
      final fichiers = classeurs();
      expect(fichiers, hasLength(1));
      final feuille = lireClasseur(fichiers.single.readAsBytesSync()).feuille('Élèves')!;
      expect(feuille.cellule(5, 1).texte, 'Nom');
      expect(feuille.cellule(5, 13).texte, 'Classe');
      expect(feuille.cellule(0, 0).texte, 'Groupe Scolaire Test');
      await fin(tester);
    });

    testWidgets('titres non reconnus : association manuelle des colonnes', (tester) async {
      await demarrer(tester);
      await ouvrirImport(tester);
      await choisirFichier(
        tester,
        classeurEleves(
          [
            ['A1', 'SOW', 'Ali', 'M', '10e A'],
          ],
          titres: ['Réf', 'Famille', 'Prénoms', 'Genre', 'Division'],
        ),
      );
      await verifier(tester);
      expect(find.textContaining('champ obligatoire « Nom »'), findsOneWidget);
      expect(find.byKey(const Key('import_filtre_tout')), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const Key('import_lancer'))).onPressed, isNull);

      await choisirDansListe(tester, 'import_col_1', 'Nom *');
      expect(find.byKey(const Key('import_rapport_carte')), findsNothing,
          reason: 'changer l\'association invalide la vérification');
      await choisirDansListe(tester, 'import_col_4', 'Classe');
      await verifier(tester);
      expect(find.text('À importer (1)'), findsOneWidget);
      expect(find.textContaining('Aucune colonne « Matricule »'), findsOneWidget);

      await importer(tester);
      final base = await elevesDeLaBase(tester);
      final sow = base.firstWhere((e) => e.nom == 'SOW');
      expect(sow.matricule, '2026-0002');
      expect(sow.classeNom, '10e A');
      await fin(tester);
    });

    testWidgets('classe choisie pour tout le fichier', (tester) async {
      await demarrer(tester);
      await ouvrirImport(tester);
      await choisirFichier(
        tester,
        classeurEleves(
          [
            ['2026-0040', 'SOW', 'Ali', 'M'],
            ['2026-0041', 'BAH', 'Fatou', 'F'],
          ],
          titres: ['Matricule', 'Nom', 'Prénom', 'Sexe'],
        ),
      );
      await verifier(tester);
      expect(find.textContaining('classe de tous les élèves'), findsWidgets);
      expect(tester.widget<FilledButton>(find.byKey(const Key('import_lancer'))).onPressed, isNull);

      await choisirDansListe(tester, 'import_classe_defaut', '10e B');
      await verifier(tester);
      expect(find.text('À importer (2)'), findsOneWidget);
      await importer(tester);
      final classes = (await tester.runAsync(() => services.classes.lister(etat.anneeId!)))!;
      final b = classes.firstWhere((c) => c.classe.nom == '10e B').classe.id;
      expect((await elevesDeLaBase(tester, classeId: b)).map((e) => e.nom), ['BAH', 'SOW']);
      await fin(tester);
    });

    testWidgets('fichier illisible : message clair, rien ne change', (tester) async {
      await demarrer(tester);
      await ouvrirImport(tester);
      fichier = FichierChoisi(nom: 'photo.xlsx', octets: Uint8List.fromList([1, 2, 3, 4]));
      await tester.tap(find.byKey(const Key('import_choisir')));
      await tester.pump();
      await attendre(tester, find.byType(SnackBar));
      expect(find.textContaining('n\'est pas un classeur Excel'), findsOneWidget);
      expect(find.byKey(const Key('import_association')), findsNothing);
      await fin(tester);
    });

    testWidgets('sans le droit de gérer les élèves : import désactivé', (tester) async {
      final session = Session()
        ..ouvrir(Utilisateur(
          id: 1,
          identifiant: 'secretaire',
          nomComplet: 'Secrétaire',
          role: RoleUtilisateur.consultation,
          actif: true,
          creeLe: '2026-01-01',
          permissionsPersonnalisees:
              Permission.values.where((p) => p != Permission.elevesGerer).toSet(),
        ));
      await demarrer(tester, session: session);
      await ouvrirImport(tester);
      expect(find.byKey(const Key('import_refus')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('import_choisir'))).onPressed,
          isNull);
      await fin(tester);
    });
  });
}
