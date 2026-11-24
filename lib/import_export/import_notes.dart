/// Import des notes depuis un tableau Excel : reconnaissance du fichier,
/// association des colonnes aux évaluations, puis vérification de **chaque
/// case** avant toute écriture.
///
/// Rien n'est lu dans la base ici : [ContexteImportNotes] fournit les élèves,
/// les évaluations et les notes déjà enregistrées, ce qui permet de tout
/// tester sans fichier ni base. L'écriture se fait ensuite en une seule
/// transaction (`EvaluationDepot.importerNotes`).
///
/// Principes :
/// - une note déjà enregistrée n'est **jamais** écrasée, sauf si l'utilisateur
///   le demande ([ContexteImportNotes.remplacerExistantes]) ;
/// - une case vide n'efface rien : la note non remise reste « non saisie » ;
/// - une ligne qui contient une erreur n'est jamais importée à moitié ;
/// - le barème, le coefficient et le mois d'une évaluation existante sont
///   ceux de GESCO, jamais ceux du fichier.
library;

import '../data/modeles_donnees.dart';
import '../data/modeles_notation.dart';
import '../domain/bareme.dart';
import '../domain/modeles.dart';
import '../domain/periodes.dart';
import '../domain/saisie_note.dart';
import '../tableur/classeur.dart';
import 'lecture_tableur.dart';
import 'liste_vierge.dart';

// ----------------------------------------------------------------- Contexte

/// Ce que l'import doit savoir de la base pour vérifier le fichier.
class ContexteImportNotes {
  const ContexteImportNotes({
    required this.classeId,
    required this.classeNom,
    required this.matiereId,
    required this.matiereNom,
    required this.matiereBareme,
    required this.anneeLibelle,
    required this.trimestreLibelle,
    required this.moisTrimestre,
    required this.eleves,
    required this.evaluations,
    this.notesExistantes = const {},
    this.moisVerrouilles = const {},
    this.remplacerExistantes = false,
  });

  final int classeId;
  final String classeNom;
  final int matiereId;
  final String matiereNom;

  /// Barème de la matière : celui des évaluations créées par l'import.
  final int matiereBareme;
  final String anneeLibelle;

  /// Période choisie (« Trimestre 1 ») et ses mois civils.
  final String trimestreLibelle;
  final List<int> moisTrimestre;

  /// Élèves inscrits dans l'année, **toutes classes** (pour expliquer qu'un
  /// matricule appartient à une autre classe).
  final List<EleveInscrit> eleves;

  /// Évaluations de la classe (celles d'autres matières sont ignorées).
  final List<Evaluation> evaluations;

  /// évaluation -> inscription -> note déjà enregistrée.
  final Map<int, Map<int, Saisie>> notesExistantes;

  /// Mois verrouillés pour la classe : plus aucune note n'y est acceptée.
  final Set<int> moisVerrouilles;

  /// Remplace les notes déjà enregistrées quand le fichier en donne une autre.
  final bool remplacerExistantes;
}

// ------------------------------------------------------------- Association

/// Évaluation visée par une colonne du fichier.
class CibleColonne {
  const CibleColonne({
    this.evaluationId,
    required this.titre,
    this.type = TypeEvaluation.evaluation,
    required this.mois,
    required this.bareme,
    this.coefficient = 100,
    this.baremeAnnonce,
  });

  /// Évaluation existante qui reçoit les notes ; null : évaluation à créer
  /// (ou reprise d'une évaluation existante de même titre et de même mois).
  final int? evaluationId;

  /// Caractéristiques de l'évaluation à créer. Pour une évaluation existante,
  /// seuls ses propres titre, mois, barème et coefficient comptent.
  final String titre;
  final TypeEvaluation type;
  final int mois;
  final int bareme;
  final int coefficient;

  /// Barème que le fichier annonce pour la colonne (« sur 10 »), ou null s'il
  /// n'en annonce pas. S'il diffère de celui de l'évaluation, l'import est
  /// refusé : les notes seraient lues sur un mauvais barème.
  final int? baremeAnnonce;

  bool get nouvelle => evaluationId == null;

  CibleColonne copie({
    int? evaluationId,
    bool nouvelle = false,
    String? titre,
    TypeEvaluation? type,
    int? mois,
    int? bareme,
    int? coefficient,
  }) =>
      CibleColonne(
        evaluationId: nouvelle ? null : (evaluationId ?? this.evaluationId),
        titre: titre ?? this.titre,
        type: type ?? this.type,
        mois: mois ?? this.mois,
        bareme: bareme ?? this.bareme,
        coefficient: coefficient ?? this.coefficient,
        baremeAnnonce: baremeAnnonce,
      );
}

/// Association des colonnes du fichier.
class MappingNotes {
  const MappingNotes({
    this.colonneMatricule,
    this.colonneNom,
    this.colonnePrenom,
    this.colonnes = const {},
  });

  /// Colonne du matricule (indice à partir de 0), ou null.
  final int? colonneMatricule;

  /// Colonne du nom (ou « nom et prénom »), ou null.
  final int? colonneNom;

  /// Colonne du prénom quand il est séparé du nom, ou null.
  final int? colonnePrenom;

  /// colonne -> évaluation visée. Les colonnes absentes ne sont pas importées.
  final Map<int, CibleColonne> colonnes;
}

// ------------------------------------------------------------------ Rapport

/// Ce que devient une case de note.
enum EtatCaseNote {
  /// Aucune note n'existait : elle sera enregistrée.
  nouvelle,

  /// Le fichier donne la note déjà enregistrée : rien à faire.
  identique,

  /// Le fichier donne une autre note et l'utilisateur a demandé de remplacer.
  remplacee,

  /// Le fichier donne une autre note : l'ancienne est conservée.
  conflit,

  /// Case vide : rien n'est écrit ni effacé.
  vide,

  /// Valeur illisible, hors barème ou formule.
  erreur,
}

/// Une case de note vérifiée.
class CaseNote {
  const CaseNote({
    required this.colonne,
    required this.texte,
    required this.etat,
    this.saisie,
    this.ancienne,
    this.message,
  });

  /// Colonne du fichier (indice à partir de 0).
  final int colonne;

  /// Texte lu dans la case.
  final String texte;
  final EtatCaseNote etat;

  /// Note lue (null si la case est vide ou en erreur).
  final Saisie? saisie;

  /// Note déjà enregistrée, s'il y en a une.
  final Saisie? ancienne;

  /// Raison de l'erreur.
  final String? message;

  /// Cette case sera écrite dans la base.
  bool get aEcrire => etat == EtatCaseNote.nouvelle || etat == EtatCaseNote.remplacee;
}

/// Résultat de la vérification d'une ligne du fichier.
class LigneImportNotes {
  const LigneImportNotes({
    required this.numero,
    required this.matricule,
    required this.nom,
    this.eleve,
    this.cases = const {},
    this.erreurs = const [],
    this.avertissements = const [],
  });

