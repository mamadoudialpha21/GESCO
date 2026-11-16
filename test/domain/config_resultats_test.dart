import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/domain/modeles.dart';

void main() {
  const config = ConfigResultats.defaut;

  group('mentions (seuils par défaut)', () {
    test('aucune mention sous 10', () {
      expect(config.mention(0), '');
      expect(config.mention(999), '');
    });

    test('les seuils sont inclus (>=)', () {
      expect(config.mention(1000), 'Passable');
      expect(config.mention(1199), 'Passable');
      expect(config.mention(1200), 'Assez bien');
      expect(config.mention(1399), 'Assez bien');
      expect(config.mention(1400), 'Bien');
      expect(config.mention(1599), 'Bien');
      expect(config.mention(1600), 'Très bien');
      expect(config.mention(1799), 'Très bien');
      expect(config.mention(1800), 'Excellent');
      expect(config.mention(2000), 'Excellent');
    });
  });

  group('décisions', () {
    test('période', () {
      expect(config.decisionPeriode(999), 'Non admis(e)');
      expect(config.decisionPeriode(1000), 'Admis(e)');
    });

    test('année', () {
      expect(config.decisionAnnee(999), 'Redouble');
      expect(config.decisionAnnee(1000), 'Admis(e) en classe supérieure');
    });
  });

  group('niveau (codes couleur)', () {
    test('rouge / orange / vert', () {
      expect(config.niveau(999), NiveauResultat.insuffisant);
      expect(config.niveau(1000), NiveauResultat.moyen);
      expect(config.niveau(1199), NiveauResultat.moyen);
      expect(config.niveau(1200), NiveauResultat.bon);
    });
  });

  group('seuils personnalisés', () {
    test('modifiables sans toucher au code', () {
      const perso = ConfigResultats(
        seuilAdmission: 900,
        seuilBon: 1500,
        mentions: [Palier(1500, 'Satisfaisant'), Palier(1800, 'Brillant')],
        decisionsPeriode: [Palier(0, 'Insuffisant'), Palier(900, 'Suffisant')],
        decisionsAnnee: [
          Palier(0, 'Redouble'),
          Palier(800, 'Rattrapage'),
          Palier(900, 'Passe'),
        ],
      );
      expect(perso.erreurs(), isEmpty);
      expect(perso.mention(1499), '');
      expect(perso.mention(1500), 'Satisfaisant');
      expect(perso.mention(1850), 'Brillant');
      expect(perso.decisionAnnee(850), 'Rattrapage');
      expect(perso.decisionAnnee(900), 'Passe');
      expect(perso.niveau(900), NiveauResultat.moyen);
    });

    test('l\'ordre de saisie des paliers n\'a pas d\'importance', () {
      const desordre = ConfigResultats(
        seuilAdmission: 1000,
        seuilBon: 1200,
        mentions: [Palier(1400, 'Bien'), Palier(1000, 'Passable')],
        decisionsPeriode: [Palier(1000, 'Admis'), Palier(0, 'Refusé')],
        decisionsAnnee: [Palier(1000, 'Admis'), Palier(0, 'Refusé')],
      );
      expect(desordre.mention(1100), 'Passable');
      expect(desordre.mention(1450), 'Bien');
      expect(desordre.decisionPeriode(500), 'Refusé');
    });
  });

  group('validation', () {
    test('la configuration par défaut est valide', () {
      expect(config.erreurs(), isEmpty);
    });

    test('détecte les erreurs', () {
      const mauvaise = ConfigResultats(
        seuilAdmission: 1000,
        seuilBon: 900, // inférieur au seuil d'admission
        mentions: [Palier(1000, 'Passable'), Palier(1000, 'Doublon')],
        decisionsPeriode: [Palier(1000, 'Admis')], // pas de palier à 0
        decisionsAnnee: [Palier(0, ' ')], // libellé vide
      );
      final erreurs = mauvaise.erreurs();
      expect(erreurs.length, 4);
      expect(erreurs.any((e) => e.contains('seuil « bon »')), isTrue);
      expect(erreurs.any((e) => e.contains('en double')), isTrue);
      expect(erreurs.any((e) => e.contains('palier à 0,00')), isTrue);
      expect(erreurs.any((e) => e.contains('libellé vide')), isTrue);
    });
  });

  group('sérialisation JSON (stockage en base)', () {
    test('aller-retour sans perte', () {
      final relue = ConfigResultats.fromJsonString(config.toJsonString());
      expect(relue.toJson(), config.toJson());
      expect(relue.mention(1450), 'Bien');
    });
  });
}
