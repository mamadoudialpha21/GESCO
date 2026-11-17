import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/moteur_resultats.dart';

const maths = MatiereCoef(id: 1, nom: 'Maths', coefficient: 400);
const francais = MatiereCoef(id: 2, nom: 'Français', coefficient: 200);
const musique = MatiereCoef(id: 3, nom: 'Musique', coefficient: 100, facultative: true);

DonneesEleve eleve(int id, Map<int, Map<int, Saisie>> saisies) => DonneesEleve(
      inscriptionId: id,
      nom: 'NOM$id',
      prenom: 'P$id',
      sexe: 'F',
      saisies: saisies,
    );

Saisie v(int centiemes) => Saisie.valeur(centiemes);

MoteurResultats moteur(
  List<DonneesEleve> eleves, {
  Calendrier calendrier = Calendrier.defaut,
  List<MatiereCoef> matieres = const [maths, francais],
}) =>
    MoteurResultats(matieres: matieres, eleves: eleves, calendrier: calendrier);

void main() {
  // Élève qui a 10 en maths et 16 en français tous les mois d'octobre à janvier,
  // puis 14 / 14 en février et mars.
  final regulier = eleve(1, {
    1: {10: v(1000), 11: v(1000), 12: v(1000), 1: v(1000), 2: v(1400), 3: v(1400)},
    2: {10: v(1600), 11: v(1600), 12: v(1600), 1: v(1600), 2: v(1400), 3: v(1400)},
  });

  group('trimestres : le comportement historique est inchangé', () {
    test('moyenne de chaque trimestre et de l\'année', () {
      final m = moteur([regulier]);
      // Mois d'octobre : (10x4 + 16x2) / 6 = 12,00
      expect(m.moyenneMois(regulier, 10), 1200);
      expect(m.moyenneTrimestre(regulier, 1), 1200);
      // Janvier : 12,00 ; février, mars : 14,00 -> 13,33
      expect(m.moyenneTrimestre(regulier, 2), 1333);
      expect(m.moyenneTrimestre(regulier, 3), isNull);
      // Année : moyenne des deux trimestres disponibles (12,00 et 13,33) -> 12,67
      expect(m.moyenneAnnuelle(regulier), 1267);
    });

    test('un numéro de période inexistant est refusé', () {
      expect(() => moteur([regulier]).moyenneTrimestre(regulier, 0), throwsArgumentError);
      expect(() => moteur([regulier]).moyenneTrimestre(regulier, 4), throwsArgumentError);
    });
  });

  group('semestres', () {
    final m = moteur([regulier], calendrier: Calendrier.semestres);

    test('le semestre 1 regroupe octobre à janvier', () {
      final s1 = Calendrier.semestres.periodes[0];
      expect(m.moyenne(regulier, Portee.periode(s1)), 1200);
    });

    test('le semestre 2 regroupe février à juin (mois sans note ignorés)', () {
      final s2 = Calendrier.semestres.periodes[1];
      expect(m.moyenne(regulier, Portee.periode(s2)), 1400);
    });

    test('l\'année est la moyenne des deux semestres', () {
      expect(m.moyenneAnnuelle(regulier), 1300);
      expect(m.moyenne(regulier, const Portee.annee()), 1300);
    });

    test('le raccourci « trimestre 2 » désigne la deuxième période', () {
      expect(m.moyenneTrimestre(regulier, 2), 1400);
      expect(() => m.moyenneTrimestre(regulier, 3), throwsArgumentError);
    });

    test('résultats par semestre : moyenne, rang, mention, décision', () {
      final autre = eleve(2, {
        1: {10: v(1800), 1: v(1800)},
        2: {10: v(1800), 1: v(1800)},
      });
      final r = moteur([regulier, autre], calendrier: Calendrier.semestres)
          .resultats(Portee.periode(Calendrier.semestres.periodes[0]));
      expect(r[0].moyenne, 1200);
      expect(r[0].rang, 2);
      expect(r[1].moyenne, 1800);
      expect(r[1].rang, 1);
      expect(r[1].mention, isNotEmpty);
    });
  });

  group('séquences', () {
    final cal = Calendrier.trimestres.copyWith(sequences: Calendrier.sequencesProposees);
    final m = moteur([regulier], calendrier: cal);

    test('moyenne d\'une séquence de plusieurs mois', () {
      final q3 = cal.sequence('q3')!; // janvier, février
      expect(m.moyenne(regulier, Portee.periode(q3)), 1300);
    });

    test('moyenne d\'une séquence d\'un seul mois = moyenne de ce mois', () {
      final q2 = cal.sequence('q2')!; // décembre
      expect(m.moyenne(regulier, Portee.periode(q2)), m.moyenneMois(regulier, 12));
    });

    test('séquence sans note : pas de moyenne', () {
      expect(m.moyenne(regulier, Portee.periode(cal.sequence('q6')!)), isNull);
    });
  });

  group('une seule période pour l\'année entière', () {
    test('année = période unique', () {
      const cal = Calendrier(
        type: TypePeriodes.personnalise,
        periodes: [
          PeriodeScolaire(cle: 'a', libelle: 'Année', mois: [10, 11, 12, 1, 2, 3, 4, 5, 6]),
        ],
      );
      final m = moteur([regulier], calendrier: cal);
      expect(m.moyenneAnnuelle(regulier), m.moyenneTrimestre(regulier, 1));
      expect(m.moyenneAnnuelle(regulier), 1267);
    });
  });

  group('matières facultatives', () {
    final avecMusique = eleve(1, {
      1: {10: v(1000)},
      2: {10: v(1600)},
      3: {10: v(2000)},
    });

    test('exclues de la moyenne générale', () {
      final m = moteur([avecMusique], matieres: const [maths, francais, musique]);
      expect(m.moyenneMois(avecMusique, 10), 1200);
    });

    test('leur note reste disponible matière par matière', () {
      final m = moteur([avecMusique], matieres: const [maths, francais, musique]);
      expect(m.noteMatiere(avecMusique, 3, const Portee.mois(10)), 2000);
      expect(m.noteMatiere(avecMusique, 3, Portee.periode(Calendrier.defaut.periodes[0])),
          2000);
    });

    test('une facultative manquante ne rend pas le mois incomplet', () {
      final sansMusique = eleve(1, {
        1: {10: v(1000)},
        2: {10: v(1600)},
      });
      final m = moteur([sansMusique], matieres: const [maths, francais, musique]);
      expect(m.moisIncomplet(sansMusique, 10), isFalse);
    });

    test('un élève qui n\'a que la facultative n\'a pas de moyenne', () {
      final seule = eleve(1, {
        3: {10: v(1800)},
      });
      final m = moteur([seule], matieres: const [maths, francais, musique]);
      expect(m.moyenneMois(seule, 10), isNull);
    });
  });

  group('note et classement par matière', () {
    final a = eleve(1, {
      1: {10: v(1500), 11: v(1700), 1: v(1000)},
    });
    final b = eleve(2, {
      1: {10: v(1500), 11: v(900)},
    });
    final c = eleve(3, {
      1: {10: const Saisie.absent()},
    });
    final d = eleve(4, {});
    final m = moteur([a, b, c, d]);

    test('note d\'une matière sur un mois', () {
      expect(m.noteMatiere(a, 1, const Portee.mois(10)), 1500);
      expect(m.noteMatiere(c, 1, const Portee.mois(10)), isNull);
      expect(m.noteMatiere(d, 1, const Portee.mois(10)), isNull);
    });

    test('note d\'une matière sur un trimestre : moyenne des mois notés', () {
      final t1 = Portee.periode(Calendrier.defaut.periodes[0]);
      expect(m.noteMatiere(a, 1, t1), 1600);
      expect(m.noteMatiere(b, 1, t1), 1200);
    });

    test('note d\'une matière sur l\'année : moyenne des notes de période', () {
      // T1 = 16,00 ; T2 = 10,00 -> 13,00
      expect(m.noteMatiere(a, 1, const Portee.annee()), 1300);
    });

    test('classement dans la matière avec ex æquo et absents sans rang', () {
      final r = m.classementMatiere(1, const Portee.mois(10));
      expect(r.map((x) => x.rang).toList(), [1, 1, null, null]);
      expect(r.map((x) => x.note).toList(), [1500, 1500, null, null]);
    });

    test('classement sur un trimestre', () {
      final t1 = Portee.periode(Calendrier.defaut.periodes[0]);
      final r = m.classementMatiere(1, t1);
      expect(r[0].rang, 1);
      expect(r[1].rang, 2);
    });

    test('matière inconnue refusée', () {
      expect(() => m.classementMatiere(99, const Portee.mois(10)), throwsArgumentError);
    });

    test('mois hors année scolaire refusé', () {
      expect(() => m.noteMatiere(a, 1, const Portee.mois(7)), throwsArgumentError);
      expect(() => m.resultats(const Portee.mois(7)), throwsArgumentError);
    });
  });

  group('périodes incomplètes', () {
    test('une période est incomplète si un de ses mois n\'a pas de moyenne', () {
      final m = moteur([regulier]);
      expect(m.trimestreIncomplet(regulier, 2), isFalse); // janvier à mars notés
      expect(m.trimestreIncomplet(regulier, 3), isTrue); // avril à juin vides
      final complet = eleve(1, {
        1: {for (final mois in [10, 11, 12]) mois: v(1000)},
        2: {for (final mois in [10, 11, 12]) mois: v(1000)},
      });
      expect(moteur([complet]).trimestreIncomplet(complet, 1), isFalse);
      expect(moteur([complet]).incomplet(complet, const Portee.annee()), isTrue);
    });
  });
}
