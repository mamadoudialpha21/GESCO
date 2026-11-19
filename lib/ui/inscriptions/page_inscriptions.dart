import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/erreurs.dart';
import '../../data/modeles_donnees.dart';
import '../../domain/permissions.dart';
import '../../domain/dates.dart';
import '../../domain/recherche.dart';
import '../commun/chargeur.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../theme.dart';
import 'dialogue_eleve.dart';
import 'dialogue_reinscription.dart';
import 'dialogues_mouvements.dart';
import 'fiche_eleve.dart';

class _Donnees {
  const _Donnees({required this.classes, required this.eleves});

  final List<ClasseResume> classes;
  final List<EleveInscrit> eleves;
}

enum _Action { fiche, modifier, sortie, reprendre, transferer, archiver, supprimer }

/// Inscriptions : liste des élèves de l'année scolaire sélectionnée, avec
/// filtre par classe, recherche par nom ou matricule, et ajout, modification,
/// consultation et suppression.
class PageInscriptions extends StatefulWidget {
  const PageInscriptions({
    super.key,
    required this.etat,
    required this.allerAuxParametres,
  });

  final EtatApp etat;
  final VoidCallback allerAuxParametres;

  @override
  State<PageInscriptions> createState() => _PageInscriptionsState();
}

class _PageInscriptionsState extends State<PageInscriptions> {
  /// Valeur du filtre « toutes les classes » (les identifiants commencent à 1).
  static const int _toutes = 0;

  final TextEditingController _recherche = TextEditingController();
  int _classeFiltre = _toutes;
  bool _archives = false;

  EtatApp get _etat => widget.etat;

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<_Donnees> _charger() async {
    final anneeId = _etat.anneeId;
    if (anneeId == null) return const _Donnees(classes: [], eleves: []);
    final classes = await _etat.services.classes.lister(anneeId);
    final eleves = await _etat.services.eleves.lister(
      anneeId,
      inclureArchives: _archives,
    );
    return _Donnees(classes: classes, eleves: eleves);
  }

  /// Exécute [action] ; si la classe d'arrivée est pleine, demande
  /// confirmation puis recommence en autorisant le dépassement.
  Future<T> _avecCapacite<T>(Future<T> Function(bool depasser) action) async {
    try {
      return await action(false);
    } on ErreurAConfirmer catch (e) {
      if (e.sujet != 'capacite' || !mounted) rethrow;
      final oui = await confirmer(
        context,
        titre: 'Classe pleine',
        message: '${e.message}\n\nContinuer quand même ?',
        libelleConfirmer: 'Continuer',
      );
      if (!oui) {
        throw const ErreurGesco('Opération annulée : la classe est pleine.');
      }
      return action(true);
    }
  }

  /// Début des matricules proposés : l'année de début, ex. « 2026 ».
  String _prefixeMatricule() {
    final libelle = _etat.anneeCourante?.libelle ?? '';
    final trouve = RegExp(r'\d{4}').firstMatch(libelle);
    return trouve?.group(0) ?? '';
  }

  // ------------------------------------------------------------- Actions

  Future<void> _inscrire(_Donnees donnees, int filtre) async {
    final anneeId = _etat.anneeId;
    if (anneeId == null) return;
    List<String>? matricules;
    final ok = await executer(context, () async {
      matricules = await _etat.services.eleves.matricules();
    });
    final connus = matricules;
    if (!ok || connus == null || !mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DialogueEleve(
        classes: [for (final c in donnees.classes) c.classe],
        matricules: connus,
        prefixeMatricule: _prefixeMatricule(),
        classeInitiale: filtre == _toutes ? null : filtre,
        enregistrer: (eleve, classeId) async {
          await _avecCapacite(
            (depasser) => _etat.services.eleves.inscrire(
              eleve,
              anneeId: anneeId,
              classeId: classeId,
              depasserCapacite: depasser,
            ),
          );
          _etat.donneesModifiees();
          if (mounted) {
            afficherMessage(context, '${eleve.nomComplet} est inscrit(e).');
          }
        },
      ),
    );
  }

