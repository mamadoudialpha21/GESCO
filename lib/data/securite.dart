import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Hachage des mots de passe : PBKDF2-HMAC-SHA256 avec sel aléatoire.
///
/// Le mot de passe n'est jamais enregistré : seuls le sel, le nombre
/// d'itérations et l'empreinte le sont, ce qui permet d'augmenter le nombre
/// d'itérations plus tard sans invalider les comptes existants.
class Hachage {
  const Hachage._();

  /// Nombre d'itérations pour les nouveaux mots de passe.
  static const int iterationsParDefaut = 100000;

  static const String _alphabetCode = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static final Random _hasard = Random.secure();

  /// Sel aléatoire de 16 octets, en base 64.
  static String genererSel([Random? hasard]) {
    final r = hasard ?? _hasard;
    return base64Encode([for (var i = 0; i < 16; i++) r.nextInt(256)]);
  }

  /// Code de récupération lisible : 16 caractères sans ambiguïté (ni 0/O ni
  /// 1/I), par groupes de 4 (XXXX-XXXX-XXXX-XXXX).
  static String genererCodeRecuperation([Random? hasard]) {
    final r = hasard ?? _hasard;
    final lettres = [
      for (var i = 0; i < 16; i++) _alphabetCode[r.nextInt(_alphabetCode.length)],
    ];
    return [
      for (var g = 0; g < 4; g++) lettres.sublist(g * 4, g * 4 + 4).join(),
    ].join('-');
  }

  /// Met un code saisi à la main sous sa forme canonique (majuscules, sans
  /// tirets ni espaces).
  static String normaliserCode(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// PBKDF2-HMAC-SHA256, 32 octets.
  static Uint8List deriver(Uint8List motDePasse, Uint8List sel, int iterations) {
    if (iterations < 1) {
      throw ArgumentError.value(iterations, 'iterations', 'doit être positif');
    }
    final hmac = Hmac(sha256, motDePasse);
    final bloc = Uint8List(sel.length + 4)..setAll(0, sel);
    bloc[sel.length + 3] = 1;
    var u = Uint8List.fromList(hmac.convert(bloc).bytes);
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    return t;
  }

  /// Empreinte d'un mot de passe, en base 64.
  static String hacher(String motDePasse, String sel, int iterations) =>
      base64Encode(
        deriver(
          Uint8List.fromList(utf8.encode(motDePasse)),
          Uint8List.fromList(base64Decode(sel)),
          iterations,
        ),
      );

  /// Vrai si [motDePasse] correspond à l'empreinte. Comparaison en temps
  /// constant.
  static bool verifier(
    String motDePasse, {
    required String hash,
    required String sel,
    required int iterations,
  }) {
    final calcule = hacher(motDePasse, sel, iterations);
    if (calcule.length != hash.length) return false;
    var difference = 0;
    for (var i = 0; i < calcule.length; i++) {
      difference |= calcule.codeUnitAt(i) ^ hash.codeUnitAt(i);
    }
    return difference == 0;
  }
}
