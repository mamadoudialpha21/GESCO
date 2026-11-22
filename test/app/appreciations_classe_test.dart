import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/appreciations_classe.dart';
import 'package:gesco/app/calcul_classe.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/modeles.dart';

import 'classe_exemple.dart';

/// Huit élèves classés (1 à 8), plus un élève sans note (9) et un parti (10).
/// Maths (1), Français (2), Dessin (3, facultative).
CalculClasse classeDeHuit() => CalculClasse(
      classe: ClasseResume(
        classe: const Classe(id: 1, anneeId: 1, niveau: '10e année', nom: '10e A'),
        nbMatieres: 3,
        nbEleves: 10,
      ),
      eleves: [
        for (var i = 1; i <= 9; i++) eleve(i, 'ELEVE$i'),
        eleve(10, 'PARTI', statut: StatutInscription.depart),
      ],
      matieres: [
        matiere(1, 'Maths'),
        matiere(2, 'Français'),
        matiere(3, 'Dessin', coefficient: 150, facultative: true),
      ],
      config: ConfigResultats.defaut,
      calendrier: Calendrier.defaut,
      saisies: {
        // Novembre (11) ; octobre (10) pour mesurer l'évolution.
        1: {1: {11: note(1900), 10: note(1700)}, 2: {11: note(1900), 10: note(1700)}, 3: {11: note(200)}},
        2: {1: {11: note(1700)}, 2: {11: note(1500)}},
        3: {1: {11: note(1400), 10: note(1800)}, 2: {11: note(1400), 10: note(1800)}},
        4: {1: {11: note(1300)}, 2: {11: note(1100)}},
        5: {1: {11: note(1000)}, 2: {11: note(800)}},
        6: {1: {11: note(800), 10: note(1200)}, 2: {11: note(800), 10: note(1200)}},
        7: {1: {11: note(600)}, 2: {11: note(400)}},
        8: {1: {11: note(300), 10: note(100)}, 2: {11: note(300), 10: note(100)}},
        10: {1: {11: note(1800)}, 2: {11: note(1800)}},
      },
    );

void main() {
  group('étendue précédente', () {
    const cal = Calendrier.defaut;

    test('mois : le mois d\'avant, y compris au passage d\'année', () {
      expect(porteePrecedente(cal, const Portee.mois(10)), isNull);
      expect(porteePrecedente(cal, const Portee.mois(11))!.moisChoisi, 10);
      expect(porteePrecedente(cal, const Portee.mois(1))!.moisChoisi, 12);
      expect(porteePrecedente(cal, const Portee.mois(6))!.moisChoisi, 5);
    });

    test('période : la période d\'avant ; rien pour la première ni pour l\'année', () {
      final t1 = cal.periodes[0];
      final t2 = cal.periodes[1];
      expect(porteePrecedente(cal, Portee.periode(t1)), isNull);
      expect(porteePrecedente(cal, Portee.periode(t2))!.periodeChoisie!.cle, 't1');
      expect(porteePrecedente(cal, const Portee.annee()), isNull);
    });

    test('deux trimestres', () {
      final t2 = Calendrier.deuxTrimestres.periodes[1];
      expect(porteePrecedente(Calendrier.deuxTrimestres, Portee.periode(t2))!.periodeChoisie!.cle,
          't1');
    });
  });

  group('appréciations d\'une classe', () {
    late AppreciationsGenerees g;
    setUp(() => g = genererAppreciations(classeDeHuit(), const Portee.mois(11)));

    test('premier de la classe, progrès et points forts', () {
      // ELEVE1 (id 1, masculin) : 19, rang 1, +2 points sur octobre.
      expect(
        g.generales[1],
        'Résultats excellents, félicitations. Premier de la classe. '
        'En progrès par rapport à la période précédente. '
        'Points forts : Maths et Français.',
      );
    });

    test('les matières facultatives ne sont pas citées', () {
      // Dessin 2/20 pour l'élève 1 : ni « à renforcer », mais appréciation de matière.
      expect(g.generales[1], isNot(contains('Dessin')));
      expect(g.matieres[1]![3], 'Très faible, travail à reprendre');
    });

    test('les trois premiers', () {
      expect(g.generales[2], contains('Se classe parmi les trois premiers de la classe.'));
      expect(g.generales[2], startsWith('Très bons résultats'));
    });

    test('fléchissement et baisse', () {
      expect(g.generales[3], contains('Léger fléchissement par rapport à la période précédente.'));
      expect(g.generales[6], contains('En baisse par rapport à la période précédente'));
    });

    test('milieu de classe : niveau seul', () {
      expect(g.generales[4], 'Résultats satisfaisants.');
      expect(g.generales[5], 'Résultats insuffisants mais proches de la moyenne : quelques efforts suffiront. À renforcer : Français.');
    });

    test('derniers de la classe : dernier quart et matières à renforcer', () {
      expect(g.generales[7],
          contains('Résultats insuffisants : le travail doit être nettement renforcé.'));
      expect(g.generales[7], contains('Se classe dans le dernier quart de la classe'));
      expect(g.generales[7], endsWith('À renforcer : Français et Maths.'));
      expect(g.generales[8], contains('Résultats très faibles'));
      expect(g.generales[8], contains('En progrès par rapport à la période précédente.'));
    });

    test('élève sans note et élève parti : aucune appréciation', () {
      expect(g.generales.containsKey(9), isFalse);
      expect(g.generales.containsKey(10), isFalse);
      expect(g.matieres.containsKey(9), isFalse);
      expect(g.matieres.containsKey(10), isFalse);
    });

    test('appréciation de chaque matière', () {
      expect(g.matieres[1]![1], 'Excellent travail');
      expect(g.matieres[2]![1], 'Très bon travail');
      expect(g.matieres[2]![2], 'Bon travail');
      expect(g.matieres[4]![2], 'Passable, peut mieux faire');
      expect(g.matieres[5]![2], 'Insuffisant, proche de la moyenne');
      expect(g.matieres[7]![2], 'Très faible, travail à reprendre');
      // Pas de note en Dessin : pas d'appréciation de cette matière.
      expect(g.matieres[2]!.containsKey(3), isFalse);
    });

    test('toutes les appréciations tiennent dans les limites de saisie', () {
      for (final t in g.generales.values) {
        expect(t.length, lessThanOrEqualTo(400));
      }
      for (final m in g.matieres.values) {
        for (final t in m.values) {
          expect(t.length, lessThanOrEqualTo(200));
        }
      }
    });
  });

  test('sans période précédente (octobre), aucune phrase d\'évolution', () {
    final g = genererAppreciations(classeDeHuit(), const Portee.mois(10));
    expect(g.generales.values.any((t) => t.contains('période précédente')), isFalse);
    expect(g.generales.keys.toSet(), {1, 3, 6, 8});
  });

  test('étendue sans aucune note : rien n\'est généré', () {
    final g = genererAppreciations(classeDeHuit(), const Portee.mois(5));
    expect(g.generales, isEmpty);
    expect(g.matieres, isEmpty);
  });
}
