import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/moteur_resultats.dart';
import 'package:gesco/domain/statistiques.dart';

DonneesEleve eleve(int id, String sexe) => DonneesEleve(
      inscriptionId: id,
      nom: 'NOM$id',
      prenom: 'Prénom',
      sexe: sexe,
      saisies: const {},
    );

ResultatEleve resultat(int id, int? moyenne, ConfigResultats config) =>
    ResultatEleve(
      inscriptionId: id,
      moyenne: moyenne,
      rang: null,
      mention: moyenne == null ? '' : config.mention(moyenne),
      decision: '',
      incomplet: false,
    );

void main() {
  const config = ConfigResultats.defaut;

  test('classe de 5 élèves dont un sans note', () {
    final eleves = [
      eleve(1, 'F'),
      eleve(2, 'M'),
      eleve(3, 'F'),
      eleve(4, 'M'),
      eleve(5, 'F'),
    ];
    final moyennes = [1500, 1500, 1400, null, 1300];
    final stats = calculerStats(
      eleves: eleves,
      resultats: [
        for (var i = 0; i < 5; i++) resultat(i + 1, moyennes[i], config),
      ],
      config: config,
    );

    expect(stats.effectif, 5);
    expect(stats.filles, 3);
    expect(stats.garcons, 2);
    expect(stats.evalues, 4);
    expect(stats.admis, 4);
    expect(stats.nonAdmis, 0);
    expect(stats.moyenneClasse, 1425); // (1500+1500+1400+1300) / 4
    expect(stats.meilleureMoyenne, 1500);
    expect(stats.plusFaibleMoyenne, 1300);
    expect(stats.tauxReussiteCentiemes, 10000); // 100,00 %
    expect(stats.repartitionMentions, {
      sansMention: 0,
      'Passable': 0,
      'Assez bien': 1,
      'Bien': 3,
      'Très bien': 0,
      'Excellent': 0,
    });
  });

  test('admis, non admis et taux de réussite', () {
    final stats = calculerStats(
      eleves: [eleve(1, 'M'), eleve(2, 'F'), eleve(3, 'F')],
      resultats: [
        resultat(1, 900, config),
        resultat(2, 1000, config), // exactement le seuil : admis
        resultat(3, null, config),
      ],
      config: config,
    );
    expect(stats.evalues, 2);
    expect(stats.admis, 1);
    expect(stats.nonAdmis, 1);
    expect(stats.tauxReussiteCentiemes, 5000); // 50,00 %
    expect(stats.moyenneClasse, 950);
    expect(stats.repartitionMentions[sansMention], 1);
    expect(stats.repartitionMentions['Passable'], 1);
  });

  test('taux arrondi : 2 admis sur 3 = 66,67 %', () {
    final stats = calculerStats(
      eleves: [eleve(1, 'M'), eleve(2, 'M'), eleve(3, 'M')],
      resultats: [
        resultat(1, 1500, config),
        resultat(2, 1100, config),
        resultat(3, 700, config),
      ],
      config: config,
    );
    expect(stats.tauxReussiteCentiemes, 6667);
  });

  test('moyenne de classe arrondie demi vers le haut', () {
    final stats = calculerStats(
      eleves: [eleve(1, 'M'), eleve(2, 'M'), eleve(3, 'M')],
      resultats: [
        resultat(1, 1000, config),
        resultat(2, 1000, config),
        resultat(3, 1001, config),
      ],
      config: config,
    );
    expect(stats.moyenneClasse, 1000); // 1000,33 -> 1000
  });

  test('classe vide ou sans aucune moyenne', () {
    final vide = calculerStats(eleves: [], resultats: [], config: config);
    expect(vide.effectif, 0);
    expect(vide.moyenneClasse, isNull);
    expect(vide.meilleureMoyenne, isNull);
    expect(vide.plusFaibleMoyenne, isNull);
    expect(vide.tauxReussiteCentiemes, isNull);

    final sansNotes = calculerStats(
      eleves: [eleve(1, 'F')],
      resultats: [resultat(1, null, config)],
      config: config,
    );
    expect(sansNotes.effectif, 1);
    expect(sansNotes.evalues, 0);
    expect(sansNotes.admis, 0);
    expect(sansNotes.tauxReussiteCentiemes, isNull);
  });
}
