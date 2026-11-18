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
    this.directeur = '',
    this.devise = '',
    this.infosAdmin = '',
    this.signatureDirecteur,
    this.cachet,
  });

  final String nom;
  final String adresse;
  final String telephone;
  final String email;

  /// Image PNG ou JPEG du logo, ou null.
  final Uint8List? logo;

  /// Nom du directeur ou de la directrice (imprimé sur les bulletins).
  final String directeur;

  /// Devise de l'établissement.
  final String devise;

  /// Informations administratives libres (agrément, BP, ville...), imprimées
  /// dans l'en-tête des documents.
  final String infosAdmin;

  /// Signature du directeur (image PNG ou JPEG), ou null.
  final Uint8List? signatureDirecteur;

  /// Cachet de l'établissement (image PNG ou JPEG), ou null.
  final Uint8List? cachet;

  Etablissement copyWith({
    String? nom,
    String? adresse,
    String? telephone,
    String? email,
    Uint8List? logo,
    bool supprimerLogo = false,
    String? directeur,
    String? devise,
    String? infosAdmin,
    Uint8List? signatureDirecteur,
    bool supprimerSignature = false,
    Uint8List? cachet,
    bool supprimerCachet = false,
  }) {
    return Etablissement(
      nom: nom ?? this.nom,
      adresse: adresse ?? this.adresse,
      telephone: telephone ?? this.telephone,
      email: email ?? this.email,
      logo: supprimerLogo ? null : (logo ?? this.logo),
      directeur: directeur ?? this.directeur,
      devise: devise ?? this.devise,
      infosAdmin: infosAdmin ?? this.infosAdmin,
      signatureDirecteur: supprimerSignature
          ? null
          : (signatureDirecteur ?? this.signatureDirecteur),
      cachet: supprimerCachet ? null : (cachet ?? this.cachet),
    );
  }
}

class AnneeScolaire {
  const AnneeScolaire({
    required this.id,
    required this.libelle,
    required this.active,
    required this.creeLe,
    this.archivee = false,
  });

  final int id;
  final String libelle;

  /// L'année ouverte par défaut au démarrage (une seule à la fois).
  final bool active;
  final String creeLe;

  /// Année terminée et figée : plus aucune note ne peut y être modifiée.
  final bool archivee;
}

class Classe {
  const Classe({
    required this.id,
    required this.anneeId,
    required this.niveau,
    required this.nom,
    this.capacite,
    this.profPrincipalId,
  });

  final int id;
  final int anneeId;

  /// Niveau d'études (« 10e année », « Terminale »...). Peut être vide.
  final String niveau;
  final String nom;

  /// Nombre maximal d'élèves, ou null si non limité.
  final int? capacite;

  /// Enseignant responsable de la classe, ou null.
  final int? profPrincipalId;
}

/// Une classe avec ses effectifs, pour les listes.
class ClasseResume {
  const ClasseResume({
    required this.classe,
    required this.nbMatieres,
    required this.nbEleves,
    int? nbActifs,
    this.nbFilles = 0,
    this.nbGarcons = 0,
    this.profPrincipalNom = '',
  }) : nbActifs = nbActifs ?? nbEleves;

  final Classe classe;
  final int nbMatieres;

  /// Élèves inscrits, y compris ceux qui sont partis ou ont abandonné.
  final int nbEleves;

  /// Élèves qui suivent encore la classe (ni départ ni abandon).
  final int nbActifs;
  final int nbFilles;
  final int nbGarcons;
  final String profPrincipalNom;

  /// Vrai si la classe a une capacité et qu'elle est atteinte ou dépassée.
  bool get pleine => classe.capacite != null && nbActifs >= classe.capacite!;
}

/// Matière d'une classe avec son coefficient (en centièmes : 2,5 -> 250).
class MatiereClasse {
  const MatiereClasse({
    required this.id,
    required this.classeId,
    required this.nom,
    required this.coefficient,
    required this.ordre,
    this.bareme = 20,
    this.facultative = false,
    this.enseignantId,
  });

  final int id;
  final int classeId;
  final String nom;
  final int coefficient;
  final int ordre;

  /// Note maximale de la matière (10, 20, 40, 100...).
  final int bareme;

  /// Matière facultative : elle n'entre pas dans les moyennes générales.
  final bool facultative;

  /// Enseignant qui assure la matière, ou null.
  final int? enseignantId;

  MatiereCoef versCoef() => MatiereCoef(
        id: id,
        nom: nom,
        coefficient: coefficient,
        facultative: facultative,
      );
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
    this.telephone = '',
    this.nomTuteur = '',
    this.contactTuteur = '',
    this.archive = false,
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

  /// Téléphone de l'élève.
  final String telephone;

  /// Tuteur légal, si différent des parents.
  final String nomTuteur;
  final String contactTuteur;

  /// Dossier archivé : l'élève n'apparaît plus dans les listes courantes,
  /// mais ses données sont conservées.
  final bool archive;

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
    String? telephone,
    String? nomTuteur,
    String? contactTuteur,
    bool? archive,
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
      telephone: telephone ?? this.telephone,
      nomTuteur: nomTuteur ?? this.nomTuteur,
      contactTuteur: contactTuteur ?? this.contactTuteur,
      archive: archive ?? this.archive,
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
    this.statut = StatutInscription.inscrit,
    this.archive = false,
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

  /// Situation dans l'année : inscrit, parti ou ayant abandonné.
  final StatutInscription statut;

  /// Dossier archivé (voir [Eleve.archive]).
  final bool archive;

  /// Vrai si l'élève suit encore la classe : il figure dans les classements
  /// et les statistiques.
  bool get actif => statut == StatutInscription.inscrit;

  String get nomComplet => '${nom.toUpperCase()} $prenom';
}

