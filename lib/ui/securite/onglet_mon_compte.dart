import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/depots/parametre_depot.dart';
import '../../domain/permissions.dart';
import '../acces/ecran_mot_de_passe.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../theme.dart';

/// Compte de la personne connectée : mot de passe, verrouillage,
/// déconnexion et (pour qui peut modifier les paramètres) délai de
/// verrouillage automatique.
class OngletMonCompte extends StatefulWidget {
  const OngletMonCompte({super.key, required this.etat});

  final EtatApp etat;

  @override
  State<OngletMonCompte> createState() => _OngletMonCompteState();
}

class _OngletMonCompteState extends State<OngletMonCompte> {
  static const List<int> _delais = [5, 10, 15, 30, 60, 120];

  EtatApp get etat => widget.etat;

  Future<void> _changerDelai(int? minutes) async {
    if (minutes == null) return;
    final ok = await executer(
      context,
      () async {
        etat.services.controle.exiger(
          Permission.parametresGerer,
          'modifier le délai de verrouillage',
        );
        await etat.services.parametres.ecrire(
          CleParametre.delaiInactiviteMinutes,
          '$minutes',
        );
        etat.services.session.delaiInactivite = Duration(minutes: minutes);
      },
      succes: 'Verrouillage automatique après $minutes minutes d\'inactivité.',
    );
    if (ok && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = etat.services.session;
    final u = session.utilisateur;
    final minutes = session.delaiInactivite.inMinutes;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const TitreSection(
          'Mon compte',
          sousTitre: 'Votre mot de passe et votre session.',
        ),
        const SizedBox(height: 16),
        if (u == null)
          const Carte(
            padding: EdgeInsets.all(16),
            child: Text(
              'Aucune connexion n\'est demandée dans ce mode : toutes les '
              'opérations sont autorisées.',
            ),
          )
        else ...[
          Carte(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.nomAffiche,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Identifiant : ${u.identifiant}',
                  style: const TextStyle(color: CouleursGesco.gris),
                ),
                const SizedBox(height: 8),
                Etiquette(
                  u.role.libelle,
                  couleur: CouleursGesco.bleu,
                  fond: CouleursGesco.bleuClair,
                ),
                const SizedBox(height: 4),
                Text(
                  u.role.description,
                  style: const TextStyle(color: CouleursGesco.gris),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('bouton_mon_mdp'),
                      onPressed: () => demanderChangementMotDePasse(context, etat.acces),
                      icon: const Icon(Icons.key_outlined),
                      label: const Text('Changer mon mot de passe'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('bouton_verrouiller'),
                      onPressed: () => etat.acces.verrouiller(),
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Verrouiller'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('bouton_deconnexion'),
                      onPressed: () => etat.acces.seDeconnecter(),
                      icon: const Icon(Icons.logout),
                      label: const Text('Se déconnecter'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Carte(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, color: CouleursGesco.bleu),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Verrouillage automatique : après ce temps sans activité, '
                    'le mot de passe est redemandé.',
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  key: const Key('choix_delai'),
                  value: _delais.contains(minutes) ? minutes : null,
                  hint: Text('$minutes min'),
                  items: [
                    for (final m in _delais)
                      DropdownMenuItem(value: m, child: Text('$m min')),
                  ],
                  onChanged: etat.peut(Permission.parametresGerer) ? _changerDelai : null,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
