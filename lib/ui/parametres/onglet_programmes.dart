import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/depots/programme_depot.dart';
import '../../data/modeles_donnees.dart';
import '../../domain/arrondi.dart';
import '../../domain/calendrier.dart';
import '../../domain/niveaux.dart';
import '../../domain/permissions.dart';
import '../commun/chargeur.dart';
import '../commun/choix.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../theme.dart';

/// Cycles et programmes : pour chaque cycle (maternelle, primaire, collège) et,
/// au lycée, pour chaque option (SM, SE, SS), les matières et leurs
/// coefficients. Elles sont ajoutées automatiquement à chaque classe du cycle,
/// à la création de la classe comme dès qu'on les ajoute ici.
class OngletProgrammes extends StatefulWidget {
  const OngletProgrammes({super.key, required this.etat});

  final EtatApp etat;

  @override
  State<OngletProgrammes> createState() => _OngletProgrammesState();
}

class _DonneesProgramme {
  const _DonneesProgramme({
    required this.matieres,
    required this.classes,
    required this.calendrier,
  });

  final List<MatiereProgramme> matieres;

  /// Classes de l'année rattachées à ce cycle (et à cette option au lycée).
  final List<ClasseResume> classes;

  /// Méthode de calcul de ce cycle pour l'année.
  final Calendrier calendrier;
}

class _OngletProgrammesState extends State<OngletProgrammes> {
  Cycle _cycle = Cycle.primaire;
  SerieLycee _serie = SerieLycee.sciencesMathematiques;

  EtatApp get _etat => widget.etat;

  /// Option choisie : seulement au lycée.
  SerieLycee? get _option => _cycle == Cycle.lycee ? _serie : null;

  String get _cibleLibelle =>
      _option == null ? 'le cycle ${_cycle.libelle}' : 'l\'option ${_option!.libelle}';

  @override
  Widget build(BuildContext context) {
    final anneeId = _etat.anneeId;
    if (anneeId == null) {
      return const MessageVide(
        'Créez d\'abord une année scolaire (onglet « Années scolaires »).',
        icone: Icons.event_outlined,
      );
    }
    final cycle = _cycle;
    final option = _option;
    return Chargeur<_DonneesProgramme>(
      cle: (anneeId, _etat.version, cycle, option),
      charger: () async {
        final services = _etat.services;
        final classes = await services.classes.lister(anneeId);
        return _DonneesProgramme(
          matieres: await services.programmes.lister(anneeId, cycle, serie: option),
          classes: [
            for (final c in classes)
              if (c.classe.cycle == cycle && (option == null || c.classe.serie == option)) c,
          ],
          calendrier: await services.calendriers.lire(anneeId, cycle: cycle),
        );
      },
      builder: (context, donnees) => _contenu(context, anneeId, donnees),
    );
  }

