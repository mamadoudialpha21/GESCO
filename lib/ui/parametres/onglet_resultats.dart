import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../domain/arrondi.dart';
import '../../domain/modeles.dart';
import '../commun/chargeur.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../theme.dart';

/// Seuils des mentions et des décisions, propres à chaque année scolaire.
/// Modifiables à tout moment, sans toucher au code de l'application.
class OngletResultats extends StatelessWidget {
  const OngletResultats({super.key, required this.etat});

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
    return Chargeur<ConfigResultats>(
      cle: (anneeId, etat.version),
      charger: () => etat.services.configs.lire(anneeId),
      builder: (context, config) => _EditeurResultats(
        // Nouvelle clé = nouvel éditeur quand on change d'année ou après
        // un enregistrement : les champs repartent de la base.
        key: ValueKey('resultats-$anneeId-${etat.version}'),
        etat: etat,
        anneeId: anneeId,
        config: config,
      ),
    );
  }
}

class _LignePalier {
  _LignePalier(int seuilInitial, String libelleInitial)
      : seuil = TextEditingController(text: formaterCentiemes(seuilInitial)),
        libelle = TextEditingController(text: libelleInitial);

  /// Ligne vide, pour un palier à compléter.
  _LignePalier.vide()
      : seuil = TextEditingController(),
        libelle = TextEditingController();

  final TextEditingController seuil;
  final TextEditingController libelle;

  void dispose() {
    seuil.dispose();
    libelle.dispose();
  }
}

class _EditeurResultats extends StatefulWidget {
  const _EditeurResultats({
    super.key,
    required this.etat,
    required this.anneeId,
    required this.config,
  });

  final EtatApp etat;
  final int anneeId;
  final ConfigResultats config;

  @override
  State<_EditeurResultats> createState() => _EditeurResultatsState();
}

class _EditeurResultatsState extends State<_EditeurResultats> {
  final TextEditingController _admission = TextEditingController();
  final TextEditingController _bon = TextEditingController();
  List<_LignePalier> _mentions = [];
  List<_LignePalier> _decisionsPeriode = [];
  List<_LignePalier> _decisionsAnnee = [];
  bool _absenceZero = false;
  bool _periodeComplete = false;

  /// Lignes retirées : leurs contrôleurs sont libérés à la fermeture de
  /// l'écran seulement, pour ne pas toucher à un champ encore affiché.
  final List<_LignePalier> _retirees = [];

  @override
  void initState() {
    super.initState();
    _remplir(widget.config);
  }

  @override
  void dispose() {
    _admission.dispose();
    _bon.dispose();
    for (final l in [..._mentions, ..._decisionsPeriode, ..._decisionsAnnee, ..._retirees]) {
      l.dispose();
    }
    super.dispose();
  }

  static List<_LignePalier> _lignes(List<Palier> paliers) => [
        for (final p in paliers) _LignePalier(p.seuil, p.libelle),
      ];

  void _remplir(ConfigResultats c) {
    _retirees.addAll([..._mentions, ..._decisionsPeriode, ..._decisionsAnnee]);
    _admission.text = formaterCentiemes(c.seuilAdmission);
    _bon.text = formaterCentiemes(c.seuilBon);
    _mentions = _lignes(c.mentions);
    _decisionsPeriode = _lignes(c.decisionsPeriode);
    _decisionsAnnee = _lignes(c.decisionsAnnee);
    _absenceZero = c.absenceEgaleZero;
    _periodeComplete = c.exigerPeriodeComplete;
  }

  List<Palier> _lirePaliers(
    List<_LignePalier> lignes,
    String rubrique,
    List<String> erreurs,
  ) {
    final resultat = <Palier>[];
    for (final l in lignes) {
      final seuil = analyserDecimal(l.seuil.text, maxCentiemes: 2000);
      if (seuil == null) {
        erreurs.add('$rubrique : seuil « ${l.seuil.text} » invalide (nombre de 0 à 20).');
        continue;
      }
      resultat.add(Palier(seuil, l.libelle.text.trim()));
    }
    return resultat;
  }

  Future<void> _enregistrer() async {
    final erreurs = <String>[];
    final admission = analyserDecimal(_admission.text, maxCentiemes: 2000);
    final bon = analyserDecimal(_bon.text, maxCentiemes: 2000);
    if (admission == null) {
      erreurs.add('Seuil d\'admission invalide (nombre de 0 à 20).');
    }
    if (bon == null) {
      erreurs.add('Seuil « bon résultat » invalide (nombre de 0 à 20).');
    }
    final mentions = _lirePaliers(_mentions, 'Mentions', erreurs);
    final decisionsPeriode =
        _lirePaliers(_decisionsPeriode, 'Décisions (mois et trimestres)', erreurs);
    final decisionsAnnee = _lirePaliers(_decisionsAnnee, 'Décisions (année)', erreurs);

    if (erreurs.isNotEmpty || admission == null || bon == null) {
      afficherMessage(context, erreurs.join('\n'), erreur: true);
      return;
    }

    final config = ConfigResultats(
      seuilAdmission: admission,
      seuilBon: bon,
      mentions: mentions,
      decisionsPeriode: decisionsPeriode,
      decisionsAnnee: decisionsAnnee,
      absenceEgaleZero: _absenceZero,
      exigerPeriodeComplete: _periodeComplete,
    );
    final ok = await executer(
      context,
      () => widget.etat.services.configs.enregistrer(widget.anneeId, config),
      succes: 'Seuils enregistrés pour cette année scolaire.',
    );
    if (ok) widget.etat.donneesModifiees();
  }

