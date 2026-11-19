import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/depots/evaluation_depot.dart';
import '../../data/erreurs.dart';
import '../../data/modeles_donnees.dart';
import '../../data/modeles_notation.dart';
import '../../domain/arrondi.dart';
import '../../domain/bareme.dart';
import '../../domain/dates.dart';
import '../../domain/modeles.dart';
import '../../domain/periodes.dart';
import '../../domain/permissions.dart';
import '../commun/chargeur.dart';
import '../commun/choix.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../notes/choix_classe.dart';
import '../notes/periode.dart';
import '../theme.dart';
import 'dialogue_evaluation.dart';
import 'dialogue_saisie_collective.dart';

class _DonneesEvaluations {
  const _DonneesEvaluations({
    this.classes = const [],
    this.classe,
    this.matieres = const [],
    this.evaluations = const [],
    this.moisVerrouilles = const {},
    this.config = ConfigResultats.defaut,
  });

  final List<ClasseResume> classes;
  final ClasseResume? classe;
  final List<MatiereClasse> matieres;
  final List<EvaluationResume> evaluations;
  final Set<int> moisVerrouilles;
  final ConfigResultats config;
}

/// Évaluations d'une classe : interrogations, devoirs, compositions, examens.
///
/// La note du mois d'une matière est calculée d'après ses évaluations
/// (moyenne pondérée par les coefficients des évaluations).
class VueEvaluations extends StatefulWidget {
  const VueEvaluations({
    super.key,
    required this.etat,
    required this.classeId,
    required this.surClasse,
    required this.allerAuxParametres,
    this.maintenant,
  });

  final EtatApp etat;
  final int? classeId;
  final ValueChanged<int> surClasse;
  final VoidCallback allerAuxParametres;
  final DateTime Function()? maintenant;

  @override
  State<VueEvaluations> createState() => _VueEvaluationsState();
}

class _VueEvaluationsState extends State<VueEvaluations> {
  int? _matiereId;
  int? _mois;

  EtatApp get _etat => widget.etat;
  EvaluationDepot get _depot => _etat.services.evaluations;

