import 'package:flutter/material.dart';

import '../../app/acces.dart';
import '../../data/erreurs.dart';
import '../commun/composants.dart';
import '../theme.dart';
import 'cadre_acces.dart';

/// Connexion, ou déverrouillage d'une session verrouillée (le compte est
/// alors connu : seul le mot de passe est demandé).
class EcranConnexion extends StatefulWidget {
  const EcranConnexion({super.key, required this.acces, this.deverrouillage = false});

  final Acces acces;
  final bool deverrouillage;

  @override
  State<EcranConnexion> createState() => _EcranConnexionState();
}

class _EcranConnexionState extends State<EcranConnexion> {
  final _identifiant = TextEditingController();
  final _motDePasse = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _identifiant.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_enCours) return;
    final identifiant = _identifiant.text.trim();
    if (!widget.deverrouillage && identifiant.isEmpty) {
      setState(() => _erreur = 'Saisissez votre identifiant.');
      return;
    }
    if (_motDePasse.text.isEmpty) {
      setState(() => _erreur = 'Saisissez votre mot de passe.');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      if (widget.deverrouillage) {
        await widget.acces.deverrouiller(_motDePasse.text);
      } else {
        await widget.acces.seConnecter(identifiant, _motDePasse.text);
      }
      // La porte d'accès affiche l'application dès que la session est ouverte.
    } on ErreurGesco catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _motDePasse.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = 'Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _oublie() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _DialogueRecuperation(acces: widget.acces),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.acces.session.utilisateur;
    final verrou = widget.deverrouillage;
    return CadreAcces(
      titre: verrou ? 'Session verrouillée' : 'Connexion',
      sousTitre: verrou
          ? 'Saisissez le mot de passe de ${u?.nomAffiche ?? 'votre compte'} '
              'pour reprendre.'
          : 'Identifiez-vous pour accéder à GESCO.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!verrou) ...[
            TextField(
              key: const Key('champ_identifiant'),
              controller: _identifiant,
              autofocus: true,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: champ('Identifiant'),
            ),
            const SizedBox(height: 12),
          ],
          ChampMotDePasse(
            key: const Key('champ_mot_de_passe'),
            controleur: _motDePasse,
            libelle: 'Mot de passe',
            autofocus: verrou,
            onSubmitted: _valider,
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 12),
            MessageErreur(_erreur!),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('bouton_connexion'),
            onPressed: _enCours ? null : _valider,
            child: Text(verrou ? 'Déverrouiller' : 'Se connecter'),
          ),
          const SizedBox(height: 8),
          if (verrou)
            TextButton(
              key: const Key('bouton_changer_utilisateur'),
              onPressed: _enCours ? null : () => widget.acces.seDeconnecter(),
              child: const Text('Changer d\'utilisateur'),
            )
          else
            TextButton(
              key: const Key('bouton_mot_de_passe_oublie'),
              onPressed: _enCours ? null : _oublie,
              child: const Text('Mot de passe oublié (administrateur)'),
            ),
        ],
      ),
    );
  }
}

/// Un administrateur qui a perdu son mot de passe le réinitialise avec le
/// code de récupération remis à la création du compte.
class _DialogueRecuperation extends StatefulWidget {
  const _DialogueRecuperation({required this.acces});

  final Acces acces;

  @override
  State<_DialogueRecuperation> createState() => _DialogueRecuperationState();
}

class _DialogueRecuperationState extends State<_DialogueRecuperation> {
  final _identifiant = TextEditingController();
  final _code = TextEditingController();
  final _nouveau = TextEditingController();
  final _confirmation = TextEditingController();
  String? _erreur;
  String? _nouveauCode;
  bool _enCours = false;

  @override
  void dispose() {
    _identifiant.dispose();
    _code.dispose();
    _nouveau.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_nouveau.text != _confirmation.text) {
      setState(() => _erreur = 'Les deux mots de passe ne sont pas identiques.');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final code = await widget.acces.recuperer(
        identifiant: _identifiant.text,
        code: _code.text,
        nouveauMotDePasse: _nouveau.text,
      );
      if (mounted) setState(() => _nouveauCode = code);
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
    if (_nouveauCode != null) {
      return AlertDialog(
        title: const Text('Mot de passe réinitialisé'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Vous pouvez maintenant vous connecter. L\'ancien code de '
              'récupération n\'est plus valable : notez le nouveau et '
              'gardez-le en lieu sûr.',
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: CouleursGesco.bleuClair,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                _nouveauCode!,
                key: const Key('nouveau_code_recuperation'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('J\'ai noté le code'),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('Récupérer l\'accès'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Saisissez l\'identifiant d\'un administrateur et le code de '
                'récupération remis lors de la création du compte.',
                style: TextStyle(color: CouleursGesco.gris),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('recup_identifiant'),
                controller: _identifiant,
                autocorrect: false,
                decoration: champ('Identifiant de l\'administrateur'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('recup_code'),
                controller: _code,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: champ('Code de récupération', aide: 'XXXX-XXXX-XXXX-XXXX'),
              ),
              const SizedBox(height: 10),
              ChampMotDePasse(
                key: const Key('recup_nouveau'),
                controleur: _nouveau,
                libelle: 'Nouveau mot de passe',
              ),
              const SizedBox(height: 10),
              ChampMotDePasse(
                key: const Key('recup_confirmation'),
                controleur: _confirmation,
                libelle: 'Confirmer le mot de passe',
                onSubmitted: _valider,
              ),
              if (_erreur != null) ...[
                const SizedBox(height: 12),
                MessageErreur(_erreur!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enCours ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('bouton_recuperer'),
          onPressed: _enCours ? null : _valider,
          child: const Text('Réinitialiser'),
        ),
      ],
    );
  }
}
