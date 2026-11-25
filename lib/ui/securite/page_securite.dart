import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../domain/permissions.dart';
import 'onglet_comptes.dart';
import 'onglet_mon_compte.dart';
import 'onglet_sauvegardes.dart';
import 'onglets_journaux.dart';

/// Sécurité : comptes et permissions, sauvegardes, journaux, historique des
/// notes et compte de la personne connectée. Chaque onglet n'apparaît que si le
/// compte a la permission correspondante.
class PageSecurite extends StatelessWidget {
  const PageSecurite({super.key, required this.etat});

  final EtatApp etat;

  @override
  Widget build(BuildContext context) {
    final onglets = <(Tab, Widget)>[
      if (etat.peut(Permission.utilisateursGerer))
        (
          const Tab(text: 'Comptes', icon: Icon(Icons.groups_outlined)),
          OngletComptes(etat: etat),
        ),
      if (etat.peut(Permission.sauvegardeGerer) && etat.sauvegarde != null)
        (
          const Tab(text: 'Sauvegardes', icon: Icon(Icons.backup_outlined)),
          OngletSauvegardes(etat: etat),
        ),
      if (etat.peut(Permission.journalVoir)) ...[
        (
          const Tab(text: 'Journal', icon: Icon(Icons.history)),
          OngletJournal(etat: etat),
        ),
        (
          const Tab(text: 'Connexions', icon: Icon(Icons.login)),
          OngletConnexions(etat: etat),
        ),
        (
          const Tab(text: 'Historique des notes', icon: Icon(Icons.grading_outlined)),
          OngletHistoriqueNotes(etat: etat),
        ),
      ],
      (
        const Tab(text: 'Mon compte', icon: Icon(Icons.person_outline)),
        OngletMonCompte(etat: etat),
      ),
    ];
    return DefaultTabController(
      key: ValueKey(onglets.length),
      length: onglets.length,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            alignment: Alignment.centerLeft,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (final o in onglets) o.$1],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(children: [for (final o in onglets) o.$2]),
          ),
        ],
      ),
    );
  }
}
