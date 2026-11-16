import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/domain/dates.dart';

void main() {
  group('analyserDateFr', () {
    test('formats acceptés', () {
      expect(analyserDateFr('05/03/2011'), DateTime(2011, 3, 5));
      expect(analyserDateFr('5/3/2011'), DateTime(2011, 3, 5));
      expect(analyserDateFr('05-03-2011'), DateTime(2011, 3, 5));
      expect(analyserDateFr('05.03.2011'), DateTime(2011, 3, 5));
      expect(analyserDateFr('  31/12/1999 '), DateTime(1999, 12, 31));
      expect(analyserDateFr('01/01/1900'), DateTime(1900, 1, 1));
    });

    test('années bissextiles', () {
      expect(analyserDateFr('29/02/2012'), DateTime(2012, 2, 29));
      expect(analyserDateFr('29/02/2011'), isNull);
      expect(analyserDateFr('29/02/2000'), DateTime(2000, 2, 29));
      expect(analyserDateFr('29/02/1900'), isNull); // 1900 n'est pas bissextile
    });

    test('dates ou formats invalides', () {
      for (final texte in [
        '',
        'abc',
        '31/02/2011',
        '31/04/2011',
        '00/03/2011',
        '05/00/2011',
        '05/13/2011',
        '32/01/2011',
        '5/3/11', // année sur 2 chiffres
        '05/03/2011/1',
        '2011-03-05', // ordre ISO : pas le format de saisie
        '31/12/1899', // avant 1900
        '5 mars 2011',
      ]) {
        expect(analyserDateFr(texte), isNull, reason: 'saisie "$texte"');
      }
    });
  });

  group('format de stockage ISO', () {
    test('dateVersIso', () {
      expect(dateVersIso(DateTime(2011, 3, 5)), '2011-03-05');
      expect(dateVersIso(DateTime(1999, 12, 31)), '1999-12-31');
      expect(dateVersIso(DateTime(1900, 1, 1)), '1900-01-01');
    });

    test('analyserDateIso', () {
      expect(analyserDateIso('2011-03-05'), DateTime(2011, 3, 5));
      expect(analyserDateIso(null), isNull);
      expect(analyserDateIso(''), isNull);
      expect(analyserDateIso('2011-3-5'), isNull);
      expect(analyserDateIso('2011-02-30'), isNull);
      expect(analyserDateIso('05/03/2011'), isNull);
    });

    test('aller-retour saisie -> stockage -> affichage', () {
      final date = analyserDateFr('5/3/2011')!;
      final iso = dateVersIso(date);
      expect(iso, '2011-03-05');
      expect(formaterDateFr(iso), '05/03/2011');
      expect(dateVersFr(date), '05/03/2011');
    });

    test('formaterDateFr : vide si absent ou invalide', () {
      expect(formaterDateFr(null), '');
      expect(formaterDateFr(''), '');
      expect(formaterDateFr('n\'importe quoi'), '');
    });
  });

  group('ageEn', () {
    test('avant, le jour même et après l\'anniversaire', () {
      final naissance = DateTime(2011, 3, 5);
      expect(ageEn(naissance, DateTime(2026, 3, 4)), 14);
      expect(ageEn(naissance, DateTime(2026, 3, 5)), 15);
      expect(ageEn(naissance, DateTime(2026, 3, 6)), 15);
      expect(ageEn(naissance, DateTime(2026, 12, 31)), 15);
      expect(ageEn(naissance, DateTime(2026, 1, 1)), 14);
    });

    test('né un 29 février', () {
      final naissance = DateTime(2012, 2, 29);
      expect(ageEn(naissance, DateTime(2026, 2, 28)), 13);
      expect(ageEn(naissance, DateTime(2026, 3, 1)), 14);
    });
  });
}
