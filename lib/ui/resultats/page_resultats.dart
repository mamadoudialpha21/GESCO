import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/calcul_classe.dart';
import '../../app/etat_app.dart';
import '../../domain/arrondi.dart';
import '../../domain/calendrier.dart';
import '../../domain/modeles.dart';
import '../../domain/periodes.dart';
import '../../domain/permissions.dart';
import '../../domain/statistiques.dart';
import '../commun/chargeur.dart';
import '../commun/choix.dart';
import '../commun/composants.dart';
import '../notes/choix_classe.dart';
import '../theme.dart';

enum _Vue { eleves, classes }

class _DonneesResultats {
  const _DonneesResultats({
    this.calculs = const [],
    this.calendrier = Calendrier.defaut,
  });

  final List<CalculClasse> calculs;
  final Calendrier calendrier;
}

/// Résultats et classements : moyennes, rangs (avec ex æquo), mentions et
/// décisions des élèves d'une classe, et comparaison des classes, pour un mois,
/// une période, une séquence ou l'année entière.
class PageResultats extends StatefulWidget {
  const PageResultats({
    super.key,
    required this.etat,
    required this.allerAuxParametres,
    this.maintenant,
  });

  final EtatApp etat;
  final VoidCallback allerAuxParametres;

  /// Horloge (remplaçable dans les tests) : sert à choisir la période affichée
  /// au départ.
  final DateTime Function()? maintenant;

  @override
  State<PageResultats> createState() => _PageResultatsState();
}

class _PageResultatsState extends State<PageResultats> {
  _Vue _vue = _Vue.eleves;
  int? _classeId;
  String? _cle;

  /// Matière du classement ; null = moyenne générale.
  int? _matiereId;

  Future<_DonneesResultats> _charger() async {
    final anneeId = widget.etat.anneeId;
    if (anneeId == null) return const _DonneesResultats();
    final services = widget.etat.services;
    final calendrier = await services.calendriers.lire(anneeId);
    final calculs = await chargerToutesLesClasses(
      services,
      anneeId,
      calendrier: calendrier,
    );
    return _DonneesResultats(calculs: calculs, calendrier: calendrier);
  }

  @override
  Widget build(BuildContext context) {
    final etat = widget.etat;
    if (!etat.peut(Permission.resultatsVoir)) {
      return const MessageVide(
        'Votre compte n\'a pas le droit de consulter les résultats.',
        icone: Icons.lock_outline,
      );
    }
    return Chargeur<_DonneesResultats>(
      cle: (etat.anneeId, etat.version),
      charger: _charger,
      builder: _contenu,
    );
  }

