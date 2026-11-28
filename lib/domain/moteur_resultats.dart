/// Moteur de calcul des moyennes, rangs, mentions et décisions.
///
/// Règles (détaillées dans docs/REGLES_DE_CALCUL.md) :
/// - moyenne d'un mois = somme(note x coefficient) / somme(coefficients), sur
///   les seules matières ayant une note chiffrée ;
/// - une note non saisie, absente ou dispensée n'est JAMAIS comptée comme zéro ;
/// - chaque moyenne publiée est arrondie à 2 décimales (demi vers le haut) ;
///   les moyennes de niveau supérieur sont calculées à partir des moyennes
///   publiées du niveau inférieur (vérifiable à la main sur les documents) ;
/// - période (trimestre, semestre, séquence) = moyenne des moyennes
///   mensuelles disponibles de ses mois ; année = moyenne des moyennes de
///   périodes disponibles ;
/// - période avec composition (semestres du collège et du lycée) :
///   (poids × composition + moyenne des autres mois) ÷ (poids + 1), la moyenne
///   des autres mois étant arrondie avant d'être combinée ;
/// - compositions (maternelle, primaire) : chaque composition est un mois ;
///   la note finale est la moyenne des moyennes des compositions ;
/// - avec un calendrier « moyenne simple » ([Calendrier.ponderee] faux), les
///   coefficients sont ignorés : chaque matière notée compte pour 1 ;
/// - les matières facultatives ne comptent pas dans les moyennes générales ;
/// - rang : classement par moyenne décroissante, ex æquo = même rang
///   (1, 1, 3 ...).
library;

import 'arrondi.dart';
import 'calendrier.dart';
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

/// Note et rang d'un élève dans une matière (classement par matière).
class ResultatMatiere {
  const ResultatMatiere({
    required this.inscriptionId,
    required this.note,
    required this.rang,
  });

  final int inscriptionId;

  /// Note sur 20 en centièmes, ou null si l'élève n'a pas de note chiffrée.
  final int? note;

