import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../domain/calendrier.dart';
import '../../domain/periodes.dart';
import '../../domain/permissions.dart';
import '../commun/chargeur.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../theme.dart';

/// Découpage de l'année en périodes (trimestres, semestres ou personnalisé),
/// séquences facultatives et affichage des moyennes mensuelles. Propre à
/// chaque année scolaire.
class OngletPeriodes extends StatelessWidget {
  const OngletPeriodes({super.key, required this.etat});

  final EtatApp etat;

  @override
  Widget build(BuildContext context) {
    final anneeId = etat.anneeId;
    if (anneeId == null) {
      return const MessageVide(
        'Créez d\'abord une année scolaire (onglet « Années scolaires »).',
        icone: Icons.event_outlined,
      );
    }
    return Chargeur<Calendrier>(
      cle: (anneeId, etat.version),
      charger: () => etat.services.calendriers.lire(anneeId),
      builder: (context, calendrier) => _EditeurPeriodes(
        // La clé suit les données réellement chargées (et non le compteur de
        // version) : après un enregistrement, l'éditeur repart de la base dès
        // que la relecture est terminée, jamais des anciennes valeurs.
        key: ValueKey('periodes-$anneeId-${identityHashCode(calendrier)}'),
        etat: etat,
        anneeId: anneeId,
        calendrier: calendrier,
      ),
    );
  }
}

/// Un groupe de mois en cours de modification (période ou séquence).
class _Groupe {
  _Groupe(this.cle, String nom, Iterable<int> mois)
      : nom = TextEditingController(text: nom),
        mois = {...mois};

  final String cle;
  final TextEditingController nom;
  final Set<int> mois;

  void dispose() => nom.dispose();
}

class _EditeurPeriodes extends StatefulWidget {
  const _EditeurPeriodes({
    super.key,
    required this.etat,
    required this.anneeId,
    required this.calendrier,
  });

  final EtatApp etat;
  final int anneeId;
  final Calendrier calendrier;

  @override
  State<_EditeurPeriodes> createState() => _EditeurPeriodesState();
}

class _EditeurPeriodesState extends State<_EditeurPeriodes> {
  late TypePeriodes _type;
  late List<_Groupe> _periodes;
  late List<_Groupe> _sequences;
  late bool _moyenneMensuelle;

  /// Groupes retirés : libérés à la fermeture de l'écran seulement, pour ne pas
  /// toucher à un champ encore affiché.
  final List<_Groupe> _retires = [];

  @override
  void initState() {
    super.initState();
    _remplir(widget.calendrier);
  }

  @override
  void dispose() {
    for (final g in [..._periodes, ..._sequences, ..._retires]) {
      g.dispose();
    }
    super.dispose();
  }

  static List<_Groupe> _groupes(List<PeriodeScolaire> liste) =>
      [for (final p in liste) _Groupe(p.cle, p.libelle, p.mois)];

  void _remplir(Calendrier c) {
    _type = c.type;
    _periodes = _groupes(c.periodes);
    _sequences = _groupes(c.sequences);
    _moyenneMensuelle = c.moyenneMensuelle;
  }

  void _choisirType(TypePeriodes type) {
    setState(() {
      _type = type;
      final modele = switch (type) {
        TypePeriodes.trimestres => Calendrier.trimestres,
        TypePeriodes.semestres => Calendrier.semestres,
        TypePeriodes.personnalise => null,
      };
      if (modele != null) {
        _retires.addAll(_periodes);
        _periodes = _groupes(modele.periodes);
      }
    });
  }

  void _basculerMois(List<_Groupe> groupes, _Groupe groupe, int mois, {required bool periodes}) {
    setState(() {
      if (groupe.mois.contains(mois)) {
        groupe.mois.remove(mois);
      } else {
        // Un mois n'appartient qu'à un seul groupe.
        for (final autre in groupes) {
          autre.mois.remove(mois);
        }
        groupe.mois.add(mois);
      }
      if (periodes) _type = TypePeriodes.personnalise;
    });
  }

