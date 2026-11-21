import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/etat_app.dart';
import '../domain/permissions.dart';
import 'acces/ecran_mot_de_passe.dart';
import 'commun/composants.dart';
import 'inscriptions/page_inscriptions.dart';
import 'notes/page_notes.dart';
import 'parametres/page_parametres.dart';
import 'resultats/avis_bulletins_auto.dart';
import 'resultats/page_resultats.dart';
import 'securite/page_securite.dart';
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
    this.permission,
    this.avecConnexion = false,
  });

  final String cle;

  /// Permission nécessaire pour voir cette page (null : toujours visible).
  final Permission? permission;

  /// Page affichée seulement quand une connexion est exigée.
  final bool avecConnexion;

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
    permission: Permission.tableauDeBord,
  ),
  _Destination(
    cle: 'inscriptions',
    titre: 'Inscriptions',
    libelleCourt: 'Inscriptions',
    icone: Icons.people_outline,
    iconeActive: Icons.people,
    permission: Permission.elevesVoir,
  ),
  _Destination(
    cle: 'notes',
    titre: 'Notes',
    libelleCourt: 'Notes',
    icone: Icons.grading_outlined,
    iconeActive: Icons.grading,
    permission: Permission.notesVoir,
  ),
  _Destination(
    cle: 'resultats',
    titre: 'Résultats',
    libelleCourt: 'Résultats',
    icone: Icons.emoji_events_outlined,
    iconeActive: Icons.emoji_events,
    permission: Permission.resultatsVoir,
  ),
  _Destination(
    cle: 'parametres',
    titre: 'Paramètres',
    libelleCourt: 'Paramètres',
    icone: Icons.settings_outlined,
    iconeActive: Icons.settings,
    permission: Permission.etablissementVoir,
  ),
  _Destination(
    cle: 'securite',
    titre: 'Sécurité',
    libelleCourt: 'Sécurité',
    icone: Icons.shield_outlined,
    iconeActive: Icons.shield,
    avecConnexion: true,
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
  String _cle = 'tableau_de_bord';

  void _aller(String cle) => setState(() => _cle = cle);

  bool _visible(_Destination d) {
    final session = widget.etat.services.session;
    if (d.avecConnexion && !session.controle) return false;
    final p = d.permission;
    return p == null || session.peut(p);
  }

  Widget _page(String cle) {
    final etat = widget.etat;
    return switch (cle) {
      'inscriptions' => PageInscriptions(
          etat: etat,
          allerAuxParametres: () => _aller('parametres'),
        ),
      'notes' => PageNotes(
          etat: etat,
          allerAuxParametres: () => _aller('parametres'),
          allerAuxInscriptions: () => _aller('inscriptions'),
        ),
      'resultats' => PageResultats(
          etat: etat,
          allerAuxParametres: () => _aller('parametres'),
        ),
      'parametres' => PageParametres(etat: etat),
      'securite' => PageSecurite(etat: etat),
      _ => PageTableauDeBord(
          etat: etat,
          allerAuxParametres: () => _aller('parametres'),
          allerAuxInscriptions: () => _aller('inscriptions'),
          allerAuxNotes: () => _aller('notes'),
          allerAuxResultats: widget.etat.peut(Permission.resultatsVoir)
              ? () => _aller('resultats')
              : null,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return AvisBulletinsAuto(
      auto: widget.etat.bulletinsAuto,
      child: _construire(context),
    );
  }

  Widget _construire(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.etat, widget.etat.services.session]),
      builder: (context, _) {
        final visibles = [for (final d in _destinations) if (_visible(d)) d];
        if (visibles.isEmpty) {
          return const Scaffold(
            body: MessageVide(
              'Votre compte n\'a accès à aucune page. Demandez à un '
              'administrateur de modifier vos permissions.',
              icone: Icons.lock_outline,
            ),
          );
        }
        if (!visibles.any((d) => d.cle == _cle)) _cle = visibles.first.cle;
        final index = visibles.indexWhere((d) => d.cle == _cle);
        void allerIndex(int i) => _aller(visibles[i].cle);

        return LayoutBuilder(
          builder: (context, contraintes) {
            final etroit = contraintes.maxWidth < 760;
            final contenu = Column(
              children: [
                _BarreSuperieure(
                  etat: widget.etat,
                  titre: visibles[index].titre,
                  etroit: etroit,
                  versParametres: () => _aller('parametres'),
                  versSecurite: () => _aller('securite'),
                ),
                Expanded(child: _page(_cle)),
              ],
            );

            if (etroit) {
              return Scaffold(
                body: SafeArea(child: contenu),
                bottomNavigationBar: NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: allerIndex,
                  destinations: [
                    for (final d in visibles)
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
                    destinations: visibles,
                    index: index,
                    onSelection: allerIndex,
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
    required this.destinations,
    required this.index,
    required this.onSelection,
  });

  final EtatApp etat;
  final List<_Destination> destinations;
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
            for (var i = 0; i < destinations.length; i++)
              _ElementMenu(
                destination: destinations[i],
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
    required this.versSecurite,
  });

  final EtatApp etat;
  final String titre;
  final bool etroit;
  final VoidCallback versParametres;
  final VoidCallback versSecurite;

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
          if (etat.services.session.controle &&
              etat.services.session.utilisateur != null)
            _MenuUtilisateur(etat: etat, etroit: etroit, versSecurite: versSecurite),
        ],
      ),
    );
  }
}

/// Pastille de la personne connectée : mot de passe, verrouillage,
/// déconnexion.
class _MenuUtilisateur extends StatelessWidget {
  const _MenuUtilisateur({
    required this.etat,
    required this.etroit,
    required this.versSecurite,
  });

  final EtatApp etat;
  final bool etroit;
  final VoidCallback versSecurite;

  @override
  Widget build(BuildContext context) {
    final u = etat.services.session.utilisateur!;
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: PopupMenuButton<String>(
        key: const Key('menu_utilisateur'),
        tooltip: 'Mon compte',
        offset: const Offset(0, 44),
        onSelected: (action) {
          switch (action) {
            case 'mdp':
              demanderChangementMotDePasse(context, etat.acces);
            case 'compte':
              versSecurite();
            case 'verrouiller':
              etat.acces.verrouiller();
            case 'deconnexion':
              etat.acces.seDeconnecter();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            enabled: false,
            child: Text('${u.nomAffiche} · ${u.role.libelle}'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'compte', child: Text('Mon compte et sécurité')),
          const PopupMenuItem(value: 'mdp', child: Text('Changer mon mot de passe')),
          const PopupMenuItem(value: 'verrouiller', child: Text('Verrouiller')),
          const PopupMenuItem(value: 'deconnexion', child: Text('Se déconnecter')),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: CouleursGesco.fond,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: CouleursGesco.bordure),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_circle_outlined, size: 20, color: CouleursGesco.bleu),
              if (!etroit) ...[
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    u.nomAffiche,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
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
