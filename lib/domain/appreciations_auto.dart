/// Appréciations générées automatiquement d'après les notes et le classement.
///
/// Dart pur. Les textes sont volontairement neutres (« l'élève ») pour être
/// justes quel que soit le sexe, courts pour tenir sur un bulletin, et ne
/// dépassent jamais [longueurMaxAppreciation] caractères (limite de saisie de
/// l'appréciation générale).
///
/// Les seuils s'appuient sur la configuration de l'année : le seuil
/// d'admission sépare les résultats « insuffisants » des résultats
/// « passables », le seuil « bon » sépare « passables » et « satisfaisants ».
/// Au-dessus, les paliers 14, 16 et 18 sur 20 sont fixes.
library;

/// Longueur maximale d'une appréciation générée (celle de la saisie manuelle).
const int longueurMaxAppreciation = 400;

/// Longueur maximale d'une appréciation de matière générée.
const int longueurMaxAppreciationMatiere = 200;

/// Données d'un élève utilisées pour rédiger son appréciation générale.
///
/// Toutes les moyennes sont en centièmes de points sur 20 (1450 = 14,50).
class EntreeAppreciation {
  const EntreeAppreciation({
    required this.moyenne,
    this.rang,
    this.exAequo = false,
    this.effectif = 0,
    this.moyennePrecedente,
    this.sexe = '',
    this.matieresFortes = const [],
    this.matieresFaibles = const [],
    this.seuilAdmission = 1000,
    this.seuilBon = 1200,
  });

  /// Moyenne de la période ; sans moyenne, aucune appréciation n'est produite.
  final int? moyenne;

  /// Rang dans la classe (1 = premier) et nombre d'élèves classés.
  final int? rang;
  final bool exAequo;
  final int effectif;

  /// Moyenne de la période comparable précédente (mois ou trimestre
  /// précédent), si elle existe.
  final int? moyennePrecedente;

  /// « F » ou « M » : sert uniquement à écrire « Première » / « Premier ».
  final String sexe;

  /// Noms des matières où l'élève réussit le mieux / le moins bien.
  final List<String> matieresFortes;
  final List<String> matieresFaibles;

  final int seuilAdmission;
  final int seuilBon;
}

/// Phrase décrivant le niveau d'une moyenne.
String _niveau(int m, int admission, int bon) {
  if (m < admission) {
    if (m >= admission - 200) {
      return 'Résultats insuffisants mais proches de la moyenne : '
          'quelques efforts suffiront.';
    }
    if (m >= 500) {
      return 'Résultats insuffisants : le travail doit être nettement renforcé.';
    }
    return 'Résultats très faibles : un travail personnel sérieux et un suivi '
        'régulier sont indispensables.';
  }
  if (m >= 1800) return 'Résultats excellents, félicitations.';
  if (m >= 1600) return 'Très bons résultats, il faut continuer ainsi.';
  if (m >= 1400) return 'Bons résultats, encouragements.';
  if (m >= bon) return 'Résultats satisfaisants.';
  return 'Résultats passables : l\'élève peut mieux faire.';
}

String? _phraseRang(EntreeAppreciation e) {
  final rang = e.rang;
  final moyenne = e.moyenne;
  if (rang == null || moyenne == null || e.effectif < 4) return null;
  if (rang == 1 && moyenne >= e.seuilAdmission) {
    final premier = e.sexe == 'F' ? 'Première' : 'Premier';
    return e.exAequo ? '$premier ex æquo de la classe.' : '$premier de la classe.';
  }
  if (rang <= 3 && e.effectif >= 6 && moyenne >= e.seuilAdmission) {
    return 'Se classe parmi les trois premiers de la classe.';
  }
  // Un quart de l'effectif (arrondi vers le haut).
  final quart = (e.effectif + 3) ~/ 4;
  if (e.effectif >= 8 && rang <= quart && moyenne >= e.seuilAdmission) {
    return 'Se classe parmi les meilleurs de la classe.';
  }
  if (e.effectif >= 8 && rang > e.effectif - quart && moyenne < e.seuilBon) {
    return 'Se classe dans le dernier quart de la classe : des efforts sont attendus.';
  }
  return null;
}

String? _phraseEvolution(EntreeAppreciation e) {
  final m = e.moyenne;
  final p = e.moyennePrecedente;
  if (m == null || p == null) return null;
  final ecart = m - p;
  if (ecart >= 100) return 'En progrès par rapport à la période précédente.';
  if (ecart <= -100) {
    return m >= e.seuilBon
        ? 'Léger fléchissement par rapport à la période précédente.'
        : 'En baisse par rapport à la période précédente : il faut se ressaisir.';
  }
  return null;
}

String _liste(List<String> noms) => noms.length <= 1
    ? noms.join()
    : '${noms.sublist(0, noms.length - 1).join(', ')} et ${noms.last}';

/// Appréciation générale d'un élève, ou chaîne vide s'il n'a pas de moyenne.
///
/// La phrase de niveau vient toujours en premier ; viennent ensuite, tant que
/// la longueur le permet : le rang, l'évolution, les points forts et les
/// matières à renforcer.
String appreciationGenerale(EntreeAppreciation e) {
  final moyenne = e.moyenne;
  if (moyenne == null) return '';
  final rang = _phraseRang(e);
  final evolution = _phraseEvolution(e);
  final parties = <String>[
    _niveau(moyenne, e.seuilAdmission, e.seuilBon),
    if (rang != null) rang,
    if (evolution != null) evolution,
    if (e.matieresFortes.isNotEmpty) 'Points forts : ${_liste(e.matieresFortes)}.',
    if (e.matieresFaibles.isNotEmpty) 'À renforcer : ${_liste(e.matieresFaibles)}.',
  ];
  var texte = parties.join(' ');
  // Sécurité : on retire les derniers éléments facultatifs jusqu'à tenir.
  while (texte.length > longueurMaxAppreciation && parties.length > 1) {
    parties.removeLast();
    texte = parties.join(' ');
  }
  return texte;
}

/// Appréciation d'une matière d'après la note de l'élève (centièmes sur 20),
/// ou chaîne vide s'il n'a pas de note chiffrée.
String appreciationMatiere(
  int? note, {
  int seuilAdmission = 1000,
  int seuilBon = 1200,
}) {
  if (note == null) return '';
  if (note < seuilAdmission) {
    if (note >= seuilAdmission - 200) return 'Insuffisant, proche de la moyenne';
    if (note >= 500) return 'Insuffisant, des efforts s\'imposent';
    return 'Très faible, travail à reprendre';
  }
  if (note >= 1800) return 'Excellent travail';
  if (note >= 1600) return 'Très bon travail';
  if (note >= 1400) return 'Bon travail';
  if (note >= seuilBon) return 'Travail satisfaisant';
  return 'Passable, peut mieux faire';
}
