import 'package:flutter/foundation.dart';

import '../data/controle.dart';
import '../data/modeles_securite.dart';
import '../domain/permissions.dart';

/// Session de l'utilisateur connecté : qui il est, ce qu'il a le droit de
/// faire, et verrouillage après une période d'inactivité.
class Session extends ChangeNotifier implements Autorisations {
  Session({this.delaiInactivite = const Duration(minutes: 30)}) : controle = true;

  /// Session sans contrôle d'accès (tests et outils internes) : tout est
  /// autorisé et aucune connexion n'est demandée.
  Session.sansControle()
      : controle = false,
        delaiInactivite = Duration.zero;

  /// Faux seulement pour [Session.sansControle].
  final bool controle;

  /// Durée d'inactivité avant verrouillage ; zéro désactive le verrouillage.
  Duration delaiInactivite;

  Utilisateur? _utilisateur;
  bool _verrouillee = false;
  DateTime? _derniereActivite;

  Utilisateur? get utilisateur => _utilisateur;

  /// Dernier compte utilisé (pour préremplir l'écran de déverrouillage).
  Utilisateur? get dernierUtilisateur => _utilisateur;

  bool get verrouillee => _verrouillee;

  @override
  bool get aUtilisateur => !controle || _utilisateur != null;

  /// Vrai si l'application peut être utilisée.
  bool get connectee => !controle || (_utilisateur != null && !_verrouillee);

  @override
  bool peut(Permission p) {
    if (!controle) return true;
    final u = _utilisateur;
    return u != null && !_verrouillee && u.peut(p);
  }

  /// Identifiant d'enseignant qui limite la saisie aux matières qu'il
  /// enseigne, ou null si le compte n'est pas limité.
  @override
  int? get enseignantLimite {
    final u = _utilisateur;
    if (!controle || u == null || !u.limiteAuxMatieres) return null;
    return u.enseignantId;
  }

  void ouvrir(Utilisateur utilisateur, {DateTime? maintenant}) {
    _utilisateur = utilisateur;
    _verrouillee = false;
    _derniereActivite = maintenant ?? DateTime.now();
    notifyListeners();
  }

  /// Ferme la session (déconnexion).
  void fermer() {
    _utilisateur = null;
    _verrouillee = false;
    _derniereActivite = null;
    notifyListeners();
  }

  /// Verrouille sans oublier l'utilisateur : seul son mot de passe est redemandé.
  void verrouiller() {
    if (_utilisateur == null || _verrouillee) return;
    _verrouillee = true;
    notifyListeners();
  }

  /// Met à jour le compte connecté après une modification de son profil.
  void actualiser(Utilisateur utilisateur) {
    if (_utilisateur?.id != utilisateur.id) return;
    _utilisateur = utilisateur;
    notifyListeners();
  }

  /// À appeler à chaque action de l'utilisateur.
  void activite([DateTime? maintenant]) {
    if (_utilisateur == null || _verrouillee) return;
    _derniereActivite = maintenant ?? DateTime.now();
  }

  /// Verrouille si le délai d'inactivité est dépassé. Retourne vrai si la
  /// session vient d'être verrouillée.
  bool verifierInactivite([DateTime? maintenant]) {
    if (!controle ||
        _utilisateur == null ||
        _verrouillee ||
        delaiInactivite == Duration.zero ||
        _derniereActivite == null) {
      return false;
    }
    final now = maintenant ?? DateTime.now();
    if (now.difference(_derniereActivite!) >= delaiInactivite) {
      verrouiller();
      return true;
    }
    return false;
  }
}
