import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/domain/matricule.dart';
import 'package:gesco/domain/recherche.dart';

void main() {
  group('normaliserRecherche', () {
    test('minuscules, sans accents, espaces réduits', () {
      expect(normaliserRecherche('Élodie  DIALLO'), 'elodie diallo');
      expect(normaliserRecherche('  Mamadou Alpha '), 'mamadou alpha');
      expect(normaliserRecherche('FRANÇOIS'), 'francois');
      expect(normaliserRecherche('Zoë Noël'), 'zoe noel');
      expect(normaliserRecherche('Cœur'), 'coeur');
      expect(normaliserRecherche('Aïssatou Bâ'), 'aissatou ba');
      expect(normaliserRecherche(''), '');
      expect(normaliserRecherche('   '), '');
    });

    test('ne touche pas aux chiffres ni aux tirets', () {
      expect(normaliserRecherche('2026-0001'), '2026-0001');
    });
  });

  group('correspondRecherche', () {
    const champs = ['DIALLO', 'Aminata', '2026-0001'];

    test('recherche vide : tout correspond', () {
      expect(correspondRecherche('', champs), isTrue);
      expect(correspondRecherche('   ', champs), isTrue);
    });

    test('par nom, prénom ou matricule, sans accents ni casse', () {
      expect(correspondRecherche('diallo', champs), isTrue);
      expect(correspondRecherche('AMINA', champs), isTrue);
      expect(correspondRecherche('0001', champs), isTrue);
      expect(correspondRecherche('2026-0001', champs), isTrue);
      expect(correspondRecherche('Diallo Aminata', champs), isTrue);
      expect(correspondRecherche('aminata diallo', champs), isTrue);
    });

    test('tous les mots doivent être trouvés', () {
      expect(correspondRecherche('diallo fatou', champs), isFalse);
      expect(correspondRecherche('bah', champs), isFalse);
      expect(correspondRecherche('0002', champs), isFalse);
    });

    test('un accent saisi ou non donne le même résultat', () {
      expect(correspondRecherche('Élodie', ['Elodie', 'BAH']), isTrue);
      expect(correspondRecherche('elodie', ['Élodie', 'BAH']), isTrue);
    });
  });

  group('proposerMatricule', () {
    test('premier matricule', () {
      expect(proposerMatricule('2026', const []), '2026-0001');
      expect(proposerMatricule('', const []), '0001');
    });

    test('numérote après le plus grand numéro existant', () {
      expect(
        proposerMatricule('2026', ['2026-0001', '2026-0007', '2026-0003']),
        '2026-0008',
      );
    });

    test('ne réutilise pas le numéro d\'un élève supprimé', () {
      // 0002 a disparu, mais 0003 existe : on continue à 0004.
      expect(proposerMatricule('2026', ['2026-0001', '2026-0003']), '2026-0004');
    });

    test('ignore les autres préfixes et les formats libres', () {
      expect(
        proposerMatricule('2026', ['2025-0099', 'M001', '2026-ABC', '20260005']),
        '2026-0001',
      );
    });

    test('insensible à la casse et aux espaces', () {
      expect(proposerMatricule('ecole', [' ECOLE-0004 ']), 'ecole-0005');
      expect(proposerMatricule(' 2026 ', ['2026-0002']), '2026-0003');
    });

    test('dépasse 4 chiffres sans planter', () {
      expect(proposerMatricule('2026', ['2026-9999']), '2026-10000');
      expect(proposerMatricule('2026', ['2026-99999999999999999999999']), '2026-0001');
    });

    test('caractères spéciaux dans le préfixe', () {
      expect(proposerMatricule('A.B', ['A.B-0001', 'AxB-0009']), 'A.B-0002');
    });
  });
}
