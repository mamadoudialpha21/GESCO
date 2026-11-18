import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/securite.dart';

void main() {
  group('PBKDF2-HMAC-SHA256', () {
    // Vecteurs de référence (mot de passe « password », sel « salt », 32 octets).
    String hex(Uint8List o) => o.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    Uint8List octets(String t) => Uint8List.fromList(utf8.encode(t));

    test('1 itération', () {
      expect(
        hex(Hachage.deriver(octets('password'), octets('salt'), 1)),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });

    test('2 itérations', () {
      expect(
        hex(Hachage.deriver(octets('password'), octets('salt'), 2)),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
    });

    test('4096 itérations', () {
      expect(
        hex(Hachage.deriver(octets('password'), octets('salt'), 4096)),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });

    test('refuse un nombre d\'itérations nul', () {
      expect(() => Hachage.deriver(octets('a'), octets('b'), 0), throwsArgumentError);
    });
  });

  group('Hachage des mots de passe', () {
    test('un bon mot de passe est reconnu, un mauvais refusé', () {
      final sel = Hachage.genererSel();
      final hash = Hachage.hacher('Tombolia26', sel, 3);
      expect(Hachage.verifier('Tombolia26', hash: hash, sel: sel, iterations: 3), isTrue);
      expect(Hachage.verifier('tombolia26', hash: hash, sel: sel, iterations: 3), isFalse);
      expect(Hachage.verifier('', hash: hash, sel: sel, iterations: 3), isFalse);
    });

    test('un autre nombre d\'itérations donne une autre empreinte', () {
      final sel = Hachage.genererSel();
      final hash = Hachage.hacher('Tombolia26', sel, 3);
      expect(Hachage.verifier('Tombolia26', hash: hash, sel: sel, iterations: 4), isFalse);
    });

    test('le mot de passe n\'apparaît pas dans l\'empreinte', () {
      final sel = Hachage.genererSel();
      expect(Hachage.hacher('Tombolia26', sel, 2), isNot(contains('Tombolia26')));
    });

    test('deux sels successifs sont différents et font 16 octets', () {
      final a = Hachage.genererSel();
      final b = Hachage.genererSel();
      expect(a, isNot(b));
      expect(base64Decode(a).length, 16);
    });

    test('le même mot de passe avec deux sels donne deux empreintes', () {
      expect(
        Hachage.hacher('Tombolia26', Hachage.genererSel(), 2),
        isNot(Hachage.hacher('Tombolia26', Hachage.genererSel(), 2)),
      );
    });
  });

  group('Code de récupération', () {
    test('a le format XXXX-XXXX-XXXX-XXXX sans caractère ambigu', () {
      for (var i = 0; i < 50; i++) {
        final code = Hachage.genererCodeRecuperation();
        expect(RegExp(r'^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$').hasMatch(code), isTrue, reason: code);
        expect(code.contains(RegExp('[01OI]')), isFalse, reason: code);
      }
    });

    test('deux codes successifs diffèrent', () {
      expect(Hachage.genererCodeRecuperation(), isNot(Hachage.genererCodeRecuperation()));
    });

    test('la saisie est normalisée (casse, tirets, espaces)', () {
      expect(Hachage.normaliserCode('abcd-efgh 2345-jklm'), 'ABCDEFGH2345JKLM');
      expect(Hachage.normaliserCode(' ABCD EFGH '), 'ABCDEFGH');
    });
  });
}
