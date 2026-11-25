import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/gesco_database.dart';
import '../sauvegarde/service_sauvegarde.dart';
import 'bulletins_auto.dart';
import 'etat_app.dart';
import 'gestion_base.dart';
import 'planificateur_sauvegarde.dart';
import 'services.dart';
import 'session.dart';

/// Ouvre la base et construit tout ce qui en dépend (services, état de
/// l'application, bulletins automatiques, sauvegarde automatique). Après une
/// restauration, la base est remplacée : [redemarrer] reconstruit tout sur la
/// nouvelle connexion et [etat] change, ce qui reconstruit l'interface.
class GestionBaseApp implements GestionBase {
  GestionBaseApp._({
    required this.fabrique,
    required this.chemin,
    required this.creerBulletinsAuto,
    required this.demarrerPlanificateur,
    required GescoDatabase gdb,
  }) : _gdb = gdb;

  final DatabaseFactory fabrique;

  /// Fichier de la base de données.
  final String chemin;

  /// Crée (et démarre) la génération automatique des bulletins d'une base.
  final BulletinsAuto Function(Services services)? creerBulletinsAuto;
  final bool demarrerPlanificateur;

  GescoDatabase _gdb;

  /// État courant de l'application. Change après une restauration.
  late final ValueNotifier<EtatApp> etat;

  /// Ouvre la base et construit l'application.
  static Future<GestionBaseApp> demarrer({
    required DatabaseFactory fabrique,
    required String chemin,
    BulletinsAuto Function(Services services)? creerBulletinsAuto,
    bool demarrerPlanificateur = true,
  }) async {
    final gdb = await GescoDatabase.ouvrir(fabrique: fabrique, chemin: chemin);
    final g = GestionBaseApp._(
      fabrique: fabrique,
      chemin: chemin,
      creerBulletinsAuto: creerBulletinsAuto,
      demarrerPlanificateur: demarrerPlanificateur,
      gdb: gdb,
    );
    g.etat = ValueNotifier<EtatApp>(await g._construire());
    return g;
  }

  Future<EtatApp> _construire() async {
    final problemes = await _gdb.verifierIntegrite();
    final services = Services(_gdb, session: Session());
    final sauvegarde = ServiceSauvegarde(services, fabrique: fabrique, cheminBase: chemin);
    final planificateur = PlanificateurSauvegarde(sauvegarde);
    final e = EtatApp(
      services,
      chemin: chemin,
      problemesIntegrite: problemes,
      bulletinsAuto: creerBulletinsAuto?.call(services),
      sauvegarde: sauvegarde,
      planificateurSauvegarde: planificateur,
      gestionBase: this,
    );
    await e.charger();
    await e.acces.charger();
    if (demarrerPlanificateur) planificateur.demarrer();
    return e;
  }

  void _arreterTravauxEnCours(EtatApp e) {
    e.planificateurSauvegarde?.arreter();
    e.bulletinsAuto?.arreter();
  }

  @override
  Future<ResultatRestauration> restaurer(
    String cheminSauvegarde, {
    void Function(EtapeRestauration etape)? progression,
  }) {
    final courant = etat.value;
    return courant.sauvegarde!.restaurer(
      cheminSauvegarde,
      fermerBase: () async {
        _arreterTravauxEnCours(courant);
        await _gdb.fermer();
      },
      ouvrirBase: () async {
        _gdb = await GescoDatabase.ouvrir(fabrique: fabrique, chemin: chemin);
        return _gdb;
      },
      progression: progression,
    );
  }

  @override
  Future<void> redemarrer() async {
    final ancien = etat.value;
    _arreterTravauxEnCours(ancien);
    etat.value = await _construire();
  }

  /// Arrête tout et ferme la base (fermeture de l'application, tests).
  Future<void> fermer() async {
    _arreterTravauxEnCours(etat.value);
    await _gdb.fermer();
  }
}