  Future<_DonneesEvaluations> _charger() async {
    final anneeId = _etat.anneeId;
    if (anneeId == null) return const _DonneesEvaluations();
    final services = _etat.services;
    final classes = await services.classes.lister(anneeId);
    if (classes.isEmpty) return _DonneesEvaluations(classes: classes);
    final choisie = classes.firstWhere(
      (c) => c.classe.id == widget.classeId,
      orElse: () => classes.first,
    );
    final id = choisie.classe.id;
    final matieres = await services.matieres.lister(id);
    final matiereId = matieres.any((m) => m.id == _matiereId) ? _matiereId : null;
    return _DonneesEvaluations(
      classes: classes,
      classe: choisie,
      matieres: matieres,
      evaluations: await _depot.lister(classeId: id, matiereId: matiereId, mois: _mois),
      moisVerrouilles: await services.notes.moisVerrouilles(id),
      config: await services.configs.lire(anneeId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Chargeur<_DonneesEvaluations>(
      cle: (_etat.anneeId, widget.classeId, _matiereId, _mois, _etat.version),
      charger: _charger,
      builder: _contenu,
    );
  }

  Widget _contenu(BuildContext context, _DonneesEvaluations d) {
    if (_etat.anneeCourante == null) {
      return _Vide(
        message: 'Aucune année scolaire. Créez-en une dans les paramètres '
            'avant de créer des évaluations.',
        libelleBouton: 'Ouvrir les paramètres',
        onPressed: widget.allerAuxParametres,
      );
    }
    final classe = d.classe;
    if (classe == null) {
      return _Vide(
        message: 'Aucune classe pour cette année scolaire. Créez une classe et '
            'ses matières dans les paramètres.',
        libelleBouton: 'Ouvrir les paramètres',
        onPressed: widget.allerAuxParametres,
      );
    }
    final gerer = _etat.peut(Permission.evaluationsGerer);
    final matiereFiltre = d.matieres.any((m) => m.id == _matiereId) ? _matiereId : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: CouleursGesco.bordure)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: Wrap(
            spacing: 16,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoixClasse(
                classes: d.classes,
                classeId: classe.classe.id,
                surClasse: (id) {
                  setState(() {
                    _matiereId = null;
                    _mois = null;
                  });
                  widget.surClasse(id);
                },
              ),
              SizedBox(
                width: 220,
                child: ChoixListe<int?>(
                  cleChamp: const Key('filtre_matiere'),
                  libelle: 'Matière',
                  valeur: matiereFiltre,
                  options: [
                    (null, 'Toutes les matières'),
                    for (final m in d.matieres) (m.id, m.nom),
                  ],
                  onChanged: (id) => setState(() => _matiereId = id),
                ),
              ),
              SizedBox(
                width: 180,
                child: ChoixListe<int?>(
                  cleChamp: const Key('filtre_mois'),
                  libelle: 'Mois',
                  valeur: _mois,
                  options: [
                    (null, 'Tous les mois'),
                    for (final m in moisScolaires) (m, libelleMois(m)),
                  ],
                  onChanged: (m) => setState(() => _mois = m),
                ),
              ),
              if (gerer && d.matieres.isNotEmpty)
                FilledButton.icon(
                  key: const Key('nouvelle_evaluation'),
                  onPressed: () => _creer(d),
                  icon: const Icon(Icons.add),
                  label: const Text('Nouvelle évaluation'),
                ),
            ],
          ),
        ),
        Expanded(child: _liste(d, gerer)),
      ],
    );
  }

  Widget _liste(_DonneesEvaluations d, bool gerer) {
    if (d.matieres.isEmpty) {
      return _Vide(
        message: 'La classe ${d.classe!.classe.nom} n\'a aucune matière. Ajoutez '
            'ses matières dans les paramètres avant de créer des évaluations.',
        libelleBouton: 'Ouvrir les paramètres',
        onPressed: widget.allerAuxParametres,
      );
    }
    if (d.evaluations.isEmpty) {
      final filtre = _matiereId != null || _mois != null;
      return MessageVide(
        filtre
            ? 'Aucune évaluation ne correspond à ces filtres.'
            : 'Aucune évaluation pour la classe ${d.classe!.classe.nom}. '
                '${gerer ? 'Créez la première avec « Nouvelle évaluation ». ' : ''}'
                'Sans évaluation, la note du mois se saisit directement dans '
                '« Notes du mois ».',
        icone: Icons.assignment_outlined,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: d.evaluations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _CarteEvaluation(
        resume: d.evaluations[i],
        moisVerrouille: d.moisVerrouilles.contains(d.evaluations[i].evaluation.mois),
        gerer: gerer,
        saisir: _etat.peut(Permission.notesSaisir),
        verrouiller: _etat.peut(Permission.notesVerrouiller),
        surSaisie: () => _saisir(d, d.evaluations[i]),
        surStats: () => _stats(d, d.evaluations[i]),
        surModifier: () => _modifier(d, d.evaluations[i]),
        surValidation: () => _basculerValidation(d.evaluations[i]),
        surSuppression: () => _supprimer(d.evaluations[i]),
      ),
    );
  }

  Future<void> _creer(_DonneesEvaluations d) async {
    final fiche = await showDialog<SaisieEvaluation>(
      context: context,
      builder: (ctx) => DialogueEvaluation(
        matieres: d.matieres,
        matiereInitialeId: _matiereId,
        moisInitial: _mois ?? Periode.moisDe((widget.maintenant ?? DateTime.now)()).numero,
      ),
    );
    if (fiche == null || !mounted) return;
    final ok = await executer(
      context,
      () async {
        await _depot.creer(
          classeId: d.classe!.classe.id,
          matiereId: fiche.matiereId,
          mois: fiche.mois,
          titre: fiche.titre,
          type: fiche.type,
          date: fiche.date,
          coefficient: fiche.coefficient,
          bareme: fiche.bareme,
        );
      },
      succes: 'Évaluation « ${fiche.titre} » créée.',
    );
    if (ok) _etat.donneesModifiees();
  }

  Future<void> _modifier(_DonneesEvaluations d, EvaluationResume r) async {
    final e = r.evaluation;
    final fiche = await showDialog<SaisieEvaluation>(
      context: context,
      builder: (ctx) => DialogueEvaluation(
        matieres: d.matieres,
        moisInitial: e.mois,
        existante: e,
        verrouillerMoisEtBareme: r.nbNotes > 0,
      ),
    );
    if (fiche == null || !mounted) return;
    final ok = await executer(
      context,
      () => _depot.modifier(
        e.id,
        titre: fiche.titre,
        type: fiche.type,
        date: fiche.date,
        effacerDate: fiche.date == null,
        coefficient: fiche.coefficient,
        bareme: fiche.bareme == e.bareme ? null : fiche.bareme,
        mois: fiche.mois == e.mois ? null : fiche.mois,
      ),
      succes: 'Évaluation « ${fiche.titre} » enregistrée.',
    );
    if (ok) _etat.donneesModifiees();
  }

  Future<void> _basculerValidation(EvaluationResume r) async {
    final e = r.evaluation;
    final valider = !e.valide;
    final oui = await confirmer(
      context,
      titre: valider ? 'Valider l\'évaluation' : 'Annuler la validation',
      message: valider
          ? 'Une fois « ${e.titre} » validée, ses notes ne pourront plus être '
              'modifiées. Vous pourrez annuler la validation plus tard.'
          : 'Les notes de « ${e.titre} » pourront de nouveau être modifiées.',
      libelleConfirmer: valider ? 'Valider' : 'Annuler la validation',
    );
    if (!oui || !mounted) return;
    final ok = await executer(
      context,
      () => _depot.valider(e.id, valide: valider),
      succes: valider ? 'Évaluation validée.' : 'Validation annulée.',
    );
    if (ok) _etat.donneesModifiees();
  }

  Future<void> _supprimer(EvaluationResume r) async {
    final e = r.evaluation;
    var avecNotes = false;
    try {
      final oui = await confirmer(
        context,
        titre: 'Supprimer l\'évaluation',
        message: 'Supprimer « ${e.titre} » ? La note du mois sera recalculée.',
        libelleConfirmer: 'Supprimer',
        danger: true,
      );
      if (!oui || !mounted) return;
      try {
        await _depot.supprimer(e.id);
      } on ErreurAConfirmer catch (confirmation) {
        if (!mounted) return;
        final encore = await confirmer(
          context,
          titre: 'Supprimer les notes ?',
          message: confirmation.message,
          libelleConfirmer: 'Tout supprimer',
          danger: true,
        );
        if (!encore || !mounted) return;
        avecNotes = true;
        await _depot.supprimer(e.id, avecNotes: true);
      }
      if (!mounted) return;
      afficherMessage(
        context,
        avecNotes ? 'Évaluation et notes supprimées.' : 'Évaluation supprimée.',
      );
      _etat.donneesModifiees();
    } on ErreurGesco catch (erreur) {
      if (mounted) afficherMessage(context, erreur.message, erreur: true);
    } catch (erreur) {
      if (mounted) afficherMessage(context, 'Erreur inattendue : $erreur', erreur: true);
    }
  }

  Future<void> _saisir(_DonneesEvaluations d, EvaluationResume r) async {
    final e = r.evaluation;
    final anneeId = _etat.anneeId;
    if (anneeId == null) return;
    final services = _etat.services;
    final eleves = [
      for (final el in await services.eleves.lister(anneeId, classeId: e.classeId))
        if (el.actif) el,
    ];
    final notes = await _depot.lireNotes(e.id);
    if (!mounted) return;
    String? motif;
    if (!_etat.peut(Permission.notesSaisir)) {
      motif = 'Vous n\'avez pas l\'autorisation de saisir des notes.';
    } else if (e.valide) {
      motif = 'Évaluation validée : annulez la validation pour modifier les notes.';
    } else if (d.moisVerrouilles.contains(e.mois)) {
      motif = '${libelleMois(e.mois)} est verrouillé : déverrouillez le mois pour '
          'modifier les notes.';
    }
    final modifiees = await showDialog<Map<int, Saisie?>>(
      context: context,
      builder: (ctx) => DialogueSaisieCollective(
        evaluation: e,
        matiereNom: r.matiereNom,
        eleves: eleves,
        notes: notes,
        motifLecture: motif,
      ),
    );
    if (modifiees == null || !mounted) return;
    final ok = await executer(
      context,
      () => _depot.enregistrerLot(e.id, modifiees),
      succes: modifiees.length > 1
          ? '${modifiees.length} notes enregistrées.'
          : '1 note enregistrée.',
    );
    if (ok) _etat.donneesModifiees();
  }

  Future<void> _stats(_DonneesEvaluations d, EvaluationResume r) async {
    final e = r.evaluation;
    StatsEvaluation stats;
    try {
      stats = await _depot.statistiques(e.id, seuilAdmission: d.config.seuilAdmission);
    } on ErreurGesco catch (erreur) {
      if (mounted) afficherMessage(context, erreur.message, erreur: true);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _DialogueStats(resume: r, stats: stats),
    );
  }
}

