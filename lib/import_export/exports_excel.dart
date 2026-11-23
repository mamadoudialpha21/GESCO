/// Construction des feuilles Excel exportées : élèves, notes, résultats,
/// classements, absences, statistiques, admis et non admis.
///
/// Chaque fonction transforme des données déjà chargées en [FeuilleEcrite] ;
/// rien n'est lu dans la base ici, ce qui permet de tout tester sans fichier.
/// Les notes et moyennes sont exportées comme des nombres (sur 20, deux
/// décimales) : Excel peut donc les trier et les additionner.
library;

import '../app/calcul_classe.dart';
import '../data/modeles_absences.dart';
import '../data/modeles_donnees.dart';
import '../domain/arrondi.dart';
import '../domain/calendrier.dart';
import '../domain/periodes.dart';
import '../tableur/classeur.dart';
import 'modele_export.dart';

/// Une ligne de cellules (les cellules null restent vides).
typedef Ligne = List<CelluleEcrite?>;

/// Une classe et l'étendue (mois, période ou année) sur laquelle on l'exporte.
class ClassePortee {
  const ClassePortee(this.calcul, this.portee);

  final CalculClasse calcul;
  final Portee portee;
}

// ---------------------------------------------------------------- Cellules

CelluleEcrite _t(String s, [StyleCellule style = StyleCellule.normal]) =>
    CelluleEcrite(s, style);

CelluleEcrite _h(String s) => CelluleEcrite(s, StyleCellule.entete);

CelluleEcrite _c(Object? v) => CelluleEcrite(v, StyleCellule.centre);

CelluleEcrite _i(int n) => CelluleEcrite(n, StyleCellule.entier);

/// Note ou moyenne en centièmes -> nombre sur 20 ; case vide sans note.
CelluleEcrite? _n(int? centiemes) =>
    centiemes == null ? null : CelluleEcrite(centiemes / 100, StyleCellule.note);

/// Date « AAAA-MM-JJ » -> cellule date ; le texte brut s'il n'est pas lisible.
CelluleEcrite _d(String? iso) {
  if (iso == null || iso.isEmpty) return const CelluleEcrite(null);
  final d = DateTime.tryParse(iso);
  if (d == null) return CelluleEcrite(iso);
  return CelluleEcrite(DateTime(d.year, d.month, d.day), StyleCellule.date);
}

/// Coefficient en centièmes -> « 1 », « 1,5 »...
String _decimal(int centiemes) => centiemes % 100 == 0
    ? '${centiemes ~/ 100}'
    : (centiemes / 100).toString().replaceAll('.', ',');

/// Nom d'une étendue : « Novembre », « Trimestre 1 », « Année entière ».
String libellePortee(Portee p) {
  if (p.annuelle) return 'Année entière';
  if (p.estMois) return libelleMois(p.moisChoisi!);
  return p.periodeChoisie!.libelle;
}

/// Trois lignes d'en-tête : établissement, titre du document, année et date.
List<Ligne> _tete(ContexteExport ctx, String titre, {String detail = ''}) => [
      [_t(ctx.etablissement.isEmpty ? 'Établissement' : ctx.etablissement, StyleCellule.titre)],
      [_t(titre, StyleCellule.etiquette)],
      [
        _t(
          [
            if (ctx.annee.isNotEmpty) 'Année scolaire ${ctx.annee}',
            if (detail.isNotEmpty) detail,
            'Édité le ${dateFr(ctx.date)}',
          ].join('  ·  '),
          StyleCellule.discret,
        ),
      ],
      <CelluleEcrite?>[],
    ];

String _nomClasse(CalculClasse c) => c.classe.classe.nom;

// ------------------------------------------------------------------ Élèves

/// Colonnes de la liste des élèves. Ce sont aussi celles qu'attend l'import
/// des élèves : une liste exportée peut être corrigée puis réimportée.
const List<String> colonnesEleves = [
  'N°',
  'Matricule',
  'Nom',
  'Prénom',
  'Sexe',
  'Date de naissance',
  'Lieu de naissance',
  'Adresse',
  'Téléphone',
  'Nom du père',
  'Nom de la mère',
  'Contact des parents',
  'Nom du tuteur',
  'Contact du tuteur',
  'Classe',
  'Année scolaire',
  'Situation',
];

