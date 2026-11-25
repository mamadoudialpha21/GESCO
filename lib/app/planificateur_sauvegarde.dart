import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/erreurs.dart';
import '../sauvegarde/service_sauvegarde.dart';

/// Lance la sauvegarde automatique : une vérification peu après le démarrage
/// de GESCO (elle rattrape une sauvegarde manquée parce que l'ordinateur était
/// éteint à l'heure prévue), puis une vérification chaque minute.
///
/// Un échec n'est jamais silencieux : [derniereErreur] est affichée dans
/// l'écran des sauvegardes. Après un échec, la prochaine tentative n'a lieu
/// qu'après [pauseApresEchec], pour ne pas recommencer toutes les minutes.
class PlanificateurSauvegarde extends ChangeNotifier {
  PlanificateurSauvegarde(
    this.service, {
    this.delaiDemarrage = const Duration(seconds: 5),
    this.intervalle = const Duration(minutes: 1),
    this.pauseApresEchec = const Duration(minutes: 15),
    DateTime Function()? maintenant,
  }) : _maintenant = maintenant ?? DateTime.now;

  final ServiceSauvegarde service;

  /// Attente avant la première vérification, au démarrage.
  final Duration delaiDemarrage;

  /// Temps entre deux vérifications.
  final Duration intervalle;
  final Duration pauseApresEchec;
  final DateTime Function() _maintenant;

  Timer? _depart;
  Timer? _minuteur;
  bool _arrete = true;
  bool _enCours = false;
  DateTime? _dernierEchec;

  /// Dernière sauvegarde automatique faite depuis le démarrage de GESCO.
  ResultatSauvegarde? derniere;

  /// Pourquoi la dernière tentative a échoué (null après une réussite).
  String? derniereErreur;

  /// La sauvegarde est bonne mais la copie externe a échoué (clé retirée...).
  String? dernierAvertissement;

  bool get enCours => _enCours;
  bool get actif => !_arrete;

  /// Commence la surveillance (sans effet si elle est déjà en cours).
  void demarrer() {
    if (!_arrete) return;
    _arrete = false;
    _depart = Timer(delaiDemarrage, verifier);
    _minuteur = Timer.periodic(intervalle, (_) => verifier());
  }

  /// Fait la sauvegarde automatique si elle est due. Appelée par les
  /// minuteries ; peut aussi l'être directement.
  Future<void> verifier() async {
    if (_arrete || _enCours) return;
    final echec = _dernierEchec;
    if (echec != null && _maintenant().difference(echec) < pauseApresEchec) return;
    _enCours = true;
    try {
      final r = await service.executerSiDue();
      if (_arrete) return;
      if (r != null) {
        derniere = r;
        derniereErreur = null;
        dernierAvertissement = r.avertissement;
        _dernierEchec = null;
        notifyListeners();
      }
    } catch (e) {
      if (_arrete) return;
      derniereErreur = e is ErreurGesco ? e.message : '$e';
      _dernierEchec = _maintenant();
      notifyListeners();
    } finally {
      _enCours = false;
    }
  }

  /// Arrête la surveillance (avant de fermer la base, à la fermeture).
  void arreter() {
    _arrete = true;
    _depart?.cancel();
    _minuteur?.cancel();
    _depart = null;
    _minuteur = null;
  }

  @override
  void dispose() {
    arreter();
    super.dispose();
  }
}
