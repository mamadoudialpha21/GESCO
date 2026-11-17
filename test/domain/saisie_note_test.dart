import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/domain/arrondi.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/saisie_note.dart';

void main() {
  group('lireNoteSaisie', () {
    test('une case vide est « non saisie », pas zéro', () {
      for (final texte in ['', '   ', '\t']) {
        final l = lireNoteSaisie(texte);
        expect(l.estVide, isTrue, reason: '« $texte »');
        expect(l.saisie, isNull);
        expect(l.erreur, isNull);
      }
    });

    test('nombres avec virgule ou point', () {
      expect(lireNoteSaisie('14').saisie!.centiemes, 1400);
      expect(lireNoteSaisie('14,5').saisie!.centiemes, 1450);
      expect(lireNoteSaisie('14.75').saisie!.centiemes, 1475);
      expect(lireNoteSaisie(' 7,05 ').saisie!.centiemes, 705);
      expect(lireNoteSaisie('20').saisie!.centiemes, 2000);
      expect(lireNoteSaisie('0').saisie!.centiemes, 0);
    });

    test('zéro est une vraie note, différente d\'une case vide', () {
      final l = lireNoteSaisie('0');
      expect(l.estValide, isTrue);
      expect(l.saisie!.estNumerique, isTrue);
      expect(l.saisie!.centiemes, 0);
    });

    test('absent', () {
      for (final texte in ['a', 'A', 'abs', 'ABS', 'Absent', 'absente']) {
        final s = lireNoteSaisie(texte).saisie;
        expect(s?.etat, EtatNote.absent, reason: texte);
        expect(s?.centiemes, isNull);
      }
    });

    test('dispensé', () {
      for (final texte in ['d', 'D', 'disp', 'DISP', 'dispensé', 'Dispense']) {
        final s = lireNoteSaisie(texte).saisie;
        expect(s?.etat, EtatNote.dispense, reason: texte);
        expect(s?.centiemes, isNull);
      }
    });

    test('au-dessus de 20 : refusé avec un message clair', () {
      for (final texte in ['21', '20,01', '25', '100']) {
        final l = lireNoteSaisie(texte);
        expect(l.estInvalide, isTrue, reason: texte);
        expect(l.erreur, contains('dépasse 20'));
      }
    });

    test('trop de décimales : refusé', () {
      final l = lireNoteSaisie('14,555');
      expect(l.estInvalide, isTrue);
      expect(l.erreur, contains('décimales'));
    });

    test('texte quelconque et nombres négatifs : refusés', () {
      for (final texte in ['abc', '-3', '12a', '1,2,3', '12 5', 'x']) {
        final l = lireNoteSaisie(texte);
        expect(l.estInvalide, isTrue, reason: texte);
        expect(l.erreur, contains('n\'est pas une note valide'));
      }
    });

    test('un nombre invalide ne produit aucune saisie', () {
      expect(lireNoteSaisie('99').saisie, isNull);
      expect(lireNoteSaisie('abc').saisie, isNull);
    });
  });

  group('texteSaisie', () {
    test('affichage de chaque état', () {
      expect(texteSaisie(null), '');
      expect(texteSaisie(const Saisie.valeur(1450)), '14,50');
      expect(texteSaisie(const Saisie.valeur(0)), '0,00');
      expect(texteSaisie(const Saisie.absent()), 'ABS');
      expect(texteSaisie(const Saisie.dispense()), 'DISP');
    });

    test('ce qui est affiché peut être relu sans perte', () {
      for (final v in [0, 5, 100, 1450, 1475, 2000]) {
        final texte = texteSaisie(Saisie.valeur(v));
        expect(lireNoteSaisie(texte).saisie!.centiemes, v, reason: texte);
      }
      expect(lireNoteSaisie(texteSaisie(const Saisie.absent())).saisie!.etat,
          EtatNote.absent);
      expect(lireNoteSaisie(texteSaisie(const Saisie.dispense())).saisie!.etat,
          EtatNote.dispense);
    });
  });

  group('moyenneDe', () {
    test('ignore les valeurs nulles (jamais comptées comme zéro)', () {
      expect(moyenneDe([1000, null, 1400, null]), 1200);
    });

    test('aucune valeur : pas de moyenne', () {
      expect(moyenneDe(const []), isNull);
      expect(moyenneDe([null, null]), isNull);
    });

    test('arrondi demi vers le haut à 2 décimales', () {
      // (1001 + 1000) / 2 = 1000,5 -> 1001
      expect(moyenneDe([1001, 1000]), 1001);
      // (1000 + 1000 + 1001) / 3 = 1000,333 -> 1000
      expect(moyenneDe([1000, 1000, 1001]), 1000);
    });

    test('un vrai zéro compte', () {
      expect(moyenneDe([0, 2000]), 1000);
    });
  });

  test('formaterRang', () {
    expect(formaterRang(1), '1er');
    expect(formaterRang(2), '2e');
    expect(formaterRang(10), '10e');
  });
}
