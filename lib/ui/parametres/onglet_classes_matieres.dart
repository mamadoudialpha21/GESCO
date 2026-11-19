import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/depots/classe_depot.dart';
import '../../data/modeles_donnees.dart';
import '../../domain/permissions.dart';
import '../../domain/arrondi.dart';
import '../commun/chargeur.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../theme.dart';

class _Donnees {
  const _Donnees({
    required this.classes,
    required this.matieres,
    required this.selection,
    this.enseignants = const [],
  });

  final List<ClasseResume> classes;
  final List<MatiereClasse> matieres;
  final int? selection;

  /// Tous les enseignants (pour choisir le professeur principal et
  /// l'enseignant d'une matière).
  final List<Enseignant> enseignants;

  String nomEnseignant(int? id) {
    if (id == null) return '';
    for (final e in enseignants) {
      if (e.id == id) return e.nomComplet;
    }
    return '';
  }

  ClasseResume? get classeSelectionnee {
    for (final c in classes) {
      if (c.classe.id == selection) return c;
    }
    return null;
  }

  int get totalCoefficients =>
      matieres.fold(0, (somme, m) => somme + m.coefficient);
}

/// Classes de l'année affichée, et matières avec coefficients de chaque
/// classe. Chaque classe a sa propre liste, en nombre libre.
class OngletClassesMatieres extends StatefulWidget {
  const OngletClassesMatieres({super.key, required this.etat});

  final EtatApp etat;

  @override
  State<OngletClassesMatieres> createState() => _OngletClassesMatieresState();
}

class _OngletClassesMatieresState extends State<OngletClassesMatieres> {
  int? _classeId;

  EtatApp get _etat => widget.etat;

  Future<_Donnees> _charger() async {
    final anneeId = _etat.anneeId;
    if (anneeId == null) {
      return const _Donnees(classes: [], matieres: [], selection: null);
    }
    final classes = await _etat.services.classes.lister(anneeId);
    int? selection;
    if (classes.any((c) => c.classe.id == _classeId)) {
      selection = _classeId;
    } else if (classes.isNotEmpty) {
      selection = classes.first.classe.id;
    }
    final matieres = selection == null
        ? <MatiereClasse>[]
        : await _etat.services.matieres.lister(selection);
    final enseignants = [
      for (final r in await _etat.services.enseignants.lister()) r.enseignant,
    ];
    return _Donnees(
      classes: classes,
      matieres: matieres,
      selection: selection,
      enseignants: enseignants,
    );
  }

  // ------------------------------------------------------------- Classes

  Future<void> _ajouterClasse(_Donnees donnees) async {
    final anneeId = _etat.anneeId;
    if (anneeId == null) return;
    final saisie = await showDialog<_SaisieClasse>(
      context: context,
      builder: (ctx) => _DialogueClasse(enseignants: donnees.enseignants),
    );
    if (saisie == null || !mounted) return;
    Classe? creee;
    final ok = await executer(
      context,
      () async {
        creee = await _etat.services.classes.creer(
          anneeId: anneeId,
          nom: saisie.nom,
          niveau: saisie.niveau,
          reglages: ReglagesClasse(
            capacite: saisie.capacite,
            profPrincipalId: saisie.profPrincipalId,
          ),
        );
      },
      succes: 'Classe « ${saisie.nom} » créée.',
    );
    if (ok) {
      final nouvelle = creee;
      if (nouvelle != null) _classeId = nouvelle.id;
      _etat.donneesModifiees();
    }
  }

  Future<void> _modifierClasse(Classe classe, _Donnees donnees) async {
    final saisie = await showDialog<_SaisieClasse>(
      context: context,
      builder: (ctx) => _DialogueClasse(
        existante: classe,
        enseignants: donnees.enseignants,
      ),
    );
    if (saisie == null || !mounted) return;
    final ok = await executer(
      context,
      () => _etat.services.classes.modifier(
        classe.id,
        nom: saisie.nom,
        niveau: saisie.niveau,
        reglages: ReglagesClasse(
          capacite: saisie.capacite,
          profPrincipalId: saisie.profPrincipalId,
        ),
      ),
      succes: 'Classe modifiée.',
    );
    if (ok) _etat.donneesModifiees();
  }

  Future<void> _supprimerClasse(Classe classe) async {
    final oui = await confirmer(
      context,
      titre: 'Supprimer la classe',
      message:
          'Supprimer la classe « ${classe.nom} » et toutes ses matières ? '
          'Cette action est irréversible.',
      libelleConfirmer: 'Supprimer',
      danger: true,
    );
    if (!oui || !mounted) return;
    final ok = await executer(
      context,
      () => _etat.services.classes.supprimer(classe.id),
      succes: 'Classe supprimée.',
    );
    if (ok) _etat.donneesModifiees();
  }