/// Liste des élèves (toute l'école ou une classe), une ligne par élève.
FeuilleEcrite feuilleEleves(
  ContexteExport ctx,
  String nomFeuille,
  String titre,
  List<EleveExport> eleves,
) {
  final lignes = _tete(ctx, titre, detail: '${eleves.length} élève${eleves.length > 1 ? 's' : ''}')
    ..add([for (final h in colonnesEleves) _h(h)]);
  for (var k = 0; k < eleves.length; k++) {
    final e = eleves[k].eleve;
    final ins = eleves[k].inscription;
    lignes.add([
      _i(k + 1),
      _t(e.matricule),
      _t(e.nom),
      _t(e.prenom),
      _c(e.sexe),
      _d(e.dateNaissance),
      _t(e.lieuNaissance),
      _t(e.adresse),
      _t(e.telephone),
      _t(e.nomPere),
      _t(e.nomMere),
      _t(e.contactParent),
      _t(e.nomTuteur),
      _t(e.contactTuteur),
      _t(ins.classeNom),
      _t(ctx.annee),
      _t(ins.statut.libelle),
    ]);
  }
  return FeuilleEcrite(
    nomOngletValide(nomFeuille),
    lignes,
    largeurs: const [5, 14, 20, 20, 7, 14, 18, 24, 14, 20, 20, 16, 20, 16, 12, 12, 10],
  );
}

// ------------------------------------------------------------------- Notes

/// Notes d'une matière : une ligne par élève, une colonne par mois, puis la
/// moyenne de chaque période, la moyenne annuelle et le rang dans la matière.
FeuilleEcrite feuilleNotesMatiere(ContexteExport ctx, CalculClasse c, MatiereClasse m) {
  final periodes = c.calendrier.periodes;
  final lignes = _tete(
    ctx,
    'Notes de ${m.nom}',
    detail: 'Classe ${_nomClasse(c)}  ·  coefficient ${_decimal(m.coefficient)}  ·  notes sur 20',
  )..add([
      _h('N°'),
      _h('Matricule'),
      _h('Nom'),
      _h('Prénom'),
      for (final mois in moisScolaires) _h(libelleMois(mois)),
      for (final p in periodes) _h('Moyenne ${p.libelle}'),
      _h('Moyenne annuelle'),
      _h('Rang annuel'),
    ]);
  final rangs = {
    for (final r in c.moteur.classementMatiere(m.id, const Portee.annee())) r.inscriptionId: r.rang,
  };
  var numero = 0;
  for (var k = 0; k < c.eleves.length; k++) {
    final e = c.eleves[k];
    if (!e.actif) continue;
    final d = c.donnees[k];
    numero++;
    final rang = rangs[e.inscriptionId];
    lignes.add([
      _i(numero),
      _t(e.matricule),
      _t(e.nom),
      _t(e.prenom),
      for (final mois in moisScolaires) _n(c.moteur.noteMatiere(d, m.id, Portee.mois(mois))),
      for (final p in periodes) _n(c.moteur.noteMatiere(d, m.id, Portee.periode(p))),
      _n(c.moteur.noteMatiere(d, m.id, const Portee.annee())),
      rang == null ? null : _i(rang),
    ]);
  }
  return FeuilleEcrite(
    nomOngletValide('Notes ${m.nom}'),
    lignes,
    largeurs: [5, 14, 20, 20, for (var i = 0; i < moisScolaires.length + periodes.length; i++) 11, 12, 10],
  );
}

/// Notes d'une classe sur une étendue : une colonne par matière, puis la
/// moyenne, le rang, la mention et la décision.
FeuilleEcrite feuilleNotesClasse(ContexteExport ctx, CalculClasse c, Portee portee) {
  final resultats = {for (final r in c.resultats(portee)) r.inscriptionId: r};
  final lignes = _tete(
    ctx,
    'Notes de la classe ${_nomClasse(c)}',
    detail: libellePortee(portee),
  )..add([
      _h('N°'),
      _h('Matricule'),
      _h('Nom'),
      _h('Prénom'),
      for (final m in c.matieres)
        _h('${m.nom}\ncoef. ${_decimal(m.coefficient)}${m.facultative ? ' (facultative)' : ''}'),
      _h('Moyenne'),
      _h('Rang'),
      _h('Mention'),
      _h('Décision'),
    ]);
  var numero = 0;
  for (var k = 0; k < c.eleves.length; k++) {
    final e = c.eleves[k];
    if (!e.actif) continue;
    final d = c.donnees[k];
    numero++;
    final r = resultats[e.inscriptionId];
    final rang = r?.rang;
    lignes.add([
      _i(numero),
      _t(e.matricule),
      _t(e.nom),
      _t(e.prenom),
      for (final m in c.matieres) _n(c.moteur.noteMatiere(d, m.id, portee)),
      _n(r?.moyenne),
      rang == null ? null : _i(rang),
      _t(r?.mention ?? ''),
      _t(r?.decision ?? ''),
    ]);
  }
  return FeuilleEcrite(
    nomOngletValide('Classe ${_nomClasse(c)}'),
    lignes,
    largeurs: [5, 14, 20, 20, for (var i = 0; i < c.matieres.length; i++) 13, 10, 7, 14, 22],
  );
}

