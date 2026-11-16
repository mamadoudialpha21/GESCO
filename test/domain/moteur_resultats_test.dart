import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/moteur_resultats.dart';

// Matières : Mathématiques (id 1, coef 4), Français (id 2, coef 3),
// Anglais (id 3, coef 2). Total des coefficients = 9.
const matieres = [
  MatiereCoef(id: 1, nom: 'Mathématiques', coefficient: 400),
  MatiereCoef(id: 2, nom: 'Français', coefficient: 300),
  MatiereCoef(id: 3, nom: 'Anglais', coefficient: 200),
];

/// Construit les saisies à partir de : matière -> mois -> note en centièmes.
Map<int, Map<int, Saisie>> saisiesDepuis(Map<int, Map<int, int>> valeurs) => {
      for (final m in valeurs.entries)
        m.key: {
          for (final n in m.value.entries) n.key: Saisie.valeur(n.value),
        },
    };

/// Même note dans les 3 matières, pour chaque mois indiqué (mois -> note).
Map<int, Map<int, Saisie>> uniforme(Map<int, int> parMois) => saisiesDepuis({
      for (final id in [1, 2, 3]) id: parMois,
    });

DonneesEleve eleve(
  int id,
  Map<int, Map<int, Saisie>> saisies, {
  String nom = 'NOM',
  String sexe = 'F',
}) =>
    DonneesEleve(
      inscriptionId: id,
      nom: nom,
      prenom: 'Prénom',
      sexe: sexe,
      saisies: saisies,
    );

MoteurResultats moteur(List<DonneesEleve> eleves,
        {List<MatiereCoef> liste = matieres}) =>
    MoteurResultats(matieres: liste, eleves: eleves);

