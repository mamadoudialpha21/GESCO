import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/modeles_donnees.dart';
import '../../domain/permissions.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../commun/selecteur_image.dart';

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
  late final TextEditingController _directeur;
  late final TextEditingController _devise;
  late final TextEditingController _infosAdmin;
  Uint8List? _logo;
  Uint8List? _signature;
  Uint8List? _cachet;

  @override
  void initState() {
    super.initState();
    final e = widget.etat.etablissement;
    _nom = TextEditingController(text: e.nom);
    _adresse = TextEditingController(text: e.adresse);
    _telephone = TextEditingController(text: e.telephone);
    _email = TextEditingController(text: e.email);
    _directeur = TextEditingController(text: e.directeur);
    _devise = TextEditingController(text: e.devise);
    _infosAdmin = TextEditingController(text: e.infosAdmin);
    _logo = e.logo;
    _signature = e.signatureDirecteur;
    _cachet = e.cachet;
  }

  @override
  void dispose() {
    _nom.dispose();
    _adresse.dispose();
    _telephone.dispose();
    _email.dispose();
    _directeur.dispose();
    _devise.dispose();
    _infosAdmin.dispose();
    super.dispose();
  }

  Future<Uint8List?> _choisirImage(String nom) => choisirImage(context, nom);

  Future<void> _choisirLogo() async {
    final image = await _choisirImage('Le logo');
    if (image != null) setState(() => _logo = image);
  }

  Future<void> _choisirSignature() async {
    final image = await _choisirImage('La signature');
    if (image != null) setState(() => _signature = image);
  }

  Future<void> _choisirCachet() async {
    final image = await _choisirImage('Le cachet');
    if (image != null) setState(() => _cachet = image);
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
          directeur: _directeur.text,
          devise: _devise.text,
          infosAdmin: _infosAdmin.text,
          signatureDirecteur: _signature,
          cachet: _cachet,
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
              'Ces informations figurent en en-tête des bulletins et des documents imprimés ; la signature et le cachet apparaissent en bas des bulletins.',
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Carte(
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
                    const SizedBox(height: 16),
                    TextField(
                      controller: _directeur,
                      decoration: champ('Directeur ou directrice'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _devise,
                      decoration: champ('Devise'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _infosAdmin,
                      decoration: champ(
                        'Informations administratives',
                        aide: 'Agrément, boîte postale, ville... (imprimé dans l\'en-tête)',
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),
                    SelecteurImage(
                      titre: 'Logo',
                      image: _logo,
                      onChoisir: _choisirLogo,
                      onRetirer: () => setState(() => _logo = null),
                    ),
                    const SizedBox(height: 20),
                    SelecteurImage(
                      titre: 'Signature du directeur',
                      image: _signature,
                      onChoisir: _choisirSignature,
                      onRetirer: () => setState(() => _signature = null),
                    ),
                    const SizedBox(height: 20),
                    SelecteurImage(
                      titre: 'Cachet de l\'établissement',
                      image: _cachet,
                      onChoisir: _choisirCachet,
                      onRetirer: () => setState(() => _cachet = null),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed:
                          widget.etat.peut(Permission.etablissementModifier)
                              ? _enregistrer
                              : null,
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