  /// Numéro de la ligne dans le fichier Excel.
  final int numero;

  /// Valeurs lues (affichées même si la ligne est en erreur).
  final String matricule;
  final String nom;

  /// Élève reconnu ; null si la ligne n'a pas pu lui être associée.
  final EleveInscrit? eleve;

  /// colonne du fichier -> case vérifiée (vide si l'élève n'est pas reconnu).
  final Map<int, CaseNote> cases;

  /// Raisons pour lesquelles la ligne ne sera pas importée.
  final List<String> erreurs;

  /// Remarques qui n'empêchent pas l'import (note conservée, remplacée...).
  final List<String> avertissements;

  bool get enErreur => erreurs.isNotEmpty;

  /// Nombre de notes que cette ligne écrira.
  int get nbAEcrire => enErreur ? 0 : cases.values.where((c) => c.aEcrire).length;

  /// Élève reconnu mais aucune note remise.
  bool get sansNote =>
      eleve != null && cases.values.every((c) => c.etat == EtatCaseNote.vide);
}

/// Bilan d'une colonne du fichier.
class ResumeColonneNotes {
  const ResumeColonneNotes({
    required this.colonne,
    required this.libelle,
    required this.titre,
    required this.mois,
    required this.bareme,
    required this.coefficient,
    required this.type,
    this.evaluationId,
    this.reprise = false,
    this.nbNouvelles = 0,
    this.nbRemplacees = 0,
    this.nbIdentiques = 0,
    this.nbConservees = 0,
    this.nbVides = 0,
    this.nbErreurs = 0,
    this.nbSansNote = 0,
  });

  /// Colonne du fichier et son titre tel que le fichier l'écrit.
  final int colonne;
  final String libelle;

  /// Évaluation visée.
  final String titre;
  final int mois;
  final int bareme;
  final int coefficient;
  final TypeEvaluation type;

  /// Évaluation existante ; null si l'import la créera.
  final int? evaluationId;

  /// L'évaluation existait déjà (même titre, même mois) : elle est reprise.
  final bool reprise;

  /// Notes qui seront enregistrées pour la première fois.
  final int nbNouvelles;

  /// Notes qui en remplaceront une autre.
  final int nbRemplacees;

  /// Notes du fichier identiques à celles de GESCO.
  final int nbIdentiques;

  /// Notes différentes de celles de GESCO, laissées telles quelles.
  final int nbConservees;

  /// Cases vides.
  final int nbVides;

  /// Cases en erreur (toutes lignes, y compris celles qui seront ignorées).
  final int nbErreurs;

  /// Élèves de la classe qui n'auront aucune note dans cette évaluation après
  /// l'import.
  final int nbSansNote;

  bool get creer => evaluationId == null;
  int get nbAEcrire => nbNouvelles + nbRemplacees;
}

/// Résultat de la vérification d'un fichier entier.
class RapportImportNotes {
  const RapportImportNotes({
    this.problemesFichier = const [],
    this.remarquesFichier = const [],
    this.lignes = const [],
    this.colonnes = const [],
    this.plan = const [],
    this.absentsDuFichier = const [],
    this.nbLignesVides = 0,
  });

  /// Problèmes qui empêchent toute vérification (colonne mal associée,
  /// évaluation validée, mois verrouillé...).
  final List<String> problemesFichier;

  /// Informations générales (évaluations créées, élèves absents du fichier...).
  final List<String> remarquesFichier;
  final List<LigneImportNotes> lignes;
  final List<ResumeColonneNotes> colonnes;

  /// Ce qui sera écrit : une entrée par colonne ayant au moins une note.
  final List<ColonneNotesAImporter> plan;

  /// Élèves de la classe qui ne figurent pas dans le fichier (leurs notes ne
  /// changent pas).
  final List<EleveInscrit> absentsDuFichier;

  /// Lignes entièrement vides, ignorées.
  final int nbLignesVides;

  bool get bloque => problemesFichier.isNotEmpty;

  int get nbLignesErreur => lignes.where((l) => l.enErreur).length;
  int get nbLignesImportables => lignes.where((l) => !l.enErreur && l.eleve != null).length;
  int get nbLignesSansNote => lignes.where((l) => !l.enErreur && l.sansNote).length;
  int get nbLignesAvecRemarque =>
      lignes.where((l) => !l.enErreur && l.avertissements.isNotEmpty).length;

  /// Notes qui seront enregistrées (nouvelles et remplacées).
  int get nbNotesAEcrire => plan.fold(0, (s, c) => s + c.notes.length);

  /// Évaluations que l'import créera.
  int get nbEvaluationsACreer => plan.where((c) => c.creer).length;

  int _compter(bool Function(EtatCaseNote) test) {
    var n = 0;
    for (final l in lignes) {
      if (l.enErreur) continue;
      for (final c in l.cases.values) {
        if (test(c.etat)) n++;
      }
    }
    return n;
  }

  /// Notes qui en remplaceront une autre (si l'utilisateur l'a demandé).
  int get nbNotesRemplacees => _compter((e) => e == EtatCaseNote.remplacee);

  /// Notes du fichier identiques à celles de GESCO (ignorées).
  int get nbIdentiques => _compter((e) => e == EtatCaseNote.identique);

  /// Notes différentes de celles de GESCO, conservées telles quelles.
  int get nbConservees => _compter((e) => e == EtatCaseNote.conflit);

  /// Peut-on lancer l'import ? Il faut au moins une note à écrire, et soit
  /// aucune ligne en erreur, soit l'accord pour les ignorer.
  bool peutImporter({required bool ignorerErreurs}) =>
      !bloque && nbNotesAEcrire > 0 && (nbLignesErreur == 0 || ignorerErreurs);
}

// ------------------------------------------------------------- Vérification

String _texte(Cellule c) => c.texte.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Texte d'une cellule de note. Un nombre qui n'a que des écarts d'arrondi
/// (14,100000000000001 issu d'un calcul) est ramené à ses deux décimales.
String _texteNote(Cellule c) {
  final n = c.nombre;
  if (n != null) {
    final arrondi = (n * 100).round() / 100;
    if ((n - arrondi).abs() < 1e-9) {
      return arrondi == arrondi.roundToDouble() ? '${arrondi.toInt()}' : '$arrondi';
    }
  }
  return _texte(c);
}

