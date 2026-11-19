import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/domain/bareme.dart';
import 'package:gesco/domain/evaluations.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/saisie_note.dart';

void main() {
  group('conversion de barème', () {
    test('une note sur 20 reste inchangée', () {
      expect(convertirSur20(1475, 20), 1475);
      expect(convertirDepuis20(1475, 20), 1475);
    });

    test('sur 10 : 7 -> 14,00 ; 10 -> 20,00 ; 0 -> 0', () {
      expect(convertirSur20(700, 10), 1400);
      expect(convertirSur20(1000, 10), 2000);
      expect(convertirSur20(0, 10), 0);
    });

    test('sur 40 : 31 -> 15,50 ; 40 -> 20,00', () {
      expect(convertirSur20(3100, 40), 1550);
      expect(convertirSur20(4000, 40), 2000);
    });

    test('sur 100 : 67,25 -> 13,45 ; 100 -> 20,00', () {
      expect(convertirSur20(6725, 100), 1345);
      expect(convertirSur20(10000, 100), 2000);
    });

    test('l\'arrondi se fait au centième, demi vers le haut', () {
      // 31,25 / 40 * 20 = 15,625 -> 15,63
      expect(convertirSur20(3125, 40), 1563);
      // 1 / 3 de 20 : barème 3, 1 point -> 6,666... -> 6,67
      expect(convertirSur20(100, 3), 667);
    });

    test('conversion inverse : 15,50 sur 20 -> 31 sur 40', () {
      expect(convertirDepuis20(1550, 40), 3100);
      expect(convertirDepuis20(1400, 10), 700);
      expect(convertirDepuis20(2000, 100), 10000);
    });

    test('les valeurs hors barème sont refusées', () {
      expect(() => convertirSur20(1001, 10), throwsArgumentError);
      expect(() => convertirSur20(-1, 10), throwsArgumentError);
      expect(() => convertirSur20(100, 0), throwsArgumentError);
      expect(() => convertirSur20(100, 1001), throwsArgumentError);
      expect(() => convertirDepuis20(2001, 40), throwsArgumentError);
    });

    test('barèmes valides : 1 à 1000', () {
      expect(baremeValide(1), isTrue);
      expect(baremeValide(1000), isTrue);
      expect(baremeValide(0), isFalse);
      expect(baremeValide(1001), isFalse);
      expect(baremesUsuels, [10, 20, 40, 100]);
      expect(centiemesMax(40), 4000);
    });
  });

  group('lecture d\'une note sur un barème', () {
    test('virgule ou point, deux décimales au plus', () {
      expect(analyserNoteSurBareme('7,5', 10), 750);
      expect(analyserNoteSurBareme('31.25', 40), 3125);
      expect(analyserNoteSurBareme(' 100 ', 100), 10000);
      expect(analyserNoteSurBareme('0', 10), 0);
    });

    test('refuse ce qui dépasse le barème ou n\'est pas un nombre', () {
      expect(analyserNoteSurBareme('10,01', 10), isNull);
      expect(analyserNoteSurBareme('41', 40), isNull);
      expect(analyserNoteSurBareme('abc', 40), isNull);
      expect(analyserNoteSurBareme('1,234', 40), isNull);
      expect(analyserNoteSurBareme('-1', 40), isNull);
      expect(analyserNoteSurBareme('5', 0), isNull);
    });
  });

  group('Saisie sur un barème', () {
    test('garde la note d\'origine et la note sur 20', () {
      const s = Saisie.surBareme(3100, 40);
      expect(s.brut, 3100);
      expect(s.bareme, 40);
      expect(s.centiemes, 1550);
      expect(s.centiemesSaisis, 3100);
      expect(s.estNumerique, isTrue);
    });

    test('une note sur 20 n\'a ni note d\'origine ni barème', () {
      const s = Saisie.valeur(1450);
      expect(s.brut, isNull);
      expect(s.bareme, isNull);
      expect(s.centiemesSaisis, 1450);
    });

    test('égalité : la note d\'origine compte', () {
      // 29,99 et 30,00 sur 40 donnent la même note sur 20 (15,00).
      expect(const Saisie.surBareme(2999, 40).centiemes, 1500);
      expect(const Saisie.surBareme(3000, 40).centiemes, 1500);
      expect(const Saisie.surBareme(2999, 40) == const Saisie.surBareme(3000, 40), isFalse);
      expect(const Saisie.surBareme(3000, 40) == const Saisie.surBareme(3000, 40), isTrue);
      expect(const Saisie.absent() == const Saisie.absent(), isTrue);
      expect(const Saisie.absent() == const Saisie.dispense(), isFalse);
      expect(const Saisie.valeur(1500) == const Saisie.surBareme(3000, 40), isFalse);
    });

    test('lireNoteSaisie produit la bonne sorte de saisie', () {
      expect(lireNoteSaisie('14,5').saisie, const Saisie.valeur(1450));
      expect(lireNoteSaisie('31', bareme: 40).saisie, const Saisie.surBareme(3100, 40));
      expect(lireNoteSaisie('abs', bareme: 40).saisie, const Saisie.absent());
      expect(lireNoteSaisie('D', bareme: 10).saisie, const Saisie.dispense());
      expect(lireNoteSaisie('', bareme: 40).estVide, isTrue);
    });

    test('messages d\'erreur adaptés au barème', () {
      final trop = lireNoteSaisie('45', bareme: 40);
      expect(trop.estInvalide, isTrue);
      expect(trop.erreur, contains('dépasse 40'));
      expect(lireNoteSaisie('21').erreur, contains('dépasse 20'));
      expect(lireNoteSaisie('x', bareme: 100).erreur, contains('de 0 à 100'));
      expect(lireNoteSaisie('1,234', bareme: 10).erreur, contains('décimales'));
    });

    test('texteSaisie affiche la note telle qu\'elle a été tapée', () {
      expect(texteSaisie(const Saisie.surBareme(3100, 40)), '31,00');
      expect(texteSaisie(const Saisie.valeur(1450)), '14,50');
      expect(texteSaisie(const Saisie.absent()), 'ABS');
      expect(texteSaisie(null), '');
    });
  });

  group('note du mois d\'après les évaluations', () {
    NoteEvaluee n(int centiemes, int coef) => NoteEvaluee(Saisie.valeur(centiemes), coef);

    test('moyenne pondérée par les coefficients', () {
      // (10 x 1 + 16 x 2) / 3 = 14
      expect(noteDuMois([n(1000, 100), n(1600, 200)]), const Saisie.valeur(1400));
    });

    test('arrondi au centième, demi vers le haut', () {
      // (10 + 11) / 2 = 10,50 ; (10 + 10,01 + 10,01) / 3 = 10,0067 -> 10,01
      expect(noteDuMois([n(1000, 100), n(1100, 100)]), const Saisie.valeur(1050));
      expect(
        noteDuMois([n(1000, 100), n(1001, 100), n(1001, 100)]),
        const Saisie.valeur(1001),
      );
      // (10 + 10,01) / 2 = 10,005 -> 10,01
      expect(noteDuMois([n(1000, 100), n(1001, 100)]), const Saisie.valeur(1001));
    });

    test('un zéro est une vraie note', () {
      expect(noteDuMois([n(0, 100), n(1000, 100)]), const Saisie.valeur(500));
    });

    test('absent et dispensé sont ignorés, pas comptés zéro', () {
      expect(
        noteDuMois([n(1200, 100), const NoteEvaluee(Saisie.absent(), 100)]),
        const Saisie.valeur(1200),
      );
      expect(
        noteDuMois([n(1200, 100), const NoteEvaluee(Saisie.dispense(), 300)]),
        const Saisie.valeur(1200),
      );
    });

    test('option : un absent compte pour zéro, avec le coefficient de l\'évaluation', () {
      expect(
        noteDuMois(
          [n(1200, 100), const NoteEvaluee(Saisie.absent(), 100)],
          absenceEgaleZero: true,
        ),
        const Saisie.valeur(600),
      );
      // Un dispensé reste ignoré même avec l'option.
      expect(
        noteDuMois(
          [n(1200, 100), const NoteEvaluee(Saisie.dispense(), 100)],
          absenceEgaleZero: true,
        ),
        const Saisie.valeur(1200),
      );
    });

    test('sans note chiffrée : absent, sinon dispensé, sinon rien', () {
      expect(noteDuMois(const []), isNull);
      expect(
        noteDuMois([const NoteEvaluee(Saisie.absent(), 100)]),
        const Saisie.absent(),
      );
      expect(
        noteDuMois([
          const NoteEvaluee(Saisie.dispense(), 100),
          const NoteEvaluee(Saisie.absent(), 100),
        ]),
        const Saisie.absent(),
      );
      expect(
        noteDuMois([const NoteEvaluee(Saisie.dispense(), 100)]),
        const Saisie.dispense(),
      );
    });

    test('les notes sur un autre barème sont déjà ramenées sur 20', () {
      // 7 sur 10 (14,00) et 15 sur 40 (7,50), coefficients égaux -> 10,75
      expect(
        noteDuMois([
          const NoteEvaluee(Saisie.surBareme(700, 10), 100),
          const NoteEvaluee(Saisie.surBareme(1500, 40), 100),
        ]),
        const Saisie.valeur(1075),
      );
    });
  });
}
