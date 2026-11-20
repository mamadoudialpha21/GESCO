/// Calculs de résultats d'une classe, partagés par la page « Résultats et
/// classements », le tableau de bord et (plus tard) les bulletins.
///
/// Rien ici ne dessine d'écran : la partie « chargement » lit la base, la
/// partie « lignes » transforme le résultat du moteur en listes prêtes à
/// afficher ou à exporter.
library;

import '../data/modeles_donnees.dart';
import '../domain/arrondi.dart';
import '../domain/calendrier.dart';
import '../domain/modeles.dart';
import '../domain/moteur_resultats.dart';
import '../domain/periodes.dart';
import '../domain/statistiques.dart';
import 'services.dart';

/// Une classe, ses élèves, ses matières et son moteur de calcul.
class CalculClasse {
  CalculClasse({
    required this.classe,
    required this.eleves,
    required this.matieres,
    required this.config,
    required this.calendrier,
    required Map<int, Map<int, Map<int, Saisie>>> saisies,
  })  : donnees = [
          for (final e in eleves)
            DonneesEleve(
              inscriptionId: e.inscriptionId,
              nom: e.nom,
              prenom: e.prenom,
              sexe: e.sexe,
              saisies: saisies[e.inscriptionId] ?? const {},
              actif: e.actif,
            ),
        ] {
    moteur = MoteurResultats(
      matieres: [for (final m in matieres) m.versCoef()],
      eleves: donnees,
      config: config,
      calendrier: calendrier,
    );
  }

  final ClasseResume classe;

  /// Élèves de la classe, triés par nom (partis et abandons inclus).
  final List<EleveInscrit> eleves;
  final List<MatiereClasse> matieres;
  final ConfigResultats config;
  final Calendrier calendrier;
  final List<DonneesEleve> donnees;
  late final MoteurResultats moteur;

  /// Résultats (moyenne, rang, mention, décision) sur une étendue.
  List<ResultatEleve> resultats(Portee portee) => moteur.resultats(portee);

  /// Statistiques de la classe sur une étendue (élèves actifs seulement).
  StatsClasse stats(Portee portee) => calculerStats(
        eleves: donnees,
        resultats: resultats(portee),
        config: config,
      );
}

/// Charge une classe avec ses notes (notes du mois et évaluations).
///
/// [config] et [calendrier] sont ceux de l'année : ils sont lus une seule fois
/// par l'appelant quand plusieurs classes sont chargées.
Future<CalculClasse> chargerCalculClasse(
  Services services,
  ClasseResume classe, {
  required ConfigResultats config,
  required Calendrier calendrier,
}) async {
  final id = classe.classe.id;
  final effectives = await services.evaluations.saisiesEffectives(
    id,
    absenceEgaleZero: config.absenceEgaleZero,
  );
  return CalculClasse(
    classe: classe,
    eleves: await services.eleves.lister(classe.classe.anneeId, classeId: id),
    matieres: await services.matieres.lister(id),
    config: config,
    calendrier: calendrier,
    saisies: effectives.saisies,
  );
}

/// Charge toutes les classes d'une année (dans l'ordre de la liste des classes).
Future<List<CalculClasse>> chargerToutesLesClasses(
  Services services,
  int anneeId, {
  List<ClasseResume>? classes,
  ConfigResultats? config,
  Calendrier? calendrier,
}) async {
  final liste = classes ?? await services.classes.lister(anneeId);
  final cfg = config ?? await services.configs.lire(anneeId);
  final cal = calendrier ?? await services.calendriers.lire(anneeId);
  return [
    for (final c in liste)
      await chargerCalculClasse(services, c, config: cfg, calendrier: cal),
  ];
}

// ---------------------------------------------------------------- Élèves

/// Une ligne du classement d'une classe.
class LigneClassement {
  const LigneClassement({
    required this.eleve,
    required this.moyenne,
    required this.rang,
    required this.exAequo,
    required this.mention,
    required this.decision,
    required this.incomplet,
  });

  final EleveInscrit eleve;

  /// Moyenne (ou note de la matière) en centièmes, null si aucune note.
  final int? moyenne;

  /// Rang avec ex æquo (1, 1, 3), null pour un élève non classé.
  final int? rang;

  /// Vrai si au moins un autre élève a le même rang.
  final bool exAequo;
  final String mention;
  final String decision;
  final bool incomplet;

  /// Élève classé : actif et avec une moyenne.
  bool get classe => rang != null;
}