/// Situation d'un élève dans l'année scolaire.
enum StatutInscription {
  inscrit('inscrit', 'Inscrit'),
  depart('depart', 'Parti'),
  abandon('abandon', 'Abandon');

  const StatutInscription(this.cle, this.libelle);

  final String cle;
  final String libelle;

  static StatutInscription depuisCle(String? cle) => values.firstWhere(
        (s) => s.cle == cle,
        orElse: () => StatutInscription.inscrit,
      );
}

/// Enseignant de l'établissement. [id] vaut 0 tant qu'il n'est pas enregistré.
class Enseignant {
  const Enseignant({
    this.id = 0,
    this.matricule = '',
    required this.nom,
    required this.prenom,
    this.sexe,
    this.telephone = '',
    this.email = '',
    this.specialite = '',
    this.actif = true,
    this.peutSaisir = true,
    this.signature,
  });

  final int id;
  final String matricule;
  final String nom;
  final String prenom;

  /// 'M', 'F' ou null.
  final String? sexe;
  final String telephone;
  final String email;
  final String specialite;

  /// Un enseignant inactif n'est plus proposé pour de nouvelles affectations.
  final bool actif;

  /// Autorisé à saisir des notes (pour un compte « saisie » qui lui est lié).
  final bool peutSaisir;

  /// Signature PNG ou JPEG facultative (documents imprimés).
  final Uint8List? signature;

  /// « DIALLO Aminata ».
  String get nomComplet => '${nom.toUpperCase()} $prenom'.trim();

  Enseignant copyWith({
    String? matricule,
    String? nom,
    String? prenom,
    String? sexe,
    String? telephone,
    String? email,
    String? specialite,
    bool? actif,
    bool? peutSaisir,
    Uint8List? signature,
    bool supprimerSexe = false,
    bool supprimerSignature = false,
  }) {
    return Enseignant(
      id: id,
      matricule: matricule ?? this.matricule,
      nom: nom ?? this.nom,
      prenom: prenom ?? this.prenom,
      sexe: supprimerSexe ? null : (sexe ?? this.sexe),
      telephone: telephone ?? this.telephone,
      email: email ?? this.email,
      specialite: specialite ?? this.specialite,
      actif: actif ?? this.actif,
      peutSaisir: peutSaisir ?? this.peutSaisir,
      signature: supprimerSignature ? null : (signature ?? this.signature),
    );
  }
}

/// Une matière enseignée par un enseignant dans une classe.
class AffectationMatiere {
  const AffectationMatiere({
    required this.matiereId,
    required this.matiereNom,
    required this.classeId,
    required this.classeNom,
    required this.anneeId,
  });

  final int matiereId;
  final String matiereNom;
  final int classeId;
  final String classeNom;
  final int anneeId;
}

/// Enseignant et nombre de ses affectations pour une année (liste).
class EnseignantResume {
  const EnseignantResume({
    required this.enseignant,
    required this.nbMatieres,
    required this.nbClasses,
  });

  final Enseignant enseignant;

  /// Matières enseignées l'année choisie.
  final int nbMatieres;

  /// Classes concernées l'année choisie (matières enseignées, classes
  /// confiées, professeur principal), sans doublon.
  final int nbClasses;
}

/// Un déplacement ou une modification de la situation d'un élève.
class MouvementInscription {
  const MouvementInscription({
    required this.id,
    required this.inscriptionId,
    required this.type,
    required this.date,
    this.classeOrigineNom = '',
    this.classeDestinationNom = '',
    this.motif = '',
    this.utilisateur = '',
    this.eleveNom = '',
    this.anneeLibelle = '',
  });

  final int id;
  final int inscriptionId;

  /// Nom de l'élève et libellé de l'année (utiles quand la liste couvre
  /// plusieurs élèves ou plusieurs années).
  final String eleveNom;
  final String anneeLibelle;

  /// inscription, reinscription, changement_classe, depart, abandon, reprise.
  final String type;

  /// Date et heure (ISO 8601).
  final String date;
  final String classeOrigineNom;
  final String classeDestinationNom;
  final String motif;
  final String utilisateur;

  String get libelleType => switch (type) {
        'inscription' => 'Inscription',
        'reinscription' => 'Réinscription',
        'changement_classe' => 'Changement de classe',
        'depart' => 'Départ',
        'abandon' => 'Abandon',
        'reprise' => 'Reprise',
        _ => type,
      };
}

/// Ce qu'un transfert de classe fait des notes déjà saisies.
class ApercuTransfert {
  const ApercuTransfert({
    required this.notesReprises,
    required this.notesSansMatiere,
    required this.notesEvaluation,
  });

  /// Notes mensuelles reportées sur la matière de même nom de la nouvelle
  /// classe.
  final int notesReprises;

  /// Notes mensuelles dont la matière n'existe pas dans la nouvelle classe :
  /// supprimées avec confirmation.
  final int notesSansMatiere;

  /// Notes d'évaluation (propres à la classe quittée) : supprimées avec
  /// confirmation.
  final int notesEvaluation;

  int get notesPerdues => notesSansMatiere + notesEvaluation;
  bool get aDesPertes => notesPerdues > 0;
}

/// Une inscription d'un élève dans l'une de ses années (fiche élève).
class InscriptionHistorique {
  const InscriptionHistorique({
    required this.inscriptionId,
    required this.anneeId,
    required this.anneeLibelle,
    required this.classeId,
    required this.classeNom,
    required this.statut,
    required this.dateInscription,
    this.dateSortie,
    this.motifSortie = '',
  });

  final int inscriptionId;
  final int anneeId;
  final String anneeLibelle;
  final int classeId;
  final String classeNom;
  final StatutInscription statut;
  final String dateInscription;
  final String? dateSortie;
  final String motifSortie;
}