  String _cleLibre(List<_Groupe> groupes, String prefixe) {
    var n = groupes.length + 1;
    while (groupes.any((g) => g.cle == '$prefixe$n')) {
      n++;
    }
    return '$prefixe$n';
  }

  void _ajouter(List<_Groupe> groupes, String prefixe, String nomBase, {required bool periodes}) {
    setState(() {
      final cle = _cleLibre(groupes, prefixe);
      groupes.add(_Groupe(cle, '$nomBase ${groupes.length + 1}', const []));
      if (periodes) _type = TypePeriodes.personnalise;
    });
  }

  void _retirer(List<_Groupe> groupes, _Groupe groupe, {required bool periodes}) {
    setState(() {
      groupes.remove(groupe);
      _retires.add(groupe);
      if (periodes) _type = TypePeriodes.personnalise;
    });
  }

  /// Séquences proposées : chaque période coupée en groupes de deux mois.
  List<_Groupe> _sequencesProposees() {
    final resultat = <_Groupe>[];
    for (final p in _periodes) {
      final mois = [for (final m in moisScolaires) if (p.mois.contains(m)) m];
      for (var i = 0; i < mois.length; i += 2) {
        final n = resultat.length + 1;
        resultat.add(_Groupe('q$n', 'Séquence $n', mois.skip(i).take(2)));
      }
    }
    return resultat;
  }

  void _basculerSequences(bool actives) {
    setState(() {
      if (actives) {
        _sequences = _sequencesProposees();
      } else {
        _retires.addAll(_sequences);
        _sequences = [];
      }
    });
  }

  Calendrier _calendrier() {
    PeriodeScolaire versPeriode(_Groupe g) => PeriodeScolaire(
          cle: g.cle,
          libelle: g.nom.text.trim(),
          mois: [for (final m in moisScolaires) if (g.mois.contains(m)) m],
        );
    return Calendrier(
      type: _type,
      periodes: [for (final g in _periodes) versPeriode(g)],
      sequences: [for (final g in _sequences) versPeriode(g)],
      moyenneMensuelle: _moyenneMensuelle,
    );
  }

  Future<void> _enregistrer() async {
    final calendrier = _calendrier();
    final erreurs = calendrier.erreurs();
    if (erreurs.isNotEmpty) {
      afficherMessage(context, erreurs.join('\n'), erreur: true);
      return;
    }
    final ok = await executer(
      context,
      () => widget.etat.services.calendriers.enregistrer(widget.anneeId, calendrier),
      succes: 'Périodes enregistrées pour cette année scolaire.',
    );
    if (ok) widget.etat.donneesModifiees();
  }

