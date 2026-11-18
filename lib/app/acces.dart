import 'package:flutter/foundation.dart';

import '../data/depots/parametre_depot.dart';
import '../data/erreurs.dart';
import '../data/modeles_securite.dart';
import 'services.dart';
import 'session.dart';

/// Connexion, verrouillage et déconnexion : relie les comptes (base de
/// données) à la [Session] (ce que l'utilisateur a le droit de faire).
class Acces extends ChangeNotifier {
  Acces(this.services);

  final Services services;

  Session get session => services.session;

  /// Vrai tant qu'aucun compte n'existe (premier démarrage).
  bool aucunCompte = false;
  bool _charge = false;

  /// Vrai quand l'état initial a été lu dans la base.
  bool get charge => _charge;

  /// Lit l'état initial : y a-t-il déjà des comptes, et quel délai
  /// d'inactivité est configuré.
  Future<void> charger() async {
    aucunCompte = await services.utilisateurs.aucunUtilisateur();
    final minutes = await services.parametres.lireEntier(
      CleParametre.delaiInactiviteMinutes,
      30,
    );
    session.delaiInactivite = Duration(minutes: minutes.clamp(0, 600));
    _charge = true;
    notifyListeners();
  }

  /// Crée le premier administrateur. Retourne le code de récupération, à
  /// montrer une seule fois. La session n'est ouverte qu'avec [demarrer].
  Future<({Utilisateur utilisateur, String codeRecuperation})>
      creerPremierAdministrateur({
    required String identifiant,
    required String nomComplet,
    required String motDePasse,
  }) async {
    final r = await services.utilisateurs.creerPremierAdministrateur(
      identifiant: identifiant,
      nomComplet: nomComplet,
      motDePasse: motDePasse,
    );
    aucunCompte = false;
    return r;
  }

  /// Ouvre la session de [utilisateur] (après création ou connexion).
  Future<void> demarrer(Utilisateur utilisateur) async {
    await services.utilisateurs.marquerContexte(utilisateur);
    session.ouvrir(utilisateur);
    notifyListeners();
  }

  Future<void> seConnecter(String identifiant, String motDePasse) async {
    final u = await services.utilisateurs.authentifier(identifiant, motDePasse);
    await demarrer(u);
  }

  /// Redemande le mot de passe du compte verrouillé par inactivité.
  Future<void> deverrouiller(String motDePasse) async {
    final u = session.utilisateur;
    if (u == null) throw const ErreurGesco('Aucune session à déverrouiller.');
    final frais = await services.utilisateurs.authentifier(u.identifiant, motDePasse);
    await demarrer(frais);
  }

  Future<void> seDeconnecter({bool inactivite = false}) async {
    final u = session.utilisateur;
    if (u != null) {
      await services.utilisateurs.enregistrerDeconnexion(u, inactivite: inactivite);
    }
    session.fermer();
    notifyListeners();
  }

  /// Verrouille la session si le délai d'inactivité est dépassé. Retourne
  /// vrai si elle vient d'être verrouillée.
  Future<bool> verifierInactivite([DateTime? maintenant]) async {
    final u = session.utilisateur;
    if (!session.verifierInactivite(maintenant)) return false;
    if (u != null) {
      await services.utilisateurs.enregistrerVerrouillage(u, inactivite: true);
    }
    notifyListeners();
    return true;
  }

  /// Verrouille tout de suite (bouton « Verrouiller »).
  Future<void> verrouiller() async {
    final u = session.utilisateur;
    if (u == null || session.verrouillee) return;
    session.verrouiller();
    await services.utilisateurs.enregistrerVerrouillage(u, inactivite: false);
    notifyListeners();
  }

  /// L'utilisateur connecté change son mot de passe.
  Future<void> changerMotDePasse({
    required String ancien,
    required String nouveau,
  }) async {
    final u = session.utilisateur;
    if (u == null) throw const ErreurGesco('Aucune session ouverte.');
    await services.utilisateurs.changerMotDePasse(
      u.id,
      ancien: ancien,
      nouveau: nouveau,
    );
    final frais = await services.utilisateurs.obtenir(u.id);
    if (frais != null) session.actualiser(frais);
    notifyListeners();
  }

  /// Un administrateur qui a perdu son mot de passe le réinitialise avec son
  /// code de récupération. Retourne le nouveau code à noter.
  Future<String> recuperer({
    required String identifiant,
    required String code,
    required String nouveauMotDePasse,
  }) {
    return services.utilisateurs.reinitialiserParCodeRecuperation(
      identifiant: identifiant,
      code: code,
      nouveauMotDePasse: nouveauMotDePasse,
    );
  }
}
