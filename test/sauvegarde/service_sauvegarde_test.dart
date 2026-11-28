import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_securite.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:gesco/sauvegarde/format_sauvegarde.dart';
import 'package:gesco/sauvegarde/service_sauvegarde.dart';
import 'package:gesco/sauvegarde/zip_simple.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher erreurContenant(String texte) => throwsA(
      isA<ErreurGesco>().having((e) => e.message, 'message', contains(texte)),
    );

Uint8List octets(String texte) => Uint8List.fromList(utf8.encode(texte));

ManifesteSauvegarde manifeste(Uint8List base, {int version = 4}) => ManifesteSauvegarde(
      versionSchema: version,
      versionApplication: '0.4.0',
      creeLe: '2026-11-25T19:00:00',
      type: 'manuelle',
      utilisateur: 'Test',
      etablissement: 'Groupe Scolaire Test',
      annee: '2026-2027',
      contenu: const {'eleves': 2},
      sha256: empreinte(base),
      taille: base.length,
    );

void main() {
  sqfliteFfiInit();

  group('archive zip', () {
    test('somme de contrôle CRC-32 : valeur de référence', () {
      expect(crc32(utf8.encode('123456789')), 0xCBF43926);
    });

    test('aller-retour : fichiers stockés et compressés', () {
      final gros = Uint8List.fromList([for (var i = 0; i < 20000; i++) i % 7]);
      final zip = ecrireZip(
        [EntreeZip('lisez-moi.txt', octets('Bonjour é à ç')), EntreeZip('gros.bin', gros)],
        date: DateTime(2026, 11, 25, 19, 0, 0),
        compresser: (e) => e.nom == 'gros.bin',
      );
      expect(zip.length, lessThan(gros.length));
      final lu = lireZip(zip);
      expect([for (final e in lu) e.nom], ['lisez-moi.txt', 'gros.bin']);
      expect(utf8.decode(lu[0].octets), 'Bonjour é à ç');
      expect(lu[1].octets, gros);
    });

    test('un octet modifié, un fichier tronqué ou une autre sorte de fichier sont refusés', () {
      final gros = Uint8List.fromList([for (var i = 0; i < 5000; i++) (i * 31) % 251]);
      final zip = ecrireZip([EntreeZip('a.bin', gros)]);
      final abime = Uint8List.fromList(zip)..[zip.length ~/ 2] ^= 0xFF;
      expect(() => lireZip(abime), throwsA(isA<ErreurGesco>()));
      expect(() => lireZip(Uint8List.sublistView(zip, 0, zip.length - 30)), throwsA(isA<ErreurGesco>()));
      expect(() => lireZip(octets('ceci est un simple fichier texte, pas une archive')),
          throwsA(isA<ErreurGesco>()));
      expect(() => lireZip(Uint8List(5)), throwsA(isA<ErreurGesco>()));
    });
  });

  group('format de sauvegarde', () {
    test('une archive se relit avec son descriptif et sa base', () {
      final base = octets('contenu de la base');
      final lu = lireArchive(construireArchive(base, manifeste(base)));
      expect(lu.base, base);
      expect(lu.manifeste.versionSchema, 4);
      expect(lu.manifeste.etablissement, 'Groupe Scolaire Test');
      expect(lu.manifeste.contenu, {'eleves': 2});
    });

    test('base modifiée après coup : empreinte différente, archive refusée', () {
      final base = octets('contenu de la base');
      final autre = Uint8List.fromList(base)..[0] ^= 1;
      final zip = ecrireZip([
        EntreeZip(nomManifeste, octets(jsonEncode(manifeste(base).toJson()))),
        EntreeZip(nomBaseDansArchive, autre),
      ]);
      expect(() => lireArchive(zip), erreurContenant('empreinte'));
    });

    test('taille différente de celle annoncée : refusée', () {
      final base = octets('contenu de la base');
      final zip = ecrireZip([
        EntreeZip(nomManifeste, octets(jsonEncode(manifeste(base).toJson()))),
        EntreeZip(nomBaseDansArchive, octets('contenu')),
      ]);
      expect(() => lireArchive(zip), erreurContenant('incomplète'));
    });

    test('version du format plus récente et archive sans base : refusées', () {
      final base = octets('contenu de la base');
      final futur = manifeste(base).toJson()..['version_format'] = 2;
      expect(
        () => lireArchive(ecrireZip([
          EntreeZip(nomManifeste, octets(jsonEncode(futur))),
          EntreeZip(nomBaseDansArchive, base),
        ])),
        erreurContenant('plus récente'),
      );
      expect(
        () => lireArchive(ecrireZip([EntreeZip(nomManifeste, octets(jsonEncode(manifeste(base).toJson())))])),
        erreurContenant('pas une sauvegarde GESCO'),
      );
      expect(
        () => lireArchive(ecrireZip([EntreeZip('autre.txt', octets('x'))])),
        erreurContenant('pas une sauvegarde GESCO'),
      );
    });
  });

  group('planification', () {
    test('dernière échéance : l\'heure choisie, aujourd\'hui si elle est passée, sinon hier', () {
      expect(ServiceSauvegarde.derniereEcheance(DateTime(2026, 11, 25, 10), 18, 0), DateTime(2026, 11, 24, 18));
      expect(ServiceSauvegarde.derniereEcheance(DateTime(2026, 11, 25, 18), 18, 0), DateTime(2026, 11, 25, 18));
      expect(ServiceSauvegarde.derniereEcheance(DateTime(2026, 11, 25, 23, 59), 18, 30), DateTime(2026, 11, 25, 18, 30));
      expect(ServiceSauvegarde.derniereEcheance(DateTime(2026, 12, 1, 9), 18, 30), DateTime(2026, 11, 30, 18, 30));
      expect(ServiceSauvegarde.derniereEcheance(DateTime(2026, 1, 1, 0, 10), 18, 0), DateTime(2025, 12, 31, 18));
    });
  });

  group('service de sauvegarde', () {
    late Directory tmp;
    late String cheminBase;
    late GescoDatabase gdb;
    late Services admin;
    late ServiceSauvegarde sav;
    late DateTime instant;
    late int annee;
    late int classe;

    Future<void> ouvrir() async {
      gdb = await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: cheminBase);
      admin = Services(gdb, session: Session.sansControle(), iterations: 2);
      sav = ServiceSauvegarde(
        admin,
        fabrique: databaseFactoryFfi,
        cheminBase: cheminBase,
        maintenant: () => instant,
      );
    }

    Future<int> inscrire(String matricule, String nom, String prenom) => admin.eleves.inscrire(
          Eleve(matricule: matricule, nom: nom, prenom: prenom, sexe: 'M'),
          anneeId: annee,
          classeId: classe,
        );

    Future<int> nbEleves() async =>
        (await admin.eleves.lister(annee, classeId: classe)).length;

    ServiceSauvegarde avecDroits(Set<Permission> droits) {
      final session = Session()
        ..ouvrir(Utilisateur(
          id: 1,
          identifiant: 'agent',
          nomComplet: 'Agent',
          role: RoleUtilisateur.consultation,
          actif: true,
          creeLe: '2026-01-01',
          permissionsPersonnalisees: droits,
        ));
      return ServiceSauvegarde(
        Services(gdb, session: session, iterations: 2),
        fabrique: databaseFactoryFfi,
        cheminBase: cheminBase,
        maintenant: () => instant,
      );
    }

    Future<ResultatRestauration> restaurer(
      String chemin, {
      List<EtapeRestauration>? etapes,
      Future<GescoDatabase> Function()? ouvrirBase,
    }) =>
        sav.restaurer(
          chemin,
          fermerBase: () => gdb.fermer(),
          ouvrirBase: ouvrirBase ??
              () async {
                await ouvrir();
                return gdb;
              },
          progression: etapes?.add,
        );

    /// Copie [chemin] en changeant un octet au milieu.
    String abimer(String chemin) {
      final b = File(chemin).readAsBytesSync();
      b[b.length ~/ 2] ^= 0xFF;
      final copie = p.join(tmp.path, 'abimee.zip');
      File(copie).writeAsBytesSync(b);
      return copie;
    }

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('gesco_sauvegarde_');
      cheminBase = p.join(tmp.path, 'gesco.db');
      instant = DateTime(2026, 11, 25, 19, 0, 0);
      await ouvrir();
      await admin.etablissements.enregistrer(const Etablissement(nom: 'Groupe Scolaire Test'));
      annee = (await admin.annees.creer('2026-2027', activer: true)).id;
      classe = (await admin.classes.creer(anneeId: annee, nom: '10e A', niveauCode: 10)).id;
      await inscrire('2026-0001', 'BARRY', 'Mamadou');
      await inscrire('2026-0002', 'DIALLO', 'Aminata');
      await admin.utilisateurs.creer(
        identifiant: 'directrice',
        nomComplet: 'Directrice',
        role: RoleUtilisateur.direction,
        motDePasse: 'Gesco-2026-Test',
        permissions: {Permission.notesSaisir, Permission.sauvegardeGerer},
        doitChanger: false,
      );
    });

    tearDown(() async {
      try {
        await gdb.fermer();
      } catch (_) {
        // Déjà fermée par le test.
      }
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('sauvegarde manuelle : archive créée, relue, contrôlée et inscrite à l\'historique', () async {
      final r = await sav.creerManuelle();
      final s = r.sauvegarde;
      expect(p.dirname(s.chemin), sav.dossierInterne);
      expect(s.nom, 'GESCO_sauvegarde_2026-11-25_190000_manuelle.zip');
      expect(File(s.chemin).existsSync(), isTrue);
      expect(s.type, TypeSauvegarde.manuelle);
      expect(s.verifiee, isTrue);
      expect(s.taille, File(s.chemin).lengthSync());

      final v = await sav.verifierFichier(s.chemin);
      expect(v.problemes, isEmpty);
      expect(v.valide, isTrue);
      final m = v.manifeste!;
      expect(m.versionSchema, GescoDatabase.versionSchema);
      expect(m.etablissement, 'Groupe Scolaire Test');
      expect(m.annee, '2026-2027');
      expect(m.type, 'manuelle');
      expect(m.contenu['eleves'], 2);
      expect(m.contenu, (await sav.resumeActuel()).contenu);

      // L'archive contient la base, le descriptif et la notice.
      final entrees = lireZip(File(s.chemin).readAsBytesSync());
      expect([for (final e in entrees) e.nom], [nomManifeste, nomNotice, nomBaseDansArchive]);
      expect(utf8.decode(entrees[1].octets), contains('SAUVEGARDE GESCO'));

      // Le dossier ne garde ni copie temporaire ni fichier partiel.
      expect([for (final f in Directory(sav.dossierInterne).listSync()) p.basename(f.path)], [s.nom]);

      final h = await sav.historique();
      expect(h, hasLength(1));
      expect(h.single.type, TypeSauvegarde.manuelle);
      expect(h.single.verifiee, isTrue);
      expect(h.single.existe, isTrue);
      expect(
        await admin.gdb.db.query('journal', where: "entite = 'sauvegarde' AND action = 'creation'"),
        hasLength(1),
      );

      // La sauvegarde est une photo : ce qui est saisi ensuite n'y figure pas.
      await inscrire('2026-0003', 'CAMARA', 'Fatou');
      final apres = await sav.verifierFichier(s.chemin);
      expect(apres.base!.contenu['eleves'], 2);
      expect(await nbEleves(), 3);
    });

    test('les comptes et leurs permissions sont dans la sauvegarde, mots de passe hachés', () async {
      final s = (await sav.creerManuelle()).sauvegarde;
      final archive = lireArchive(File(s.chemin).readAsBytesSync());
      final extrait = File(p.join(tmp.path, 'extrait.db'))..writeAsBytesSync(archive.base);
      final db = await databaseFactoryFfi.openDatabase(
        extrait.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      try {
        final u = await db.query('utilisateur', where: "identifiant = 'directrice'");
        expect(u, hasLength(1));
        expect(u.single['permissions'], isNotNull);
        expect(u.single['mot_de_passe_hash'], isNot(contains('Gesco-2026-Test')));
        expect(u.single['role'], 'direction');
      } finally {
        await db.close();
      }
    });

    test('destination externe (clé USB) : la sauvegarde y est écrite ; dossier absent : message clair',
        () async {
      final usb = Directory(p.join(tmp.path, 'usb'));
      final r = await sav.creerManuelle(destination: usb);
      expect(p.dirname(r.sauvegarde.chemin), usb.path);
      expect((await sav.verifierFichier(r.sauvegarde.chemin)).valide, isTrue);

      // Clé retirée : le fichier n'existe plus, l'historique le signale.
      File(r.sauvegarde.chemin).deleteSync();
      final h = await sav.historique();
      expect(h.single.existe, isFalse);

      final fichier = File(p.join(tmp.path, 'fichier'))..writeAsStringSync('x');
      await expectLater(
        sav.creerManuelle(destination: Directory(p.join(fichier.path, 'usb'))),
        erreurContenant('n\'est pas accessible'),
      );
    });

    test('droits : une sauvegarde manuelle exige le droit, la sauvegarde automatique est une action du système',
        () async {
      final sansDroit = avecDroits({Permission.notesSaisir});
      await expectLater(() => sansDroit.creerManuelle(), throwsA(isA<ErreurGesco>()));
      await expectLater(sansDroit.historique(), throwsA(isA<ErreurGesco>()));
      await expectLater(
        sansDroit.enregistrerConfig(const ConfigSauvegarde()),
        throwsA(isA<ErreurGesco>()),
      );

      final avecDroit = avecDroits({Permission.sauvegardeGerer});
      final r = await avecDroit.creerManuelle();
      expect(r.sauvegarde.utilisateur, 'Agent');

      // Personne n'est connecté (démarrage de GESCO) : la sauvegarde automatique se fait quand même.
      final deconnecte = ServiceSauvegarde(
        Services(gdb, session: Session(), iterations: 2),
        fabrique: databaseFactoryFfi,
        cheminBase: cheminBase,
        maintenant: () => instant,
      );
      final auto = await deconnecte.creerAutomatique();
      expect(auto.sauvegarde.type, TypeSauvegarde.automatique);
      expect(auto.sauvegarde.utilisateur, 'Système');
    });

    test('fichier abîmé, tronqué, étranger ou absent : jamais accepté', () async {
      final s = (await sav.creerManuelle()).sauvegarde;
      final octetsBons = File(s.chemin).readAsBytesSync();

      final v1 = await sav.verifierFichier(abimer(s.chemin));
      expect(v1.valide, isFalse);
      expect(v1.problemes, isNotEmpty);

      final tronque = File(p.join(tmp.path, 'tronquee.zip'))
        ..writeAsBytesSync(Uint8List.sublistView(octetsBons, 0, octetsBons.length - 40));
      expect((await sav.verifierFichier(tronque.path)).valide, isFalse);

      final texte = File(p.join(tmp.path, 'note.zip'))
        ..writeAsStringSync('ceci n\'est pas une sauvegarde, juste un texte assez long pour être lu');
      expect((await sav.verifierFichier(texte.path)).valide, isFalse);

      final absent = await sav.verifierFichier(p.join(tmp.path, 'absent.zip'));
      expect(absent.valide, isFalse);
      expect(absent.problemes.single, contains('introuvable'));
    });

    test('base d\'une version plus récente de GESCO : refusée avec explication', () async {
      final s = (await sav.creerManuelle()).sauvegarde;
      final archive = lireArchive(File(s.chemin).readAsBytesSync());
      final futur = File(p.join(tmp.path, 'futur.zip'))
        ..writeAsBytesSync(construireArchive(archive.base, manifeste(archive.base, version: 99)));
      final v = await sav.verifierFichier(futur.path);
      expect(v.valide, isFalse);
      expect(v.problemes.join(' '), contains('plus récente'));
      await expectLater(restaurer(futur.path), erreurContenant('plus récente'));
      expect(await nbEleves(), 2);
    });

    test('vérifier de nouveau une sauvegarde de l\'historique met son état à jour', () async {
      final s = (await sav.creerManuelle()).sauvegarde;
      expect((await sav.verifier(s)).valide, isTrue);
      final b = File(s.chemin).readAsBytesSync();
      b[b.length ~/ 2] ^= 0xFF;
      File(s.chemin).writeAsBytesSync(b);
      expect((await sav.verifier(s)).valide, isFalse);
      expect((await sav.historique()).single.verifiee, isFalse);

      await sav.supprimer((await sav.historique()).single);
      expect(await sav.historique(), isEmpty);
      expect(File(s.chemin).existsSync(), isFalse);
    });

    test('réglages : valeurs par défaut, enregistrement, valeurs refusées', () async {
      var c = await sav.config();
      expect(c.auto, isTrue);
      expect(c.heureTexte, '18:00');
      expect(c.conserver, 7);
      expect(c.dossierExterne, '');

      await sav.enregistrerConfig(c.copie(auto: false, heure: 7, minute: 5, conserver: 3, dossierExterne: ' D:\\Cle '));
      c = await sav.config();
      expect(c.auto, isFalse);
      expect(c.heureTexte, '07:05');
      expect(c.conserver, 3);
      expect(c.dossierExterne, 'D:\\Cle');

      await expectLater(sav.enregistrerConfig(c.copie(heure: 24)), erreurContenant('heure'));
      await expectLater(sav.enregistrerConfig(c.copie(minute: 60)), erreurContenant('heure'));
      await expectLater(sav.enregistrerConfig(c.copie(conserver: 0)), erreurContenant('conserver'));
      await expectLater(sav.enregistrerConfig(c.copie(conserver: 61)), erreurContenant('conserver'));
    });

    test('rotation : seules les 7 dernières sauvegardes automatiques valides sont gardées', () async {
      final manuelle = (await sav.creerManuelle()).sauvegarde;
      final chemins = <String>[];
      for (var i = 0; i < 9; i++) {
        instant = DateTime(2026, 11, 20 + i, 18, 5);
        chemins.add((await sav.creerAutomatique()).sauvegarde.chemin);
      }
      final h = await sav.historique();
      final autos = h.where((s) => s.type == TypeSauvegarde.automatique).toList();
      expect(autos, hasLength(7));
      expect(File(chemins[0]).existsSync(), isFalse);
      expect(File(chemins[1]).existsSync(), isFalse);
      for (final c in chemins.skip(2)) {
        expect(File(c).existsSync(), isTrue);
      }
      // Une sauvegarde manuelle n'est jamais supprimée automatiquement.
      expect(File(manuelle.chemin).existsSync(), isTrue);
      expect(h.where((s) => s.type == TypeSauvegarde.manuelle), hasLength(1));
    });

    test('copie sur disque externe : écrite et contrôlée, limitée au nombre à conserver ; clé absente : avertissement',
        () async {
      final usb = Directory(p.join(tmp.path, 'usb'));
      await sav.enregistrerConfig((await sav.config()).copie(dossierExterne: usb.path, conserver: 2));
      for (var i = 0; i < 3; i++) {
        instant = DateTime(2026, 11, 20 + i, 18, 5);
        final r = await sav.creerAutomatique();
        expect(r.avertissement, isNull);
        expect(p.dirname(r.copieExterne!), usb.path);
        expect((await sav.verifierFichier(r.copieExterne!)).valide, isTrue);
      }
      expect(usb.listSync().whereType<File>(), hasLength(2));
      expect((await sav.historique()).where((s) => s.type == TypeSauvegarde.automatique), hasLength(2));

      final fichier = File(p.join(tmp.path, 'fichier'))..writeAsStringSync('x');
      await sav.enregistrerConfig((await sav.config()).copie(dossierExterne: p.join(fichier.path, 'usb')));
      instant = DateTime(2026, 11, 24, 18, 5);
      final r = await sav.creerAutomatique();
      expect(r.copieExterne, isNull);
      expect(r.avertissement, contains('La copie vers'));
      expect((await sav.verifierFichier(r.sauvegarde.chemin)).valide, isTrue);
    });

    test('sauvegarde automatique due : chaque jour à l\'heure choisie, et rattrapée au démarrage', () async {
      // Rien n'a encore été sauvegardé.
      expect(await sav.sauvegardeDue(), isTrue);
      expect(await sav.executerSiDue(), isNotNull);
      expect(await sav.sauvegardeDue(), isFalse);
      expect(await sav.executerSiDue(), isNull);

      // Le lendemain avant 18 h : la sauvegarde de la veille (19 h) suffit encore.
      instant = DateTime(2026, 11, 26, 17, 59);
      expect(await sav.sauvegardeDue(), isFalse);
      // À 18 h : l'échéance du jour est passée.
      instant = DateTime(2026, 11, 26, 18, 0);
      expect(await sav.sauvegardeDue(), isTrue);
      expect(await sav.executerSiDue(), isNotNull);
      expect(await sav.sauvegardeDue(), isFalse);

      // Ordinateur éteint trois jours : une seule sauvegarde de rattrapage au démarrage.
      instant = DateTime(2026, 11, 29, 9, 0);
      expect(await sav.sauvegardeDue(), isTrue);
      final avant = (await sav.historique()).length;
      expect(await sav.executerSiDue(), isNotNull);
      instant = DateTime(2026, 11, 29, 9, 1);
      expect(await sav.executerSiDue(), isNull);
      expect((await sav.historique()).length, avant + 1);

      // Désactivée : jamais due.
      await sav.enregistrerConfig((await sav.config()).copie(auto: false));
      instant = DateTime(2026, 12, 5, 9, 0);
      expect(await sav.sauvegardeDue(), isFalse);
      expect(await sav.executerSiDue(), isNull);
    });

    test('restauration : les données reviennent, les données d\'avant sont sauvegardées, le journal en garde la trace',
        () async {
      final a = (await sav.creerManuelle()).sauvegarde; // 2 élèves
      await inscrire('2026-0003', 'CAMARA', 'Fatou');
      expect(await nbEleves(), 3);
      instant = instant.add(const Duration(hours: 2));

      final apercu = await sav.preparerRestauration(a.chemin);
      expect(apercu.possible, isTrue);
      expect(apercu.verification.manifeste!.contenu['eleves'], 2);
      expect(apercu.actuelle.contenu['eleves'], 3);

      final etapes = <EtapeRestauration>[];
      final r = await restaurer(a.chemin, etapes: etapes);
      expect(r.reussie, isTrue, reason: r.message);
      expect(etapes, [
        EtapeRestauration.verification,
        EtapeRestauration.securite,
        EtapeRestauration.remplacement,
        EtapeRestauration.reouverture,
        EtapeRestauration.controle,
        EtapeRestauration.termine,
      ]);
      expect(await nbEleves(), 2);
      expect(await gdb.verifierIntegrite(), isEmpty);

      // Les données d'avant restent disponibles dans la sauvegarde de sécurité.
      final securite = r.securite!;
      expect(securite.type, TypeSauvegarde.securite);
      expect(File(securite.chemin).existsSync(), isTrue);
      final v = await sav.verifierFichier(securite.chemin);
      expect(v.valide, isTrue);
      expect(v.manifeste!.contenu['eleves'], 3);
      expect(
        (await sav.historique()).any((s) => s.type == TypeSauvegarde.securite && s.chemin == securite.chemin),
        isTrue,
      );
      expect(await gdb.db.query('journal', where: "action = 'restauration'"), hasLength(1));
      expect(File('$cheminBase.avant-restauration').existsSync(), isFalse);
      expect(File('$cheminBase.restauration').existsSync(), isFalse);

      // Et on peut revenir en arrière en restaurant cette sauvegarde de sécurité.
      final retour = await restaurer(securite.chemin);
      expect(retour.reussie, isTrue, reason: retour.message);
      expect(await nbEleves(), 3);
    });

    test('fichier refusé : rien n\'est modifié et aucune sauvegarde de sécurité n\'est faite', () async {
      final a = (await sav.creerManuelle()).sauvegarde;
      await inscrire('2026-0003', 'CAMARA', 'Fatou');
      await expectLater(restaurer(abimer(a.chemin)), throwsA(isA<ErreurGesco>()));
      await expectLater(restaurer(p.join(tmp.path, 'absent.zip')), erreurContenant('introuvable'));
      expect(await nbEleves(), 3);
      expect(await admin.gdb.db.query('sauvegarde'), hasLength(1));
    });

    test('sauvegarde de sécurité impossible : la restauration est annulée avant tout changement', () async {
      final a = (await sav.creerManuelle()).sauvegarde;
      await inscrire('2026-0003', 'CAMARA', 'Fatou');
      final bloque = File(p.join(tmp.path, 'bloque'))..writeAsStringSync('x');
      final autre = ServiceSauvegarde(
        admin,
        fabrique: databaseFactoryFfi,
        cheminBase: cheminBase,
        dossier: bloque.path,
        maintenant: () => instant,
      );
      await expectLater(
        autre.restaurer(
          a.chemin,
          fermerBase: () async => fail('la base ne doit pas être fermée'),
          ouvrirBase: () async => fail('la base ne doit pas être rouverte'),
        ),
        erreurContenant('sauvegarde de sécurité'),
      );
      expect(await nbEleves(), 3);
      expect(File('$cheminBase.restauration').existsSync(), isFalse);
    });

    test('restauration qui échoue à la réouverture : retour arrière, données d\'avant rouvertes', () async {
      final a = (await sav.creerManuelle()).sauvegarde; // 2 élèves
      await inscrire('2026-0003', 'CAMARA', 'Fatou');
      var appels = 0;
      final r = await restaurer(a.chemin, ouvrirBase: () async {
        appels++;
        if (appels == 1) throw StateError('échec simulé de la réouverture');
        await ouvrir();
        return gdb;
      });
      expect(appels, 2);
      expect(r.reussie, isFalse);
      expect(r.retourArriere, isTrue);
      expect(r.message, contains('remises en place'));
      expect(r.message, contains('échec simulé'));
      expect(await nbEleves(), 3);
      expect(await gdb.verifierIntegrite(), isEmpty);
      expect(File('$cheminBase.avant-restauration').existsSync(), isFalse);
      expect(File('$cheminBase.restauration').existsSync(), isFalse);
      // La sauvegarde de sécurité existe quand même.
      expect(File(r.securite!.chemin).existsSync(), isTrue);
    });

    test('restauration puis réouverture toujours impossible : message précis, données conservées', () async {
      final a = (await sav.creerManuelle()).sauvegarde;
      await inscrire('2026-0003', 'CAMARA', 'Fatou');
      final r = await restaurer(a.chemin, ouvrirBase: () async => throw StateError('disque indisponible'));
      expect(r.reussie, isFalse);
      expect(r.retourArriere, isFalse);
      expect(r.message, contains('disque indisponible'));
      expect(r.message, contains(cheminBase));
      // Le fichier d'avant est revenu à sa place : il se rouvre normalement.
      await ouvrir();
      expect(await nbEleves(), 3);
    });

    test('droit de restaurer : refusé sans la permission', () async {
      final a = (await sav.creerManuelle()).sauvegarde;
      final s = avecDroits({Permission.sauvegardeGerer});
      await expectLater(
        s.restaurer(a.chemin, fermerBase: () async {}, ouvrirBase: () async => gdb),
        throwsA(isA<ErreurGesco>()),
      );
      await expectLater(s.preparerRestauration(a.chemin), throwsA(isA<ErreurGesco>()));
    });

    /// Fabrique une sauvegarde d'une base restée à la version 3 du schéma
    /// (sans la table des absences, ajoutée par la version 4, ni celle des
    /// programmes, ajoutée par la version 5).
    Future<File> sauvegardeVersion3() async {
      final v3 = File(p.join(tmp.path, 'v3.db'));
      await admin.gdb.db.execute("VACUUM INTO '${v3.path}'");
      final db = await databaseFactoryFfi.openDatabase(
        v3.path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await db.execute('DROP INDEX idx_absence_inscription');
      await db.execute('DROP TABLE absence');
      // Les programmes par cycle sont arrivés avec la version 5.
      await db.execute('DROP INDEX idx_programme_annee');
      await db.execute('DROP TABLE programme_matiere');
      await db.setVersion(3);
      await db.close();
      final base = v3.readAsBytesSync();
      final zip = File(p.join(tmp.path, 'v3.zip'))
        ..writeAsBytesSync(construireArchive(base, manifeste(base, version: 3)));
      return zip;
    }

    test('sauvegarde d\'une version plus ancienne : restaurée puis mise à jour, avec copie de précaution',
        () async {
      final zip = await sauvegardeVersion3();
      final apercu = await sav.preparerRestauration(zip.path);
      expect(apercu.possible, isTrue, reason: apercu.verification.problemes.join(' ; '));
      expect(apercu.avertissements.join(' '), contains('plus ancienne'));

      final r = await restaurer(zip.path);
      expect(r.reussie, isTrue, reason: r.message);
      expect(await gdb.version(), GescoDatabase.versionSchema);
      expect(
        await gdb.db.rawQuery("SELECT name FROM sqlite_master WHERE name = 'absence'"),
        isNotEmpty,
      );
      expect(await nbEleves(), 2);
      // La mise à jour de la base a été précédée d'une copie du fichier tel quel.
      final copies = (await sav.historique()).where((s) => s.type == TypeSauvegarde.migration).toList();
      expect(copies, hasLength(1));
    });

    test('mise à jour de la base : copie de précaution avant la migration, aucune pour une base à jour',
        () async {
      bool estCopie(FileSystemEntity f) =>
          f is File && p.basename(f.path).startsWith(GescoDatabase.prefixeAvantMiseAJour);
      final dossier = Directory(sav.dossierInterne);
      expect(!dossier.existsSync() || dossier.listSync().where(estCopie).isEmpty, isTrue);

      await gdb.fermer();
      final db = await databaseFactoryFfi.openDatabase(
        cheminBase,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await db.execute('DROP INDEX idx_absence_inscription');
      await db.execute('DROP TABLE absence');
      // Les programmes par cycle sont arrivés avec la version 5.
      await db.execute('DROP INDEX idx_programme_annee');
      await db.execute('DROP TABLE programme_matiere');
      await db.setVersion(3);
      await db.close();

      await ouvrir();
      expect(await gdb.version(), GescoDatabase.versionSchema);
      expect(await nbEleves(), 2);
      final copies = dossier.listSync().where(estCopie).cast<File>().toList();
      expect(copies, hasLength(1));
      expect(p.basename(copies.single.path), startsWith('avant-mise-a-jour_v3-vers-v4_'));

      // La copie garde l'ancienne version et toutes les données.
      final c = await databaseFactoryFfi.openDatabase(
        copies.single.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      try {
        expect(await c.getVersion(), 3);
        expect(await c.rawQuery('SELECT COUNT(*) AS n FROM eleve'), [
          {'n': 2},
        ]);
      } finally {
        await c.close();
      }

      // Rouvrir une base à jour ne crée aucune copie de plus.
      await gdb.fermer();
      await ouvrir();
      expect(dossier.listSync().where(estCopie), hasLength(1));
    });
  });
}