  /// Rang dans la matière (1 = premier), ou null sans note.
  final int? rang;
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
    this.calendrier = Calendrier.defaut,
  }) : assert(
          eleves.map((e) => e.inscriptionId).toSet().length == eleves.length,
          'Deux élèves ont le même identifiant d\'inscription.',
        );

  final List<MatiereCoef> matieres;
  final List<DonneesEleve> eleves;
  final ConfigResultats config;
  final Calendrier calendrier;

  /// Matières qui comptent dans les moyennes générales.
  Iterable<MatiereCoef> get _matieresComptees =>
      matieres.where((m) => !m.facultative);

  /// Poids d'une matière dans la moyenne : son coefficient, ou 1 en moyenne
  /// simple (coefficients ignorés).
  int _poids(MatiereCoef matiere) => calendrier.ponderee ? matiere.coefficient : 1;

  // ---------------------------------------------------------------- Mois

  /// Note retenue pour une matière et un mois (centièmes) : la note chiffrée,
  /// 0 pour un absent si l'option « absence = zéro » est active, sinon null
  /// (non saisie, dispensé, ou absent ignoré).
  int? _valeur(DonneesEleve eleve, int matiereId, int mois) {
    final saisie = eleve.saisie(matiereId, mois);
    if (saisie == null) return null;
    if (saisie.estNumerique) return saisie.centiemes;
    if (saisie.etat == EtatNote.absent && config.absenceEgaleZero) return 0;
    return null;
  }

  /// Moyenne mensuelle (centièmes), ou null si aucune note chiffrée.
  int? moyenneMois(DonneesEleve eleve, int mois) {
    _verifierMois(mois);
    var somme = 0;
    var coefficients = 0;
    for (final matiere in _matieresComptees) {
      final valeur = _valeur(eleve, matiere.id, mois);
      if (valeur != null) {
        somme += valeur * _poids(matiere);
        coefficients += _poids(matiere);
      }
    }
    if (coefficients == 0) return null;
    return divisionArrondie(somme, coefficients);
  }

  /// Vrai s'il manque une note (non saisie, ou absent quand l'absence ne
  /// compte pas pour zéro) pour au moins une matière. Une matière
  /// « dispensé » n'est pas un manque.
  bool moisIncomplet(DonneesEleve eleve, int mois) {
    _verifierMois(mois);
    for (final matiere in _matieresComptees) {
      final saisie = eleve.saisie(matiere.id, mois);
      if (saisie == null) return true;
      if (saisie.etat == EtatNote.absent && !config.absenceEgaleZero) return true;
    }
    return false;
  }

  // ------------------------------------------------- Périodes et année

  /// Moyenne sur une étendue (mois, période, séquence ou année).
  int? moyenne(DonneesEleve eleve, Portee portee) {
    if (portee.estMois) return moyenneMois(eleve, portee.moisChoisi!);
    if (portee.estPeriode) return _moyennePeriode(eleve, portee.periodeChoisie!);
    return _moyenneDes([
      for (final p in calendrier.periodes) moyenne(eleve, Portee.periode(p)),
    ]);
  }

  /// Moyenne d'une période : moyenne de ses mois, ou, quand elle a une
  /// composition, (poids × composition + moyenne des autres mois) ÷ (poids + 1).
  int? _moyennePeriode(DonneesEleve eleve, PeriodeScolaire periode) {
    final compo = periode.moisCompo;
    if (compo == null || !periode.mois.contains(compo)) {
      return _moyenneDes([for (final mois in periode.mois) moyenneMois(eleve, mois)]);
    }
    return _combinerCompo(
      moyenneMois(eleve, compo),
      [for (final mois in periode.mois) if (mois != compo) moyenneMois(eleve, mois)],
      periode.poidsCompo,
    );
  }

  /// Moyenne des mois d'une période avec composition, sans la composition
  /// (octobre, novembre et décembre pour le semestre 1), arrondie. Null si
  /// la période n'a pas de composition ou si aucun de ces mois n'a de moyenne.
  int? moyenneMoisHorsCompo(DonneesEleve eleve, PeriodeScolaire periode) {
    final compo = periode.moisCompo;
    if (compo == null) return null;
    final valeurs = <int>[];
    for (final mois in periode.mois) {
      if (mois == compo) continue;
      final m = moyenneMois(eleve, mois);
      if (m != null) valeurs.add(m);
    }
    return _moyenneDe(valeurs);
  }

  /// Combine la composition et la moyenne des autres mois. Une partie absente
  /// est ignorée (le résultat reste calculé, et signalé incomplet ailleurs) ;
  /// avec « période complète exigée », il n'y a pas de moyenne.
  int? _combinerCompo(int? compo, List<int?> autres, int poids) {
    if (config.exigerPeriodeComplete && (compo == null || autres.any((v) => v == null))) {
      return null;
    }
    final moyenneAutres = _moyenneDe([for (final v in autres) if (v != null) v]);
    if (compo != null && moyenneAutres != null) {
      return divisionArrondie(poids * compo + moyenneAutres, poids + 1);
    }
    return compo ?? moyenneAutres;
  }

  /// Vrai s'il manque des notes dans l'étendue : un mois sans moyenne ou
  /// incomplet, ou une période incomplète pour l'année.
  bool incomplet(DonneesEleve eleve, Portee portee) {
    if (portee.estMois) return moisIncomplet(eleve, portee.moisChoisi!);
    if (portee.estPeriode) {
      return portee.periodeChoisie!.mois.any(
        (mois) => moyenneMois(eleve, mois) == null || moisIncomplet(eleve, mois),
      );
    }
    return calendrier.periodes.any(
      (p) => moyenne(eleve, Portee.periode(p)) == null ||
          incomplet(eleve, Portee.periode(p)),
    );
  }

  /// Note d'une matière sur une étendue : moyenne de ses notes mensuelles
  /// chiffrées (période), ou moyenne de ses notes de période (année). Null
  /// s'il n'y en a aucune.
  int? noteMatiere(DonneesEleve eleve, int matiereId, Portee portee) {
    if (portee.estMois) {
      _verifierMois(portee.moisChoisi!);
      return _valeur(eleve, matiereId, portee.moisChoisi!);
    }
    if (portee.estPeriode) {
      final periode = portee.periodeChoisie!;
      final compo = periode.moisCompo;
      if (compo == null || !periode.mois.contains(compo)) {
        return _moyenneDes([
          for (final mois in periode.mois) _valeur(eleve, matiereId, mois),
        ]);
      }
      return _combinerCompo(
        _valeur(eleve, matiereId, compo),
        [
          for (final mois in periode.mois)
            if (mois != compo) _valeur(eleve, matiereId, mois),
        ],
        periode.poidsCompo,
      );
    }
    return _moyenneDes([
      for (final p in calendrier.periodes)
        noteMatiere(eleve, matiereId, Portee.periode(p)),
    ]);
  }

  /// Résultats de toute la classe sur une étendue (moyenne, rang, mention,
  /// décision). Les décisions « année » ne s'appliquent qu'à l'année entière.
  List<ResultatEleve> resultats(Portee portee) {
    if (portee.estMois) _verifierMois(portee.moisChoisi!);
    return _construire(
      moyenne: (e) => moyenne(e, portee),
      incomplet: (e) => incomplet(e, portee),
      annuel: portee.annuelle,
    );
  }

  /// Classement des élèves dans une matière sur une étendue (élèves actifs
  /// seulement : un élève parti garde sa note mais n'a pas de rang).
  List<ResultatMatiere> classementMatiere(int matiereId, Portee portee) {
    if (!matieres.any((m) => m.id == matiereId)) {
      throw ArgumentError.value(matiereId, 'matiereId', 'matière inconnue');
    }
    final notes = <int, int?>{
      for (final e in eleves) e.inscriptionId: noteMatiere(e, matiereId, portee),
    };
    // Comme pour la moyenne générale, les élèves partis ou ayant abandonné ne
    // sont pas classés.
    final rangs = calculerRangs({
      for (final e in eleves)
        if (e.actif) e.inscriptionId: notes[e.inscriptionId],
    });
    return [
      for (final e in eleves)
        ResultatMatiere(
          inscriptionId: e.inscriptionId,
          note: notes[e.inscriptionId],
          rang: rangs[e.inscriptionId],
        ),
    ];
  }

  // ---------------------------- Raccourcis (trimestres, numérotés à partir de 1)

  PeriodeScolaire _periodeNumero(int numero) {
    if (numero < 1 || numero > calendrier.periodes.length) {
      throw ArgumentError.value(
        numero,
        'trimestre',
        'doit être entre 1 et ${calendrier.periodes.length}',
      );
    }
    return calendrier.periodes[numero - 1];
  }

  /// Moyenne de la période numéro [trimestre] (1 = première période).
  int? moyenneTrimestre(DonneesEleve eleve, int trimestre) =>
      moyenne(eleve, Portee.periode(_periodeNumero(trimestre)));

  bool trimestreIncomplet(DonneesEleve eleve, int trimestre) =>
      incomplet(eleve, Portee.periode(_periodeNumero(trimestre)));

  int? noteMatiereTrimestre(DonneesEleve eleve, int matiereId, int trimestre) =>
      noteMatiere(eleve, matiereId, Portee.periode(_periodeNumero(trimestre)));

  int? moyenneAnnuelle(DonneesEleve eleve) => moyenne(eleve, const Portee.annee());

  bool anneeIncomplete(DonneesEleve eleve) =>
      incomplet(eleve, const Portee.annee());

  List<ResultatEleve> resultatsMois(int mois) => resultats(Portee.mois(mois));

  List<ResultatEleve> resultatsTrimestre(int trimestre) =>
      resultats(Portee.periode(_periodeNumero(trimestre)));

  List<ResultatEleve> resultatsAnnee() => resultats(const Portee.annee());

  List<ResultatEleve> _construire({
    required int? Function(DonneesEleve) moyenne,
    required bool Function(DonneesEleve) incomplet,
    required bool annuel,
  }) {
    final moyennes = <int, int?>{
      for (final e in eleves) e.inscriptionId: moyenne(e),
    };
    // Les élèves partis ou ayant abandonné ne sont pas classés et ne
    // décalent pas le rang des autres.
    final rangs = calculerRangs({
      for (final e in eleves)
        if (e.actif) e.inscriptionId: moyennes[e.inscriptionId],
    });

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

  /// Moyenne des valeurs disponibles ; avec l'option « période complète »,
  /// null dès qu'une valeur manque.
  int? _moyenneDes(List<int?> valeurs) {
    if (config.exigerPeriodeComplete && valeurs.any((v) => v == null)) return null;
    return _moyenneDe([for (final v in valeurs) if (v != null) v]);
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
