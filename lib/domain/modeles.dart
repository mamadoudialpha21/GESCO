/// Modèles du moteur de calcul. Dart pur : aucune dépendance à Flutter ni à
/// la base de données, ce qui permet de tester les calculs isolément.
library;

import 'dart:convert';

import 'arrondi.dart';

/// État d'une cellule de note.
///
/// Une cellule jamais renseignée n'a pas de [Saisie] du tout (« non saisie »).
enum EtatNote {
  /// Une note a été saisie.
  saisie,

  /// L'élève était absent : la matière est exclue du calcul (pas de zéro).
  absent,

  /// L'élève est dispensé : la matière est exclue du calcul.
  dispense,
}

/// Contenu d'une cellule de note (élève, matière, mois).
class Saisie {
  const Saisie.valeur(int valeur)
      : etat = EtatNote.saisie,
        centiemes = valeur,
        assert(valeur >= 0 && valeur <= 2000);

  const Saisie.absent()
      : etat = EtatNote.absent,
        centiemes = null;

  const Saisie.dispense()
      : etat = EtatNote.dispense,
        centiemes = null;

  final EtatNote etat;

  /// Note sur 20 en centièmes (0 à 2000). Null si absent ou dispensé.
  final int? centiemes;

  /// Vrai si une note chiffrée a été saisie.
  bool get estNumerique => etat == EtatNote.saisie;
}

/// Matière d'une classe avec son coefficient (en centièmes : 2,5 -> 250).
class MatiereCoef {
  const MatiereCoef({
    required this.id,
    required this.nom,
    required this.coefficient,
  }) : assert(coefficient > 0);

  final int id;
  final String nom;
  final int coefficient;
}

/// Toutes les données d'un élève nécessaires au calcul pour une classe.
class DonneesEleve {
  const DonneesEleve({
    required this.inscriptionId,
    required this.nom,
    required this.prenom,
    required this.sexe,
    required this.saisies,
  });

  final int inscriptionId;
  final String nom;
  final String prenom;

  /// 'M' ou 'F'.
  final String sexe;

  /// matiereId -> mois -> saisie. Une entrée absente signifie « non saisie ».
  final Map<int, Map<int, Saisie>> saisies;

  Saisie? saisie(int matiereId, int mois) => saisies[matiereId]?[mois];
}

/// Seuil (>= en centièmes) associé à un libellé : une mention ou une décision.
class Palier {
  const Palier(this.seuil, this.libelle);

  final int seuil;
  final String libelle;

  Map<String, Object?> toJson() => {'seuil': seuil, 'libelle': libelle};

  factory Palier.fromJson(Map<String, dynamic> json) =>
      Palier(json['seuil'] as int, json['libelle'] as String);
}

/// Niveau d'un résultat, utilisé pour les codes couleur de l'interface :
/// vert = bon, orange = moyen, rouge = insuffisant.
enum NiveauResultat { insuffisant, moyen, bon }

/// Seuils de mentions et de décisions, modifiables sans toucher au code.
/// Stockés par année scolaire.
class ConfigResultats {
  const ConfigResultats({
    required this.seuilAdmission,
    required this.seuilBon,
    required this.mentions,
    required this.decisionsPeriode,
    required this.decisionsAnnee,
  });

  /// Moyenne minimale pour être admis (centièmes). Pilote les statistiques
  /// « admis / non admis » et la couleur orange.
  final int seuilAdmission;

  /// Moyenne à partir de laquelle un résultat est « bon » (couleur verte).
  final int seuilBon;

  /// Mentions (la plus haute atteinte est retenue). Sous le premier seuil :
  /// aucune mention.
  final List<Palier> mentions;

  /// Décisions pour un mois ou un trimestre.
  final List<Palier> decisionsPeriode;

  /// Décisions pour le résultat annuel.
  final List<Palier> decisionsAnnee;

