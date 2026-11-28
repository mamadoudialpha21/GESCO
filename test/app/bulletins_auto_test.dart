import 'dart:io';

import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/app/bulletins_auto.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/changements_notes.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_notation.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/niveaux.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../documents/exemples.dart';

void main() {
  sqfliteFfiInit();

  group('bulletins à produire selon le changement', () {
    final college = Calendrier.deuxTrimestres;
    final primaire = Calendrier.trimestres;

    List<String> cles(Calendrier c, int mois, {bool composition = false}) => [
          for (final x
              in porteesPourChangement(c, ChangementNotes(1, mois, composition: composition)))
            x.cle,
        ];

    test('collège : une saisie ordinaire ne produit que le bulletin du mois', () {
      expect(cles(college, 11), ['m11']);
      expect(cles(college, 10), ['m10']);
      expect(cles(college, 3), ['m3']);
    });

    test('collège : une composition produit aussi le bulletin du trimestre', () {
      expect(cles(college, 11, composition: true), ['m11', 't1']);
      expect(cles(college, 3, composition: true), ['m3', 't2', 'annee']);
    });

    test('collège : le dernier mois d\'un trimestre produit le bulletin du trimestre', () {
      expect(cles(college, 1), ['m1', 't1']);
      expect(cles(college, 6), ['m6', 't2', 'annee']);
    });

    test('primaire : trois trimestres', () {
      expect(cles(primaire, 11), ['m11']);
      expect(cles(primaire, 12), ['m12', 't1']);
      expect(cles(primaire, 3), ['m3', 't2']);
      expect(cles(primaire, 6), ['m6', 't3', 'annee']);
      expect(cles(primaire, 1, composition: true), ['m1', 't2']);
    });

    test('le bulletin annuel suit le dernier trimestre du calendrier', () {
      expect(cles(Calendrier.semestres, 1), ['m1', 's1']);
      expect(cles(Calendrier.semestres, 6), ['m6', 's2', 'annee']);
    });

    test('libellés, types et dossiers', () {
      expect(libellePortee(const Portee.mois(11)), 'Novembre');
      expect(libellePortee(Portee.periode(college.periodes.first)), 'Trimestre 1');
      expect(libellePortee(const Portee.annee()), 'Année entière');
      expect(nomDossierPortee(const Portee.mois(12)), 'Mensuel_Decembre');
      expect(nomDossierPortee(Portee.periode(college.periodes.last)), 'Trimestre_2');
      expect(nomDossierPortee(const Portee.annee()), 'Annuel');
      expect(dernierMoisDe(college.periodes.first), 1);
      expect(dernierMoisDe(primaire.periodes.first), 12);
    });
  });

  group('génération des fichiers', () {
    late GescoDatabase gdb;
    late Services s;
    late Directory racine;
    late BulletinsAuto auto;
    late int annee;
    late int college;
    late int primaire;
    late int matiereCollege;
    late int matierePrimaire;
    late Map<String, int> insc;
    late int evalComposition;

    Directory dossier(String classe, String portee) =>
        Directory(p.join(racine.path, 'Bulletins', '2026-2027', classe, portee));

    List<String> fichiers(Directory d) => d.existsSync()
        ? [for (final f in d.listSync().whereType<File>()) p.basename(f.path)]
        : <String>[];

    Future<void> note(String eleve, int matiere, int mois, int centiemes) =>
        s.notes.enregistrer(
          inscriptionId: insc[eleve]!,
          matiereId: matiere,
          mois: mois,
          saisie: Saisie.valeur(centiemes),
        );

    setUp(() async {
      racine = await Directory.systemTemp.createTemp('gesco_auto_');
      gdb = await GescoDatabase.ouvrir(
        fabrique: databaseFactoryFfi,
        chemin: inMemoryDatabasePath,
      );
      s = Services(gdb, session: Session.sansControle(), iterations: 2);
      annee = (await s.annees.creer('2026-2027', activer: true)).id;
      // Ces tests portent sur l'ancien modèle (trimestres) : on le fixe explicitement.
      await s.calendriers.enregistrer(annee, Calendrier.deuxTrimestres, cycle: Cycle.college);
      await s.calendriers.enregistrer(annee, Calendrier.trimestres, cycle: Cycle.primaire);
      college = (await s.classes.creer(anneeId: annee, nom: '8e A', niveauCode: 8)).id;
      primaire = (await s.classes.creer(anneeId: annee, nom: '3e A', niveauCode: 3)).id;
      matiereCollege =
          (await s.matieres.ajouter(classeId: college, nom: 'Maths', coefficient: 200)).id;
      matierePrimaire =
          (await s.matieres.ajouter(classeId: primaire, nom: 'Calcul', coefficient: 100)).id;
      insc = {};
      var n = 0;
      for (final (nom, classe) in [
        ('BARRY', college),
        ('DIALLO', college),
        ('SOW', college),
        ('CAMARA', primaire),
      ]) {
        n++;
        insc[nom] = await s.eleves.inscrire(
          Eleve(matricule: '2026-000$n', nom: nom, prenom: 'Test', sexe: n.isEven ? 'F' : 'M'),
          anneeId: annee,
          classeId: classe,
        );
      }
      await s.eleves.enregistrerSortie(insc['SOW']!, StatutInscription.depart, motif: 'Départ');
      evalComposition = (await s.evaluations.creer(
        classeId: college,
        matiereId: matiereCollege,
        mois: 11,
        titre: 'Composition du trimestre 1',
        type: TypeEvaluation.composition,
      ))
          .id;
      auto = BulletinsAuto(
        services: s,
        dossierRacine: () async => racine,
        chargerPolices: () async => polices(),
        // Long : les tests déclenchent la génération avec vider().
        delai: const Duration(seconds: 30),
      )..demarrer();
    });

    tearDown(() async {
      auto.dispose();
      await s.notifications.fermer();
      await gdb.fermer();
      if (racine.existsSync()) await racine.delete(recursive: true);
    });

    test('une note du mois produit un PDF par élève actif et un PDF de la classe', () async {
      await note('BARRY', matiereCollege, 12, 1400);
      await note('DIALLO', matiereCollege, 12, 1000);
      await auto.vider();

      final d = dossier('8e_A', 'Mensuel_Decembre');
      final noms = fichiers(d)..sort();
      expect(noms.length, 3, reason: noms.join(', '));
      expect(noms, contains('00_Classe_entiere.pdf'));
      expect(noms.any((n) => n.startsWith('BARRY_Test_2026-0001')), isTrue, reason: noms.join(', '));
      expect(noms.any((n) => n.startsWith('DIALLO_Test_2026-0002')), isTrue);
      expect(noms.any((n) => n.contains('SOW')), isFalse, reason: 'élève parti : pas de bulletin');
      for (final n in noms) {
        final octets = File(p.join(d.path, n)).readAsBytesSync();
        expect(String.fromCharCodes(octets.take(5)), '%PDF-', reason: n);
      }
      expect(noms.where((n) => n.endsWith('.tmp')), isEmpty);

      final r = auto.dernierRapport!;
      expect(r.ok, isTrue, reason: r.erreurs.join('; '));
      expect(r.bulletins, 2);
      expect(r.fichiers, 3);
      expect(r.descriptions.single, contains('8e A'));
      // Décembre n'est pas le dernier mois du trimestre du collège (T1 va
      // jusqu'en janvier) : pas de bulletin trimestriel.
      expect(dossier('8e_A', 'Trimestre_1').existsSync(), isFalse);
    });

    test('une composition produit aussi le bulletin du trimestre', () async {
      await s.evaluations.enregistrerLot(evalComposition, {
        insc['BARRY']!: Saisie.valeur(1500),
        insc['DIALLO']!: Saisie.valeur(1100),
      });
      await auto.vider();
      expect(fichiers(dossier('8e_A', 'Mensuel_Novembre')).length, 3);
      expect(fichiers(dossier('8e_A', 'Trimestre_1')).length, 3);
      expect(dossier('8e_A', 'Annuel').existsSync(), isFalse,
          reason: 'T1 n\'est pas le dernier trimestre du collège');
    });

    test('le dernier mois de l\'année produit le bulletin annuel', () async {
      await note('BARRY', matiereCollege, 6, 1200);
      await auto.vider();
      expect(fichiers(dossier('8e_A', 'Mensuel_Juin')), isNotEmpty);
      expect(fichiers(dossier('8e_A', 'Trimestre_2')), isNotEmpty);
      expect(fichiers(dossier('8e_A', 'Annuel')), isNotEmpty);
    });

    test('primaire : décembre est la fin du trimestre 1', () async {
      await note('CAMARA', matierePrimaire, 12, 1300);
      await auto.vider();
      expect(fichiers(dossier('3e_A', 'Mensuel_Decembre')).length, 2);
      expect(fichiers(dossier('3e_A', 'Trimestre_1')).length, 2);
      expect(dossier('8e_A', 'Mensuel_Decembre').existsSync(), isFalse,
          reason: 'seule la classe modifiée est régénérée');
    });

    test('la nouvelle version remplace l\'ancienne (pas de doublons)', () async {
      await note('BARRY', matiereCollege, 12, 1400);
      await auto.vider();
      final d = dossier('8e_A', 'Mensuel_Decembre');
      final avant = fichiers(d)..sort();

      await note('BARRY', matiereCollege, 12, 600);
      await auto.vider();
      final apres = fichiers(d)..sort();
      expect(apres, avant);
      expect(apres.any((n) => RegExp(r'_\d+\.pdf$').hasMatch(n) && n.contains('_2.pdf')), isFalse);
    });

    test('plusieurs saisies rapprochées : une seule génération', () async {
      var notifications = 0;
      auto.addListener(() => notifications++);
      await note('BARRY', matiereCollege, 12, 1400);
      await note('DIALLO', matiereCollege, 12, 1000);
      await note('BARRY', matiereCollege, 10, 900);
      await auto.vider();
      // Un lot = deux notifications (début, fin), même pour deux mois.
      expect(notifications, 2);
      expect(auto.dernierRapport!.descriptions.length, 2, reason: 'décembre et octobre');
    });

    test('désactivée : aucun fichier', () async {
      await auto.definirActif(false);
      expect(await auto.estActif(), isFalse);
      await note('BARRY', matiereCollege, 12, 1400);
      await auto.vider();
      expect(Directory(p.join(racine.path, 'Bulletins')).existsSync(), isFalse);
      expect(auto.dernierRapport, isNull);

      await auto.definirActif(true);
      await note('BARRY', matiereCollege, 12, 1400);
      await auto.vider();
      expect(fichiers(dossier('8e_A', 'Mensuel_Decembre')), isNotEmpty);
    });

    test('activée par défaut', () async {
      expect(await auto.estActif(), isTrue);
    });

    test('dossier impossible à écrire : erreur signalée, rien ne plante', () async {
      // Un fichier occupe la place du dossier « Bulletins ».
      File(p.join(racine.path, 'Bulletins')).writeAsStringSync('je suis un fichier');
      await note('BARRY', matiereCollege, 12, 1400);
      await auto.vider();
      final r = auto.dernierRapport!;
      expect(r.ok, isFalse);
      expect(r.erreurs, isNotEmpty);
      expect(r.bulletins, 0);
    });

    test('élève sans classe active : rien à produire', () async {
      final vide = (await s.classes.creer(anneeId: annee, nom: '9e Vide', niveauCode: 9)).id;
      final m = (await s.matieres.ajouter(classeId: vide, nom: 'Maths', coefficient: 100)).id;
      final r = await auto.genererPourChangement(ChangementNotes(vide, 12));
      expect(r.bulletins, 0);
      expect(r.ignorees.single, contains('aucun élève actif'));
      expect(m, greaterThan(0));
    });

    test('classe supprimée entre-temps : ignorée', () async {
      final r = await auto.genererPourChangement(const ChangementNotes(9999, 11));
      expect(r.vide, isTrue);
    });

    test('tout générer : chaque classe suit son calendrier', () async {
      await note('BARRY', matiereCollege, 2, 1400);
      await note('CAMARA', matierePrimaire, 2, 1300);
      await auto.vider();

      final r2 = await auto.genererTout(annee, 't2');
      expect(r2.ok, isTrue, reason: r2.erreurs.join('; '));
      expect(fichiers(dossier('8e_A', 'Trimestre_2')), isNotEmpty);
      expect(fichiers(dossier('3e_A', 'Trimestre_2')), isNotEmpty);

      // Trimestre 3 : seulement le primaire.
      final r3 = await auto.genererTout(annee, 't3');
      expect(fichiers(dossier('3e_A', 'Trimestre_3')), isNotEmpty);
      expect(dossier('8e_A', 'Trimestre_3').existsSync(), isFalse);
      expect(r3.ignorees.single, contains('8e A'));
      expect(auto.dernierRapport, same(r3));
    });
  });
}
