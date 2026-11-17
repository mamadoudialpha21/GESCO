import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/etat_app.dart';
import 'commun/composants.dart';
import 'inscriptions/page_inscriptions.dart';
import 'notes/page_notes.dart';
import 'parametres/page_parametres.dart';
import 'tableau_de_bord.dart';
import 'theme.dart';

/// Une entrée du menu de navigation.
class _Destination {
  const _Destination({
    required this.cle,
    required this.titre,
    required this.libelleCourt,
    required this.icone,
    required this.iconeActive,
  });

  final String cle;

  /// Titre de la page (barre du haut et menu latéral).
  final String titre;

  /// Libellé de la barre du bas sur petit écran.
  final String libelleCourt;
  final IconData icone;
  final IconData iconeActive;
}

const List<_Destination> _destinations = [
  _Destination(
    cle: 'tableau_de_bord',
    titre: 'Tableau de bord',
    libelleCourt: 'Accueil',
    icone: Icons.dashboard_outlined,
    iconeActive: Icons.dashboard,
  ),
  _Destination(
    cle: 'inscriptions',
    titre: 'Inscriptions',
    libelleCourt: 'Inscriptions',
    icone: Icons.people_outline,
    iconeActive: Icons.people,
  ),
  _Destination(
    cle: 'notes',
    titre: 'Notes',
    libelleCourt: 'Notes',
    icone: Icons.grading_outlined,
    iconeActive: Icons.grading,
  ),
  _Destination(
    cle: 'parametres',
    titre: 'Paramètres',
    libelleCourt: 'Paramètres',
    icone: Icons.settings_outlined,
    iconeActive: Icons.settings,
  ),
];

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
  static const int _pageNotes = 2;
  static const int _pageParametres = 3;

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
            allerAuxNotes: () => _aller(_pageNotes),
          ),
          PageInscriptions(
            etat: widget.etat,
            allerAuxParametres: () => _aller(_pageParametres),
          ),
          PageNotes(
            etat: widget.etat,
            allerAuxParametres: () => _aller(_pageParametres),
            allerAuxInscriptions: () => _aller(_pageInscriptions),
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
                  titre: _destinations[_index].titre,
                  etroit: etroit,
                  versParametres: () => _aller(_pageParametres),
                ),
                Expanded(child: pages[_index]),
              ],
            );

            if (etroit) {
              return Scaffold(
                body: SafeArea(child: contenu),
                bottomNavigationBar: NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: _aller,
                  destinations: [
                    for (final d in _destinations)
                      NavigationDestination(
                        icon: Icon(d.icone),
                        selectedIcon: Icon(d.iconeActive),
                        label: d.libelleCourt,
                      ),
                  ],
                ),
              );
            }

            return Scaffold(
              body: Row(
                children: [
                  _MenuLateral(
                    etat: widget.etat,
                    index: _index,
                    onSelection: _aller,
                  ),
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

/// Menu latéral bleu : logo de l'établissement, navigation, mention hors ligne.
class _MenuLateral extends StatelessWidget {
  const _MenuLateral({
    required this.etat,
    required this.index,
    required this.onSelection,
  });

  final EtatApp etat;
  final int index;
  final ValueChanged<int> onSelection;

  @override
  Widget build(BuildContext context) {
    final nom = etat.etablissement.nom;
    return Container(
      width: 244,
      color: CouleursGesco.bleuFonce,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
              child: Row(
                children: [
                  _LogoMenu(logo: etat.etablissement.logo),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GESCO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Text(
                          'Gestion des notes',
                          style: TextStyle(
                            color: Color(0xFFB7C9E4),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (nom.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Text(
                  nom,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            for (var i = 0; i < _destinations.length; i++)
              _ElementMenu(
                destination: _destinations[i],
                selectionne: i == index,
                onTap: () => onSelection(i),
              ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 16, color: Color(0xFFB7C9E4)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hors ligne : vos données restent sur cet ordinateur',
                      style: TextStyle(color: Color(0xFFB7C9E4), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo de l'établissement (ou icône d'école s'il n'y en a pas).
class _LogoMenu extends StatelessWidget {
  const _LogoMenu({required this.logo});

  final Uint8List? logo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      padding: logo == null ? EdgeInsets.zero : const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: logo == null ? CouleursGesco.bleu : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: logo == null
          ? const Icon(Icons.school, color: Colors.white, size: 26)
          : Image.memory(
              logo!,
              fit: BoxFit.contain,
              errorBuilder: (context, erreur, trace) =>
                  const Icon(Icons.school, color: CouleursGesco.bleu),
            ),
    );
  }
}

class _ElementMenu extends StatelessWidget {
  const _ElementMenu({
    required this.destination,
    required this.selectionne,
    required this.onTap,
  });

  final _Destination destination;
  final bool selectionne;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selectionne ? const Color(0x2EFFFFFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: Key('menu_${destination.cle}'),
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  selectionne ? destination.iconeActive : destination.icone,
                  size: 22,
                  color: selectionne ? Colors.white : const Color(0xFFC9D8EE),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    destination.titre,
                    style: TextStyle(
                      color: selectionne ? Colors.white : const Color(0xFFC9D8EE),
                      fontSize: 14.5,
                      fontWeight: selectionne ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarreSuperieure extends StatelessWidget {
  const _BarreSuperieure({
    required this.etat,
    required this.titre,
    required this.etroit,
    required this.versParametres,
  });

  final EtatApp etat;
  final String titre;
  final bool etroit;
  final VoidCallback versParametres;

  @override
  Widget build(BuildContext context) {
    final annee = etat.anneeCourante;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: CouleursGesco.bordure)),
      ),
      padding: EdgeInsets.symmetric(horizontal: etroit ? 16 : 28, vertical: 10),
      constraints: const BoxConstraints(minHeight: 64),
      child: Row(
        children: [
          Expanded(
            child: Text(
              titre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: CouleursGesco.texte,
                fontSize: etroit ? 20 : 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (etat.annees.isEmpty)
            TextButton.icon(
              onPressed: versParametres,
              icon: const Icon(Icons.add),
              label: Text(etroit ? 'Créer l\'année' : 'Créer l\'année scolaire'),
            )
          else ...[
            if (annee != null && !annee.active && !etroit)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Etiquette(
                  'Année non active',
                  couleur: CouleursGesco.orange,
                  fond: CouleursGesco.orangeClair,
                ),
              ),
            _SelecteurAnnee(etat: etat, etroit: etroit),
          ],
        ],
      ),
    );
  }
}

/// Liste déroulante de l'année scolaire, présentée comme une pastille.
class _SelecteurAnnee extends StatelessWidget {
  const _SelecteurAnnee({required this.etat, required this.etroit});

  final EtatApp etat;
  final bool etroit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: CouleursGesco.fond,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CouleursGesco.bordure),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event, size: 18, color: CouleursGesco.bleu),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              key: const Key('choix_annee'),
              value: etat.anneeId,
              isDense: true,
              borderRadius: BorderRadius.circular(12),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: CouleursGesco.texte,
                    fontWeight: FontWeight.w600,
                  ),
              selectedItemBuilder: (context) => [
                for (final a in etat.annees)
                  Center(
                    child: Text(
                      etroit || !a.active ? a.libelle : '${a.libelle}  ·  active',
                    ),
                  ),
              ],
              items: [
                for (final a in etat.annees)
                  DropdownMenuItem<int>(
                    value: a.id,
                    child: Text(a.active ? '${a.libelle} (active)' : a.libelle),
                  ),
              ],
              onChanged: (id) {
                if (id != null) etat.choisirAnnee(id);
              },
            ),
          ),
        ],
      ),
    );
  }
}