  Widget _sansDonnees(String message, IconData icone) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MessageVide(message, icone: icone),
          FilledButton.icon(
            onPressed: widget.allerAuxParametres,
            icon: const Icon(Icons.settings),
            label: const Text('Ouvrir les paramètres'),
          ),
        ],
      ),
    );
  }

  List<(String, String)> _optionsPortee(Calendrier c) => [
        for (final p in c.periodes) (p.cle, p.libelle),
        (cleAnnee, 'Année entière'),
        for (final s in c.sequences) (s.cle, s.libelle),
        for (final m in moisScolaires) ('m$m', libelleMois(m)),
      ];

  Widget _contenu(BuildContext context, _DonneesResultats d) {
    final annee = widget.etat.anneeCourante;
    if (annee == null) {
      return _sansDonnees(
        'Aucune année scolaire. Créez-en une dans les paramètres.',
        Icons.event_outlined,
      );
    }
    if (d.calculs.isEmpty) {
      return _sansDonnees(
        'Aucune classe pour cette année scolaire. Créez des classes, leurs '
        'matières et leurs coefficients dans les paramètres.',
        Icons.school_outlined,
      );
    }

    // Choix courants : repli sur une valeur valide si la précédente a disparu
    // (classe supprimée, séquences désactivées...).
    final calcul = d.calculs.firstWhere(
      (c) => c.classe.classe.id == _classeId,
      orElse: () => d.calculs.first,
    );
    final maintenant = (widget.maintenant ?? DateTime.now)();
    final cle = (_cle != null && d.calendrier.portee(_cle!) != null)
        ? _cle!
        : (d.calendrier.periodeDuMois(maintenant.month)?.cle ?? cleAnnee);
    final portee = d.calendrier.portee(cle)!;
    final matiereId =
        calcul.matieres.any((m) => m.id == _matiereId) ? _matiereId : null;

    final commandes = Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<_Vue>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _Vue.eleves, label: Text('Élèves', key: Key('vue_eleves'))),
            ButtonSegment(value: _Vue.classes, label: Text('Classes', key: Key('vue_classes'))),
          ],
          selected: {_vue},
          onSelectionChanged: (s) => setState(() => _vue = s.first),
        ),
        if (_vue == _Vue.eleves)
          ChoixClasse(
            classes: [for (final c in d.calculs) c.classe],
            classeId: calcul.classe.classe.id,
            surClasse: (id) => setState(() {
              _classeId = id;
              _matiereId = null;
            }),
          ),
        SizedBox(
          width: 220,
          child: ChoixListe<String>(
            cleChamp: const Key('choix_portee'),
            libelle: 'Période',
            valeur: cle,
            options: _optionsPortee(d.calendrier),
            onChanged: (v) {
              if (v != null) setState(() => _cle = v);
            },
          ),
        ),
        if (_vue == _Vue.eleves)
          SizedBox(
            width: 260,
            child: ChoixListe<int>(
              cleChamp: const Key('choix_classement'),
              libelle: 'Classer par',
              valeur: matiereId ?? 0,
              options: [
                (0, 'Moyenne générale'),
                for (final m in calcul.matieres) (m.id, m.nom),
              ],
              onChanged: (v) => setState(() => _matiereId = (v == null || v == 0) ? null : v),
            ),
          ),
      ],
    );

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TitreSection(
          'Résultats et classements',
          sousTitre: 'Année ${annee.libelle} · moyennes, rangs, mentions et décisions.',
        ),
        const SizedBox(height: 16),
        commandes,
        const SizedBox(height: 16),
        if (_vue == _Vue.eleves)
          ..._vueEleves(calcul, portee, matiereId)
        else
          ..._vueClasses(d.calculs, portee),
      ],
    );
  }

  // ---------------------------------------------------------------- Élèves

  List<Widget> _vueEleves(CalculClasse calcul, Portee portee, int? matiereId) {
    final lignes = lignesClassement(calcul, portee, matiereId: matiereId);
    final matiere = matiereId == null
        ? null
        : calcul.matieres.firstWhere((m) => m.id == matiereId);
    return [
      if (matiere == null) _Synthese(stats: calcul.stats(portee)),
      if (matiere != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'Classement dans la matière « ${matiere.nom} » (note sur 20).',
            key: const Key('classement_matiere'),
            style: const TextStyle(color: CouleursGesco.gris),
          ),
        ),
      const SizedBox(height: 12),
      if (lignes.isEmpty)
        const MessageVide(
          'Aucun élève dans cette classe. Inscrivez des élèves depuis la page Inscriptions.',
          icone: Icons.people_outline,
        )
      else
        _TableauEleves(
          lignes: lignes,
          config: calcul.config,
          avecDecision: matiereId == null,
        ),
    ];
  }

  // ---------------------------------------------------------------- Classes

  List<Widget> _vueClasses(List<CalculClasse> calculs, Portee portee) {
    final resumes = comparerClasses(calculs, portee);
    return [
      const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text(
          'Les classes sont rangées d\'après la moyenne de leurs élèves évalués. '
          'La comparaison est indicative : toutes les classes n\'ont pas les '
          'mêmes matières ni le même niveau.',
          style: TextStyle(color: CouleursGesco.gris),
        ),
      ),
      _TableauClasses(resumes: resumes),
    ];
  }
}

// ----------------------------------------------------------------- Synthèse

class _Synthese extends StatelessWidget {
  const _Synthese({required this.stats});

  final StatsClasse stats;

