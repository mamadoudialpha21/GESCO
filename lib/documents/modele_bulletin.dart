/// Contenu d'un bulletin scolaire, indépendant de sa mise en page.
///
/// Ces classes ne contiennent que des données prêtes à imprimer : les calculs
/// (moyennes, rangs, mentions) sont faits en amont, par le moteur de résultats.
library;

import 'dart:typed_data';

/// Nature du bulletin.
enum TypeBulletin {
  mensuel('Bulletin du mois de'),
  periodique('Bulletin du'),
  annuel('Bulletin annuel');

  const TypeBulletin(this.prefixe);

  final String prefixe;
}

/// Une matière du bulletin.
class LigneBulletin {
  const LigneBulletin({
    required this.matiere,
    required this.coefficient,
    this.note,
    this.rang,
    this.moyenneClasse,
    this.minClasse,
    this.maxClasse,
    this.appreciation = '',
    this.facultative = false,
    this.enseignant = '',
  });

  final String matiere;

  /// Coefficient en centièmes (400 = coefficient 4).
  final int coefficient;

  /// Note sur 20 en centièmes (1450 = 14,50), null si l'élève n'a pas de note.
  final int? note;

  /// Rang de l'élève dans la matière (ex æquo possibles), null s'il n'est pas
  /// classé dans cette matière.
  final int? rang;

  /// Moyenne de la classe dans la matière, en centièmes.
  final int? moyenneClasse;
  final int? minClasse;
  final int? maxClasse;
  final String appreciation;

  /// Matière facultative : sa note est affichée mais ne compte pas dans la
  /// moyenne générale.
  final bool facultative;
  final String enseignant;
}

/// Moyenne d'une période, pour le récapitulatif du bulletin annuel.
class ResumePeriode {
  const ResumePeriode({
    required this.libelle,
    required this.moyenne,
    required this.rang,
  });

  final String libelle;
  final int? moyenne;
  final int? rang;
}

/// Un bulletin complet pour un élève et une période.
class Bulletin {
  const Bulletin({
    required this.type,
    required this.periodeLibelle,
    required this.anneeLibelle,
    required this.etablissementNom,
    this.adresse = '',
    this.telephone = '',
    this.email = '',
    this.devise = '',
    this.infosAdmin = '',
    this.directeur = '',
    this.logo,
    this.signature,
    this.cachet,
    required this.classeNom,
    this.niveau = '',
    required this.eleveNom,
    required this.elevePrenom,
    required this.matricule,
    required this.sexe,
    this.dateNaissance,
    this.lieuNaissance = '',
    this.photo,
    required this.lignes,
    this.moyenne,
    this.rang,
    this.exAequo = false,
    required this.effectif,
    this.moyenneClasse,
    this.meilleureMoyenne,
    this.plusFaibleMoyenne,
    this.mention = '',
    this.decision = '',
    this.incomplet = false,
    this.appreciation = '',
    this.decisionConseil = '',
    this.periodes = const [],
    this.dateEdition,
  });

  final TypeBulletin type;

  /// « Novembre », « Trimestre 1 », « Année scolaire »...
  final String periodeLibelle;
  final String anneeLibelle;

  // Établissement.
  final String etablissementNom;
  final String adresse;
  final String telephone;
  final String email;
  final String devise;

  /// Informations administratives libres (agrément, BP...), une par ligne.
  final String infosAdmin;
  final String directeur;
  final Uint8List? logo;
  final Uint8List? signature;
  final Uint8List? cachet;

  // Classe et élève.
  final String classeNom;
  final String niveau;
  final String eleveNom;
  final String elevePrenom;
  final String matricule;

  /// 'M' ou 'F'.
  final String sexe;

  /// « AAAA-MM-JJ » ou null.
  final String? dateNaissance;
  final String lieuNaissance;
  final Uint8List? photo;

  // Résultats.
  final List<LigneBulletin> lignes;
  final int? moyenne;
  final int? rang;

  /// Un autre élève de la classe a le même rang.
  final bool exAequo;

  /// Nombre d'élèves classés dans la classe (base du « rang sur N »).
  final int effectif;
  final int? moyenneClasse;
  final int? meilleureMoyenne;
  final int? plusFaibleMoyenne;
  final String mention;

  /// Décision calculée d'après la moyenne (passage, redoublement...).
  final String decision;

  /// Des notes manquent : la moyenne est calculée sur les notes disponibles.
  final bool incomplet;

  // Avis du conseil de classe.
  final String appreciation;
  final String decisionConseil;

  /// Récapitulatif par période (bulletin annuel).
  final List<ResumePeriode> periodes;

  /// Date d'édition imprimée en pied de page ; l'heure du jour si null.
  final DateTime? dateEdition;

  String get nomComplet => '${eleveNom.toUpperCase()} $elevePrenom';

  /// « Né(e) le 05/03/2011 à Conakry », ou chaîne vide.
  String get naissance {
    final d = dateNaissance;
    final date = (d != null && d.length == 10)
        ? '${d.substring(8, 10)}/${d.substring(5, 7)}/${d.substring(0, 4)}'
        : '';
    final verbe = sexe == 'F' ? 'Née' : 'Né';
    if (date.isEmpty && lieuNaissance.isEmpty) return '';
    final lieu = lieuNaissance.isEmpty ? '' : ' à $lieuNaissance';
    return date.isEmpty ? '$verbe$lieu' : '$verbe le $date$lieu';
  }

  /// Titre imprimé : « BULLETIN DU TRIMESTRE 1 », « BULLETIN DU MOIS DE NOVEMBRE »...
  String get titre {
    final texte = switch (type) {
      TypeBulletin.mensuel => 'Bulletin du mois de ${periodeLibelle.toLowerCase()}',
      TypeBulletin.periodique => 'Bulletin du ${periodeLibelle.toLowerCase()}',
      TypeBulletin.annuel => 'Bulletin annuel',
    };
    return texte.toUpperCase();
  }
}
