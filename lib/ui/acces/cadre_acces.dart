import 'package:flutter/material.dart';

import '../commun/composants.dart';
import '../theme.dart';

/// Fond bleu et carte centrée des écrans d'accès (connexion, premier
/// démarrage, changement de mot de passe).
class CadreAcces extends StatelessWidget {
  const CadreAcces({
    super.key,
    required this.titre,
    this.sousTitre,
    required this.child,
    this.largeurMax = 440,
  });

  final String titre;
  final String? sousTitre;
  final Widget child;
  final double largeurMax;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleursGesco.bleuFonce,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: largeurMax),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: CouleursGesco.bleu,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.school, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'GESCO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Carte(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          titre,
                          style: const TextStyle(
                            color: CouleursGesco.texte,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (sousTitre != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            sousTitre!,
                            style: const TextStyle(color: CouleursGesco.gris),
                          ),
                        ],
                        const SizedBox(height: 18),
                        child,
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline, size: 14, color: Color(0xFFB7C9E4)),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Hors ligne : vos données restent sur cet ordinateur',
                          style: TextStyle(color: Color(0xFFB7C9E4), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Champ de mot de passe avec bouton « afficher / masquer ».
class ChampMotDePasse extends StatefulWidget {
  const ChampMotDePasse({
    super.key,
    required this.controleur,
    required this.libelle,
    this.aide,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controleur;
  final String libelle;
  final String? aide;
  final VoidCallback? onSubmitted;
  final bool autofocus;

  @override
  State<ChampMotDePasse> createState() => _ChampMotDePasseState();
}

class _ChampMotDePasseState extends State<ChampMotDePasse> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controleur,
      obscureText: !_visible,
      autofocus: widget.autofocus,
      enableSuggestions: false,
      autocorrect: false,
      onSubmitted: widget.onSubmitted == null ? null : (_) => widget.onSubmitted!(),
      decoration: champ(widget.libelle, aide: widget.aide).copyWith(
        suffixIcon: IconButton(
          tooltip: _visible ? 'Masquer' : 'Afficher',
          icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
    );
  }
}

/// Message d'erreur sous un formulaire.
class MessageErreur extends StatelessWidget {
  const MessageErreur(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: CouleursGesco.rougeClair,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: CouleursGesco.rouge),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              key: const Key('message_erreur'),
              style: const TextStyle(color: CouleursGesco.rouge, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
