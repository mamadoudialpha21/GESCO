import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_securite.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:gesco/ui/resultats/page_resultats.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../documents/exemples.dart' as exemples;

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late EtatApp etat;
  late Directory dossier;
  final ouverts = <String>[];
  var ouvertureReussie = true;

  Future<bool> ouvreur(String chemin) async {
    ouverts.add(chemin);
    return ouvertureReussie;
  }

  Future<void> demarrer(WidgetTester tester, {Session? session}) async {
    tester.view.physicalSize = const Size(1500, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    ouverts.clear();
    ouvertureReussie = true;
    dossier = Directory.systemTemp.createTempSync('gesco_bulletins_');
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
      final annee = await admin.annees.creer('2026-2027', activer: true);
      final a = await admin.classes.creer(anneeId: annee.id, nom: '10e A', niveau: '10e année');
      final maths = (await admin.matieres.ajouter(classeId: a.id, nom: 'Maths', coefficient: 100)).id;
      Future<int> inscrire(String matricule, String nom, String prenom, String sexe) =>
          admin.eleves.inscrire(
            Eleve(matricule: matricule, nom: nom, prenom: prenom, sexe: sexe),
            anneeId: annee.id,
            classeId: a.id,
          );
      final barry = await inscrire('2026-0001', 'BARRY', 'Mamadou', 'M');
      final diallo = await inscrire('2026-0002', 'DIALLO', 'Aminata', 'F');
      final camara = await inscrire('2026-0003', 'CAMARA', 'Fatou', 'F');
      final sow = await inscrire('2026-0004', 'SOW', 'Ibrahima', 'M');
      Future<void> note(int inscription, int centiemes) => admin.notes.enregistrer(
            inscriptionId: inscription,
            matiereId: maths,
            mois: 11,
            saisie: Saisie.valeur(centiemes),
          );
      await note(barry, 1600);
      await note(diallo, 1400);
      await note(camara, 1000);
      await note(sow, 1800);
      await admin.eleves.enregistrerSortie(sow, StatutInscription.depart, motif: 'Déménagement');
    });
    etat = EtatApp(
      session == null ? admin : Services(gdb, session: session, iterations: 2),
      chemin: 'en mémoire',
    );
    await tester.runAsync(() => etat.charger());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: etat,
            builder: (context, _) => PageResultats(
              etat: etat,
              allerAuxParametres: () {},
              maintenant: () => DateTime(2026, 11, 5),
              ouvreur: ouvreur,
              dossierDocuments: dossier,
              chargerPolices: () async => exemples.polices(),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> attendre(WidgetTester tester, Finder f, {int essais = 80}) async {
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

  Future<void> choisir(WidgetTester tester, String cleListe, String libelle) async {
    await tester.tap(find.byKey(Key(cleListe)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(libelle).last);
    await tester.pumpAndSettle();
  }

  Future<void> ouvrirOnglet(WidgetTester tester) async {
    await attendre(tester, find.byKey(const Key('vue_bulletins')));
    await tester.tap(find.byKey(const Key('vue_bulletins')));
    await tester.pump();
    await attendre(tester, find.byKey(const Key('generer_bulletins')));
  }

  String texte(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  Future<void> produire(WidgetTester tester, String cleBouton) async {
    await tester.tap(find.byKey(Key(cleBouton)));
    await tester.pump();
    await attendre(tester, find.byKey(const Key('dernier_chemin')));
  }

  String cheminAffiche(WidgetTester tester) {
    final selectable = tester.widget<SelectableText>(find.byKey(const Key('dernier_chemin')));
    return selectable.data!;
  }

  void verifierPdfEnregistre(WidgetTester tester, {required String commencePar}) {
    final chemin = cheminAffiche(tester);
    final fichier = File(chemin);
    expect(fichier.existsSync(), isTrue);
    expect(fichier.parent.path, dossier.path);
    expect(fichier.uri.pathSegments.last, startsWith(commencePar));
    expect(fichier.uri.pathSegments.last, endsWith('.pdf'));
    expect(String.fromCharCodes(fichier.readAsBytesSync().take(5)), '%PDF-');
    expect(ouverts, [chemin]);
    // Aucun fichier temporaire ne reste dans le dossier.
    expect(dossier.listSync().every((e) => !e.path.endsWith('.tmp')), isTrue);
  }

  testWidgets('l\'onglet Bulletins propose les huit styles et les boutons d\'édition',
      (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);

    expect(find.byKey(const Key('generer_bulletins')), findsOneWidget);
    expect(find.byKey(const Key('generer_classement')), findsOneWidget);
    // Hors année entière : pas de bouton « Résultats annuels ».
    expect(find.byKey(const Key('generer_resultats_annuels')), findsNothing);
    expect(find.byKey(const Key('dernier_chemin')), findsNothing);
    expect(texte(tester, 'bulletin_type'), startsWith('Bulletin '));
    expect(find.text('Bulletins de la classe (PDF)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('choix_style')));
    await tester.pumpAndSettle();
    for (final nom in [
      'Classique bleu',
      'Couleurs guinéennes',
      'Élégant rose',
      'Moderne anthracite',
      'Minimaliste noir et blanc',
      'Bleu et or',
      'Vert sauge',
      'Violet',
    ]) {
      expect(find.text(nom), findsWidgets, reason: nom);
    }
    await fin(tester);
  });

  testWidgets('bulletins de la classe : PDF enregistré, ouvert et rappelé', (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);
    await produire(tester, 'generer_bulletins');

    // Élèves actifs seulement : BARRY, DIALLO, CAMARA (SOW est parti).
    expect(texte(tester, 'dernier_description'),
        '3 bulletins de la classe 10e A · 3 pages');
    verifierPdfEnregistre(tester, commencePar: 'Bulletins_10e_A_');
    expect(find.byKey(const Key('dernier_non_ouvert')), findsNothing);
    expect(find.byKey(const Key('bulletins_en_cours')), findsNothing);
    await fin(tester);
  });

  testWidgets('un seul élève : son bulletin', (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);
    await choisir(tester, 'choix_eleve_bulletin', 'DIALLO Aminata');
    expect(find.text('Bulletin (PDF)'), findsOneWidget);
    await produire(tester, 'generer_bulletins');

    expect(texte(tester, 'dernier_description'), 'Bulletin de DIALLO Aminata · 1 page');
    verifierPdfEnregistre(tester, commencePar: 'Bulletin_DIALLO_Aminata_');
    await fin(tester);
  });

  testWidgets('un élève parti peut recevoir un bulletin sur demande', (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);
    await choisir(tester, 'choix_eleve_bulletin', 'SOW Ibrahima (Parti)');
    await produire(tester, 'generer_bulletins');

    expect(texte(tester, 'dernier_description'), 'Bulletin de SOW Ibrahima · 1 page');
    await fin(tester);
  });

  testWidgets('classement en PDF', (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);
    await produire(tester, 'generer_classement');

    expect(texte(tester, 'dernier_description'), 'Classement de la classe 10e A · 1 page');
    verifierPdfEnregistre(tester, commencePar: 'Classement_10e_A_');
    await fin(tester);
  });

  testWidgets('année entière : bulletin annuel et résultats annuels', (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);
    await choisir(tester, 'choix_portee', 'Année entière');
    expect(find.byKey(const Key('generer_resultats_annuels')), findsOneWidget);
    expect(texte(tester, 'bulletin_type'), startsWith('Bulletin annuel'));

    await produire(tester, 'generer_resultats_annuels');
    expect(texte(tester, 'dernier_description'),
        'Résultats annuels de la classe 10e A · 1 page');
    verifierPdfEnregistre(tester, commencePar: 'Resultats_annuels_10e_A_');
    await fin(tester);
  });

  testWidgets('si le lecteur PDF ne s\'ouvre pas : fichier enregistré et message clair',
      (tester) async {
    await demarrer(tester);
    ouvertureReussie = false;
    await ouvrirOnglet(tester);
    await produire(tester, 'generer_classement');

    expect(find.byKey(const Key('dernier_non_ouvert')), findsOneWidget);
    expect(File(cheminAffiche(tester)).existsSync(), isTrue);

    // Les boutons permettent de réessayer.
    ouvertureReussie = true;
    ouverts.clear();
    await tester.tap(find.byKey(const Key('ouvrir_dernier')));
    await tester.pump();
    expect(ouverts, [cheminAffiche(tester)]);
    await tester.tap(find.byKey(const Key('ouvrir_dossier')));
    await tester.pump();
    expect(ouverts.last, dossier.path);
    await fin(tester);
  });

  testWidgets('deux éditions successives ne s\'écrasent pas', (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);
    await produire(tester, 'generer_classement');
    final premier = cheminAffiche(tester);
    await tester.tap(find.byKey(const Key('generer_classement')));
    await tester.pump();
    for (var i = 0; i < 80 && ouverts.length < 2; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(ouverts.length, 2);
    final fichiers = [
      for (final e in dossier.listSync())
        if (e.path.endsWith('.pdf')) e.path,
    ];
    expect(fichiers.length, 2);
    expect(fichiers, contains(premier));
    await fin(tester);
  });

  testWidgets('le style choisi est mémorisé et retrouvé', (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);
    await choisir(tester, 'choix_style', 'Violet');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    expect(await tester.runAsync(() => etat.services.parametres.styleDocuments()), 'violet');

    // On quitte l'onglet puis on y revient : le style est relu.
    await tester.tap(find.byKey(const Key('vue_eleves')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('vue_bulletins')));
    await tester.pump();
    await attendre(tester, find.text('Violet'));
    await fin(tester);
  });

  testWidgets('sans l\'autorisation de générer les documents : boutons désactivés',
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
    await ouvrirOnglet(tester);

    expect(find.byKey(const Key('bulletins_interdits')), findsOneWidget);
    for (final cle in ['generer_bulletins', 'generer_classement']) {
      expect(tester.widget<ButtonStyleButton>(find.byKey(Key(cle))).onPressed, isNull,
          reason: cle);
    }
    expect(ouverts, isEmpty);
    await fin(tester);
  });
}
