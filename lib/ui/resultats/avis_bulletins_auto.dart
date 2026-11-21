import 'package:flutter/material.dart';

import '../../app/bulletins_auto.dart';
import '../commun/dialogues.dart';

/// Annonce discrètement, par un message en bas de l'écran, la fin d'une
/// génération automatique de bulletins, quelle que soit la page affichée.
///
/// Les générations demandées par l'utilisateur (« Tout générer ») ne sont pas
/// annoncées ici : la carte de l'onglet Bulletins affiche déjà leur résultat.
class AvisBulletinsAuto extends StatefulWidget {
  const AvisBulletinsAuto({super.key, required this.auto, required this.child});

  /// Générateur écouté ; sans lui, le widget n'affiche que [child].
  final BulletinsAuto? auto;
  final Widget child;

  @override
  State<AvisBulletinsAuto> createState() => _AvisBulletinsAutoState();
}

class _AvisBulletinsAutoState extends State<AvisBulletinsAuto> {
  /// Dernier rapport déjà annoncé (ou déjà présent au lancement).
  RapportBulletins? _annonce;

  @override
  void initState() {
    super.initState();
    _annonce = widget.auto?.dernierRapport;
    widget.auto?.addListener(_surChangement);
  }

  @override
  void didUpdateWidget(AvisBulletinsAuto ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.auto != widget.auto) {
      ancien.auto?.removeListener(_surChangement);
      _annonce = widget.auto?.dernierRapport;
      widget.auto?.addListener(_surChangement);
    }
  }

  @override
  void dispose() {
    widget.auto?.removeListener(_surChangement);
    super.dispose();
  }

  void _surChangement() {
    final auto = widget.auto;
    if (auto == null || auto.enCours || !mounted) return;
    final rapport = auto.dernierRapport;
    if (rapport == null || identical(rapport, _annonce)) return;
    _annonce = rapport;
    if (!rapport.automatique || rapport.vide) return;
    afficherMessage(
      context,
      rapport.ok
          ? 'Bulletins mis à jour automatiquement : ${rapport.resume}.'
          : 'Bulletins automatiques : ${rapport.resume}. Détail dans Résultats › Bulletins.',
      erreur: !rapport.ok,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
