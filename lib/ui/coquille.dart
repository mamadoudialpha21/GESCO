import 'package:flutter/material.dart';

import '../app/etat_app.dart';
import 'commun/composants.dart';
import 'inscriptions/page_inscriptions.dart';
import 'parametres/page_parametres.dart';
import 'tableau_de_bord.dart';
import 'theme.dart';

/// Structure générale : menu de navigation, barre du haut avec le sélecteur
/// d'année scolaire, et page courante.
class Coquille extends StatefulWidget {
  const Coquille({super.key, required this.etat});

  final EtatApp etat;

  @override
  State<Coquille> createState() => _CoquilleState();
}

class _CoquilleState extends State<Coquille> {
  static const int _pageTableauDeBord = 0;
  static const int _pageInscriptions = 1;
  static const int _pageParametres = 2;

  static const List<String> _titres = [
    'Tableau de bord',
    'Inscriptions',
    'Paramètres',
  ];

  int _index = _pageTableauDeBord;

  void _aller(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.etat,
      builder: (context, _) {
        final pages = <Widget>[
          PageTableauDeBord(
            etat: widget.etat,
            allerAuxParametres: () => _aller(_pageParametres),
            allerAuxInscriptions: () => _aller(_pageInscriptions),
          ),
          PageInscriptions(
            etat: widget.etat,
            allerAuxParametres: () => _aller(_pageParametres),
          ),
          PageParametres(etat: widget.etat),
        ];

        return LayoutBuilder(
          builder: (context, contraintes) {
            final etroit = contraintes.maxWidth < 760;
            final contenu = Column(
              children: [
                _BarreSuperieure(
                  etat: widget.etat,
                  titre: _titres[_index],
                  versParametres: () => _aller(_pageParametres),
                ),
                const Divider(height: 1),
                Expanded(child: pages[_index]),
              ],
            );

            if (etroit) {
              return Scaffold(
                body: SafeArea(child: contenu),
                bottomNavigationBar: NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: _aller,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: 'Accueil',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.people_outline),
                      selectedIcon: Icon(Icons.people),
                      label: 'Inscriptions',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: 'Paramètres',
                    ),
                  ],
                ),
              );
            }

            return Scaffold(
              body: Row(
                children: [
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _aller,
                    labelType: NavigationRailLabelType.all,
                    leading: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'GESCO',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: CouleursGesco.bleu,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.dashboard_outlined),
                        selectedIcon: Icon(Icons.dashboard),
                        label: Text('Tableau de bord'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.people_outline),
                        selectedIcon: Icon(Icons.people),
                        label: Text('Inscriptions'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: Text('Paramètres'),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: contenu),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _BarreSuperieure extends StatelessWidget {
  const _BarreSuperieure({
    required this.etat,
    required this.titre,
    required this.versParametres,
  });

  final EtatApp etat;
  final String titre;
  final VoidCallback versParametres;

  @override
  Widget build(BuildContext context) {
    final annee = etat.anneeCourante;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(titre, style: Theme.of(context).textTheme.titleLarge),
          ),
          if (etat.annees.isEmpty)
            TextButton.icon(
              onPressed: versParametres,
              icon: const Icon(Icons.add),
              label: const Text('Créer l\'année scolaire'),
            )
          else ...[
            if (annee != null && !annee.active)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Etiquette(
                  'Année non active',
                  couleur: CouleursGesco.orange,
                  fond: CouleursGesco.orangeClair,
                ),
              ),
            const Text('Année scolaire : '),
            DropdownButton<int>(
              value: etat.anneeId,
              items: [
                for (final a in etat.annees)
                  DropdownMenuItem<int>(
                    value: a.id,
                    child: Text(
                      a.active ? '${a.libelle} (active)' : a.libelle,
                    ),
                  ),
              ],
              onChanged: (id) {
                if (id != null) etat.choisirAnnee(id);
              },
            ),
          ],
        ],
      ),
    );
  }
}
