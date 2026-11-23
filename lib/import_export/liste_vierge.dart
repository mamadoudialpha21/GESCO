/// Listes de notes vierges remises aux enseignants (fichiers Excel).
///
/// Un fichier concerne une classe et un enseignant : une feuille par matière
/// de l'enseignant, avec les élèves (matricule, nom et prénom) et des cases
/// jaunes à remplir. L'enseignant rend le fichier, qui est ensuite importé.
///
/// Pour que l'import retrouve sans ambiguïté la classe, la matière, le mois et
/// l'évaluation de chaque colonne, le fichier contient une dernière feuille
/// « GESCO » (voir [feuilleTechnique]) : l'enseignant n'a pas à y toucher.
library;

import '../data/modeles_donnees.dart';
import '../data/modeles_notation.dart';
import '../domain/periodes.dart';
import '../tableur/classeur.dart';
import 'modele_export.dart';

/// Première valeur de la feuille technique : reconnaît un fichier GESCO.
const String formatListeNotes = 'GESCO-LISTE-NOTES';

/// Version du format de la feuille technique.
const int versionFormatListeNotes = 1;

/// Nom de la feuille technique, toujours la dernière du classeur.
const String feuilleTechnique = 'GESCO';

/// Colonnes proposées au plus pour chaque sorte d'évaluation créée par défaut.
const int interrogationsMax = 6;
const int devoirsMax = 4;

/// Lignes d'une feuille de matière avant les élèves : établissement, titre,
/// année, classe, matière, enseignant, période, consigne, une ligne vide, puis
/// le titre des colonnes (indice [ligneEnteteTableau], à partir de 0). Les
/// élèves commencent à l'indice [premiereLigneEleves].
const int ligneEnteteTableau = 9;
const int premiereLigneEleves = ligneEnteteTableau + 1;

/// Colonnes fixes avant les notes : N°, matricule, nom et prénom.
const int colonneMatricule = 1;
const int colonneNom = 2;
const int premiereColonneNotes = 3;

/// Une colonne de notes d'une liste vierge : une évaluation existante ou à
/// créer au moment de l'import.
class ColonneVierge {
  const ColonneVierge({
    required this.titre,
    required this.type,
    required this.mois,
    required this.bareme,
    this.coefficient = 100,
    this.evaluationId,
  });

  final String titre;
  final TypeEvaluation type;

  /// Mois civil de l'évaluation (10, 11, 12, 1 à 6).
  final int mois;

  /// Note maximale : celle de l'évaluation existante, sinon de la matière.
  final int bareme;

  /// Poids dans la note du mois, en centièmes (100 = coefficient 1).
  final int coefficient;

  /// Évaluation existante dont la colonne recevra les notes ; null si
  /// l'évaluation sera créée à l'import.
  final int? evaluationId;
}

/// Choix de l'utilisateur pour produire des listes vierges.
class OptionsListeVierge {
  const OptionsListeVierge({
    required this.mois,
    this.nbInterrogations = 2,
    this.nbDevoirs = 0,
    this.avecComposition = false,
    this.avecObservations = true,
  });

  /// Mois civil des notes à saisir.
  final int mois;

  /// Colonnes créées par défaut quand la matière n'a encore aucune
  /// évaluation ce mois-ci.
  final int nbInterrogations;
  final int nbDevoirs;
  final bool avecComposition;

  /// Ajoute une colonne « Observations » libre (non importée).
  final bool avecObservations;
}

