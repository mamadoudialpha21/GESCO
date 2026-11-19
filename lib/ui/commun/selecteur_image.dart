import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/erreurs.dart';
import '../../data/images.dart';
import '../theme.dart';
import 'dialogues.dart';

/// Ouvre le sélecteur de fichier et retourne l'image PNG/JPEG choisie, ou null
/// si l'utilisateur annule ou si l'image est refusée (un message explique
/// alors pourquoi). [nom] est le sujet des messages : « Le logo », « La photo ».
Future<Uint8List?> choisirImage(
  BuildContext context,
  String nom, {
  int tailleMax = tailleMaxLogo,
}) async {
  final resultat = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['png', 'jpg', 'jpeg'],
    withData: true,
  );
  if (resultat == null || resultat.files.isEmpty) return null;

  final fichier = resultat.files.single;
  Uint8List? octets = fichier.bytes;
  final chemin = fichier.path;
  if (octets == null && chemin != null) {
    octets = await File(chemin).readAsBytes();
  }
  if (!context.mounted) return null;
  if (octets == null) {
    afficherMessage(context, 'Impossible de lire le fichier choisi.', erreur: true);
    return null;
  }
  try {
    verifierImage(octets, tailleMax: tailleMax, nom: nom);
  } on ErreurGesco catch (e) {
    afficherMessage(context, e.message, erreur: true);
    return null;
  }
  return octets;
}

/// Aperçu d'une image (logo, signature, cachet) avec les boutons pour la
/// choisir ou la retirer.
class SelecteurImage extends StatelessWidget {
  const SelecteurImage({
    super.key,
    required this.titre,
    required this.image,
    required this.onChoisir,
    required this.onRetirer,
  });

  final String titre;
  final Uint8List? image;
  final VoidCallback onChoisir;
  final VoidCallback onRetirer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titre, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: CouleursGesco.grisClair,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black12),
              ),
              child: image == null
                  ? const Center(
                      child: Icon(
                        Icons.image_outlined,
                        size: 40,
                        color: CouleursGesco.gris,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(6),
                      child: Image.memory(
                        image!,
                        fit: BoxFit.contain,
                        errorBuilder: (context, erreur, trace) =>
                            const Center(child: Text('Image illisible')),
                      ),
                    ),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutlinedButton.icon(
                  onPressed: onChoisir,
                  icon: const Icon(Icons.upload_file),
                  label: Text(image == null ? 'Choisir une image…' : 'Changer l\'image…'),
                ),
                if (image != null)
                  TextButton.icon(
                    onPressed: onRetirer,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Retirer'),
                  ),
                const SizedBox(height: 4),
                const Text(
                  'PNG ou JPEG, 2 Mo maximum.',
                  style: TextStyle(color: CouleursGesco.gris),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
