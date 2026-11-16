/// Dates de naissance : saisie « JJ/MM/AAAA », stockage « AAAA-MM-JJ ».
library;

final RegExp _motifFr = RegExp(r'^\s*(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})\s*$');
final RegExp _motifIso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Construit une date en refusant celles qui n'existent pas (31/02, 29/02 d'une
/// année non bissextile...) ou qui sont antérieures à 1900.
DateTime? _dateValide(int annee, int mois, int jour) {
  if (annee < 1900 || mois < 1 || mois > 12 || jour < 1) return null;
  final date = DateTime(annee, mois, jour);
  if (date.year != annee || date.month != mois || date.day != jour) return null;
  return date;
}

/// Lit « 05/03/2011 » (séparateurs « / », « - » ou « . » ; jour et mois sur
/// 1 ou 2 chiffres). Retourne null si le format ou la date est invalide.
DateTime? analyserDateFr(String texte) {
  final m = _motifFr.firstMatch(texte);
  if (m == null) return null;
  return _dateValide(
    int.parse(m.group(3)!),
    int.parse(m.group(2)!),
    int.parse(m.group(1)!),
  );
}

/// Lit « 2011-03-05 ». Retourne null si invalide ou si [iso] est null.
DateTime? analyserDateIso(String? iso) {
  if (iso == null) return null;
  final m = _motifIso.firstMatch(iso);
  if (m == null) return null;
  return _dateValide(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  );
}

String _deuxChiffres(int n) => n.toString().padLeft(2, '0');

/// Date -> « 2011-03-05 » (format de stockage).
String dateVersIso(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${_deuxChiffres(date.month)}-${_deuxChiffres(date.day)}';

/// Date -> « 05/03/2011 » (format d'affichage).
String dateVersFr(DateTime date) =>
    '${_deuxChiffres(date.day)}/${_deuxChiffres(date.month)}/${date.year.toString().padLeft(4, '0')}';

/// « 2011-03-05 » -> « 05/03/2011 ». Chaîne vide si null ou invalide.
String formaterDateFr(String? iso) {
  final date = analyserDateIso(iso);
  return date == null ? '' : dateVersFr(date);
}

/// Âge en années révolues à la date [reference].
int ageEn(DateTime naissance, DateTime reference) {
  var age = reference.year - naissance.year;
  final anniversairePasse = reference.month > naissance.month ||
      (reference.month == naissance.month && reference.day >= naissance.day);
  if (!anniversairePasse) age--;
  return age;
}
