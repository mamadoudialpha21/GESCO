/// Niveaux d'études, cycles (primaire, collège, lycée) et options du lycée.
///
/// Dart pur : utilisé par la base de données, le calcul et l'interface.
///
/// Organisation retenue (système guinéen) :
/// - primaire : 1re à 6e année (codes 1 à 6) ;
/// - collège : 7e à 10e année (codes 7 à 10) ;
/// - lycée : 11e année, 12e année et Terminale (codes 11 à 13), avec trois
///   options : sciences sociales, sciences expérimentales, sciences
///   mathématiques.
library;

import 'recherche.dart';

/// Cycle d'études.
enum Cycle {
  primaire('primaire', 'Primaire'),
  college('college', 'Collège'),
  lycee('lycee', 'Lycée');

  const Cycle(this.cle, this.libelle);

  /// Identifiant stocké dans la base.
  final String cle;
  final String libelle;

  /// Cycle correspondant à [cle], ou null.
  static Cycle? depuisCle(String? cle) {
    for (final c in values) {
      if (c.cle == cle) return c;
    }
    return null;
  }
}

/// Option (série) du lycée.
enum SerieLycee {
  sciencesSociales('SS', 'Sciences sociales'),
  sciencesExperimentales('SE', 'Sciences expérimentales'),
  sciencesMathematiques('SM', 'Sciences mathématiques');

  const SerieLycee(this.code, this.libelle);

  /// Code court stocké dans la base (SS, SE, SM).
  final String code;
  final String libelle;

  /// Option correspondant à [code], ou null (y compris pour une chaîne vide).
  static SerieLycee? depuisCode(String? code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Un niveau d'études : 1re année... Terminale.
class NiveauScolaire {
  const NiveauScolaire(this.code, this.libelle, this.abrege, this.cycle);

  /// 1 à 13 (13 = Terminale).
  final int code;

  /// Nom complet (« 7ème année », « Terminale »).
  final String libelle;

  /// Nom court pour les noms de classe et les tableaux (« 7e », « Tle »).
  final String abrege;
  final Cycle cycle;

  /// Code de la Terminale.
  static const int codeTerminale = 13;

  /// Vrai si les classes de ce niveau ont des options (lycée).
  bool get aDesOptions => cycle == Cycle.lycee;
}

/// Les treize niveaux, dans l'ordre.
const List<NiveauScolaire> niveauxScolaires = [
  NiveauScolaire(1, '1ère année', '1re', Cycle.primaire),
  NiveauScolaire(2, '2ème année', '2e', Cycle.primaire),
  NiveauScolaire(3, '3ème année', '3e', Cycle.primaire),
  NiveauScolaire(4, '4ème année', '4e', Cycle.primaire),
  NiveauScolaire(5, '5ème année', '5e', Cycle.primaire),
  NiveauScolaire(6, '6ème année', '6e', Cycle.primaire),
  NiveauScolaire(7, '7ème année', '7e', Cycle.college),
  NiveauScolaire(8, '8ème année', '8e', Cycle.college),
  NiveauScolaire(9, '9ème année', '9e', Cycle.college),
  NiveauScolaire(10, '10ème année', '10e', Cycle.college),
  NiveauScolaire(11, '11ème année', '11e', Cycle.lycee),
  NiveauScolaire(12, '12ème année', '12e', Cycle.lycee),
  NiveauScolaire(13, 'Terminale', 'Tle', Cycle.lycee),
];

/// Niveau portant ce code, ou null.
NiveauScolaire? niveauDeCode(int? code) {
  if (code == null) return null;
  for (final n in niveauxScolaires) {
    if (n.code == code) return n;
  }
  return null;
}

/// Niveaux d'un cycle, dans l'ordre.
List<NiveauScolaire> niveauxDuCycle(Cycle cycle) =>
    [for (final n in niveauxScolaires) if (n.cycle == cycle) n];

/// Cycle d'un niveau (null si le code est inconnu ou absent).
Cycle? cycleDuNiveau(int? code) => niveauDeCode(code)?.cycle;

/// Nom d'une classe proposé d'après son niveau et son option :
/// « 7e », « Tle SM »...
String nomProposeDeClasse(NiveauScolaire niveau, SerieLycee? serie) =>
    serie == null ? niveau.abrege : '${niveau.abrege} ${serie.code}';

/// Libellé complet d'un niveau et de son option :
/// « Terminale · Sciences mathématiques ».
String libelleNiveauComplet(NiveauScolaire niveau, SerieLycee? serie) =>
    serie == null ? niveau.libelle : '${niveau.libelle} · ${serie.libelle}';

const Map<String, int> _ordinaux = {
  'premiere': 1,
  'deuxieme': 2,
  'troisieme': 3,
  'quatrieme': 4,
  'cinquieme': 5,
  'sixieme': 6,
  'septieme': 7,
  'huitieme': 8,
  'neuvieme': 9,
  'dixieme': 10,
  'onzieme': 11,
  'douzieme': 12,
};

final RegExp _nombre = RegExp(r'\d+');
final RegExp _motTerminale = RegExp(r'\b(terminale|terminal|tle|term)\b');

/// Devine le niveau d'après un texte libre saisi avant l'existence du
/// catalogue (« 10e », « 7ème année », « Terminale SM », « sixième »...).
/// Retourne null quand le texte ne permet pas de conclure.
NiveauScolaire? devinerNiveau(String texte) {
  final t = normaliserRecherche(texte);
  if (t.isEmpty) return null;
  if (_motTerminale.hasMatch(t)) return niveauDeCode(NiveauScolaire.codeTerminale);
  final chiffres = _nombre.firstMatch(t);
  if (chiffres != null) {
    final n = int.tryParse(chiffres.group(0)!);
    // Un nombre hors du catalogue (« 2026 », « 15 ») n'est pas un niveau.
    return (n == null || n < 1 || n > 12) ? null : niveauDeCode(n);
  }
  for (final mot in t.split(RegExp(r'[^a-z]+'))) {
    final n = _ordinaux[mot];
    if (n != null) return niveauDeCode(n);
  }
  return null;
}

final RegExp _motSerie = RegExp(r'\b(ss|se|sm)\b');

/// Devine l'option du lycée d'après un texte libre (« Terminale SM »,
/// « 12e sciences sociales »), ou null.
SerieLycee? devinerSerie(String texte) {
  final t = normaliserRecherche(texte);
  if (t.isEmpty) return null;
  final code = _motSerie.firstMatch(t)?.group(1);
  if (code != null) return SerieLycee.depuisCode(code.toUpperCase());
  if (t.contains('mathematique')) return SerieLycee.sciencesMathematiques;
  if (t.contains('experiment')) return SerieLycee.sciencesExperimentales;
  if (t.contains('sociale')) return SerieLycee.sciencesSociales;
  return null;
}
