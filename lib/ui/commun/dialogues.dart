import 'package:flutter/material.dart';

import '../../data/erreurs.dart';
import '../theme.dart';

/// Affiche une notification de confirmation (verte) ou d'erreur (rouge).
void afficherMessage(
  BuildContext context,
  String message, {
  bool erreur = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: erreur ? CouleursGesco.rouge : CouleursGesco.vert,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: erreur ? 7 : 3),
    ),
  );
}

/// Demande une confirmation. Retourne vrai si l'utilisateur confirme.
Future<bool> confirmer(
  BuildContext context, {
  required String titre,
  required String message,
  String libelleConfirmer = 'Confirmer',
  bool danger = false,
}) async {
  final reponse = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titre),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: CouleursGesco.rouge)
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(libelleConfirmer),
        ),
      ],
    ),
  );
  return reponse ?? false;
}

/// Exécute [action] et affiche le résultat : message de succès si [succes]
/// est fourni, message d'erreur en cas de problème. Retourne vrai si l'action
/// a réussi.
///
/// Les erreurs métier ([ErreurGesco]) affichent leur message tel quel ; les
/// autres erreurs sont signalées comme inattendues.
Future<bool> executer(
  BuildContext context,
  Future<void> Function() action, {
  String? succes,
}) async {
  try {
    await action();
    if (succes != null && context.mounted) {
      afficherMessage(context, succes);
    }
    return true;
  } on ErreurGesco catch (e) {
    if (context.mounted) afficherMessage(context, e.message, erreur: true);
    return false;
  } catch (e) {
    if (context.mounted) {
      afficherMessage(context, 'Erreur inattendue : $e', erreur: true);
    }
    return false;
  }
}
