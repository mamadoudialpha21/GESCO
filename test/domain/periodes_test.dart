import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/domain/periodes.dart';

void main() {
  group('calendrier scolaire', () {
    test('9 mois, d\'octobre à juin, regroupés en 3 trimestres', () {
      expect(moisScolaires, [10, 11, 12, 1, 2, 3, 4, 5, 6]);
      expect(trimestres, [1, 2, 3]);
      expect(moisDuTrimestre[1], [10, 11, 12]);
      expect(moisDuTrimestre[2], [1, 2, 3]);
      expect(moisDuTrimestre[3], [4, 5, 6]);
    });

    test('trimestreDuMois', () {
      expect(trimestreDuMois(10), 1);
      expect(trimestreDuMois(12), 1);
      expect(trimestreDuMois(1), 2);
      expect(trimestreDuMois(3), 2);
      expect(trimestreDuMois(4), 3);
      expect(trimestreDuMois(6), 3);
      for (final mois in [7, 8, 9]) {
        expect(trimestreDuMois(mois), isNull, reason: 'mois $mois');
      }
    });

    test('libellés en français', () {
      expect(libelleMois(1), 'Janvier');
      expect(libelleMois(2), 'Février');
      expect(libelleMois(8), 'Août');
      expect(libelleMois(12), 'Décembre');
      expect(libelleTrimestre(2), 'Trimestre 2');
      expect(() => libelleMois(0), throwsArgumentError);
      expect(() => libelleMois(13), throwsArgumentError);
    });
  });

  group('proposerAnneeSuivante', () {
    final octobre2026 = DateTime(2026, 10, 15);

    test('année suivante d\'un libellé existant', () {
      expect(proposerAnneeSuivante('2026-2027', octobre2026), '2027-2028');
      expect(proposerAnneeSuivante('2026/2027', octobre2026), '2027-2028');
      expect(proposerAnneeSuivante(' 2026 - 2027 ', octobre2026), '2027-2028');
    });

    test('sans année précédente : l\'année en cours, rentrée en septembre', () {
      expect(proposerAnneeSuivante(null, DateTime(2026, 10, 15)), '2026-2027');
      expect(proposerAnneeSuivante(null, DateTime(2027, 3, 10)), '2026-2027');
      expect(proposerAnneeSuivante(null, DateTime(2026, 9, 1)), '2026-2027');
      expect(proposerAnneeSuivante(null, DateTime(2026, 8, 31)), '2025-2026');
    });

    test('libellé non reconnu : on retombe sur l\'année en cours', () {
      expect(proposerAnneeSuivante('abc', DateTime(2026, 11, 1)), '2026-2027');
      expect(proposerAnneeSuivante('', DateTime(2026, 11, 1)), '2026-2027');
    });
  });
}
