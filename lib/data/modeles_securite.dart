import '../domain/permissions.dart';

/// Compte utilisateur local.
class Utilisateur {
  const Utilisateur({
    required this.id,
    required this.identifiant,
    required this.nomComplet,
    required this.role,
    required this.actif,
    required this.creeLe,
    this.permissionsPersonnalisees,
    this.enseignantId,
    this.doitChangerMotDePasse = false,
    this.derniereConnexion,
    this.verrouilleJusqua,
  });

  final int id;
  final String identifiant;
  final String nomComplet;
  final RoleUtilisateur role;
  final bool actif;
  final String creeLe;

  /// Liste de permissions propre au compte, ou null pour celles du rôle.
  final Set<Permission>? permissionsPersonnalisees;

  /// Enseignant associé au compte (limite la saisie à ses matières).
  final int? enseignantId;
  final bool doitChangerMotDePasse;
  final String? derniereConnexion;
  final String? verrouilleJusqua;

  Set<Permission> get permissions =>
      permissionsEffectives(role, permissionsPersonnalisees);

  bool peut(Permission p) => actif && permissions.contains(p);

  /// Nom à afficher : le nom complet, sinon l'identifiant.
  String get nomAffiche => nomComplet.trim().isEmpty ? identifiant : nomComplet;

  /// Compte limité aux matières de son enseignant (rôle saisie lié à un
  /// enseignant).
  bool get limiteAuxMatieres =>
      role == RoleUtilisateur.saisie && enseignantId != null;
}

/// Ligne du journal des opérations.
class EntreeJournal {
  const EntreeJournal({
    required this.id,
    required this.dateHeure,
    required this.utilisateurNom,
    required this.action,
    required this.entite,
    required this.entiteId,
    required this.details,
  });

  final int id;
  final String dateHeure;
  final String utilisateurNom;
  final String action;
  final String entite;
  final int? entiteId;
  final String details;
}

/// Ligne du journal des connexions.
class EntreeConnexion {
  const EntreeConnexion({
    required this.id,
    required this.dateHeure,
    required this.identifiant,
    required this.evenement,
    required this.detail,
  });

  final int id;
  final String dateHeure;
  final String identifiant;
  final String evenement;
  final String detail;
}

/// Ligne de l'historique des notes (anciennes et nouvelles valeurs).
class EntreeHistoriqueNote {
  const EntreeHistoriqueNote({
    required this.id,
    required this.dateHeure,
    required this.utilisateurNom,
    required this.source,
    required this.operation,
    required this.eleveNom,
    required this.matiereNom,
    required this.classeNom,
    required this.mois,
    required this.bareme,
    required this.ancienEtat,
    required this.ancienneValeur,
    required this.nouvelEtat,
    required this.nouvelleValeur,
    this.evaluationId,
  });

  final int id;
  final String dateHeure;
  final String utilisateurNom;

  /// `mensuelle` ou `evaluation`.
  final String source;

  /// `creation`, `modification` ou `suppression`.
  final String operation;
  final String eleveNom;
  final String matiereNom;
  final String classeNom;
  final int? mois;
  final int? evaluationId;

  /// Barème de la note (20 pour une note mensuelle).
  final int bareme;
  final String? ancienEtat;
  final int? ancienneValeur;
  final String? nouvelEtat;
  final int? nouvelleValeur;
}