  void _valeursParDefaut() {
    setState(() => _remplir(ConfigResultats.defaut));
    afficherMessage(
      context,
      'Valeurs par défaut chargées. Cliquez sur « Enregistrer » pour les appliquer.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final annee = widget.etat.anneeCourante;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TitreSection(
          'Mentions et décisions',
          sousTitre:
              'Seuils propres à l\'année ${annee?.libelle ?? ''}. Les mentions et '
              'décisions sont calculées automatiquement à partir de ces valeurs.',
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _carte(
                  titre: 'Admission et codes couleur',
                  enfants: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _admission,
                            decoration: champ(
                              'Moyenne minimale pour être admis(e)',
                              aide: 'Orange à partir de ce seuil, rouge en dessous',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _bon,
                            decoration: champ(
                              'Moyenne à partir de laquelle le résultat est bon',
                              aide: 'Vert à partir de ce seuil',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                _carte(
                  titre: 'Règles de calcul',
                  aide: 'Ces règles s\'appliquent à tous les calculs de l\'année : '
                      'moyennes, rangs, classements et statistiques.',
                  enfants: [
                    SwitchListTile(
                      key: const Key('option_absence_zero'),
                      contentPadding: EdgeInsets.zero,
                      value: _absenceZero,
                      onChanged: (v) => setState(() => _absenceZero = v),
                      title: const Text('Une absence compte pour zéro'),
                      subtitle: const Text(
                        'Désactivé : une absence est ignorée dans la moyenne '
                        '(jamais comptée comme zéro).',
                      ),
                    ),
                    SwitchListTile(
                      key: const Key('option_periode_complete'),
                      contentPadding: EdgeInsets.zero,
                      value: _periodeComplete,
                      onChanged: (v) => setState(() => _periodeComplete = v),
                      title: const Text('Exiger les trois mois pour calculer un trimestre'),
                      subtitle: const Text(
                        'Activé : pas de moyenne trimestrielle tant qu\'un mois '
                        'n\'a pas de moyenne, ni de moyenne annuelle tant qu\'un '
                        'trimestre n\'en a pas.',
                      ),
                    ),
                  ],
                ),
                _carte(
                  titre: 'Mentions',
                  aide:
                      'La mention la plus haute atteinte est retenue. '
                      'En dessous du premier seuil, aucune mention.',
                  enfants: _editeurPaliers(
                    _mentions,
                    libelleSeuil: 'Moyenne ≥',
                    libelleTexte: 'Mention',
                  ),
                ),
                _carte(
                  titre: 'Décisions des mois et des trimestres',
                  aide: 'Prévoyez un palier à 0,00 pour couvrir toutes les moyennes.',
                  enfants: _editeurPaliers(
                    _decisionsPeriode,
                    libelleSeuil: 'Moyenne ≥',
                    libelleTexte: 'Décision',
                  ),
                ),
                _carte(
                  titre: 'Décisions annuelles',
                  aide: 'Prévoyez un palier à 0,00 pour couvrir toutes les moyennes.',
                  enfants: _editeurPaliers(
                    _decisionsAnnee,
                    libelleSeuil: 'Moyenne ≥',
                    libelleTexte: 'Décision',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const Key('enregistrer_resultats'),
                      onPressed: _enregistrer,
                      icon: const Icon(Icons.save),
                      label: const Text('Enregistrer'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('valeurs_par_defaut'),
                      onPressed: _valeursParDefaut,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Valeurs par défaut'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
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

  List<Widget> _editeurPaliers(
    List<_LignePalier> lignes, {
    required String libelleSeuil,
    required String libelleTexte,
  }) {
    return [
      for (var i = 0; i < lignes.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              SizedBox(
                width: 150,
                child: TextField(
                  controller: lignes[i].seuil,
                  decoration: champ(libelleSeuil),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: lignes[i].libelle,
                  decoration: champ(libelleTexte),
                ),
              ),
              IconButton(
                tooltip: 'Retirer ce palier',
                onPressed: () => setState(() {
                  _retirees.add(lignes.removeAt(i));
                }),
                icon: const Icon(Icons.delete_outline, color: CouleursGesco.rouge),
              ),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => lignes.add(_LignePalier.vide())),
          icon: const Icon(Icons.add),
          label: const Text('Ajouter un palier'),
        ),
      ),
    ];
  }
}