  Widget _contenu(BuildContext context, int anneeId, _DonneesProgramme d) {
    final gerer = _etat.peut(Permission.classesGerer);
    final niveaux = niveauxDuCycle(_cycle).map((n) => n.libelle).join(', ');
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TitreSection(
                  'Cycles et programmes',
                  sousTitre: 'Les matières et coefficients d\'un cycle (ou d\'une option du '
                      'lycée) sont ajoutés automatiquement à chaque classe de ce cycle : '
                      'à la création de la classe, et dès que vous les ajoutez ici.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in Cycle.values)
                      ChoiceChip(
                        key: Key('cycle_prog_${c.cle}'),
                        label: Text(c.libelle),
                        selected: _cycle == c,
                        onSelected: (_) => setState(() => _cycle = c),
                      ),
                  ],
                ),
                if (_cycle == Cycle.lycee) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in SerieLycee.values)
                        ChoiceChip(
                          key: Key('serie_prog_${s.code}'),
                          label: Text('${s.code} · ${s.libelle}'),
                          selected: _serie == s,
                          onSelected: (_) => setState(() => _serie = s),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Niveaux : $niveaux.',
                  style: const TextStyle(color: CouleursGesco.gris),
                ),
                if (!gerer) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Lecture seule : vous n\'avez pas le droit de modifier les programmes.',
                    key: Key('programme_lecture_seule'),
                    style: TextStyle(color: CouleursGesco.gris),
                  ),
                ],
                const SizedBox(height: 16),
                _carteMethode(d),
                const SizedBox(height: 16),
                _carteMatieres(anneeId, d, gerer),
                const SizedBox(height: 16),
                _carteClasses(anneeId, d, gerer),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _carteMethode(_DonneesProgramme d) {
    final c = d.calendrier;
    return Carte(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.calculate_outlined, color: CouleursGesco.bleu),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Méthode de calcul de ce cycle : ${c.descriptionCourte}, moyennes '
              '${c.ponderee ? 'pondérées par les coefficients' : 'simples (sans coefficient)'}. '
              'Elle se règle dans l\'onglet « Périodes ».',
              key: const Key('methode_programme'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteMatieres(int anneeId, _DonneesProgramme d, bool gerer) {
    return Carte(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Matières et coefficients de $_cibleLibelle',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                key: const Key('ajouter_matiere_programme'),
                onPressed: gerer ? () => _ajouter(anneeId) : null,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter une matière'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (d.matieres.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Aucune matière dans ce programme. Ajoutez-les ici une seule fois : '
                'elles seront ajoutées à toutes les classes concernées.',
                key: Key('programme_vide'),
                style: TextStyle(color: CouleursGesco.gris),
              ),
            )
          else
            for (final (i, m) in d.matieres.indexed)
              ListTile(
                key: Key('matiere_programme_${m.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(m.nom),
                subtitle: Text(
                  'Coefficient ${formaterCoefficient(m.coefficient)} · sur ${m.bareme}'
                  '${m.facultative ? ' · facultative' : ''}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: Key('monter_programme_${m.id}'),
                      tooltip: 'Monter',
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: gerer && i > 0 ? () => _deplacer(anneeId, d, i, -1) : null,
                    ),
                    IconButton(
                      key: Key('descendre_programme_${m.id}'),
                      tooltip: 'Descendre',
                      icon: const Icon(Icons.arrow_downward),
                      onPressed: gerer && i < d.matieres.length - 1
                          ? () => _deplacer(anneeId, d, i, 1)
                          : null,
                    ),
                    IconButton(
                      key: Key('modifier_programme_${m.id}'),
                      tooltip: 'Modifier',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: gerer ? () => _modifier(m) : null,
                    ),
                    IconButton(
                      key: Key('supprimer_programme_${m.id}'),
                      tooltip: 'Retirer du programme',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: gerer ? () => _supprimer(m) : null,
                    ),
                  ],
                ),
              ),
          if (d.matieres.isNotEmpty) ...[
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Une classe qui a perdu une matière à la main ne la retrouve que si '
                    'vous appliquez le programme.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: CouleursGesco.gris),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  key: const Key('appliquer_programme'),
                  onPressed: gerer ? () => _appliquer(anneeId) : null,
                  icon: const Icon(Icons.playlist_add_check),
                  label: const Text('Appliquer aux classes existantes'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _carteClasses(int anneeId, _DonneesProgramme d, bool gerer) {
    return Carte(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Classes de $_cibleLibelle',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                key: const Key('ajouter_classe_programme'),
                onPressed: gerer ? () => _ajouterClasse(anneeId) : null,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter une classe'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (d.classes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Aucune classe pour le moment. Une classe créée ici reçoit '
                'automatiquement les matières du programme.',
                key: Key('classes_programme_vide'),
                style: TextStyle(color: CouleursGesco.gris),
              ),
            )
          else
            for (final c in d.classes)
              ListTile(
                key: Key('classe_programme_${c.classe.id}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.class_outlined),
                title: Text(c.classe.nom),
                subtitle: Text(
                  '${c.classe.niveau}'
                  '${c.classe.serie == null ? '' : ' · ${c.classe.serie!.libelle}'}'
                  ' · ${pluriel(c.nbEleves, 'élève')}'
                  ' · ${pluriel(c.nbMatieres, 'matière')}',
                ),
              ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- actions

  Future<void> _ajouter(int anneeId) async {
    final saisie = await showDialog<_SaisieMatiere>(
      context: context,
      builder: (ctx) => const _DialogueMatiere(),
    );
    if (saisie == null || !mounted) return;
    ResultatProgramme? resultat;
    final ok = await executer(context, () async {
      final (_, r) = await _etat.services.programmes.ajouter(
        anneeId: anneeId,
        cycle: _cycle,
        serie: _option,
        nom: saisie.nom,
        coefficient: saisie.coefficient,
        bareme: saisie.bareme,
        facultative: saisie.facultative,
      );
      resultat = r;
    });
    if (!ok) return;
    _etat.donneesModifiees();
    if (!mounted) return;
    final r = resultat!;
    afficherMessage(
      context,
      r.classesConcernees == 0
          ? '« ${saisie.nom} » ajoutée au programme. Elle sera ajoutée aux classes que '
              'vous créerez dans ${_cibleLibelle.replaceFirst('le cycle', 'ce cycle')}.'
          : '« ${saisie.nom} » ajoutée au programme. ${r.resume}',
    );
  }

  Future<void> _modifier(MatiereProgramme m) async {
    final saisie = await showDialog<_SaisieMatiere>(
      context: context,
      builder: (ctx) => _DialogueMatiere(existante: m),
    );
    if (saisie == null || !mounted) return;
    ResultatProgramme? resultat;
    final ok = await executer(context, () async {
      resultat = await _etat.services.programmes.modifier(
        m.id,
        nom: saisie.nom,
        coefficient: saisie.coefficient,
        bareme: saisie.bareme,
        facultative: saisie.facultative,
      );
    });
    if (!ok) return;
    _etat.donneesModifiees();
    if (!mounted) return;
    afficherMessage(context, 'Programme mis à jour. ${resultat!.resume}');
  }

  Future<void> _supprimer(MatiereProgramme m) async {
    final confirme = await confirmer(
      context,
      titre: 'Retirer « ${m.nom} » du programme ?',
      message: 'La matière est retirée des classes de $_cibleLibelle qui n\'ont ni note ni '
          'évaluation pour elle. Là où des notes existent, elle reste dans la classe.',
      libelleConfirmer: 'Retirer',
      danger: true,
    );
    if (!confirme || !mounted) return;
    ResultatProgramme? resultat;
    final ok = await executer(context, () async {
      resultat = await _etat.services.programmes.supprimer(m.id);
    });
    if (!ok) return;
    _etat.donneesModifiees();
    if (!mounted) return;
    afficherMessage(context, '« ${m.nom} » retirée du programme. ${resultat!.resume}');
  }

  Future<void> _deplacer(int anneeId, _DonneesProgramme d, int index, int sens) async {
    final ids = [for (final m in d.matieres) m.id];
    final voisin = index + sens;
    if (voisin < 0 || voisin >= ids.length) return;
    final id = ids.removeAt(index);
    ids.insert(voisin, id);
    final ok = await executer(
      context,
      () => _etat.services.programmes.reordonner(anneeId, _cycle, ids, serie: _option),
    );
    if (ok) _etat.donneesModifiees();
  }

  Future<void> _appliquer(int anneeId) async {
    ResultatProgramme? resultat;
    final ok = await executer(context, () async {
      resultat = await _etat.services.programmes.appliquer(anneeId, _cycle, serie: _option);
    });
    if (!ok) return;
    _etat.donneesModifiees();
    if (!mounted) return;
    final r = resultat!;
    afficherMessage(
      context,
      r.classesConcernees == 0
          ? r.resume
          : r.ajoutees == 0
              ? 'Rien à ajouter : les ${pluriel(r.classesConcernees, 'classe')} '
                  'du programme ont déjà toutes ses matières.'
              : 'Programme appliqué : ${pluriel(r.ajoutees, 'matière')} ajoutée'
                  '${r.ajoutees > 1 ? 's' : ''} dans '
                  '${pluriel(r.classesConcernees, 'classe')} concernée'
                  '${r.classesConcernees > 1 ? 's' : ''}.',
    );
  }

  Future<void> _ajouterClasse(int anneeId) async {
    final saisie = await showDialog<_SaisieClasse>(
      context: context,
      builder: (ctx) => _DialogueClasse(cycle: _cycle, serie: _option),
    );
    if (saisie == null || !mounted) return;
    Classe? creee;
    var nbMatieres = 0;
    final ok = await executer(context, () async {
      final services = _etat.services;
      creee = await services.classes.creer(
        anneeId: anneeId,
        nom: saisie.nom,
        niveauCode: saisie.niveauCode,
        serie: _option,
      );
      nbMatieres = (await services.matieres.lister(creee!.id)).length;
    });
    if (!ok) return;
    _etat.donneesModifiees();
    if (!mounted) return;
    afficherMessage(
      context,
      nbMatieres == 0
          ? 'Classe « ${creee!.nom} » créée. Le programme est vide : aucune matière ajoutée.'
          : 'Classe « ${creee!.nom} » créée avec ${pluriel(nbMatieres, 'matière')} du programme.',
    );
  }
}

class _SaisieMatiere {
  const _SaisieMatiere(this.nom, this.coefficient, this.bareme, this.facultative);

  final String nom;
  final int coefficient;
  final int bareme;
  final bool facultative;
}

class _DialogueMatiere extends StatefulWidget {
  const _DialogueMatiere({this.existante});

  final MatiereProgramme? existante;

  @override
  State<_DialogueMatiere> createState() => _DialogueMatiereState();
}

class _DialogueMatiereState extends State<_DialogueMatiere> {
  late final TextEditingController _nom;
  late final TextEditingController _coefficient;
  late final TextEditingController _bareme;
  bool _facultative = false;
  String? _erreurNom;
  String? _erreurCoefficient;
  String? _erreurBareme;

  @override
  void initState() {
    super.initState();
    final m = widget.existante;
    _nom = TextEditingController(text: m?.nom ?? '');
    _coefficient = TextEditingController(
      text: m == null ? '1' : formaterCoefficient(m.coefficient),
    );
    _bareme = TextEditingController(text: '${m?.bareme ?? 20}');
    _facultative = m?.facultative ?? false;
  }

  @override
  void dispose() {
    _nom.dispose();
    _coefficient.dispose();
    _bareme.dispose();
    super.dispose();
  }

  void _valider() {
    final nom = _nom.text.trim();
    final coefficient = analyserCoefficient(_coefficient.text);
    final bareme = int.tryParse(_bareme.text.trim());
    final baremeValide = bareme != null && bareme >= 1 && bareme <= 1000;
    setState(() {
      _erreurNom = nom.isEmpty ? 'Le nom de la matière est obligatoire.' : null;
      _erreurCoefficient =
          coefficient == null ? 'Coefficient invalide (de 0,01 à 99,99 ; ex. 2 ou 2,5).' : null;
      _erreurBareme =
          baremeValide ? null : 'Barème invalide (entier de 1 à 1000 ; ex. 10, 20, 40, 100).';
    });
    if (nom.isNotEmpty && coefficient != null && baremeValide) {
      Navigator.of(context).pop(_SaisieMatiere(nom, coefficient, bareme, _facultative));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existante == null ? 'Ajouter une matière au programme' : 'Modifier la matière',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('programme_nom'),
                controller: _nom,
                autofocus: true,
                decoration: champ('Nom de la matière', erreur: _erreurNom),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('programme_coefficient'),
                      controller: _coefficient,
                      decoration: champ('Coefficient', erreur: _erreurCoefficient),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const Key('programme_bareme'),
                      controller: _bareme,
                      decoration: champ(
                        'Note maximale',
                        aide: 'Barème : 10, 20...',
                        erreur: _erreurBareme,
                      ),
                      keyboardType: TextInputType.number,
                      onSubmitted: (_) => _valider(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                key: const Key('programme_facultative'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _facultative,
                onChanged: (v) => setState(() => _facultative = v ?? false),
                title: const Text('Matière facultative'),
                subtitle: const Text('Ne compte pas dans la moyenne générale.'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('programme_enregistrer'),
          onPressed: _valider,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _SaisieClasse {
  const _SaisieClasse(this.nom, this.niveauCode);

  final String nom;
  final int niveauCode;
}

class _DialogueClasse extends StatefulWidget {
  const _DialogueClasse({required this.cycle, this.serie});

  final Cycle cycle;
  final SerieLycee? serie;

  @override
  State<_DialogueClasse> createState() => _DialogueClasseState();
}

class _DialogueClasseState extends State<_DialogueClasse> {
  late final TextEditingController _nom;
  late int _niveauCode;
  String _nomPropose = '';
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _niveauCode = niveauxDuCycle(widget.cycle).first.code;
    _nom = TextEditingController();
    _proposerNom();
  }

  @override
  void dispose() {
    _nom.dispose();
    super.dispose();
  }

  /// Propose le nom du niveau tant que l'utilisateur n'a pas écrit le sien.
  void _proposerNom() {
    final n = niveauDeCode(_niveauCode);
    if (n == null) return;
    final nom = _nom.text.trim();
    if (nom.isEmpty || nom == _nomPropose) {
      _nomPropose = nomProposeDeClasse(n, widget.serie);
      _nom.text = _nomPropose;
      _nom.selection = TextSelection.collapsed(offset: _nom.text.length);
    }
  }

  void _valider() {
    final nom = _nom.text.trim();
    setState(() => _erreur = nom.isEmpty ? 'Le nom de la classe est obligatoire.' : null);
    if (nom.isEmpty) return;
    Navigator.of(context).pop(_SaisieClasse(nom, _niveauCode));
  }

  @override
  Widget build(BuildContext context) {
    final serie = widget.serie;
    return AlertDialog(
      title: Text(
        serie == null
            ? 'Ajouter une classe (${widget.cycle.libelle})'
            : 'Ajouter une classe (${serie.libelle})',
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChoixListe<int>(
              cleChamp: const Key('programme_niveau'),
              libelle: 'Niveau',
              valeur: _niveauCode,
              options: [for (final n in niveauxDuCycle(widget.cycle)) (n.code, n.libelle)],
              onChanged: (code) => setState(() {
                _niveauCode = code ?? _niveauCode;
                _proposerNom();
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('programme_nom_classe'),
              controller: _nom,
              decoration: champ('Nom de la classe', erreur: _erreur),
              onSubmitted: (_) => _valider(),
            ),
            const SizedBox(height: 12),
            const Text(
              'Les matières du programme seront ajoutées à la classe automatiquement.',
              style: TextStyle(color: CouleursGesco.gris),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('programme_creer_classe'),
          onPressed: _valider,
          child: const Text('Créer la classe'),
        ),
      ],
    );
  }
}