// ---------------------------------------------------------------- Résultats

String _remarque(EleveInscrit e, bool incomplet) {
  if (!e.actif) return e.statut.libelle;
  return incomplet ? 'Notes incomplètes' : '';
}

/// Résultats d'une classe sur une étendue : moyenne, rang, mention, décision.
/// Pour l'année entière, la moyenne de chaque période est ajoutée.
FeuilleEcrite feuilleResultats(ContexteExport ctx, CalculClasse c, Portee portee) {
  final resultats = {for (final r in c.resultats(portee)) r.inscriptionId: r};
  final periodes = portee.annuelle ? c.calendrier.periodes : const <PeriodeScolaire>[];
  final lignes = _tete(
    ctx,
    portee.annuelle ? 'Résultats annuels' : 'Résultats : ${libellePortee(portee)}',
    detail: 'Classe ${_nomClasse(c)}',
  )..add([
      _h('N°'),
      _h('Matricule'),
      _h('Nom'),
      _h('Prénom'),
      _h('Sexe'),
      for (final p in periodes) _h('Moyenne ${p.libelle}'),
      _h(portee.annuelle ? 'Moyenne annuelle' : 'Moyenne'),
      _h('Rang'),
      _h('Mention'),
      _h('Décision'),
      _h('Remarque'),
    ]);
  for (var k = 0; k < c.eleves.length; k++) {
    final e = c.eleves[k];
    final d = c.donnees[k];
    final r = resultats[e.inscriptionId];
    final rang = r?.rang;
    lignes.add([
      _i(k + 1),
      _t(e.matricule),
      _t(e.nom),
      _t(e.prenom),
      _c(e.sexe),
      for (final p in periodes) _n(c.moteur.moyenne(d, Portee.periode(p))),
      _n(r?.moyenne),
      rang == null ? null : _i(rang),
      _t(r?.mention ?? ''),
      _t(r?.decision ?? ''),
      _t(_remarque(e, r?.incomplet ?? false)),
    ]);
  }
  return FeuilleEcrite(
    nomOngletValide('Résultats ${_nomClasse(c)}'),
    lignes,
    largeurs: [5, 14, 20, 20, 7, for (var i = 0; i < periodes.length; i++) 13, 12, 7, 14, 22, 18],
  );
}

// -------------------------------------------------------------- Classements

/// Classement d'une classe (moyenne générale ou note d'une [matiere]) : les
/// classés par rang, puis les élèves sans rang.
FeuilleEcrite feuilleClassement(
  ContexteExport ctx,
  CalculClasse c,
  Portee portee, {
  MatiereClasse? matiere,
}) {
  final classement = lignesClassement(c, portee, matiereId: matiere?.id);
  final lignes = _tete(
    ctx,
    matiere == null ? 'Classement général' : 'Classement en ${matiere.nom}',
    detail: 'Classe ${_nomClasse(c)}  ·  ${libellePortee(portee)}',
  )..add([
      _h('Rang'),
      _h('Ex æquo'),
      _h('Matricule'),
      _h('Nom'),
      _h('Prénom'),
      _h('Sexe'),
      _h(matiere == null ? 'Moyenne' : 'Note'),
      _h('Mention'),
      if (matiere == null) _h('Décision'),
      _h('Remarque'),
    ]);
  for (final l in classement) {
    final rang = l.rang;
    lignes.add([
      rang == null ? null : _i(rang),
      _c(l.exAequo ? 'oui' : ''),
      _t(l.eleve.matricule),
      _t(l.eleve.nom),
      _t(l.eleve.prenom),
      _c(l.eleve.sexe),
      _n(l.moyenne),
      _t(l.mention),
      if (matiere == null) _t(l.decision),
      _t(_remarque(l.eleve, l.incomplet)),
    ]);
  }
  return FeuilleEcrite(
    nomOngletValide(matiere == null ? 'Classement ${_nomClasse(c)}' : '${matiere.nom} ${_nomClasse(c)}'),
    lignes,
    largeurs: [7, 9, 14, 20, 20, 7, 11, 14, if (matiere == null) 22, 18],
  );
}