  Future<void> _modifier(EleveInscrit inscrit, _Donnees donnees) async {
    Eleve? fiche;
    var nbNotes = 0;
    List<String>? matricules;
    final ok = await executer(context, () async {
      fiche = await _etat.services.eleves.obtenir(inscrit.eleveId);
      nbNotes = await _etat.services.eleves.compterNotes(inscrit.inscriptionId);
      matricules = await _etat.services.eleves.matricules();
    });
    final eleve = fiche;
    final connus = matricules;
    if (!ok || !mounted) return;
    if (eleve == null || connus == null) {
      afficherMessage(context, 'Fiche élève introuvable.', erreur: true);
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DialogueEleve(
        classes: [for (final c in donnees.classes) c.classe],
        matricules: connus,
        prefixeMatricule: _prefixeMatricule(),
        classeInitiale: inscrit.classeId,
        eleve: eleve,
        nbNotes: nbNotes,
        enregistrer: (modifie, classeId) async {
          await _avecCapacite(
            (depasser) => _etat.services.eleves.modifier(
              modifie,
              inscriptionId: inscrit.inscriptionId,
              nouvelleClasseId: classeId == inscrit.classeId ? null : classeId,
              depasserCapacite: depasser,
            ),
          );
          _etat.donneesModifiees();
          if (mounted) {
            afficherMessage(context, 'La fiche de ${modifie.nomComplet} est modifiée.');
          }
        },
      ),
    );
  }