  // ------------------------------------------------------------ Matières

  Future<void> _ajouterMatiere(int classeId, _Donnees donnees) async {
    // Le barème proposé est celui des paramètres de notation.
    final bareme = await _etat.services.parametres.baremeDefaut();
    if (!mounted) return;
    final saisie = await showDialog<_SaisieMatiere>(
      context: context,
      builder: (ctx) => _DialogueMatiere(
        enseignants: donnees.enseignants,
        baremeInitial: bareme,
      ),
    );
    if (saisie == null || !mounted) return;
    final ok = await executer(
      context,
      () async {
        await _etat.services.matieres.ajouter(
          classeId: classeId,
          nom: saisie.nom,
          coefficient: saisie.coefficient,
          bareme: saisie.bareme,
          facultative: saisie.facultative,
          enseignantId: saisie.enseignantId,
        );
      },
      succes: 'Matière « ${saisie.nom} » ajoutée.',
    );
    if (ok) _etat.donneesModifiees();
  }

  Future<void> _modifierMatiere(MatiereClasse matiere, _Donnees donnees) async {
    final saisie = await showDialog<_SaisieMatiere>(
      context: context,
      builder: (ctx) => _DialogueMatiere(
        existante: matiere,
        enseignants: donnees.enseignants,
      ),
    );
    if (saisie == null || !mounted) return;
    final ok = await executer(
      context,
      () => _etat.services.matieres.modifier(
        matiere.id,
        nom: saisie.nom,
        coefficient: saisie.coefficient,
        bareme: saisie.bareme,
        facultative: saisie.facultative,
        enseignantId: saisie.enseignantId,
        retirerEnseignant: saisie.enseignantId == null,
      ),
      succes: 'Matière modifiée. Les moyennes seront recalculées.',
    );
    if (ok) _etat.donneesModifiees();
  }

  Future<void> _supprimerMatiere(MatiereClasse matiere) async {
    final oui = await confirmer(
      context,
      titre: 'Supprimer la matière',
      message: 'Supprimer la matière « ${matiere.nom} » de cette classe ?',
      libelleConfirmer: 'Supprimer',
      danger: true,
    );
    if (!oui || !mounted) return;
    final ok = await executer(
      context,
      () => _etat.services.matieres.supprimer(matiere.id),
      succes: 'Matière supprimée.',
    );
    if (ok) _etat.donneesModifiees();
  }

  Future<void> _deplacer(List<MatiereClasse> liste, int index, int delta) async {
    final cible = index + delta;
    if (cible < 0 || cible >= liste.length) return;
    final ids = [for (final m in liste) m.id];
    final temporaire = ids[index];
    ids[index] = ids[cible];
    ids[cible] = temporaire;
    final ok = await executer(
      context,
      () => _etat.services.matieres.reordonner(liste[index].classeId, ids),
    );
    if (ok) _etat.donneesModifiees();
  }

  Future<void> _copierDepuis(_Donnees donnees) async {
    final cible = donnees.classeSelectionnee;
    if (cible == null) return;
    final autres = [
      for (final c in donnees.classes)
        if (c.classe.id != cible.classe.id) c,
    ];
    if (autres.isEmpty) {
      afficherMessage(context, 'Il n\'y a pas d\'autre classe à copier.', erreur: true);
      return;
    }
    final sourceId = await showDialog<int>(
      context: context,
      builder: (ctx) => _DialogueCopie(sources: autres),
    );
    if (sourceId == null || !mounted) return;
    var ajoutees = 0;
    final ok = await executer(
      context,
      () async {
        ajoutees = await _etat.services.matieres.copier(
          depuisClasseId: sourceId,
          versClasseId: cible.classe.id,
        );
      },
    );
    if (!mounted) return;
    if (ok) {
      afficherMessage(
        context,
        ajoutees == 0
            ? 'Aucune matière ajoutée : elles existent déjà dans cette classe.'
            : '$ajoutees matière${ajoutees > 1 ? 's' : ''} copiée${ajoutees > 1 ? 's' : ''}.',
      );
      _etat.donneesModifiees();
    }
  }

  // --------------------------------------------------------- Construction