  @override
  Widget build(BuildContext context) {
    final annee = widget.etat.anneeCourante;
    final modifiable = widget.etat.peut(Permission.parametresGerer);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TitreSection(
          'Périodes',
          sousTitre: 'Découpage de l\'année ${annee?.libelle ?? ''} : les moyennes '
              'des périodes et de l\'année en découlent. Les notes déjà saisies '
              'ne sont jamais modifiées.',
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _carte(
                  titre: 'Type de périodes',
                  aide: 'Chaque mois (octobre à juin) appartient à une seule période.',
                  enfants: [
                    SegmentedButton<TypePeriodes>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: TypePeriodes.trimestres,
                          label: Text('Trois trimestres', key: Key('type_trimestres')),
                        ),
                        ButtonSegment(
                          value: TypePeriodes.semestres,
                          label: Text('Deux semestres', key: Key('type_semestres')),
                        ),
                        ButtonSegment(
                          value: TypePeriodes.personnalise,
                          label: Text('Personnalisé', key: Key('type_personnalise')),
                        ),
                      ],
                      selected: {_type},
                      onSelectionChanged:
                          modifiable ? (choix) => _choisirType(choix.first) : null,
                    ),
                    const SizedBox(height: 16),
                    ..._editeurGroupes(
                      _periodes,
                      prefixe: 'periode',
                      cles: 'p',
                      nomBase: 'Période',
                      periodes: true,
                      modifiable: modifiable,
                      couvrirTout: true,
                    ),
                  ],
                ),
                _carte(
                  titre: 'Séquences',
                  aide: 'Facultatif : découpe chaque période en séquences (par '
                      'exemple deux mois) pour calculer des moyennes séquentielles.',
                  enfants: [
                    SwitchListTile(
                      key: const Key('option_sequences'),
                      contentPadding: EdgeInsets.zero,
                      value: _sequences.isNotEmpty,
                      onChanged: modifiable ? _basculerSequences : null,
                      title: const Text('Activer les moyennes séquentielles'),
                    ),
                    if (_sequences.isNotEmpty)
                      ..._editeurGroupes(
                        _sequences,
                        prefixe: 'sequence',
                        cles: 'q',
                        nomBase: 'Séquence',
                        periodes: false,
                        modifiable: modifiable,
                        couvrirTout: true,
                      ),
                  ],
                ),
                _carte(
                  titre: 'Affichage',
                  enfants: [
                    SwitchListTile(
                      key: const Key('option_moyenne_mensuelle'),
                      contentPadding: EdgeInsets.zero,
                      value: _moyenneMensuelle,
                      onChanged:
                          modifiable ? (v) => setState(() => _moyenneMensuelle = v) : null,
                      title: const Text('Afficher les moyennes mensuelles'),
                      subtitle: const Text(
                        'Désactivé : la grille d\'un mois ne montre que les notes, '
                        'sans moyenne, rang ni mention.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (modifiable)
                  FilledButton.icon(
                    key: const Key('enregistrer_periodes'),
                    onPressed: _enregistrer,
                    icon: const Icon(Icons.save),
                    label: const Text('Enregistrer'),
                  )
                else
                  const Text(
                    'Vous n\'avez pas l\'autorisation de modifier les paramètres.',
                    style: TextStyle(color: CouleursGesco.orange),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _editeurGroupes(
    List<_Groupe> groupes, {
    required String prefixe,
    required String cles,
    required String nomBase,
    required bool periodes,
    required bool modifiable,
    required bool couvrirTout,
  }) {
    final sansGroupe = [
      for (final m in moisScolaires)
        if (!groupes.any((g) => g.mois.contains(m))) libelleMois(m),
    ];
    return [
      for (var i = 0; i < groupes.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: CouleursGesco.bordure),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 240,
                      child: TextField(
                        key: Key('${prefixe}_nom_$i'),
                        controller: groupes[i].nom,
                        enabled: modifiable,
                        decoration: champ('Nom'),
                      ),
                    ),
                    const Spacer(),
                    if (modifiable && groupes.length > 1)
                      IconButton(
                        key: Key('retirer_${prefixe}_$i'),
                        tooltip: 'Retirer',
                        onPressed: () => _retirer(groupes, groupes[i], periodes: periodes),
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final m in moisScolaires)
                      FilterChip(
                        key: Key('${prefixe}_${i}_mois_$m'),
                        label: Text(libelleMois(m)),
                        selected: groupes[i].mois.contains(m),
                        showCheckmark: false,
                        selectedColor: CouleursGesco.bleuClair,
                        onSelected: modifiable
                            ? (_) => _basculerMois(groupes, groupes[i], m, periodes: periodes)
                            : null,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      if (couvrirTout && sansGroupe.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Mois sans ${periodes ? 'période' : 'séquence'} : ${sansGroupe.join(', ')}.',
            key: Key('${prefixe}_mois_libres'),
            style: const TextStyle(color: CouleursGesco.orange),
          ),
        ),
      if (modifiable && groupes.length < (periodes ? 6 : 9))
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: Key('ajouter_$prefixe'),
            onPressed: () => _ajouter(groupes, cles, nomBase, periodes: periodes),
            icon: const Icon(Icons.add),
            label: Text('Ajouter ${periodes ? 'une période' : 'une séquence'}'),
          ),
        ),
    ];
  }

  Widget _carte({
    required String titre,
    String? aide,
    required List<Widget> enfants,
  }) {
    return Carte(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titre, style: Theme.of(context).textTheme.titleMedium),
            if (aide != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(aide, style: const TextStyle(color: CouleursGesco.gris)),
              ),
            const SizedBox(height: 16),
            ...enfants,
          ],
        ),
      ),
    );
  }
}
