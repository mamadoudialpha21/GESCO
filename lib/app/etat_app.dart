import 'package:flutter/foundation.dart';

import '../data/modeles_donnees.dart';
import '../domain/permissions.dart';
import 'acces.dart';
import 'bulletins_auto.dart';
import 'services.dart';

/// État partagé de l'application : année sélectionnée, fiche de
/// l'établissement, et compteur de modifications qui déclenche le
/// rechargement des écrans.
class EtatApp extends ChangeNotifier {
  EtatApp(
    this.services, {
    required this.chemin,
    this.problemesIntegrite = const [],
    this.bulletinsAuto,
  }) : acces = Acces(services);

  final Services services;

  /// Connexion, verrouillage et déconnexion.
  final Acces acces;

  /// Vrai si l'utilisateur connecté a la permission [p] (toujours vrai quand
  /// l'application tourne sans contrôle d'accès, par exemple dans les tests).
  bool peut(Permission p) => services.session.peut(p);

  /// Emplacement du fichier de base de données (affiché à l'utilisateur).
  final String chemin;

  /// Problèmes détectés par le contrôle d'intégrité au démarrage.
  final List<String> problemesIntegrite;

  /// Génération automatique des bulletins individuels (absente dans les
  /// tests qui n'en ont pas besoin).
  final BulletinsAuto? bulletinsAuto;

  List<AnneeScolaire> annees = const [];
  int? anneeId;
  Etablissement etablissement = const Etablissement();

  /// Incrémenté à chaque modification des données : les écrans comparent
  /// cette valeur pour savoir s'ils doivent se recharger.
  int version = 0;

  AnneeScolaire? get anneeCourante {
    for (final a in annees) {
      if (a.id == anneeId) return a;
    }
    return null;
  }

  /// (Re)charge la liste des années et la fiche de l'établissement.
  /// L'année sélectionnée est conservée si elle existe encore ; sinon on
  /// retombe sur l'année active, puis sur la plus récente.
  Future<void> charger() async {
    annees = await services.annees.lister();
    etablissement = await services.etablissements.lire();

    final existe = annees.any((a) => a.id == anneeId);
    if (!existe) {
      anneeId = null;
      for (final a in annees) {
        if (a.active) anneeId = a.id;
      }
      if (anneeId == null && annees.isNotEmpty) {
        anneeId = annees.first.id;
      }
    }
    version++;
    notifyListeners();
  }

  void choisirAnnee(int id) {
    anneeId = id;
    version++;
    notifyListeners();
  }

  /// À appeler après toute modification de données.
  void donneesModifiees() {
    version++;
    notifyListeners();
  }
}
