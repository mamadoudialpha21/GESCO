import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../domain/calendrier.dart';
import '../../domain/niveaux.dart';
import '../../domain/periodes.dart';
import '../../domain/permissions.dart';
import '../commun/chargeur.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../theme.dart';

/// Méthode de calcul et découpage de l'année en périodes. Propre à chaque année
/// scolaire et à chaque cycle d'études : la maternelle et le primaire calculent
/// par compositions (décembre, mars, juin), le collège et le lycée par mois,
/// compositions et semestres. L'ancienne méthode (trimestres, semestres ou
/// découpage personnalisé, séquences facultatives) reste disponible.
class OngletPeriodes extends StatefulWidget {
  const OngletPeriodes({super.key, required this.etat});

  final EtatApp etat;

  @override
  State<OngletPeriodes> createState() => _OngletPeriodesState();
}

/// Clé du calendrier général (classes sans cycle).
const String _cleGeneral = 'general';

class _DonneesPeriodes {
  const _DonneesPeriodes(this.calendrier, this.autresClasses);

  final Calendrier calendrier;

  /// Vrai si une classe de l'année n'est rattachée à aucun cycle.
  final bool autresClasses;
}

class _OngletPeriodesState extends State<OngletPeriodes> {
  String _cycle = Cycle.primaire.cle;

  @override
  Widget build(BuildContext context) {
    final etat = widget.etat;
    final anneeId = etat.anneeId;
    if (anneeId == null) {
      return const MessageVide(
        'Créez d\'abord une année scolaire (onglet « Années scolaires »).',
        icone: Icons.event_outlined,
      );
    }
    final cycle = Cycle.depuisCle(_cycle);
    return Chargeur<_DonneesPeriodes>(
      cle: (anneeId, etat.version, _cycle),
      charger: () async {
        final services = etat.services;
        final classes = await services.classes.lister(anneeId);
        return _DonneesPeriodes(
          await services.calendriers.lire(anneeId, cycle: cycle),
          classes.any((c) => c.classe.cycle == null),
        );
      },
      builder: (context, donnees) => _EditeurPeriodes(
        // La clé suit les données réellement chargées (et non le compteur de
        // version) : après un enregistrement, l'éditeur repart de la base dès
        // que la relecture est terminée, jamais des anciennes valeurs.
        key: ValueKey('periodes-$anneeId-$_cycle-${identityHashCode(donnees)}'),
        etat: etat,
        anneeId: anneeId,
        calendrier: donnees.calendrier,
        cycle: cycle,
        autresClasses: donnees.autresClasses,
        surCycle: (cle) => setState(() => _cycle = cle),
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
    required this.cycle,
    required this.autresClasses,
    required this.surCycle,
  });

  final EtatApp etat;
  final int anneeId;
  final Calendrier calendrier;

  /// Cycle dont on règle les périodes ; null : calendrier général.
  final Cycle? cycle;
  final bool autresClasses;
  final void Function(String cle) surCycle;

  @override
  State<_EditeurPeriodes> createState() => _EditeurPeriodesState();
}

class _EditeurPeriodesState extends State<_EditeurPeriodes> {
  late TypePeriodes _type;
  late List<_Groupe> _periodes;
  late List<_Groupe> _sequences;
  late bool _moyenneMensuelle;
  late bool _ponderee;

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
    _ponderee = c.ponderee;
  }

  /// Vrai si le calendrier suit la méthode de calcul du cycle (compositions,
  /// ou mois + compositions + semestres).
  bool get _methodeDuCycle =>
      _type == TypePeriodes.compositions || _type == TypePeriodes.semestresCompo;

  /// Ancien modèle du cycle : trois trimestres au primaire et en maternelle,
  /// deux trimestres au collège et au lycée.
  static Calendrier _modeleAncien(Cycle cycle) => switch (cycle) {
        Cycle.maternelle || Cycle.primaire => Calendrier.trimestres,
        Cycle.college || Cycle.lycee => Calendrier.deuxTrimestres,
      };

  void _choisirMethode({required bool duCycle}) {
    final cycle = widget.cycle;
    if (cycle == null) return;
    setState(() {
      final modele = duCycle ? Calendrier.pourCycle(cycle) : _modeleAncien(cycle);
      _type = modele.type;
      _retires
        ..addAll(_periodes)
        ..addAll(_sequences);
      _periodes = _groupes(modele.periodes);
      _sequences = _groupes(modele.sequences);
    });
  }

