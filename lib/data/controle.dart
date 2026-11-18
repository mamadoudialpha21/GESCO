import '../domain/permissions.dart';
import 'depots/journal_depot.dart';
import 'erreurs.dart';

/// Ce que la couche données doit savoir de l'utilisateur connecté.
abstract class Autorisations {
  bool peut(Permission p);

  /// Vrai si un utilisateur est connecté.
  bool get aUtilisateur;

  /// Enseignant dont le compte est limité aux matières (rôle « saisie »
  /// lié à un enseignant), ou null.
  int? get enseignantLimite;
}

/// Tout est autorisé (tests, outils internes).
class ToutAutoriser implements Autorisations {
  const ToutAutoriser();

  @override
  bool peut(Permission p) => true;

  @override
  bool get aUtilisateur => true;

  @override
  int? get enseignantLimite => null;
}

/// Contrôle d'accès et journalisation partagés par les dépôts : même si un
/// écran affiche un bouton par erreur, une opération sensible est refusée
/// sans la permission, et chaque modification est inscrite au journal.
class Controle {
  const Controle({
    this.autorisations = const ToutAutoriser(),
    this.journal,
  });

  /// Aucun contrôle et aucun journal.
  static const Controle aucun = Controle();

  final Autorisations autorisations;
  final JournalDepot? journal;

  bool peut(Permission p) => autorisations.peut(p);

  int? get enseignantLimite => autorisations.enseignantLimite;

  /// Lève une [ErreurGesco] si la permission manque. [action] complète la
  /// phrase « Vous n'avez pas l'autorisation de ... ».
  void exiger(Permission p, [String? action]) {
    if (autorisations.peut(p)) return;
    if (!autorisations.aUtilisateur) {
      throw const ErreurGesco('Connectez-vous pour effectuer cette opération.');
    }
    throw ErreurGesco(
      'Vous n\'avez pas l\'autorisation '
      '${action == null ? 'd\'effectuer cette opération' : 'de $action'}.',
    );
  }

  /// Inscrit une opération au journal (ne fait rien sans journal).
  Future<void> noter(
    String action,
    String entite, {
    int? id,
    String details = '',
  }) async {
    await journal?.enregistrer(
      action: action,
      entite: entite,
      entiteId: id,
      details: details,
    );
  }
}
