import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/moteur_resultats.dart';
import 'package:gesco/domain/niveaux.dart';

/// Méthodes de calcul par cycle. Chaque résultat attendu est calculé à la main
/// dans le commentaire qui précède l'assertion.
const maths = MatiereCoef(id: 1, nom: 'Maths', coefficient: 100);
const francais = MatiereCoef(id: 2, nom: 'Français', coefficient: 100);
const eveil = MatiereCoef(id: 3, nom: 'Éveil', coefficient: 100);

Saisie v(int centiemes) => Saisie.valeur(centiemes);

/// Élève dont [notes] donne, par matière (1, 2, 3), les notes (en centièmes)
/// par mois.
DonneesEleve eleve(int id, Map<int, Map<int, int>> notes, {bool actif = true}) => DonneesEleve(
      inscriptionId: id,
      nom: 'NOM$id',
      prenom: 'P$id',
      sexe: 'F',
      actif: actif,
      saisies: {
        for (final m in notes.entries)
          m.key: {for (final n in m.value.entries) n.key: v(n.value)},
      },
    );

MoteurResultats moteur(
  List<DonneesEleve> eleves, {
  required Calendrier calendrier,
  List<MatiereCoef> matieres = const [maths, francais, eveil],
  ConfigResultats config = ConfigResultats.defaut,
}) =>
    MoteurResultats(matieres: matieres, eleves: eleves, calendrier: calendrier, config: config);

