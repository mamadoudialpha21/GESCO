import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../coquille.dart';
import 'ecran_connexion.dart';
import 'ecran_mot_de_passe.dart';
import 'ecran_premier_demarrage.dart';

/// Contrôle l'entrée dans l'application : premier démarrage (création de
/// l'administrateur), connexion, verrouillage après inactivité, changement
/// obligatoire du mot de passe. Sans contrôle d'accès (tests, outils), la
/// coquille de l'application s'ouvre directement.
class PorteAcces extends StatefulWidget {
  const PorteAcces({super.key, required this.etat, this.construire});

  final EtatApp etat;

  /// Contenu affiché une fois l'accès accordé (par défaut, la coquille de
  /// l'application). Sert surtout aux tests.
  final WidgetBuilder? construire;

  @override
  State<PorteAcces> createState() => _PorteAccesState();
}

class _PorteAccesState extends State<PorteAcces> {
  Timer? _minuteur;
  bool _etaitVerrouillee = false;

  /// Ferme les boîtes de dialogue ouvertes quand la session se verrouille :
  /// elles seraient sinon visibles par-dessus l'écran de déverrouillage.
  void _surChangementSession() {
    final verrouillee = widget.etat.services.session.verrouillee;
    if (verrouillee && !_etaitVerrouillee && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    _etaitVerrouillee = verrouillee;
  }

  @override
  void initState() {
    super.initState();
    if (widget.etat.services.session.controle) {
      widget.etat.services.session.addListener(_surChangementSession);
      // Vérifie régulièrement si le délai d'inactivité est dépassé.
      _minuteur = Timer.periodic(const Duration(seconds: 15), (_) {
        widget.etat.acces.verifierInactivite();
      });
    }
  }

  @override
  void dispose() {
    widget.etat.services.session.removeListener(_surChangementSession);
    _minuteur?.cancel();
    super.dispose();
  }

  Widget _contenu(BuildContext context) =>
      widget.construire?.call(context) ?? Coquille(etat: widget.etat);

  @override
  Widget build(BuildContext context) {
    final acces = widget.etat.acces;
    final session = acces.session;
    if (!session.controle) return _contenu(context);

    return ListenableBuilder(
      listenable: Listenable.merge([acces, session]),
      builder: (context, _) {
        final utilisateur = session.utilisateur;
        if (acces.aucunCompte && utilisateur == null) {
          return EcranPremierDemarrage(acces: acces);
        }
        if (utilisateur == null) {
          return EcranConnexion(acces: acces);
        }
        if (utilisateur.doitChangerMotDePasse) {
          return EcranChangementObligatoire(acces: acces);
        }
        // La coquille reste en place (mais invisible) quand la session est
        // verrouillée : on retrouve l'écran en cours après le déverrouillage.
        return Stack(
          children: [
            Offstage(
              offstage: session.verrouillee,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => session.activite(),
                onPointerMove: (_) => session.activite(),
                onPointerSignal: (_) => session.activite(),
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: (noeud, evenement) {
                    session.activite();
                    return KeyEventResult.ignored;
                  },
                  child: KeyedSubtree(
                    key: ValueKey('coquille_${utilisateur.id}'),
                    child: _contenu(context),
                  ),
                ),
              ),
            ),
            if (session.verrouillee)
              Positioned.fill(
                child: EcranConnexion(acces: acces, deverrouillage: true),
              ),
          ],
        );
      },
    );
  }
}
