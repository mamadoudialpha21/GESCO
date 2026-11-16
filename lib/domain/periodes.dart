/// Calendrier scolaire : mois et trimestres.
library;

/// Mois scolaires (numéro du mois civil), dans l'ordre de l'année scolaire.
const List<int> moisScolaires = [10, 11, 12, 1, 2, 3, 4, 5, 6];

/// Numéros des trimestres.
const List<int> trimestres = [1, 2, 3];

/// Mois qui composent chaque trimestre.
const Map<int, List<int>> moisDuTrimestre = {
  1: [10, 11, 12],
  2: [1, 2, 3],
  3: [4, 5, 6],
};

/// Trimestre (1, 2 ou 3) auquel appartient [mois], ou null s'il est hors
/// de l'année scolaire (juillet, août, septembre).
int? trimestreDuMois(int mois) {
  for (final entree in moisDuTrimestre.entries) {
    if (entree.value.contains(mois)) return entree.key;
  }
  return null;
}

const List<String> _nomsMois = [
  'Janvier',
  'Février',
  'Mars',
  'Avril',
  'Mai',
  'Juin',
  'Juillet',
  'Août',
  'Septembre',
  'Octobre',
  'Novembre',
  'Décembre',
];

/// Nom français d'un mois (1 à 12).
String libelleMois(int mois) {
  if (mois < 1 || mois > 12) {
    throw ArgumentError.value(mois, 'mois', 'doit être entre 1 et 12');
  }
  return _nomsMois[mois - 1];
}

String libelleTrimestre(int trimestre) => 'Trimestre $trimestre';

/// Propose le libellé de la prochaine année scolaire.
///
/// - `proposerAnneeSuivante('2026-2027', ...)` -> « 2027-2028 » ;
/// - sans année précédente (ou libellé non reconnu) : l'année en cours, la
///   rentrée étant supposée en septembre (octobre 2026 -> « 2026-2027 »,
///   mars 2027 -> « 2026-2027 »).
String proposerAnneeSuivante(String? derniere, DateTime maintenant) {
  if (derniere != null) {
    final m = RegExp(r'^\s*(\d{4})\s*[-/]\s*(\d{4})\s*$').firstMatch(derniere);
    if (m != null) {
      final fin = int.parse(m.group(2)!);
      return '$fin-${fin + 1}';
    }
  }
  final debut = maintenant.month >= 9 ? maintenant.year : maintenant.year - 1;
  return '$debut-${debut + 1}';
}
