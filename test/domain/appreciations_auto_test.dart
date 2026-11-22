import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/domain/appreciations_auto.dart';

String gen(
  int? moyenne, {
  int? rang,
  bool exAequo = false,
  int effectif = 0,
  int? precedente,
  String sexe = 'M',
  List<String> fortes = const [],
  List<String> faibles = const [],
  int admission = 1000,
  int bon = 1200,
}) =>
    appreciationGenerale(EntreeAppreciation(
      moyenne: moyenne,
      rang: rang,
      exAequo: exAequo,
      effectif: effectif,
      moyennePrecedente: precedente,
      sexe: sexe,
      matieresFortes: fortes,
      matieresFaibles: faibles,
      seuilAdmission: admission,
      seuilBon: bon,
    ));

void main() {
  group('niveau selon la moyenne', () {
    test('sans moyenne : aucune appréciation', () {
      expect(gen(null), '');
      expect(gen(null, rang: 1, effectif: 10, fortes: ['Maths']), '');
    });

    test('chaque palier a sa phrase', () {
      expect(gen(1850), 'Résultats excellents, félicitations.');
      expect(gen(1800), 'Résultats excellents, félicitations.');
      expect(gen(1799), 'Très bons résultats, il faut continuer ainsi.');
      expect(gen(1600), 'Très bons résultats, il faut continuer ainsi.');
      expect(gen(1450), 'Bons résultats, encouragements.');
      expect(gen(1400), 'Bons résultats, encouragements.');
      expect(gen(1399), 'Résultats satisfaisants.');
      expect(gen(1200), 'Résultats satisfaisants.');
      expect(gen(1199), 'Résultats passables : l\'élève peut mieux faire.');
      expect(gen(1000), 'Résultats passables : l\'élève peut mieux faire.');
      expect(gen(999), contains('insuffisants mais proches de la moyenne'));
      expect(gen(800), contains('insuffisants mais proches de la moyenne'));
      expect(gen(799), contains('nettement renforcé'));
      expect(gen(500), contains('nettement renforcé'));
      expect(gen(499), contains('très faibles'));
      expect(gen(0), contains('très faibles'));
    });

    test('les seuils de l\'année sont respectés', () {
      // Admission à 12 : 11 est insuffisant (proche de la moyenne), pas passable.
      expect(gen(1100, admission: 1200, bon: 1300), contains('insuffisants mais proches'));
      expect(gen(1250, admission: 1200, bon: 1300), contains('passables'));
      expect(gen(1350, admission: 1200, bon: 1300), 'Résultats satisfaisants.');
    });
  });

  group('classement', () {
    test('premier / première, avec ex æquo', () {
      expect(gen(1700, rang: 1, effectif: 10),
          'Très bons résultats, il faut continuer ainsi. Premier de la classe.');
      expect(gen(1700, rang: 1, effectif: 10, sexe: 'F'), endsWith('Première de la classe.'));
      expect(gen(1700, rang: 1, effectif: 10, exAequo: true), endsWith('Premier ex æquo de la classe.'));
      expect(gen(1700, rang: 1, effectif: 10, sexe: 'F', exAequo: true),
          endsWith('Première ex æquo de la classe.'));
    });

    test('trois premiers et meilleurs de la classe', () {
      expect(gen(1500, rang: 3, effectif: 12), endsWith('Se classe parmi les trois premiers de la classe.'));
      // Pas de « trois premiers » dans une classe de 5 élèves.
      expect(gen(1500, rang: 2, effectif: 5), 'Bons résultats, encouragements.');
      // Quart de 20 élèves = 5 : les rangs 4 et 5 sont « parmi les meilleurs ».
      expect(gen(1500, rang: 4, effectif: 20), endsWith('Se classe parmi les meilleurs de la classe.'));
      expect(gen(1500, rang: 5, effectif: 20), endsWith('Se classe parmi les meilleurs de la classe.'));
      expect(gen(1500, rang: 6, effectif: 20), 'Bons résultats, encouragements.');
    });

    test('dernier quart : seulement si la moyenne n\'est pas bonne', () {
      expect(gen(900, rang: 11, effectif: 12),
          endsWith('Se classe dans le dernier quart de la classe : des efforts sont attendus.'));
      expect(gen(1300, rang: 12, effectif: 12), 'Résultats satisfaisants.');
    });

    test('pas de félicitations de rang sans la moyenne d\'admission', () {
      expect(gen(900, rang: 1, effectif: 10), isNot(contains('Premier')));
      expect(gen(900, rang: 2, effectif: 10), isNot(contains('premiers')));
    });

    test('classe trop petite : aucun commentaire de rang', () {
      expect(gen(1700, rang: 1, effectif: 3), 'Très bons résultats, il faut continuer ainsi.');
      expect(gen(1700, rang: 1, effectif: 0), 'Très bons résultats, il faut continuer ainsi.');
    });
  });

  group('évolution', () {
    test('progrès, baisse et stabilité', () {
      expect(gen(1500, precedente: 1350), endsWith('En progrès par rapport à la période précédente.'));
      expect(gen(1300, precedente: 1500),
          endsWith('Léger fléchissement par rapport à la période précédente.'));
      expect(gen(900, precedente: 1100),
          endsWith('En baisse par rapport à la période précédente : il faut se ressaisir.'));
      expect(gen(1500, precedente: 1450), 'Bons résultats, encouragements.');
      expect(gen(1500, precedente: 1550), 'Bons résultats, encouragements.');
      expect(gen(1500), 'Bons résultats, encouragements.');
    });
  });

  group('matières', () {
    test('points forts et matières à renforcer', () {
      expect(gen(1500, fortes: ['Maths', 'Français']),
          'Bons résultats, encouragements. Points forts : Maths et Français.');
      expect(gen(900, faibles: ['Anglais']),
          '${gen(900)} À renforcer : Anglais.');
      expect(gen(1500, fortes: ['Maths'], faibles: ['Anglais']),
          'Bons résultats, encouragements. Points forts : Maths. À renforcer : Anglais.');
      expect(gen(1500, fortes: ['A', 'B', 'C']), contains('Points forts : A, B et C.'));
    });

    test('ordre des éléments : niveau, rang, évolution, matières', () {
      final t = gen(1700,
          rang: 1,
          effectif: 10,
          precedente: 1400,
          fortes: ['Maths'],
          faibles: ['Dessin']);
      expect(
        t,
        'Très bons résultats, il faut continuer ainsi. Premier de la classe. '
        'En progrès par rapport à la période précédente. '
        'Points forts : Maths. À renforcer : Dessin.',
      );
    });
  });

  group('longueur', () {
    test('ne dépasse jamais la limite de saisie, le niveau est conservé', () {
      final longs = [for (var i = 0; i < 2; i++) 'Matière très longue ${'x' * 150}'];
      final t = gen(1700,
          rang: 1, effectif: 10, precedente: 1400, fortes: longs, faibles: longs);
      expect(t.length, lessThanOrEqualTo(longueurMaxAppreciation));
      expect(t, startsWith('Très bons résultats, il faut continuer ainsi.'));
    });

    test('toutes les phrases tiennent dans la limite', () {
      for (var m = 0; m <= 2000; m += 50) {
        final t = gen(m,
            rang: 5,
            effectif: 20,
            precedente: m + 200,
            fortes: ['Mathématiques', 'Physique-Chimie'],
            faibles: ['Histoire-Géographie', 'Éducation civique']);
        expect(t, isNotEmpty, reason: '$m');
        expect(t.length, lessThanOrEqualTo(longueurMaxAppreciation), reason: '$m');
      }
    });
  });

  group('appréciation d\'une matière', () {
    test('sans note : vide', () {
      expect(appreciationMatiere(null), '');
    });

    test('chaque palier', () {
      expect(appreciationMatiere(1900), 'Excellent travail');
      expect(appreciationMatiere(1650), 'Très bon travail');
      expect(appreciationMatiere(1400), 'Bon travail');
      expect(appreciationMatiere(1250), 'Travail satisfaisant');
      expect(appreciationMatiere(1000), 'Passable, peut mieux faire');
      expect(appreciationMatiere(900), 'Insuffisant, proche de la moyenne');
      expect(appreciationMatiere(600), 'Insuffisant, des efforts s\'imposent');
      expect(appreciationMatiere(200), 'Très faible, travail à reprendre');
      expect(appreciationMatiere(0), 'Très faible, travail à reprendre');
    });

    test('longueur compatible avec la colonne d\'un bulletin', () {
      for (var n = 0; n <= 2000; n += 25) {
        final t = appreciationMatiere(n);
        expect(t.length, lessThanOrEqualTo(40), reason: '$n');
        expect(t.length, lessThanOrEqualTo(longueurMaxAppreciationMatiere));
      }
    });

    test('suit les seuils de l\'année', () {
      expect(appreciationMatiere(1100, seuilAdmission: 1200), 'Insuffisant, proche de la moyenne');
      expect(appreciationMatiere(1250, seuilAdmission: 1200, seuilBon: 1300),
          'Passable, peut mieux faire');
    });
  });
}
