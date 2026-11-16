/// Moteur de calcul des moyennes, rangs, mentions et décisions.
///
/// Règles (détaillées dans docs/REGLES_DE_CALCUL.md) :
/// - moyenne d'un mois = somme(note x coefficient) / somme(coefficients), sur
///   les seules matières ayant une note chiffrée ;
/// - une note non saisie, absente ou dispensée n'est JAMAIS comptée comme zéro ;
/// - chaque moyenne publiée est arrondie à 2 décimales (demi vers le haut) ;
///   les moyennes de niveau supérieur sont calculées à partir des moyennes
///   publiées du niveau inférieur (vérifiable à la main sur les documents) ;
/// - trimestre = moyenne des moyennes mensuelles disponibles ;
///   année = moyenne des moyennes trimestrielles disponibles ;
/// - rang : classement par moyenne décroissante, ex æquo = même rang
///   (1, 1, 3 ...).
library;

import 'arrondi.dart';
import 'modeles.dart';
import 'periodes.dart';

/// Résultat d'un élève pour une période (mois, trimestre ou année).
class ResultatEleve {
  const ResultatEleve({
    required this.inscriptionId,
    required this.moyenne,
    required this.rang,
    required this.mention,
    required this.decision,
    required this.incomplet,
  });

  final int inscriptionId;

  /// Moyenne en centièmes, ou null si aucune note chiffrée n'existe.
  final int? moyenne;

  /// Rang (1 = premier), ou null si l'élève n'a pas de moyenne.
  final int? rang;

  /// Mention (chaîne vide si aucune ou si pas de moyenne).
  final String mention;

  /// Décision (chaîne vide si pas de moyenne).
  final String decision;

  /// Vrai s'il manque des notes (matière non saisie ou absent, mois sans
  /// moyenne...). Le résultat est calculé sur les données disponibles.
  final bool incomplet;
}

/// Calcule les rangs avec ex æquo (classement « olympique » : 1, 1, 3).
/// Les élèves sans moyenne (valeur null) n'ont pas de rang.
Map<int, int> calculerRangs(Map<int, int?> moyennes) {
  final valides = <MapEntry<int, int>>[
    for (final entree in moyennes.entries)
      if (entree.value != null) MapEntry(entree.key, entree.value!),
  ];
  valides.sort((a, b) {
    final comparaison = b.value.compareTo(a.value);
    return comparaison != 0 ? comparaison : a.key.compareTo(b.key);
  });

  final rangs = <int, int>{};
  int? precedente;
  var rangCourant = 0;
  for (var i = 0; i < valides.length; i++) {
    if (valides[i].value != precedente) {
      rangCourant = i + 1;
      precedente = valides[i].value;
    }
    rangs[valides[i].key] = rangCourant;
  }
  return rangs;
}

class MoteurResultats {
  MoteurResultats({
    required this.matieres,
    required this.eleves,
    this.config = ConfigResultats.defaut,
  }) : assert(
          eleves.map((e) => e.inscriptionId).toSet().length == eleves.length,
          'Deux élèves ont le même identifiant d\'inscription.',
        );

  final List<MatiereCoef> matieres;
  final List<DonneesEleve> eleves;
  final ConfigResultats config;

  // ---------------------------------------------------------------- Mois

  /// Moyenne mensuelle (centièmes), ou null si aucune note chiffrée.
  int? moyenneMois(DonneesEleve eleve, int mois) {
    _verifierMois(mois);
    var somme = 0;
    var coefficients = 0;
    for (final matiere in matieres) {
      final saisie = eleve.saisie(matiere.id, mois);
      if (saisie != null && saisie.estNumerique) {
        somme += saisie.centiemes! * matiere.coefficient;
        coefficients += matiere.coefficient;
      }
    }
    if (coefficients == 0) return null;
    return divisionArrondie(somme, coefficients);
  }

  /// Vrai s'il manque une note (non saisie ou absent) pour au moins une
  /// matière. Une matière « dispensé » n'est pas un manque.
  bool moisIncomplet(DonneesEleve eleve, int mois) {
    _verifierMois(mois);
    for (final matiere in matieres) {
      final saisie = eleve.saisie(matiere.id, mois);
      if (saisie == null || saisie.etat == EtatNote.absent) return true;
    }
    return false;
  }

  // ----------------------------------------------------------- Trimestre

