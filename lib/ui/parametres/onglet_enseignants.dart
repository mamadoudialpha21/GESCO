import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/modeles_donnees.dart';
import '../../domain/permissions.dart';
import '../../domain/recherche.dart';
import '../commun/chargeur.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../commun/selecteur_image.dart';
import '../theme.dart';

/// Enseignants : fiche, matières enseignées et classes confiées.
///
/// Les matières se confient dans « Classes et matières » ; les classes
/// confiées (sans matière précise) se choisissent ici.
class OngletEnseignants extends StatefulWidget {
  const OngletEnseignants({super.key, required this.etat});

  final EtatApp etat;

  @override
  State<OngletEnseignants> createState() => _OngletEnseignantsState();
}

class _OngletEnseignantsState extends State<OngletEnseignants> {
  final TextEditingController _recherche = TextEditingController();
  bool _inactifs = true;

  EtatApp get etat => widget.etat;

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _creer() async {
    final fiche = await showDialog<Enseignant>(
      context: context,
      builder: (ctx) => const _DialogueEnseignant(),
    );
    if (fiche == null || !mounted) return;
    final ok = await executer(
      context,
      () async {
        await etat.services.enseignants.creer(fiche);
      },
      succes: 'Enseignant « ${fiche.nomComplet} » ajouté.',
    );
    if (ok) etat.donneesModifiees();
  }

  Future<void> _modifier(Enseignant e) async {
    // La liste ne charge pas la signature de chaque fiche : on relit la fiche.
    final complet = await etat.services.enseignants.obtenir(e.id);
    if (!mounted) return;
    if (complet == null) {
      afficherMessage(context, 'Enseignant introuvable.', erreur: true);
      etat.donneesModifiees();
      return;
    }
    final fiche = await showDialog<Enseignant>(
      context: context,
      builder: (ctx) => _DialogueEnseignant(enseignant: complet),
    );
    if (fiche == null || !mounted) return;
    final ok = await executer(
      context,
      () => etat.services.enseignants.modifier(fiche),
      succes: 'Fiche de « ${fiche.nomComplet} » enregistrée.',
    );
    if (ok) etat.donneesModifiees();
  }

  Future<void> _basculerActif(Enseignant e) async {
    final complet = await etat.services.enseignants.obtenir(e.id);
    if (!mounted || complet == null) return;
    final ok = await executer(
      context,
      () => etat.services.enseignants.modifier(complet.copyWith(actif: !complet.actif)),
      succes: complet.actif
          ? '${complet.nomComplet} est désactivé : il n\'apparaît plus pour de nouvelles affectations.'
          : '${complet.nomComplet} est réactivé.',
    );
    if (ok) etat.donneesModifiees();
  }

  Future<void> _supprimer(Enseignant e) async {
    final oui = await confirmer(
      context,
      titre: 'Supprimer l\'enseignant',
      message: 'Supprimer définitivement ${e.nomComplet} ? Cette action est '
          'refusée tant qu\'il a des matières, des classes ou un compte : '
          'désactivez-le plutôt.',
      libelleConfirmer: 'Supprimer',
      danger: true,
    );
    if (!oui || !mounted) return;
    final ok = await executer(
      context,
      () => etat.services.enseignants.supprimer(e.id),
      succes: 'Enseignant supprimé.',
    );
    if (ok) etat.donneesModifiees();
  }

