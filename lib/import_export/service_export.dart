/// Exports Excel (.xlsx) et listes vierges : lit la base, construit les
/// feuilles (voir `exports_excel.dart` et `liste_vierge.dart`), écrit le
/// classeur et vérifie le fichier enregistré.
library;

import 'dart:io';
import 'dart:typed_data';

import '../app/calcul_classe.dart';
import '../app/services.dart';
import '../data/erreurs.dart';
import '../data/modeles_donnees.dart';
import '../documents/ouvrir_document.dart';
import '../domain/calendrier.dart';
import '../domain/periodes.dart';
import '../domain/permissions.dart';
import '../tableur/classeur.dart';
import '../tableur/xlsx.dart';
import 'exports_excel.dart';
import 'liste_vierge.dart';
import 'modele_export.dart';

/// Les dix exports proposés.
enum TypeExport {
  eleves(
    'eleves',
    'Liste complète des élèves',
    'Tous les élèves inscrits, avec leur fiche (état civil, parents, tuteur, classe).',
  ),
  elevesParClasse(
    'eleves_par_classe',
    'Élèves par classe',
    'Une feuille par classe (ou une seule classe au choix).',
  ),
  notesParMatiere(
    'notes_par_matiere',
    'Notes par matière',
    'Pour une classe : les notes de chaque mois, la moyenne de chaque période, '
        'la moyenne annuelle et le rang, une feuille par matière.',
  ),
  notesParClasse(
    'notes_par_classe',
    'Notes par classe',
    'Les notes de chaque matière, la moyenne, le rang, la mention et la décision '
        'pour le mois ou la période choisis.',
  ),
  resultatsTrimestriels(
    'resultats_trimestriels',
    'Résultats trimestriels',
    'Moyenne, rang, mention et décision de chaque élève pour un trimestre '
        '(ou une période).',
  ),
  resultatsAnnuels(
    'resultats_annuels',
    'Résultats annuels',
    'Moyenne de chaque période, moyenne annuelle, rang, mention et décision.',
  ),
  classements(
    'classements',
    'Classements',
    'Classement des élèves d\'une classe (général, ou dans une matière), '
        'avec les ex æquo.',
  ),
  absences(
    'absences',
    'Absences et retards',
    'Totaux par élève, puis détail jour par jour.',
  ),
  statistiques(
    'statistiques',
    'Statistiques générales',
    'Effectifs, taux de réussite et moyennes : établissement et classe par classe.',
  ),
  admis(
    'admis',
    'Listes des admis et non admis',
    'Les élèves dont la moyenne atteint (ou non) le seuil d\'admission, '
        'toutes classes confondues.',
  );

  const TypeExport(this.cle, this.libelle, this.description);

  final String cle;
  final String libelle;
  final String description;

  /// Le choix d'une classe est obligatoire.
  bool get classeObligatoire => this == notesParMatiere;

  /// Le choix d'une classe est possible (sinon : toutes les classes, ou sans objet).
  bool get accepteClasse => this != eleves;

  /// Le choix d'une matière est possible (avec une classe).
  bool get accepteMatiere => this == notesParMatiere || this == classements;

  /// L'export dépend d'un mois, d'une période ou de l'année.
  bool get demandePeriode => switch (this) {
        notesParClasse || resultatsTrimestriels || classements || statistiques || admis => true,
        _ => false,
      };

  /// Seule une période (trimestre, semestre, séquence) a un sens.
  bool get periodeSeulement => this == resultatsTrimestriels;
}

/// Choix de l'utilisateur pour un export.
class OptionsExport {
  const OptionsExport({this.classeId, this.matiereId, this.cle = cleAnnee});

  /// Classe concernée ; null = toutes les classes (selon le type).
  final int? classeId;

  /// Matière concernée (avec [classeId]) ; null = toutes ou la moyenne générale.
  final int? matiereId;

  /// Étendue : `m11` (un mois), `t1` (une période), `annee`.
  final String cle;
}

/// Un classeur prêt à être enregistré.
class FichierExcel {
  const FichierExcel({
    required this.nomBase,
    required this.octets,
    required this.feuilles,
    this.avertissements = const [],
  });

  /// Nom du fichier sans horodatage ni extension.
  final String nomBase;
  final Uint8List octets;

  /// Noms des onglets, dans l'ordre.
  final List<String> feuilles;

  /// Classes ignorées et autres remarques à montrer à l'utilisateur.
  final List<String> avertissements;
}

/// Fichier enregistré et vérifié.
class FichierEnregistre {
  const FichierEnregistre({required this.fichier, required this.nbFeuilles});

  final File fichier;
  final int nbFeuilles;
}

