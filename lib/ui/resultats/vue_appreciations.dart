import 'package:flutter/material.dart';

import '../../app/appreciations_classe.dart';
import '../../app/calcul_classe.dart';
import '../../app/etat_app.dart';
import '../../data/depots/appreciation_depot.dart';
import '../../data/modeles_donnees.dart';
import '../../domain/arrondi.dart';
import '../../domain/calendrier.dart';
import '../../domain/decisions_conseil.dart';
import '../../domain/moteur_resultats.dart';
import '../../domain/permissions.dart';
import '../commun/chargeur.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../theme.dart';
import 'dialogue_appreciations_matieres.dart';

class _DonneesAppreciations {
  const _DonneesAppreciations(this.classeId, this.cle, this.eleves, this.matieres, this.auto);

  /// Classe et période auxquelles ces données appartiennent.
  final int classeId;
  final String cle;
  final Map<int, AppreciationEleve> eleves;
  final Map<int, Map<int, String>> matieres;

  /// Appréciations automatiques activées.
  final bool auto;
}

/// Saisie des appréciations et de la décision du conseil pour une classe et
/// une période : une appréciation générale et une décision par élève, et un
/// accès aux appréciations de chaque matière.
class VueAppreciations extends StatelessWidget {
  const VueAppreciations({
    super.key,
    required this.etat,
    required this.calcul,
    required this.portee,
    required this.periodeLibelle,
  });

  final EtatApp etat;
  final CalculClasse calcul;
  final Portee portee;

  /// Nom de la période affiché dans les titres (« Trimestre 1 », « Novembre »).
  final String periodeLibelle;

  @override
  Widget build(BuildContext context) {
    final classeId = calcul.classe.classe.id;
    final cle = portee.cle;
    return Chargeur<_DonneesAppreciations>(
      cle: (classeId, cle, etat.version),
      charger: () async => _DonneesAppreciations(
        classeId,
        cle,
        await etat.services.appreciations.eleves(classeId, cle),
        await etat.services.appreciations.matieres(classeId, cle),
        await etat.services.parametres.appreciationsAutomatiques(),
      ),
      builder: (context, d) {
        // Pendant le chargement d'une autre classe ou d'une autre période, le
        // chargeur garde les dernières données : on ne les montre pas ici,
        // sous peine d'afficher (ou d'enregistrer) l'appréciation d'une autre
        // période.
        if (d.classeId != classeId || d.cle != cle) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _Editeur(
          // Nouvel éditeur dès que les données relues arrivent (changement de
          // classe, de période ou enregistrement).
          key: ValueKey('appreciations-$classeId-$cle-${identityHashCode(d)}'),
          etat: etat,
          calcul: calcul,
          portee: portee,
          periodeLibelle: periodeLibelle,
          donnees: d,
        );
      },
    );
  }
}

class _Editeur extends StatefulWidget {
  const _Editeur({
    super.key,
    required this.etat,
    required this.calcul,
    required this.portee,
    required this.periodeLibelle,
    required this.donnees,
  });

  final EtatApp etat;
  final CalculClasse calcul;
  final Portee portee;
  final String periodeLibelle;
  final _DonneesAppreciations donnees;

  @override
  State<_Editeur> createState() => _EditeurState();
}

class _EditeurState extends State<_Editeur> {
  late final List<EleveInscrit> _eleves;
  late final Map<int, TextEditingController> _appreciations;
  late final Map<int, TextEditingController> _decisions;

  /// Appréciations rédigées d'après les notes et le classement de la période.
  late final AppreciationsGenerees _generees;
  late bool _autoActif;

  bool get _peutSaisir => widget.etat.peut(Permission.appreciationsSaisir);