  @override
  Widget build(BuildContext context) {
    Widget tuile(String cle, String libelle, String valeur) {
      return Carte(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(libelle, style: const TextStyle(color: CouleursGesco.gris, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              valeur,
              key: Key(cle),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    final taux = stats.tauxReussiteCentiemes;
    final mentions = [
      for (final e in stats.repartitionMentions.entries)
        if (e.value > 0 && e.key != sansMention) '${e.key} : ${e.value}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            tuile('stat_effectif', 'Effectif', '${stats.effectif}'),
            tuile('stat_evalues', 'Élèves évalués', '${stats.evalues}'),
            tuile('stat_moyenne', 'Moyenne de la classe', formaterCentiemes(stats.moyenneClasse)),
            tuile('stat_meilleure', 'Meilleure moyenne', formaterCentiemes(stats.meilleureMoyenne)),
            tuile('stat_faible', 'Moyenne la plus faible', formaterCentiemes(stats.plusFaibleMoyenne)),
            tuile(
              'stat_reussite',
              'Taux de réussite',
              taux == null ? '—' : '${formaterCentiemes(taux)} %',
            ),
            tuile('stat_admis', 'Admis / non admis', '${stats.admis} / ${stats.nonAdmis}'),
          ],
        ),
        if (mentions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            key: const Key('repartition_mentions'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in mentions)
                Etiquette(m, couleur: CouleursGesco.bleu, fond: CouleursGesco.bleuClair),
            ],
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------ Tableaux

const double _largeurMin = 1000;

/// Cellule de largeur fixe (ou souple avec [souple]).
Widget _cellule(Widget enfant, {double largeur = 100, bool souple = false}) {
  final contenu = Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Align(alignment: Alignment.centerLeft, child: enfant),
  );
  return souple ? Expanded(child: contenu) : SizedBox(width: largeur, child: contenu);
}

Widget _enTete(List<Widget> cellules) {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      color: CouleursGesco.grisClair,
      border: Border(bottom: BorderSide(color: CouleursGesco.bordure)),
    ),
    child: Row(children: cellules),
  );
}

Widget _titre(String texte) =>
    Text(texte, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13));

/// Tableau défilant horizontalement quand la fenêtre est étroite.
Widget _tableau(List<Widget> lignes) {
  return Carte(
    child: LayoutBuilder(
      builder: (context, contraintes) {
        final largeur = math.max(contraintes.maxWidth, _largeurMin);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: largeur, child: Column(children: lignes)),
        );
      },
    ),
  );
}

class _TableauEleves extends StatelessWidget {
  const _TableauEleves({
    required this.lignes,
    required this.config,
    required this.avecDecision,
  });

  final List<LigneClassement> lignes;
  final ConfigResultats config;
  final bool avecDecision;

  @override
  Widget build(BuildContext context) {
    return _tableau([
      _enTete([
        _cellule(_titre('Rang'), largeur: 150),
        _cellule(_titre('Matricule'), largeur: 110),
        _cellule(_titre('Élève'), souple: true),
        _cellule(_titre(avecDecision ? 'Moyenne' : 'Note'), largeur: 90),
        _cellule(_titre('Mention'), largeur: 130),
        if (avecDecision) _cellule(_titre('Décision'), largeur: 150),
        _cellule(_titre('Situation'), largeur: 170),
      ]),
      for (final l in lignes) _LigneEleve(ligne: l, config: config, avecDecision: avecDecision),
    ]);
  }
}

class _LigneEleve extends StatelessWidget {
  const _LigneEleve({
    required this.ligne,
    required this.config,
    required this.avecDecision,
  });

  final LigneClassement ligne;
  final ConfigResultats config;
  final bool avecDecision;

