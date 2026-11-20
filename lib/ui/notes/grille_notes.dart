import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/depots/note_depot.dart';
import '../../data/erreurs.dart';
import '../../data/modeles_donnees.dart';
import '../../domain/arrondi.dart';
import '../../domain/bareme.dart';
import '../../domain/modeles.dart';
import '../../domain/moteur_resultats.dart';
import '../../domain/periodes.dart';
import '../../domain/saisie_note.dart';
import '../../domain/statistiques.dart';
import '../theme.dart';
import 'periode.dart';

/// Enregistre le contenu d'une case (null = case vidée).
typedef EnregistrerNote = Future<void> Function({
  required int inscriptionId,
  required int matiereId,
  required int mois,
  required Saisie? saisie,
});

enum _Deplacement { bas, haut, droite, gauche }

/// Note chiffrée (centièmes) telle qu'on l'affiche sur le barème [bareme] de
/// la matière : la note d'origine si elle a été saisie sur ce barème, sinon la
/// note sur 20 ramenée sur ce barème.
int _centiemesAffiches(Saisie s, int bareme) {
  if (s.brut != null && s.bareme == bareme) return s.brut!;
  final sur20 = s.centiemes!;
  return bareme == baremeParDefaut ? sur20 : convertirDepuis20(sur20, bareme);
}

enum _Statut { repos, enCours, enregistre, erreur }

const double _largeurNom = 168;
const double _largeurMatiere = 76;
const double _hauteurLigne = 54;
const double _hauteurEntete = 58;

/// Colonne du tableau : une matière (saisie ou lecture), une moyenne, un rang...
class _Colonne {
  const _Colonne({
    required this.titre,
    this.sousTitre,
    this.largeur = _largeurMatiere,
    this.valeur,
    this.texte,
    this.matiereId,
    this.estMoyenne = false,
    this.estRang = false,
  });

  final String titre;
  final String? sousTitre;
  final double largeur;

  /// Valeur numérique (centièmes) de la colonne pour un élève, ou null.
  final int? Function(DonneesEleve, ResultatEleve)? valeur;

  /// Texte libre (mention, décision).
  final String Function(DonneesEleve, ResultatEleve)? texte;

  /// Renseigné pour les colonnes dont les cases se saisissent.
  final int? matiereId;
  final bool estMoyenne;
  final bool estRang;

  /// Même colonne, élargie : sert à remplir la largeur disponible quand le
  /// tableau est plus étroit que l'écran.
  _Colonne etirer(double facteur) => _Colonne(
        titre: titre,
        sousTitre: sousTitre,
        largeur: largeur * facteur,
        valeur: valeur,
        texte: texte,
        matiereId: matiereId,
        estMoyenne: estMoyenne,
        estRang: estRang,
      );
}

int _plusLongMot(String titre) => titre
    .split(RegExp(r'[\s\-]+'))
    .fold<int>(0, (m, mot) => mot.length > m ? mot.length : m);

/// Taille de police d'un titre de colonne : un mot très long (« Mathématiques »)
/// est un peu réduit pour tenir sur une ligne au lieu d'être coupé en deux.
double taillePoliceTitre(String titre) {
  final n = _plusLongMot(titre);
  if (n >= 13) return 11.5;
  if (n >= 11) return 12;
  return 12.5;
}

/// Largeur d'une colonne de matière : celle par défaut, élargie si le nom
/// contient un mot long.
double largeurColonneMatiere(String nom) {
  final voulue = _plusLongMot(nom) * 7.0 + 12;
  return voulue > _largeurMatiere ? (voulue > 112 ? 112 : voulue) : _largeurMatiere;
}

/// Tableau élèves × matières pour une période.
///
/// Mois : cases modifiables, enregistrées automatiquement, avec moyenne,
/// rang et mention recalculés à chaque changement. Trimestre et année :
/// lecture seule (calculés à partir des moyennes mensuelles).
class GrilleNotes extends StatefulWidget {
  const GrilleNotes({
    super.key,
    required this.enregistrer,
    required this.matieres,
    required this.eleves,
    required this.saisies,
    required this.config,
    required this.periode,
    this.casesEvaluees = const {},
    this.moisVerrouilles = const {},
  });

  final EnregistrerNote enregistrer;
  final List<MatiereClasse> matieres;
  final List<EleveInscrit> eleves;
  final SaisiesClasse saisies;
  final ConfigResultats config;
  final Periode periode;

  /// Couples (matière, mois) dont la note du mois est calculée d'après les
  /// évaluations : la saisie directe y est interdite.
  final Set<(int, int)> casesEvaluees;

  /// Mois verrouillés pour la classe : aucune case n'y est modifiable.
  final Set<int> moisVerrouilles;

