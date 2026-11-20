import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/calcul_classe.dart';
import '../domain/arrondi.dart';
import '../domain/periodes.dart';
import 'commun/composants.dart';
import 'theme.dart';

/// Couleurs des courbes de la progression (une par classe, dans l'ordre).
const List<Color> _couleursSeries = [
  Color(0xFF1F5FA8),
  Color(0xFFEF6C00),
  Color(0xFF2E7D32),
  Color(0xFF7B1FA2),
  Color(0xFFC62828),
  Color(0xFF00838F),
  Color(0xFF6D4C41),
  Color(0xFF546E7A),
];

/// Libellés courts des mois, dans l'ordre de [moisScolaires].
const List<String> _moisCourts = [
  'Oct',
  'Nov',
  'Déc',
  'Jan',
  'Fév',
  'Mar',
  'Avr',
  'Mai',
  'Juin',
];

String _pourcent(int? centiemes) =>
    centiemes == null ? '—' : '${formaterCentiemes(centiemes)} %';

/// Résultats de l'année pour le tableau de bord : indicateurs, moyennes par
/// classe et par période, progression et meilleurs élèves.
class SectionResultats extends StatelessWidget {
  const SectionResultats({
    super.key,
    required this.synthese,
    required this.large,
    this.allerAuxResultats,
  });

  final SyntheseEtablissement synthese;
  final bool large;

  /// Ouvre la page Résultats (bouton absent si null).
  final VoidCallback? allerAuxResultats;

  @override
  Widget build(BuildContext context) {
    final progression = _CarteProgression(synthese: synthese);
    final meilleurs = _CarteMeilleurs(synthese: synthese);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: TitreSection(
                'Résultats de l\'année',
                sousTitre: 'Moyennes sur 20 calculées d\'après les notes saisies.',
              ),
            ),
            if (allerAuxResultats != null)
              OutlinedButton.icon(
                key: const Key('voir_resultats'),
                onPressed: allerAuxResultats,
                icon: const Icon(Icons.emoji_events_outlined),
                label: const Text('Résultats détaillés'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            _TuileChiffre(
              cle: 'dash_moyenne_generale',
              libelle: 'Moyenne générale',
              valeur: formaterCentiemes(synthese.moyenneGenerale),
              detail: 'élèves évalués, année entière',
            ),
            _TuileChiffre(
              cle: 'dash_taux_reussite',
              libelle: 'Taux de réussite',
              valeur: _pourcent(synthese.tauxReussiteCentiemes),
              detail: '${synthese.nbAdmis} admis sur ${synthese.nbEvalues} évalués',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _CarteMoyennesClasses(synthese: synthese),
        const SizedBox(height: 16),
        if (large)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: progression),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: meilleurs),
            ],
          )
        else ...[
          progression,
          const SizedBox(height: 16),
          meilleurs,
        ],
      ],
    );
  }
}

class _TuileChiffre extends StatelessWidget {
  const _TuileChiffre({
    required this.cle,
    required this.libelle,
    required this.valeur,
    required this.detail,
  });

