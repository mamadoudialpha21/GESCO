import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/tableur/classeur.dart';
import 'package:gesco/tableur/xlsx.dart';

void main() {
  group('écriture puis relecture', () {
    test('textes, nombres, dates et cellules vides', () {
      final octets = ecrireClasseur([
        FeuilleEcrite('Données', [
          [
            const CelluleEcrite('Nom', StyleCellule.entete),
            const CelluleEcrite('Note', StyleCellule.entete),
            const CelluleEcrite('Entier', StyleCellule.entete),
            const CelluleEcrite('Date', StyleCellule.entete),
          ],
          [
            const CelluleEcrite('DIALLO Aminata'),
            const CelluleEcrite(14.5, StyleCellule.note),
            const CelluleEcrite(7, StyleCellule.entier),
            CelluleEcrite(DateTime(2011, 3, 5), StyleCellule.date),
          ],
          [
            const CelluleEcrite('Œuvre « Çà » – élève'),
            null,
            const CelluleEcrite(''),
            const CelluleEcrite(null, StyleCellule.saisie),
          ],
        ]),
      ]);
      expect(String.fromCharCodes(octets.take(2)), 'PK');

      final lu = lireClasseur(octets);
      expect(lu.feuilles.length, 1);
      final f = lu.feuilles.single;
      expect(f.nom, 'Données');
      expect(f.cellule(0, 0).texte, 'Nom');
      expect(f.cellule(1, 0).texte, 'DIALLO Aminata');
      expect(f.cellule(1, 1).nombre, 14.5);
      expect(f.cellule(1, 2).nombre, 7);
      expect(f.cellule(1, 3).date, DateTime(2011, 3, 5));
      expect(f.cellule(2, 0).texte, 'Œuvre « Çà » – élève');
      expect(f.cellule(2, 1).vide, isTrue);
      expect(f.cellule(2, 2).vide, isTrue);
      expect(f.cellule(2, 3).vide, isTrue);
    });

    test('plusieurs feuilles, retrouvées par leur nom', () {
      final octets = ecrireClasseur([
        const FeuilleEcrite('Élèves', [
          [CelluleEcrite('a')],
        ]),
        const FeuilleEcrite('Instructions', [
          [CelluleEcrite('b')],
        ]),
      ]);
      final lu = lireClasseur(octets);
      expect([for (final f in lu.feuilles) f.nom], ['Élèves', 'Instructions']);
      expect(lu.feuille('instructions')!.cellule(0, 0).texte, 'b');
      expect(lu.feuille('absente'), isNull);
    });

    test('noms d\'onglets invalides ou en double corrigés', () {
      final octets = ecrireClasseur([
        const FeuilleEcrite('a/b:c*d?e[f]g\\h', [
          [CelluleEcrite('1')],
        ]),
        const FeuilleEcrite('Doublon', [
          [CelluleEcrite('2')],
        ]),
        const FeuilleEcrite('doublon', [
          [CelluleEcrite('3')],
        ]),
        FeuilleEcrite('x' * 50, const [
          [CelluleEcrite('4')],
        ]),
        const FeuilleEcrite('', [
          [CelluleEcrite('5')],
        ]),
      ]);
      final noms = [for (final f in lireClasseur(octets).feuilles) f.nom];
      expect(noms.length, 5);
      expect(noms.toSet().length, 5);
      expect(noms.every((n) => n.isNotEmpty && n.length <= 31), isTrue);
      expect(noms.any((n) => RegExp(r'[\[\]:*?/\\]').hasMatch(n)), isFalse);
    });

    test('largeurs de colonnes acceptées', () {
      final octets = ecrireClasseur([
        const FeuilleEcrite(
          'Largeurs',
          [
            [CelluleEcrite('x'), CelluleEcrite('y')],
          ],
          largeurs: [30, 12],
        ),
      ]);
      expect(lireClasseur(octets).feuilles.single.cellule(0, 1).texte, 'y');
    });

    test('aucune feuille : erreur', () {
      expect(() => ecrireClasseur(const []), throwsArgumentError);
    });
  });

  group('fichiers invalides', () {
    ErreurGesco erreurDe(Uint8List octets) {
      try {
        lireClasseur(octets);
      } on ErreurGesco catch (e) {
        return e;
      }
      fail('Une erreur était attendue.');
    }

    test('texte quelconque', () {
      final e = erreurDe(Uint8List.fromList('ceci n\'est pas Excel'.codeUnits));
      expect(e.message, contains('.xlsx'));
    });

    test('fichier vide', () {
      expect(erreurDe(Uint8List(0)).message, contains('.xlsx'));
    });

    test('archive zip qui n\'est pas un classeur', () {
      // En-tête zip d'un fichier vide.
      final zipVide = Uint8List.fromList([
        0x50, 0x4B, 0x05, 0x06, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
      ]);
      expect(erreurDe(zipVide).message, isNotEmpty);
    });

    test('classeur coupé en cours de route', () {
      final octets = ecrireClasseur([
        const FeuilleEcrite('A', [
          [CelluleEcrite('x')],
        ]),
      ]);
      expect(erreurDe(Uint8List.sublistView(octets, 0, octets.length ~/ 2)).message,
          isNotEmpty);
    });
  });

  group('FeuilleLue', () {
    test('cellules hors de la feuille : vides', () {
      const f = FeuilleLue('F', [
        [Cellule(texte: 'a'), Cellule()],
        [Cellule(), Cellule()],
      ]);
      expect(f.cellule(0, 0).texte, 'a');
      expect(f.cellule(5, 0).vide, isTrue);
      expect(f.cellule(0, 9).vide, isTrue);
      expect(f.cellule(-1, 0).vide, isTrue);
      expect(f.ligneVide(0), isFalse);
      expect(f.ligneVide(1), isTrue);
      expect(f.ligneVide(7), isTrue);
      expect(f.nbLignes, 2);
    });
  });

  test('nomOngletValide', () {
    expect(nomOngletValide('  Notes / 10e A  '), 'Notes 10e A');
    expect(nomOngletValide(''), 'Feuille');
    expect(nomOngletValide('[]'), 'Feuille');
    expect(nomOngletValide('a' * 40).length, 31);
  });
}
