/// Rôles et permissions des utilisateurs.
///
/// Chaque rôle a un ensemble de permissions par défaut. L'administrateur peut
/// personnaliser les permissions d'un compte (sauf celles d'un administrateur,
/// qui a toujours tous les droits : cela évite de se verrouiller soi-même).
library;

enum RoleUtilisateur { administrateur, direction, saisie, consultation }

extension RoleUtilisateurInfo on RoleUtilisateur {
  /// Valeur enregistrée dans la base.
  String get cle => name;

  String get libelle => switch (this) {
        RoleUtilisateur.administrateur => 'Administrateur',
        RoleUtilisateur.direction => 'Direction',
        RoleUtilisateur.saisie => 'Saisie des notes',
        RoleUtilisateur.consultation => 'Consultation',
      };

  String get description => switch (this) {
        RoleUtilisateur.administrateur => 'Accès à tous les modules, comptes et sauvegardes.',
        RoleUtilisateur.direction =>
          'Gestion et consultation générale ; ni comptes ni restauration.',
        RoleUtilisateur.saisie => 'Saisie et modification des notes et évaluations.',
        RoleUtilisateur.consultation => 'Consultation et impression uniquement.',
      };

  static RoleUtilisateur depuisCle(String cle) =>
      RoleUtilisateur.values.firstWhere(
        (r) => r.name == cle,
        orElse: () => RoleUtilisateur.consultation,
      );
}

enum Permission {
  // Consultation
  tableauDeBord('tableau_de_bord.voir', 'Voir le tableau de bord', 'Consultation'),
  etablissementVoir('etablissement.voir', 'Voir la fiche de l\'établissement', 'Consultation'),
  anneesVoir('annees.voir', 'Voir les années scolaires', 'Consultation'),
  classesVoir('classes.voir', 'Voir les classes et les matières', 'Consultation'),
  elevesVoir('eleves.voir', 'Voir les élèves et les inscriptions', 'Consultation'),
  enseignantsVoir('enseignants.voir', 'Voir les enseignants', 'Consultation'),
  notesVoir('notes.voir', 'Voir les notes et les évaluations', 'Consultation'),
  resultatsVoir('resultats.voir', 'Voir moyennes, classements et statistiques', 'Consultation'),
  documentsGenerer('documents.generer', 'Générer et imprimer les documents (PDF)', 'Consultation'),

  // Gestion
  etablissementModifier('etablissement.modifier', 'Modifier la fiche de l\'établissement', 'Gestion'),
  anneesGerer('annees.gerer', 'Gérer les années scolaires', 'Gestion'),
  classesGerer('classes.gerer', 'Gérer les classes et les matières', 'Gestion'),
  elevesGerer('eleves.gerer', 'Gérer les élèves et les inscriptions', 'Gestion'),
  elevesSupprimer('eleves.supprimer', 'Supprimer ou archiver un dossier élève', 'Gestion'),
  enseignantsGerer('enseignants.gerer', 'Gérer les enseignants', 'Gestion'),
  parametresGerer('parametres.gerer', 'Modifier les paramètres avancés', 'Gestion'),
  importExport('import_export.executer', 'Importer et exporter (Excel)', 'Gestion'),

  // Notes
  notesSaisir('notes.saisir', 'Saisir et modifier les notes', 'Notes'),
  evaluationsGerer('evaluations.gerer', 'Créer et supprimer des évaluations', 'Notes'),
  notesVerrouiller('notes.verrouiller', 'Valider et verrouiller les résultats', 'Notes'),
  appreciationsSaisir('appreciations.saisir', 'Saisir les appréciations', 'Notes'),
  decisionsSaisir('decisions.saisir', 'Saisir les décisions du conseil de classe', 'Notes'),

  // Sécurité
  journalVoir('journal.voir', 'Consulter le journal et l\'historique', 'Sécurité'),
  sauvegardeGerer('sauvegarde.gerer', 'Créer et consulter les sauvegardes', 'Sécurité'),
  sauvegardeRestaurer('sauvegarde.restaurer', 'Restaurer une sauvegarde', 'Sécurité'),
  utilisateursGerer('utilisateurs.gerer', 'Gérer les comptes et les permissions', 'Sécurité');

  const Permission(this.cle, this.libelle, this.groupe);

  final String cle;
  final String libelle;
  final String groupe;

  static Permission? depuisCle(String cle) {
    for (final p in values) {
      if (p.cle == cle) return p;
    }
    return null;
  }
}

/// Permissions de consultation : accordées à tous les rôles.
const Set<Permission> _consultation = {
  Permission.tableauDeBord,
  Permission.etablissementVoir,
  Permission.anneesVoir,
  Permission.classesVoir,
  Permission.elevesVoir,
  Permission.enseignantsVoir,
  Permission.notesVoir,
  Permission.resultatsVoir,
  Permission.documentsGenerer,
};

/// Permissions par défaut d'un rôle.
Set<Permission> permissionsDuRole(RoleUtilisateur role) => switch (role) {
      RoleUtilisateur.administrateur => Permission.values.toSet(),
      RoleUtilisateur.direction => Permission.values.toSet()
        ..removeAll({Permission.utilisateursGerer, Permission.sauvegardeRestaurer}),
      RoleUtilisateur.saisie => {
          ..._consultation,
          Permission.notesSaisir,
          Permission.evaluationsGerer,
          Permission.appreciationsSaisir,
        },
      RoleUtilisateur.consultation => {..._consultation},
    };

/// Permissions effectives d'un compte : celles du rôle, ou la liste
/// personnalisée si elle existe. Un administrateur a toujours tout.
Set<Permission> permissionsEffectives(
  RoleUtilisateur role,
  Set<Permission>? personnalisees,
) {
  if (role == RoleUtilisateur.administrateur) return Permission.values.toSet();
  return personnalisees ?? permissionsDuRole(role);
}

/// Les permissions regroupées par thème (pour les écrans de configuration).
Map<String, List<Permission>> permissionsParGroupe() {
  final groupes = <String, List<Permission>>{};
  for (final p in Permission.values) {
    groupes.putIfAbsent(p.groupe, () => []).add(p);
  }
  return groupes;
}