  Future<void> _affectations(Enseignant e) async {
    final anneeId = etat.anneeId;
    if (anneeId == null) {
      afficherMessage(context, 'Créez d\'abord une année scolaire.', erreur: true);
      return;
    }
    final gerer = etat.peut(Permission.enseignantsGerer);
    final modifie = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DialogueAffectations(
        etat: etat,
        enseignant: e,
        anneeId: anneeId,
        anneeLibelle: etat.anneeCourante?.libelle ?? '',
        modifiable: gerer,
      ),
    );
    if (modifie == true) etat.donneesModifiees();
  }

  @override
  Widget build(BuildContext context) {
    if (!etat.peut(Permission.enseignantsVoir)) {
      return const MessageVide(
        'Vous n\'avez pas l\'autorisation de consulter les enseignants.',
        icone: Icons.lock_outline,
      );
    }
    final gerer = etat.peut(Permission.enseignantsGerer);
    return Chargeur<List<EnseignantResume>>(
      cle: (etat.version, etat.anneeId),
      charger: () => etat.services.enseignants.lister(anneeId: etat.anneeId),
      builder: (context, liste) {
        final affiches = [
          for (final r in liste)
            if ((_inactifs || r.enseignant.actif) &&
                correspondRecherche(_recherche.text, [
                  r.enseignant.nom,
                  r.enseignant.prenom,
                  r.enseignant.matricule,
                  r.enseignant.specialite,
                ]))
              r,
        ];
        final annee = etat.anneeCourante?.libelle;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TitreSection(
                    'Enseignants',
                    sousTitre: annee == null
                        ? 'Fiche de chaque enseignant, matières enseignées et classes confiées.'
                        : 'Fiche de chaque enseignant. Les nombres de matières et de '
                            'classes concernent l\'année $annee.',
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  key: const Key('bouton_nouvel_enseignant'),
                  onPressed: gerer ? _creer : null,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Nouvel enseignant'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('recherche_enseignant'),
                    controller: _recherche,
                    decoration: champ('Rechercher (nom, matricule, spécialité)'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 16),
                FilterChip(
                  label: const Text('Afficher les inactifs'),
                  selected: _inactifs,
                  onSelected: (v) => setState(() => _inactifs = v),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (liste.isEmpty)
              const SizedBox(
                height: 240,
                child: MessageVide(
                  'Aucun enseignant enregistré.',
                  icone: Icons.badge_outlined,
                ),
              )
            else if (affiches.isEmpty)
              const SizedBox(
                height: 160,
                child: MessageVide('Aucun enseignant ne correspond.', icone: Icons.search_off),
              ),
            for (final r in affiches)
              Carte(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  key: Key('enseignant_${r.enseignant.id}'),
                  leading: CircleAvatar(
                    backgroundColor: r.enseignant.actif
                        ? CouleursGesco.bleuClair
                        : CouleursGesco.grisClair,
                    child: Text(
                      _initiales(r.enseignant),
                      style: TextStyle(
                        color: r.enseignant.actif ? CouleursGesco.bleu : CouleursGesco.gris,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          r.enseignant.nomComplet,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                      ),
                      if (!r.enseignant.actif) ...[
                        const SizedBox(width: 12),
                        const Etiquette(
                          'Inactif',
                          couleur: CouleursGesco.gris,
                          fond: CouleursGesco.grisClair,
                        ),
                      ],
                      if (!r.enseignant.peutSaisir) ...[
                        const SizedBox(width: 8),
                        const Etiquette(
                          'Sans saisie de notes',
                          couleur: CouleursGesco.orange,
                          fond: CouleursGesco.orangeClair,
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(_resume(r)),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Matières et classes',
                        onPressed: () => _affectations(r.enseignant),
                        icon: const Icon(Icons.account_tree_outlined),
                      ),
                      IconButton(
                        tooltip: 'Modifier la fiche',
                        onPressed: gerer ? () => _modifier(r.enseignant) : null,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: r.enseignant.actif ? 'Désactiver' : 'Réactiver',
                        onPressed: gerer ? () => _basculerActif(r.enseignant) : null,
                        icon: Icon(
                          r.enseignant.actif
                              ? Icons.person_off_outlined
                              : Icons.person_outline,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Supprimer',
                        onPressed: gerer ? () => _supprimer(r.enseignant) : null,
                        icon: const Icon(Icons.delete_outline, color: CouleursGesco.rouge),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static String _initiales(Enseignant e) {
    String premiere(String s) => s.trim().isEmpty ? '' : s.trim().substring(0, 1).toUpperCase();
    final i = '${premiere(e.nom)}${premiere(e.prenom)}';
    return i.isEmpty ? '?' : i;
  }

  static String _resume(EnseignantResume r) {
    final e = r.enseignant;
    final morceaux = <String>[
      if (e.specialite.isNotEmpty) e.specialite,
      if (e.matricule.isNotEmpty) 'Matricule ${e.matricule}',
      if (e.telephone.isNotEmpty) e.telephone,
      '${r.nbMatieres} ${r.nbMatieres > 1 ? 'matières' : 'matière'}',
      '${r.nbClasses} ${r.nbClasses > 1 ? 'classes' : 'classe'}',
    ];
    return morceaux.join(' · ');
  }
}

/// Création ou modification de la fiche d'un enseignant.
class _DialogueEnseignant extends StatefulWidget {
  const _DialogueEnseignant({this.enseignant});

  final Enseignant? enseignant;

  @override
  State<_DialogueEnseignant> createState() => _DialogueEnseignantState();
}

class _DialogueEnseignantState extends State<_DialogueEnseignant> {
  late final TextEditingController _matricule;
  late final TextEditingController _nom;
  late final TextEditingController _prenom;
  late final TextEditingController _telephone;
  late final TextEditingController _email;
  late final TextEditingController _specialite;
  String? _sexe;
  late bool _actif;
  late bool _peutSaisir;
  Uint8List? _signature;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    final e = widget.enseignant;
    _matricule = TextEditingController(text: e?.matricule ?? '');
    _nom = TextEditingController(text: e?.nom ?? '');
    _prenom = TextEditingController(text: e?.prenom ?? '');
    _telephone = TextEditingController(text: e?.telephone ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _specialite = TextEditingController(text: e?.specialite ?? '');
    _sexe = e?.sexe;
    _actif = e?.actif ?? true;
    _peutSaisir = e?.peutSaisir ?? true;
    _signature = e?.signature;
  }

  @override
  void dispose() {
    _matricule.dispose();
    _nom.dispose();
    _prenom.dispose();
    _telephone.dispose();
    _email.dispose();
    _specialite.dispose();
    super.dispose();
  }

  Future<void> _choisirSignature() async {
    final image = await choisirImage(context, 'La signature');
    if (image != null && mounted) setState(() => _signature = image);
  }

  void _valider() {
    if (_nom.text.trim().isEmpty || _prenom.text.trim().isEmpty) {
      setState(() => _erreur = 'Le nom et le prénom sont obligatoires.');
      return;
    }
    Navigator.of(context).pop(
      Enseignant(
        id: widget.enseignant?.id ?? 0,
        matricule: _matricule.text.trim(),
        nom: _nom.text.trim(),
        prenom: _prenom.text.trim(),
        sexe: _sexe,
        telephone: _telephone.text.trim(),
        email: _email.text.trim(),
        specialite: _specialite.text.trim(),
        actif: _actif,
        peutSaisir: _peutSaisir,
        signature: _signature,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final creation = widget.enseignant == null;
    return AlertDialog(
      title: Text(creation ? 'Nouvel enseignant' : 'Modifier l\'enseignant'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('enseignant_nom'),
                      controller: _nom,
                      autofocus: true,
                      decoration: champ('Nom'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const Key('enseignant_prenom'),
                      controller: _prenom,
                      decoration: champ('Prénom'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('enseignant_matricule'),
                      controller: _matricule,
                      decoration: champ('Matricule', aide: 'Facultatif, unique'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InputDecorator(
                      decoration: champ('Sexe'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          key: const Key('enseignant_sexe'),
                          isExpanded: true,
                          isDense: true,
                          value: _sexe,
                          items: const [
                            DropdownMenuItem<String?>(value: null, child: Text('Non précisé')),
                            DropdownMenuItem<String?>(value: 'M', child: Text('Masculin')),
                            DropdownMenuItem<String?>(value: 'F', child: Text('Féminin')),
                          ],
                          onChanged: (v) => setState(() => _sexe = v),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('enseignant_specialite'),
                controller: _specialite,
                decoration: champ('Spécialité', aide: 'Exemple : Mathématiques'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('enseignant_telephone'),
                      controller: _telephone,
                      keyboardType: TextInputType.phone,
                      decoration: champ('Téléphone'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const Key('enseignant_email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: champ('E-mail'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('enseignant_actif'),
                contentPadding: EdgeInsets.zero,
                value: _actif,
                onChanged: (v) => setState(() => _actif = v),
                title: const Text('Enseignant actif'),
                subtitle: const Text('Un enseignant inactif n\'est plus proposé pour de nouvelles affectations.'),
              ),
              SwitchListTile(
                key: const Key('enseignant_peut_saisir'),
                contentPadding: EdgeInsets.zero,
                value: _peutSaisir,
                onChanged: (v) => setState(() => _peutSaisir = v),
                title: const Text('Autorisé à saisir des notes'),
              ),
              const SizedBox(height: 8),
              SelecteurImage(
                titre: 'Signature',
                image: _signature,
                onChoisir: _choisirSignature,
                onRetirer: () => setState(() => _signature = null),
              ),
              if (_erreur != null) ...[
                const SizedBox(height: 12),
                Text(_erreur!, style: const TextStyle(color: CouleursGesco.rouge)),
              ],
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
          key: const Key('bouton_valider_enseignant'),
          onPressed: _valider,
          child: Text(creation ? 'Ajouter' : 'Enregistrer'),
        ),
      ],
    );
  }
}

/// Matières enseignées et classes confiées à un enseignant pour une année.
class _DialogueAffectations extends StatefulWidget {
  const _DialogueAffectations({
    required this.etat,
    required this.enseignant,
    required this.anneeId,
    required this.anneeLibelle,
    required this.modifiable,
  });

  final EtatApp etat;
  final Enseignant enseignant;
  final int anneeId;
  final String anneeLibelle;
  final bool modifiable;

  @override
  State<_DialogueAffectations> createState() => _DialogueAffectationsState();
}

class _DonneesAffectations {
  const _DonneesAffectations({
    required this.matieres,
    required this.classes,
    required this.confiees,
  });

  final List<AffectationMatiere> matieres;
  final List<ClasseResume> classes;
  final Set<int> confiees;
}

class _DialogueAffectationsState extends State<_DialogueAffectations> {
  Set<int>? _choix;
  late final Future<_DonneesAffectations> _futur = _charger();

  Future<_DonneesAffectations> _charger() async {
    final services = widget.etat.services;
    final matieres = await services.enseignants.matieres(
      widget.enseignant.id,
      anneeId: widget.anneeId,
    );
    final classes = await services.classes.lister(widget.anneeId);
    final confiees = await services.enseignants.classesConfiees(
      widget.enseignant.id,
      widget.anneeId,
    );
    return _DonneesAffectations(matieres: matieres, classes: classes, confiees: confiees);
  }

  Future<void> _enregistrer() async {
    final choix = _choix;
    if (choix == null) {
      Navigator.of(context).pop(false);
      return;
    }
    final ok = await executer(
      context,
      () => widget.etat.services.enseignants.definirClassesConfiees(
        widget.enseignant.id,
        widget.anneeId,
        choix,
      ),
      succes: 'Classes confiées enregistrées.',
    );
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.enseignant.nomComplet} — ${widget.anneeLibelle}'),
      content: SizedBox(
        width: 520,
        height: 440,
        child: FutureBuilder<_DonneesAffectations>(
          future: _futur,
          builder: (context, instantane) {
            if (instantane.hasError) {
              return SelectableText(
                'Erreur de chargement : ${instantane.error}',
                style: const TextStyle(color: CouleursGesco.rouge),
              );
            }
            final d = instantane.data;
            if (d == null) return const Center(child: CircularProgressIndicator());
            final choix = _choix ??= {...d.confiees};
            return ListView(
              children: [
                Text('Matières enseignées', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                if (d.matieres.isEmpty)
                  const Text(
                    'Aucune matière. On confie une matière à un enseignant dans '
                    '« Classes et matières ».',
                    style: TextStyle(color: CouleursGesco.gris),
                  )
                else
                  for (final m in d.matieres)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('${m.matiereNom} — ${m.classeNom}'),
                    ),
                const SizedBox(height: 16),
                Text('Classes confiées', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text(
                  'Classes qui lui sont rattachées sans matière précise.',
                  style: TextStyle(color: CouleursGesco.gris),
                ),
                if (d.classes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Aucune classe dans cette année scolaire.'),
                  ),
                for (final c in d.classes)
                  CheckboxListTile(
                    key: Key('classe_confiee_${c.classe.id}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: choix.contains(c.classe.id),
                    onChanged: widget.modifiable
                        ? (v) => setState(() {
                              if (v ?? false) {
                                choix.add(c.classe.id);
                              } else {
                                choix.remove(c.classe.id);
                              }
                            })
                        : null,
                    title: Text(c.classe.nom),
                    subtitle: c.classe.profPrincipalId == widget.enseignant.id
                        ? const Text('Professeur principal')
                        : null,
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(widget.modifiable ? 'Annuler' : 'Fermer'),
        ),
        if (widget.modifiable)
          FilledButton(
            key: const Key('bouton_valider_classes_confiees'),
            onPressed: _enregistrer,
            child: const Text('Enregistrer'),
          ),
      ],
    );
  }
}
