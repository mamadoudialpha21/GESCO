import 'dart:typed_data';

import '../domain/modeles.dart';

/// Informations de l'établissement (une seule fiche dans la base).
class Etablissement {
  const Etablissement({
    this.nom = '',
    this.adresse = '',
    this.telephone = '',
    this.email = '',
    this.logo,
  });

  final String nom;
  final String adresse;
  final String telephone;
  final String email;

  /// Image PNG ou JPEG du logo, ou null.
  final Uint8List? logo;

  Etablissement copyWith({
    String? nom,
    String? adresse,
    String? telephone,
    String? email,
    Uint8List? logo,
    bool supprimerLogo = false,
  }) {
    return Etablissement(
      nom: nom ?? this.nom,
      adresse: adresse ?? this.adresse,
      telephone: telephone ?? this.telephone,
      email: email ?? this.email,
      logo: supprimerLogo ? null : (logo ?? this.logo),
    );
  }
}

class AnneeScolaire {
  const AnneeScolaire({
    required this.id,
    required this.libelle,
    required this.active,
    required this.creeLe,
  });

  final int id;
  final String libelle;

  /// L'année ouverte par défaut au démarrage (une seule à la fois).
  final bool active;
  final String creeLe;
}

class Classe {
  const Classe({
    required this.id,
    required this.anneeId,
    required this.niveau,
    required this.nom,
  });

  final int id;
  final int anneeId;

  /// Niveau d'études (« 10e année », « Terminale »...). Peut être vide.
  final String niveau;
  final String nom;
}

/// Une classe avec ses effectifs, pour les listes.
class ClasseResume {
  const ClasseResume({
    required this.classe,
    required this.nbMatieres,
    required this.nbEleves,
  });

  final Classe classe;
  final int nbMatieres;
  final int nbEleves;
}

/// Matière d'une classe avec son coefficient (en centièmes : 2,5 -> 250).
class MatiereClasse {
  const MatiereClasse({
    required this.id,
    required this.classeId,
    required this.nom,
    required this.coefficient,
    required this.ordre,
  });

  final int id;
  final int classeId;
  final String nom;
  final int coefficient;
  final int ordre;

  MatiereCoef versCoef() =>
      MatiereCoef(id: id, nom: nom, coefficient: coefficient);
}

/// Fiche d'un élève. Les informations personnelles sont communes à toutes
/// les années ; la classe dépend de l'inscription (voir [EleveInscrit]).
///
/// [id] vaut 0 tant que l'élève n'est pas enregistré.
class Eleve {
  const Eleve({
    this.id = 0,
    required this.matricule,
    required this.nom,
    required this.prenom,
    required this.sexe,
    this.dateNaissance,
    this.lieuNaissance = '',
    this.nomPere = '',
    this.nomMere = '',
    this.contactParent = '',
    this.adresse = '',
    this.photo,
  });

  final int id;
  final String matricule;
  final String nom;
  final String prenom;

  /// 'M' ou 'F'.
  final String sexe;

  /// Date de naissance au format « AAAA-MM-JJ », ou null.
  final String? dateNaissance;
  final String lieuNaissance;
  final String nomPere;
  final String nomMere;
  final String contactParent;
  final String adresse;

  /// Photo PNG ou JPEG facultative.
  final Uint8List? photo;

  /// « DIALLO Aminata ».
  String get nomComplet => '${nom.toUpperCase()} $prenom';

  Eleve copyWith({
    String? matricule,
    String? nom,
    String? prenom,
    String? sexe,
    String? dateNaissance,
    String? lieuNaissance,
    String? nomPere,
    String? nomMere,
    String? contactParent,
    String? adresse,
    Uint8List? photo,
    bool supprimerDate = false,
    bool supprimerPhoto = false,
  }) {
    return Eleve(
      id: id,
      matricule: matricule ?? this.matricule,
      nom: nom ?? this.nom,
      prenom: prenom ?? this.prenom,
      sexe: sexe ?? this.sexe,
      dateNaissance:
          supprimerDate ? null : (dateNaissance ?? this.dateNaissance),
      lieuNaissance: lieuNaissance ?? this.lieuNaissance,
      nomPere: nomPere ?? this.nomPere,
      nomMere: nomMere ?? this.nomMere,
      contactParent: contactParent ?? this.contactParent,
      adresse: adresse ?? this.adresse,
      photo: supprimerPhoto ? null : (photo ?? this.photo),
    );
  }
}

/// Un élève inscrit dans une classe pour une année (ligne des listes).
/// Ne contient pas la photo, pour que les listes restent légères.
class EleveInscrit {
  const EleveInscrit({
    required this.inscriptionId,
    required this.eleveId,
    required this.classeId,
    required this.classeNom,
    required this.matricule,
    required this.nom,
    required this.prenom,
    required this.sexe,
    this.dateNaissance,
  });

  final int inscriptionId;
  final int eleveId;
  final int classeId;
  final String classeNom;
  final String matricule;
  final String nom;
  final String prenom;
  final String sexe;
  final String? dateNaissance;

  String get nomComplet => '${nom.toUpperCase()} $prenom';
}
