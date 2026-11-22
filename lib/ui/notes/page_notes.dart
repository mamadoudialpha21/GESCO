import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/depots/note_depot.dart';
import '../../data/modeles_donnees.dart';
import '../../domain/calendrier.dart';
import '../../domain/periodes.dart';
import '../../domain/permissions.dart';
import '../../domain/modeles.dart';
import '../commun/chargeur.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../theme.dart';
import 'choix_classe.dart';
import 'dialogue_fiche_notes.dart';
import '../evaluations/vue_evaluations.dart';
import 'grille_notes.dart';
import 'historique_notes.dart';
import 'periode.dart';

class _DonneesNotes {
  const _DonneesNotes({
    this.classes = const [],
    this.classe,
    this.matieres = const [],
    this.eleves = const [],
    this.saisies = const {},
    this.casesEvaluees = const {},
    this.moisVerrouilles = const {},
    this.config = ConfigResultats.defaut,
    this.calendrier = Calendrier.defaut,
  });

  final List<ClasseResume> classes;
  final ClasseResume? classe;
  final List<MatiereClasse> matieres;
  final List<EleveInscrit> eleves;
  final SaisiesClasse saisies;

  /// (matière, mois) dont la note du mois est calculée d'après les évaluations.
  final Set<(int, int)> casesEvaluees;
  final Set<int> moisVerrouilles;
  final ConfigResultats config;
  final Calendrier calendrier;
}

enum _Vue { saisie, evaluations, historique }

/// Page Notes : saisie mensuelle, évaluations et historique des notes. La
/// classe choisie est conservée quand on change de vue.
class PageNotes extends StatefulWidget {
  const PageNotes({
    super.key,
    required this.etat,
    required this.allerAuxParametres,
    required this.allerAuxInscriptions,
    this.maintenant,
  });

  final EtatApp etat;
  final VoidCallback allerAuxParametres;
  final VoidCallback allerAuxInscriptions;

  /// Horloge (pour les tests) : détermine le mois proposé au départ.
  final DateTime Function()? maintenant;

  @override
  State<PageNotes> createState() => _PageNotesState();
}

class _PageNotesState extends State<PageNotes> {
  _Vue _vue = _Vue.saisie;
  int? _classeId;

  void _choisirClasse(int id) => setState(() => _classeId = id);

  @override
  Widget build(BuildContext context) {
    final etat = widget.etat;
    final historique = etat.peut(Permission.journalVoir);
    // Une vue n'est plus accessible si les droits ont changé.
    final vue = _vue == _Vue.historique && !historique ? _Vue.saisie : _vue;
    final Widget contenu = switch (vue) {
      _Vue.saisie => VueSaisie(
          etat: etat,
          classeId: _classeId,
          surClasse: _choisirClasse,
          allerAuxParametres: widget.allerAuxParametres,
          allerAuxInscriptions: widget.allerAuxInscriptions,
          maintenant: widget.maintenant,
        ),
      _Vue.evaluations => VueEvaluations(
          etat: etat,
          classeId: _classeId,
          surClasse: _choisirClasse,
          allerAuxParametres: widget.allerAuxParametres,
          maintenant: widget.maintenant,
        ),
      _Vue.historique => VueHistorique(
          etat: etat,
          classeId: _classeId,
          surClasse: _choisirClasse,
        ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_Vue>(
              showSelectedIcon: false,
              segments: [
                const ButtonSegment(
                  value: _Vue.saisie,
                  icon: Icon(Icons.grid_on, size: 18),
                  label: Text('Notes du mois', key: Key('vue_saisie')),
                ),
                const ButtonSegment(
                  value: _Vue.evaluations,
                  icon: Icon(Icons.assignment_outlined, size: 18),
                  label: Text('Évaluations', key: Key('vue_evaluations')),
                ),
                if (historique)
                  const ButtonSegment(
                    value: _Vue.historique,
                    icon: Icon(Icons.history, size: 18),
                    label: Text('Historique', key: Key('vue_historique')),
                  ),
              ],
              selected: {vue},
              onSelectionChanged: (choix) => setState(() => _vue = choix.first),
            ),
          ),
        ),
        Expanded(child: contenu),
      ],
    );
  }
}

/// Saisie des notes du mois : choix de la classe et de la période, puis
/// tableau élèves × matières avec enregistrement automatique.
class VueSaisie extends StatefulWidget {
  const VueSaisie({
    super.key,
    required this.etat,
    required this.classeId,
    required this.surClasse,
    required this.allerAuxParametres,
    required this.allerAuxInscriptions,
    this.maintenant,
  });

  final EtatApp etat;
  final int? classeId;
  final ValueChanged<int> surClasse;
  final VoidCallback allerAuxParametres;
  final VoidCallback allerAuxInscriptions;
  final DateTime Function()? maintenant;

  @override
  State<VueSaisie> createState() => _VueSaisieState();
}