// ----------------------------------------------------------------- Absences

/// Absences et retards : totaux par élève, puis détail jour par jour.
List<FeuilleEcrite> feuillesAbsences(
  ContexteExport ctx,
  List<EleveInscrit> eleves,
  Map<int, TotauxAbsences> totaux,
  List<Absence> detail,
) {
  final lignes = _tete(ctx, 'Absences et retards : totaux par élève')
    ..add([
      _h('Classe'),
      _h('Matricule'),
      _h('Nom'),
      _h('Prénom'),
      _h('Absences (jours)'),
      _h('dont justifiées'),
      _h('dont injustifiées'),
      _h('Retards'),
      _h('dont justifiés'),
      _h('Minutes de retard'),
    ]);
  var absences = 0, justifiees = 0, retards = 0, retardsJ = 0, minutes = 0;
  for (final e in eleves) {
    final t = totaux[e.inscriptionId] ?? const TotauxAbsences();
    absences += t.absences;
    justifiees += t.absencesJustifiees;
    retards += t.retards;
    retardsJ += t.retardsJustifies;
    minutes += t.minutesRetard;
    lignes.add([
      _t(e.classeNom),
      _t(e.matricule),
      _t(e.nom),
      _t(e.prenom),
      _i(t.absences),
      _i(t.absencesJustifiees),
      _i(t.absencesInjustifiees),
      _i(t.retards),
      _i(t.retardsJustifies),
      _i(t.minutesRetard),
    ]);
  }
  lignes.add([
    _t('TOTAL', StyleCellule.etiquette),
    null,
    null,
    null,
    _i(absences),
    _i(justifiees),
    _i(absences - justifiees),
    _i(retards),
    _i(retardsJ),
    _i(minutes),
  ]);

  final jours = _tete(ctx, 'Absences et retards : détail')
    ..add([
      _h('Date'),
      _h('Classe'),
      _h('Matricule'),
      _h('Nom et prénom'),
      _h('Type'),
      _h('Justifiée'),
      _h('Durée (min)'),
      _h('Motif'),
    ]);
  for (final a in detail) {
    final minutesRetard = a.dureeMinutes;
    jours.add([
      _d(a.date),
      _t(a.classeNom),
      _t(a.matricule),
      _t(a.eleveNom),
      _t(a.type.libelle),
      _c(a.justifiee ? 'Oui' : 'Non'),
      minutesRetard == null ? null : _i(minutesRetard),
      _t(a.motif),
    ]);
  }
  return [
    FeuilleEcrite(
      'Totaux',
      lignes,
      largeurs: const [12, 14, 20, 20, 12, 12, 12, 9, 12, 12],
    ),
    FeuilleEcrite(
      'Détail',
      jours,
      largeurs: const [12, 12, 14, 28, 10, 10, 11, 34],
    ),
  ];
}

// -------------------------------------------------------------- Statistiques