String _cleMatricule(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

/// Mots d'un nom, sans accent ni majuscule, rangés par ordre alphabétique :
/// « DIALLO Mamadou » et « Mamadou Diallo » donnent la même clé.
String _cleNom(String s) {
  final mots = cleColonne(s).split(' ').where((m) => m.isNotEmpty).toList()..sort();
  return mots.join(' ');
}

Set<String> _mots(String s) =>
    {for (final m in cleColonne(s).split(' ')) if (m.length >= 2) m};

String _coef(int centiemes) => centiemes % 100 == 0
    ? '${centiemes ~/ 100}'
    : (centiemes / 100).toString().replaceAll('.', ',');

String _pluriel(int n, String mot, [String? pluriel]) =>
    '$n ${n > 1 ? (pluriel ?? '${mot}s') : mot}';

/// Colonne du fichier résolue : l'évaluation existante qu'elle vise, ou les
/// caractéristiques de celle qui sera créée.
class _Col {
  _Col({required this.index, required this.libelle, required this.cible, this.evaluation})
      : reprise = evaluation != null && cible.nouvelle;

  final int index;
  final String libelle;
  final CibleColonne cible;
  final Evaluation? evaluation;
  final bool reprise;

  int? get evaluationId => evaluation?.id;
  String get titre => evaluation?.titre ?? cible.titre.trim();
  int get mois => evaluation?.mois ?? cible.mois;
  int get bareme => evaluation?.bareme ?? cible.bareme;
  int get coefficient => evaluation?.coefficient ?? cible.coefficient;
  TypeEvaluation get type => evaluation?.type ?? cible.type;
}

class _Brouillon {
  _Brouillon(this.numero);

  final int numero;
  String matricule = '';
  String nom = '';
  EleveInscrit? eleve;
  final Map<int, CaseNote> cases = {};
  final List<String> erreurs = [];
  final List<String> avertissements = [];

  LigneImportNotes versLigne() => LigneImportNotes(
        numero: numero,
        matricule: matricule,
        nom: nom,
        eleve: eleve,
        cases: cases,
        erreurs: erreurs,
        avertissements: avertissements,
      );
}

/// Vérifie le fichier **sans rien écrire** : chaque colonne, chaque élève,
/// chaque note. Le résultat dit exactement ce que l'import ferait.
RapportImportNotes analyserImportNotes({
  required TableLue table,
  required MappingNotes mapping,
  required ContexteImportNotes ctx,
}) {
  final problemes = <String>[];
  final remarques = <String>[];
  final nbCol = table.nbColonnes;

  int? dansTable(int? i) => i != null && i >= 0 && i < nbCol ? i : null;
  final cMat = dansTable(mapping.colonneMatricule);
  final cNom = dansTable(mapping.colonneNom);
  final cPrenom = dansTable(mapping.colonnePrenom);
  final indices = [
    for (final i in mapping.colonnes.keys)
      if (dansTable(i) != null) i,
  ]..sort();

  // ---- Colonnes d'identité
  if (table.lignes.isEmpty) {
    problemes.add('Le tableau ne contient aucune ligne d\'élève sous la ligne d\'en-tête.');
  }
  if (cMat == null && cNom == null) {
    problemes.add(
      'Aucune colonne ne permet de reconnaître les élèves : associez la colonne '
      '« Matricule » ou la colonne « Nom ».',
    );
  }
  if (cPrenom != null && cNom == null) {
    problemes.add('Le prénom est associé, mais pas le nom : associez aussi la colonne « Nom ».');
  }
  final identite = [for (final i in [cMat, cNom, cPrenom]) if (i != null) i];
  if (identite.toSet().length != identite.length) {
    problemes.add('La même colonne ne peut pas servir à deux informations (matricule, nom, prénom).');
  }
  for (final i in indices) {
    if (identite.contains(i)) {
      problemes.add(
        'La colonne « ${table.titreColonne(i)} » sert à reconnaître les élèves : '
        'elle ne peut pas contenir des notes.',
      );
    }
  }
  if (indices.isEmpty) {
    problemes.add('Aucune colonne de notes n\'est choisie : indiquez au moins une colonne à importer.');
  }

  // ---- Colonnes de notes : évaluation visée
  final evaluations = {
    for (final e in ctx.evaluations)
      if (e.matiereId == ctx.matiereId && e.classeId == ctx.classeId) e.id: e,
  };
  Evaluation? memeEvaluation(String titre, int mois) {
    final cle = cleColonne(titre);
    for (final e in evaluations.values) {
      if (e.mois == mois && cleColonne(e.titre) == cle) return e;
    }
    return null;
  }

  final colonnes = <_Col>[];
  for (final i in indices) {
    final cible = mapping.colonnes[i]!;
    final libelle = table.titreColonne(i);
    Evaluation? ev;
    if (cible.evaluationId != null) {
      ev = evaluations[cible.evaluationId];
      if (ev == null) {
        problemes.add(
          'La colonne « $libelle » vise une évaluation qui n\'existe pas pour la matière '
          '${ctx.matiereNom} de ${ctx.classeNom}.',
        );
        continue;
      }
    } else {
      final titre = cible.titre.trim();
      if (titre.isEmpty) {
        problemes.add('La colonne « $libelle » n\'a pas de titre d\'évaluation.');
        continue;
      }
      if (titre.length > longueurMaxTitreEvaluation) {
        problemes.add(
          'Le titre « $titre » est trop long ($longueurMaxTitreEvaluation caractères au maximum).',
        );
        continue;
      }
      if (!moisScolaires.contains(cible.mois) || !ctx.moisTrimestre.contains(cible.mois)) {
        problemes.add(
          'La colonne « $libelle » : le mois de l\'évaluation « $titre » doit être un mois de '
          '${ctx.trimestreLibelle}.',
        );
        continue;
      }
      if (!baremeValide(cible.bareme)) {
        problemes.add('La colonne « $libelle » : le barème doit être compris entre 1 et $baremeMax.');
        continue;
      }
      if (cible.coefficient <= 0 || cible.coefficient > coefficientMaxEvaluation) {
        problemes.add(
          'La colonne « $libelle » : le coefficient doit être strictement positif et inférieur '
          'à 100.',
        );
        continue;
      }
      ev = memeEvaluation(titre, cible.mois);
    }
    final col = _Col(index: i, libelle: libelle, cible: cible, evaluation: ev);
    final existante = col.evaluation;
    if (existante != null) {
      if (existante.valide) {
        problemes.add(
          'L\'évaluation « ${existante.titre} » (${libelleMois(existante.mois)}) est validée : '
          'annulez sa validation pour y importer des notes.',
        );
        continue;
      }
      if (!ctx.moisTrimestre.contains(existante.mois)) {
        problemes.add(
          'L\'évaluation « ${existante.titre} » est en ${libelleMois(existante.mois)}, '
          'hors de ${ctx.trimestreLibelle}.',
        );
        continue;
      }
      final annonce = cible.baremeAnnonce;
      if (annonce != null && annonce != existante.bareme) {
        problemes.add(
          'La colonne « $libelle » est notée sur $annonce dans le fichier, mais l\'évaluation '
          '« ${existante.titre} » est notée sur ${existante.bareme} : les notes ne seraient '
          'pas sur le bon barème.',
        );
        continue;
      }
    }
    if (ctx.moisVerrouilles.contains(col.mois)) {
      problemes.add(
        '${libelleMois(col.mois)} est verrouillé pour ${ctx.classeNom} : déverrouillez le mois '
        'pour y importer des notes (colonne « $libelle »).',
      );
      continue;
    }
    colonnes.add(col);
  }

  // ---- Deux colonnes pour la même évaluation
  final vues = <String, _Col>{};
  for (final c in colonnes) {
    final cle = c.evaluationId != null
        ? 'e${c.evaluationId}'
        : 'n${cleColonne(c.titre)}|${c.mois}';
    final autre = vues[cle];
    if (autre != null) {
      problemes.add(
        'Les colonnes « ${autre.libelle} » et « ${c.libelle} » visent la même évaluation '
        '« ${c.titre} » : une seule des deux peut être importée.',
      );
    } else {
      vues[cle] = c;
    }
  }

  if (problemes.isNotEmpty) {
    return RapportImportNotes(problemesFichier: problemes, remarquesFichier: remarques);
  }

  // ---- Élèves de la classe
  final dansClasse = [for (final e in ctx.eleves) if (e.classeId == ctx.classeId) e];
  final parMatricule = <String, EleveInscrit>{};
  for (final e in dansClasse) {
    parMatricule.putIfAbsent(_cleMatricule(e.matricule), () => e);
  }
  final parMatriculeAutres = <String, EleveInscrit>{};
  for (final e in ctx.eleves) {
    if (e.classeId != ctx.classeId) {
      parMatriculeAutres.putIfAbsent(_cleMatricule(e.matricule), () => e);
    }
  }
  final parNom = <String, List<EleveInscrit>>{};
  for (final e in dansClasse) {
    parNom.putIfAbsent(_cleNom('${e.nom} ${e.prenom}'), () => []).add(e);
  }
  final actifs = [for (final e in dansClasse) if (e.actif) e];

  if (cMat == null) {
    remarques.add('Le fichier n\'a pas de colonne matricule : les élèves sont reconnus par leur nom.');
  }

  String lireNom(LigneTable l) {
    final nom = cNom == null ? '' : _texte(l.cellule(cNom));
    final prenom = cPrenom == null ? '' : _texte(l.cellule(cPrenom));
    return [nom, prenom].where((t) => t.isNotEmpty).join(' ');
  }

  // ---- Lecture des lignes
  final brouillons = <_Brouillon>[];
  var nbVides = 0;
  for (final l in table.lignes) {
    final texteMat = cMat == null ? '' : _texte(l.cellule(cMat));
    final texteNom = lireNom(l);
    final aDesNotes = indices.any((i) => !l.cellule(i).vide);
    final formuleIdentite = identite.any((i) => l.cellule(i).formule);
    if (texteMat.isEmpty && texteNom.isEmpty && !aDesNotes && !formuleIdentite) {
      nbVides++;
      continue;
    }
    final b = _Brouillon(l.numero)
      ..matricule = texteMat
      ..nom = texteNom;
    brouillons.add(b);

    if (formuleIdentite) {
      b.erreurs.add(
        'Le matricule ou le nom contient une formule : remplacez-la par sa valeur '
        '(Copier, puis Collage spécial > Valeurs).',
      );
      continue;
    }

    // Reconnaissance de l'élève : par le matricule, sinon par le nom.
    final problemesEleve = <String>[];
    EleveInscrit? eleve;
    if (texteMat.isNotEmpty) {
      eleve = parMatricule[_cleMatricule(texteMat)];
      if (eleve == null) {
        final ailleurs = parMatriculeAutres[_cleMatricule(texteMat)];
        if (ailleurs != null) {
          problemesEleve.add(
            'Le matricule « $texteMat » est celui de ${ailleurs.nomComplet}, qui est dans la '
            'classe ${ailleurs.classeNom} et non dans ${ctx.classeNom}.',
          );
        } else {
          var m = 'Matricule « $texteMat » inconnu : aucun élève de ${ctx.classeNom} ne le porte.';
          final proches = texteNom.isEmpty ? null : parNom[_cleNom(texteNom)];
          if (proches != null && proches.length == 1) {
            m += ' Un élève de la classe porte ce nom : ${proches.first.nomComplet} '
                '(matricule ${proches.first.matricule}).';
          }
          problemesEleve.add(m);
        }
      } else if (texteNom.isNotEmpty) {
        final a = _mots(texteNom);
        final b2 = _mots('${eleve.nom} ${eleve.prenom}');
        if (a.isNotEmpty && b2.isNotEmpty && !a.any(b2.contains)) {
          problemesEleve.add(
            'Le matricule « $texteMat » est celui de ${eleve.nomComplet}, mais la ligne porte le '
            'nom « $texteNom » : vérifiez la ligne.',
          );
          eleve = null;
        }
      }
    } else if (texteNom.isNotEmpty) {
      final trouves = parNom[_cleNom(texteNom)];
      if (trouves == null || trouves.isEmpty) {
        problemesEleve.add('Aucun élève de ${ctx.classeNom} ne porte le nom « $texteNom ».');
      } else if (trouves.length > 1) {
        problemesEleve.add(
          'Plusieurs élèves de ${ctx.classeNom} portent le nom « $texteNom » : '
          'indiquez leur matricule.',
        );
      } else {
        eleve = trouves.first;
        if (cMat != null) {
          b.avertissements.add(
            'Matricule vide : élève reconnu par son nom (${eleve.nomComplet}, '
            'matricule ${eleve.matricule}).',
          );
        }
      }
    } else {
      problemesEleve.add('Cette ligne a des notes mais ni matricule ni nom : élève non reconnu.');
    }

    if (eleve != null && !eleve.actif) {
      problemesEleve.add(
        '${eleve.nomComplet} a quitté la classe (${eleve.statut.libelle.toLowerCase()}) : '
        'ses notes ne sont pas importées.',
      );
      eleve = null;
    }

    if (eleve == null) {
      if (aDesNotes) {
        b.erreurs.addAll(problemesEleve);
      } else {
        // Aucune note à importer : rien à perdre, simple remarque.
        for (final p in problemesEleve) {
          b.avertissements.add('$p Aucune note sur la ligne : elle est ignorée.');
        }
      }
      continue;
    }
    b.eleve = eleve;

    // Lecture des cases de notes.
    for (final col in colonnes) {
      final cellule = l.cellule(col.index);
      final ancienne = col.evaluationId == null
          ? null
          : ctx.notesExistantes[col.evaluationId]?[eleve.inscriptionId];
      final c = _lireCase(cellule, col, ancienne, ctx.remplacerExistantes);
      b.cases[col.index] = c;
      switch (c.etat) {
        case EtatCaseNote.erreur:
          b.erreurs.add('« ${col.titre} » : ${c.message}');
        case EtatCaseNote.conflit:
          b.avertissements.add(
            '« ${col.titre} » : le fichier donne ${c.texte}, mais GESCO a déjà '
            '${texteSaisie(c.ancienne)} (note conservée).',
          );
        case EtatCaseNote.remplacee:
          b.avertissements.add(
            '« ${col.titre} » : ${texteSaisie(c.ancienne)} sera remplacée par ${c.texte}.',
          );
        case EtatCaseNote.nouvelle || EtatCaseNote.identique || EtatCaseNote.vide:
          break;
      }
    }
  }

  // ---- Un élève sur plusieurs lignes
  final lignesParEleve = <int, List<_Brouillon>>{};
  for (final b in brouillons) {
    final e = b.eleve;
    if (e != null) lignesParEleve.putIfAbsent(e.inscriptionId, () => []).add(b);
  }
  for (final liste in lignesParEleve.values) {
    if (liste.length < 2) continue;
    final numeros = liste.map((b) => b.numero).join(', ');
    for (final b in liste) {
      b.erreurs.add(
        '${b.eleve!.nomComplet} figure sur plusieurs lignes ($numeros) : gardez une seule ligne.',
      );
    }
  }

  final lignes = [for (final b in brouillons) b.versLigne()];
  final importables = [for (final l in lignes) if (!l.enErreur && l.eleve != null) l];

  // ---- Ce qui sera écrit, colonne par colonne
  final plan = <ColonneNotesAImporter>[];
  final resumes = <ResumeColonneNotes>[];
  final actifsIds = {for (final e in actifs) e.inscriptionId};
  for (final col in colonnes) {
    final notes = <int, Saisie>{};
    var nouvelles = 0, remplacees = 0, identiques = 0, conservees = 0, vides = 0;
    for (final l in importables) {
      final c = l.cases[col.index];
      if (c == null) continue;
      switch (c.etat) {
        case EtatCaseNote.nouvelle:
          nouvelles++;
          notes[l.eleve!.inscriptionId] = c.saisie!;
        case EtatCaseNote.remplacee:
          remplacees++;
          notes[l.eleve!.inscriptionId] = c.saisie!;
        case EtatCaseNote.identique:
          identiques++;
        case EtatCaseNote.conflit:
          conservees++;
        case EtatCaseNote.vide:
          vides++;
        case EtatCaseNote.erreur:
          break;
      }
    }
    final nbErreurs = [
      for (final l in lignes)
        if (l.cases[col.index]?.etat == EtatCaseNote.erreur) l,
    ].length;

    final existantes = col.evaluationId == null
        ? const <int, Saisie>{}
        : (ctx.notesExistantes[col.evaluationId] ?? const <int, Saisie>{});
    final couverts = <int>{
      for (final id in existantes.keys)
        if (actifsIds.contains(id)) id,
      for (final id in notes.keys)
        if (actifsIds.contains(id)) id,
    };

    if (notes.isNotEmpty) {
      plan.add(ColonneNotesAImporter(
        evaluationId: col.evaluationId,
        titre: col.titre,
        type: col.type,
        mois: col.mois,
        bareme: col.bareme,
        coefficient: col.coefficient,
        notes: notes,
      ));
      if (col.evaluationId == null) {
        remarques.add(
          'L\'évaluation « ${col.titre} » (${libelleMois(col.mois)}, sur ${col.bareme}, '
          'coefficient ${_coef(col.coefficient)}) sera créée.',
        );
      }
    } else if (col.evaluationId == null) {
      remarques.add(
        'La colonne « ${col.libelle} » ne contient aucune note valide : l\'évaluation '
        '« ${col.titre} » ne sera pas créée.',
      );
    }
    if (col.reprise) {
      remarques.add(
        'La colonne « ${col.libelle} » reprend l\'évaluation existante « ${col.titre} » '
        '(${libelleMois(col.mois)}, sur ${col.bareme}) : aucune évaluation en double n\'est créée.',
      );
    }
    resumes.add(ResumeColonneNotes(
      colonne: col.index,
      libelle: col.libelle,
      titre: col.titre,
      mois: col.mois,
      bareme: col.bareme,
      coefficient: col.coefficient,
      type: col.type,
      evaluationId: col.evaluationId,
      reprise: col.reprise,
      nbNouvelles: nouvelles,
      nbRemplacees: remplacees,
      nbIdentiques: identiques,
      nbConservees: conservees,
      nbVides: vides,
      nbErreurs: nbErreurs,
      nbSansNote: actifs.length - couverts.length,
    ));
  }

  // ---- Élèves de la classe absents du fichier
  final reconnus = {for (final b in brouillons) if (b.eleve != null) b.eleve!.inscriptionId};
  final absents = [for (final e in actifs) if (!reconnus.contains(e.inscriptionId)) e];
  if (absents.isNotEmpty) {
    remarques.add(
      '${_pluriel(absents.length, 'élève')} de ${ctx.classeNom} '
      '${absents.length > 1 ? 'ne figurent' : 'ne figure'} pas dans le fichier : '
      '${absents.length > 1 ? 'leurs notes ne changent' : 'ses notes ne changent'} pas.',
    );
  }

  return RapportImportNotes(
    problemesFichier: problemes,
    remarquesFichier: remarques,
    lignes: lignes,
    colonnes: resumes,
    plan: plan,
    absentsDuFichier: absents,
    nbLignesVides: nbVides,
  );
}

CaseNote _lireCase(Cellule cellule, _Col col, Saisie? ancienne, bool remplacer) {
  CaseNote erreur(String texte, String message) => CaseNote(
        colonne: col.index,
        texte: texte,
        etat: EtatCaseNote.erreur,
        ancienne: ancienne,
        message: message,
      );
  if (cellule.vide) {
    return CaseNote(
      colonne: col.index,
      texte: '',
      etat: EtatCaseNote.vide,
      ancienne: ancienne,
    );
  }
  if (cellule.formule) {
    return erreur(
      cellule.texte,
      'la cellule contient une formule : remplacez-la par sa valeur '
      '(Copier, puis Collage spécial > Valeurs).',
    );
  }
  if (cellule.date != null) {
    return erreur(cellule.texte, '« ${cellule.texte} » est une date, pas une note.');
  }
  final texte = _texteNote(cellule);
  final lecture = lireNoteSaisie(texte, bareme: col.bareme);
  if (lecture.estInvalide) return erreur(texte, lecture.erreur!);
  final saisie = lecture.saisie;
  if (saisie == null) {
    return CaseNote(
      colonne: col.index,
      texte: '',
      etat: EtatCaseNote.vide,
      ancienne: ancienne,
    );
  }
  final affiche = texteSaisie(saisie);
  EtatCaseNote etat;
  if (ancienne == null) {
    etat = EtatCaseNote.nouvelle;
  } else if (ancienne == saisie) {
    etat = EtatCaseNote.identique;
  } else {
    etat = remplacer ? EtatCaseNote.remplacee : EtatCaseNote.conflit;
  }
  return CaseNote(
    colonne: col.index,
    texte: affiche,
    etat: etat,
    saisie: saisie,
    ancienne: ancienne,
  );
}

// ------------------------------------------------- Fichier GESCO (liste vierge)

/// Une colonne de notes décrite par la feuille technique « GESCO ».
class ColonneGesco {
  const ColonneGesco({
    required this.feuille,
    required this.matiereId,
    required this.matiere,
    required this.colonne,
    required this.titre,
    required this.type,
    required this.mois,
    required this.bareme,
    required this.coefficient,
    required this.evaluationId,
    required this.ligneDebut,
    required this.ligneFin,
  });

  /// Onglet de la matière.
  final String feuille;
  final int matiereId;
  final String matiere;

  /// Numéro de la colonne dans Excel (A = 1).
  final int colonne;
  final String titre;
  final TypeEvaluation type;
  final int mois;
  final int bareme;
  final int coefficient;

  /// Évaluation existante, ou 0 si elle sera créée à l'import.
  final int evaluationId;

  /// Première et dernière ligne des élèves (numéros Excel, à partir de 1).
  final int ligneDebut;
  final int ligneFin;
}

/// Contenu de la feuille technique d'une liste de notes produite par GESCO.
class ListeGescoLue {
  const ListeGescoLue({
    required this.version,
    required this.annee,
    required this.classeId,
    required this.classeNom,
    required this.enseignantNom,
    required this.mois,
    required this.colonnes,
  });

  final int version;
  final String annee;
  final int classeId;
  final String classeNom;
  final String enseignantNom;
  final int mois;
  final List<ColonneGesco> colonnes;

  bool get versionSupportee => version >= 1 && version <= versionFormatListeNotes;
}

int? _entier(Cellule c) {
  final n = c.nombre;
  if (n != null) return n.round();
  return int.tryParse(c.texte.trim());
}

/// Lit la feuille « GESCO » d'un classeur. Null si le classeur n'en a pas :
/// ce n'est pas une liste produite par GESCO.
ListeGescoLue? lireFeuilleTechnique(ClasseurLu classeur) {
  final f = classeur.feuille(feuilleTechnique);
  if (f == null || f.cellule(1, 1).texte != formatListeNotes) return null;
  final classeId = _entier(f.cellule(3, 1));
  if (classeId == null) return null;
  final colonnes = <ColonneGesco>[];
  for (var i = 8; i < f.nbLignes; i++) {
    if (f.ligneVide(i)) continue;
    final matiereId = _entier(f.cellule(i, 1));
    final colonne = _entier(f.cellule(i, 3));
    final mois = _entier(f.cellule(i, 6));
    final bareme = _entier(f.cellule(i, 7));
    final coefficient = _entier(f.cellule(i, 8));
    final evaluationId = _entier(f.cellule(i, 9));
    final debut = _entier(f.cellule(i, 10));
    final fin = _entier(f.cellule(i, 11));
    if (matiereId == null ||
        colonne == null ||
        mois == null ||
        bareme == null ||
        coefficient == null ||
        evaluationId == null ||
        debut == null ||
        fin == null) {
      continue;
    }
    colonnes.add(ColonneGesco(
      feuille: f.cellule(i, 0).texte,
      matiereId: matiereId,
      matiere: f.cellule(i, 2).texte,
      colonne: colonne,
      titre: f.cellule(i, 4).texte,
      type: TypeEvaluation.depuisCle(f.cellule(i, 5).texte),
      mois: mois,
      bareme: bareme,
      coefficient: coefficient,
      evaluationId: evaluationId,
      ligneDebut: debut,
      ligneFin: fin,
    ));
  }
  return ListeGescoLue(
    version: _entier(f.cellule(1, 2)) ?? 0,
    annee: f.cellule(2, 1).texte,
    classeId: classeId,
    classeNom: f.cellule(3, 2).texte,
    enseignantNom: f.cellule(4, 2).texte,
    mois: _entier(f.cellule(5, 1)) ?? 0,
    colonnes: colonnes,
  );
}

/// Ce que l'on déduit d'une liste GESCO pour la matière choisie.
class PropositionGesco {
  const PropositionGesco({
    this.table,
    this.mapping,
    this.problemes = const [],
    this.remarques = const [],
  });

  final TableLue? table;
  final MappingNotes? mapping;

  /// Pourquoi le fichier ne peut pas être lu automatiquement.
  final List<String> problemes;
  final List<String> remarques;

  bool get utilisable => problemes.isEmpty && table != null && mapping != null;
}

/// Reconnaît dans [classeur] la feuille de la matière du contexte et associe
/// ses colonnes aux évaluations décrites par la feuille technique.
///
/// Refus (avec explication) si le fichier concerne une autre classe, une
/// autre année ou une autre matière, ou si le tableau a été modifié (colonne
/// ajoutée, supprimée ou déplacée) : mieux vaut refuser que mettre des notes
/// dans la mauvaise évaluation.
PropositionGesco proposerDepuisListeGesco({
  required ClasseurLu classeur,
  required ListeGescoLue liste,
  required ContexteImportNotes ctx,
}) {
  final problemes = <String>[];
  if (!liste.versionSupportee) {
    problemes.add(
      'Ce fichier a été créé par une autre version de GESCO (format ${liste.version}) : '
      'utilisez l\'association manuelle des colonnes.',
    );
  }
  if (liste.classeId != ctx.classeId) {
    problemes.add(
      'Ce fichier est la liste de la classe « ${liste.classeNom} », '
      'mais vous avez choisi « ${ctx.classeNom} ».',
    );
  }
  if (cleColonne(liste.annee) != cleColonne(ctx.anneeLibelle)) {
    problemes.add(
      'Ce fichier concerne l\'année scolaire ${liste.annee}, '
      'alors que l\'année en cours est ${ctx.anneeLibelle}.',
    );
  }
  final colonnes = [
    for (final c in liste.colonnes)
      if (c.matiereId == ctx.matiereId) c,
  ];
  if (colonnes.isEmpty && problemes.isEmpty) {
    final matieres = {for (final c in liste.colonnes) c.matiere}.join(', ');
    problemes.add(
      'Ce fichier ne contient aucune colonne pour la matière ${ctx.matiereNom}'
      '${matieres.isEmpty ? '' : ' (matières du fichier : $matieres)'}.',
    );
  }
  if (problemes.isNotEmpty) return PropositionGesco(problemes: problemes);

  // L'onglet est retrouvé par son nom ; s'il a été renommé, par la matière
  // inscrite en tête de la feuille.
  FeuilleLue? feuille = classeur.feuille(colonnes.first.feuille);
  if (feuille == null) {
    for (final f in classeur.feuilles) {
      if (cleColonne(f.cellule(4, 2).texte) == cleColonne(ctx.matiereNom)) {
        feuille = f;
        break;
      }
    }
  }
  if (feuille == null) {
    return PropositionGesco(
      problemes: ['La feuille de la matière ${ctx.matiereNom} est introuvable dans le fichier.'],
    );
  }
  if (cleColonne(feuille.cellule(ligneEnteteTableau, colonneMatricule).texte) != 'matricule') {
    return PropositionGesco(
      problemes: [
        'Le tableau de la feuille « ${feuille.nom} » a été modifié : la ligne de titres '
        '(Matricule, Nom et prénom...) n\'est plus à la ligne ${ligneEnteteTableau + 1}. '
        'Utilisez l\'association manuelle des colonnes.',
      ],
    );
  }

  final table = lireTable(feuille, indexEntete: ligneEnteteTableau);
  final cibles = <int, CibleColonne>{};
  for (final c in colonnes) {
    final index = c.colonne - 1;
    final titreFichier = table.titreColonne(index);
    if (index < 0 ||
        index >= table.nbColonnes ||
        !cleColonne(table.entetes[index]).contains(cleColonne(c.titre))) {
      return PropositionGesco(
        problemes: [
          'La colonne « ${c.titre} » n\'est plus à sa place dans la feuille « ${feuille.nom} » '
          '(en ${TableLue.lettre(index < 0 ? 0 : index)}, on trouve « $titreFichier »). '
          'Le fichier a été modifié : utilisez l\'association manuelle des colonnes.',
        ],
      );
    }
    cibles[index] = CibleColonne(
      evaluationId: c.evaluationId > 0 ? c.evaluationId : null,
      titre: c.titre,
      type: c.type,
      mois: c.mois,
      bareme: c.bareme,
      coefficient: c.coefficient,
      baremeAnnonce: c.bareme,
    );
  }
  return PropositionGesco(
    table: table,
    mapping: MappingNotes(
      colonneMatricule: colonneMatricule,
      colonneNom: colonneNom,
      colonnes: cibles,
    ),
    remarques: [
      'Liste GESCO reconnue : ${liste.classeNom}, ${ctx.matiereNom}, '
          '${_pluriel(colonnes.length, 'colonne')} de notes.',
    ],
  );
}

// -------------------------------------------- Association automatique (autre fichier)

const Set<String> _titresMatricule = {
  'matricule',
  'n matricule',
  'no matricule',
  'numero matricule',
  'numero de matricule',
  'identifiant',
  'id',
  'mat',
};

const Set<String> _titresNomComplet = {
  'nom et prenom',
  'nom et prenoms',
  'nom prenom',
  'nom prenoms',
  'noms et prenoms',
  'nom complet',
  'eleve',
  'eleves',
  'nom de l eleve',
  'nom eleve',
  'nom et prenom de l eleve',
};

const Set<String> _titresNom = {'nom', 'noms', 'nom de famille', 'patronyme'};
const Set<String> _titresPrenom = {'prenom', 'prenoms'};

/// Mots d'un titre de colonne qui ne désignent jamais une note.
const Set<String> _motsIgnores = {
  'n',
  'no',
  'num',
  'numero',
  'ordre',
  'rang',
  'classement',
  'moyenne',
  'moy',
  'total',
  'observation',
  'observations',
  'appreciation',
  'appreciations',
  'remarque',
  'remarques',
  'commentaire',
  'commentaires',
  'decision',
  'mention',
  'telephone',
  'tel',
};

bool _ressembleAUneNote(Cellule c) {
  if (c.date != null || c.formule) return false;
  if (c.nombre != null) return c.nombre! >= 0;
  final mot = cleColonne(c.texte);
  return const {'a', 'abs', 'absent', 'absente', 'd', 'disp', 'dispense', 'dispensee'}
      .contains(mot);
}

/// Nature probable d'une évaluation d'après son titre.
TypeEvaluation typeDepuisTitre(String titre) {
  final t = cleColonne(titre);
  if (t.contains('interro')) return TypeEvaluation.interrogation;
  if (t.contains('compo')) return TypeEvaluation.composition;
  if (t.contains('exam')) return TypeEvaluation.examen;
  if (t.contains('devoir') || t.split(' ').contains('dev')) return TypeEvaluation.devoir;
  return TypeEvaluation.evaluation;
}

/// Titre sans l'indication du barème : « Devoir 1\n(sur 20) » -> « Devoir 1 » ;
/// le barème annoncé (20) est retourné à part.
({String titre, int? bareme}) separerBaremeDuTitre(String entete) {
  final plat = entete.replaceAll(RegExp(r'\s+'), ' ').trim();
  final m = RegExp(r'[\(\[]?\s*(?:sur\s*|/\s*)(\d{1,4})\s*[\)\]]?\s*$', caseSensitive: false)
      .firstMatch(plat);
  if (m == null) return (titre: plat, bareme: null);
  final bareme = int.parse(m.group(1)!);
  final titre = plat.substring(0, m.start).trim();
  return (titre: titre.isEmpty ? plat : titre, bareme: baremeValide(bareme) ? bareme : null);
}

/// Association proposée pour un tableau quelconque (l'utilisateur la corrige).
///
/// - le matricule et le nom sont reconnus d'après leurs titres ;
/// - une colonne devient une colonne de notes si son titre n'est pas celui
///   d'un total, d'un rang, d'observations... et si ses valeurs sont des
///   nombres, ABS ou DISP ;
/// - la colonne reprend l'évaluation existante de même titre dans la période,
///   sinon une évaluation nouvelle est proposée au mois [moisParDefaut].
MappingNotes proposerAssociationNotes({
  required TableLue table,
  required ContexteImportNotes ctx,
  required int moisParDefaut,
}) {
  int? colonneMat;
  int? colonneNomComplet;
  int? colonneNom;
  int? colonnePrenom;
  for (var i = 0; i < table.nbColonnes; i++) {
    final cle = cleColonne(table.entetes[i]);
    if (colonneMat == null && _titresMatricule.contains(cle)) {
      colonneMat = i;
    } else if (colonneNomComplet == null && _titresNomComplet.contains(cle)) {
      colonneNomComplet = i;
    } else if (colonneNom == null && _titresNom.contains(cle)) {
      colonneNom = i;
    } else if (colonnePrenom == null && _titresPrenom.contains(cle)) {
      colonnePrenom = i;
    }
  }
  final nom = colonneNomComplet ?? colonneNom;
  final prenom = colonneNomComplet == null ? colonnePrenom : null;
  final identite = {
    if (colonneMat != null) colonneMat,
    if (nom != null) nom,
    if (prenom != null) prenom,
    if (colonneNom != null) colonneNom,
    if (colonnePrenom != null) colonnePrenom,
    if (colonneNomComplet != null) colonneNomComplet,
  };

  final evaluationsMatiere = [
    for (final e in ctx.evaluations)
      if (e.matiereId == ctx.matiereId &&
          e.classeId == ctx.classeId &&
          ctx.moisTrimestre.contains(e.mois))
        e,
  ];

  final colonnes = <int, CibleColonne>{};
  for (var i = 0; i < table.nbColonnes; i++) {
    if (identite.contains(i)) continue;
    final entete = table.entetes[i];
    final cle = cleColonne(entete);
    if (cle.isEmpty || cle.split(' ').any(_motsIgnores.contains)) continue;
    var nonVides = 0, notes = 0;
    for (final l in table.lignes) {
      final c = l.cellule(i);
      if (c.vide) continue;
      nonVides++;
      if (_ressembleAUneNote(c)) notes++;
    }
    if (notes == 0 || notes * 10 < nonVides * 7) continue;

    final separe = separerBaremeDuTitre(entete);
    final cleTitre = cleColonne(separe.titre);
    Evaluation? existante;
    for (final e in evaluationsMatiere) {
      if (cleColonne(e.titre) != cleTitre) continue;
      if (existante == null || e.mois == moisParDefaut) existante = e;
    }
    colonnes[i] = existante != null
        ? CibleColonne(
            evaluationId: existante.id,
            titre: existante.titre,
            type: existante.type,
            mois: existante.mois,
            bareme: existante.bareme,
            coefficient: existante.coefficient,
            baremeAnnonce: separe.bareme,
          )
        : CibleColonne(
            titre: separe.titre,
            type: typeDepuisTitre(separe.titre),
            mois: moisParDefaut,
            bareme: separe.bareme ?? ctx.matiereBareme,
            baremeAnnonce: separe.bareme,
          );
  }
  return MappingNotes(
    colonneMatricule: colonneMat,
    colonneNom: nom,
    colonnePrenom: prenom,
    colonnes: colonnes,
  );
}

// ------------------------------------------------------------- Rapport Excel

CelluleEcrite _t(String s, [StyleCellule style = StyleCellule.normal]) => CelluleEcrite(s, style);
CelluleEcrite _h(String s) => CelluleEcrite(s, StyleCellule.entete);

/// Rapport de vérification, à ouvrir dans Excel, en deux feuilles :
/// - « Rapport » : problèmes du fichier, remarques, une ligne par ligne du
///   fichier ayant une erreur ou une remarque, élèves absents du fichier ;
/// - « Colonnes » : le bilan de chaque colonne de notes.
List<FeuilleEcrite> feuillesRapportImportNotes({
  required String etablissement,
  required String nomFichier,
  required DateTime date,
  required ContexteImportNotes ctx,
  required RapportImportNotes rapport,
}) {
  String d2(int n) => n.toString().padLeft(2, '0');
  final quand = '${d2(date.day)}/${d2(date.month)}/${date.year}';
  final lignes = <List<CelluleEcrite?>>[
    [_t(etablissement.isEmpty ? 'Établissement' : etablissement, StyleCellule.titre)],
    [_t('Rapport de vérification de l\'import des notes', StyleCellule.etiquette)],
    [
      _t(
        'Fichier « $nomFichier »  ·  ${ctx.classeNom}  ·  ${ctx.matiereNom}  ·  '
        '${ctx.trimestreLibelle}  ·  Année scolaire ${ctx.anneeLibelle}  ·  Vérifié le $quand',
        StyleCellule.discret,
      ),
    ],
    [
      _t(
        '${rapport.nbNotesAEcrire} notes à enregistrer  ·  ${rapport.nbConservees} conservées '
        '(différentes de GESCO)  ·  ${rapport.nbIdentiques} déjà identiques  ·  '
        '${rapport.nbNotesRemplacees} remplacées  ·  ${rapport.nbLignesErreur} lignes en erreur',
        StyleCellule.discret,
      ),
    ],
    <CelluleEcrite?>[],
  ];
  for (final p in rapport.problemesFichier) {
    lignes.add([_t('Problème : $p', StyleCellule.etiquette)]);
  }
  for (final r in rapport.remarquesFichier) {
    lignes.add([_t(r, StyleCellule.discret)]);
  }
  if (rapport.problemesFichier.isNotEmpty || rapport.remarquesFichier.isNotEmpty) {
    lignes.add(<CelluleEcrite?>[]);
  }
  lignes.add([_h('Ligne'), _h('Matricule'), _h('Nom'), _h('Résultat'), _h('Détail')]);
  for (final l in rapport.lignes) {
    final resultat = l.enErreur
        ? 'Erreur (ligne ignorée)'
        : l.avertissements.isNotEmpty
            ? 'À importer (remarque)'
            : null;
    if (resultat == null) continue;
    final eleve = l.eleve;
    lignes.add([
      CelluleEcrite(l.numero, StyleCellule.entier),
      _t(l.matricule.isEmpty && eleve != null ? eleve.matricule : l.matricule),
      _t(l.nom.isEmpty && eleve != null ? eleve.nomComplet : l.nom),
      _t(resultat),
      _t([...l.erreurs, ...l.avertissements].join('\n')),
    ]);
  }
  if (rapport.absentsDuFichier.isNotEmpty) {
    lignes.add(<CelluleEcrite?>[]);
    lignes.add([_t('Élèves de la classe absents du fichier', StyleCellule.etiquette)]);
    for (final e in rapport.absentsDuFichier) {
      lignes.add([null, _t(e.matricule), _t(e.nomComplet), _t('Notes inchangées')]);
    }
  }
  final feuilles = [
    FeuilleEcrite('Rapport', lignes, largeurs: const [10, 16, 30, 26, 90]),
  ];

  if (rapport.colonnes.isNotEmpty) {
    feuilles.add(FeuilleEcrite(
      'Colonnes',
      [
        [_t('Bilan par colonne de notes', StyleCellule.etiquette)],
        <CelluleEcrite?>[],
        [
          _h('Colonne du fichier'),
          _h('Évaluation'),
          _h('Mois'),
          _h('Barème'),
          _h('Nouvelles'),
          _h('Remplacées'),
          _h('Identiques'),
          _h('Conservées'),
          _h('Vides'),
          _h('Erreurs'),
          _h('Sans note après import'),
        ],
        for (final c in rapport.colonnes)
          [
            _t(c.libelle),
            _t(c.creer ? '${c.titre} (à créer)' : c.titre),
            _t(libelleMois(c.mois)),
            CelluleEcrite(c.bareme, StyleCellule.entier),
            CelluleEcrite(c.nbNouvelles, StyleCellule.entier),
            CelluleEcrite(c.nbRemplacees, StyleCellule.entier),
            CelluleEcrite(c.nbIdentiques, StyleCellule.entier),
            CelluleEcrite(c.nbConservees, StyleCellule.entier),
            CelluleEcrite(c.nbVides, StyleCellule.entier),
            CelluleEcrite(c.nbErreurs, StyleCellule.entier),
            CelluleEcrite(c.nbSansNote, StyleCellule.entier),
          ],
      ],
      largeurs: const [28, 30, 12, 8, 11, 11, 11, 11, 8, 8, 22],
    ));
  }
  return feuilles;
}