class _VueSaisieState extends State<VueSaisie> {
  late Periode _periode;

  EtatApp get _etat => widget.etat;

  @override
  void initState() {
    super.initState();
    _periode = Periode.moisDe((widget.maintenant ?? DateTime.now)());
  }

  Future<_DonneesNotes> _charger() async {
    final anneeId = _etat.anneeId;
    if (anneeId == null) return const _DonneesNotes();
    final services = _etat.services;
    final classes = await services.classes.lister(anneeId);
    if (classes.isEmpty) return _DonneesNotes(classes: classes);

    final choisie = classes.firstWhere(
      (c) => c.classe.id == widget.classeId,
      orElse: () => classes.first,
    );
    final id = choisie.classe.id;
    final config = await services.configs.lire(anneeId);
    // L'option « absence = zéro » s'applique aussi aux notes du mois calculées
    // d'après les évaluations.
    final effectives = await services.evaluations.saisiesEffectives(
      id,
      absenceEgaleZero: config.absenceEgaleZero,
    );
    return _DonneesNotes(
      classes: classes,
      classe: choisie,
      matieres: await services.matieres.lister(id),
      eleves: await services.eleves.lister(anneeId, classeId: id),
      saisies: effectives.saisies,
      casesEvaluees: effectives.casesEvaluees,
      moisVerrouilles: await services.notes.moisVerrouilles(id),
      config: config,
      calendrier: await services.calendriers.lire(
        anneeId,
        cycle: choisie.classe.cycle,
      ),
    );
  }

  /// Ouvre la fenêtre d'impression de la fiche de notes de la classe.
  Future<void> _ouvrirFiche(ClasseResume classe, Periode periode) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => DialogueFicheNotes(
        etat: _etat,
        classe: classe,
        periodeInitiale: periode.libelle,
        maintenant: widget.maintenant,
      ),
    );
  }

  /// Verrouille le mois affiché (avec confirmation) ou le déverrouille.
  Future<void> _basculerVerrou(int classeId, String classeNom, Periode periode) async {
    if (!periode.saisissable) return;
    final mois = periode.numero;
    final notes = _etat.services.notes;
    final verrouille = (await notes.moisVerrouilles(classeId)).contains(mois);
    if (!mounted) return;
    final ok = await confirmer(
      context,
      titre: verrouille ? 'Déverrouiller ${libelleMois(mois)} ?' : 'Verrouiller ${libelleMois(mois)} ?',
      message: verrouille
          ? 'Les notes de $classeNom pour ${libelleMois(mois)} pourront de '
              'nouveau être modifiées.'
          : 'Plus aucune note de $classeNom ne pourra être ajoutée, modifiée ou '
              'supprimée pour ${libelleMois(mois)} (notes du mois et '
              'évaluations) tant que le mois n\'est pas déverrouillé.',
      libelleConfirmer: verrouille ? 'Déverrouiller' : 'Verrouiller',
    );
    if (!ok || !mounted) return;
    final reussi = await executer(
      context,
      () => verrouille
          ? notes.deverrouiller(classeId, mois)
          : notes.verrouiller(classeId, mois),
      succes: verrouille
          ? '${libelleMois(mois)} déverrouillé.'
          : '${libelleMois(mois)} verrouillé.',
    );
    if (reussi) _etat.donneesModifiees();
  }

  @override
  Widget build(BuildContext context) {
    return Chargeur<_DonneesNotes>(
      cle: (_etat.anneeId, widget.classeId, _etat.version),
      charger: _charger,
      builder: _contenu,
    );
  }

  Widget _contenu(BuildContext context, _DonneesNotes d) {
    if (_etat.anneeCourante == null) {
      return _Vide(
        message: 'Aucune année scolaire. Créez-en une dans les paramètres '
            'avant de saisir des notes.',
        libelleBouton: 'Ouvrir les paramètres',
        icone: Icons.settings,
        onPressed: widget.allerAuxParametres,
      );
    }
    final classe = d.classe;
    if (classe == null) {
      return _Vide(
        message: 'Aucune classe pour cette année scolaire. Créez une classe, '
            'ses matières et ses coefficients dans les paramètres.',
        libelleBouton: 'Ouvrir les paramètres',
        icone: Icons.settings,
        onPressed: widget.allerAuxParametres,
      );
    }

    // La période choisie suit le calendrier de la classe (celui de son cycle) :
    // si elle n'existe plus
    // (séquences désactivées...), on revient au mois courant.
    final periodes = periodesDuCalendrier(d.calendrier);
    final periode = periodes.firstWhere(
      (p) => p == _periode,
      orElse: () => Periode.moisDe((widget.maintenant ?? DateTime.now)()),
    );
    final haut = _Selection(
      classes: d.classes,
      classeId: classe.classe.id,
      nbEleves: d.eleves.length,
      nbMatieres: d.matieres.length,
      periodes: periodes,
      periode: periode,
      verrouille: d.moisVerrouilles.contains(periode.numero) && periode.saisissable,
      peutVerrouiller: _etat.peut(Permission.notesVerrouiller),
      surFiche: _etat.peut(Permission.documentsGenerer)
          ? () => _ouvrirFiche(classe, periode)
          : null,
      surClasse: widget.surClasse,
      surPeriode: (p) => setState(() => _periode = p),
      surVerrou: () => _basculerVerrou(classe.classe.id, classe.classe.nom, periode),
    );

    Widget corps;
    if (d.matieres.isEmpty) {
      corps = _Vide(
        message: 'La classe ${classe.classe.nom} n\'a aucune matière. Ajoutez '
            'ses matières et leurs coefficients dans les paramètres.',
        libelleBouton: 'Ouvrir les paramètres',
        icone: Icons.settings,
        onPressed: widget.allerAuxParametres,
      );
    } else if (d.eleves.isEmpty) {
      corps = _Vide(
        message: 'Aucun élève n\'est inscrit dans la classe '
            '${classe.classe.nom} pour cette année scolaire.',
        libelleBouton: 'Inscrire des élèves',
        icone: Icons.person_add_alt_1,
        onPressed: widget.allerAuxInscriptions,
      );
    } else {
      corps = GrilleNotes(
        // Nouvelle grille à chaque rechargement des données.
        key: ObjectKey(d),
        enregistrer: _etat.services.notes.enregistrer,
        matieres: d.matieres,
        eleves: d.eleves,
        saisies: d.saisies,
        config: d.config,
        periode: periode,
        calendrier: d.calendrier,
        casesEvaluees: d.casesEvaluees,
        moisVerrouilles: d.moisVerrouilles,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [haut, Expanded(child: corps)],
    );
  }
}

