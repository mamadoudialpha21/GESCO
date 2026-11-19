/// Barèmes de notation : conversion d'une note sur 10, 40, 100... vers une
/// note sur 20 (et inversement), sans calcul en virgule flottante.
///
/// Les notes sont des entiers en centièmes (14,5 -> 1450). Une note « brute »
/// est exprimée sur son barème ; une note « sur 20 » sert aux moyennes.
library;

import 'arrondi.dart';

/// Barèmes proposés dans les listes (tout autre barème de 1 à 1000 reste
/// possible).
const List<int> baremesUsuels = [10, 20, 40, 100];

/// Barème des matières et des évaluations quand rien d'autre n'est choisi.
const int baremeParDefaut = 20;

/// Plus grand barème accepté.
const int baremeMax = 1000;

/// Vrai si [bareme] est un barème acceptable (1 à 1000).
bool baremeValide(int bareme) => bareme >= 1 && bareme <= baremeMax;

/// Note maximale, en centièmes, d'un barème : 20 -> 2000.
int centiemesMax(int bareme) => bareme * 100;

/// Ramène une note brute (centièmes, sur [bareme]) sur 20 (centièmes),
/// arrondie au centième, demi vers le haut : 7 sur 10 -> 14,00 ; 31 sur 40
/// -> 15,50.
int convertirSur20(int brut, int bareme) {
  if (!baremeValide(bareme)) {
    throw ArgumentError.value(bareme, 'bareme', 'doit être entre 1 et $baremeMax');
  }
  if (brut < 0 || brut > centiemesMax(bareme)) {
    throw ArgumentError.value(brut, 'brut', 'doit être entre 0 et ${centiemesMax(bareme)}');
  }
  return divisionArrondie(brut * 20, bareme);
}

/// Ramène une note sur 20 (centièmes) sur [bareme], arrondie au centième.
int convertirDepuis20(int centiemes20, int bareme) {
  if (!baremeValide(bareme)) {
    throw ArgumentError.value(bareme, 'bareme', 'doit être entre 1 et $baremeMax');
  }
  if (centiemes20 < 0 || centiemes20 > 2000) {
    throw ArgumentError.value(centiemes20, 'centiemes20', 'doit être entre 0 et 2000');
  }
  return divisionArrondie(centiemes20 * bareme, 20);
}

/// Lit une note tapée sur [bareme] (« 7 », « 7,5 », « 31.25 ») et la
/// convertit en centièmes. Null si le texte est invalide, a plus de deux
/// décimales ou dépasse le barème.
int? analyserNoteSurBareme(String texte, int bareme) {
  if (!baremeValide(bareme)) return null;
  final t = texte.trim().replaceAll(',', '.');
  final m = RegExp(r'^(\d{1,4})(?:\.(\d{1,2}))?$').firstMatch(t);
  if (m == null) return null;
  final decimales = m.group(2) ?? '';
  final valeur = int.parse(m.group(1)!) * 100 +
      (decimales.isEmpty ? 0 : int.parse(decimales.padRight(2, '0')));
  if (valeur > centiemesMax(bareme)) return null;
  return valeur;
}

/// « sur 20 » : texte court pour les en-têtes et les messages.
String libelleBareme(int bareme) => 'sur $bareme';
