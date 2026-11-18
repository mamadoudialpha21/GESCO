import 'package:flutter/material.dart';

import '../../app/acces.dart';
import '../../data/erreurs.dart';
import '../commun/dialogues.dart';
import 'cadre_acces.dart';

/// Formulaire de changement de mot de passe (ancien, nouveau, confirmation).
class FormulaireMotDePasse extends StatefulWidget {
  const FormulaireMotDePasse({
    super.key,
    required this.acces,
    required this.apres,
    this.libelleBouton = 'Changer le mot de passe',
  });

  final Acces acces;

  /// Appelé après un changement réussi.
  final VoidCallback apres;
  final String libelleBouton;

  @override
  State<FormulaireMotDePasse> createState() => _FormulaireMotDePasseState();
}

class _FormulaireMotDePasseState extends State<FormulaireMotDePasse> {
  final _ancien = TextEditingController();
  final _nouveau = TextEditingController();
  final _confirmation = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _ancien.dispose();
    _nouveau.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_enCours) return;
    if (_nouveau.text != _confirmation.text) {
      setState(() => _erreur = 'Les deux nouveaux mots de passe ne sont pas identiques.');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await widget.acces.changerMotDePasse(
        ancien: _ancien.text,
        nouveau: _nouveau.text,
      );
      if (mounted) widget.apres();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ChampMotDePasse(
          key: const Key('mdp_ancien'),
          controleur: _ancien,
          libelle: 'Mot de passe actuel',
          autofocus: true,
        ),
        const SizedBox(height: 12),
        ChampMotDePasse(
          key: const Key('mdp_nouveau'),
          controleur: _nouveau,
          libelle: 'Nouveau mot de passe',
          aide: '6 caractères minimum',
        ),
        const SizedBox(height: 12),
        ChampMotDePasse(
          key: const Key('mdp_confirmation'),
          controleur: _confirmation,
          libelle: 'Confirmer le nouveau mot de passe',
          onSubmitted: _valider,
        ),
        if (_erreur != null) ...[
          const SizedBox(height: 12),
          MessageErreur(_erreur!),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('bouton_changer_mdp'),
          onPressed: _enCours ? null : _valider,
          child: Text(widget.libelleBouton),
        ),
      ],
    );
  }
}

/// Écran plein cadre : le mot de passe doit être changé avant de continuer
/// (compte créé ou réinitialisé par un administrateur).
class EcranChangementObligatoire extends StatelessWidget {
  const EcranChangementObligatoire({super.key, required this.acces});

  final Acces acces;

  @override
  Widget build(BuildContext context) {
    return CadreAcces(
      titre: 'Choisissez votre mot de passe',
      sousTitre: 'Un administrateur a défini un mot de passe provisoire pour '
          'votre compte. Remplacez-le par un mot de passe que vous êtes seul '
          'à connaître.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormulaireMotDePasse(acces: acces, apres: () {}, libelleBouton: 'Continuer'),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => acces.seDeconnecter(),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
  }
}

/// Boîte de dialogue de changement volontaire du mot de passe.
Future<void> demanderChangementMotDePasse(BuildContext context, Acces acces) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Changer mon mot de passe'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: FormulaireMotDePasse(
            acces: acces,
            apres: () {
              Navigator.of(ctx).pop();
              if (context.mounted) afficherMessage(context, 'Mot de passe modifié.');
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Annuler'),
        ),
      ],
    ),
  );
}
