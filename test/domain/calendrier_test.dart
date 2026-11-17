import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/domain/calendrier.dart';

void main() {
  group('calendriers prédéfinis', () {
    test('trois trimestres par défaut, tous valides', () {
      expect(Calendrier.defaut, Calendrier.trimestres);
      expect(Calendrier.trimestres.erreurs(), isEmpty);
      expect(Calendrier.trimestres.periodes.map((p) => p.cle), ['t1', 't2', 't3']);
      expect(Calendrier.trimestres.periodes[0].mois, [10, 11, 12]);
      expect(Calendrier.trimestres.periodes[2].mois, [4, 5, 6]);
    });

    test('deux semestres valides', () {
      expect(Calendrier.semestres.erreurs(), isEmpty);
      expect(Calendrier.semestres.periodes.map((p) => p.cle), ['s1', 's2']);
      expect(Calendrier.semestres.periodes[0].mois, [10, 11, 12, 1]);
      expect(Calendrier.semestres.periodes[1].mois, [2, 3, 4, 5, 6]);
    });

    test('les séquences proposées sont valides avec les trimestres', () {
      final c = Calendrier.trimestres.copyWith(sequences: Calendrier.sequencesProposees);
      expect(c.erreurs(), isEmpty);
      expect(c.sequencesActives, isTrue);
      expect(Calendrier.trimestres.sequencesActives, isFalse);
    });
  });

  group('recherche', () {
    final c = Calendrier.trimestres.copyWith(sequences: Calendrier.sequencesProposees);

    test('période et séquence d\'un mois', () {
      expect(c.periodeDuMois(11)!.cle, 't1');
      expect(c.periodeDuMois(1)!.cle, 't2');
      expect(c.periodeDuMois(6)!.cle, 't3');
      expect(c.periodeDuMois(7), isNull);
      expect(c.sequenceDuMois(12)!.cle, 'q2');
      expect(c.sequenceDuMois(2)!.cle, 'q3');
      expect(Calendrier.trimestres.sequenceDuMois(12), isNull);
    });

    test('étendue à partir d\'une clé', () {
      expect(c.portee('annee')!.annuelle, isTrue);
      expect(c.portee('m10')!.moisChoisi, 10);
      expect(c.portee('t2')!.periodeChoisie!.libelle, 'Trimestre 2');
      expect(c.portee('q1')!.periodeChoisie!.mois, [10, 11]);
      expect(c.portee('m7'), isNull);
      expect(c.portee('s1'), isNull);
      expect(c.portee('xyz'), isNull);
    });

    test('clé d\'une étendue', () {
      expect(const Portee.mois(11).cle, 'm11');
      expect(const Portee.annee().cle, 'annee');
      expect(Calendrier.semestres.portee('s2')!.cle, 's2');
    });
  });

  group('validation', () {
    PeriodeScolaire p(String cle, List<int> mois, [String? nom]) =>
        PeriodeScolaire(cle: cle, libelle: nom ?? cle.toUpperCase(), mois: mois);

    Calendrier avec(List<PeriodeScolaire> periodes,
            [List<PeriodeScolaire> sequences = const []]) =>
        Calendrier(
          type: TypePeriodes.personnalise,
          periodes: periodes,
          sequences: sequences,
        );

    test('au moins une période', () {
      expect(avec([]).erreurs(), contains('Il faut au moins une période.'));
    });

    test('une seule période couvrant toute l\'année est valide', () {
      expect(avec([p('a', [10, 11, 12, 1, 2, 3, 4, 5, 6])]).erreurs(), isEmpty);
    });

    test('un mois dans deux périodes est refusé', () {
      final e = avec([
        p('a', [10, 11, 12, 1]),
        p('b', [1, 2, 3, 4, 5, 6]),
      ]).erreurs();
      expect(e.any((m) => m.contains('Janvier') && m.contains('deux')), isTrue);
    });

    test('un mois oublié est signalé', () {
      final e = avec([
        p('a', [10, 11, 12]),
        p('b', [1, 2, 3, 4, 5]),
      ]).erreurs();
      expect(e, ['Juin n\'appartient à aucune période.']);
    });

    test('mois inexistant dans l\'année scolaire', () {
      final e = avec([
        p('a', [7, 10, 11, 12, 1, 2, 3, 4, 5, 6]),
      ]).erreurs();
      expect(e.any((m) => m.contains('mois 7')), isTrue);
    });

    test('période vide, sans nom ou nom trop long', () {
      final e = avec([
        p('a', [10, 11, 12, 1, 2, 3, 4, 5, 6]),
        p('b', [], ' '),
        p('c', [], 'x' * 31),
      ]).erreurs();
      expect(e.any((m) => m.contains('ne contient aucun mois')), isTrue);
      expect(e.any((m) => m.contains('n\'a pas de nom')), isTrue);
      expect(e.any((m) => m.contains('trop long')), isTrue);
    });

    test('identifiants : uniques et non réservés', () {
      final doublons = avec([
        p('a', [10, 11, 12]),
        p('a', [1, 2, 3, 4, 5, 6]),
      ]).erreurs();
      expect(doublons.any((m) => m.contains('même identifiant')), isTrue);
      for (final cle in ['annee', 'm10', ' ']) {
        final e = avec([p(cle, [10, 11, 12, 1, 2, 3, 4, 5, 6])]).erreurs();
        expect(e.any((m) => m.contains('non autorisé')), isTrue, reason: cle);
      }
    });

    test('plus de six périodes refusé', () {
      final sept = [
        p('a', [10]), p('b', [11]), p('c', [12]), p('d', [1]),
        p('e', [2]), p('f', [3]), p('g', [4, 5, 6]),
      ];
      expect(avec(sept).erreurs(), contains('Six périodes au maximum.'));
    });

    test('une séquence ne peut pas chevaucher deux périodes', () {
      final e = Calendrier.trimestres.copyWith(sequences: [
        p('q1', [10, 11, 12, 1]),
        p('q2', [2, 3, 4, 5, 6]),
      ]).erreurs();
      expect(e.where((m) => m.contains('chevauche')).length, 2);
    });

    test('les séquences, si elles existent, doivent couvrir tous les mois', () {
      final e = Calendrier.trimestres.copyWith(sequences: [
        p('q1', [10, 11, 12]),
      ]).erreurs();
      expect(e.any((m) => m.contains('Janvier n\'appartient à aucune séquence')), isTrue);
    });
  });

  group('enregistrement en JSON', () {
    test('aller-retour sans perte', () {
      final c = Calendrier.semestres.copyWith(
        moyenneMensuelle: false,
        sequences: [
          const PeriodeScolaire(cle: 'q1', libelle: 'Séq. 1', mois: [10, 11, 12, 1]),
          const PeriodeScolaire(cle: 'q2', libelle: 'Séq. 2', mois: [2, 3, 4, 5, 6]),
        ],
      );
      final relu = Calendrier.fromJsonString(c.toJsonString());
      expect(relu, c);
      expect(relu.moyenneMensuelle, isFalse);
      expect(relu.type, TypePeriodes.semestres);
    });

    test('un calendrier ancien sans séquences reste lisible', () {
      final c = Calendrier.fromJson({
        'periodes': [
          {'cle': 't1', 'libelle': 'T1', 'mois': [10, 11, 12, 1, 2, 3, 4, 5, 6]},
        ],
      });
      expect(c.sequences, isEmpty);
      expect(c.moyenneMensuelle, isTrue);
      expect(c.erreurs(), isEmpty);
    });

    test('un contenu abîmé lève une erreur', () {
      expect(() => Calendrier.fromJsonString('pas du json'), throwsFormatException);
      expect(() => Calendrier.fromJsonString('{"periodes": 3}'), throwsA(isA<TypeError>()));
    });
  });
}
