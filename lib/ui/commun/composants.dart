import 'package:flutter/material.dart';

import '../theme.dart';

/// Style commun des champs de saisie.
InputDecoration champ(String label, {String? aide, String? erreur}) {
  return InputDecoration(
    labelText: label,
    helperText: aide,
    errorText: erreur,
    border: const OutlineInputBorder(),
    isDense: true,
  );
}

/// Message centré affiché quand il n'y a rien à montrer.
class MessageVide extends StatelessWidget {
  const MessageVide(this.message, {super.key, this.icone = Icons.info_outline});

  final String message;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 48, color: CouleursGesco.gris),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: CouleursGesco.gris, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

/// Petite étiquette colorée (« Active », « Consultation »...).
class Etiquette extends StatelessWidget {
  const Etiquette(this.texte, {super.key, required this.couleur, required this.fond});

  final String texte;
  final Color couleur;
  final Color fond;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        texte,
        style: TextStyle(
          color: couleur,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Titre de section d'une page.
class TitreSection extends StatelessWidget {
  const TitreSection(this.texte, {super.key, this.sousTitre});

  final String texte;
  final String? sousTitre;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(texte, style: Theme.of(context).textTheme.titleLarge),
        if (sousTitre != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              sousTitre!,
              style: const TextStyle(color: CouleursGesco.gris),
            ),
          ),
      ],
    );
  }
}
