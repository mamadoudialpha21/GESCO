import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/calcul_classe.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/modeles.dart';

ClasseResume classeDe(int id, String nom) => ClasseResume(
      classe: Classe(id: id, anneeId: 1, niveau: '10e année', nom: nom),
      nbMatieres: 2,
      nbEleves: 5,
    );

EleveInscrit eleve(
  int id,
  String nom, {
  int classeId = 1,
  StatutInscription statut = StatutInscription.inscrit,
}) =>
    EleveInscrit(
      inscriptionId: id,
      eleveId: id,
      classeId: classeId,
      classeNom: 'Classe $classeId',
      matricule: 'M$id',
      nom: nom,
      prenom: 'X',
      sexe: id.isEven ? 'F' : 'M',
      statut: statut,
    );

MatiereClasse matiere(int id, String nom, {int classeId = 1}) => MatiereClasse(
      id: id,
      classeId: classeId,
      nom: nom,
      coefficient: 100,
      ordre: id,
    );

/// inscription -> matière -> mois -> saisie, pour novembre (mois 11).
Map<int, Map<int, Map<int, Saisie>>> notesNovembre(Map<int, Map<int, int>> notes) => {
      for (final e in notes.entries)
        e.key: {
          for (final m in e.value.entries) m.key: {11: Saisie.valeur(m.value)},
        },
    };

CalculClasse classeA() => CalculClasse(
      classe: classeDe(1, '10e A'),
      eleves: [
        eleve(1, 'BARRY'),
        eleve(2, 'CAMARA'),
        eleve(3, 'DIALLO'),
        eleve(4, 'SOW', statut: StatutInscription.depart),
        eleve(5, 'TOURE'),
      ],
      matieres: [matiere(1, 'Maths'), matiere(2, 'Français')],
      config: ConfigResultats.defaut,
      calendrier: Calendrier.defaut,
      saisies: notesNovembre({
        1: {1: 1600, 2: 1600},
        2: {1: 1400, 2: 1800},
        3: {1: 1400, 2: 600},
        4: {1: 1800, 2: 1800},
      }),
    );

CalculClasse classeAvecMoyenne(int id, int? note) => CalculClasse(
      classe: classeDe(id, 'Classe $id'),
      eleves: [eleve(10 * id, 'ELEVE$id', classeId: id)],
      matieres: [matiere(10 * id, 'Maths', classeId: id)],
      config: ConfigResultats.defaut,
      calendrier: Calendrier.defaut,
      saisies: note == null
          ? const {}
          : notesNovembre({
              10 * id: {10 * id: note},
            }),
    );

void main() {
  const novembre = Portee.mois(11);

  group('lignesClassement - moyenne générale', () {
    test('classés par rang, ex æquo repérés, non classés à la fin', () {
      final lignes = lignesClassement(classeA(), novembre);
      expect([for (final l in lignes) l.eleve.nom],
          ['BARRY', 'CAMARA', 'DIALLO', 'SOW', 'TOURE']);
      expect([for (final l in lignes) l.rang], [1, 1, 3, null, null]);
      expect([for (final l in lignes) l.exAequo], [true, true, false, false, false]);
      expect([for (final l in lignes) l.moyenne], [1600, 1600, 1000, 1800, null]);
      expect([for (final l in lignes) l.classe], [true, true, true, false, false]);
    });

    test('mentions et décisions viennent de la configuration', () {
      final lignes = lignesClassement(classeA(), novembre);
      expect(lignes[0].mention, 'Très bien');
      expect(lignes[0].decision, 'Admis(e)');
      expect(lignes[2].mention, 'Passable');
      expect(lignes[4].mention, '');
      expect(lignes[4].decision, '');
    });

    test('un élève parti garde sa moyenne mais n\'est pas classé', () {
      final sow = lignesClassement(classeA(), novembre).firstWhere((l) => l.eleve.nom == 'SOW');
      expect(sow.moyenne, 1800);
      expect(sow.rang, isNull);
      expect(sow.eleve.actif, isFalse);
    });

    test('la même période en trimestre donne le même classement', () {
      final t1 = Portee.periode(Calendrier.defaut.periodes.first);
      final lignes = lignesClassement(classeA(), t1);
      expect([for (final l in lignes) l.rang], [1, 1, 3, null, null]);
    });

    test('un mois sans note : personne n\'est classé', () {
      final lignes = lignesClassement(classeA(), const Portee.mois(12));
      expect(lignes.every((l) => l.rang == null && l.moyenne == null), isTrue);
      expect([for (final l in lignes) l.eleve.nom],
          ['BARRY', 'CAMARA', 'DIALLO', 'SOW', 'TOURE']);
    });
  });

  group('lignesClassement - par matière', () {
    test('classement dans Maths avec ex æquo, sans décision', () {
      final lignes = lignesClassement(classeA(), novembre, matiereId: 1);
      expect([for (final l in lignes) l.eleve.nom],
          ['BARRY', 'CAMARA', 'DIALLO', 'SOW', 'TOURE']);
      expect([for (final l in lignes) l.rang], [1, 2, 2, null, null]);
      expect([for (final l in lignes) l.exAequo], [false, true, true, false, false]);
      expect([for (final l in lignes) l.moyenne], [1600, 1400, 1400, 1800, null]);
      expect(lignes.every((l) => l.decision.isEmpty), isTrue);
      expect(lignes[1].mention, 'Bien');
    });

    test('matière inconnue : erreur claire', () {
      expect(() => lignesClassement(classeA(), novembre, matiereId: 99), throwsArgumentError);
    });
  });

  group('statistiques d\'une classe', () {
    test('élèves actifs seulement', () {
      final s = classeA().stats(novembre);
      expect(s.effectif, 4);
      expect(s.evalues, 3);
      expect(s.admis, 3);
      expect(s.moyenneClasse, 1400);
      expect(s.meilleureMoyenne, 1600);
      expect(s.plusFaibleMoyenne, 1000);
      expect(s.tauxReussiteCentiemes, 10000);
    });
  });

  group('comparerClasses', () {
    test('rang d\'après la moyenne, classes sans moyenne à la fin', () {
      final resumes = comparerClasses([
        classeAvecMoyenne(1, 1200),
        classeAvecMoyenne(2, null),
        classeAvecMoyenne(3, 1600),
      ], novembre);
      expect([for (final r in resumes) r.classe.classe.id], [3, 1, 2]);
      expect([for (final r in resumes) r.rang], [1, 2, null]);
      expect(resumes.first.stats.moyenneClasse, 1600);
    });

    test('deux classes à égalité ont le même rang, la suivante saute', () {
      final resumes = comparerClasses([
        classeAvecMoyenne(1, 1200),
        classeAvecMoyenne(2, 1600),
        classeAvecMoyenne(3, 1600),
      ], novembre);
      expect([for (final r in resumes) r.classe.classe.id], [2, 3, 1]);
      expect([for (final r in resumes) r.rang], [1, 1, 3]);
    });

    test('liste vide', () {
      expect(comparerClasses(const [], novembre), isEmpty);
    });
  });
}
