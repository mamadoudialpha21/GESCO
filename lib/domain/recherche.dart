/// Recherche tolérante : sans tenir compte des majuscules ni des accents.
library;

const Map<String, String> _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
  'ç': 'c',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ý': 'y', 'ÿ': 'y',
  'œ': 'oe', 'æ': 'ae',
};

final RegExp _espaces = RegExp(r'\s+');

/// Minuscules, sans accents, espaces multiples réduits à un seul.
/// « Élodie  DIALLO » -> « elodie diallo ».
String normaliserRecherche(String texte) {
  final tampon = StringBuffer();
  for (final rune in texte.toLowerCase().runes) {
    final caractere = String.fromCharCode(rune);
    tampon.write(_accents[caractere] ?? caractere);
  }
  return tampon.toString().replaceAll(_espaces, ' ').trim();
}

/// Vrai si **chaque mot** de [recherche] apparaît dans l'un des [champs]
/// (nom, prénom, matricule...). Une recherche vide correspond à tout.
bool correspondRecherche(String recherche, Iterable<String> champs) {
  final mots = [
    for (final mot in normaliserRecherche(recherche).split(' '))
      if (mot.isNotEmpty) mot,
  ];
  if (mots.isEmpty) return true;
  final base = normaliserRecherche(champs.join(' '));
  return mots.every((mot) => base.contains(mot));
}
