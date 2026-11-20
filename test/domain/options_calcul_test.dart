import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/moteur_resultats.dart';
import 'package:gesco/domain/statistiques.dart';

// Mathématiques (coef 4), Français (coef 3), Anglais (coef 2).
const matieres = [
  MatiereCoef(id: 1, nom: 'Mathématiques', coefficient: 400),
  MatiereCoef(id: 2, nom: 'Français', coefficient: 300),
  MatiereCoef(id: 3, nom: 'Anglais', coefficient: 200),
];

Map<int, Map<int, Saisie>> uniforme(Map<int, int> parMois) => {
      for (final id in [1, 2, 3])
        id: {for (final m in parMois.entries) m.key: Saisie.valeur(m.value)},
    };

DonneesEleve eleve(
  int id,
  Map<int, Map<int, Saisie>> saisies, {
  bool actif = true,
  String sexe = 'F',
}) =>
    DonneesEleve(
      inscriptionId: id,
      nom: 'NOM$id',
      prenom: 'Prénom',
      sexe: sexe,
      saisies: saisies,
      actif: actif,
    );

MoteurResultats moteur(
  List<DonneesEleve> eleves, {
  bool absenceZero = false,
  bool periodeComplete = false,
}) =>
    MoteurResultats(
      matieres: matieres,
      eleves: eleves,
      config: ConfigResultats.defaut.avecRegles(
        absenceEgaleZero: absenceZero,
        exigerPeriodeComplete: periodeComplete,
      ),
    );

