import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Services s;

  setUp(() async {
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    s = Services(gdb, session: Session.sansControle(), iterations: 2);
  });

  tearDown(() async {
    await s.notifications.fermer();
    await gdb.fermer();
  });

  test('appréciations automatiques : activées par défaut, réglage mémorisé', () async {
    expect(await s.parametres.appreciationsAutomatiques(), isTrue);
    await s.parametres.definirAppreciationsAutomatiques(false);
    expect(await s.parametres.appreciationsAutomatiques(), isFalse);
    await s.parametres.definirAppreciationsAutomatiques(true);
    expect(await s.parametres.appreciationsAutomatiques(), isTrue);
  });

  test('ne modifie pas le réglage des bulletins automatiques', () async {
    await s.parametres.definirAppreciationsAutomatiques(false);
    expect(await s.parametres.bulletinsAutomatiques(), isTrue);
    await s.parametres.definirBulletinsAutomatiques(false);
    await s.parametres.definirAppreciationsAutomatiques(true);
    expect(await s.parametres.bulletinsAutomatiques(), isFalse);
  });
}
