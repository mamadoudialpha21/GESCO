import 'package:flutter/material.dart';

import '../commun/composants.dart';
import '../theme.dart';

/// Ce qu'une création de fichiers Excel a produit.
class ProduitExcel {
  const ProduitExcel({
    required this.titre,
    required this.chemins,
    this.avertissements = const [],
    this.ouvert = false,
  });

  /// Phrase de résultat : « Fichier créé : 3 feuilles ».
  final String titre;

  /// Chemins complets des fichiers enregistrés et vérifiés.
  final List<String> chemins;
  final List<String> avertissements;

  /// Vrai si le fichier a été ouvert dans Excel (un seul fichier).
  final bool ouvert;
}

/// Carte « fichier créé » : emplacement exact, remarques éventuelles et
/// boutons pour ouvrir le fichier ou son dossier.
class CarteProduit extends StatelessWidget {
  const CarteProduit({
    super.key,
    required this.produit,
    required this.ouvrir,
    required this.dossier,
  });

  final ProduitExcel produit;

  /// Ouvre un fichier (ou un dossier) dans le programme du système.
  final Future<bool> Function(String chemin) ouvrir;

  /// Dossier des fichiers, ouvert par le bouton « Ouvrir le dossier ».
  final String dossier;

  @override
  Widget build(BuildContext context) {
    return Carte(
      key: const Key('excel_resultat'),
      padding: const EdgeInsets.all(16),
      couleur: CouleursGesco.vertClair,
      bordure: CouleursGesco.vert,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: CouleursGesco.vert),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  produit.titre,
                  key: const Key('excel_resultat_titre'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < produit.chemins.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SelectableText(
                produit.chemins[i],
                key: Key('excel_fichier_$i'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          if (!produit.ouvert && produit.chemins.length == 1) ...[
            const SizedBox(height: 8),
            const Text(
              'Le fichier n\'a pas pu être ouvert automatiquement : ouvrez-le depuis '
              'l\'emplacement ci-dessus.',
              key: Key('excel_non_ouvert'),
              style: TextStyle(color: CouleursGesco.gris),
            ),
          ],
          if (produit.avertissements.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final a in produit.avertissements)
              Text('• $a', style: const TextStyle(color: CouleursGesco.gris)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (produit.chemins.length == 1)
                OutlinedButton.icon(
                  key: const Key('excel_ouvrir_fichier'),
                  onPressed: () => ouvrir(produit.chemins.first),
                  icon: const Icon(Icons.table_chart_outlined, size: 18),
                  label: const Text('Ouvrir le fichier'),
                ),
              OutlinedButton.icon(
                key: const Key('excel_ouvrir_dossier'),
                onPressed: () => ouvrir(dossier),
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Ouvrir le dossier'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
