import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/modeles_donnees.dart';
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
  });

  final List<ClasseResume> classes;
  final List<MatiereClasse> matieres;
  final int? selection;

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
    return _Donnees(classes: classes, matieres: matieres, selection: selection);
  }

  // ------------------------------------------------------------- Classes

  Future<void> _ajouterClasse() async {
    final anneeId = _etat.anneeId;
    if (anneeId == null) return;
    final saisie = await showDialog<_SaisieClasse>(
      context: context,
      builder: (ctx) => const _DialogueClasse(),
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

  Future<void> _modifierClasse(Classe classe) async {
    final saisie = await showDialog<_SaisieClasse>(
      context: context,
      builder: (ctx) => _DialogueClasse(existante: classe),
    );
    if (saisie == null || !mounted) return;
    final ok = await executer(
      context,
      () => _etat.services.classes.modifier(
        classe.id,
        nom: saisie.nom,
        niveau: saisie.niveau,
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

  Future<void> _ajouterMatiere(int classeId) async {
    final saisie = await showDialog<_SaisieMatiere>(
      context: context,
      builder: (ctx) => const _DialogueMatiere(),
    );
    if (saisie == null || !mounted) return;
    final ok = await executer(
      context,
      () async {
        await _etat.services.matieres.ajouter(
          classeId: classeId,
          nom: saisie.nom,
          coefficient: saisie.coefficient,
        );
      },
      succes: 'Matière « ${saisie.nom} » ajoutée.',
    );
    if (ok) _etat.donneesModifiees();
  }

  Future<void> _modifierMatiere(MatiereClasse matiere) async {
    final saisie = await showDialog<_SaisieMatiere>(
      context: context,
      builder: (ctx) => _DialogueMatiere(existante: matiere),
    );
    if (saisie == null || !mounted) return;
    final ok = await executer(
      context,
      () => _etat.services.matieres.modifier(
        matiere.id,
        nom: saisie.nom,
        coefficient: saisie.coefficient,
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
                onPressed: _ajouterClasse,
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
                          onTap: () => setState(() => _classeId = r.classe.id),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Actions',
                            onSelected: (action) {
                              if (action == 'modifier') _modifierClasse(r.classe);
                              if (action == 'supprimer') _supprimerClasse(r.classe);
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'modifier', child: Text('Modifier')),
                              PopupMenuItem(value: 'supprimer', child: Text('Supprimer')),
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
    morceaux.add('${r.nbEleves} élève${r.nbEleves > 1 ? 's' : ''}');
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
              onPressed: () => _ajouterMatiere(classe.classe.id),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une matière'),
            ),
            OutlinedButton.icon(
              onPressed: () => _copierDepuis(donnees),
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
                    subtitle: Text(
                      'Coefficient ${formaterCoefficient(matieres[i].coefficient)}',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Modifier',
                          onPressed: () => _modifierMatiere(matieres[i]),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Supprimer',
                          onPressed: () => _supprimerMatiere(matieres[i]),
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
  const _SaisieClasse(this.nom, this.niveau);

  final String nom;
  final String niveau;
}

class _DialogueClasse extends StatefulWidget {
  const _DialogueClasse({this.existante});

  final Classe? existante;

  @override
  State<_DialogueClasse> createState() => _DialogueClasseState();
}

class _DialogueClasseState extends State<_DialogueClasse> {
  late final TextEditingController _nom;
  late final TextEditingController _niveau;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _nom = TextEditingController(text: widget.existante?.nom ?? '');
    _niveau = TextEditingController(text: widget.existante?.niveau ?? '');
  }

  @override
  void dispose() {
    _nom.dispose();
    _niveau.dispose();
    super.dispose();
  }

  void _valider() {
    final nom = _nom.text.trim();
    if (nom.isEmpty) {
      setState(() => _erreur = 'Le nom de la classe est obligatoire.');
      return;
    }
    Navigator.of(context).pop(_SaisieClasse(nom, _niveau.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existante == null ? 'Ajouter une classe' : 'Modifier la classe'),
      content: SizedBox(
        width: 400,
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
              onSubmitted: (_) => _valider(),
            ),
          ],
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
  const _SaisieMatiere(this.nom, this.coefficient);

  final String nom;
  final int coefficient;
}

class _DialogueMatiere extends StatefulWidget {
  const _DialogueMatiere({this.existante});

  final MatiereClasse? existante;

  @override
  State<_DialogueMatiere> createState() => _DialogueMatiereState();
}

class _DialogueMatiereState extends State<_DialogueMatiere> {
  late final TextEditingController _nom;
  late final TextEditingController _coefficient;
  String? _erreurNom;
  String? _erreurCoefficient;

  @override
  void initState() {
    super.initState();
    final m = widget.existante;
    _nom = TextEditingController(text: m?.nom ?? '');
    _coefficient = TextEditingController(
      text: m == null ? '1' : formaterCoefficient(m.coefficient),
    );
  }

  @override
  void dispose() {
    _nom.dispose();
    _coefficient.dispose();
    super.dispose();
  }

  void _valider() {
    final nom = _nom.text.trim();
    final coefficient = analyserCoefficient(_coefficient.text);
    setState(() {
      _erreurNom = nom.isEmpty ? 'Le nom de la matière est obligatoire.' : null;
      _erreurCoefficient = coefficient == null
          ? 'Coefficient invalide (de 0,01 à 99,99 ; ex. 2 ou 2,5).'
          : null;
    });
    if (nom.isNotEmpty && coefficient != null) {
      Navigator.of(context).pop(_SaisieMatiere(nom, coefficient));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existante == null ? 'Ajouter une matière' : 'Modifier la matière'),
      content: SizedBox(
        width: 400,
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
            TextField(
              controller: _coefficient,
              decoration: champ('Coefficient', erreur: _erreurCoefficient),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onSubmitted: (_) => _valider(),
            ),
          ],
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
