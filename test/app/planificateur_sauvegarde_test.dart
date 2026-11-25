import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/planificateur_sauvegarde.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/sauvegarde/service_sauvegarde.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tmp;
  late String cheminBase;
  late GescoDatabase gdb;
  late ServiceSauvegarde service;
  late DateTime horloge;

  const longtemps = Duration(hours: 1);

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('gesco_planificateur_');
    cheminBase = p.join(tmp.path, 'gesco.db');
    horloge = DateTime(2026, 11, 25, 19, 0, 0);
    gdb = await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: cheminBase);
    service = ServiceSauvegarde(
      Services(gdb, session: Session.sansControle(), iterations: 2),
      fabrique: databaseFactoryFfi,
      cheminBase: cheminBase,
      maintenant: () => horloge,
    );
  });

  tearDown(() async {
    await gdb.fermer();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  PlanificateurSauvegarde planificateur({
    Duration delai = longtemps,
    Duration pause = const Duration(minutes: 15),
  }) =>
      PlanificateurSauvegarde(
        service,
        delaiDemarrage: delai,
        intervalle: longtemps,
        pauseApresEchec: pause,
        maintenant: () => horloge,
      );

  test('rattrapage : la sauvegarde manquée est faite peu après le démarrage de GESCO', () async {
    final pl = planificateur(delai: const Duration(milliseconds: 20));
    var notifications = 0;
    pl.addListener(() => notifications++);
    expect(pl.actif, isFalse);
    pl.demarrer();
    expect(pl.actif, isTrue);
    for (var i = 0; i < 100 && pl.derniere == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    pl.arreter();

    final r = pl.derniere;
    expect(r, isNotNull);
    expect(r!.sauvegarde.type, TypeSauvegarde.automatique);
    expect(File(r.sauvegarde.chemin).existsSync(), isTrue);
    expect(pl.derniereErreur, isNull);
    expect(notifications, 1);
    expect(await service.sauvegardeDue(), isFalse);
    expect(pl.actif, isFalse);
  });

  test('rien à faire quand la sauvegarde du jour existe déjà', () async {
    await service.creerAutomatique();
    final pl = planificateur()..demarrer();
    await pl.verifier();
    pl.arreter();
    expect(pl.derniere, isNull);
    expect(pl.derniereErreur, isNull);
    expect(await service.historique(), hasLength(1));
  });

  test('sauvegarde automatique désactivée : aucune sauvegarde', () async {
    await service.enregistrerConfig((await service.config()).copie(auto: false));
    final pl = planificateur()..demarrer();
    await pl.verifier();
    pl.arreter();
    expect(pl.derniere, isNull);
    expect(await service.historique(), isEmpty);
  });

  test('tant qu\'il n\'est pas démarré (ou une fois arrêté), il ne fait rien', () async {
    final pl = planificateur();
    await pl.verifier();
    expect(await service.historique(), isEmpty);
    pl.demarrer();
    pl.arreter();
    await pl.verifier();
    expect(await service.historique(), isEmpty);
  });

  test('deux vérifications en même temps : une seule sauvegarde', () async {
    final pl = planificateur()..demarrer();
    final a = pl.verifier();
    final b = pl.verifier();
    expect(pl.enCours, isTrue);
    await Future.wait([a, b]);
    pl.arreter();
    expect(pl.enCours, isFalse);
    expect(await service.historique(), hasLength(1));
  });

  test('échec : l\'erreur est conservée, nouvelle tentative seulement après la pause, la réussite l\'efface',
      () async {
    final bloque = File(p.join(tmp.path, 'sauvegardes'))..writeAsStringSync('je bloque le dossier');
    final pl = planificateur()..demarrer();
    var notifications = 0;
    pl.addListener(() => notifications++);

    await pl.verifier();
    expect(pl.derniereErreur, contains('n\'est pas accessible'));
    expect(pl.derniere, isNull);
    expect(notifications, 1);

    // Le problème est réparé, mais la pause de 15 minutes n'est pas écoulée.
    bloque.deleteSync();
    horloge = horloge.add(const Duration(minutes: 10));
    await pl.verifier();
    expect(pl.derniere, isNull);
    expect(pl.derniereErreur, isNotNull);

    horloge = horloge.add(const Duration(minutes: 6));
    await pl.verifier();
    pl.arreter();
    expect(pl.derniere, isNotNull);
    expect(pl.derniereErreur, isNull);
    expect(notifications, 2);
    expect(await service.historique(), hasLength(1));
  });

  test('copie externe impossible : la sauvegarde est faite, l\'avertissement est conservé', () async {
    final fichier = File(p.join(tmp.path, 'fichier'))..writeAsStringSync('x');
    await service.enregistrerConfig(
      (await service.config()).copie(dossierExterne: p.join(fichier.path, 'usb')),
    );
    final pl = planificateur()..demarrer();
    await pl.verifier();
    pl.arreter();
    expect(pl.derniere, isNotNull);
    expect(pl.derniereErreur, isNull);
    expect(pl.dernierAvertissement, contains('La copie vers'));
    expect(pl.derniere!.copieExterne, isNull);
  });
}