/// Colonnes de notes d'une matière pour le mois choisi.
///
/// - Si la matière a déjà des évaluations ce mois-ci, ce sont elles (hors
///   évaluations validées, qui ne peuvent plus recevoir de notes) : l'import
///   remplira les évaluations existantes.
/// - Sinon, des colonnes par défaut : interrogations, devoirs, composition
///   selon [options]. Elles seront créées à l'import. Au moins une colonne est
///   toujours proposée.
List<ColonneVierge> planifierColonnes({
  required MatiereClasse matiere,
  required List<Evaluation> evaluations,
  required OptionsListeVierge options,
}) {
  final duMois = [
    for (final e in evaluations)
      if (e.matiereId == matiere.id && e.mois == options.mois) e,
  ]..sort((a, b) {
      final parDate = (a.date ?? '').compareTo(b.date ?? '');
      return parDate != 0 ? parDate : a.id.compareTo(b.id);
    });
  if (duMois.isNotEmpty) {
    return [
      for (final e in duMois)
        if (!e.valide)
          ColonneVierge(
            titre: e.titre,
            type: e.type,
            mois: e.mois,
            bareme: e.bareme,
            coefficient: e.coefficient,
            evaluationId: e.id,
          ),
    ];
  }

  ColonneVierge nouvelle(String titre, TypeEvaluation type) => ColonneVierge(
        titre: titre,
        type: type,
        mois: options.mois,
        bareme: matiere.bareme,
      );
  List<ColonneVierge> serie(String nom, int nombre, TypeEvaluation type) => [
        if (nombre == 1)
          nouvelle(nom, type)
        else
          for (var i = 1; i <= nombre; i++) nouvelle('$nom $i', type),
      ];

  final colonnes = [
    ...serie('Interrogation', options.nbInterrogations.clamp(0, interrogationsMax),
        TypeEvaluation.interrogation),
    ...serie('Devoir', options.nbDevoirs.clamp(0, devoirsMax), TypeEvaluation.devoir),
    if (options.avecComposition) nouvelle('Composition', TypeEvaluation.composition),
  ];
  if (colonnes.isEmpty) colonnes.add(nouvelle('Évaluation', TypeEvaluation.evaluation));
  return colonnes;
}

/// Une matière d'une liste vierge avec ses colonnes de notes.
class MatiereVierge {
  const MatiereVierge({required this.matiere, required this.colonnes});

  final MatiereClasse matiere;
  final List<ColonneVierge> colonnes;
}

/// Contenu d'un fichier : une classe, un enseignant, ses matières, les élèves.
class ListeVierge {
  const ListeVierge({
    required this.classe,
    required this.matieres,
    required this.eleves,
    this.enseignantId,
    this.enseignantNom = '',
  });

  final Classe classe;
  final List<MatiereVierge> matieres;

  /// Élèves qui suivent la classe (partis et abandons exclus), dans l'ordre
  /// des écrans de saisie.
  final List<EleveInscrit> eleves;

  /// Enseignant du fichier ; null et nom vide pour les matières sans
  /// enseignant (la case est alors à remplir à la main).
  final int? enseignantId;
  final String enseignantNom;
}

/// Noms d'onglet valides et tous différents (Excel les compare sans tenir
/// compte des majuscules). Les noms de [reserves] sont déjà pris.
List<String> nomsOngletsUniques(Iterable<String> souhaites, {Set<String> reserves = const {}}) {
  final pris = {for (final r in reserves) r.toLowerCase()};
  final noms = <String>[];
  for (final souhait in souhaites) {
    final base = nomOngletValide(souhait);
    var nom = base;
    for (var n = 2; pris.contains(nom.toLowerCase()); n++) {
      final suffixe = ' ($n)';
      final debut = base.length + suffixe.length > 31
          ? base.substring(0, 31 - suffixe.length).trim()
          : base;
      nom = '$debut$suffixe';
    }
    pris.add(nom.toLowerCase());
    noms.add(nom);
  }
  return noms;
}

CelluleEcrite _t(String s, [StyleCellule style = StyleCellule.normal]) => CelluleEcrite(s, style);

const CelluleEcrite _saisie = CelluleEcrite(null, StyleCellule.saisie);