void main() {
  group('option « une absence compte pour zéro »', () {
    // Maths 15, Français absent, Anglais 10.
    final e = eleve(1, {
      1: {10: const Saisie.valeur(1500)},
      2: {10: const Saisie.absent()},
      3: {10: const Saisie.valeur(1000)},
    });

    test('désactivée (par défaut) : l\'absence est ignorée et rend le mois incomplet', () {
      final m = moteur([e]);
      // (15x4 + 10x2) / 6 = 13,333... -> 13,33
      expect(m.moyenneMois(e, 10), 1333);
      expect(m.moisIncomplet(e, 10), isTrue);
      expect(m.noteMatiere(e, 2, const Portee.mois(10)), isNull);
    });

    test('activée : l\'absence vaut 0 avec le coefficient de la matière', () {
      final m = moteur([e], absenceZero: true);
      // (15x4 + 0x3 + 10x2) / 9 = 8,888... -> 8,89
      expect(m.moyenneMois(e, 10), 889);
      expect(m.noteMatiere(e, 2, const Portee.mois(10)), 0);
      expect(m.moisIncomplet(e, 10), isFalse,
          reason: 'l\'absence est comptée : plus rien ne manque');
    });

    test('activée : une note non saisie reste ignorée (jamais zéro)', () {
      final sans = eleve(2, {
        1: {10: const Saisie.valeur(1500)},
        2: {10: const Saisie.absent()},
      });
      final m = moteur([sans], absenceZero: true);
      // Anglais non saisi : ignoré. (15x4 + 0x3) / 7 = 8,571... -> 8,57
      expect(m.moyenneMois(sans, 10), 857);
      expect(m.moisIncomplet(sans, 10), isTrue);
    });

    test('activée : un dispensé reste exclu du calcul', () {
      final dispense = eleve(3, {
        1: {10: const Saisie.valeur(1500)},
        2: {10: const Saisie.absent()},
        3: {10: const Saisie.dispense()},
      });
      final m = moteur([dispense], absenceZero: true);
      expect(m.moyenneMois(dispense, 10), 857);
      expect(m.moisIncomplet(dispense, 10), isFalse);
    });

    test('activée : l\'absence pèse aussi dans le trimestre et le classement', () {
      final bon = eleve(4, uniforme({10: 1000}));
      final m = moteur([e, bon], absenceZero: true);
      final r = m.resultatsMois(10);
      expect(r[0].moyenne, 889);
      expect(r[1].moyenne, 1000);
      expect(r.map((x) => x.rang), [2, 1]);
      expect(m.moyenneTrimestre(e, 1), 889);
    });
  });

  group('option « exiger les trois mois pour un trimestre »', () {
    final deuxMois = eleve(1, uniforme({10: 1200, 11: 1400}));
    final troisMois = eleve(2, uniforme({10: 1200, 11: 1400, 12: 1000}));

    test('désactivée : la moyenne se calcule sur les mois disponibles', () {
      final m = moteur([deuxMois, troisMois]);
      expect(m.moyenneTrimestre(deuxMois, 1), 1300);
      expect(m.trimestreIncomplet(deuxMois, 1), isTrue);
      expect(m.moyenneTrimestre(troisMois, 1), 1200);
    });

    test('activée : pas de moyenne tant qu\'un mois manque', () {
      final m = moteur([deuxMois, troisMois], periodeComplete: true);
      expect(m.moyenneTrimestre(deuxMois, 1), isNull);
      expect(m.trimestreIncomplet(deuxMois, 1), isTrue);
      expect(m.moyenneTrimestre(troisMois, 1), 1200);
    });

    test('activée : l\'élève sans moyenne n\'est pas classé', () {
      final m = moteur([deuxMois, troisMois], periodeComplete: true);
      final r = m.resultatsTrimestre(1);
      expect(r.map((x) => x.moyenne), [null, 1200]);
      expect(r.map((x) => x.rang), [null, 1]);
      expect(r.map((x) => x.decision), ['', 'Admis(e)']);
    });

    test('activée : la note d\'une matière exige ses trois mois', () {
      final sansFrancaisEnDecembre = eleve(3, {
        1: {10: const Saisie.valeur(1000), 11: const Saisie.valeur(1000), 12: const Saisie.valeur(1000)},
        2: {10: const Saisie.valeur(1000), 11: const Saisie.valeur(1000)},
        3: {10: const Saisie.valeur(1000), 11: const Saisie.valeur(1000), 12: const Saisie.valeur(1000)},
      });
      expect(moteur([sansFrancaisEnDecembre]).noteMatiereTrimestre(sansFrancaisEnDecembre, 2, 1),
          1000);
      expect(
        moteur([sansFrancaisEnDecembre], periodeComplete: true)
            .noteMatiereTrimestre(sansFrancaisEnDecembre, 2, 1),
        isNull,
      );
      expect(
        moteur([sansFrancaisEnDecembre], periodeComplete: true)
            .noteMatiereTrimestre(sansFrancaisEnDecembre, 1, 1),
        1000,
      );
    });

    test('activée : l\'année exige tous les trimestres', () {
      final partiel = eleve(4, uniforme({10: 1200, 11: 1200, 12: 1200}));
      final complet = eleve(
        5,
        uniforme({10: 1000, 11: 1000, 12: 1000, 1: 1400, 2: 1400, 3: 1400, 4: 1200, 5: 1200, 6: 1200}),
      );
      final libre = moteur([partiel, complet]);
      expect(libre.moyenneAnnuelle(partiel), 1200);
      expect(libre.moyenneAnnuelle(complet), 1200);

      final strict = moteur([partiel, complet], periodeComplete: true);
      expect(strict.moyenneAnnuelle(partiel), isNull);
      expect(strict.moyenneAnnuelle(complet), 1200);
      expect(strict.resultatsAnnee().map((r) => r.rang), [null, 1]);
    });

    test('n\'affecte pas la moyenne d\'un mois', () {
      final m = moteur([deuxMois], periodeComplete: true);
      expect(m.moyenneMois(deuxMois, 10), 1200);
    });
  });

  group('élèves partis ou ayant abandonné', () {
    final a = eleve(1, uniforme({10: 1500}), sexe: 'F');
    final parti = eleve(2, uniforme({10: 1600}), actif: false, sexe: 'M');
    final c = eleve(3, uniforme({10: 1400}), sexe: 'M');

    test('ne sont pas classés et ne décalent pas les rangs', () {
      final r = moteur([a, parti, c]).resultatsMois(10);
      expect(r.map((x) => x.moyenne), [1500, 1600, 1400],
          reason: 'sa moyenne reste calculée');
      expect(r.map((x) => x.rang), [1, null, 2]);
    });

    test('ne comptent pas dans les statistiques', () {
      final m = moteur([a, parti, c]);
      final stats = calculerStats(
        eleves: m.eleves,
        resultats: m.resultatsMois(10),
        config: ConfigResultats.defaut,
      );
      expect(stats.effectif, 2);
      expect(stats.filles, 1);
      expect(stats.garcons, 1);
      expect(stats.evalues, 2);
      expect(stats.moyenneClasse, 1450);
      expect(stats.meilleureMoyenne, 1500);
      expect(stats.plusFaibleMoyenne, 1400);
    });

    test('élèves à égalité : le parti ne prend pas la place d\'un ex æquo', () {
      final egal = eleve(4, uniforme({10: 1500}), actif: false);
      final r = moteur([a, egal, c]).resultatsMois(10);
      expect(r.map((x) => x.rang), [1, null, 2]);
    });

    test('le classement par matière les ignore aussi', () {
      final r = moteur([a, parti, c]).classementMatiere(1, const Portee.mois(10));
      expect(r.map((x) => x.note), [1500, 1600, 1400],
          reason: 'sa note reste visible');
      expect(r.map((x) => x.rang), [1, null, 2]);
    });
  });

  group('configuration enregistrée', () {
    test('les règles de calcul survivent à l\'enregistrement', () {
      final config = ConfigResultats.defaut.avecRegles(
        absenceEgaleZero: true,
        exigerPeriodeComplete: true,
      );
      final relue = ConfigResultats.fromJsonString(config.toJsonString());
      expect(relue.absenceEgaleZero, isTrue);
      expect(relue.exigerPeriodeComplete, isTrue);
    });

    test('une ancienne configuration sans ces règles garde le comportement par défaut', () {
      final ancienne = ConfigResultats.fromJson({
        'seuilAdmission': 1000,
        'seuilBon': 1200,
        'mentions': [
          {'seuil': 1200, 'libelle': 'Bien'},
        ],
        'decisionsPeriode': [
          {'seuil': 0, 'libelle': 'Non admis(e)'},
        ],
        'decisionsAnnee': [
          {'seuil': 0, 'libelle': 'Redouble'},
        ],
      });
      expect(ancienne.absenceEgaleZero, isFalse);
      expect(ancienne.exigerPeriodeComplete, isFalse);
    });

    test('par défaut : absence ignorée, moyenne sur les mois disponibles', () {
      expect(ConfigResultats.defaut.absenceEgaleZero, isFalse);
      expect(ConfigResultats.defaut.exigerPeriodeComplete, isFalse);
    });
  });
}