class _CarteEvaluation extends StatelessWidget {
  const _CarteEvaluation({
    required this.resume,
    required this.moisVerrouille,
    required this.gerer,
    required this.saisir,
    required this.verrouiller,
    required this.surSaisie,
    required this.surStats,
    required this.surModifier,
    required this.surValidation,
    required this.surSuppression,
  });

  final EvaluationResume resume;
  final bool moisVerrouille;
  final bool gerer;
  final bool saisir;
  final bool verrouiller;
  final VoidCallback surSaisie;
  final VoidCallback surStats;
  final VoidCallback surModifier;
  final VoidCallback surValidation;
  final VoidCallback surSuppression;

  @override
  Widget build(BuildContext context) {
    final e = resume.evaluation;
    final fige = e.valide || moisVerrouille;
    final date = e.date == null ? '' : ' · ${formaterDateFr(e.date)}';
    final avancement = resume.nbEleves == 0 ? 0.0 : resume.nbNotes / resume.nbEleves;
    return Carte(
      key: Key('evaluation_${e.id}'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                e.titre,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              Etiquette(e.type.libelle, couleur: CouleursGesco.bleu, fond: CouleursGesco.bleuClair),
              if (e.valide)
                const Etiquette('Validée', couleur: CouleursGesco.vert, fond: CouleursGesco.vertClair),
              if (moisVerrouille)
                const Etiquette(
                  'Mois verrouillé',
                  couleur: CouleursGesco.orange,
                  fond: CouleursGesco.orangeClair,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${resume.matiereNom} · ${libelleMois(e.mois)}$date · '
            'coef ${formaterCoefficient(e.coefficient)} · ${e.libelleBareme}',
            key: Key('detail_evaluation_${e.id}'),
            style: const TextStyle(color: CouleursGesco.gris),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: avancement.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: CouleursGesco.grisClair,
                    color: resume.complete ? CouleursGesco.vert : CouleursGesco.bleu,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${resume.nbNotes} / ${resume.nbEleves} notes',
                key: Key('avancement_evaluation_${e.id}'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.tonalIcon(
                key: Key('saisir_${e.id}'),
                onPressed: surSaisie,
                icon: Icon(saisir && !fige ? Icons.edit_note : Icons.visibility_outlined, size: 18),
                label: Text(saisir && !fige ? 'Saisir les notes' : 'Voir les notes'),
              ),
              OutlinedButton.icon(
                key: Key('stats_${e.id}'),
                onPressed: surStats,
                icon: const Icon(Icons.bar_chart, size: 18),
                label: const Text('Statistiques'),
              ),
              if (gerer)
                OutlinedButton.icon(
                  key: Key('modifier_${e.id}'),
                  onPressed: surModifier,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Modifier'),
                ),
              if (verrouiller)
                OutlinedButton.icon(
                  key: Key('valider_${e.id}'),
                  onPressed: surValidation,
                  icon: Icon(e.valide ? Icons.lock_open : Icons.verified_outlined, size: 18),
                  label: Text(e.valide ? 'Annuler la validation' : 'Valider'),
                ),
              if (gerer)
                TextButton.icon(
                  key: Key('supprimer_${e.id}'),
                  style: TextButton.styleFrom(foregroundColor: CouleursGesco.rouge),
                  onPressed: surSuppression,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Supprimer'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DialogueStats extends StatelessWidget {
  const _DialogueStats({required this.resume, required this.stats});

  final EvaluationResume resume;
  final StatsEvaluation stats;

  @override
  Widget build(BuildContext context) {
    final e = resume.evaluation;
    final b = stats.bareme;
    String note(int? c) => c == null ? '—' : '${formaterCentiemes(c)} / $b';
    final taux = stats.tauxReussite;
    final lignes = <(String, String)>[
      ('Élèves dans la classe', '${stats.nbEleves}'),
      ('Notes saisies', '${stats.nbSaisies}'),
      ('Absents', '${stats.nbAbsents}'),
      ('Dispensés', '${stats.nbDispenses}'),
      ('Pas encore notés', '${stats.nbNonSaisis}'),
      ('Moyenne de la classe', note(stats.moyenne)),
      if (b != baremeParDefaut)
        ('Moyenne ramenée sur 20', stats.moyenneSur20 == null ? '—' : '${formaterCentiemes(stats.moyenneSur20!)} / 20'),
      ('Meilleure note', note(stats.maximum)),
      ('Note la plus basse', note(stats.minimum)),
      (
        'Taux de réussite',
        taux == null ? '—' : '${taux.toStringAsFixed(1).replaceAll('.', ',')} % (${stats.nbReussites} / ${stats.nbSaisies})',
      ),
    ];
    return AlertDialog(
      title: Text('Statistiques · ${e.titre}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${resume.matiereNom} · ${libelleMois(e.mois)} · ${e.libelleBareme}',
              style: const TextStyle(color: CouleursGesco.gris),
            ),
            const SizedBox(height: 12),
            for (final l in lignes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: Text(l.$1)),
                    Text(l.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Les élèves partis ou ayant abandonné ne sont pas comptés. La '
              'réussite compare la note ramenée sur 20 au seuil d\'admission.',
              style: TextStyle(color: CouleursGesco.gris, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
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
          MessageVide(message, icone: Icons.assignment_outlined),
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
