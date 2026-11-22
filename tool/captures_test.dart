// Captures d'écran de GESCO, produites par le test (pas par une vraie fenêtre).
//
// Rend les écrans avec des données d'exemple, avec le vrai code de
// l'application et la police Roboto du SDK Flutter, et écrit des PNG dans
// `captures/`. Sert à relire l'interface sans avoir à lancer l'application.
//
// Lancer :  flutter test tool/captures_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/bulletins_auto.dart';
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/niveaux.dart';
import 'package:gesco/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test/documents/exemples.dart' as exemples;

const String dossierSortie = 'captures';

Future<void> chargerPolices() async {
  final racine = Platform.environment['FLUTTER_ROOT'] ?? '';
  final dossier = '$racine/bin/cache/artifacts/material_fonts';
  Future<void> charger(String famille, List<String> fichiers) async {
    final chargeur = FontLoader(famille);
    var trouves = 0;
    for (final nom in fichiers) {
      final f = File('$dossier/$nom');
      if (f.existsSync()) {
        final octets = f.readAsBytesSync();
        chargeur.addFont(Future.value(ByteData.sublistView(octets)));
        trouves++;
      }
    }
    if (trouves > 0) await chargeur.load();
    // ignore: avoid_print
    print('POLICE $famille : $trouves fichier(s) chargé(s) depuis $dossier');
  }

  await charger('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await charger('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

/// Données d'exemple, créées avec les vrais dépôts de l'application.
Future<void> semer(Services s) async {
  await s.etablissements.enregistrer(const Etablissement(
    nom: 'Groupe Scolaire Exemple',
    adresse: 'Quartier Exemple, Conakry',
    telephone: '+224 600 00 00 00',
    email: 'contact@exemple.gn',
  ));
  final annee = await s.annees.creer('2026-2027');

  const matieres = <(String, int)>[
    ('Mathématiques', 400),
    ('Français', 400),
    ('Physique-Chimie', 300),
    ('Anglais', 200),
    ('SVT', 200),
    ('Histoire-Géographie', 200),
    ('EPS', 100),
  ];
  const eleves = <String, List<(String, String, String)>>{
    '10e A': [
      ('Diallo', 'Aminata', 'F'),
      ('Bah', 'Mamadou', 'M'),
      ('Camara', 'Fatoumata', 'F'),
      ('Barry', 'Ibrahima', 'M'),
      ('Sow', 'Mariama', 'F'),
      ('Keita', 'Sékou', 'M'),
    ],
    '10e B': [
      ('Touré', 'Aïssatou', 'F'),
      ('Condé', 'Alpha', 'M'),
      ('Soumah', 'Kadiatou', 'F'),
      ('Sylla', 'Moussa', 'M'),
      ('Baldé', 'Hawa', 'F'),
    ],
    '9e A': [
      ('Traoré', 'Ousmane', 'M'),
      ('Fofana', 'Nene', 'F'),
    ],
    'CE2 A': [
      ('Kourouma', 'Fanta', 'F'),
      ('Bangoura', 'Lansana', 'M'),
      ('Camara', 'Mariam', 'F'),
    ],
    'Tle SM': [
      ('Diakité', 'Mohamed', 'M'),
      ('Sidibé', 'Kadiatou', 'F'),
      ('Cissé', 'Abdoulaye', 'M'),
    ],
  };
  // Niveau du catalogue et option du lycée de chaque classe.
  const niveaux = <String, (int, SerieLycee?)>{
    '10e A': (10, null),
    '10e B': (10, null),
    '9e A': (9, null),
    'CE2 A': (3, null),
    'Tle SM': (13, SerieLycee.sciencesMathematiques),
  };

  var numero = 0;
  for (final entree in eleves.entries) {
    final classe = await s.classes.creer(
      anneeId: annee.id,
      nom: entree.key,
      niveauCode: niveaux[entree.key]!.$1,
      serie: niveaux[entree.key]!.$2,
    );
    final matieresClasse = <MatiereClasse>[];
    for (final m in matieres) {
      matieresClasse.add(
        await s.matieres.ajouter(classeId: classe.id, nom: m.$1, coefficient: m.$2),
      );
    }
    for (final e in entree.value) {
      numero++;
      final inscription = await s.eleves.inscrire(
        Eleve(
          matricule: '2026-${numero.toString().padLeft(4, '0')}',
          nom: e.$1,
          prenom: e.$2,
          sexe: e.$3,
          dateNaissance: '${2010 + numero % 3}-0${1 + numero % 9}-1${numero % 9}',
          lieuNaissance: 'Conakry',
          nomPere: 'Père de ${e.$2}',
          nomMere: 'Mère de ${e.$2}',
          contactParent: '+224 62$numero 00 00 00',
          adresse: 'Quartier Exemple',
        ),
        anneeId: annee.id,
        classeId: classe.id,
      );
      // Notes d'octobre et de novembre (quelques cases vides et une absence).
      for (final mois in [10, 11]) {
        for (var i = 0; i < matieresClasse.length; i++) {
          final graine = numero * 7 + i * 13 + mois * 5;
          if (graine % 11 == 0) continue;
          final saisie = graine % 23 == 0
              ? const Saisie.absent()
              : Saisie.valeur((graine % 15 + 5) * 100 + (numero * 25) % 100);
          await s.notes.enregistrer(
            inscriptionId: inscription,
            matiereId: matieresClasse[i].id,
            mois: mois,
            saisie: saisie,
          );
        }
      }
    }
  }
}

void main() {
  sqfliteFfiInit();

  testWidgets('captures des écrans', timeout: const Timeout(Duration(minutes: 4)),
      (tester) async {
    // Dans les tests, Flutter remplace les ombres par des traits noirs ; on
    // veut ici le rendu réel de l'application.
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    await tester.runAsync(chargerPolices);

    final gdb = await tester.runAsync(() => GescoDatabase.ouvrir(
          fabrique: databaseFactoryFfi,
          chemin: inMemoryDatabasePath,
        ));
    final services = Services(gdb!);
    await tester.runAsync(() => semer(services));
    final dossierBulletins = Directory.systemTemp.createTempSync('gesco_captures_');
    final etat = EtatApp(
      services,
      chemin: 'en mémoire',
      bulletinsAuto: BulletinsAuto(
        services: services,
        dossierRacine: () async => dossierBulletins,
        chargerPolices: () async => exemples.polices(),
      ),
    );
    await tester.runAsync(etat.charger);

    final cle = GlobalKey();
    var echecs = 0;

    Future<void> attendre() async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 350)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> taille(double largeur, double hauteur) async {
      tester.view.physicalSize = Size(largeur, hauteur);
      tester.view.devicePixelRatio = 1.0;
      await tester.pump();
    }

    Future<void> capturer(String nom) async {
      await attendre();
      final frontiere = tester.renderObject<RenderRepaintBoundary>(find.byKey(cle));
      final image = await tester.runAsync(() => frontiere.toImage(pixelRatio: 1.0));
      final donnees = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
      final fichier = File('$dossierSortie/$nom.png');
      fichier.createSync(recursive: true);
      fichier.writeAsBytesSync(donnees!.buffer.asUint8List());
      // ignore: avoid_print
      print('CAPTURE $nom (${image!.width}x${image.height})');
    }

    /// Une étape qui échoue ne doit pas empêcher les captures suivantes.
    Future<void> etape(String nom, Future<void> Function() action) async {
      try {
        await action();
        await capturer(nom);
      } catch (erreur) {
        echecs++;
        // ignore: avoid_print
        print('CAPTURE_ECHEC $nom : $erreur');
      }
    }

    Future<void> toucher(Finder f) async {
      bool vide;
      try {
        vide = f.evaluate().isEmpty;
      } on StateError {
        vide = true;
      }
      if (vide) throw StateError('Élément introuvable : ${f.description}');
      // Les puces de période défilent : on amène la cible à l'écran avant.
      await tester.ensureVisible(f.first);
      await tester.pump();
      await tester.tap(f.first);
      await attendre();
    }

    Future<void> toucherSiPresent(Finder f) async {
      var present = false;
      try {
        present = f.evaluate().isNotEmpty;
      } on StateError {
        present = false;
      }
      if (present) await toucher(f);
    }

    await taille(1280, 860);
    await tester.pumpWidget(RepaintBoundary(key: cle, child: GescoApp(etat: etat)));

    await etape('01_tableau_de_bord', () async {});
    await etape('02_inscriptions', () async => toucher(find.text('Inscriptions').first));
    await etape('03_formulaire_eleve', () async => toucher(find.text('Inscrire un élève')));
    await toucherSiPresent(find.text('Annuler'));
    // La liste est triée par nom : BAH Mamadou est le premier.
    await etape('04_fiche_eleve', () async => toucher(find.text('BAH Mamadou')));
    await toucherSiPresent(find.text('Fermer'));

    await toucherSiPresent(find.text('Paramètres').first);
    await etape('05_parametres_etablissement', () async {});
    await etape('06_parametres_annees', () async => toucher(find.text('Années scolaires')));
    await etape('07_parametres_classes', () async => toucher(find.text('Classes et matières')));
    await etape('08_parametres_mentions', () async => toucher(find.text('Mentions et décisions')));

    // Nouveau : cycles (primaire, collège, lycée) et options du lycée.
    await taille(1280, 1200);
    await etape('17_formulaire_classe', () async {
      await toucher(find.text('Classes et matières'));
      // Le défilement entre onglets éloignés demande quelques images de plus.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await toucher(find.text('Ajouter').first);
      await toucher(find.byKey(const Key('choix_niveau_classe')));
      await toucher(find.text('Terminale · Lycée').last);
      await toucher(find.byKey(const Key('choix_serie_classe')));
      await toucher(find.text('Sciences mathématiques').last);
    });
    await toucherSiPresent(find.text('Annuler'));
    await taille(1280, 860);
    await etape('18_parametres_periodes', () async => toucher(find.text('Périodes')));
    await etape('19_periodes_primaire', () async =>
        toucher(find.byKey(const Key('cycle_periodes_primaire'))));
    await etape('20_periodes_college', () async =>
        toucher(find.byKey(const Key('cycle_periodes_college'))));

    await toucherSiPresent(find.byKey(const Key('menu_resultats')));
    await etape('21_resultats_eleves', () async {});
    await etape('22_resultats_classes', () async =>
        toucher(find.byKey(const Key('vue_classes'))));
    await etape('23_resultats_bulletins', () async =>
        toucher(find.byKey(const Key('vue_bulletins'))));
    await etape('24_bulletins_auto_resultat', () async {
      await toucher(find.byKey(const Key('auto_bulletins_tout')));
      for (var i = 0; i < 200; i++) {
        if (find.byKey(const Key('auto_bulletins_resume')).evaluate().isNotEmpty) break;
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
    // Appréciations proposées automatiquement d'après les notes et le classement.
    await etape('27_resultats_appreciations', () async {
      await toucher(find.byKey(const Key('vue_appreciations')));
      for (var i = 0; i < 100; i++) {
        if (find.byKey(const Key('appr_tout_utiliser')).evaluate().isNotEmpty) break;
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
    await toucherSiPresent(find.byKey(const Key('menu_tableau_de_bord')));
    await etape('25_tableau_de_bord_cycles', () async {});

    await toucher(find.byKey(const Key('menu_notes')));
    await etape('11_notes_octobre', () async =>
        toucher(find.byKey(const Key('periode_m10'))));
    await etape('12_notes_saisie', () async {
      await toucher(find.byKey(const Key('case_1_0')));
    });
    await etape('13_notes_novembre', () async =>
        toucher(find.byKey(const Key('periode_m11'))));
    await etape('14_notes_trimestre', () async =>
        toucher(find.byKey(const Key('periode_t1'))));
    await etape('15_notes_annee', () async =>
        toucher(find.byKey(const Key('periode_annee'))));

    // Fiche de notes à remettre au professeur : fenêtre d'impression.
    await toucher(find.byKey(const Key('menu_notes')));
    await etape('26_notes_fiche_dialogue', () async {
      await toucher(find.byKey(const Key('periode_m11')));
      await toucher(find.byKey(const Key('bouton_fiche_notes')));
      for (var i = 0; i < 20; i++) {
        if (find.byKey(const Key('fiche_contenu')).evaluate().isNotEmpty) break;
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
    await toucherSiPresent(find.byKey(const Key('fiche_fermer')));

    // Petit écran (téléphone).
    await taille(420, 860);
    await toucher(find.text('Accueil').first);
    await etape('09_mobile_tableau_de_bord', () async {});
    await etape('10_mobile_inscriptions', () async => toucher(find.text('Inscriptions').first));
    await etape('16_mobile_notes', () async => toucher(find.text('Notes').first));

    // ignore: avoid_print
    print('CAPTURES TERMINÉES : $echecs échec(s)');
    addTearDown(tester.view.reset);
  });
}