  @override
  State<GrilleNotes> createState() => _GrilleNotesState();
}

class _GrilleNotesState extends State<GrilleNotes> {
  /// Copie modifiable des saisies : inscription -> matière -> mois -> saisie.
  late final Map<int, Map<int, Map<int, Saisie>>> _saisies = {
    for (final e in widget.saisies.entries)
      e.key: {
        for (final m in e.value.entries) m.key: Map<int, Saisie>.of(m.value),
      },
  };

  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();
  final ScrollController _horizontalEntete = ScrollController();

  /// Case en cours de modification (ligne = élève, colonne = matière).
  int? _ligne;
  int? _colonne;
  String _texteCourant = '';
  String? _erreurSaisie;
  Timer? _minuterie;

  _Statut _statut = _Statut.repos;
  String? _message;
  int _enCours = 0;
  Future<void> _file = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _horizontal.addListener(_synchroniserEntete);
  }

  void _synchroniserEntete() {
    if (!_horizontalEntete.hasClients || !_horizontal.hasClients) return;
    final max = _horizontalEntete.position.maxScrollExtent;
    final cible = _horizontal.offset.clamp(0.0, max).toDouble();
    if (_horizontalEntete.offset != cible) _horizontalEntete.jumpTo(cible);
  }

  @override
  void didUpdateWidget(GrilleNotes ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.periode != widget.periode) {
      _minuterie?.cancel();
      final l = _ligne;
      final c = _colonne;
      if (l != null && c != null && ancien.periode.saisissable) {
        final lecture = _lire(c, _texteCourant);
        if (!lecture.estInvalide) {
          _appliquerLecture(l, c, ancien.periode.numero, lecture);
        }
      }
      _ligne = null;
      _colonne = null;
      _erreurSaisie = null;
    }
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    // Une frappe pas encore enregistrée (page quittée pendant la saisie) est
    // enregistrée quand même.
    final l = _ligne;
    final c = _colonne;
    if (l != null && c != null && widget.periode.saisissable) {
      final lecture = _lire(c, _texteCourant);
      if (!lecture.estInvalide) {
        final e = widget.eleves[l];
        final m = widget.matieres[c];
        final mois = widget.periode.numero;
        final ancienne = _saisies[e.inscriptionId]?[m.id]?[mois];
        if (!_memeSaisie(ancienne, lecture.saisie)) {
          widget
              .enregistrer(
                inscriptionId: e.inscriptionId,
                matiereId: m.id,
                mois: mois,
                saisie: lecture.saisie,
              )
              .catchError((Object _) {});
        }
      }
    }
    _horizontal.removeListener(_synchroniserEntete);
    _vertical.dispose();
    _horizontal.dispose();
    _horizontalEntete.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------- Saisie

  static bool _memeSaisie(Saisie? a, Saisie? b) => a == b;

  /// Contenu d'une case tel qu'on le tape : sur le barème de la matière.
  String _texteCase(int ligne, int colonne) {
    final s = _saisieDe(ligne, colonne);
    if (s == null || s.etat != EtatNote.saisie) return texteSaisie(s);
    return formaterCentiemes(_centiemesAffiches(s, widget.matieres[colonne].bareme));
  }

  /// Lit ce qui a été tapé dans la colonne [colonne], sur le barème de sa
  /// matière.
  LectureNote _lire(int colonne, String texte) =>
      lireNoteSaisie(texte, bareme: widget.matieres[colonne].bareme);

  /// Vrai si les cases de cette colonne se saisissent : un mois verrouillé ou
  /// une matière dont la note vient des évaluations est en lecture seule.
  bool _colonneEditable(int colonne) {
    if (colonne < 0 || colonne >= widget.matieres.length) return false;
    final p = widget.periode;
    if (!p.saisissable) return false;
    if (widget.moisVerrouilles.contains(p.numero)) return false;
    return !widget.casesEvaluees.contains((widget.matieres[colonne].id, p.numero));
  }

  void _ouvrir(int ligne, int colonne) {
    setState(() {
      // Une case encore ouverte est d'abord validée (clic direct sur une autre).
      _cloreCourante(_texteCourant);
      _ligne = ligne;
      _colonne = colonne;
      _texteCourant = _texteCase(ligne, colonne);
      _erreurSaisie = null;
    });
  }

  Saisie? _saisieDe(int ligne, int colonne) {
    final e = widget.eleves[ligne];
    final m = widget.matieres[colonne];
    return _saisies[e.inscriptionId]?[m.id]?[widget.periode.numero];
  }

  void _appliquer(int inscriptionId, int matiereId, int mois, Saisie? saisie) {
    if (saisie == null) {
      final parMatiere = _saisies[inscriptionId];
      parMatiere?[matiereId]?.remove(mois);
    } else {
      _saisies
          .putIfAbsent(inscriptionId, () => {})
          .putIfAbsent(matiereId, () => {})[mois] = saisie;
    }
  }

  /// La frappe est enregistrée 0,7 s après le dernier caractère tapé, sans
  /// quitter la case.
  void _auChangement(String texte) {
    _texteCourant = texte;
    _minuterie?.cancel();
    if (_erreurSaisie != null) {
      setState(() {
        _erreurSaisie = null;
        if (_statut == _Statut.erreur) _statut = _Statut.repos;
      });
    }
    _minuterie = Timer(const Duration(milliseconds: 700), _enregistrerSansQuitter);
  }

  void _enregistrerSansQuitter() {
    final l = _ligne;
    final c = _colonne;
    if (l == null || c == null) return;
    final lecture = _lire(c, _texteCourant);
    if (lecture.estInvalide) return; // l'erreur n'est signalée qu'à la validation
    setState(() => _appliquerLecture(l, c, widget.periode.numero, lecture));
  }

  /// Applique ce qui a été lu dans la case (mise à jour de l'affichage, puis
  /// enregistrement en base). À appeler dans un `setState`.
  void _appliquerLecture(int ligne, int colonne, int mois, LectureNote lecture) {
    final e = widget.eleves[ligne];
    final m = widget.matieres[colonne];
    final ancienne = _saisies[e.inscriptionId]?[m.id]?[mois];
    final nouvelle = lecture.saisie;
    if (_memeSaisie(ancienne, nouvelle)) return;
    _appliquer(e.inscriptionId, m.id, mois, nouvelle);
    // L'enregistrement est lancé après la reconstruction de l'écran.
    scheduleMicrotask(
      () => _persister(e.inscriptionId, m.id, mois, nouvelle, ancienne),
    );
  }

  void _persister(
    int inscriptionId,
    int matiereId,
    int mois,
    Saisie? nouvelle,
    Saisie? ancienne,
  ) {
    _enCours++;
    if (mounted) setState(() => _statut = _Statut.enCours);
    _file = _file.then((_) async {
      try {
        await widget.enregistrer(
          inscriptionId: inscriptionId,
          matiereId: matiereId,
          mois: mois,
          saisie: nouvelle,
        );
        _enCours--;
        if (mounted && _enCours == 0 && _statut != _Statut.erreur) {
          setState(() {
            _statut = _Statut.enregistre;
            _message = null;
          });
        }
      } catch (erreur) {
        _enCours--;
        _appliquer(inscriptionId, matiereId, mois, ancienne);
        final detail = erreur is ErreurGesco ? erreur.message : 'Erreur inattendue : $erreur';
        if (mounted) {
          setState(() {
            _statut = _Statut.erreur;
            _message = 'Note non enregistrée : $detail';
          });
        }
      }
    });
  }

  /// Valide la case ouverte (Entrée, Tab, flèches). Retourne faux si le texte
  /// est invalide : la case reste alors ouverte pour être corrigée.
  bool _valider(String texte, _Deplacement? deplacement) {
    final l = _ligne;
    final c = _colonne;
    if (l == null || c == null) return true;
    _minuterie?.cancel();
    final lecture = _lire(c, texte);
    if (lecture.estInvalide) {
      setState(() {
        _erreurSaisie = lecture.erreur;
        _statut = _Statut.erreur;
        _message = lecture.erreur;
      });
      return false;
    }
    setState(() {
      _erreurSaisie = null;
      if (_statut == _Statut.erreur) {
        _statut = _Statut.repos;
        _message = null;
      }
      _appliquerLecture(l, c, widget.periode.numero, lecture);
      final cible = deplacement == null ? null : _cibleApres(l, c, deplacement);
      _ligne = cible?.$1;
      _colonne = cible?.$2;
      if (cible != null) {
        _texteCourant = _texteCase(cible.$1, cible.$2);
      }
    });
    return true;
  }

  /// La case perd le focus (clic ailleurs) : une saisie valide est enregistrée,
  /// une saisie invalide est abandonnée avec un message.
  void _perteFocus(String texte) {
    if (_ligne == null || _colonne == null) return;
    setState(() {
      _cloreCourante(texte);
      _ligne = null;
      _colonne = null;
    });
  }

  /// Termine la saisie de la case ouverte : une saisie valide est enregistrée,
  /// une saisie invalide est abandonnée avec un message. À appeler dans un
  /// `setState` ; ne change pas la case ouverte.
  void _cloreCourante(String texte) {
    final l = _ligne;
    final c = _colonne;
    if (l == null || c == null) return;
    _minuterie?.cancel();
    final lecture = _lire(c, texte);
    if (lecture.estInvalide) {
      _statut = _Statut.erreur;
      _message = 'Note non enregistrée : ${lecture.erreur}';
    } else {
      _appliquerLecture(l, c, widget.periode.numero, lecture);
    }
    _erreurSaisie = null;
  }

  void _annuler() {
    _minuterie?.cancel();
    setState(() {
      _ligne = null;
      _colonne = null;
      _erreurSaisie = null;
      if (_statut == _Statut.erreur) {
        _statut = _Statut.repos;
        _message = null;
      }
    });
  }

  (int, int)? _cibleApres(int ligne, int colonne, _Deplacement deplacement) {
    var cible = _cibleBrute(ligne, colonne, deplacement);
    // Saute les colonnes en lecture seule (note calculée d'après les
    // évaluations) ; la boucle est bornée par le nombre de cases.
    var essais = widget.eleves.length * widget.matieres.length + 1;
    while (cible != null && !_colonneEditable(cible.$2) && essais-- > 0) {
      if (deplacement == _Deplacement.bas || deplacement == _Deplacement.haut) {
        return null;
      }
      cible = _cibleBrute(cible.$1, cible.$2, deplacement);
    }
    return cible != null && _colonneEditable(cible.$2) ? cible : null;
  }

  (int, int)? _cibleBrute(int ligne, int colonne, _Deplacement deplacement) {
    final lignes = widget.eleves.length;
    final colonnes = widget.matieres.length;
    switch (deplacement) {
      case _Deplacement.bas:
        return ligne + 1 < lignes ? (ligne + 1, colonne) : null;
      case _Deplacement.haut:
        return ligne > 0 ? (ligne - 1, colonne) : (ligne, colonne);
      case _Deplacement.droite:
        if (colonne + 1 < colonnes) return (ligne, colonne + 1);
        return ligne + 1 < lignes ? (ligne + 1, 0) : null;
      case _Deplacement.gauche:
        if (colonne > 0) return (ligne, colonne - 1);
        return ligne > 0 ? (ligne - 1, colonnes - 1) : (ligne, colonne);
    }
  }

  // ----------------------------------------------------------- Affichage

  List<_Colonne> _colonnes(MoteurResultats moteur) {
    final p = widget.periode;
    final colonnes = <_Colonne>[];
    switch (p.genre) {
      case GenrePeriode.mois:
        for (final m in widget.matieres) {
          colonnes.add(_Colonne(
            titre: m.nom,
            largeur: largeurColonneMatiere(m.nom),
            sousTitre: 'coef ${formaterCoefficient(m.coefficient)}'
                '${m.bareme == baremeParDefaut ? '' : ' · /${m.bareme}'}',
            matiereId: m.id,
            valeur: (d, r) => d.saisie(m.id, p.numero)?.centiemes,
          ));
        }
      case GenrePeriode.trimestre:
        for (final m in widget.matieres) {
          colonnes.add(_Colonne(
            titre: m.nom,
            largeur: largeurColonneMatiere(m.nom),
            sousTitre: 'coef ${formaterCoefficient(m.coefficient)}',
            valeur: (d, r) => moteur.noteMatiereTrimestre(d, m.id, p.numero),
          ));
        }
      case GenrePeriode.annee:
        for (final t in trimestres) {
          colonnes.add(_Colonne(
            titre: 'Trimestre $t',
            sousTitre: 'moyenne',
            largeur: 92,
            valeur: (d, r) => moteur.moyenneTrimestre(d, t),
          ));
        }
    }
    colonnes.add(_Colonne(
      titre: p.genre == GenrePeriode.annee ? 'Moy. annuelle' : 'Moyenne',
      sousTitre: p.genre == GenrePeriode.annee ? null : 'sur 20',
      largeur: 88,
      valeur: (d, r) => r.moyenne,
      estMoyenne: true,
    ));
    colonnes.add(const _Colonne(titre: 'Rang', largeur: 64, estRang: true));
    colonnes.add(_Colonne(
      titre: 'Mention',
      largeur: 108,
      texte: (d, r) => r.mention,
    ));
    if (p.genre != GenrePeriode.mois) {
      colonnes.add(_Colonne(
        titre: 'Décision',
        largeur: 180,
        texte: (d, r) => r.decision,
      ));
    }
    return colonnes;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.periode;
    final donnees = [
      for (final e in widget.eleves)
        DonneesEleve(
          inscriptionId: e.inscriptionId,
          nom: e.nom,
          prenom: e.prenom,
          sexe: e.sexe,
          saisies: _saisies[e.inscriptionId] ?? const {},
          actif: e.actif,
        ),
    ];
    final moteur = MoteurResultats(
      matieres: [for (final m in widget.matieres) m.versCoef()],
      eleves: donnees,
      config: widget.config,
    );
    final resultats = switch (p.genre) {
      GenrePeriode.mois => moteur.resultatsMois(p.numero),
      GenrePeriode.trimestre => moteur.resultatsTrimestre(p.numero),
      GenrePeriode.annee => moteur.resultatsAnnee(),
    };
    final parId = {for (final r in resultats) r.inscriptionId: r};
    final effectifsRang = <int, int>{};
    for (final r in resultats) {
      final rang = r.rang;
      if (rang != null) effectifsRang[rang] = (effectifsRang[rang] ?? 0) + 1;
    }
    final stats = calculerStats(
      eleves: donnees,
      resultats: resultats,
      config: widget.config,
    );
    final colonnesBase = _colonnes(moteur);
    final largeurBase = colonnesBase.fold<double>(0, (s, c) => s + c.largeur);

    final comportement = ScrollConfiguration.of(context).copyWith(
      dragDevices: {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BandeauResume(
          periode: p,
          stats: stats,
          saisies: _compterCases(p),
          totalCases: widget.eleves.length * widget.matieres.length,
          statut: _statut,
          message: _message,
        ),
        Expanded(
          child: ScrollConfiguration(
            behavior: comportement,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: CouleursGesco.bordure),
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: LayoutBuilder(
                builder: (context, contraintes) {
                  // Si le tableau est plus étroit que l'écran, les colonnes
                  // s'élargissent pour le remplir ; sinon il défile.
                  final disponible = contraintes.maxWidth - _largeurNom;
                  final facteur =
                      disponible > largeurBase ? disponible / largeurBase : 1.0;
                  final colonnes = facteur == 1.0
                      ? colonnesBase
                      : [for (final c in colonnesBase) c.etirer(facteur)];
                  final largeurTotale = largeurBase * facteur;
                  return Column(
                children: [
                  _entete(colonnes),
                  const Divider(height: 1),
                  Expanded(
                    child: Scrollbar(
                      controller: _vertical,
                      child: SingleChildScrollView(
                        controller: _vertical,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: _largeurNom,
                              child: Column(
                                children: [
                                  for (var l = 0; l < widget.eleves.length; l++)
                                    _caseNom(widget.eleves[l]),
                                  _caseNomPied(),
                                ],
                              ),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _horizontal,
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: largeurTotale,
                                  child: Column(
                                    children: [
                                      for (var l = 0; l < widget.eleves.length; l++)
                                        _ligneEleve(
                                          l,
                                          colonnes,
                                          donnees[l],
                                          parId[donnees[l].inscriptionId]!,
                                          effectifsRang,
                                        ),
                                      _lignePied(colonnes, donnees, parId),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  int _compterCases(Periode p) {
    if (!p.saisissable) return 0;
    var n = 0;
    for (final e in widget.eleves) {
      for (final m in widget.matieres) {
        if (_saisies[e.inscriptionId]?[m.id]?[p.numero] != null) n++;
      }
    }
    return n;
  }

  Widget _entete(List<_Colonne> colonnes) {
    return Container(
      color: CouleursGesco.grisClair,
      height: _hauteurEntete,
      child: Row(
        children: [
          const SizedBox(
            width: _largeurNom,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Élève',
                style: TextStyle(fontWeight: FontWeight.w700, color: CouleursGesco.texte),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _horizontalEntete,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: [
                  for (final c in colonnes)
                    Container(
                      width: c.largeur,
                      height: _hauteurEntete,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            c.titre,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: taillePoliceTitre(c.titre),
                              color: CouleursGesco.texte,
                            ),
                          ),
                          if (c.sousTitre != null)
                            Text(
                              c.sousTitre!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: CouleursGesco.gris,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _caseNom(EleveInscrit e) {
    return Container(
      height: _hauteurLigne,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CouleursGesco.bordure)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.nomComplet,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
          Text(
            e.matricule,
            style: const TextStyle(color: CouleursGesco.gris, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  Widget _caseNomPied() {
    return Container(
      height: _hauteurLigne - 8,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      color: CouleursGesco.grisClair,
      child: const Text(
        'Moyenne de la classe',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }

  Widget _ligneEleve(
    int l,
    List<_Colonne> colonnes,
    DonneesEleve d,
    ResultatEleve r,
    Map<int, int> effectifsRang,
  ) {
    return Container(
      height: _hauteurLigne,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CouleursGesco.bordure)),
      ),
      child: Row(
        children: [
          for (var c = 0; c < colonnes.length; c++)
            _cellule(l, c, colonnes[c], d, r, effectifsRang),
        ],
      ),
    );
  }

  Widget _cellule(
    int l,
    int c,
    _Colonne col,
    DonneesEleve d,
    ResultatEleve r,
    Map<int, int> effectifsRang,
  ) {
    final saisissable = col.matiereId != null && widget.periode.saisissable;
    final editable = saisissable && _colonneEditable(c);
    Widget contenu;
    if (saisissable && !editable) {
      contenu = _caseLecture(l, c, d.saisie(col.matiereId!, widget.periode.numero));
    } else if (editable) {
      if (_ligne == l && _colonne == c) {
        contenu = _ChampNote(
          key: const Key('champ_note'),
          texteInitial: _texteCourant,
          invalide: _erreurSaisie != null,
          surChangement: _auChangement,
          surValidation: (texte, dep) => _valider(texte, dep),
          surPerteFocus: _perteFocus,
          surAnnulation: _annuler,
        );
      } else {
        contenu = _caseNote(l, c, d.saisie(col.matiereId!, widget.periode.numero));
      }
    } else if (col.estRang) {
      contenu = _caseRang(l, r, effectifsRang);
    } else if (col.valeur != null) {
      contenu = _caseNombre(l, c, col, col.valeur!(d, r), r);
    } else {
      final texte = col.texte!(d, r);
      contenu = Text(
        texte.isEmpty ? '—' : texte,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.5,
          color: texte.isEmpty ? CouleursGesco.gris : CouleursGesco.texte,
        ),
      );
    }
    return Container(
      width: col.largeur,
      height: _hauteurLigne,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: CouleursGesco.bordure)),
      ),
      child: contenu,
    );
  }

  Widget _caseNote(int l, int c, Saisie? s) {
    Widget contenu;
    Color? fond;
    if (s == null) {
      contenu = const SizedBox.shrink();
      fond = const Color(0xFFF8F9FC);
    } else if (s.etat == EtatNote.saisie) {
      final v = s.centiemes!;
      contenu = Text(
        formaterCentiemes(_centiemesAffiches(s, widget.matieres[c].bareme)),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14.5,
          color: couleurNiveau(widget.config.niveau(v)),
        ),
      );
    } else {
      contenu = Text(
        texteSaisie(s),
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: CouleursGesco.gris,
          fontStyle: FontStyle.italic,
        ),
      );
      fond = CouleursGesco.grisClair;
    }
    return Material(
      color: fond ?? Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: Key('case_${l}_$c'),
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(8),
        onTap: () => _ouvrir(l, c),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Center(child: contenu),
        ),
      ),
    );
  }

  /// Case non modifiable d'une matière : mois verrouillé ou note calculée
  /// d'après les évaluations (affichée sur le barème de la matière).
  Widget _caseLecture(int l, int c, Saisie? s) {
    final m = widget.matieres[c];
    final mois = widget.periode.numero;
    final evaluee = widget.casesEvaluees.contains((m.id, mois));
    final verrouille = widget.moisVerrouilles.contains(mois);
    Widget contenu;
    if (s == null) {
      contenu = const Text('—', style: TextStyle(color: CouleursGesco.gris));
    } else if (s.etat == EtatNote.saisie) {
      final v = s.centiemes!;
      contenu = Text(
        formaterCentiemes(_centiemesAffiches(s, m.bareme)),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14.5,
          color: couleurNiveau(widget.config.niveau(v)),
        ),
      );
    } else {
      contenu = Text(
        texteSaisie(s),
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: CouleursGesco.gris,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    final explication = evaluee
        ? 'Note calculée d\'après les évaluations de ${m.nom} : modifiez les '
            'notes des évaluations.'
        : verrouille
            ? '${libelleMois(mois)} est verrouillé : déverrouillez le mois pour '
                'modifier les notes.'
            : '';
    return Tooltip(
      message: explication,
      child: Container(
        key: Key('case_lecture_${l}_$c'),
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: evaluee ? CouleursGesco.bleuClair : CouleursGesco.grisClair,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(child: contenu),
            if (evaluee || verrouille)
              Positioned(
                top: 2,
                right: 4,
                child: Icon(
                  evaluee ? Icons.functions : Icons.lock_outline,
                  size: 11,
                  color: CouleursGesco.gris,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _caseNombre(int l, int c, _Colonne col, int? valeur, ResultatEleve r) {
    if (valeur == null) {
      return const Text('—', style: TextStyle(color: CouleursGesco.gris));
    }
    final niveau = widget.config.niveau(valeur);
    final texte = Text(
      formaterCentiemes(valeur),
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: col.estMoyenne ? 14.5 : 13.5,
        color: couleurNiveau(niveau),
      ),
    );
    if (!col.estMoyenne) return texte;
    // FittedBox : si la police est plus large que prévu, le contenu se
    // réduit au lieu de déborder de la case.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            key: Key('moyenne_$l'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: fondNiveau(niveau),
              borderRadius: BorderRadius.circular(8),
            ),
            child: texte,
          ),
          if (r.incomplet)
            const Tooltip(
              message: 'Des notes manquent : moyenne calculée sur les notes saisies.',
              child: Padding(
                padding: EdgeInsets.only(left: 3),
                child: Text(
                  '*',
                  style: TextStyle(
                    color: CouleursGesco.orange,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _caseRang(int l, ResultatEleve r, Map<int, int> effectifsRang) {
    final rang = r.rang;
    if (rang == null) {
      return const Text('—', style: TextStyle(color: CouleursGesco.gris));
    }
    final exAequo = (effectifsRang[rang] ?? 0) > 1;
    return Column(
      key: Key('rang_$l'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formaterRang(rang),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        if (exAequo)
          const Text(
            'ex æquo',
            style: TextStyle(fontSize: 10.5, color: CouleursGesco.gris),
          ),
      ],
    );
  }

  Widget _lignePied(
    List<_Colonne> colonnes,
    List<DonneesEleve> donnees,
    Map<int, ResultatEleve> parId,
  ) {
    return Container(
      height: _hauteurLigne - 8,
      color: CouleursGesco.grisClair,
      child: Row(
        children: [
          for (final col in colonnes)
            Container(
              width: col.largeur,
              alignment: Alignment.center,
              child: _piedColonne(col, donnees, parId),
            ),
        ],
      ),
    );
  }

  Widget _piedColonne(
    _Colonne col,
    List<DonneesEleve> donnees,
    Map<int, ResultatEleve> parId,
  ) {
    final calcul = col.valeur;
    if (calcul == null) return const SizedBox.shrink();
    final moyenne = moyenneDe([
      for (final d in donnees) calcul(d, parId[d.inscriptionId]!),
    ]);
    if (moyenne == null) {
      return const Text('—', style: TextStyle(color: CouleursGesco.gris));
    }
    return Text(
      formaterCentiemes(moyenne),
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 13.5,
        color: couleurNiveau(widget.config.niveau(moyenne)),
      ),
    );
  }
}

/// Champ de saisie d'une case : une seule case est modifiable à la fois.
class _ChampNote extends StatefulWidget {
  const _ChampNote({
    super.key,
    required this.texteInitial,
    required this.invalide,
    required this.surChangement,
    required this.surValidation,
    required this.surPerteFocus,
    required this.surAnnulation,
  });

  final String texteInitial;
  final bool invalide;
  final ValueChanged<String> surChangement;

  /// Retourne faux si le texte est refusé (la case reste ouverte).
  final bool Function(String texte, _Deplacement? deplacement) surValidation;
  final ValueChanged<String> surPerteFocus;
  final VoidCallback surAnnulation;

  @override
  State<_ChampNote> createState() => _ChampNoteState();
}

class _ChampNoteState extends State<_ChampNote> {
  late final TextEditingController _controleur;
  late final FocusNode _focus;
  bool _termine = false;

  @override
  void initState() {
    super.initState();
    _controleur = TextEditingController(text: widget.texteInitial);
    _controleur.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.texteInitial.length,
    );
    _focus = FocusNode()..addListener(_surFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _surFocus() {
    if (mounted && !_focus.hasFocus && !_termine) {
      _termine = true;
      widget.surPerteFocus(_controleur.text);
    }
  }

  void _valider(_Deplacement? deplacement) {
    if (_termine) return;
    final accepte = widget.surValidation(_controleur.text, deplacement);
    if (accepte) _termine = true;
  }

  KeyEventResult _touche(FocusNode noeud, KeyEvent evenement) {
    if (evenement is! KeyDownEvent) return KeyEventResult.ignored;
    final touche = evenement.logicalKey;
    if (touche == LogicalKeyboardKey.arrowDown) {
      _valider(_Deplacement.bas);
    } else if (touche == LogicalKeyboardKey.arrowUp) {
      _valider(_Deplacement.haut);
    } else if (touche == LogicalKeyboardKey.tab) {
      _valider(
        HardwareKeyboard.instance.isShiftPressed
            ? _Deplacement.gauche
            : _Deplacement.droite,
      );
    } else if (touche == LogicalKeyboardKey.escape) {
      _termine = true;
      widget.surAnnulation();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _focus.removeListener(_surFocus);
    _focus.dispose();
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final couleur = widget.invalide ? CouleursGesco.rouge : CouleursGesco.bleu;
    OutlineInputBorder trait() => OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: couleur, width: 2),
        );
    return Focus(
      onKeyEvent: _touche,
      child: TextField(
        controller: _controleur,
        focusNode: _focus,
        textAlign: TextAlign.center,
        textInputAction: TextInputAction.next,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,A-Za-zéÉèÈêÊ]')),
          LengthLimitingTextInputFormatter(10),
        ],
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          border: trait(),
          enabledBorder: trait(),
          focusedBorder: trait(),
        ),
        onChanged: widget.surChangement,
        onEditingComplete: () {},
        onSubmitted: (texte) => _valider(_Deplacement.bas),
        onTapOutside: (_) => _focus.unfocus(),
      ),
    );
  }
}

/// Bandeau au-dessus du tableau : avancement de la saisie, statistiques de la
/// classe et état de l'enregistrement automatique.
class _BandeauResume extends StatelessWidget {
  const _BandeauResume({
    required this.periode,
    required this.stats,
    required this.saisies,
    required this.totalCases,
    required this.statut,
    required this.message,
  });

  final Periode periode;
  final StatsClasse stats;
  final int saisies;
  final int totalCases;
  final _Statut statut;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final pourcentage = totalCases == 0 ? 0.0 : saisies / totalCases;
    final taux = stats.tauxReussiteCentiemes;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (periode.saisissable)
                SizedBox(
                  width: 260,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${periode.libelle} : $saisies / $totalCases cases renseignées',
                        key: const Key('avancement'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pourcentage,
                          minHeight: 6,
                          color: CouleursGesco.bleu,
                          backgroundColor: CouleursGesco.bleuClair,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  '${periode.libelle} : lecture seule. Les notes se saisissent '
                  'mois par mois ; les moyennes sont calculées automatiquement.',
                  style: const TextStyle(color: CouleursGesco.gris, fontSize: 13),
                ),
              _Pastille(
                'Moyenne de la classe',
                formaterCentiemes(stats.moyenneClasse),
              ),
              _Pastille(
                'Admis',
                stats.evalues == 0 ? '—' : '${stats.admis} sur ${stats.evalues}',
              ),
              _Pastille(
                'Taux de réussite',
                taux == null ? '—' : '${formaterCentiemes(taux)} %',
              ),
              _Pastille('Meilleure', formaterCentiemes(stats.meilleureMoyenne)),
              _Pastille('Plus faible', formaterCentiemes(stats.plusFaibleMoyenne)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _Etat(statut: statut, message: message, saisissable: periode.saisissable)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille(this.libelle, this.valeur);

  final String libelle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: CouleursGesco.bordure),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$libelle : ',
            style: const TextStyle(color: CouleursGesco.gris, fontSize: 12.5),
          ),
          Text(
            valeur,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Ligne d'état : aide à la saisie ou résultat de l'enregistrement.
class _Etat extends StatelessWidget {
  const _Etat({
    required this.statut,
    required this.message,
    required this.saisissable,
  });

  final _Statut statut;
  final String? message;
  final bool saisissable;

  @override
  Widget build(BuildContext context) {
    if (!saisissable) return const SizedBox.shrink();
    switch (statut) {
      case _Statut.enCours:
        return const _LigneEtat(
          key: Key('statut_enregistrement'),
          icone: Icons.sync,
          couleur: CouleursGesco.bleu,
          texte: 'Enregistrement…',
        );
      case _Statut.enregistre:
        return const _LigneEtat(
          key: Key('statut_enregistrement'),
          icone: Icons.check_circle,
          couleur: CouleursGesco.vert,
          texte: 'Enregistré automatiquement',
        );
      case _Statut.erreur:
        return _LigneEtat(
          key: const Key('statut_enregistrement'),
          icone: Icons.error_outline,
          couleur: CouleursGesco.rouge,
          texte: message ?? 'Erreur',
        );
      case _Statut.repos:
        return const _LigneEtat(
          key: Key('statut_enregistrement'),
          icone: Icons.edit_outlined,
          couleur: CouleursGesco.gris,
          texte: 'Cliquez sur une case et tapez la note (0 à 20, virgule acceptée). '
              'A = absent, D = dispensé, case vide = non saisie. '
              'Entrée valide et passe à l\'élève suivant. Enregistrement automatique.',
        );
    }
  }
}

class _LigneEtat extends StatelessWidget {
  const _LigneEtat({
    super.key,
    required this.icone,
    required this.couleur,
    required this.texte,
  });

  final IconData icone;
  final Color couleur;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 16, color: couleur),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            texte,
            style: TextStyle(color: couleur, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}
