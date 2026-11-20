/// Statistiques de classe pour une période (mois, trimestre ou année).
library;

import 'arrondi.dart';
import 'modeles.dart';
import 'moteur_resultats.dart';

/// Clé de [StatsClasse.repartitionMentions] pour les élèves sans mention.
const String sansMention = '';

class StatsClasse {
  const StatsClasse({
    required this.effectif,
    required this.filles,
    required this.garcons,
    required this.evalues,
    required this.admis,
    required this.nonAdmis,
    required this.moyenneClasse,
    required this.meilleureMoyenne,
    required this.plusFaibleMoyenne,
    required this.tauxReussiteCentiemes,
    required this.repartitionMentions,
  });

  /// Nombre total d'élèves inscrits dans la classe.
  final int effectif;
  final int filles;
  final int garcons;

  /// Élèves ayant une moyenne pour la période.
  final int evalues;

  /// Élèves évalués dont la moyenne atteint le seuil d'admission.
  final int admis;
  final int nonAdmis;

  /// Moyenne de la classe (centièmes), null si personne n'est évalué.
  final int? moyenneClasse;
  final int? meilleureMoyenne;
  final int? plusFaibleMoyenne;

  /// Taux de réussite en centièmes de pourcent (6667 = 66,67 %), calculé sur
  /// les élèves évalués. Null si personne n'est évalué.
  final int? tauxReussiteCentiemes;

  /// Nombre d'élèves évalués par mention. La clé [sansMention] regroupe ceux
  /// qui n'ont aucune mention.
  final Map<String, int> repartitionMentions;
}

StatsClasse calculerStats({
  required List<DonneesEleve> eleves,
  required List<ResultatEleve> resultats,
  required ConfigResultats config,
}) {
  // Les élèves partis ou ayant abandonné ne comptent pas.
  final inactifs = {
    for (final e in eleves)
      if (!e.actif) e.inscriptionId,
  };
  final actifs = [for (final e in eleves) if (e.actif) e];
  final filles = actifs.where((e) => e.sexe == 'F').length;
  final garcons = actifs.where((e) => e.sexe == 'M').length;

  final evalues = resultats
      .where((r) => r.moyenne != null && !inactifs.contains(r.inscriptionId))
      .toList();
  final moyennes = [for (final r in evalues) r.moyenne!];
  final admis = moyennes.where((m) => m >= config.seuilAdmission).length;

  final repartition = <String, int>{sansMention: 0};
  final mentionsTriees = [...config.mentions]
    ..sort((a, b) => a.seuil.compareTo(b.seuil));
  for (final palier in mentionsTriees) {
    repartition.putIfAbsent(palier.libelle, () => 0);
  }
  for (final r in evalues) {
    repartition[r.mention] = (repartition[r.mention] ?? 0) + 1;
  }

  final somme = moyennes.fold(0, (a, b) => a + b);

  return StatsClasse(
    effectif: actifs.length,
    filles: filles,
    garcons: garcons,
    evalues: evalues.length,
    admis: admis,
    nonAdmis: evalues.length - admis,
    moyenneClasse:
        moyennes.isEmpty ? null : divisionArrondie(somme, moyennes.length),
    meilleureMoyenne:
        moyennes.isEmpty ? null : moyennes.reduce((a, b) => a > b ? a : b),
    plusFaibleMoyenne:
        moyennes.isEmpty ? null : moyennes.reduce((a, b) => a < b ? a : b),
    tauxReussiteCentiemes: evalues.isEmpty
        ? null
        : divisionArrondie(admis * 10000, evalues.length),
    repartitionMentions: repartition,
  );
}