/// Classement des élèves d'une classe : classés d'abord (par rang, puis par
/// nom), puis non classés (sans moyenne, partis, abandons) par nom.
///
/// Sans [matiereId], le classement porte sur la moyenne générale ; sinon sur
/// la note de la matière (mention d'après la note, sans décision).
List<LigneClassement> lignesClassement(
  CalculClasse calcul,
  Portee portee, {
  int? matiereId,
}) {
  final lignes = <LigneClassement>[];
  if (matiereId == null) {
    final resultats = {
      for (final r in calcul.resultats(portee)) r.inscriptionId: r,
    };
    for (final e in calcul.eleves) {
      final r = resultats[e.inscriptionId]!;
      lignes.add(LigneClassement(
        eleve: e,
        moyenne: r.moyenne,
        rang: r.rang,
        exAequo: false,
        mention: r.mention,
        decision: r.decision,
        incomplet: r.incomplet,
      ));
    }
  } else {
    final notes = {
      for (final r in calcul.moteur.classementMatiere(matiereId, portee))
        r.inscriptionId: r,
    };
    for (final e in calcul.eleves) {
      final r = notes[e.inscriptionId]!;
      lignes.add(LigneClassement(
        eleve: e,
        moyenne: r.note,
        rang: r.rang,
        exAequo: false,
        mention: r.note == null ? '' : calcul.config.mention(r.note!),
        decision: '',
        incomplet: false,
      ));
    }
  }

  // Ex æquo : un rang partagé par plusieurs élèves.
  final parRang = <int, int>{};
  for (final l in lignes) {
    if (l.rang != null) parRang[l.rang!] = (parRang[l.rang!] ?? 0) + 1;
  }
  final avecExAequo = [
    for (final l in lignes)
      LigneClassement(
        eleve: l.eleve,
        moyenne: l.moyenne,
        rang: l.rang,
        exAequo: l.rang != null && (parRang[l.rang!] ?? 0) > 1,
        mention: l.mention,
        decision: l.decision,
        incomplet: l.incomplet,
      ),
  ];
  // Tri stable : à rang égal (ou sans rang), l'ordre alphabétique d'origine.
  final indices = [for (var i = 0; i < avecExAequo.length; i++) i];
  indices.sort((a, b) {
    final ra = avecExAequo[a].rang;
    final rb = avecExAequo[b].rang;
    if (ra != null && rb != null) {
      final c = ra.compareTo(rb);
      return c != 0 ? c : a.compareTo(b);
    }
    if (ra != null) return -1;
    if (rb != null) return 1;
    return a.compareTo(b);
  });
  return [for (final i in indices) avecExAequo[i]];
}

// ---------------------------------------------------------------- Classes

/// Résultat d'une classe sur une étendue, pour la comparaison des classes.
class ResumeClasse {
  const ResumeClasse({required this.classe, required this.stats, required this.rang});

  final ClasseResume classe;
  final StatsClasse stats;

  /// Rang de la classe d'après sa moyenne (ex æquo possibles), null si aucun
  /// élève de la classe n'a de moyenne.
  final int? rang;
}

/// Compare les classes sur une étendue, de la meilleure moyenne à la plus
/// faible (les classes sans moyenne en dernier, dans l'ordre d'origine).
List<ResumeClasse> comparerClasses(List<CalculClasse> calculs, Portee portee) {
  final stats = [for (final c in calculs) c.stats(portee)];
  final rangs = calculerRangs({
    for (var i = 0; i < calculs.length; i++)
      calculs[i].classe.classe.id: stats[i].moyenneClasse,
  });
  final resumes = [
    for (var i = 0; i < calculs.length; i++)
      ResumeClasse(
        classe: calculs[i].classe,
        stats: stats[i],
        rang: rangs[calculs[i].classe.classe.id],
      ),
  ];
  final indices = [for (var i = 0; i < resumes.length; i++) i];
  indices.sort((a, b) {
    final ra = resumes[a].rang;
    final rb = resumes[b].rang;
    if (ra != null && rb != null) {
      final c = ra.compareTo(rb);
      return c != 0 ? c : a.compareTo(b);
    }
    if (ra != null) return -1;
    if (rb != null) return 1;
    return a.compareTo(b);
  });
  return [for (final i in indices) resumes[i]];
}

// ------------------------------------------------- Synthèse de l'établissement

/// Un élève du palmarès de l'établissement.
class ElevePalmares {
  const ElevePalmares({
    required this.eleve,
    required this.classeNom,
    required this.moyenne,
    required this.rang,
  });

  final EleveInscrit eleve;
  final String classeNom;
  final int moyenne;

  /// Rang dans l'établissement (ex æquo possibles : 1, 1, 3).
  final int rang;
}

/// Chiffres d'une classe pour le tableau de bord.
class SyntheseClasse {
  const SyntheseClasse({
    required this.classe,
    required this.moyennesPeriodes,
    required this.moyennesMensuelles,
    required this.annee,
  });

  final ClasseResume classe;

  /// Moyenne de la classe pour chaque période du calendrier (même ordre que
  /// [Calendrier.periodes]) ; null si personne n'est évalué.
  final List<int?> moyennesPeriodes;