  static const ConfigResultats defaut = ConfigResultats(
    seuilAdmission: 1000,
    seuilBon: 1200,
    mentions: [
      Palier(1000, 'Passable'),
      Palier(1200, 'Assez bien'),
      Palier(1400, 'Bien'),
      Palier(1600, 'Très bien'),
      Palier(1800, 'Excellent'),
    ],
    decisionsPeriode: [
      Palier(0, 'Non admis(e)'),
      Palier(1000, 'Admis(e)'),
    ],
    decisionsAnnee: [
      Palier(0, 'Redouble'),
      Palier(1000, 'Admis(e) en classe supérieure'),
    ],
  );

  /// Mention correspondant à [moyenne] (chaîne vide si aucune).
  String mention(int moyenne) => _libelle(mentions, moyenne);

  String decisionPeriode(int moyenne) => _libelle(decisionsPeriode, moyenne);

  String decisionAnnee(int moyenne) => _libelle(decisionsAnnee, moyenne);

  NiveauResultat niveau(int moyenne) {
    if (moyenne >= seuilBon) return NiveauResultat.bon;
    if (moyenne >= seuilAdmission) return NiveauResultat.moyen;
    return NiveauResultat.insuffisant;
  }

  static String _libelle(List<Palier> paliers, int moyenne) {
    var resultat = '';
    var meilleurSeuil = -1;
    for (final palier in paliers) {
      if (palier.seuil <= moyenne && palier.seuil > meilleurSeuil) {
        resultat = palier.libelle;
        meilleurSeuil = palier.seuil;
      }
    }
    return resultat;
  }

  /// Liste des erreurs de configuration (vide si la configuration est valide).
  List<String> erreurs() {
    final e = <String>[];
    if (seuilAdmission < 0 || seuilAdmission > 2000) {
      e.add('Seuil d\'admission hors de 0 à 20.');
    }
    if (seuilBon < seuilAdmission || seuilBon > 2000) {
      e.add('Le seuil « bon » doit être entre le seuil d\'admission et 20.');
    }
    _validerPaliers('Mentions', mentions, e, exigerZero: false);
    _validerPaliers('Décisions (mois et trimestres)', decisionsPeriode, e,
        exigerZero: true);
    _validerPaliers('Décisions (année)', decisionsAnnee, e, exigerZero: true);
    return e;
  }

  static void _validerPaliers(
    String nom,
    List<Palier> paliers,
    List<String> erreurs, {
    required bool exigerZero,
  }) {
    final vus = <int>{};
    for (final p in paliers) {
      if (p.seuil < 0 || p.seuil > 2000) {
        erreurs.add('$nom : seuil hors de 0 à 20 (${formaterCentiemes(p.seuil)}).');
      }
      if (p.libelle.trim().isEmpty) {
        erreurs.add('$nom : libellé vide.');
      }
      if (!vus.add(p.seuil)) {
        erreurs.add('$nom : seuil en double (${formaterCentiemes(p.seuil)}).');
      }
    }
    if (exigerZero && !paliers.any((p) => p.seuil == 0)) {
      erreurs.add('$nom : prévoir un palier à 0,00 pour couvrir toutes les moyennes.');
    }
  }

  Map<String, Object?> toJson() => {
        'seuilAdmission': seuilAdmission,
        'seuilBon': seuilBon,
        'mentions': [for (final p in mentions) p.toJson()],
        'decisionsPeriode': [for (final p in decisionsPeriode) p.toJson()],
        'decisionsAnnee': [for (final p in decisionsAnnee) p.toJson()],
      };

  String toJsonString() => jsonEncode(toJson());

  factory ConfigResultats.fromJson(Map<String, dynamic> json) {
    List<Palier> lire(String cle) => [
          for (final element in json[cle] as List<dynamic>)
            Palier.fromJson(element as Map<String, dynamic>),
        ];
    return ConfigResultats(
      seuilAdmission: json['seuilAdmission'] as int,
      seuilBon: json['seuilBon'] as int,
      mentions: lire('mentions'),
      decisionsPeriode: lire('decisionsPeriode'),
      decisionsAnnee: lire('decisionsAnnee'),
    );
  }

  factory ConfigResultats.fromJsonString(String texte) =>
      ConfigResultats.fromJson(jsonDecode(texte) as Map<String, dynamic>);
}
