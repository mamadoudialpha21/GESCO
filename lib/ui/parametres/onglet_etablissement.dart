import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/erreurs.dart';
import '../../data/images.dart';
import '../../data/modeles_donnees.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../theme.dart';

/// Nom, logo, adresse et coordonnées de l'établissement. Le logo apparaîtra
/// automatiquement sur tous les documents imprimables.
class OngletEtablissement extends StatefulWidget {
  const OngletEtablissement({super.key, required this.etat});

  final EtatApp etat;

  @override
  State<OngletEtablissement> createState() => _OngletEtablissementState();
}

class _OngletEtablissementState extends State<OngletEtablissement> {
  late final TextEditingController _nom;
  late final TextEditingController _adresse;
  late final TextEditingController _telephone;
  late final TextEditingController _email;
  Uint8List? _logo;

  @override
  void initState() {
    super.initState();
    final e = widget.etat.etablissement;
    _nom = TextEditingController(text: e.nom);
    _adresse = TextEditingController(text: e.adresse);
    _telephone = TextEditingController(text: e.telephone);
    _email = TextEditingController(text: e.email);
    _logo = e.logo;
  }

  @override
  void dispose() {
    _nom.dispose();
    _adresse.dispose();
    _telephone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _choisirLogo() async {
    final resultat = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (resultat == null || resultat.files.isEmpty) return;

    final fichier = resultat.files.single;
    Uint8List? octets = fichier.bytes;
    final chemin = fichier.path;
    if (octets == null && chemin != null) {
      octets = await File(chemin).readAsBytes();
    }
    if (!mounted) return;
    if (octets == null) {
      afficherMessage(context, 'Impossible de lire le fichier choisi.', erreur: true);
      return;
    }
    try {
      verifierImage(octets, tailleMax: tailleMaxLogo, nom: 'Le logo');
    } on ErreurGesco catch (e) {
      afficherMessage(context, e.message, erreur: true);
      return;
    }
    setState(() => _logo = octets);
  }

  Future<void> _enregistrer() async {
    final etat = widget.etat;
    final ok = await executer(
      context,
      () => etat.services.etablissements.enregistrer(
        Etablissement(
          nom: _nom.text,
          adresse: _adresse.text,
          telephone: _telephone.text,
          email: _email.text,
          logo: _logo,
        ),
      ),
      succes: 'Informations de l\'établissement enregistrées.',
    );
    if (ok) await etat.charger();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const TitreSection(
          'Établissement',
          sousTitre:
              'Ces informations figurent en en-tête des bulletins et des documents imprimés.',
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _nom,
                      decoration: champ('Nom de l\'établissement'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _adresse,
                      decoration: champ('Adresse'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _telephone,
                            decoration: champ('Téléphone'),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _email,
                            decoration: champ('E-mail'),
                            keyboardType: TextInputType.emailAddress,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Logo',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
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
                          child: _logo == null
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
                                    _logo!,
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
                              onPressed: _choisirLogo,
                              icon: const Icon(Icons.upload_file),
                              label: Text(
                                _logo == null ? 'Choisir un logo…' : 'Changer le logo…',
                              ),
                            ),
                            if (_logo != null)
                              TextButton.icon(
                                onPressed: () => setState(() => _logo = null),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Retirer le logo'),
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
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _enregistrer,
                      icon: const Icon(Icons.save),
                      label: const Text('Enregistrer'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