void main() {
  group('moyenne mensuelle', () {
    final a = eleve(
      1,
      saisiesDepuis({
        1: {10: 1500, 11: 1600, 12: 1400},
        2: {10: 1200, 11: 1300, 12: 1400},
        3: {10: 1000, 11: 1100, 12: 1200},
      }),
    );

    test('somme(note x coefficient) / somme(coefficients), arrondie', () {
      final m = moteur([a]);
      // Octobre : (15x4 + 12x3 + 10x2) / 9 = 116 / 9 = 12,888... -> 12,89
      expect(m.moyenneMois(a, 10), 1289);
      // Novembre : 125 / 9 = 13,888... -> 13,89
      expect(m.moyenneMois(a, 11), 1389);
      // Décembre : 122 / 9 = 13,555... -> 13,56
      expect(m.moyenneMois(a, 12), 1356);
    });

    test('modifier un coefficient recalcule sans toucher aux notes brutes', () {
      const autres = [
        MatiereCoef(id: 1, nom: 'Mathématiques', coefficient: 100),
        MatiereCoef(id: 2, nom: 'Français', coefficient: 300),
        MatiereCoef(id: 3, nom: 'Anglais', coefficient: 200),
      ];
      final m = moteur([a], liste: autres);
      // (15x1 + 12x3 + 10x2) / 6 = 71 / 6 = 11,833... -> 11,83
      expect(m.moyenneMois(a, 10), 1183);
      // La note brute n'a pas bougé.
      expect(a.saisie(1, 10)!.centiemes, 1500);
    });

    test('un mois mal renseigné est refusé', () {
      expect(() => moteur([a]).moyenneMois(a, 7), throwsArgumentError);
      expect(() => moteur([a]).moyenneMois(a, 0), throwsArgumentError);
    });
  });

  group('notes manquantes, absences et dispenses', () {
    test('une note non saisie n\'est PAS un zéro', () {
      final e = eleve(1, saisiesDepuis({1: {10: 1500}}));
      final m = moteur([e]);
      // Seule les mathématiques comptent : 15,00 (et non 15x4/9 = 6,67).
      expect(m.moyenneMois(e, 10), 1500);
      expect(m.moisIncomplet(e, 10), isTrue);
    });

    test('un absent est exclu du calcul et rend le mois incomplet', () {
      final e = eleve(1, {
        1: {10: const Saisie.valeur(1500)},
        2: {10: const Saisie.absent()},
      });
      final m = moteur([e]);
      expect(m.moyenneMois(e, 10), 1500);
      expect(m.moisIncomplet(e, 10), isTrue);
    });

    test('un dispensé est exclu du calcul sans rendre le mois incomplet', () {
      final e = eleve(1, {
        1: {10: const Saisie.valeur(1500)},
        2: {10: const Saisie.valeur(1200)},
        3: {10: const Saisie.dispense()},
      });
      final m = moteur([e]);
      // (15x4 + 12x3) / 7 = 96 / 7 = 13,714... -> 13,71
      expect(m.moyenneMois(e, 10), 1371);
      expect(m.moisIncomplet(e, 10), isFalse);
    });

    test('aucune note chiffrée : pas de moyenne', () {
      final e = eleve(1, {
        1: {10: const Saisie.absent()},
        2: {10: const Saisie.dispense()},
      });
      expect(moteur([e]).moyenneMois(e, 10), isNull);
      expect(moteur([eleve(2, {})]).moyenneMois(eleve(2, {}), 10), isNull);
    });

    test('un vrai zéro saisi est bien compté', () {
      final e = eleve(1, saisiesDepuis({1: {10: 0}, 2: {10: 1200}}));
      // (0x4 + 12x3) / 7 = 5,142... -> 5,14
      expect(moteur([e]).moyenneMois(e, 10), 514);
    });
  });

  group('moyenne trimestrielle', () {
    test('moyenne des moyennes mensuelles publiées (arrondies)', () {
      final a = eleve(
        1,
        saisiesDepuis({
          1: {10: 1500, 11: 1600, 12: 1400},
          2: {10: 1200, 11: 1300, 12: 1400},
          3: {10: 1000, 11: 1100, 12: 1200},
        }),
      );
      // (12,89 + 13,89 + 13,56) / 3 = 13,4467 -> 13,45
      // (un calcul sans arrondi intermédiaire donnerait 13,44 : la règle
      // retenue est celle qu'on peut refaire à la main sur les documents).
      expect(moteur([a]).moyenneTrimestre(a, 1), 1345);
    });

    test('calculée sur les mois disponibles, signalée incomplète', () {
      final e = eleve(1, uniforme({10: 1200}));
      final m = moteur([e]);
      expect(m.moyenneTrimestre(e, 1), 1200);
      expect(m.trimestreIncomplet(e, 1), isTrue);
    });

    test('trimestre complet : non incomplet', () {
      final e = eleve(1, uniforme({10: 1200, 11: 1300, 12: 1400}));
      final m = moteur([e]);
      expect(m.moyenneTrimestre(e, 1), 1300);
      expect(m.trimestreIncomplet(e, 1), isFalse);
    });

    test('trimestre sans aucune note : pas de moyenne', () {
      final e = eleve(1, uniforme({10: 1200}));
      expect(moteur([e]).moyenneTrimestre(e, 2), isNull);
    });

    test('numéro de trimestre invalide', () {
      final e = eleve(1, {});
      expect(() => moteur([e]).moyenneTrimestre(e, 4), throwsArgumentError);
    });

    test('note d\'une matière au trimestre = moyenne de ses notes mensuelles',
        () {
      final e = eleve(1, saisiesDepuis({1: {10: 1000, 11: 1500, 12: 1250}}));
      // (10 + 15 + 12,5) / 3 = 12,5
      expect(moteur([e]).noteMatiereTrimestre(e, 1, 1), 1250);
      expect(moteur([e]).noteMatiereTrimestre(e, 2, 1), isNull);
    });
  });

  group('moyenne annuelle', () {
    final complete = eleve(
      1,
      uniforme({
        10: 1200, 11: 1300, 12: 1400, // T1 = 13,00
        1: 1000, 2: 1000, 3: 1000, // T2 = 10,00
        4: 1500, 5: 1500, 6: 1800, // T3 = 16,00
      }),
    );

    test('(T1 + T2 + T3) / 3', () {
      final m = moteur([complete]);
      expect(m.moyenneTrimestre(complete, 1), 1300);
      expect(m.moyenneTrimestre(complete, 2), 1000);
      expect(m.moyenneTrimestre(complete, 3), 1600);
      expect(m.moyenneAnnuelle(complete), 1300);
      expect(m.anneeIncomplete(complete), isFalse);
    });

    test('un seul trimestre disponible : année incomplète', () {
      final e = eleve(1, uniforme({10: 1200, 11: 1300, 12: 1400}));
      final m = moteur([e]);
      expect(m.moyenneAnnuelle(e), 1300);
      expect(m.anneeIncomplete(e), isTrue);
    });

    test('aucune note : pas de moyenne annuelle', () {
      final e = eleve(1, {});
      expect(moteur([e]).moyenneAnnuelle(e), isNull);
    });
  });

  group('rangs', () {
    test('ex æquo : 1, 1, 3 ; les élèves sans moyenne n\'ont pas de rang', () {
      final rangs = calculerRangs({1: 1500, 2: 1500, 3: 1400, 4: null, 5: 1300});
      expect(rangs, {1: 1, 2: 1, 3: 3, 5: 4});
    });

    test('personne n\'a de moyenne', () {
      expect(calculerRangs({1: null, 2: null}), isEmpty);
      expect(calculerRangs({}), isEmpty);
    });

    test('un seul élève est premier', () {
      expect(calculerRangs({7: 800}), {7: 1});
    });

    test('rangs, mentions et décisions d\'une classe pour un mois', () {
      final eleves = [
        eleve(1, uniforme({10: 1500}), nom: 'A'),
        eleve(2, uniforme({10: 1500}), nom: 'B'),
        eleve(3, uniforme({10: 1200}), nom: 'C'),
        eleve(4, uniforme({10: 900}), nom: 'D'),
        eleve(5, {}, nom: 'E'), // aucune note
      ];
      final r = moteur(eleves).resultatsMois(10);
      expect(r.map((x) => x.rang), [1, 1, 3, 4, null]);
      expect(r.map((x) => x.moyenne), [1500, 1500, 1200, 900, null]);
      expect(r.map((x) => x.mention), ['Bien', 'Bien', 'Assez bien', '', '']);
      expect(
        r.map((x) => x.decision),
        ['Admis(e)', 'Admis(e)', 'Admis(e)', 'Non admis(e)', ''],
      );
      expect(r.map((x) => x.incomplet), [false, false, false, false, true]);
      expect(r.map((x) => x.inscriptionId), [1, 2, 3, 4, 5]);
    });

    test('classement annuel avec décision annuelle', () {
      final eleves = [
        eleve(1, uniforme({10: 1200, 11: 1300, 12: 1400}), nom: 'A'),
        eleve(2, uniforme({10: 800, 11: 900, 12: 700}), nom: 'B'),
      ];
      final r = moteur(eleves).resultatsAnnee();
      expect(r[0].moyenne, 1300);
      expect(r[0].rang, 1);
      expect(r[0].decision, 'Admis(e) en classe supérieure');
      expect(r[1].moyenne, 800);
      expect(r[1].rang, 2);
      expect(r[1].decision, 'Redouble');
    });
  });

  group('arrondis aux limites', () {
    test('trimestre : (1001 + 1000 + 1000) / 3 = 1000,33 -> 1000', () {
      final e = eleve(1, uniforme({10: 1001, 11: 1000, 12: 1000}));
      expect(moteur([e]).moyenneTrimestre(e, 1), 1000);
    });

    test('trimestre : (1001 + 1001 + 1000) / 3 = 1000,67 -> 1001', () {
      final e = eleve(1, uniforme({10: 1001, 11: 1001, 12: 1000}));
      expect(moteur([e]).moyenneTrimestre(e, 1), 1001);
    });

    test('moyenne exactement à .005 : arrondie vers le haut', () {
      // Deux matières coef 1 : (10,00 + 10,01) / 2 = 10,005 -> 10,01
      const deux = [
        MatiereCoef(id: 1, nom: 'A', coefficient: 100),
        MatiereCoef(id: 2, nom: 'B', coefficient: 100),
      ];
      final e = eleve(1, saisiesDepuis({1: {10: 1000}, 2: {10: 1001}}));
      expect(moteur([e], liste: deux).moyenneMois(e, 10), 1001);
    });

    test('coefficients décimaux', () {
      // Coefficients 2,5 et 1,5 : (16x2,5 + 12x1,5) / 4 = 58 / 4 = 14,5
      const decimaux = [
        MatiereCoef(id: 1, nom: 'A', coefficient: 250),
        MatiereCoef(id: 2, nom: 'B', coefficient: 150),
      ];
      final e = eleve(1, saisiesDepuis({1: {10: 1600}, 2: {10: 1200}}));
      expect(moteur([e], liste: decimaux).moyenneMois(e, 10), 1450);
    });
  });
}
