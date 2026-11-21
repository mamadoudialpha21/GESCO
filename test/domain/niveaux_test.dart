import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/niveaux.dart';

void main() {
  group('catalogue des niveaux', () {
    test('treize niveaux : 1re à 6e année, 7e à 10e, 11e, 12e, Terminale', () {
      expect(niveauxScolaires.length, 13);
      expect([for (final n in niveauxScolaires) n.code], List.generate(13, (i) => i + 1));
      expect(niveauxScolaires.first.libelle, '1ère année');
      expect(niveauxScolaires.last.libelle, 'Terminale');
      expect(niveauxScolaires.last.code, NiveauScolaire.codeTerminale);
    });

    test('cycles : primaire 1-6, collège 7-10, lycée 11-Terminale', () {
      expect([for (final n in niveauxDuCycle(Cycle.primaire)) n.code], [1, 2, 3, 4, 5, 6]);
      expect([for (final n in niveauxDuCycle(Cycle.college)) n.code], [7, 8, 9, 10]);
      expect([for (final n in niveauxDuCycle(Cycle.lycee)) n.code], [11, 12, 13]);
      expect(cycleDuNiveau(6), Cycle.primaire);
      expect(cycleDuNiveau(7), Cycle.college);
      expect(cycleDuNiveau(10), Cycle.college);
      expect(cycleDuNiveau(11), Cycle.lycee);
      expect(cycleDuNiveau(13), Cycle.lycee);
      expect(cycleDuNiveau(0), isNull);
      expect(cycleDuNiveau(14), isNull);
      expect(cycleDuNiveau(null), isNull);
    });

    test('seul le lycée a des options', () {
      for (final n in niveauxScolaires) {
        expect(n.aDesOptions, n.code >= 11, reason: n.libelle);
      }
    });

    test('trois options : sciences sociales, expérimentales, mathématiques', () {
      expect([for (final s in SerieLycee.values) s.code], ['SS', 'SE', 'SM']);
      expect(SerieLycee.depuisCode('SM'), SerieLycee.sciencesMathematiques);
      expect(SerieLycee.depuisCode('SS')!.libelle, 'Sciences sociales');
      expect(SerieLycee.depuisCode('SE')!.libelle, 'Sciences expérimentales');
      expect(SerieLycee.depuisCode(''), isNull);
      expect(SerieLycee.depuisCode(null), isNull);
      expect(SerieLycee.depuisCode('XX'), isNull);
    });

    test('Cycle.depuisCle', () {
      expect(Cycle.depuisCle('college'), Cycle.college);
      expect(Cycle.depuisCle('lycee'), Cycle.lycee);
      expect(Cycle.depuisCle('inconnu'), isNull);
      expect(Cycle.depuisCle(null), isNull);
    });

    test('noms proposés et libellés complets', () {
      expect(nomProposeDeClasse(niveauDeCode(7)!, null), '7e');
      expect(nomProposeDeClasse(niveauDeCode(13)!, SerieLycee.sciencesMathematiques), 'Tle SM');
      expect(libelleNiveauComplet(niveauDeCode(12)!, SerieLycee.sciencesSociales),
          '12ème année · Sciences sociales');
      expect(libelleNiveauComplet(niveauDeCode(3)!, null), '3ème année');
    });
  });

  group('devinerNiveau (anciens niveaux saisis à la main)', () {
    final cas = <String, int?>{
      '10e': 10,
      '10e année': 10,
      '10ème': 10,
      '7ème année': 7,
      '1ère année': 1,
      '1re': 1,
      'Sixième': 6,
      'sixieme annee': 6,
      'Dixième année': 10,
      'Onzième': 11,
      '11e': 11,
      '12eme annee': 12,
      'Terminale': 13,
      'Terminale SM': 13,
      'Tle': 13,
      'TERMINALE': 13,
      '': null,
      '   ': null,
      'Maternelle': null,
      '2026': null,
      '15e': null,
      '0': null,
    };
    cas.forEach((texte, attendu) {
      test('« $texte » -> ${attendu ?? 'inconnu'}', () {
        expect(devinerNiveau(texte)?.code, attendu);
      });
    });
  });

  group('devinerSerie', () {
    final cas = <String, SerieLycee?>{
      'Terminale SM': SerieLycee.sciencesMathematiques,
      '12e SS': SerieLycee.sciencesSociales,
      '11e se': SerieLycee.sciencesExperimentales,
      'Terminale sciences mathématiques': SerieLycee.sciencesMathematiques,
      '12ème Sciences expérimentales': SerieLycee.sciencesExperimentales,
      '11 sciences sociales': SerieLycee.sciencesSociales,
      'Terminale': null,
      '': null,
      // « se » au milieu d'un mot ne doit pas être pris pour une option.
      'serie unique': null,
    };
    cas.forEach((texte, attendu) {
      test('« $texte »', () => expect(devinerSerie(texte), attendu));
    });
  });

  group('calendrier par cycle', () {
    test('primaire : trois trimestres', () {
      final c = Calendrier.pourCycle(Cycle.primaire);
      expect(c.periodes.length, 3);
      expect([for (final p in c.periodes) p.libelle],
          ['Trimestre 1', 'Trimestre 2', 'Trimestre 3']);
      expect(c.erreurs(), isEmpty);
    });

    test('collège et lycée : deux trimestres couvrant octobre à juin', () {
      for (final cycle in [Cycle.college, Cycle.lycee]) {
        final c = Calendrier.pourCycle(cycle);
        expect(c.periodes.length, 2, reason: cycle.libelle);
        expect([for (final p in c.periodes) p.libelle], ['Trimestre 1', 'Trimestre 2']);
        expect(c.erreurs(), isEmpty);
        final mois = [for (final p in c.periodes) ...p.mois]..sort();
        expect(mois, [1, 2, 3, 4, 5, 6, 10, 11, 12]);
        expect(c.periodeDuMois(11)!.cle, 't1');
        expect(c.periodeDuMois(1)!.cle, 't1');
        expect(c.periodeDuMois(2)!.cle, 't2');
        expect(c.periodeDuMois(6)!.cle, 't2');
      }
    });

    test('sans cycle : calendrier par défaut (trois trimestres)', () {
      expect(Calendrier.pourCycle(null), Calendrier.defaut);
    });

    test('le calendrier à deux trimestres se relit tel quel', () {
      final relu = Calendrier.fromJsonString(Calendrier.deuxTrimestres.toJsonString());
      expect(relu, Calendrier.deuxTrimestres);
      expect(relu.type, TypePeriodes.deuxTrimestres);
    });

    test('CalendriersAnnee : cycle absent = modèle du cycle', () {
      const c = CalendriersAnnee();
      expect(c.pour(Cycle.primaire), Calendrier.trimestres);
      expect(c.pour(Cycle.college), Calendrier.deuxTrimestres);
      expect(c.pour(Cycle.lycee), Calendrier.deuxTrimestres);
      expect(c.pour(null), Calendrier.defaut);

      final perso = CalendriersAnnee(
        general: Calendrier.semestres,
        parCycle: {Cycle.college: Calendrier.trimestres},
      );
      expect(perso.pour(Cycle.college), Calendrier.trimestres);
      expect(perso.pour(Cycle.lycee), Calendrier.deuxTrimestres);
      expect(perso.pour(null), Calendrier.semestres);
    });
  });
}