/// Choix de la classe et de la période.
class _Selection extends StatelessWidget {
  const _Selection({
    required this.classes,
    required this.classeId,
    required this.nbEleves,
    required this.nbMatieres,
    required this.periodes,
    required this.periode,
    required this.verrouille,
    required this.peutVerrouiller,
    required this.surFiche,
    required this.surClasse,
    required this.surPeriode,
    required this.surVerrou,
  });

  final List<ClasseResume> classes;
  final int classeId;
  final int nbEleves;
  final int nbMatieres;
  final List<Periode> periodes;
  final Periode periode;
  final bool verrouille;
  final bool peutVerrouiller;

  /// Ouvre l'impression de la fiche de notes ; null si le compte n'a pas le droit.
  final VoidCallback? surFiche;
  final ValueChanged<int> surClasse;
  final ValueChanged<Periode> surPeriode;
  final VoidCallback surVerrou;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: CouleursGesco.bordure)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoixClasse(
                classes: classes,
                classeId: classeId,
                surClasse: surClasse,
              ),
              Text(
                '${nbEleves > 1 ? '$nbEleves élèves' : '$nbEleves élève'}'
                '  ·  ${nbMatieres > 1 ? '$nbMatieres matières' : '$nbMatieres matière'}',
                style: const TextStyle(color: CouleursGesco.gris),
              ),
              if (periode.saisissable && verrouille)
                const Etiquette('Mois verrouillé',
                    couleur: CouleursGesco.orange, fond: CouleursGesco.orangeClair),
              if (periode.saisissable && (peutVerrouiller || verrouille))
                OutlinedButton.icon(
                  key: const Key('bouton_verrou'),
                  onPressed: peutVerrouiller ? surVerrou : null,
                  icon: Icon(verrouille ? Icons.lock_open : Icons.lock_outline, size: 18),
                  label: Text(verrouille ? 'Déverrouiller le mois' : 'Verrouiller le mois'),
                ),
              if (surFiche != null)
                OutlinedButton.icon(
                  key: const Key('bouton_fiche_notes'),
                  onPressed: surFiche,
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('Fiche de notes'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in periodes)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      key: Key('periode_${p.cle}'),
                      label: Text(p.libelle),
                      selected: p == periode,
                      showCheckmark: false,
                      selectedColor: CouleursGesco.bleu,
                      backgroundColor: p.saisissable
                          ? Colors.white
                          : CouleursGesco.bleuClair,
                      labelStyle: TextStyle(
                        color: p == periode ? Colors.white : CouleursGesco.texte,
                        fontWeight: p.saisissable ? FontWeight.w500 : FontWeight.w700,
                      ),
                      onSelected: (_) => surPeriode(p),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Vide extends StatelessWidget {
  const _Vide({
    required this.message,
    required this.libelleBouton,
    required this.icone,
    required this.onPressed,
  });

  final String message;
  final String libelleBouton;
  final IconData icone;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MessageVide(message, icone: Icons.edit_note),
          FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icone),
            label: Text(libelleBouton),
          ),
        ],
      ),
    );
  }
}