/// Mois proposé par défaut pour une liste vierge : le mois en cours s'il fait
/// partie de l'année scolaire (octobre à juin), sinon octobre.
int moisParDefaut(DateTime maintenant) =>
    moisScolaires.contains(maintenant.month) ? maintenant.month : moisScolaires.first;

class ServiceExport {
  ServiceExport(this.services, {DateTime Function()? maintenant})
      : _maintenant = maintenant ?? DateTime.now;

  final Services services;
  final DateTime Function() _maintenant;

  // --------------------------------------------------------------- Contexte

  Future<ContexteExport> _contexte(int anneeId) async {
    final annee = await services.annees.obtenir(anneeId);
    if (annee == null) throw const ErreurGesco('Année scolaire introuvable.');
    final etablissement = await services.etablissements.lire();
    return ContexteExport(
      etablissement: etablissement.nom,
      annee: annee.libelle,
      date: _maintenant(),
    );
  }

  Future<List<ClasseResume>> _classes(int anneeId, int? classeId) async {
    final toutes = await services.classes.lister(anneeId);
    if (toutes.isEmpty) {
      throw const ErreurGesco('Aucune classe n\'existe pour cette année scolaire.');
    }
    if (classeId == null) return toutes;
    final choisies = [
      for (final c in toutes)
        if (c.classe.id == classeId) c,
    ];
    if (choisies.isEmpty) {
      throw const ErreurGesco('Cette classe n\'existe pas pour l\'année scolaire choisie.');
    }
    return choisies;
  }

  /// Classes chargées avec leurs notes, associées à l'étendue [cle] de leur
  /// calendrier. Une classe dont le calendrier n'a pas cette période est
  /// ignorée et signalée dans [avertissements].
  Future<List<ClassePortee>> _classesPortee(
    int anneeId,
    int? classeId,
    String cle,
    List<String> avertissements,
  ) async {
    final classes = await _classes(anneeId, classeId);
    final calculs = await chargerToutesLesClasses(services, anneeId, classes: classes);
    final resultat = <ClassePortee>[];
    for (final c in calculs) {
      final portee = c.calendrier.portee(cle);
      if (portee == null) {
        avertissements.add(
          'Classe ${c.classe.classe.nom} ignorée : sa période « $cle » n\'existe pas '
          'dans son calendrier.',
        );
        continue;
      }
      resultat.add(ClassePortee(c, portee));
    }
    if (resultat.isEmpty) {
      throw ErreurGesco(
        classeId == null
            ? 'Aucune classe n\'a la période choisie dans son calendrier.'
            : 'La période choisie n\'existe pas dans le calendrier de cette classe.',
      );
    }
    return resultat;
  }

  // ----------------------------------------------------------------- Export

  /// Construit le classeur de l'export [type] pour l'année [anneeId].
  /// Lève une [ErreurGesco] explicite s'il n'y a rien à exporter.
  Future<FichierExcel> construire(
    TypeExport type, {
    required int anneeId,
    OptionsExport options = const OptionsExport(),
  }) async {
    services.controle.exiger(Permission.importExport, 'exporter des données');
    if (type.classeObligatoire && options.classeId == null) {
      throw const ErreurGesco('Choisissez une classe pour cet export.');
    }
    if (type.periodeSeulement &&
        (options.cle == cleAnnee || RegExp(r'^m\d+$').hasMatch(options.cle))) {
      throw const ErreurGesco('Choisissez un trimestre (ou une période), pas un mois ni l\'année.');
    }
    final ctx = await _contexte(anneeId);
    final avertissements = <String>[];
    final feuilles = await _feuilles(type, ctx, anneeId, options, avertissements);
    if (feuilles.isEmpty) {
      throw const ErreurGesco('Il n\'y a rien à exporter avec ces choix.');
    }
    final octets = ecrireClasseur(feuilles);

    var nom = '${type.libelle} ${ctx.annee}';
    if (type.accepteClasse && options.classeId != null) {
      final classe = (await _classes(anneeId, options.classeId)).first;
      nom = '${type.libelle} ${classe.classe.nom} ${ctx.annee}';
    }
    await services.controle.noter(
      'export',
      'excel',
      details: '${type.libelle} (${feuilles.length} feuille${feuilles.length > 1 ? 's' : ''})',
    );
    return FichierExcel(
      nomBase: nom,
      octets: octets,
      feuilles: [for (final f in feuilles) nomOngletValide(f.nom)],
      avertissements: avertissements,
    );
  }