  void _choisirType(TypePeriodes type) {
    setState(() {
      _type = type;
      final modele = switch (type) {
        TypePeriodes.trimestres => Calendrier.trimestres,
        TypePeriodes.deuxTrimestres => Calendrier.deuxTrimestres,
        TypePeriodes.semestres => Calendrier.semestres,
        TypePeriodes.compositions => Calendrier.compositions,
        TypePeriodes.semestresCompo => Calendrier.semestresCompo,
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
    // Méthode du cycle : la structure est fixe (mois des compositions et des
    // semestres), seuls la pondération et l'affichage se règlent.
    if (_methodeDuCycle) {
      final modele = _type == TypePeriodes.compositions
          ? Calendrier.compositions
          : Calendrier.semestresCompo;
      return modele.copyWith(moyenneMensuelle: _moyenneMensuelle, ponderee: _ponderee);
    }
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
      ponderee: _ponderee,
    );
  }

  static String _nomCycle(Cycle? cycle) => cycle?.libelle ?? 'autres classes';

  Future<void> _enregistrer() async {
    final calendrier = _calendrier();
    final erreurs = calendrier.erreurs();
    if (erreurs.isNotEmpty) {
      afficherMessage(context, erreurs.join('\n'), erreur: true);
      return;
    }
    final ok = await executer(
      context,
      () => widget.etat.services.calendriers
          .enregistrer(widget.anneeId, calendrier, cycle: widget.cycle),
      succes: 'Périodes enregistrées (${_nomCycle(widget.cycle)}) pour cette '
          'année scolaire.',
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
              'des périodes et de l\'année en découlent. Chaque cycle a son '
              'propre découpage. Les notes déjà saisies ne sont jamais modifiées.',
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
                  titre: 'Cycle d\'études',
                  aide: 'Maternelle : petite à grande section. Primaire : 1ère à 6ème '
                      'année. Collège : 7ème à 10ème année. Lycée : 11ème année à '
                      'Terminale. Chaque cycle a sa méthode de calcul. Changer de '
                      'cycle abandonne les modifications non enregistrées.',
                  enfants: [
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: [
                        for (final c in Cycle.values)
                          ButtonSegment(
                            value: c.cle,
                            label: Text(c.libelle, key: Key('cycle_periodes_${c.cle}')),
                          ),
                        if (widget.autresClasses || widget.cycle == null)
                          const ButtonSegment(
                            value: _cleGeneral,
                            label: Text(
                              'Autres classes',
                              key: Key('cycle_periodes_general'),
                            ),
                          ),
                      ],
                      selected: {widget.cycle?.cle ?? _cleGeneral},
                      onSelectionChanged: (choix) => widget.surCycle(choix.first),
                    ),
                  ],
                ),
                if (widget.cycle != null)
                  _carte(
                    titre: 'Méthode de calcul',
                    aide: 'La méthode du cycle est celle de GESCO pour ce cycle. '
                        'L\'ancienne méthode (par trimestres ou semestres, '
                        'découpage libre) reste possible.',
                    enfants: [
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: true,
                            label: Text(
                              'Méthode du cycle',
                              key: const Key('methode_cycle'),
                            ),
                          ),
                          ButtonSegment(
                            value: false,
                            label: Text(
                              'Ancienne méthode',
                              key: const Key('methode_ancienne'),
                            ),
                          ),
                        ],
                        selected: {_methodeDuCycle},
                        onSelectionChanged: modifiable
                            ? (choix) => _choisirMethode(duCycle: choix.first)
                            : null,
                      ),
                      if (_methodeDuCycle) ...[
                        const SizedBox(height: 16),
                        Text(
                          _descriptionMethode(_type),
                          key: const Key('description_methode'),
                        ),
                      ],
                    ],
                  ),
                if (!_methodeDuCycle) ...[
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
                          value: TypePeriodes.deuxTrimestres,
                          label: Text('Deux trimestres', key: Key('type_deux_trimestres')),
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
                ],
                _carte(
                  titre: 'Calcul des moyennes',
                  enfants: [
                    SwitchListTile(
                      key: const Key('option_ponderee'),
                      contentPadding: EdgeInsets.zero,
                      value: _ponderee,
                      onChanged: modifiable ? (v) => setState(() => _ponderee = v) : null,
                      title: const Text('Pondérer par les coefficients des matières'),
                      subtitle: const Text(
                        'Activé : moyenne = Σ(note × coefficient) ÷ Σ coefficients ; '
                        'avec des coefficients tous égaux à 1, c\'est la somme des '
                        'notes ÷ le nombre de matières. Désactivé : moyenne simple, '
                        'les coefficients sont ignorés.',
                      ),
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

  static String _descriptionMethode(TypePeriodes type) => switch (type) {
        TypePeriodes.compositions =>
          'Trois compositions par an : décembre (compo 1), mars (compo 2) et juin '
              '(compo 3). Moyenne d\'une composition = somme des notes de la '
              'composition ÷ nombre de matières. Note finale = somme des moyennes '
              'des compositions ÷ nombre de compositions.',
        TypePeriodes.semestresCompo =>
          'Une note par matière et par mois, d\'octobre à juin. Moyenne d\'un mois = '
              'somme des notes ÷ nombre de matières. La moyenne de janvier est la '
              'composition 1, celle de juin la composition 2. Semestre 1 = (2 × '
              'composition 1 + moyenne des mois d\'octobre, novembre et décembre) ÷ 3. '
              'Semestre 2 = (2 × composition 2 + moyenne des mois de février à mai) ÷ 3. '
              'Moyenne de l\'année = (semestre 1 + semestre 2) ÷ 2.',
        _ => '',
      };

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