  @override
  Widget build(BuildContext context) {
    if (_etat.anneeId == null) {
      return const MessageVide(
        'Créez d\'abord une année scolaire (onglet « Années scolaires »).',
        icone: Icons.event_outlined,
      );
    }
    return Chargeur<_Donnees>(
      cle: (_etat.anneeId, _etat.version, _classeId),
      charger: _charger,
      builder: (context, donnees) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 340, child: _panneauClasses(donnees)),
            const VerticalDivider(width: 1),
            Expanded(child: _panneauMatieres(donnees)),
          ],
        );
      },
    );
  }

  Widget _panneauClasses(_Donnees donnees) {
    final annee = _etat.anneeCourante;
    final gerer = _etat.peut(Permission.classesGerer);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TitreSection(
                  'Classes',
                  sousTitre: annee == null ? null : 'Année ${annee.libelle}',
                ),
              ),
              FilledButton.icon(
                onPressed: gerer ? () => _ajouterClasse(donnees) : null,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter'),
              ),
            ],
          ),
        ),
        Expanded(
          child: donnees.classes.isEmpty
              ? const MessageVide(
                  'Aucune classe pour cette année.\nAjoutez-en une pour commencer.',
                  icone: Icons.class_outlined,
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final r in donnees.classes)
                      Carte(
                        margin: const EdgeInsets.only(bottom: 8),
                        couleur: r.classe.id == donnees.selection
                            ? CouleursGesco.bleuClair
                            : Colors.white,
                        bordure: r.classe.id == donnees.selection
                            ? CouleursGesco.bleu
                            : CouleursGesco.bordure,
                        child: ListTile(
                          selected: r.classe.id == donnees.selection,
                          title: Text(
                            r.classe.nom,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(_sousTitreClasse(r)),
                          isThreeLine: true,
                          onTap: () => setState(() => _classeId = r.classe.id),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Actions',
                            onSelected: (action) {
                              if (action == 'modifier') {
                                _modifierClasse(r.classe, donnees);
                              }
                              if (action == 'supprimer') _supprimerClasse(r.classe);
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'modifier',
                                enabled: gerer,
                                child: const Text('Modifier'),
                              ),
                              PopupMenuItem(
                                value: 'supprimer',
                                enabled: gerer,
                                child: const Text('Supprimer'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  String _sousTitreClasse(ClasseResume r) {
    final morceaux = <String>[];
    if (r.classe.niveau.isNotEmpty) morceaux.add(r.classe.niveau);
    morceaux.add('${r.nbMatieres} matière${r.nbMatieres > 1 ? 's' : ''}');
    final partis = r.nbEleves - r.nbActifs;
    var eleves = '${r.nbActifs} élève${r.nbActifs > 1 ? 's' : ''}'
        ' (${r.nbFilles} F / ${r.nbGarcons} G)';
    final capacite = r.classe.capacite;
    if (capacite != null) eleves += ' sur $capacite';
    if (partis > 0) eleves += ', $partis parti${partis > 1 ? 's' : ''}';
    morceaux.add(eleves);
    final ligne2 = r.profPrincipalNom.isEmpty
        ? 'Pas de professeur principal'
        : 'Prof. principal : ${r.profPrincipalNom}';
    return '${morceaux.join(' · ')}\n$ligne2';
  }

  String _sousTitreMatiere(MatiereClasse m, _Donnees donnees) {
    final morceaux = <String>[
      'Coefficient ${formaterCoefficient(m.coefficient)}',
      'sur ${m.bareme}',
      if (m.facultative) 'facultative (hors moyenne générale)',
      if (m.enseignantId != null && donnees.nomEnseignant(m.enseignantId).isNotEmpty)
        donnees.nomEnseignant(m.enseignantId),
    ];
    return morceaux.join(' · ');
  }

  Widget _panneauMatieres(_Donnees donnees) {
    final classe = donnees.classeSelectionnee;
    if (classe == null) {
      return const MessageVide(
        'Sélectionnez ou créez une classe pour définir ses matières.',
        icone: Icons.menu_book_outlined,
      );
    }
    final matieres = donnees.matieres;
    final gerer = _etat.peut(Permission.classesGerer);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: TitreSection(
                'Matières de ${classe.classe.nom}',
                sousTitre:
                    'Chaque classe a ses propres matières et coefficients. '
                    'Modifier un coefficient ne change jamais les notes saisies.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: gerer ? () => _ajouterMatiere(classe.classe.id, donnees) : null,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une matière'),
            ),
            OutlinedButton.icon(
              onPressed: gerer ? () => _copierDepuis(donnees) : null,
              icon: const Icon(Icons.copy_all),
              label: const Text('Copier depuis une autre classe…'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (matieres.isEmpty)
          const SizedBox(
            height: 220,
            child: MessageVide(
              'Aucune matière dans cette classe.',
              icone: Icons.menu_book_outlined,
            ),
          )
        else
          Carte(
            child: Column(
              children: [
                for (var i = 0; i < matieres.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: i == 0 ? null : () => _deplacer(matieres, i, -1),
                          child: Icon(
                            Icons.keyboard_arrow_up,
                            size: 20,
                            color: i == 0 ? Colors.black26 : CouleursGesco.gris,
                          ),
                        ),
                        InkWell(
                          onTap: i == matieres.length - 1
                              ? null
                              : () => _deplacer(matieres, i, 1),
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            size: 20,
                            color: i == matieres.length - 1
                                ? Colors.black26
                                : CouleursGesco.gris,
                          ),
                        ),
                      ],
                    ),
                    title: Text(matieres[i].nom),
                    subtitle: Text(_sousTitreMatiere(matieres[i], donnees)),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Modifier',
                          onPressed: gerer ? () => _modifierMatiere(matieres[i], donnees) : null,
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Supprimer',
                          onPressed: gerer ? () => _supprimerMatiere(matieres[i]) : null,
                          icon: const Icon(
                            Icons.delete_outline,
                            color: CouleursGesco.rouge,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Total des coefficients',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Etiquette(
                        formaterCoefficient(donnees.totalCoefficients),
                        couleur: CouleursGesco.bleu,
                        fond: CouleursGesco.bleuClair,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Dialogues

class _SaisieClasse {
  const _SaisieClasse(this.nom, this.niveau, this.capacite, this.profPrincipalId);

  final String nom;
  final String niveau;
  final int? capacite;
  final int? profPrincipalId;
}

/// Liste déroulante d'enseignants, avec une première entrée « aucun ».
class _ChoixEnseignant extends StatelessWidget {
  const _ChoixEnseignant({
    required this.libelle,
    required this.enseignants,
    required this.valeur,
    required this.onChanged,
    required this.aucun,
  });

  final String libelle;
  final List<Enseignant> enseignants;
  final int? valeur;
  final ValueChanged<int?> onChanged;
  final String aucun;

  @override
  Widget build(BuildContext context) {
    // Un enseignant devenu inactif reste proposé tant qu'il est choisi.
    final proposes = [
      for (final e in enseignants)
        if (e.actif || e.id == valeur) e,
    ];
    final existe = proposes.any((e) => e.id == valeur);
    return InputDecorator(
      decoration: champ(libelle),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          isExpanded: true,
          isDense: true,
          value: existe ? valeur : null,
          items: [
            DropdownMenuItem<int?>(value: null, child: Text(aucun)),
            for (final e in proposes)
              DropdownMenuItem<int?>(
                value: e.id,
                child: Text(e.actif ? e.nomComplet : '${e.nomComplet} (inactif)'),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DialogueClasse extends StatefulWidget {
  const _DialogueClasse({this.existante, this.enseignants = const []});

  final Classe? existante;
  final List<Enseignant> enseignants;

  @override
  State<_DialogueClasse> createState() => _DialogueClasseState();
}

class _DialogueClasseState extends State<_DialogueClasse> {
  late final TextEditingController _nom;
  late final TextEditingController _niveau;
  late final TextEditingController _capacite;
  int? _profPrincipalId;
  String? _erreur;
  String? _erreurCapacite;

  @override
  void initState() {
    super.initState();
    _nom = TextEditingController(text: widget.existante?.nom ?? '');
    _niveau = TextEditingController(text: widget.existante?.niveau ?? '');
    final capacite = widget.existante?.capacite;
    _capacite = TextEditingController(text: capacite == null ? '' : '$capacite');
    _profPrincipalId = widget.existante?.profPrincipalId;
  }

  @override
  void dispose() {
    _nom.dispose();
    _niveau.dispose();
    _capacite.dispose();
    super.dispose();
  }

  void _valider() {
    final nom = _nom.text.trim();
    final texteCapacite = _capacite.text.trim();
    int? capacite;
    String? erreurCapacite;
    if (texteCapacite.isNotEmpty) {
      capacite = int.tryParse(texteCapacite);
      if (capacite == null || capacite < 1 || capacite > ClasseDepot.capaciteMax) {
        erreurCapacite =
            'Entier de 1 à ${ClasseDepot.capaciteMax} (ou laissez vide).';
      }
    }
    setState(() {
      _erreur = nom.isEmpty ? 'Le nom de la classe est obligatoire.' : null;
      _erreurCapacite = erreurCapacite;
    });
    if (nom.isEmpty || erreurCapacite != null) return;
    Navigator.of(context).pop(
      _SaisieClasse(nom, _niveau.text.trim(), capacite, _profPrincipalId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existante == null ? 'Ajouter une classe' : 'Modifier la classe'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nom,
                autofocus: true,
                decoration: champ('Nom de la classe', aide: 'Exemple : 10e A', erreur: _erreur),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _niveau,
                decoration: champ('Niveau d\'études (facultatif)', aide: 'Exemple : 10e année'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _capacite,
                decoration: champ(
                  'Capacité (facultatif)',
                  aide: 'Nombre maximal d\'élèves ; vide = non limitée',
                  erreur: _erreurCapacite,
                ),
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _valider(),
              ),
              const SizedBox(height: 16),
              _ChoixEnseignant(
                libelle: 'Professeur principal',
                enseignants: widget.enseignants,
                valeur: _profPrincipalId,
                aucun: 'Aucun',
                onChanged: (id) => setState(() => _profPrincipalId = id),
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
        FilledButton(onPressed: _valider, child: const Text('Enregistrer')),
      ],
    );
  }
}

class _SaisieMatiere {
  const _SaisieMatiere(
    this.nom,
    this.coefficient,
    this.bareme,
    this.facultative,
    this.enseignantId,
  );

  final String nom;
  final int coefficient;
  final int bareme;
  final bool facultative;
  final int? enseignantId;
}

class _DialogueMatiere extends StatefulWidget {
  const _DialogueMatiere({
    this.existante,
    this.enseignants = const [],
    this.baremeInitial = 20,
  });

  final MatiereClasse? existante;
  final List<Enseignant> enseignants;

  /// Barème proposé pour une nouvelle matière.
  final int baremeInitial;

  @override
  State<_DialogueMatiere> createState() => _DialogueMatiereState();
}

class _DialogueMatiereState extends State<_DialogueMatiere> {
  late final TextEditingController _nom;
  late final TextEditingController _coefficient;
  late final TextEditingController _bareme;
  bool _facultative = false;
  int? _enseignantId;
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
    _bareme = TextEditingController(text: '${m?.bareme ?? widget.baremeInitial}');
    _facultative = m?.facultative ?? false;
    _enseignantId = m?.enseignantId;
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
      _erreurCoefficient = coefficient == null
          ? 'Coefficient invalide (de 0,01 à 99,99 ; ex. 2 ou 2,5).'
          : null;
      _erreurBareme =
          baremeValide ? null : 'Barème invalide (entier de 1 à 1000 ; ex. 10, 20, 40, 100).';
    });
    if (nom.isNotEmpty && coefficient != null && baremeValide) {
      Navigator.of(context).pop(
        _SaisieMatiere(nom, coefficient, bareme, _facultative, _enseignantId),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existante == null ? 'Ajouter une matière' : 'Modifier la matière'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
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
                      controller: _coefficient,
                      decoration: champ('Coefficient', erreur: _erreurCoefficient),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
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
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _facultative,
                onChanged: (v) => setState(() => _facultative = v ?? false),
                title: const Text('Matière facultative'),
                subtitle: const Text('Ne compte pas dans la moyenne générale.'),
              ),
              const SizedBox(height: 8),
              _ChoixEnseignant(
                libelle: 'Enseignant',
                enseignants: widget.enseignants,
                valeur: _enseignantId,
                aucun: 'Aucun enseignant',
                onChanged: (id) => setState(() => _enseignantId = id),
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
        FilledButton(onPressed: _valider, child: const Text('Enregistrer')),
      ],
    );
  }
}

class _DialogueCopie extends StatefulWidget {
  const _DialogueCopie({required this.sources});

  final List<ClasseResume> sources;

  @override
  State<_DialogueCopie> createState() => _DialogueCopieState();
}

class _DialogueCopieState extends State<_DialogueCopie> {
  late int _choix = widget.sources.first.classe.id;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Copier les matières d\'une autre classe'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Les matières absentes de cette classe sont ajoutées avec leurs '
              'coefficients. Celles qui existent déjà ne sont pas modifiées.',
            ),
            const SizedBox(height: 12),
            DropdownButton<int>(
              isExpanded: true,
              value: _choix,
              items: [
                for (final r in widget.sources)
                  DropdownMenuItem<int>(
                    value: r.classe.id,
                    child: Text('${r.classe.nom} (${r.nbMatieres} matières)'),
                  ),
              ],
              onChanged: (id) {
                if (id != null) setState(() => _choix = id);
              },
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
          onPressed: () => Navigator.of(context).pop(_choix),
          child: const Text('Copier'),
        ),
      ],
    );
  }
}