  Future<List<FeuilleEcrite>> _feuilles(
    TypeExport type,
    ContexteExport ctx,
    int anneeId,
    OptionsExport o,
    List<String> avertissements,
  ) async {
    switch (type) {
      case TypeExport.eleves:
        final fiches = await services.eleves.fichesInscrits(anneeId);
        if (fiches.isEmpty) {
          throw const ErreurGesco('Aucun élève n\'est inscrit pour cette année scolaire.');
        }
        return [
          feuilleEleves(
            ctx,
            'Élèves',
            'Liste complète des élèves',
            [for (final (e, i) in fiches) EleveExport(eleve: e, inscription: i)],
          ),
        ];

      case TypeExport.elevesParClasse:
        final classes = await _classes(anneeId, o.classeId);
        final fiches = await services.eleves.fichesInscrits(anneeId);
        final feuilles = <FeuilleEcrite>[];
        for (final c in classes) {
          final liste = [
            for (final (e, i) in fiches)
              if (i.classeId == c.classe.id) EleveExport(eleve: e, inscription: i),
          ];
          if (liste.isEmpty) continue;
          feuilles.add(feuilleEleves(ctx, c.classe.nom, 'Élèves de la classe ${c.classe.nom}', liste));
        }
        if (feuilles.isEmpty) {
          throw const ErreurGesco('Aucun élève n\'est inscrit dans les classes choisies.');
        }
        return feuilles;

      case TypeExport.notesParMatiere:
        final classes = await _classes(anneeId, o.classeId);
        final calcul = (await chargerToutesLesClasses(services, anneeId, classes: classes)).first;
        final matieres = [
          for (final m in calcul.matieres)
            if (o.matiereId == null || m.id == o.matiereId) m,
        ];
        if (matieres.isEmpty) {
          throw const ErreurGesco('Cette classe n\'a pas de matière à exporter.');
        }
        return [for (final m in matieres) feuilleNotesMatiere(ctx, calcul, m)];

      case TypeExport.notesParClasse:
        final cps = await _classesPortee(anneeId, o.classeId, o.cle, avertissements);
        return [for (final cp in cps) feuilleNotesClasse(ctx, cp.calcul, cp.portee)];

      case TypeExport.resultatsTrimestriels:
        final cps = await _classesPortee(anneeId, o.classeId, o.cle, avertissements);
        return [for (final cp in cps) feuilleResultats(ctx, cp.calcul, cp.portee)];

      case TypeExport.resultatsAnnuels:
        final cps = await _classesPortee(anneeId, o.classeId, cleAnnee, avertissements);
        return [for (final cp in cps) feuilleResultats(ctx, cp.calcul, cp.portee)];

      case TypeExport.classements:
        final cps = await _classesPortee(anneeId, o.classeId, o.cle, avertissements);
        final feuilles = <FeuilleEcrite>[];
        for (final cp in cps) {
          MatiereClasse? matiere;
          if (o.matiereId != null) {
            for (final m in cp.calcul.matieres) {
              if (m.id == o.matiereId) matiere = m;
            }
            if (matiere == null) {
              throw const ErreurGesco('Cette matière n\'appartient pas à la classe choisie.');
            }
          }
          feuilles.add(feuilleClassement(ctx, cp.calcul, cp.portee, matiere: matiere));
        }
        return feuilles;

      case TypeExport.absences:
        final classes = await _classes(anneeId, o.classeId);
        final tous = await services.eleves.lister(anneeId, classeId: o.classeId);
        final eleves = [
          for (final c in classes)
            for (final e in tous)
              if (e.classeId == c.classe.id) e,
        ];
        if (eleves.isEmpty) {
          throw const ErreurGesco('Aucun élève n\'est inscrit dans les classes choisies.');
        }
        final totaux = await services.absences.totauxAnnee(anneeId, classeId: o.classeId);
        final detail = await services.absences.listerAnnee(anneeId, classeId: o.classeId);
        return feuillesAbsences(ctx, eleves, totaux, detail);

      case TypeExport.statistiques:
        final cps = await _classesPortee(anneeId, o.classeId, o.cle, avertissements);
        return feuillesStatistiques(ctx, cps, libelle: libellePortee(cps.first.portee));

      case TypeExport.admis:
        final cps = await _classesPortee(anneeId, o.classeId, o.cle, avertissements);
        return feuillesAdmis(ctx, cps, libelle: libellePortee(cps.first.portee));
    }
  }

  // ---------------------------------------------------------- Listes vierges

