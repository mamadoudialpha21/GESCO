import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/domain/arrondi.dart';

void main() {
  group('divisionArrondie (demi vers le haut)', () {
    test('cas usuels', () {
      expect(divisionArrondie(1, 2), 1); // 0,5 -> 1
      expect(divisionArrondie(1, 3), 0); // 0,33 -> 0
      expect(divisionArrondie(2, 3), 1); // 0,67 -> 1
      expect(divisionArrondie(3, 2), 2); // 1,5 -> 2
      expect(divisionArrondie(5, 2), 3); // 2,5 -> 3
      expect(divisionArrondie(0, 5), 0);
      expect(divisionArrondie(10, 5), 2); // exact
    });

    test('refuse un dénominateur nul ou négatif', () {
      expect(() => divisionArrondie(1, 0), throwsArgumentError);
      expect(() => divisionArrondie(1, -2), throwsArgumentError);
    });

    test('refuse un numérateur négatif', () {
      expect(() => divisionArrondie(-1, 2), throwsArgumentError);
    });
  });

  group('formaterCentiemes', () {
    test('affiche toujours 2 décimales avec une virgule', () {
      expect(formaterCentiemes(1289), '12,89');
      expect(formaterCentiemes(1250), '12,50');
      expect(formaterCentiemes(5), '0,05');
      expect(formaterCentiemes(0), '0,00');
      expect(formaterCentiemes(2000), '20,00');
    });

    test('valeur absente', () {
      expect(formaterCentiemes(null), '—');
      expect(formaterCentiemes(null, vide: ''), '');
    });
  });

  group('formaterCoefficient', () {
    test('sans zéros inutiles', () {
      expect(formaterCoefficient(400), '4');
      expect(formaterCoefficient(100), '1');
      expect(formaterCoefficient(250), '2,5');
      expect(formaterCoefficient(150), '1,5');
      expect(formaterCoefficient(125), '1,25');
      expect(formaterCoefficient(5), '0,05');
      expect(formaterCoefficient(10), '0,1');
      expect(formaterCoefficient(9999), '99,99');
    });

    test('aller-retour avec la saisie', () {
      for (final c in [1, 5, 10, 100, 125, 150, 250, 400, 1050, 9999]) {
        expect(analyserCoefficient(formaterCoefficient(c)), c, reason: 'coefficient $c');
      }
    });
  });

  group('analyserNote', () {
    test('saisies valides', () {
      expect(analyserNote('12'), 1200);
      expect(analyserNote('12,5'), 1250);
      expect(analyserNote('12.75'), 1275);
      expect(analyserNote('12,05'), 1205);
      expect(analyserNote(' 7 '), 700);
      expect(analyserNote('0'), 0);
      expect(analyserNote('09'), 900);
      expect(analyserNote('20'), 2000);
      expect(analyserNote('20,00'), 2000);
    });

    test('saisies invalides', () {
      for (final texte in [
        '',
        'abc',
        '20,01',
        '21',
        '-1',
        '12,',
        ',5',
        '12,345',
        '1 2',
        '100',
      ]) {
        expect(analyserNote(texte), isNull, reason: 'saisie "$texte"');
      }
    });
  });

  group('analyserCoefficient', () {
    test('valeurs valides', () {
      expect(analyserCoefficient('4'), 400);
      expect(analyserCoefficient('1,5'), 150);
      expect(analyserCoefficient('0,25'), 25);
      expect(analyserCoefficient('99,99'), 9999);
    });

    test('zéro, négatif ou trop grand refusés', () {
      expect(analyserCoefficient('0'), isNull);
      expect(analyserCoefficient('0,00'), isNull);
      expect(analyserCoefficient('-2'), isNull);
      expect(analyserCoefficient('100'), isNull);
      expect(analyserCoefficient('abc'), isNull);
    });
  });
}
