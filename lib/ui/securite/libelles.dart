import '../../data/modeles_securite.dart';
import '../../domain/arrondi.dart';

/// `2026-11-17T08:05:09` -> `17/11/2026 08:05`.
String dateHeureFr(String iso) {
  if (iso.length < 16) return iso;
  final j = iso.substring(0, 10).split('-');
  if (j.length != 3) return iso;
  return '${j[2]}/${j[1]}/${j[0]} ${iso.substring(11, 16)}';
}

String libelleAction(String action) => switch (action) {
      'creation' => 'Création',
      'modification' => 'Modification',
      'suppression' => 'Suppression',
      'activation' => 'Activation',
      'desactivation' => 'Désactivation',
      'inscription' => 'Inscription',
      'reinscription' => 'Réinscription',
      'copie' => 'Copie',
      'reinitialisation' => 'Réinitialisation',
      'reinitialisation_mdp' => 'Mot de passe réinitialisé',
      _ => action,
    };

String libelleEntite(String entite) => switch (entite) {
      'annee' => 'Année scolaire',
      'classe' => 'Classe',
      'matiere' => 'Matière',
      'eleve' => 'Élève',
      'etablissement' => 'Établissement',
      'seuils' => 'Seuils et mentions',
      'calendrier' => 'Périodes',
      'utilisateur' => 'Compte',
      'enseignant' => 'Enseignant',
      'absence' => 'Absence ou retard',
      'evaluation' => 'Évaluation',
      'bareme' => 'Barème',
      'sauvegarde' => 'Sauvegarde',
      'import' => 'Import',
      'verrou' => 'Verrouillage',
      'bulletin' => 'Bulletin',
      _ => entite,
    };

String libelleEvenement(String evenement) => switch (evenement) {
      'connexion' => 'Connexion',
      'deconnexion' => 'Déconnexion',
      'deconnexion_inactivite' => 'Déconnexion (inactivité)',
      'verrouillage_manuel' => 'Session verrouillée',
      'verrouillage_inactivite' => 'Session verrouillée (inactivité)',
      'echec' => 'Échec de connexion',
      'verrouillage' => 'Compte verrouillé',
      'refus_verrou' => 'Connexion refusée (compte verrouillé)',
      'refus_inactif' => 'Connexion refusée (compte désactivé)',
      'creation_compte' => 'Compte créé',
      'compte_active' => 'Compte activé',
      'compte_desactive' => 'Compte désactivé',
      'compte_supprime' => 'Compte supprimé',
      'mot_de_passe_change' => 'Mot de passe changé',
      'mot_de_passe_reinitialise' => 'Mot de passe réinitialisé',
      'recuperation' => 'Accès récupéré par code',
      'recuperation_echec' => 'Échec de récupération',
      _ => evenement,
    };

/// Vrai pour les événements de connexion à surveiller (échecs, blocages).
bool evenementSuspect(String evenement) =>
    const {'echec', 'verrouillage', 'refus_verrou', 'refus_inactif', 'recuperation_echec'}
        .contains(evenement);

String _valeurNote(String? etat, int? valeur, int bareme) {
  switch (etat) {
    case null:
      return '—';
    case 'absent':
      return 'Absent';
    case 'dispense':
      return 'Dispensé';
    default:
      return '${formaterCentiemes(valeur)}/$bareme';
  }
}

/// « 12,5/20 → 14/20 », « — → 9/20 », « 9/20 → supprimée ».
String changementNote(EntreeHistoriqueNote e) {
  final avant = _valeurNote(e.ancienEtat, e.ancienneValeur, e.bareme);
  final apres = e.operation == 'suppression'
      ? 'supprimée'
      : _valeurNote(e.nouvelEtat, e.nouvelleValeur, e.bareme);
  return '$avant → $apres';
}

const List<String> _nomsMois = [
  '',
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String nomMois(int? mois) =>
    mois == null || mois < 1 || mois > 12 ? '' : _nomsMois[mois];
