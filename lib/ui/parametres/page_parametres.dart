import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import 'onglet_annees.dart';
import 'onglet_classes_matieres.dart';
import 'onglet_enseignants.dart';
import 'onglet_etablissement.dart';
import 'onglet_resultats.dart';

/// Espace de configuration : établissement, années, classes et matières,
/// enseignants, mentions et décisions.
class PageParametres extends StatelessWidget {
  const PageParametres({super.key, required this.etat});

  final EtatApp etat;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            alignment: Alignment.centerLeft,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'Établissement', icon: Icon(Icons.school_outlined)),
                Tab(text: 'Années scolaires', icon: Icon(Icons.event_outlined)),
                Tab(
                  text: 'Classes et matières',
                  icon: Icon(Icons.menu_book_outlined),
                ),
                Tab(text: 'Enseignants', icon: Icon(Icons.badge_outlined)),
                Tab(
                  text: 'Mentions et décisions',
                  icon: Icon(Icons.emoji_events_outlined),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              children: [
                OngletEtablissement(etat: etat),
                OngletAnnees(etat: etat),
                OngletClassesMatieres(etat: etat),
                OngletEnseignants(etat: etat),
                OngletResultats(etat: etat),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
