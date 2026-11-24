import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/import_export/lecture_tableur.dart';
import 'package:gesco/tableur/classeur.dart';

FeuilleLue feuille(List<List<String>> lignes) => FeuilleLue('Feuille', [
      for (final l in lignes) [for (final t in l) Cellule(texte: t)],
    ]);

void main() {
  group('cleColonne', () {
    test('sans accent, majuscule ni ponctuation', () {
      expect(cleColonne('Date de naissance'), 'date de naissance');
      expect(cleColonne('DATE_DE_NAISSANCE'), 'date de naissance');
      expect(cleColonne('  Prénom  '), 'prenom');
      expect(cleColonne('N°'), 'n');
      expect(cleColonne('Nom de l\'élève'), 'nom de l eleve');
      expect(cleColonne(''), '');
    });
  });

  group('TableLue.lettre', () {
    test('lettres de colonnes Excel', () {
      expect(TableLue.lettre(0), 'A');
      expect(TableLue.lettre(25), 'Z');
      expect(TableLue.lettre(26), 'AA');
      expect(TableLue.lettre(27), 'AB');
      expect(TableLue.lettre(701), 'ZZ');
      expect(TableLue.lettre(702), 'AAA');
    });
  });

  group('trouverLigneEntete', () {
    const connus = {'nom', 'prenom', 'sexe'};

    test('première ligne ayant au moins deux titres connus', () {
      final f = feuille([
        ['Groupe Scolaire'],
        ['Liste des élèves'],
        [],
        ['Nom', 'Prénom', 'Sexe'],
        ['BARRY', 'Mamadou', 'M'],
      ]);
      expect(trouverLigneEntete(f, connus), 3);
    });

    test('un seul titre connu ne suffit pas : première ligne non vide', () {
      final f = feuille([
        [],
        ['Nom', 'Autre chose'],
        ['BARRY', 'x'],
      ]);
      expect(trouverLigneEntete(f, connus), 1);
    });

    test('feuille vide : aucune ligne', () {
      expect(trouverLigneEntete(feuille([[], []]), connus), isNull);
      expect(trouverLigneEntete(feuille([]), connus), isNull);
    });

    test('au-delà des 15 premières lignes, l\'en-tête n\'est plus cherché', () {
      final f = feuille([
        for (var i = 0; i < 16; i++) ['x$i'],
        ['Nom', 'Prénom'],
      ]);
      expect(trouverLigneEntete(f, connus), 0);
    });
  });

  group('lireTable', () {
    test('en-têtes, numéros de ligne Excel, lignes vides ignorées', () {
      final f = feuille([
        ['Titre'],
        ['Nom', 'Prénom', ''],
        ['BARRY', 'Mamadou'],
        ['', ''],
        ['DIALLO', 'Aminata', 'extra'],
      ]);
      final t = lireTable(f, indexEntete: 1);
      expect(t.nomFeuille, 'Feuille');
      expect(t.ligneEntete, 2);
      expect(t.entetes, ['Nom', 'Prénom', '']);
      expect(t.nbColonnes, 3);
      expect([for (final l in t.lignes) l.numero], [3, 5]);
      expect(t.lignes.first.cellule(0).texte, 'BARRY');
      expect(t.lignes.first.cellule(9).vide, isTrue, reason: 'hors tableau : cellule vide');
      expect(t.exemples(0), ['BARRY', 'DIALLO']);
      expect(t.exemples(2), ['extra']);
      expect(t.exemples(0, max: 1), ['BARRY']);
    });

    test('la largeur suit la ligne la plus large', () {
      final f = feuille([
        ['A'],
        ['1', '2', '3'],
      ]);
      expect(lireTable(f, indexEntete: 0).nbColonnes, 3);
    });
  });
}