  @override
  void initState() {
    super.initState();
    _autoActif = widget.donnees.auto;
    _generees = genererAppreciations(widget.calcul, widget.portee);
    // Les élèves partis ou ayant abandonné n'ont pas d'appréciation.
    _eleves = [for (final e in widget.calcul.eleves) if (e.actif) e];
    _appreciations = {
      for (final e in _eleves)
        e.inscriptionId: TextEditingController(
          text: widget.donnees.eleves[e.inscriptionId]?.appreciation ?? '',
        ),
    };
    _decisions = {
      for (final e in _eleves)
        e.inscriptionId: TextEditingController(
          text: widget.donnees.eleves[e.inscriptionId]?.decision ?? '',
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _appreciations.values) {
      c.dispose();
    }
    for (final c in _decisions.values) {
      c.dispose();
    }
    super.dispose();
  }

  AppreciationEleve _saisie(int id) => AppreciationEleve(
        appreciation: _appreciations[id]!.text.trim(),
        decision: _decisions[id]!.text.trim(),
      );

  AppreciationEleve _enregistree(int id) =>
      widget.donnees.eleves[id] ?? const AppreciationEleve();

  /// Élèves dont la saisie diffère de ce qui est enregistré.
  Map<int, AppreciationEleve> _modifications() => {
        for (final e in _eleves)
          if (_saisie(e.inscriptionId) != _enregistree(e.inscriptionId))
            e.inscriptionId: _saisie(e.inscriptionId),
      };

  Future<void> _enregistrer() async {
    final modifications = _modifications();
    if (modifications.isEmpty) return;
    final ok = await executer(
      context,
      () => widget.etat.services.appreciations.enregistrerEleves(
        modifications,
        widget.portee.cle,
      ),
      succes: modifications.length > 1
          ? 'Appréciations enregistrées pour ${modifications.length} élèves.'
          : 'Appréciation enregistrée.',
    );
    if (ok) widget.etat.donneesModifiees();
  }

  /// Proposition automatique pour un élève dont le champ est vide.
  String? _proposition(int id) {
    if (!_autoActif || _appreciations[id]!.text.trim().isNotEmpty) return null;
    final texte = _generees.generales[id];
    return (texte == null || texte.isEmpty) ? null : texte;
  }

  int get _nbPropositions => [for (final e in _eleves) _proposition(e.inscriptionId)]
      .where((p) => p != null)
      .length;

  /// Recopie les propositions dans les champs vides ; l'utilisateur peut les
  /// modifier avant d'enregistrer.
  void _utiliserTout() {
    for (final e in _eleves) {
      final p = _proposition(e.inscriptionId);
      if (p != null) _appreciations[e.inscriptionId]!.text = p;
    }
    setState(() {});
  }

  void _utiliser(int id) {
    final p = _proposition(id);
    if (p != null) {
      _appreciations[id]!.text = p;
      setState(() {});
    }
  }

  Future<void> _basculerAuto(bool actif) async {
    setState(() => _autoActif = actif);
    final ok = await executer(
      context,
      () => widget.etat.services.parametres.definirAppreciationsAutomatiques(actif),
    );
    if (!ok && mounted) setState(() => _autoActif = !actif);
  }

  Future<void> _parMatiere(EleveInscrit e) async {
    final textes = widget.donnees.matieres[e.inscriptionId] ?? const {};
    final modifies = await showDialog<Map<int, String>>(
      context: context,
      builder: (ctx) => DialogueAppreciationsMatieres(
        eleveNom: e.nomComplet,
        periodeLibelle: widget.periodeLibelle,
        matieres: widget.calcul.matieres,
        textes: textes,
        propositions: _autoActif ? _generees.matieres[e.inscriptionId] ?? const {} : const {},
        lectureSeule: !_peutSaisir,
      ),
    );
    if (modifies == null || !mounted) return;
    final ok = await executer(
      context,
      () => widget.etat.services.appreciations.enregistrerMatieres(
        e.inscriptionId,
        widget.portee.cle,
        modifies,
      ),
      succes: 'Appréciations de ${e.nomComplet} enregistrées.',
    );
    if (ok) widget.etat.donneesModifiees();
  }

  @override
  Widget build(BuildContext context) {
    if (_eleves.isEmpty) {
      return const MessageVide(
        'Aucun élève actif dans cette classe.',
        icone: Icons.people_outline,
      );
    }
    final resultats = {
      for (final r in widget.calcul.resultats(widget.portee)) r.inscriptionId: r,
    };
    final modifications = _modifications().length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _peutSaisir
                    ? 'Appréciation générale et décision du conseil, ${widget.periodeLibelle}. '
                        'Un champ vidé efface l\'appréciation.'
                    : 'Appréciations (lecture seule : votre compte ne peut pas les modifier).',
                style: const TextStyle(color: CouleursGesco.gris),
              ),
            ),
            if (_peutSaisir) ...[
              if (modifications > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    modifications > 1
                        ? '$modifications modifications non enregistrées'
                        : '1 modification non enregistrée',
                    key: const Key('appr_modifications'),
                    style: const TextStyle(color: CouleursGesco.orange),
                  ),
                ),
              FilledButton.icon(
                key: const Key('enregistrer_appreciations'),
                onPressed: modifications == 0 ? null : _enregistrer,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Enregistrer'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Switch(
              key: const Key('appr_auto_actif'),
              value: _autoActif,
              onChanged: _peutSaisir ? _basculerAuto : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _autoActif
                    ? 'Appréciation automatique : pour les élèves sans appréciation saisie, '
                        'le bulletin reprend un texte rédigé d\'après leurs notes et leur classement.'
                    : 'Appréciation automatique désactivée : seuls les textes saisis figurent '
                        'sur les bulletins.',
                key: const Key('appr_auto_texte'),
                style: const TextStyle(color: CouleursGesco.gris),
              ),
            ),
            if (_peutSaisir && _nbPropositions > 0)
              OutlinedButton.icon(
                key: const Key('appr_tout_utiliser'),
                onPressed: _utiliserTout,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: Text('Utiliser pour $_nbPropositions élève${_nbPropositions > 1 ? 's' : ''}'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        for (final e in _eleves) ...[
          _CarteEleve(
            eleve: e,
            resultat: resultats[e.inscriptionId],
            appreciation: _appreciations[e.inscriptionId]!,
            proposition: _proposition(e.inscriptionId),
            surUtiliser: () => _utiliser(e.inscriptionId),
            decision: _decisions[e.inscriptionId]!,
            lectureSeule: !_peutSaisir,
            nbMatieresRenseignees: widget.donnees.matieres[e.inscriptionId]?.length ?? 0,
            surChangement: () => setState(() {}),
            surParMatiere: () => _parMatiere(e),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _CarteEleve extends StatelessWidget {
  const _CarteEleve({
    required this.eleve,
    required this.resultat,
    required this.appreciation,
    required this.proposition,
    required this.surUtiliser,
    required this.decision,
    required this.lectureSeule,
    required this.nbMatieresRenseignees,
    required this.surChangement,
    required this.surParMatiere,
  });

  final EleveInscrit eleve;
  final ResultatEleve? resultat;
  final TextEditingController appreciation;

  /// Texte automatique proposé tant que le champ est vide (null sinon).
  final String? proposition;
  final VoidCallback surUtiliser;
  final TextEditingController decision;
  final bool lectureSeule;
  final int nbMatieresRenseignees;
  final VoidCallback surChangement;
  final VoidCallback surParMatiere;

  @override
  Widget build(BuildContext context) {
    final id = eleve.inscriptionId;
    final moyenne = resultat?.moyenne;
    final rang = resultat?.rang;
    return Carte(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  eleve.nomComplet,
                  key: Key('appr_nom_$id'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                moyenne == null
                    ? 'Pas de moyenne'
                    : 'Moyenne ${formaterCentiemes(moyenne)}'
                        '${rang == null ? '' : ' · ${formaterRang(rang)}'}',
                key: Key('appr_moyenne_$id'),
                style: const TextStyle(color: CouleursGesco.gris),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: Key('appr_$id'),
            controller: appreciation,
            readOnly: lectureSeule,
            onChanged: (_) => surChangement(),
            minLines: 1,
            maxLines: 3,
            maxLength: AppreciationDepot.longueurMaxGenerale,
            decoration: champ('Appréciation générale').copyWith(counterText: ''),
          ),
          if (proposition != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2, right: 6),
                    child: Icon(Icons.auto_awesome_outlined, size: 16, color: CouleursGesco.gris),
                  ),
                  Expanded(
                    child: Text(
                      proposition!,
                      key: Key('appr_auto_$id'),
                      style: const TextStyle(
                        color: CouleursGesco.gris,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  if (!lectureSeule)
                    TextButton(
                      key: Key('appr_utiliser_$id'),
                      onPressed: surUtiliser,
                      child: const Text('Utiliser'),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: Key('decision_conseil_$id'),
                  controller: decision,
                  readOnly: lectureSeule,
                  onChanged: (_) => surChangement(),
                  maxLength: AppreciationDepot.longueurMaxDecision,
                  decoration: champ('Décision du conseil').copyWith(
                    counterText: '',
                    suffixIcon: lectureSeule
                        ? null
                        : PopupMenuButton<String>(
                            key: Key('suggestions_$id'),
                            tooltip: 'Décisions usuelles',
                            icon: const Icon(Icons.arrow_drop_down),
                            onSelected: (v) {
                              decision.text = v;
                              surChangement();
                            },
                            itemBuilder: (_) => [
                              for (var i = 0; i < decisionsConseilUsuelles.length; i++)
                                PopupMenuItem(
                                  key: Key('suggestion_$i'),
                                  value: decisionsConseilUsuelles[i],
                                  child: Text(decisionsConseilUsuelles[i]),
                                ),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                key: Key('par_matiere_$id'),
                onPressed: surParMatiere,
                icon: const Icon(Icons.menu_book_outlined),
                label: Text(
                  nbMatieresRenseignees == 0
                      ? 'Par matière'
                      : 'Par matière ($nbMatieresRenseignees)',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
