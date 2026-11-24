/// Lecture d'un tableau dans une feuille Excel : repérage de la ligne
/// d'en-tête, puis lignes de données. Commun à tous les imports.
library;

import '../domain/recherche.dart';
import '../tableur/classeur.dart';

/// Texte comparable : sans accent ni majuscule, ponctuation remplacée par des
/// espaces. « Date de naissance » et « DATE_DE_NAISSANCE » donnent le même
/// résultat : `date de naissance`.
String cleColonne(String texte) =>
    normaliserRecherche(texte).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// Une ligne de données du tableau.
class LigneTable {
  const LigneTable(this.numero, this.cellules);

  /// Numéro de la ligne dans Excel (la première ligne du fichier est la 1).
  final int numero;
  final List<Cellule> cellules;

  /// Cellule de la colonne [colonne] (à partir de 0) ; vide si elle n'existe pas.
  Cellule cellule(int colonne) =>
      colonne >= 0 && colonne < cellules.length ? cellules[colonne] : const Cellule();

  bool get vide => cellules.every((c) => c.vide);
}

/// Un tableau lu : titres de colonnes et lignes de données (sans les lignes
/// entièrement vides).
class TableLue {
  const TableLue({
    required this.nomFeuille,
    required this.ligneEntete,
    required this.entetes,
    required this.lignes,
  });

  final String nomFeuille;

  /// Numéro Excel de la ligne d'en-tête (la première ligne est la 1).
  final int ligneEntete;

  /// Titre de chaque colonne ; vide si la cellule d'en-tête est vide.
  final List<String> entetes;
  final List<LigneTable> lignes;

  int get nbColonnes => entetes.length;

  /// Titre de la colonne [colonne] sur une seule ligne (« Devoir 1 (sur 20) ») ;
  /// « Colonne C » si la cellule d'en-tête est vide.
  String titreColonne(int colonne) {
    final t = colonne >= 0 && colonne < entetes.length
        ? entetes[colonne].replaceAll(RegExp(r'\s+'), ' ').trim()
        : '';
    return t.isEmpty ? 'Colonne ${lettre(colonne)}' : t;
  }

  /// Lettre Excel d'une colonne : 0 -> A, 25 -> Z, 26 -> AA.
  static String lettre(int colonne) {
    var n = colonne;
    final sb = StringBuffer();
    do {
      sb.write(String.fromCharCode(65 + n % 26));
      n = n ~/ 26 - 1;
    } while (n >= 0);
    return sb.toString().split('').reversed.join();
  }

  /// Premières valeurs non vides de la colonne, pour reconnaître son contenu.
  List<String> exemples(int colonne, {int max = 3}) {
    final res = <String>[];
    for (final l in lignes) {
      final t = l.cellule(colonne).texte;
      if (t.isNotEmpty) res.add(t);
      if (res.length >= max) break;
    }
    return res;
  }
}

/// Indice (à partir de 0) de la ligne d'en-tête de [feuille] : la première
/// des [maxLignes] premières lignes dont au moins [minimum] cellules ont un
/// titre connu ([titresConnus], sous la forme de [cleColonne]).
/// À défaut, la première ligne non vide ; null si la feuille est vide.
int? trouverLigneEntete(
  FeuilleLue feuille,
  Set<String> titresConnus, {
  int maxLignes = 15,
  int minimum = 2,
}) {
  final limite = feuille.nbLignes < maxLignes ? feuille.nbLignes : maxLignes;
  for (var i = 0; i < limite; i++) {
    var connus = 0;
    for (final c in feuille.lignes[i]) {
      if (titresConnus.contains(cleColonne(c.texte))) connus++;
    }
    if (connus >= minimum) return i;
  }
  for (var i = 0; i < feuille.nbLignes; i++) {
    if (!feuille.ligneVide(i)) return i;
  }
  return null;
}

/// Le tableau de [feuille] dont l'en-tête est à la ligne d'indice
/// [indexEntete]. Les lignes entièrement vides sont ignorées.
TableLue lireTable(FeuilleLue feuille, {required int indexEntete}) {
  var largeur = 0;
  for (var i = indexEntete; i < feuille.nbLignes; i++) {
    final n = feuille.lignes[i].length;
    if (n > largeur) largeur = n;
  }
  final entete = indexEntete < feuille.nbLignes ? feuille.lignes[indexEntete] : const <Cellule>[];
  return TableLue(
    nomFeuille: feuille.nom,
    ligneEntete: indexEntete + 1,
    entetes: [
      for (var c = 0; c < largeur; c++) c < entete.length ? entete[c].texte : '',
    ],
    lignes: [
      for (var i = indexEntete + 1; i < feuille.nbLignes; i++)
        if (!feuille.ligneVide(i)) LigneTable(i + 1, feuille.lignes[i]),
    ],
  );
}
