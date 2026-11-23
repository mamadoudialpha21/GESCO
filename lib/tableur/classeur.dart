/// Représentation simple d'un classeur Excel, indépendante de la bibliothèque
/// qui lit et écrit les fichiers .xlsx (voir `xlsx.dart`).
///
/// Tout le reste de l'application (import, export) ne manipule que ces classes :
/// elles se testent sans fichier.
library;

/// Contenu d'une cellule lue.
class Cellule {
  const Cellule({this.texte = '', this.nombre, this.date, this.formule = false});

  /// Texte affiché, sans espace superflu ; vide si la cellule est vide.
  final String texte;

  /// Valeur numérique si la cellule contient un nombre.
  final double? nombre;

  /// Date si la cellule est au format date.
  final DateTime? date;

  /// Vrai si la cellule contient une formule (non évaluée).
  final bool formule;

  bool get vide => texte.isEmpty && nombre == null && date == null && !formule;

  @override
  String toString() => 'Cellule($texte)';
}

/// Une feuille lue : [lignes] contient toutes les lignes, la première ligne du
/// fichier étant l'indice 0 (numéro de ligne 1 dans Excel).
class FeuilleLue {
  const FeuilleLue(this.nom, this.lignes);

  final String nom;
  final List<List<Cellule>> lignes;

  int get nbLignes => lignes.length;

  /// Cellule de la ligne [ligne] et de la colonne [colonne] (indices à partir
  /// de 0) ; une cellule vide si elle est hors de la feuille.
  Cellule cellule(int ligne, int colonne) {
    if (ligne < 0 || ligne >= lignes.length) return const Cellule();
    final l = lignes[ligne];
    if (colonne < 0 || colonne >= l.length) return const Cellule();
    return l[colonne];
  }

  /// Vrai si toutes les cellules de la ligne sont vides.
  bool ligneVide(int ligne) =>
      ligne < 0 || ligne >= lignes.length || lignes[ligne].every((c) => c.vide);
}

/// Les feuilles d'un classeur lu.
class ClasseurLu {
  const ClasseurLu(this.feuilles);

  final List<FeuilleLue> feuilles;

  /// La feuille de ce nom (sans tenir compte des majuscules), ou null.
  FeuilleLue? feuille(String nom) {
    final cible = nom.toLowerCase();
    for (final f in feuilles) {
      if (f.nom.toLowerCase() == cible) return f;
    }
    return null;
  }
}

/// Mise en forme d'une cellule écrite.
enum StyleCellule {
  normal,

  /// Titre du document (gros, gras).
  titre,

  /// Ligne d'en-tête d'un tableau : fond foncé, texte blanc, gras.
  entete,

  /// Texte explicatif, en italique gris (retour à la ligne dans la cellule).
  consigne,

  /// Ligne d'information en italique gris, sur une seule ligne : le texte
  /// déborde sur les cellules voisines vides au lieu de rendre la ligne haute.
  discret,

  /// Étiquette d'une information (gras).
  etiquette,

  /// Cellule à remplir (fond jaune clair).
  saisie,

  /// Note ou moyenne : deux décimales, centré.
  note,

  /// Nombre entier, centré.
  entier,

  /// Texte centré.
  centre,

  /// Date au format jour/mois/année.
  date,
}

/// Valeur et mise en forme d'une cellule à écrire. [valeur] : texte, entier,
/// décimal, date ou null (cellule vide).
class CelluleEcrite {
  const CelluleEcrite(this.valeur, [this.style = StyleCellule.normal]);

  final Object? valeur;
  final StyleCellule style;
}

/// Une feuille à écrire.
class FeuilleEcrite {
  const FeuilleEcrite(this.nom, this.lignes, {this.largeurs = const []});

  /// Nom de l'onglet (31 caractères au plus, sans `[ ] : * ? / \`).
  final String nom;
  final List<List<CelluleEcrite?>> lignes;

  /// Largeur des colonnes, en caractères (colonne A en premier).
  final List<double> largeurs;
}

/// Nom d'onglet accepté par Excel : sans caractère interdit, 31 caractères au
/// plus, jamais vide.
String nomOngletValide(String nom) {
  var s = nom.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.length > 31) s = s.substring(0, 31).trim();
  return s.isEmpty ? 'Feuille' : s;
}
