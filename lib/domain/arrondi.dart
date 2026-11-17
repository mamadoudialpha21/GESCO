/// Outils numériques de GESCO.
///
/// Toutes les notes, coefficients et moyennes sont des entiers en CENTIÈMES
/// (14,75 -> 1475). Il n'y a aucun calcul en virgule flottante : les
/// résultats sont exacts et reproductibles.
library;

/// Division entière arrondie « demi vers le haut » (entiers positifs).
///
/// `divisionArrondie(1, 2) == 1` (0,5 -> 1) ; `divisionArrondie(1, 3) == 0`.
int divisionArrondie(int numerateur, int denominateur) {
  if (denominateur <= 0) {
    throw ArgumentError.value(denominateur, 'denominateur', 'doit être > 0');
  }
  if (numerateur < 0) {
    throw ArgumentError.value(numerateur, 'numerateur', 'doit être >= 0');
  }
  return (2 * numerateur + denominateur) ~/ (2 * denominateur);
}

/// Affiche des centièmes avec une virgule : 1289 -> « 12,89 ».
String formaterCentiemes(int? centiemes, {String vide = '—'}) {
  if (centiemes == null) return vide;
  final signe = centiemes < 0 ? '-' : '';
  final absolu = centiemes.abs();
  final entier = absolu ~/ 100;
  final decimales = (absolu % 100).toString().padLeft(2, '0');
  return '$signe$entier,$decimales';
}

/// Rang en toutes lettres abrégées : 1 -> « 1er », 2 -> « 2e ».
String formaterRang(int rang) => rang == 1 ? '1er' : '${rang}e';

/// Affiche un coefficient sans zéros inutiles : 400 -> « 4 », 250 -> « 2,5 »,
/// 125 -> « 1,25 », 5 -> « 0,05 ».
String formaterCoefficient(int centiemes) {
  final entier = centiemes ~/ 100;
  final reste = centiemes % 100;
  if (reste == 0) return '$entier';
  final decimales = reste.toString().padLeft(2, '0');
  final utiles = decimales.endsWith('0') ? decimales.substring(0, 1) : decimales;
  return '$entier,$utiles';
}

/// Lit un nombre saisi au clavier (« 12 », « 12,5 », « 12.75 ») et le
/// convertit en centièmes. Retourne null si la saisie est invalide ou si la
/// valeur dépasse [maxCentiemes].
///
/// Au plus 2 chiffres avant la virgule et 2 après.
int? analyserDecimal(String texte, {required int maxCentiemes}) {
  final t = texte.trim().replaceAll(',', '.');
  final m = RegExp(r'^(\d{1,2})(?:\.(\d{1,2}))?$').firstMatch(t);
  if (m == null) return null;
  final entier = int.parse(m.group(1)!);
  final partieDecimale = m.group(2) ?? '';
  final decimales =
      partieDecimale.isEmpty ? 0 : int.parse(partieDecimale.padRight(2, '0'));
  final valeur = entier * 100 + decimales;
  if (valeur > maxCentiemes) return null;
  return valeur;
}

/// Note sur 20 saisie au clavier -> centièmes (0 à 2000), ou null.
int? analyserNote(String texte) => analyserDecimal(texte, maxCentiemes: 2000);

/// Coefficient saisi au clavier -> centièmes (strictement positif), ou null.
int? analyserCoefficient(String texte) {
  final valeur = analyserDecimal(texte, maxCentiemes: 9999);
  if (valeur == null || valeur == 0) return null;
  return valeur;
}