  /// Listes de notes vierges pour les enseignants : un classeur par classe et
  /// par enseignant (les matières sans enseignant forment un classeur à part).
  ///
  /// [classeId] null : toutes les classes ; [enseignantId] : seulement les
  /// matières de cet enseignant. Une matière dont toutes les évaluations du mois
  /// sont validées n'a plus de colonne à remplir : elle est signalée et omise.
  Future<List<FichierExcel>> listesVierges({
    required int anneeId,
    required OptionsListeVierge options,
    int? classeId,
    int? enseignantId,
  }) async {
    services.controle.exiger(Permission.importExport, 'générer des listes de notes');
    if (!moisScolaires.contains(options.mois)) {
      throw const ErreurGesco('Choisissez un mois de l\'année scolaire (octobre à juin).');
    }
    final ctx = await _contexte(anneeId);
    final classes = await _classes(anneeId, classeId);
    final enseignants = {
      for (final r in await services.enseignants.lister())
        r.enseignant.id: r.enseignant.nomComplet,
    };
    if (enseignantId != null && !enseignants.containsKey(enseignantId)) {
      throw const ErreurGesco('Enseignant introuvable.');
    }

    final fichiers = <FichierExcel>[];
    final avertissements = <String>[];
    for (final c in classes) {
      final matieres = await services.matieres.lister(c.classe.id);
      final evaluations = [
        for (final r in await services.evaluations.lister(classeId: c.classe.id)) r.evaluation,
      ];
      final eleves = [
        for (final e in await services.eleves.lister(anneeId, classeId: c.classe.id))
          if (e.actif) e,
      ];

      // Matières groupées par enseignant, dans l'ordre des matières.
      final groupes = <int?, List<MatiereVierge>>{};
      for (final m in matieres) {
        if (enseignantId != null && m.enseignantId != enseignantId) continue;
        final colonnes = planifierColonnes(matiere: m, evaluations: evaluations, options: options);
        if (colonnes.isEmpty) {
          avertissements.add(
            'Classe ${c.classe.nom}, ${m.nom} : toutes les évaluations de '
            '${libelleMois(options.mois)} sont validées, aucune liste à remplir.',
          );
          continue;
        }
        (groupes[m.enseignantId] ??= []).add(MatiereVierge(matiere: m, colonnes: colonnes));
      }
      for (final entree in groupes.entries) {
        final nomEnseignant = entree.key == null ? '' : (enseignants[entree.key] ?? '');
        final liste = ListeVierge(
          classe: c.classe,
          matieres: entree.value,
          eleves: eleves,
          enseignantId: entree.key,
          enseignantNom: nomEnseignant,
        );
        final feuilles = construireListeVierge(
          ctx,
          liste,
          mois: options.mois,
          avecObservations: options.avecObservations,
        );
        fichiers.add(FichierExcel(
          nomBase: 'Liste notes ${c.classe.nom} '
              '${nomEnseignant.isEmpty ? 'sans enseignant' : nomEnseignant} '
              '${libelleMois(options.mois)}',
          octets: ecrireClasseur(feuilles),
          feuilles: [for (final f in feuilles) f.nom],
        ));
      }
    }
    if (fichiers.isEmpty) {
      throw ErreurGesco(
        avertissements.isEmpty
            ? 'Aucune matière à mettre en liste avec ces choix.'
            : avertissements.join('\n'),
      );
    }
    await services.controle.noter(
      'export',
      'liste_notes',
      details: '${fichiers.length} fichier${fichiers.length > 1 ? 's' : ''} '
          '(${libelleMois(options.mois)})',
    );
    // Les remarques concernent l'ensemble des listes : chaque fichier les porte.
    return [
      for (final f in fichiers)
        FichierExcel(
          nomBase: f.nomBase,
          octets: f.octets,
          feuilles: f.feuilles,
          avertissements: avertissements,
        ),
    ];
  }

  // ------------------------------------------------------------ Enregistrement

  /// Enregistre le classeur dans [dossier] (par défaut « Documents\GESCO »)
  /// sans jamais écraser un fichier, puis le relit : le fichier n'est annoncé
  /// comme créé que s'il s'ouvre comme un classeur Excel avec les mêmes onglets.
  Future<FichierEnregistre> enregistrer(
    FichierExcel f, {
    Directory? dossier,
  }) async {
    final fichier = await enregistrerFichier(
      f.octets,
      f.nomBase,
      'xlsx',
      dossier: dossier,
      maintenant: _maintenant(),
    );
    try {
      final relu = lireClasseur(await fichier.readAsBytes());
      if (relu.feuilles.length != f.feuilles.length) {
        throw const ErreurGesco('Le fichier enregistré est incomplet.');
      }
    } catch (_) {
      if (fichier.existsSync()) await fichier.delete();
      throw const ErreurGesco(
        'Le fichier Excel n\'a pas pu être vérifié après son enregistrement ; '
        'il a été supprimé. Réessayez ou choisissez un autre dossier.',
      );
    }
    return FichierEnregistre(fichier: fichier, nbFeuilles: f.feuilles.length);
  }
}