  /// Moyenne de la classe pour chaque mois, d'octobre à juin ([moisScolaires]).
  final List<int?> moyennesMensuelles;

  /// Statistiques de l'année entière (moyenne, taux de réussite...).
  final StatsClasse annee;

  /// Vrai si au moins un mois a une moyenne (la classe a des notes).
  bool get aDesNotes => moyennesMensuelles.any((m) => m != null);
}

/// Résultats de tout l'établissement sur l'année, pour le tableau de bord.
class SyntheseEtablissement {
  const SyntheseEtablissement({
    required this.calendrier,
    required this.config,
    required this.classes,
    required this.moyenneGenerale,
    required this.tauxReussiteCentiemes,
    required this.nbEvalues,
    required this.nbAdmis,
    required this.meilleurs,
  });

  final Calendrier calendrier;
  final ConfigResultats config;
  final List<SyntheseClasse> classes;

  /// Moyenne de tous les élèves évalués (année entière), null s'il n'y en a pas.
  final int? moyenneGenerale;

  /// Part des élèves évalués qui atteignent le seuil d'admission, en
  /// centièmes de pourcent (8333 = 83,33 %).
  final int? tauxReussiteCentiemes;
  final int nbEvalues;
  final int nbAdmis;

  /// Les meilleurs élèves de l'année (rang 5 au plus, ex æquo compris).
  final List<ElevePalmares> meilleurs;

  bool get aDesNotes => nbEvalues > 0 || classes.any((c) => c.aDesNotes);
}

/// Calcule la synthèse de l'établissement.
///
/// [nbMeilleurs] : on garde les élèves dont le rang est au plus [nbMeilleurs]
/// (les ex æquo restent ensemble), dans la limite de deux fois ce nombre.
SyntheseEtablissement synthetiserEtablissement(
  List<CalculClasse> calculs, {
  required Calendrier calendrier,
  required ConfigResultats config,
  int nbMeilleurs = 5,
}) {
  const annee = Portee.annee();
  final classes = <SyntheseClasse>[];
  final candidats = <(EleveInscrit, String, int)>[];
  var somme = 0;
  var nbEvalues = 0;
  var nbAdmis = 0;

  for (final c in calculs) {
    final resultats = c.resultats(annee);
    classes.add(SyntheseClasse(
      classe: c.classe,
      moyennesPeriodes: [
        for (final p in calendrier.periodes) c.stats(Portee.periode(p)).moyenneClasse,
      ],
      moyennesMensuelles: [
        for (final m in moisScolaires) c.stats(Portee.mois(m)).moyenneClasse,
      ],
      annee: calculerStats(eleves: c.donnees, resultats: resultats, config: config),
    ));
    final actifs = {
      for (final d in c.donnees)
        if (d.actif) d.inscriptionId,
    };
    final parInscription = {for (final e in c.eleves) e.inscriptionId: e};
    for (final r in resultats) {
      final m = r.moyenne;
      if (m == null || !actifs.contains(r.inscriptionId)) continue;
      somme += m;
      nbEvalues++;
      if (m >= config.seuilAdmission) nbAdmis++;
      candidats.add((parInscription[r.inscriptionId]!, c.classe.classe.nom, m));
    }
  }

  // Palmarès : tri par moyenne décroissante, puis par nom (ordre stable).
  candidats.sort((a, b) {
    final c = b.$3.compareTo(a.$3);
    if (c != 0) return c;
    final n = a.$1.nom.toLowerCase().compareTo(b.$1.nom.toLowerCase());
    if (n != 0) return n;
    return a.$1.prenom.toLowerCase().compareTo(b.$1.prenom.toLowerCase());
  });
  final meilleurs = <ElevePalmares>[];
  int? precedente;
  var rang = 0;
  for (var i = 0; i < candidats.length; i++) {
    final (eleve, classeNom, moyenne) = candidats[i];
    if (moyenne != precedente) {
      rang = i + 1;
      precedente = moyenne;
    }
    if (rang > nbMeilleurs || meilleurs.length >= 2 * nbMeilleurs) break;
    meilleurs.add(ElevePalmares(
      eleve: eleve,
      classeNom: classeNom,
      moyenne: moyenne,
      rang: rang,
    ));
  }

  return SyntheseEtablissement(
    calendrier: calendrier,
    config: config,
    classes: classes,
    moyenneGenerale: nbEvalues == 0 ? null : divisionArrondie(somme, nbEvalues),
    tauxReussiteCentiemes:
        nbEvalues == 0 ? null : divisionArrondie(nbAdmis * 10000, nbEvalues),
    nbEvalues: nbEvalues,
    nbAdmis: nbAdmis,
    meilleurs: meilleurs,
  );
}