/// Statistiques générales : une feuille pour l'établissement, une ligne par
/// classe sur la seconde.
List<FeuilleEcrite> feuillesStatistiques(
  ContexteExport ctx,
  List<ClassePortee> classes, {
  required String libelle,
}) {
  var effectif = 0, filles = 0, garcons = 0, evalues = 0, admis = 0, nonAdmis = 0;
  var somme = 0, nbMoyennes = 0;
  int? meilleure, faible;
  final parClasse = _tete(ctx, 'Statistiques par classe', detail: libelle)
    ..add([
      _h('Classe'),
      _h('Effectif'),
      _h('Filles'),
      _h('Garçons'),
      _h('Évalués'),
      _h('Admis'),
      _h('Non admis'),
      _h('Taux de réussite (%)'),
      _h('Moyenne de la classe'),
      _h('Meilleure moyenne'),
      _h('Plus faible moyenne'),
    ]);
  for (final cp in classes) {
    final s = cp.calcul.stats(cp.portee);
    effectif += s.effectif;
    filles += s.filles;
    garcons += s.garcons;
    evalues += s.evalues;
    admis += s.admis;
    nonAdmis += s.nonAdmis;
    final moyenne = s.moyenneClasse;
    final inactifs = {
      for (final d in cp.calcul.donnees)
        if (!d.actif) d.inscriptionId,
    };
    for (final r in cp.calcul.resultats(cp.portee)) {
      final m = r.moyenne;
      if (m != null && !inactifs.contains(r.inscriptionId)) {
        somme += m;
        nbMoyennes++;
      }
    }
    final haut = s.meilleureMoyenne;
    if (haut != null && (meilleure == null || haut > meilleure)) meilleure = haut;
    final bas = s.plusFaibleMoyenne;
    if (bas != null && (faible == null || bas < faible)) faible = bas;
    final taux = s.tauxReussiteCentiemes;
    parClasse.add([
      _t(_nomClasse(cp.calcul)),
      _i(s.effectif),
      _i(s.filles),
      _i(s.garcons),
      _i(s.evalues),
      _i(s.admis),
      _i(s.nonAdmis),
      _n(taux),
      _n(moyenne),
      _n(haut),
      _n(bas),
    ]);
  }

  final tauxGlobal = evalues == 0 ? null : divisionArrondie(admis * 10000, evalues);
  final moyenneGenerale = nbMoyennes == 0 ? null : divisionArrondie(somme, nbMoyennes);
  Ligne valeur(String etiquette, CelluleEcrite? v) => [_t(etiquette, StyleCellule.etiquette), v];
  final ecole = _tete(ctx, 'Statistiques générales de l\'établissement', detail: libelle)
    ..add([_h('Indicateur'), _h('Valeur')])
    ..add(valeur('Nombre de classes', _i(classes.length)))
    ..add(valeur('Élèves inscrits', _i(effectif)))
    ..add(valeur('dont filles', _i(filles)))
    ..add(valeur('dont garçons', _i(garcons)))
    ..add(valeur('Élèves évalués', _i(evalues)))
    ..add(valeur('Admis', _i(admis)))
    ..add(valeur('Non admis', _i(nonAdmis)))
    ..add(valeur('Taux de réussite (%)', _n(tauxGlobal)))
    ..add(valeur('Moyenne générale (de tous les élèves évalués)', _n(moyenneGenerale)))
    ..add(valeur('Meilleure moyenne', _n(meilleure)))
    ..add(valeur('Plus faible moyenne', _n(faible)));
  return [
    FeuilleEcrite('Établissement', ecole, largeurs: const [52, 14]),
    FeuilleEcrite(
      'Classes',
      parClasse,
      largeurs: const [16, 10, 9, 9, 10, 9, 11, 14, 14, 14, 14],
    ),
  ];
}

// ------------------------------------------------------------ Admis / non admis

/// Listes des élèves admis (moyenne au moins égale au seuil d'admission) et
/// non admis, toutes classes confondues. Les élèves sans moyenne, partis ou
/// ayant abandonné ne figurent dans aucune des deux listes.
List<FeuilleEcrite> feuillesAdmis(ContexteExport ctx, List<ClassePortee> classes, {required String libelle}) {
  final admis = <Ligne>[];
  final non = <Ligne>[];
  var nAdmis = 0, nNon = 0;
  for (final cp in classes) {
    final seuil = cp.calcul.config.seuilAdmission;
    for (final l in lignesClassement(cp.calcul, cp.portee)) {
      final moyenne = l.moyenne;
      final rang = l.rang;
      if (!l.eleve.actif || moyenne == null || rang == null) continue;
      final estAdmis = moyenne >= seuil;
      final numero = estAdmis ? ++nAdmis : ++nNon;
      (estAdmis ? admis : non).add([
        _i(numero),
        _t(_nomClasse(cp.calcul)),
        _t(l.eleve.matricule),
        _t(l.eleve.nom),
        _t(l.eleve.prenom),
        _c(l.eleve.sexe),
        _n(moyenne),
        _i(rang),
        _t(l.mention),
        _t(l.decision),
      ]);
    }
  }
  FeuilleEcrite feuille(String nom, String titre, List<Ligne> corps) => FeuilleEcrite(
        nom,
        [
          ..._tete(ctx, titre, detail: '$libelle  ·  ${corps.length} élève${corps.length > 1 ? 's' : ''}'),
          [
            _h('N°'),
            _h('Classe'),
            _h('Matricule'),
            _h('Nom'),
            _h('Prénom'),
            _h('Sexe'),
            _h('Moyenne'),
            _h('Rang'),
            _h('Mention'),
            _h('Décision'),
          ],
          ...corps,
        ],
        largeurs: const [5, 12, 14, 20, 20, 7, 11, 7, 14, 22],
      );
  return [
    feuille('Admis', 'Liste des élèves admis', admis),
    feuille('Non admis', 'Liste des élèves non admis', non),
  ];
}