  Future<void> _voirFiche(EleveInscrit inscrit, _Donnees donnees) async {
    final action = await showDialog<ActionFiche>(
      context: context,
      builder: (ctx) => DialogueFiche(
        etat: _etat,
        inscrit: inscrit,
        anneeLibelle: _etat.anneeCourante?.libelle ?? '',
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case ActionFiche.modifier:
        await _modifier(inscrit, donnees);
      case ActionFiche.supprimer:
        await _supprimer(inscrit);
      case ActionFiche.sortie:
        await _sortie(inscrit);
      case ActionFiche.reprendre:
        await _reprendre(inscrit);
      case ActionFiche.transferer:
        await _transferer(inscrit, donnees);
      case ActionFiche.archiver:
        await _archiver(inscrit);
    }
  }

  Future<void> _sortie(EleveInscrit inscrit) async {
    final choix = await showDialog<ChoixSortie>(
      context: context,
      builder: (ctx) => DialogueSortie(nomEleve: inscrit.nomComplet),
    );
    if (choix == null || !mounted) return;
    final ok = await executer(
      context,
      () => _etat.services.eleves.enregistrerSortie(
        inscrit.inscriptionId,
        choix.statut,
        motif: choix.motif,
        date: choix.date,
      ),
      succes: choix.statut == StatutInscription.depart
          ? 'Le départ de ${inscrit.nomComplet} est enregistré.'
          : 'L\'abandon de ${inscrit.nomComplet} est enregistré.',
    );
    if (ok) _etat.donneesModifiees();
  }

  Future<void> _reprendre(EleveInscrit inscrit) async {
    final oui = await confirmer(
      context,
      titre: 'Reprendre l\'élève',
      message:
          'Remettre ${inscrit.nomComplet} dans la classe ${inscrit.classeNom} ? '
          'Il sera de nouveau compté dans les effectifs et les classements.',
      libelleConfirmer: 'Reprendre',
    );
    if (!oui || !mounted) return;
    final ok = await executer(
      context,
      () => _avecCapacite(
        (depasser) => _etat.services.eleves.reprendre(
          inscrit.inscriptionId,
          depasserCapacite: depasser,
        ),
      ),
      succes: '${inscrit.nomComplet} suit de nouveau la classe ${inscrit.classeNom}.',
    );
    if (ok) _etat.donneesModifiees();
  }

  Future<void> _transferer(EleveInscrit inscrit, _Donnees donnees) async {
    var nbNotes = 0;
    final lu = await executer(context, () async {
      nbNotes = await _etat.services.eleves.compterNotes(inscrit.inscriptionId);
    });
    if (!lu || !mounted) return;
    final choix = await showDialog<ChoixTransfert>(
      context: context,
      builder: (ctx) => DialogueTransfert(
        nomEleve: inscrit.nomComplet,
        classeActuelleId: inscrit.classeId,
        classes: donnees.classes,
        nbNotes: nbNotes,
      ),
    );
    if (choix == null || !mounted) return;

    var annule = false;
    ApercuTransfert? resultat;
    final ok = await executer(context, () async {
      var pertes = false;
      var depasser = false;
      while (true) {
        try {
          resultat = await _etat.services.eleves.transferer(
            inscrit.inscriptionId,
            choix.classeId,
            motif: choix.motif,
            confirmerPertes: pertes,
            depasserCapacite: depasser,
          );
          return;
        } on ErreurAConfirmer catch (e) {
          if (!mounted) rethrow;
          final oui = await confirmer(
            context,
            titre: e.sujet == 'pertes' ? 'Des notes seront supprimées' : 'Classe pleine',
            message: '${e.message}\n\nContinuer quand même ?',
            libelleConfirmer: e.sujet == 'pertes' ? 'Supprimer ces notes' : 'Continuer',
            danger: e.sujet == 'pertes',
          );
          if (!oui) {
            annule = true;
            return;
          }
          if (e.sujet == 'pertes') {
            pertes = true;
          } else {
            depasser = true;
          }
        }
      }
    });
    if (!ok || annule || !mounted) return;
    final r = resultat;
    _etat.donneesModifiees();
    afficherMessage(
      context,
      r == null || r.notesReprises == 0
          ? '${inscrit.nomComplet} a changé de classe.'
          : '${inscrit.nomComplet} a changé de classe : '
              '${r.notesReprises} note${r.notesReprises > 1 ? 's' : ''} '
              'reportée${r.notesReprises > 1 ? 's' : ''}.',
    );
  }

  Future<void> _archiver(EleveInscrit inscrit) async {
    final archive = !inscrit.archive;
    if (archive) {
      final oui = await confirmer(
        context,
        titre: 'Archiver le dossier',
        message:
            'Archiver le dossier de ${inscrit.nomComplet} ? Il disparaîtra des listes '
            'courantes, des classements et des statistiques, mais toutes ses '
            'données sont conservées. Vous pourrez le désarchiver.',
        libelleConfirmer: 'Archiver',
      );
      if (!oui || !mounted) return;
    }
    final ok = await executer(
      context,
      () => _etat.services.eleves.archiver(inscrit.eleveId, archive: archive),
      succes: archive
          ? 'Le dossier de ${inscrit.nomComplet} est archivé.'
          : 'Le dossier de ${inscrit.nomComplet} est de nouveau actif.',
    );
    if (ok) _etat.donneesModifiees();
  }

  Future<void> _voirMouvements() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => DialogueMouvements(
        etat: _etat,
        titre: 'Mouvements d\'inscription — ${_etat.anneeCourante?.libelle ?? ''}',
      ),
    );
  }

  Future<void> _supprimer(EleveInscrit inscrit) async {
    var nbNotes = 0;
    final lu = await executer(context, () async {
      nbNotes = await _etat.services.eleves.compterNotes(inscrit.inscriptionId);
    });
    if (!lu || !mounted) return;

    final annee = _etat.anneeCourante?.libelle ?? '';
    if (nbNotes == 0) {
      final oui = await confirmer(
        context,
        titre: 'Supprimer l\'élève',
        message:
            'Supprimer ${inscrit.nomComplet} (matricule ${inscrit.matricule}) '
            'de l\'année scolaire $annee ?\n\n'
            'S\'il n\'est inscrit dans aucune autre année, sa fiche sera aussi '
            'supprimée. Cette action est irréversible.',
        libelleConfirmer: 'Supprimer',
        danger: true,
      );
      if (!oui || !mounted) return;
    } else {
      final premiere = await confirmer(
        context,
        titre: 'Cet élève a des notes',
        message:
            '${inscrit.nomComplet} a $nbNotes '
            '${nbNotes > 1 ? 'notes enregistrées' : 'note enregistrée'} '
            'pour l\'année $annee.\n\n'
            'Supprimer l\'élève supprimera aussi définitivement '
            '${nbNotes > 1 ? 'ces notes' : 'cette note'}.',
        libelleConfirmer: 'Continuer',
        danger: true,
      );
      if (!premiere || !mounted) return;
      final derniere = await confirmer(
        context,
        titre: 'Dernière confirmation',
        message:
            'Supprimer définitivement ${inscrit.nomComplet} et '
            '${nbNotes > 1 ? 'ses $nbNotes notes' : 'sa note'} ? '
            'Il ne sera pas possible de les récupérer, sauf en restaurant '
            'une sauvegarde.',
        libelleConfirmer: 'Supprimer définitivement',
        danger: true,
      );
      if (!derniere || !mounted) return;
    }

    final ok = await executer(
      context,
      () async {
        await _etat.services.eleves.supprimerInscription(
          inscrit.inscriptionId,
          avecNotes: nbNotes > 0,
        );
      },
      succes: '${inscrit.nomComplet} a été supprimé.',
    );
    if (ok) _etat.donneesModifiees();
  }

  Future<void> _reinscrire(_Donnees donnees, int filtre) async {
    final anneeId = _etat.anneeId;
    if (anneeId == null) return;
    List<Eleve>? candidats;
    final ok = await executer(context, () async {
      candidats = await _etat.services.eleves.nonInscrits(anneeId);
    });
    final liste = candidats;
    if (!ok || liste == null || !mounted) return;
    if (liste.isEmpty) {
      afficherMessage(
        context,
        'Aucun élève à réinscrire : tous les élèves enregistrés sont déjà '
        'inscrits pour cette année scolaire.',
      );
      return;
    }

    final choix = await showDialog<ChoixReinscription>(
      context: context,
      builder: (ctx) => DialogueReinscription(
        candidats: liste,
        classes: [for (final c in donnees.classes) c.classe],
        classeInitiale: filtre == _toutes ? null : filtre,
      ),
    );
    if (choix == null || !mounted) return;

    var faits = 0;
    final termine = await executer(context, () async {
      try {
        for (final id in choix.eleveIds) {
          await _avecCapacite(
            (depasser) => _etat.services.eleves.inscrireExistant(
              eleveId: id,
              anneeId: anneeId,
              classeId: choix.classeId,
              depasserCapacite: depasser,
            ),
          );
          faits++;
        }
      } on ErreurGesco catch (e) {
        throw ErreurGesco(
          '$faits sur ${choix.eleveIds.length} élève(s) réinscrit(s) avant '
          'l\'arrêt. ${e.message}',
        );
      }
    });
    if (faits > 0) _etat.donneesModifiees();
    if (termine && mounted) {
      afficherMessage(
        context,
        faits > 1 ? '$faits élèves réinscrits.' : '$faits élève réinscrit.',
      );
    }
  }

  // ------------------------------------------------------------ Affichage

  @override
  Widget build(BuildContext context) {
    return Chargeur<_Donnees>(
      cle: (_etat.anneeId, _etat.version, _archives),
      charger: _charger,
      builder: _contenu,
    );
  }

  Widget _contenu(BuildContext context, _Donnees donnees) {
    if (_etat.anneeCourante == null) {
      return _Vide(
        message: 'Aucune année scolaire. Créez-en une dans les paramètres '
            'avant d\'inscrire des élèves.',
        libelleBouton: 'Ouvrir les paramètres',
        onPressed: widget.allerAuxParametres,
      );
    }
    if (donnees.classes.isEmpty) {
      return _Vide(
        message: 'Aucune classe pour cette année scolaire. Créez au moins une '
            'classe dans les paramètres pour pouvoir inscrire des élèves.',
        libelleBouton: 'Ouvrir les paramètres',
        onPressed: widget.allerAuxParametres,
      );
    }

    final filtre = donnees.classes.any((c) => c.classe.id == _classeFiltre)
        ? _classeFiltre
        : _toutes;
    final total = filtre == _toutes
        ? donnees.eleves.length
        : donnees.eleves.where((e) => e.classeId == filtre).length;
    final affiches = [
      for (final e in donnees.eleves)
        if ((filtre == _toutes || e.classeId == filtre) &&
            correspondRecherche(_recherche.text, [e.nom, e.prenom, e.matricule]))
          e,
    ];
    final recherche = _recherche.text.trim().isNotEmpty;
    final gerer = _etat.peut(Permission.elevesGerer);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  key: const Key('recherche_eleves'),
                  controller: _recherche,
                  decoration: champ('Nom, prénom ou matricule')
                      .copyWith(
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: recherche
                        ? IconButton(
                            tooltip: 'Effacer la recherche',
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(_recherche.clear),
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(
                width: 240,
                child: InputDecorator(
                  decoration: champ('Classe'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      key: const Key('filtre_classe'),
                      isExpanded: true,
                      isDense: true,
                      value: filtre,
                      items: [
                        DropdownMenuItem<int>(
                          value: _toutes,
                          child: Text('Toutes les classes (${donnees.eleves.length})'),
                        ),
                        for (final c in donnees.classes)
                          DropdownMenuItem<int>(
                            value: c.classe.id,
                            child: Text('${c.classe.nom} (${c.nbEleves})'),
                          ),
                      ],
                      onChanged: (id) {
                        if (id != null) setState(() => _classeFiltre = id);
                      },
                    ),
                  ),
                ),
              ),
              FilledButton.icon(
                key: const Key('bouton_inscrire'),
                onPressed: gerer ? () => _inscrire(donnees, filtre) : null,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Inscrire un élève'),
              ),
              OutlinedButton.icon(
                key: const Key('bouton_reinscrire'),
                onPressed: gerer ? () => _reinscrire(donnees, filtre) : null,
                icon: const Icon(Icons.history_edu_outlined),
                label: const Text('Réinscrire…'),
              ),
              OutlinedButton.icon(
                key: const Key('bouton_mouvements'),
                onPressed: _voirMouvements,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Mouvements'),
              ),
              FilterChip(
                key: const Key('filtre_archives'),
                label: const Text('Dossiers archivés'),
                selected: _archives,
                onSelected: (v) => setState(() => _archives = v),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: Text(
            _decompte(affiches.length, total, recherche) +
                _resumeSorties(donnees.eleves, filtre),
            key: const Key('decompte_eleves'),
            style: const TextStyle(
              color: CouleursGesco.gris,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: affiches.isEmpty
              ? MessageVide(
                  donnees.eleves.isEmpty
                      ? 'Aucun élève inscrit pour cette année scolaire.\n'
                          'Utilisez « Inscrire un élève » pour commencer.'
                      : 'Aucun élève ne correspond à la recherche ou à la classe choisie.',
                  icone: Icons.people_outline,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: affiches.length,
                  itemBuilder: (context, index) =>
                      _ligne(context, affiches[index], donnees),
                ),
        ),
      ],
    );
  }

  String _resumeSorties(List<EleveInscrit> eleves, int filtre) {
    var departs = 0;
    var abandons = 0;
    for (final e in eleves) {
      if (filtre != _toutes && e.classeId != filtre) continue;
      if (e.statut == StatutInscription.depart) departs++;
      if (e.statut == StatutInscription.abandon) abandons++;
    }
    final morceaux = <String>[
      if (departs > 0) '$departs parti${departs > 1 ? 's' : ''}',
      if (abandons > 0) '$abandons abandon${abandons > 1 ? 's' : ''}',
    ];
    return morceaux.isEmpty ? '' : ' (dont ${morceaux.join(', ')})';
  }

  String _decompte(int affiches, int total, bool recherche) {
    final mot = affiches > 1 ? 'élèves' : 'élève';
    if (!recherche) return '$affiches $mot';
    return '$affiches $mot sur $total';
  }

  Widget _ligne(BuildContext context, EleveInscrit e, _Donnees donnees) {
    final naissance = analyserDateIso(e.dateNaissance) != null
        ? 'né(e) le ${formaterDateFr(e.dateNaissance)}'
        : null;
    final initiales = _initiales(e);

    return Carte(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _voirFiche(e, donnees),
        leading: CircleAvatar(
          backgroundColor: CouleursGesco.bleuClair,
          foregroundColor: CouleursGesco.bleu,
          child: Text(initiales),
        ),
        title: Text(
          e.nomComplet,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(e.matricule),
              Etiquette(
                e.classeNom,
                couleur: CouleursGesco.bleu,
                fond: CouleursGesco.bleuClair,
              ),
              if (naissance != null) Text(naissance),
              if (e.statut != StatutInscription.inscrit)
                Etiquette(
                  e.statut.libelle,
                  couleur: CouleursGesco.orange,
                  fond: CouleursGesco.orangeClair,
                ),
              if (e.archive)
                const Etiquette(
                  'Archivé',
                  couleur: CouleursGesco.gris,
                  fond: CouleursGesco.grisClair,
                ),
            ],
          ),
        ),
        trailing: PopupMenuButton<_Action>(
          tooltip: 'Actions',
          onSelected: (action) {
            switch (action) {
              case _Action.fiche:
                _voirFiche(e, donnees);
              case _Action.modifier:
                _modifier(e, donnees);
              case _Action.sortie:
                _sortie(e);
              case _Action.reprendre:
                _reprendre(e);
              case _Action.transferer:
                _transferer(e, donnees);
              case _Action.archiver:
                _archiver(e);
              case _Action.supprimer:
                _supprimer(e);
            }
          },
          itemBuilder: (context) {
            final gerer = _etat.peut(Permission.elevesGerer);
            final supprimer = _etat.peut(Permission.elevesSupprimer);
            return [
              const PopupMenuItem<_Action>(
                value: _Action.fiche,
                child: ListTile(
                  leading: Icon(Icons.badge_outlined),
                  title: Text('Voir la fiche'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem<_Action>(
                value: _Action.modifier,
                enabled: gerer,
                child: const ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Modifier'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (e.actif) ...[
                PopupMenuItem<_Action>(
                  value: _Action.transferer,
                  enabled: gerer,
                  child: const ListTile(
                    leading: Icon(Icons.compare_arrows),
                    title: Text('Transférer dans une autre classe'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem<_Action>(
                  value: _Action.sortie,
                  enabled: gerer,
                  child: const ListTile(
                    leading: Icon(Icons.exit_to_app),
                    title: Text('Départ ou abandon'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ] else
                PopupMenuItem<_Action>(
                  value: _Action.reprendre,
                  enabled: gerer,
                  child: const ListTile(
                    leading: Icon(Icons.keyboard_return),
                    title: Text('Reprendre dans la classe'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              PopupMenuItem<_Action>(
                value: _Action.archiver,
                enabled: supprimer,
                child: ListTile(
                  leading: Icon(e.archive ? Icons.unarchive_outlined : Icons.archive_outlined),
                  title: Text(e.archive ? 'Désarchiver le dossier' : 'Archiver le dossier'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem<_Action>(
                value: _Action.supprimer,
                enabled: supprimer,
                child: const ListTile(
                  leading: Icon(Icons.delete_outline, color: CouleursGesco.rouge),
                  title: Text('Supprimer', style: TextStyle(color: CouleursGesco.rouge)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ];
          },
        ),
      ),
    );
  }

  /// Initiales (nom + prénom) pour l'avatar de la liste.
  static String _initiales(EleveInscrit e) {
    String premiere(String texte) {
      final t = texte.trim();
      return t.isEmpty ? '' : t.substring(0, 1).toUpperCase();
    }

    final initiales = '${premiere(e.nom)}${premiere(e.prenom)}';
    return initiales.isEmpty ? '?' : initiales;
  }
}

class _Vide extends StatelessWidget {
  const _Vide({
    required this.message,
    required this.libelleBouton,
    required this.onPressed,
  });

  final String message;
  final String libelleBouton;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MessageVide(message, icone: Icons.people_outline),
          FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.settings),
            label: Text(libelleBouton),
          ),
        ],
      ),
    );
  }
}