void main() {
  group('calendriers par cycle', () {
    test('maternelle et primaire : trois compositions (décembre, mars, juin)', () {
      for (final cycle in [Cycle.maternelle, Cycle.primaire]) {
        final c = Calendrier.pourCycle(cycle);
        expect(c.type, TypePeriodes.compositions, reason: cycle.libelle);
        expect(c.methode, MethodeCalcul.compositions);
        expect([for (final p in c.periodes) p.mois], [
          [12],
          [3],
          [6],
        ]);
        expect(c.erreurs(), isEmpty);
        // Seuls décembre, mars et juin reçoivent des notes.
        expect(c.moisDeSaisie, [12, 3, 6]);
        expect(c.numeroCompo(12), 1);
        expect(c.numeroCompo(3), 2);
        expect(c.numeroCompo(6), 3);
        expect(c.numeroCompo(10), isNull);
      }
    });

    test('collège et lycée : deux semestres, janvier et juin sont les compositions', () {
      for (final cycle in [Cycle.college, Cycle.lycee]) {
        final c = Calendrier.pourCycle(cycle);
        expect(c.type, TypePeriodes.semestresCompo, reason: cycle.libelle);
        expect(c.methode, MethodeCalcul.semestresCompo);
        expect(c.periodes[0].mois, [10, 11, 12, 1]);
        expect(c.periodes[0].moisCompo, 1);
        expect(c.periodes[1].mois, [2, 3, 4, 5, 6]);
        expect(c.periodes[1].moisCompo, 6);
        expect(c.periodes.every((p) => p.poidsCompo == 2), isTrue);
        expect(c.erreurs(), isEmpty);
        expect(c.moisDeSaisie, [10, 11, 12, 1, 2, 3, 4, 5, 6]);
        expect(c.numeroCompo(1), 1);
        expect(c.numeroCompo(6), 2);
        expect(c.numeroCompo(10), isNull);
        expect(c.numeroCompo(2), isNull);
      }
    });

    test('sans cycle et ancien calendrier : la méthode historique', () {
      expect(Calendrier.pourCycle(null), Calendrier.trimestres);
      expect(Calendrier.trimestres.methode, MethodeCalcul.moyenneDesMois);
      expect(Calendrier.semestres.methode, MethodeCalcul.moyenneDesMois);
      expect(Calendrier.semestres == Calendrier.semestresCompo, isFalse);
    });

    test('les calendriers se relisent tels quels (type, composition, poids, pondération)', () {
      for (final c in [
        Calendrier.compositions,
        Calendrier.semestresCompo,
        Calendrier.compositions.copyWith(ponderee: false),
        Calendrier.semestresCompo.copyWith(ponderee: false),
      ]) {
        final relu = Calendrier.fromJsonString(c.toJsonString());
        expect(relu, c);
        expect(relu.ponderee, c.ponderee);
        expect(relu.methode, c.methode);
      }
      // Un calendrier enregistré avant l'arrivée des compositions reste lisible.
      final ancien = Calendrier.fromJsonString(Calendrier.semestres.toJsonString());
      expect(ancien.periodes[0].moisCompo, isNull);
      expect(ancien.ponderee, isTrue);
      expect(Calendrier.semestres.toJsonString(), isNot(contains('moisCompo')));
    });

    test('contrôles : une composition = un mois ; un semestre a un mois de composition', () {
      final deuxMois = Calendrier.compositions.copyWith(periodes: const [
        PeriodeScolaire(cle: 'c1', libelle: 'Compo 1', mois: [11, 12]),
      ]);
      expect(deuxMois.erreurs().join(' '), contains('un seul mois'));

      final sansCompo = Calendrier.semestresCompo.copyWith(periodes: const [
        PeriodeScolaire(cle: 's1', libelle: 'S1', mois: [10, 11, 12, 1]),
        PeriodeScolaire(cle: 's2', libelle: 'S2', mois: [2, 3, 4, 5, 6], moisCompo: 6),
      ]);
      expect(sansCompo.erreurs().join(' '), contains('mois de composition'));

      final composHorsPeriode = Calendrier.semestresCompo.copyWith(periodes: const [
        PeriodeScolaire(cle: 's1', libelle: 'S1', mois: [10, 11, 12, 1], moisCompo: 3),
        PeriodeScolaire(cle: 's2', libelle: 'S2', mois: [2, 3, 4, 5, 6], moisCompo: 6),
      ]);
      expect(composHorsPeriode.erreurs().join(' '), contains('mois de composition'));

      final poids = Calendrier.semestresCompo.copyWith(periodes: const [
        PeriodeScolaire(cle: 's1', libelle: 'S1', mois: [10, 11, 12, 1], moisCompo: 1, poidsCompo: 0),
        PeriodeScolaire(cle: 's2', libelle: 'S2', mois: [2, 3, 4, 5, 6], moisCompo: 6),
      ]);
      expect(poids.erreurs().join(' '), contains('poids'));

      // Les semestres doivent toujours couvrir octobre à juin.
      final incomplet = Calendrier.semestresCompo.copyWith(periodes: const [
        PeriodeScolaire(cle: 's1', libelle: 'S1', mois: [10, 11, 12, 1], moisCompo: 1),
      ]);
      expect(incomplet.erreurs().join(' '), contains('n\'appartient à aucune'));
    });
  });

  group('maternelle et primaire : trois compositions', () {
    // Trois matières de coefficient 1 : la moyenne d'une composition est la
    // somme des notes ÷ 3.
    //
    // Élève 1
    //   Décembre (compo 1) : 12 + 14 + 10 = 36  -> 36 / 3 = 12,00
    //   Mars     (compo 2) : 15 + 13 + 14 = 42  -> 42 / 3 = 14,00
    //   Juin     (compo 3) : 16 + 18 + 11 = 45  -> 45 / 3 = 15,00
    //   Note finale = (12,00 + 14,00 + 15,00) / 3 = 41 / 3 = 13,67
    final e1 = eleve(1, {
      1: {12: 1200, 3: 1500, 6: 1600},
      2: {12: 1400, 3: 1300, 6: 1800},
      3: {12: 1000, 3: 1400, 6: 1100},
    });
    // Élève 2 : 10 partout -> 10,00
    final e2 = eleve(2, {
      1: {12: 1000, 3: 1000, 6: 1000},
      2: {12: 1000, 3: 1000, 6: 1000},
      3: {12: 1000, 3: 1000, 6: 1000},
    });
    // Élève 3 : (14,00 + 12,00 + 13,00) / 3 = 13,00
    final e3 = eleve(3, {
      1: {12: 1400, 3: 1200, 6: 1300},
      2: {12: 1400, 3: 1200, 6: 1300},
      3: {12: 1400, 3: 1200, 6: 1300},
    });
    // Élève 4 : exactement comme l'élève 3 (ex æquo)
    final e4 = eleve(4, {
      1: {12: 1400, 3: 1200, 6: 1300},
      2: {12: 1400, 3: 1200, 6: 1300},
      3: {12: 1400, 3: 1200, 6: 1300},
    });
    final m = moteur([e1, e2, e3, e4], calendrier: Calendrier.compositions);
    final periodes = Calendrier.compositions.periodes;

    test('moyenne de chaque composition = somme des notes ÷ nombre de matières', () {
      expect(m.moyenne(e1, Portee.periode(periodes[0])), 1200);
      expect(m.moyenne(e1, Portee.periode(periodes[1])), 1400);
      expect(m.moyenne(e1, Portee.periode(periodes[2])), 1500);
    });

    test('note finale = somme des moyennes des compositions ÷ nombre de compositions', () {
      expect(m.moyenneAnnuelle(e1), 1367);
      expect(m.moyenneAnnuelle(e2), 1000);
      expect(m.moyenneAnnuelle(e3), 1300);
    });

    test('classement par mérite de chaque composition et de l\'année (ex æquo : 1, 1, 3)', () {
      // Année : élève 1 = 13,67 ; élèves 3 et 4 = 13,00 ; élève 2 = 10,00
      final annee = {for (final r in m.resultatsAnnee()) r.inscriptionId: r};
      expect(annee[1]!.rang, 1);
      expect(annee[3]!.rang, 2);
      expect(annee[4]!.rang, 2);
      expect(annee[2]!.rang, 4);
      expect(annee[1]!.moyenne, 1367);
      expect(annee[1]!.decision, 'Admis(e) en classe supérieure');
      // Compo 1 (décembre) : 12,00 ; 10,00 ; 14,00 ; 14,00
      final compo1 = {for (final r in m.resultats(Portee.periode(periodes[0]))) r.inscriptionId: r};
      expect(compo1[3]!.rang, 1);
      expect(compo1[4]!.rang, 1);
      expect(compo1[1]!.rang, 3);
      expect(compo1[2]!.rang, 4);
    });

    test('les autres mois ne comptent pas : une note d\'octobre est ignorée', () {
      final avecOctobre = eleve(9, {
        1: {10: 2000, 12: 1200, 3: 1500, 6: 1600},
        2: {10: 2000, 12: 1400, 3: 1300, 6: 1800},
        3: {10: 2000, 12: 1000, 3: 1400, 6: 1100},
      });
      final mo = moteur([avecOctobre], calendrier: Calendrier.compositions);
      expect(mo.moyenneAnnuelle(avecOctobre), 1367);
      expect(mo.moyenneMois(avecOctobre, 10), 2000);
    });

    test('compositions non encore passées : moyenne des compositions disponibles, signalée incomplète', () {
      final partiel = eleve(5, {
        1: {12: 1200, 3: 1500},
        2: {12: 1400, 3: 1300},
        3: {12: 1000, 3: 1400},
      });
      final mp = moteur([partiel], calendrier: Calendrier.compositions);
      // (12,00 + 14,00) / 2 = 13,00
      expect(mp.moyenneAnnuelle(partiel), 1300);
      expect(mp.anneeIncomplete(partiel), isTrue);
      expect(mp.incomplet(partiel, Portee.periode(periodes[0])), isFalse);
      expect(mp.incomplet(partiel, Portee.periode(periodes[2])), isTrue);
      expect(mp.moyenne(partiel, Portee.periode(periodes[2])), isNull);
    });

    test('avec « période complète exigée », pas de note finale tant qu\'une composition manque', () {
      final partiel = eleve(5, {
        1: {12: 1200, 3: 1500},
        2: {12: 1400, 3: 1300},
        3: {12: 1000, 3: 1400},
      });
      final mp = moteur(
        [partiel],
        calendrier: Calendrier.compositions,
        config: ConfigResultats.defaut.avecRegles(exigerPeriodeComplete: true),
      );
      expect(mp.moyenneAnnuelle(partiel), isNull);
    });

    test('coefficients : par défaut la moyenne est pondérée, en « moyenne simple » ils sont ignorés', () {
      // Maths coef 2, Français coef 1, Éveil coef 1 ; compo 1 : 16, 14, 10.
      //   pondérée : (16x2 + 14 + 10) / 4 = 56 / 4 = 14,00
      //   simple   : (16 + 14 + 10) / 3 = 40 / 3 = 13,33
      const maths2 = MatiereCoef(id: 1, nom: 'Maths', coefficient: 200);
      final e = eleve(7, {
        1: {12: 1600},
        2: {12: 1400},
        3: {12: 1000},
      });
      final c1 = Calendrier.compositions.periodes[0];
      final ponderee = moteur([e], calendrier: Calendrier.compositions, matieres: const [maths2, francais, eveil]);
      expect(ponderee.moyenne(e, Portee.periode(c1)), 1400);
      final simple = moteur(
        [e],
        calendrier: Calendrier.compositions.copyWith(ponderee: false),
        matieres: const [maths2, francais, eveil],
      );
      expect(simple.moyenne(e, Portee.periode(c1)), 1333);
    });

    test('matière absente ou dispensée : exclue de la somme et du nombre de matières', () {
      // Décembre : maths 12, français absent, éveil 10 -> (12 + 10) / 2 = 11,00
      final e = DonneesEleve(
        inscriptionId: 8,
        nom: 'A',
        prenom: 'B',
        sexe: 'M',
        saisies: {
          1: {12: v(1200)},
          2: {12: const Saisie.absent()},
          3: {12: v(1000)},
        },
      );
      final me = moteur([e], calendrier: Calendrier.compositions);
      expect(me.moyenne(e, Portee.periode(Calendrier.compositions.periodes[0])), 1100);
      expect(me.incomplet(e, Portee.periode(Calendrier.compositions.periodes[0])), isTrue);
    });
  });

  group('collège et lycée : mois, compositions et semestres', () {
    // Deux matières de coefficient 1 : la moyenne d'un mois est la somme des
    // notes ÷ 2.
    //
    //   Octobre  : 12 + 14 = 26 -> 13,00        Février : 11 + 13 = 24 -> 12,00
    //   Novembre : 10 + 12 = 22 -> 11,00        Mars    : 14 + 10 = 24 -> 12,00
    //   Décembre : 15 + 13 = 28 -> 14,00        Avril   :  9 + 11 = 20 -> 10,00
    //   Janvier  : 16 + 18 = 34 -> 17,00 = compo 1      Mai : 13 + 15 = 28 -> 14,00
    //                                           Juin    : 14 + 16 = 30 -> 15,00 = compo 2
    //
    //   Semestre 1 = (compo 1 x 2 + moyenne(oct, nov, déc)) / 3
    //     moyenne(oct, nov, déc) = (13 + 11 + 14) / 3 = 12,67 (arrondie)
    //     S1 = (17,00 x 2 + 12,67) / 3 = 46,67 / 3 = 15,56
    //   Semestre 2 = (compo 2 x 2 + moyenne(fév, mars, avril, mai)) / 3
    //     moyenne(fév, mars, avril, mai) = (12 + 12 + 10 + 14) / 4 = 12,00
    //     S2 = (15,00 x 2 + 12,00) / 3 = 42 / 3 = 14,00
    //   Année = (S1 + S2) / 2 = (15,56 + 14,00) / 2 = 14,78
    final e1 = eleve(1, {
      1: {10: 1200, 11: 1000, 12: 1500, 1: 1600, 2: 1100, 3: 1400, 4: 900, 5: 1300, 6: 1400},
      2: {10: 1400, 11: 1200, 12: 1300, 1: 1800, 2: 1300, 3: 1000, 4: 1100, 5: 1500, 6: 1600},
    });
    const deux = [maths, francais];
    final cal = Calendrier.semestresCompo;
    final s1 = cal.periodes[0];
    final s2 = cal.periodes[1];
    final m = moteur([e1], calendrier: cal, matieres: deux);

    test('moyenne de chaque mois = somme des notes ÷ nombre de matières', () {
      final attendu = {
        10: 1300, 11: 1100, 12: 1400, 1: 1700, 2: 1200, 3: 1200, 4: 1000, 5: 1400, 6: 1500,
      };
      attendu.forEach((mois, moyenne) {
        expect(m.moyenneMois(e1, mois), moyenne, reason: 'mois $mois');
      });
    });

    test('moyenne des mois du semestre sans la composition (arrondie)', () {
      expect(m.moyenneMoisHorsCompo(e1, s1), 1267);
      expect(m.moyenneMoisHorsCompo(e1, s2), 1200);
      expect(m.moyenneMoisHorsCompo(e1, Calendrier.semestres.periodes[0]), isNull);
    });

    test('semestre 1 = (composition 1 × 2 + moyenne de octobre, novembre, décembre) ÷ 3', () {
      expect(m.moyenne(e1, Portee.periode(s1)), 1556);
      expect(m.moyenneTrimestre(e1, 1), 1556);
    });

    test('semestre 2 = (composition 2 × 2 + moyenne de février à mai) ÷ 3', () {
      expect(m.moyenne(e1, Portee.periode(s2)), 1400);
    });

    test('moyenne de fin d\'année = (semestre 1 + semestre 2) ÷ 2', () {
      expect(m.moyenneAnnuelle(e1), 1478);
      expect(m.anneeIncomplete(e1), isFalse);
      expect(m.incomplet(e1, Portee.periode(s1)), isFalse);
    });

    test('note d\'une matière au semestre : même formule, matière par matière', () {
      // Maths S1 : moyenne(12, 10, 15) = 12,33 ; (16 x 2 + 12,33) / 3 = 14,78
      expect(m.noteMatiere(e1, 1, Portee.periode(s1)), 1478);
      // Français S1 : moyenne(14, 12, 13) = 13,00 ; (18 x 2 + 13) / 3 = 16,33
      expect(m.noteMatiere(e1, 2, Portee.periode(s1)), 1633);
      // Maths S2 : moyenne(11, 14, 9, 13) = 11,75 ; (14 x 2 + 11,75) / 3 = 13,25
      expect(m.noteMatiere(e1, 1, Portee.periode(s2)), 1325);
      // Année, maths : (14,78 + 13,25) / 2 = 14,015 -> 14,02
      expect(m.noteMatiere(e1, 1, const Portee.annee()), 1402);
    });

    test('le lycée suit exactement la même méthode', () {
      final lycee = moteur([e1], calendrier: Calendrier.pourCycle(Cycle.lycee), matieres: deux);
      expect(lycee.moyenneTrimestre(e1, 1), 1556);
      expect(lycee.moyenneTrimestre(e1, 2), 1400);
      expect(lycee.moyenneAnnuelle(e1), 1478);
    });

    test('coefficients : maths coef 3, français coef 1', () {
      // Octobre : (12 x 3 + 14 x 1) / 4 = 50 / 4 = 12,50 ; en moyenne simple : 13,00
      const maths3 = MatiereCoef(id: 1, nom: 'Maths', coefficient: 300);
      const fr = MatiereCoef(id: 2, nom: 'Français', coefficient: 100);
      final p = moteur([e1], calendrier: cal, matieres: const [maths3, fr]);
      expect(p.moyenneMois(e1, 10), 1250);
      final s = moteur([e1], calendrier: cal.copyWith(ponderee: false), matieres: const [maths3, fr]);
      expect(s.moyenneMois(e1, 10), 1300);
    });

    test('mois manquant : moyenne calculée sur les mois disponibles, résultat incomplet', () {
      // Novembre non saisi : moyenne(oct, déc) = (13 + 14) / 2 = 13,50 (arrondi 13,50)
      // S1 = (17,00 x 2 + 13,50) / 3 = 47,50 / 3 = 15,83
      final sansNovembre = eleve(2, {
        1: {10: 1200, 12: 1500, 1: 1600},
        2: {10: 1400, 12: 1300, 1: 1800},
      });
      final mn = moteur([sansNovembre], calendrier: cal, matieres: deux);
      expect(mn.moyenne(sansNovembre, Portee.periode(s1)), 1583);
      expect(mn.incomplet(sansNovembre, Portee.periode(s1)), isTrue);
    });

    test('composition manquante : le semestre se calcule sur les mois seuls, signalé incomplet', () {
      final sansJanvier = eleve(3, {
        1: {10: 1200, 11: 1000, 12: 1500},
        2: {10: 1400, 11: 1200, 12: 1300},
      });
      final mj = moteur([sansJanvier], calendrier: cal, matieres: deux);
      // Seulement la moyenne des trois mois : 12,67
      expect(mj.moyenne(sansJanvier, Portee.periode(s1)), 1267);
      expect(mj.incomplet(sansJanvier, Portee.periode(s1)), isTrue);
      final strict = moteur(
        [sansJanvier],
        calendrier: cal,
        matieres: deux,
        config: ConfigResultats.defaut.avecRegles(exigerPeriodeComplete: true),
      );
      expect(strict.moyenne(sansJanvier, Portee.periode(s1)), isNull);
    });

    test('composition seule : le semestre vaut la composition', () {
      final seule = eleve(4, {
        1: {1: 1600},
        2: {1: 1800},
      });
      final ms = moteur([seule], calendrier: cal, matieres: deux);
      expect(ms.moyenne(seule, Portee.periode(s1)), 1700);
    });

    test('un seul semestre noté : l\'année est calculée sur les semestres disponibles', () {
      final s1seul = eleve(5, {
        1: {10: 1200, 11: 1000, 12: 1500, 1: 1600},
        2: {10: 1400, 11: 1200, 12: 1300, 1: 1800},
      });
      final ms = moteur([s1seul], calendrier: cal, matieres: deux);
      expect(ms.moyenneAnnuelle(s1seul), 1556);
      expect(ms.anneeIncomplete(s1seul), isTrue);
    });

    test('classement par mérite : par mois, par semestre et pour l\'année', () {
      // Élève 2 : 18,00 en octobre seulement ; élève 3 : 13,00 en octobre.
      final e2 = eleve(2, {
        1: {10: 1800},
        2: {10: 1800},
      });
      final e3 = eleve(3, {
        1: {10: 1300},
        2: {10: 1300},
      });
      final mc = moteur([e1, e2, e3], calendrier: cal, matieres: deux);
      // Octobre : élève 2 (18,00), puis élèves 1 et 3 (13,00, ex æquo)
      final octobre = {for (final r in mc.resultatsMois(10)) r.inscriptionId: r.rang};
      expect(octobre, {1: 2, 2: 1, 3: 2});
      // Semestre 1 : élève 1 = 15,56 ; élève 2 = 18,00 ; élève 3 = 13,00
      final sem = {for (final r in mc.resultatsTrimestre(1)) r.inscriptionId: r.rang};
      expect(sem, {1: 2, 2: 1, 3: 3});
    });

    test('un élève parti garde ses notes mais n\'est pas classé', () {
      final parti = eleve(
        6,
        {
          1: {10: 2000},
          2: {10: 2000},
        },
        actif: false,
      );
      final mc = moteur([e1, parti], calendrier: cal, matieres: deux);
      final octobre = {for (final r in mc.resultatsMois(10)) r.inscriptionId: r};
      expect(octobre[6]!.moyenne, 2000);
      expect(octobre[6]!.rang, isNull);
      expect(octobre[1]!.rang, 1);
    });
  });

  group('ancienne méthode', () {
    test('un calendrier en trimestres calcule toujours la moyenne des mois', () {
      final e = eleve(1, {
        1: {10: 1000, 11: 1400, 12: 1200},
        2: {10: 1000, 11: 1400, 12: 1200},
      });
      final m = moteur([e], calendrier: Calendrier.trimestres, matieres: const [maths, francais]);
      expect(m.moyenneTrimestre(e, 1), 1200);
    });
  });
}