  @override
  Widget build(BuildContext context) {
    final e = ligne.eleve;
    final id = e.inscriptionId;
    final moyenne = ligne.moyenne;
    final couleur = moyenne == null ? CouleursGesco.gris : couleurNiveau(config.niveau(moyenne));
    final podium = ligne.rang != null && ligne.rang! <= 3;

    final situations = <Widget>[
      if (!e.actif)
        Etiquette(
          e.statut.libelle,
          key: Key('statut_$id'),
          couleur: CouleursGesco.gris,
          fond: CouleursGesco.grisClair,
        )
      else if (moyenne == null)
        Etiquette(
          'Sans note',
          key: Key('sans_moyenne_$id'),
          couleur: CouleursGesco.rouge,
          fond: CouleursGesco.rougeClair,
        )
      else if (ligne.incomplet)
        Etiquette(
          'Incomplet',
          key: Key('incomplet_$id'),
          couleur: CouleursGesco.orange,
          fond: CouleursGesco.orangeClair,
        ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CouleursGesco.bordure)),
      ),
      child: Row(
        children: [
          _cellule(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ligne.rang == null ? '—' : formaterRang(ligne.rang!),
                  key: Key('rang_$id'),
                  style: TextStyle(
                    fontWeight: podium ? FontWeight.w800 : FontWeight.w500,
                    color: podium ? CouleursGesco.bleu : null,
                  ),
                ),
                if (ligne.exAequo) ...[
                  const SizedBox(width: 6),
                  Text(
                    'ex æquo',
                    key: Key('exaequo_$id'),
                    style: const TextStyle(fontSize: 11, color: CouleursGesco.gris),
                  ),
                ],
              ],
            ),
            largeur: 150,
          ),
          _cellule(Text(e.matricule, overflow: TextOverflow.ellipsis), largeur: 110),
          _cellule(
            Text(
              '${e.nom} ${e.prenom}',
              key: Key('nom_$id'),
              overflow: TextOverflow.ellipsis,
            ),
            souple: true,
          ),
          _cellule(
            Text(
              formaterCentiemes(moyenne),
              key: Key('moyenne_$id'),
              style: TextStyle(fontWeight: FontWeight.w700, color: couleur),
            ),
            largeur: 90,
          ),
          _cellule(Text(ligne.mention, key: Key('mention_$id')), largeur: 130),
          if (avecDecision)
            _cellule(Text(ligne.decision, key: Key('decision_$id')), largeur: 150),
          _cellule(
            Wrap(spacing: 6, runSpacing: 4, children: situations),
            largeur: 170,
          ),
        ],
      ),
    );
  }
}

class _TableauClasses extends StatelessWidget {
  const _TableauClasses({required this.resumes});

  final List<ResumeClasse> resumes;

  @override
  Widget build(BuildContext context) {
    return _tableau([
      _enTete([
        _cellule(_titre('Rang'), largeur: 110),
        _cellule(_titre('Classe'), souple: true),
        _cellule(_titre('Niveau'), largeur: 140),
        _cellule(_titre('Effectif'), largeur: 80),
        _cellule(_titre('Évalués'), largeur: 80),
        _cellule(_titre('Moyenne'), largeur: 90),
        _cellule(_titre('Meilleure'), largeur: 90),
        _cellule(_titre('Plus faible'), largeur: 90),
        _cellule(_titre('Réussite'), largeur: 100),
      ]),
      for (final r in resumes) _LigneClasse(resume: r),
    ]);
  }
}

class _LigneClasse extends StatelessWidget {
  const _LigneClasse({required this.resume});

  final ResumeClasse resume;

  @override
  Widget build(BuildContext context) {
    final id = resume.classe.classe.id;
    final s = resume.stats;
    final taux = s.tauxReussiteCentiemes;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CouleursGesco.bordure)),
      ),
      child: Row(
        children: [
          _cellule(
            Text(
              resume.rang == null ? '—' : formaterRang(resume.rang!),
              key: Key('classe_rang_$id'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            largeur: 110,
          ),
          _cellule(
            Text(resume.classe.classe.nom, key: Key('classe_nom_$id'), overflow: TextOverflow.ellipsis),
            souple: true,
          ),
          _cellule(Text(resume.classe.classe.niveau, overflow: TextOverflow.ellipsis), largeur: 140),
          _cellule(Text('${s.effectif}', key: Key('classe_effectif_$id')), largeur: 80),
          _cellule(Text('${s.evalues}', key: Key('classe_evalues_$id')), largeur: 80),
          _cellule(
            Text(
              formaterCentiemes(s.moyenneClasse),
              key: Key('classe_moyenne_$id'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            largeur: 90,
          ),
          _cellule(Text(formaterCentiemes(s.meilleureMoyenne)), largeur: 90),
          _cellule(Text(formaterCentiemes(s.plusFaibleMoyenne)), largeur: 90),
          _cellule(
            Text(
              taux == null ? '—' : '${formaterCentiemes(taux)} %',
              key: Key('classe_reussite_$id'),
            ),
            largeur: 100,
          ),
        ],
      ),
    );
  }
}
