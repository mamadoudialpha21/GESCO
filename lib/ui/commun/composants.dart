import 'package:flutter/material.dart';

import '../theme.dart';

OutlineInputBorder _traitChamp(Color couleur, [double epaisseur = 1]) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: couleur, width: epaisseur),
  );
}

/// Style commun des champs de saisie : fond blanc, coins arrondis.
InputDecoration champ(String label, {String? aide, String? erreur}) {
  return InputDecoration(
    labelText: label,
    helperText: aide,
    errorText: erreur,
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    border: _traitChamp(CouleursGesco.bordureChamp),
    enabledBorder: _traitChamp(CouleursGesco.bordureChamp),
    focusedBorder: _traitChamp(CouleursGesco.bleu, 2),
    errorBorder: _traitChamp(CouleursGesco.rouge),
    focusedErrorBorder: _traitChamp(CouleursGesco.rouge, 2),
  );
}

/// Carte plate : fond blanc, coins arrondis, fin trait gris, sans ombre.
///
/// Remplace `Card` partout pour que l'aspect soit identique sur toutes les
/// versions de Flutter (et dans les captures de test, où les ombres sont
/// dessinées en traits noirs).
class Carte extends StatelessWidget {
  const Carte({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.couleur = Colors.white,
    this.bordure = CouleursGesco.bordure,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color couleur;
  final Color bordure;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final contenu = Padding(padding: padding, child: child);
    return Card(
      margin: margin,
      elevation: 0,
      color: couleur,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: bordure),
      ),
      child: onTap == null ? contenu : InkWell(onTap: onTap, child: contenu),
    );
  }
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