  final String cle;
  final String libelle;
  final String valeur;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Carte(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(libelle, style: const TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(
              valeur,
              key: Key(cle),
              style: const TextStyle(
                color: CouleursGesco.bleu,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(detail, style: const TextStyle(color: CouleursGesco.gris, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

Widget _titreCarte(String titre, String? aide) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        titre,
        style: const TextStyle(
          color: CouleursGesco.texte,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (aide != null) ...[
        const SizedBox(height: 4),
        Text(aide, style: const TextStyle(color: CouleursGesco.gris)),
      ],
      const SizedBox(height: 14),
    ],
  );
}

// ------------------------------------------------------- Moyennes par classe

class _CarteMoyennesClasses extends StatelessWidget {
  const _CarteMoyennesClasses({required this.synthese});

  final SyntheseEtablissement synthese;

  @override
  Widget build(BuildContext context) {
    final periodes = synthese.calendrier.periodes;
    final largeurMin = 360.0 + 100.0 * (periodes.length + 2);

    Widget cellule(Widget enfant, {int flex = 1}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Align(alignment: Alignment.centerLeft, child: enfant),
          ),
        );
    Widget titre(String t) =>
        Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13));
    Widget moyenne(int? valeur, String cle, {bool gras = false}) => Text(
          formaterCentiemes(valeur),
          key: Key(cle),
          style: TextStyle(
            fontWeight: gras ? FontWeight.w700 : FontWeight.w500,
            color: valeur == null
                ? CouleursGesco.gris
                : couleurNiveau(synthese.config.niveau(valeur)),
          ),
        );

    final lignes = <Widget>[
      Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          color: CouleursGesco.grisClair,
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        ),
        child: Row(
          children: [
            cellule(titre('Classe'), flex: 3),
            for (final p in periodes) cellule(titre(p.libelle), flex: 2),
            cellule(titre('Année'), flex: 2),
            cellule(titre('Réussite'), flex: 2),
          ],
        ),
      ),
      for (final c in synthese.classes)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CouleursGesco.bordure)),
          ),
          child: Row(
            children: [
              cellule(
                Text(
                  c.classe.classe.nom,
                  key: Key('dash_nom_${c.classe.classe.id}'),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                flex: 3,
              ),
              for (var i = 0; i < periodes.length; i++)
                cellule(
                  moyenne(c.moyennesPeriodes[i], 'dash_periode_${c.classe.classe.id}_${periodes[i].cle}'),
                  flex: 2,
                ),
              cellule(
                moyenne(c.annee.moyenneClasse, 'dash_annee_${c.classe.classe.id}', gras: true),
                flex: 2,
              ),
              cellule(
                Text(
                  _pourcent(c.annee.tauxReussiteCentiemes),
                  key: Key('dash_reussite_${c.classe.classe.id}'),
                ),
                flex: 2,
              ),
            ],
          ),
        ),
    ];

    return Carte(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titreCarte(
            'Moyennes par classe',
            'Moyenne des élèves évalués pour chaque période, puis pour l\'année, '
                'et taux de réussite de l\'année.',
          ),
          LayoutBuilder(
            builder: (context, contraintes) {
              final largeur = math.max(contraintes.maxWidth, largeurMin);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: largeur, child: Column(children: lignes)),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- Progression

class _CarteProgression extends StatelessWidget {
  const _CarteProgression({required this.synthese});

  final SyntheseEtablissement synthese;

  @override
  Widget build(BuildContext context) {
    final series = [
      for (final c in synthese.classes)
        if (c.aDesNotes) c,
    ].take(_couleursSeries.length).toList();

    // Résumé lisible par un lecteur d'écran et par les tests.
    final resume = [
      for (final c in series)
        '${c.classe.classe.nom} : ${[
          for (var i = 0; i < moisScolaires.length; i++)
            if (c.moyennesMensuelles[i] != null)
              '${_moisCourts[i]} ${formaterCentiemes(c.moyennesMensuelles[i])}',
        ].join(', ')}',
    ].join(' ; ');

    return Carte(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titreCarte(
            'Progression mensuelle',
            'Moyenne de chaque classe, mois par mois (sur 20).',
          ),
          if (series.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Pas encore de moyenne mensuelle.',
                  style: TextStyle(color: CouleursGesco.gris),
                ),
              ),
            )
          else ...[
            Semantics(
              label: 'Progression mensuelle des moyennes. $resume',
              child: SizedBox(
                height: 230,
                child: CustomPaint(
                  key: const Key('graphique_progression'),
                  size: Size.infinite,
                  painter: _PeintreProgression(
                    series: [for (final c in series) c.moyennesMensuelles],
                    seuil: synthese.config.seuilAdmission,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                for (var i = 0; i < series.length; i++)
                  Row(
                    key: Key('legende_${series[i].classe.classe.id}'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _couleursSeries[i],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(series[i].classe.classe.nom),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Courbes de moyennes : axe vertical de 0 à 20 (échelle honnête), un point
/// par mois, une ligne par classe, trait pointillé au seuil d'admission.
class _PeintreProgression extends CustomPainter {
  _PeintreProgression({required this.series, required this.seuil});

  /// Une liste de 9 valeurs (octobre à juin) par classe, en centièmes.
  final List<List<int?>> series;
  final int seuil;

  static const double _gauche = 34;
  static const double _bas = 24;
  static const double _haut = 8;
  static const double _droite = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final zone = Rect.fromLTRB(
      _gauche,
      _haut,
      math.max(_gauche + 10, size.width - _droite),
      math.max(_haut + 10, size.height - _bas),
    );
    double x(int i) => zone.left + zone.width * i / (moisScolaires.length - 1);
    double y(int centiemes) => zone.bottom - zone.height * centiemes / 2000;

    final trait = Paint()
      ..color = CouleursGesco.bordure
      ..strokeWidth = 1;
    for (final v in const [0, 5, 10, 15, 20]) {
      final py = y(v * 100);
      canvas.drawLine(Offset(zone.left, py), Offset(zone.right, py), trait);
      _texte(canvas, '$v', Offset(zone.left - 6, py), alignerADroite: true);
    }
    for (var i = 0; i < moisScolaires.length; i++) {
      _texte(canvas, _moisCourts[i], Offset(x(i), zone.bottom + 6), centre: true);
    }

    // Seuil d'admission, en pointillés.
    final pointille = Paint()
      ..color = CouleursGesco.orange
      ..strokeWidth = 1.2;
    final ys = y(seuil);
    for (var px = zone.left; px < zone.right; px += 8) {
      canvas.drawLine(
        Offset(px, ys),
        Offset(math.min(px + 4, zone.right), ys),
        pointille,
      );
    }

    for (var s = 0; s < series.length; s++) {
      final couleur = _couleursSeries[s % _couleursSeries.length];
      final ligne = Paint()
        ..color = couleur
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final point = Paint()..color = couleur;
      Path? chemin;
      for (var i = 0; i < moisScolaires.length; i++) {
        final v = series[s][i];
        if (v == null) {
          // Mois sans moyenne : la courbe s'interrompt.
          if (chemin != null) canvas.drawPath(chemin, ligne);
          chemin = null;
          continue;
        }
        final p = Offset(x(i), y(math.min(2000, math.max(0, v))));
        if (chemin == null) {
          chemin = Path()..moveTo(p.dx, p.dy);
        } else {
          chemin.lineTo(p.dx, p.dy);
        }
        canvas.drawCircle(p, 3.5, point);
      }
      if (chemin != null) canvas.drawPath(chemin, ligne);
    }
  }

  void _texte(
    Canvas canvas,
    String texte,
    Offset position, {
    bool alignerADroite = false,
    bool centre = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: texte,
        style: const TextStyle(color: CouleursGesco.gris, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = alignerADroite
        ? position.dx - tp.width
        : centre
            ? position.dx - tp.width / 2
            : position.dx;
    final dy = alignerADroite ? position.dy - tp.height / 2 : position.dy;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_PeintreProgression ancien) =>
      ancien.seuil != seuil || !_memesSeries(ancien.series, series);

  static bool _memesSeries(List<List<int?>> a, List<List<int?>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].length != b[i].length) return false;
      for (var j = 0; j < a[i].length; j++) {
        if (a[i][j] != b[i][j]) return false;
      }
    }
    return true;
  }
}

// -------------------------------------------------------------- Top élèves

class _CarteMeilleurs extends StatelessWidget {
  const _CarteMeilleurs({required this.synthese});

  final SyntheseEtablissement synthese;

  @override
  Widget build(BuildContext context) {
    final rangs = <int, int>{};
    for (final e in synthese.meilleurs) {
      rangs[e.rang] = (rangs[e.rang] ?? 0) + 1;
    }
    return Carte(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titreCarte(
            'Meilleurs élèves',
            'Les cinq premiers de l\'établissement d\'après la moyenne annuelle '
                '(ex æquo compris).',
          ),
          if (synthese.meilleurs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Aucune moyenne annuelle pour le moment.',
                  style: TextStyle(color: CouleursGesco.gris),
                ),
              ),
            )
          else
            for (final e in synthese.meilleurs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        formaterRang(e.rang),
                        key: Key('top_rang_${e.eleve.inscriptionId}'),
                        style: const TextStyle(
                          color: CouleursGesco.bleu,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${e.eleve.nom} ${e.eleve.prenom}',
                            key: Key('top_nom_${e.eleve.inscriptionId}'),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            (rangs[e.rang] ?? 0) > 1
                                ? '${e.classeNom} · ex æquo'
                                : e.classeNom,
                            style: const TextStyle(color: CouleursGesco.gris, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formaterCentiemes(e.moyenne),
                      key: Key('top_moyenne_${e.eleve.inscriptionId}'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: couleurNiveau(synthese.config.niveau(e.moyenne)),
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