/// Les feuilles du classeur : une par matière de [liste], puis la feuille
/// technique « GESCO ».
List<FeuilleEcrite> construireListeVierge(
  ContexteExport ctx,
  ListeVierge liste, {
  required int mois,
  bool avecObservations = true,
}) {
  final noms = nomsOngletsUniques(
    [for (final m in liste.matieres) m.matiere.nom],
    reserves: {feuilleTechnique},
  );
  final classeNom = liste.classe.nom;
  final feuilles = <FeuilleEcrite>[];
  for (var k = 0; k < liste.matieres.length; k++) {
    final mv = liste.matieres[k];
    final nbCol = mv.colonnes.length;
    final lignes = <List<CelluleEcrite?>>[
      [_t(ctx.etablissement.isEmpty ? 'Établissement' : ctx.etablissement, StyleCellule.titre)],
      [_t('LISTE DE NOTES À REMPLIR', StyleCellule.etiquette)],
      [_t('Année scolaire :', StyleCellule.etiquette), null, _t(ctx.annee)],
      [_t('Classe :', StyleCellule.etiquette), null, _t(classeNom)],
      [_t('Matière :', StyleCellule.etiquette), null, _t(mv.matiere.nom)],
      [
        _t('Enseignant :', StyleCellule.etiquette),
        null,
        liste.enseignantNom.isEmpty ? _saisie : _t(liste.enseignantNom),
      ],
      [_t('Période :', StyleCellule.etiquette), null, _t(libelleMois(mois))],
      [
        _t(
          'Remplir les cases jaunes. Absent : ABS. Dispensé : DISP. '
          'Case vide : note non remise. Ne pas modifier le matricule, '
          'les titres ni la feuille « $feuilleTechnique ».',
          StyleCellule.discret,
        ),
      ],
      <CelluleEcrite?>[],
      [
        _t('N°', StyleCellule.entete),
        _t('Matricule', StyleCellule.entete),
        _t('Nom et prénom', StyleCellule.entete),
        for (final c in mv.colonnes)
          _t('${c.titre}\n(sur ${c.bareme})', StyleCellule.entete),
        if (avecObservations) _t('Observations', StyleCellule.entete),
      ],
    ];
    assert(lignes.length == premiereLigneEleves);
    for (var i = 0; i < liste.eleves.length; i++) {
      final e = liste.eleves[i];
      lignes.add([
        CelluleEcrite(i + 1, StyleCellule.entier),
        _t(e.matricule, StyleCellule.centre),
        _t(e.nomComplet),
        for (var c = 0; c < nbCol; c++) _saisie,
        if (avecObservations) const CelluleEcrite(null, StyleCellule.saisie),
      ]);
    }
    feuilles.add(FeuilleEcrite(
      noms[k],
      lignes,
      largeurs: [5, 14, 32, for (var c = 0; c < nbCol; c++) 14, if (avecObservations) 30],
    ));
  }
  feuilles.add(_feuilleTechnique(ctx, liste, noms, mois));
  return feuilles;
}

/// Feuille « GESCO » : de quoi relire le fichier sans rien deviner.
///
/// Lignes, de haut en bas : format et version ; année ; classe ; enseignant ;
/// mois ; titres des colonnes ; puis une ligne par colonne de notes
/// (feuille, matière, numéro de colonne à partir de 1, titre, type, mois,
/// barème, coefficient, évaluation existante ou 0, première et dernière ligne
/// des élèves).
List<List<CelluleEcrite?>> _lignesTechniques(
  ContexteExport ctx,
  ListeVierge liste,
  List<String> noms,
  int mois,
) {
  final premiere = premiereLigneEleves + 1; // numéros de ligne Excel (à partir de 1)
  final derniere = premiereLigneEleves + liste.eleves.length;
  final lignes = <List<CelluleEcrite?>>[
    [_t('GESCO — ne pas modifier cette feuille', StyleCellule.titre)],
    [_t('format'), _t(formatListeNotes), CelluleEcrite(versionFormatListeNotes)],
    [_t('annee'), _t(ctx.annee)],
    [_t('classe_id'), CelluleEcrite(liste.classe.id), _t(liste.classe.nom)],
    [
      _t('enseignant_id'),
      CelluleEcrite(liste.enseignantId ?? 0),
      _t(liste.enseignantNom),
    ],
    [_t('mois'), CelluleEcrite(mois), _t(libelleMois(mois))],
    <CelluleEcrite?>[],
    [
      for (final titre in const [
        'feuille',
        'matiere_id',
        'matiere',
        'colonne',
        'titre',
        'type',
        'mois',
        'bareme',
        'coefficient',
        'evaluation_id',
        'ligne_debut',
        'ligne_fin',
      ])
        _t(titre, StyleCellule.entete),
    ],
  ];
  for (var k = 0; k < liste.matieres.length; k++) {
    final mv = liste.matieres[k];
    for (var c = 0; c < mv.colonnes.length; c++) {
      final col = mv.colonnes[c];
      lignes.add([
        _t(noms[k]),
        CelluleEcrite(mv.matiere.id),
        _t(mv.matiere.nom),
        CelluleEcrite(premiereColonneNotes + c + 1),
        _t(col.titre),
        _t(col.type.cle),
        CelluleEcrite(col.mois),
        CelluleEcrite(col.bareme),
        CelluleEcrite(col.coefficient),
        CelluleEcrite(col.evaluationId ?? 0),
        CelluleEcrite(premiere),
        CelluleEcrite(derniere),
      ]);
    }
  }
  return lignes;
}

FeuilleEcrite _feuilleTechnique(
  ContexteExport ctx,
  ListeVierge liste,
  List<String> noms,
  int mois,
) =>
    FeuilleEcrite(
      feuilleTechnique,
      _lignesTechniques(ctx, liste, noms, mois),
      largeurs: const [16, 14, 24, 9, 22, 14, 7, 8, 12, 14, 11, 9],
    );
