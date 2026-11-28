import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/app/bulletins_auto.dart';
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_securite.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:gesco/ui/resultats/avis_bulletins_auto.dart';
import 'package:gesco/ui/resultats/page_resultats.dart';
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
  late Directory racine;
  late BulletinsAuto auto;
  late int annee;
  late int classe;
  late int maths;
  late int barry;
  final ouverts = <String>[];

  Future<bool> ouvreur(String chemin) async {
    ouverts.add(chemin);
    return true;
  }

  Future<void> demarrer(
    WidgetTester tester, {
    bool avecAuto = true,
    Session? session,
    bool afficher = true,
  }) async {
    tester.view.physicalSize = const Size(1500, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    ouverts.clear();
    racine = Directory.systemTemp.createTempSync('gesco_auto_ui_');
    addTearDown(() {
      if (racine.existsSync()) racine.deleteSync(recursive: true);
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
      maths = (await admin.matieres.ajouter(classeId: classe, nom: 'Maths', coefficient: 100)).id;
      Future<int> inscrire(String matricule, String nom, String prenom, String sexe) =>
          admin.eleves.inscrire(
            Eleve(matricule: matricule, nom: nom, prenom: prenom, sexe: sexe),
            anneeId: annee,
            classeId: classe,
          );
      barry = await inscrire('2026-0001', 'BARRY', 'Mamadou', 'M');
      final diallo = await inscrire('2026-0002', 'DIALLO', 'Aminata', 'F');
      await admin.notes.enregistrer(
          inscriptionId: barry, matiereId: maths, mois: 11, saisie: const Saisie.valeur(1600));
      await admin.notes.enregistrer(
          inscriptionId: diallo, matiereId: maths, mois: 11, saisie: const Saisie.valeur(1400));
    });
    services = session == null ? admin : Services(gdb, session: session, iterations: 2);
    auto = BulletinsAuto(
      services: services,
      dossierRacine: () async => racine,
      chargerPolices: () async => exemples.polices(),
      delai: const Duration(seconds: 30),
    );
    // L'écoute démarre dans la vraie zone asynchrone : les saisies de notes
    // faites pendant le test y sont reçues.
    await tester.runAsync(() async => auto.demarrer());
    addTearDown(auto.dispose);

    etat = EtatApp(
      services,
      chemin: 'en mémoire',
      bulletinsAuto: avecAuto ? auto : null,
    );
    await tester.runAsync(() => etat.charger());
    if (!afficher) return;
    await tester.pumpWidget(
      MaterialApp(
        home: AvisBulletinsAuto(
          auto: etat.bulletinsAuto,
          child: Scaffold(
            body: ListenableBuilder(
              listenable: etat,
              builder: (context, _) => PageResultats(
                etat: etat,
                allerAuxParametres: () {},
                maintenant: () => DateTime(2026, 11, 5),
                ouvreur: ouvreur,
                dossierDocuments: racine,
                chargerPolices: () async => exemples.polices(),
              ),
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

  Future<void> ouvrirOnglet(WidgetTester tester) async {
    await attendre(tester, find.byKey(const Key('vue_bulletins')));
    await tester.tap(find.byKey(const Key('vue_bulletins')));
    await tester.pump();
    await attendre(tester, find.byKey(const Key('generer_bulletins')));
    await attendre(tester, find.byKey(const Key('auto_bulletins_dossier')));
  }

  String texte(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  String texteSelectionnable(WidgetTester tester, String cle) =>
      tester.widget<SelectableText>(find.byKey(Key(cle))).data!;

  bool interrupteur(WidgetTester tester) =>
      tester.widget<Switch>(find.byKey(const Key('auto_bulletins_actif'))).value;

  Directory dossierClasse() => Directory(p.join(racine.path, 'Bulletins', '2026-2027', '10e_A'));

  Future<void> noterEtAttendre(WidgetTester tester, int mois, int centiemes) async {
    await tester.runAsync(() async {
      await services.notes.enregistrer(
        inscriptionId: barry,
        matiereId: maths,
        mois: mois,
        saisie: Saisie.valeur(centiemes),
      );
      await auto.vider();
    });
    await tester.pump();
  }

  testWidgets('sans générateur, aucune carte n\'est affichée', (tester) async {
    await demarrer(tester, avecAuto: false);
    await attendre(tester, find.byKey(const Key('vue_bulletins')));
    await tester.tap(find.byKey(const Key('vue_bulletins')));
    await tester.pump();
    await attendre(tester, find.byKey(const Key('generer_bulletins')));
    expect(find.byKey(const Key('auto_bulletins_actif')), findsNothing);
    expect(find.byKey(const Key('auto_bulletins_tout')), findsNothing);
    await fin(tester);
  });

  testWidgets('la carte montre l\'interrupteur activé et le dossier de destination',
      (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);

    expect(interrupteur(tester), isTrue);
    expect(texteSelectionnable(tester, 'auto_bulletins_dossier'), p.join(racine.path, 'Bulletins'));
    expect(texte(tester, 'auto_bulletins_texte'), contains('2 semestres'));
    expect(find.text('Tout générer : Trimestre 1'), findsOneWidget);
    expect(find.byKey(const Key('auto_bulletins_resume')), findsNothing);
    await fin(tester);
  });

  testWidgets('« Ouvrir le dossier » crée le dossier au besoin et l\'ouvre', (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);
    final dossier = Directory(p.join(racine.path, 'Bulletins'));
    expect(dossier.existsSync(), isFalse);

    await tester.tap(find.byKey(const Key('auto_bulletins_ouvrir')));
    await tester.pump();
    for (var i = 0; i < 50 && ouverts.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(ouverts, [dossier.path]);
    expect(dossier.existsSync(), isTrue);
    await fin(tester);
  });

  testWidgets('« Tout générer » produit un PDF par élève et un PDF de classe', (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);

    await tester.tap(find.byKey(const Key('auto_bulletins_tout')));
    await tester.pump();
    await attendre(tester, find.byKey(const Key('auto_bulletins_resume')));

    expect(texte(tester, 'auto_bulletins_resume'),
        '2 bulletins individuels (1 classe/période)');
    expect(texte(tester, 'auto_bulletins_quand'), startsWith('Dernière génération manuelle'));
    final periode = Directory(p.join(dossierClasse().path, 'Trimestre_1'));
    final noms = [for (final f in periode.listSync()) p.basename(f.path)]..sort();
    expect(noms, [
      '00_Classe_entiere.pdf',
      'BARRY_Mamadou_2026-0001.pdf',
      'DIALLO_Aminata_2026-0002.pdf',
    ]);
    for (final f in periode.listSync().whereType<File>()) {
      expect(String.fromCharCodes(f.readAsBytesSync().take(5)), '%PDF-', reason: f.path);
    }
    expect(find.byKey(const Key('auto_bulletins_en_cours')), findsNothing);
    await fin(tester);
  });

  testWidgets('l\'interrupteur est mémorisé et coupe la génération automatique',
      (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);

    await tester.tap(find.byKey(const Key('auto_bulletins_actif')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(interrupteur(tester), isFalse);
    expect(texte(tester, 'auto_bulletins_texte'), contains('désactivée'));
    expect(await tester.runAsync(() => services.parametres.bulletinsAutomatiques()), isFalse);

    // Une saisie de notes ne produit alors aucun fichier.
    await noterEtAttendre(tester, 11, 1700);
    expect(Directory(p.join(racine.path, 'Bulletins')).existsSync(), isFalse);
    expect(auto.dernierRapport, isNull);

    // On réactive : la saisie suivante produit les bulletins.
    await tester.tap(find.byKey(const Key('auto_bulletins_actif')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(interrupteur(tester), isTrue);
    await noterEtAttendre(tester, 11, 1800);
    expect(File(p.join(dossierClasse().path, 'Mensuel_Novembre', '00_Classe_entiere.pdf'))
        .existsSync(), isTrue);
    await fin(tester);
  });

  testWidgets('une saisie de notes régénère les bulletins et la carte l\'indique',
      (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);

    await noterEtAttendre(tester, 11, 1900);

    expect(texte(tester, 'auto_bulletins_quand'), startsWith('Dernière génération automatique'));
    expect(texte(tester, 'auto_bulletins_resume'),
        '2 bulletins individuels (1 classe/période)');
    final mensuel = Directory(p.join(dossierClasse().path, 'Mensuel_Novembre'));
    expect(mensuel.listSync().length, 3);
    expect(find.byKey(const Key('auto_bulletins_erreur_0')), findsNothing);
    await fin(tester);
  });

  testWidgets('un message annonce la fin d\'une génération automatique, pas d\'une manuelle',
      (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);
    expect(find.textContaining('mis à jour automatiquement'), findsNothing);

    await noterEtAttendre(tester, 11, 1500);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Bulletins mis à jour automatiquement : 2 bulletins'),
        findsOneWidget);

    // Génération manuelle : le message de la carte, pas celui de l'avis automatique.
    await tester.pump(const Duration(seconds: 6));
    await tester.tap(find.byKey(const Key('auto_bulletins_tout')));
    await tester.pump();
    await attendre(tester, find.textContaining('Terminé :'));
    expect(find.textContaining('mis à jour automatiquement'), findsNothing);
    await fin(tester);
  });

  testWidgets('un dossier inutilisable : l\'erreur est affichée, rien ne plante',
      (tester) async {
    await demarrer(tester);
    await ouvrirOnglet(tester);
    // Un fichier occupe l'emplacement du dossier « Bulletins ».
    File(p.join(racine.path, 'Bulletins')).writeAsStringSync('occupé');

    await noterEtAttendre(tester, 11, 1300);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('auto_bulletins_erreur_0')), findsOneWidget);
    expect(find.textContaining('erreur'), findsWidgets);
    await fin(tester);
  });

  testWidgets('sans l\'autorisation de générer les documents : réglage et bouton désactivés',
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

    expect(tester.widget<Switch>(find.byKey(const Key('auto_bulletins_actif'))).onChanged, isNull);
    expect(
        tester.widget<ButtonStyleButton>(find.byKey(const Key('auto_bulletins_tout'))).onPressed,
        isNull);
    await fin(tester);
  });
}