  /// Moyenne du trimestre : moyenne des moyennes mensuelles disponibles.
  int? moyenneTrimestre(DonneesEleve eleve, int trimestre) {
    final valeurs = <int>[];
    for (final mois in _moisDuTrimestre(trimestre)) {
      final v = moyenneMois(eleve, mois);
      if (v != null) valeurs.add(v);
    }
    return _moyenneDe(valeurs);
  }

  /// Vrai si un des mois du trimestre n'a pas de moyenne ou est incomplet.
  bool trimestreIncomplet(DonneesEleve eleve, int trimestre) {
    return _moisDuTrimestre(trimestre).any(
      (mois) => moyenneMois(eleve, mois) == null || moisIncomplet(eleve, mois),
    );
  }

  /// Note d'une matière pour un trimestre (bulletin) : moyenne de ses notes
  /// mensuelles chiffrées, ou null s'il n'y en a aucune.
  int? noteMatiereTrimestre(DonneesEleve eleve, int matiereId, int trimestre) {
    final valeurs = <int>[];
    for (final mois in _moisDuTrimestre(trimestre)) {
      final saisie = eleve.saisie(matiereId, mois);
      if (saisie != null && saisie.estNumerique) {
        valeurs.add(saisie.centiemes!);
      }
    }
    return _moyenneDe(valeurs);
  }

  // --------------------------------------------------------------- Année

  /// Moyenne annuelle : moyenne des moyennes trimestrielles disponibles.
  int? moyenneAnnuelle(DonneesEleve eleve) {
    final valeurs = <int>[];
    for (final trimestre in trimestres) {
      final v = moyenneTrimestre(eleve, trimestre);
      if (v != null) valeurs.add(v);
    }
    return _moyenneDe(valeurs);
  }

  bool anneeIncomplete(DonneesEleve eleve) {
    return trimestres.any(
      (t) => moyenneTrimestre(eleve, t) == null || trimestreIncomplet(eleve, t),
    );
  }

  // ------------------------------------------------- Résultats de la classe

  List<ResultatEleve> resultatsMois(int mois) {
    _verifierMois(mois);
    return _construire(
      moyenne: (e) => moyenneMois(e, mois),
      incomplet: (e) => moisIncomplet(e, mois),
      annuel: false,
    );
  }

  List<ResultatEleve> resultatsTrimestre(int trimestre) {
    _moisDuTrimestre(trimestre); // valide le numéro
    return _construire(
      moyenne: (e) => moyenneTrimestre(e, trimestre),
      incomplet: (e) => trimestreIncomplet(e, trimestre),
      annuel: false,
    );
  }

  List<ResultatEleve> resultatsAnnee() {
    return _construire(
      moyenne: moyenneAnnuelle,
      incomplet: anneeIncomplete,
      annuel: true,
    );
  }

  List<ResultatEleve> _construire({
    required int? Function(DonneesEleve) moyenne,
    required bool Function(DonneesEleve) incomplet,
    required bool annuel,
  }) {
    final moyennes = <int, int?>{
      for (final e in eleves) e.inscriptionId: moyenne(e),
    };
    final rangs = calculerRangs(moyennes);

    return [
      for (final e in eleves)
        _resultat(
          e,
          moyennes[e.inscriptionId],
          rangs[e.inscriptionId],
          incomplet(e),
          annuel: annuel,
        ),
    ];
  }

  ResultatEleve _resultat(
    DonneesEleve eleve,
    int? moyenne,
    int? rang,
    bool incomplet, {
    required bool annuel,
  }) {
    return ResultatEleve(
      inscriptionId: eleve.inscriptionId,
      moyenne: moyenne,
      rang: rang,
      mention: moyenne == null ? '' : config.mention(moyenne),
      decision: moyenne == null
          ? ''
          : (annuel
              ? config.decisionAnnee(moyenne)
              : config.decisionPeriode(moyenne)),
      incomplet: incomplet,
    );
  }

  // ------------------------------------------------------------ Utilitaires

  static int? _moyenneDe(List<int> valeurs) {
    if (valeurs.isEmpty) return null;
    final somme = valeurs.fold(0, (a, b) => a + b);
    return divisionArrondie(somme, valeurs.length);
  }

  static List<int> _moisDuTrimestre(int trimestre) {
    final mois = moisDuTrimestre[trimestre];
    if (mois == null) {
      throw ArgumentError.value(trimestre, 'trimestre', 'doit être 1, 2 ou 3');
    }
    return mois;
  }

  static void _verifierMois(int mois) {
    if (!moisScolaires.contains(mois)) {
      throw ArgumentError.value(
        mois,
        'mois',
        'hors année scolaire (octobre à juin)',
      );
    }
  }
}
