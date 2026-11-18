import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/acces.dart';
import '../../data/erreurs.dart';
import '../../data/modeles_securite.dart';
import '../commun/composants.dart';
import '../theme.dart';
import 'cadre_acces.dart';

/// Premier démarrage : création du compte administrateur, puis affichage
/// (une seule fois) du code de récupération.
class EcranPremierDemarrage extends StatefulWidget {
  const EcranPremierDemarrage({super.key, required this.acces});

  final Acces acces;

  @override
  State<EcranPremierDemarrage> createState() => _EcranPremierDemarrageState();
}

class _EcranPremierDemarrageState extends State<EcranPremierDemarrage> {
  final _nom = TextEditingController();
  final _identifiant = TextEditingController(text: 'admin');
  final _motDePasse = TextEditingController();
  final _confirmation = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  Utilisateur? _cree;
  String? _code;
  bool _note = false;

  @override
  void dispose() {
    _nom.dispose();
    _identifiant.dispose();
    _motDePasse.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _creer() async {
    if (_enCours) return;
    if (_motDePasse.text != _confirmation.text) {
      setState(() => _erreur = 'Les deux mots de passe ne sont pas identiques.');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final r = await widget.acces.creerPremierAdministrateur(
        identifiant: _identifiant.text,
        nomComplet: _nom.text,
        motDePasse: _motDePasse.text,
      );
      if (mounted) {
        setState(() {
          _cree = r.utilisateur;
          _code = r.codeRecuperation;
        });
      }
    } on ErreurGesco catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } catch (e) {
      if (mounted) setState(() => _erreur = 'Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_code != null && _cree != null) return _ecranCode(context);
    return CadreAcces(
      titre: 'Bienvenue dans GESCO',
      sousTitre: 'Créez le compte administrateur. Il pourra ensuite créer les '
          'comptes de la direction et des enseignants.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('premier_nom'),
            controller: _nom,
            decoration: champ('Nom complet (facultatif)'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('premier_identifiant'),
            controller: _identifiant,
            autocorrect: false,
            decoration: champ(
              'Identifiant',
              aide: 'Lettres, chiffres, point, tiret (3 caractères minimum)',
            ),
          ),
          const SizedBox(height: 12),
          ChampMotDePasse(
            key: const Key('premier_mot_de_passe'),
            controleur: _motDePasse,
            libelle: 'Mot de passe',
            aide: '6 caractères minimum',
          ),
          const SizedBox(height: 12),
          ChampMotDePasse(
            key: const Key('premier_confirmation'),
            controleur: _confirmation,
            libelle: 'Confirmer le mot de passe',
            onSubmitted: _creer,
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 12),
            MessageErreur(_erreur!),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('bouton_creer_admin'),
            onPressed: _enCours ? null : _creer,
            child: const Text('Créer le compte'),
          ),
        ],
      ),
    );
  }

  Widget _ecranCode(BuildContext context) {
    return CadreAcces(
      titre: 'Code de récupération',
      sousTitre: 'Si vous oubliez le mot de passe de l\'administrateur, ce code '
          'est le seul moyen de retrouver l\'accès sans perdre de données. '
          'Il ne sera plus affiché.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: CouleursGesco.bleuClair,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              _code!,
              key: const Key('code_recuperation'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: CouleursGesco.texte,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _code!));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Code copié')),
                  );
                }
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copier'),
            ),
          ),
          CheckboxListTile(
            key: const Key('case_code_note'),
            value: _note,
            onChanged: (v) => setState(() => _note = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'J\'ai noté ce code et je le garde en lieu sûr.',
              style: TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('bouton_commencer'),
            onPressed: _note ? () => widget.acces.demarrer(_cree!) : null,
            child: const Text('Commencer'),
          ),
        ],
      ),
    );
  }
}
