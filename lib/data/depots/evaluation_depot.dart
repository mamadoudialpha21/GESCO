import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/arrondi.dart';
import '../../domain/bareme.dart';
import '../../domain/dates.dart';
import '../../domain/evaluations.dart';
import '../../domain/modeles.dart';
import '../../domain/periodes.dart';
import '../../domain/permissions.dart';
import '../changements_notes.dart';
import '../controle.dart';
import '../erreurs.dart';
import '../modeles_notation.dart';
import 'aides.dart';
import 'erreurs_notes.dart';
import 'note_depot.dart';

/// Notes d'une classe telles que les moyennes doivent les lire : notes saisies
/// directement, remplacées par la moyenne des évaluations dans chaque mois où
/// la matière en a.
class SaisiesEffectives {
  const SaisiesEffectives(this.saisies, this.casesEvaluees);

  /// inscription -> matière -> mois -> saisie.
  final SaisiesClasse saisies;

  /// Couples (matière, mois) dont la note vient des évaluations : la saisie
  /// directe y est interdite.
  final Set<(int, int)> casesEvaluees;

  bool estEvaluee(int matiereId, int mois) => casesEvaluees.contains((matiereId, mois));
}

/// Évaluations (interrogation, devoir, composition, examen) et leurs notes.
///
/// Une évaluation appartient à une matière et à un mois, avec un coefficient
/// (poids dans la note du mois) et un barème propre (sur 10, 20, 40, 100...).
/// Les notes sont enregistrées sur le barème de l'évaluation et ramenées sur
/// 20 au moment du calcul : rien n'est stocké en double.
class EvaluationDepot {
  EvaluationDepot(
    this._db, {
    required NoteDepot notes,
    this.controle = Controle.aucun,
    DateTime Function()? maintenant,
  })  : _notes = notes,
        _maintenant = maintenant ?? DateTime.now;

  final Database _db;
  final NoteDepot _notes;
  final Controle controle;
  final DateTime Function() _maintenant;

  /// Prévient les écouteurs (bulletins automatiques) qu'une note du mois a
  /// changé. Une composition ou un examen marque la fin d'un trimestre.
  void _signaler(Evaluation e) => _notes.notifications?.signaler(
        ChangementNotes(
          e.classeId,
          e.mois,
          composition: e.type == TypeEvaluation.composition || e.type == TypeEvaluation.examen,
        ),
      );

  static const int longueurMaxTitre = longueurMaxTitreEvaluation;
  static const int coefficientMax = coefficientMaxEvaluation;

  static Evaluation _depuis(Map<String, Object?> l) => Evaluation(
        id: l['id'] as int,
        classeId: l['classe_id'] as int,
        matiereId: l['matiere_id'] as int,
        mois: l['mois'] as int,
        type: TypeEvaluation.depuisCle(l['type'] as String),
        titre: l['titre'] as String,
        date: l['date_evaluation'] as String?,
        coefficient: l['coefficient'] as int,
        bareme: l['bareme'] as int,
        valide: ((l['valide'] as int?) ?? 0) == 1,
      );

  // ---------------------------------------------------------------- Lecture

  Future<Evaluation?> obtenir(int id) async {
    final lignes = await _db.query('evaluation', where: 'id = ?', whereArgs: [id]);
    return lignes.isEmpty ? null : _depuis(lignes.first);
  }

  /// Évaluations d'une classe (d'une matière ou d'un mois si précisé), dans
  /// l'ordre de l'année scolaire puis par date.
  Future<List<EvaluationResume>> lister({
    required int classeId,
    int? matiereId,
    int? mois,
  }) async {
    final lignes = await _db.rawQuery(
      '''
      SELECT e.*, m.nom AS matiere_nom,
        (SELECT COUNT(*) FROM evaluation_note n
           JOIN inscription i ON i.id = n.inscription_id
          WHERE n.evaluation_id = e.id AND i.statut = 'inscrit') AS nb_notes,
        (SELECT COUNT(*) FROM inscription i
          WHERE i.classe_id = e.classe_id AND i.statut = 'inscrit') AS nb_eleves
      FROM evaluation e JOIN matiere_classe m ON m.id = e.matiere_id
      WHERE e.classe_id = ?
        ${matiereId == null ? '' : 'AND e.matiere_id = ?'}
        ${mois == null ? '' : 'AND e.mois = ?'}
      ''',
      [classeId, if (matiereId != null) matiereId, if (mois != null) mois],
    );
    final liste = [
      for (final l in lignes)
        EvaluationResume(
          evaluation: _depuis(l),
          matiereNom: l['matiere_nom'] as String,
          nbEleves: l['nb_eleves'] as int,
          nbNotes: l['nb_notes'] as int,
        ),
    ];
    liste.sort((a, b) {
      final parMois = moisScolaires
          .indexOf(a.evaluation.mois)
          .compareTo(moisScolaires.indexOf(b.evaluation.mois));
      if (parMois != 0) return parMois;
      final parDate = (a.evaluation.date ?? '').compareTo(b.evaluation.date ?? '');
      if (parDate != 0) return parDate;
      return a.evaluation.id.compareTo(b.evaluation.id);
    });
    return liste;
  }

  // ----------------------------------------------------------- Modification

  /// Crée une évaluation. Le barème par défaut est celui de la matière.
  /// Refusé dans un mois verrouillé ou une année archivée.
  Future<Evaluation> creer({
    required int classeId,
    required int matiereId,
    required int mois,
    required String titre,
    TypeEvaluation type = TypeEvaluation.evaluation,
    String? date,
    int coefficient = 100,
    int? bareme,
  }) async {
    controle.exiger(Permission.evaluationsGerer, 'créer une évaluation');
    final titreValide = _titreValide(titre);
    _verifierMois(mois);
    _verifierCoefficient(coefficient);
    if (bareme != null) _verifierBareme(bareme);
    final dateValide = _dateValide(date);
    await _verifierEnseignant(_db, matiereId);

    try {
      final id = await _db.transaction<int>((txn) async {
        final matieres = await txn.query(
          'matiere_classe',
          columns: ['classe_id', 'bareme'],
          where: 'id = ?',
          whereArgs: [matiereId],
        );
        if (matieres.isEmpty) throw const ErreurGesco('Matière introuvable.');
        if (matieres.first['classe_id'] != classeId) {
          throw const ErreurGesco('Cette matière n\'appartient pas à la classe.');
        }
        await _verifierMoisLibre(txn, classeId, mois);
        return txn.insert('evaluation', {
          'classe_id': classeId,
          'matiere_id': matiereId,
          'mois': mois,
          'type': type.cle,
          'titre': titreValide,
          'date_evaluation': dateValide,
          'coefficient': coefficient,
          'bareme': bareme ?? (matieres.first['bareme'] as int? ?? baremeParDefaut),
          'valide': 0,
          'cree_le': horodatage(_maintenant()),
        });
      });
      await controle.noter(
        'creation',
        'evaluation',
        id: id,
        details: '$titreValide (${libelleMois(mois)})',
      );
      return (await obtenir(id))!;
    } on DatabaseException catch (e) {
      throw erreurDeDeclencheur(e) ?? e;
    }
  }

  /// Modifie une évaluation. Le mois et le barème ne changent plus dès
  /// qu'une note existe. Refusé si l'évaluation est validée ou son mois
  /// verrouillé. [effacerDate] retire la date.
  Future<void> modifier(
    int id, {
    String? titre,
    TypeEvaluation? type,
    String? date,
    bool effacerDate = false,
    int? coefficient,
    int? bareme,
    int? mois,
  }) async {
    controle.exiger(Permission.evaluationsGerer, 'modifier une évaluation');
    final titreValide = titre == null ? null : _titreValide(titre);
    if (coefficient != null) _verifierCoefficient(coefficient);
    if (bareme != null) _verifierBareme(bareme);
    if (mois != null) _verifierMois(mois);
    final dateValide = _dateValide(date);

    try {
      await _db.transaction<void>((txn) async {
        final lignes = await txn.query('evaluation', where: 'id = ?', whereArgs: [id]);
        if (lignes.isEmpty) throw const ErreurGesco('Évaluation introuvable.');
        final actuelle = _depuis(lignes.first);
        await _verifierEnseignant(txn, actuelle.matiereId);
        _verifierModifiable(actuelle);
        await _verifierMoisLibre(txn, actuelle.classeId, actuelle.mois);
        if (mois != null && mois != actuelle.mois) {
          await _verifierMoisLibre(txn, actuelle.classeId, mois);
        }
        final notes = await compter(
          txn,
          'SELECT COUNT(*) FROM evaluation_note WHERE evaluation_id = ?',
          [id],
        );
        if (notes > 0) {
          if (bareme != null && bareme != actuelle.bareme) {
            throw ErreurGesco(
              'Le barème ne peut plus changer : ${pluriel(notes, 'note')} '
              '${notes > 1 ? 'sont enregistrées' : 'est enregistrée'}.',
            );
          }
          if (mois != null && mois != actuelle.mois) {
            throw ErreurGesco(
              'Le mois ne peut plus changer : ${pluriel(notes, 'note')} '
              '${notes > 1 ? 'sont enregistrées' : 'est enregistrée'}.',
            );
          }
        }
        final valeurs = <String, Object?>{
          if (titreValide != null) 'titre': titreValide,
          if (type != null) 'type': type.cle,
          if (effacerDate || dateValide != null)
            'date_evaluation': effacerDate ? null : dateValide,
          if (coefficient != null) 'coefficient': coefficient,
          if (bareme != null) 'bareme': bareme,
          if (mois != null) 'mois': mois,
        };
        if (valeurs.isEmpty) return;
        await txn.update('evaluation', valeurs, where: 'id = ?', whereArgs: [id]);
      });
    } on DatabaseException catch (e) {
      throw erreurDeDeclencheur(e) ?? e;
    }
    await controle.noter(
      'modification',
      'evaluation',
      id: id,
      details: [
        if (titre != null) 'titre',
        if (coefficient != null) 'coefficient',
        if (bareme != null) 'barème $bareme',
        if (mois != null) 'mois',
      ].join(', '),
    );
    final apres = await obtenir(id);
    if (apres != null) _signaler(apres);
  }

  /// Supprime une évaluation. Si elle a des notes, une confirmation est
  /// demandée ([ErreurAConfirmer]) ; avec [avecNotes], les notes sont
  /// supprimées avec elle (et gardées dans l'historique).
  Future<void> supprimer(int id, {bool avecNotes = false}) async {
    controle.exiger(Permission.evaluationsGerer, 'supprimer une évaluation');
    String titre = '';
    Evaluation? supprimee;
    try {
      await _db.transaction<void>((txn) async {
        final lignes = await txn.query('evaluation', where: 'id = ?', whereArgs: [id]);
        if (lignes.isEmpty) throw const ErreurGesco('Évaluation introuvable.');
        final actuelle = _depuis(lignes.first);
        titre = actuelle.titre;
        supprimee = actuelle;
        await _verifierEnseignant(txn, actuelle.matiereId);
        _verifierModifiable(actuelle);
        await _verifierMoisLibre(txn, actuelle.classeId, actuelle.mois);
        final notes = await compter(
          txn,
          'SELECT COUNT(*) FROM evaluation_note WHERE evaluation_id = ?',
          [id],
        );
        if (notes > 0 && !avecNotes) {
          throw ErreurAConfirmer(
            'L\'évaluation « ${actuelle.titre} » contient ${pluriel(notes, 'note')}. '
            'Elles seront supprimées avec elle (elles resteront dans l\'historique).',
            'pertes',
          );
        }
        if (notes > 0) {
          await txn.delete('evaluation_note', where: 'evaluation_id = ?', whereArgs: [id]);
        }
        await txn.delete('evaluation', where: 'id = ?', whereArgs: [id]);
      });
    } on DatabaseException catch (e) {
      throw erreurDeDeclencheur(e) ?? e;
    }
    await controle.noter('suppression', 'evaluation', id: id, details: titre);
    final e = supprimee;
    if (e != null) _signaler(e);
  }

  /// Valide une évaluation (plus aucune note modifiable) ou annule la
  /// validation.
  Future<void> valider(int id, {bool valide = true}) async {
    controle.exiger(Permission.notesVerrouiller, 'valider une évaluation');
    final e = await obtenir(id);
    if (e == null) throw const ErreurGesco('Évaluation introuvable.');
    if (e.valide == valide) return;
    await _db.update(
      'evaluation',
      {'valide': valide ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    await controle.noter(
      valide ? 'validation' : 'annulation_validation',
      'evaluation',
      id: id,
      details: e.titre,
    );
  }

  // ------------------------------------------------------------------ Notes

  /// Notes d'une évaluation : inscription -> saisie (sur le barème de
  /// l'évaluation, avec la note ramenée sur 20 dans `centiemes`).
  Future<Map<int, Saisie>> lireNotes(int evaluationId) async {
    final e = await obtenir(evaluationId);
    if (e == null) throw const ErreurGesco('Évaluation introuvable.');
    final lignes = await _db.query(
      'evaluation_note',
      columns: ['inscription_id', 'etat', 'brut'],
      where: 'evaluation_id = ?',
      whereArgs: [evaluationId],
    );
    return {
      for (final l in lignes)
        l['inscription_id'] as int:
            _saisieDepuis(l['etat'] as String, l['brut'] as int?, e.bareme),
    };
  }

  /// Enregistre la note d'un élève ([saisie] null : note effacée).
  Future<void> enregistrerNote({
    required int evaluationId,
    required int inscriptionId,
    required Saisie? saisie,
  }) =>
      enregistrerLot(evaluationId, {inscriptionId: saisie});

  /// Saisie collective : enregistre les notes de plusieurs élèves en une
  /// seule opération, tout ou rien. Une valeur null efface la note.
  ///
  /// Les notes doivent être sur le barème de l'évaluation : `Saisie.valeur`
  /// pour une évaluation sur 20, `Saisie.surBareme` du même barème sinon.
  Future<void> enregistrerLot(int evaluationId, Map<int, Saisie?> notes) async {
    controle.exiger(Permission.notesSaisir, 'saisir des notes');
    final e = await obtenir(evaluationId);
    if (e == null) throw const ErreurGesco('Évaluation introuvable.');
    await _verifierEnseignant(_db, e.matiereId);
    final lignes = <int, ({String etat, int? brut})?>{
      for (final entree in notes.entries) entree.key: _versLigne(entree.value, e.bareme),
    };
    try {
      await _db.transaction<void>((txn) async {
        for (final entree in lignes.entries) {
          final ligne = entree.value;
          if (ligne == null) {
            await txn.delete(
              'evaluation_note',
              where: 'evaluation_id = ? AND inscription_id = ?',
              whereArgs: [evaluationId, entree.key],
            );
            continue;
          }
          final valeurs = <String, Object?>{
            'etat': ligne.etat,
            'brut': ligne.brut,
            'modifie_le': _maintenant().toIso8601String(),
          };
          final modifiees = await txn.update(
            'evaluation_note',
            valeurs,
            where: 'evaluation_id = ? AND inscription_id = ?',
            whereArgs: [evaluationId, entree.key],
          );
          if (modifiees == 0) {
            await txn.insert('evaluation_note', {
              'evaluation_id': evaluationId,
              'inscription_id': entree.key,
              ...valeurs,
            });
          }
        }
      });
    } on DatabaseException catch (ex) {
      final traduite = erreurDeDeclencheur(ex);
      if (traduite != null) throw traduite;
      if (ex.toString().contains('FOREIGN KEY')) {
        throw const ErreurGesco('Un élève n\'existe plus : rechargez la page.');
      }
      rethrow;
    }
    _signaler(e);
  }

  /// Statistiques d'une évaluation sur les élèves qui suivent la classe.
  /// [seuilAdmission] (centièmes sur 20) fixe la réussite.
  Future<StatsEvaluation> statistiques(
    int evaluationId, {
    int seuilAdmission = 1000,
  }) async {
    final e = await obtenir(evaluationId);
    if (e == null) throw const ErreurGesco('Évaluation introuvable.');
    final eleves = await compter(
      _db,
      "SELECT COUNT(*) FROM inscription WHERE classe_id = ? AND statut = 'inscrit'",
      [e.classeId],
    );
    final lignes = await _db.rawQuery(
      '''
      SELECT n.etat AS etat, n.brut AS brut
      FROM evaluation_note n JOIN inscription i ON i.id = n.inscription_id
      WHERE n.evaluation_id = ? AND i.statut = 'inscrit'
      ''',
      [evaluationId],
    );
    var absents = 0;
    var dispenses = 0;
    final bruts = <int>[];
    for (final l in lignes) {
      switch (l['etat'] as String) {
        case 'absent':
          absents++;
        case 'dispense':
          dispenses++;
        default:
          bruts.add(l['brut'] as int);
      }
    }
    int? moyenne;
    int? moyenneSur20;
    int? minimum;
    int? maximum;
    var reussites = 0;
    if (bruts.isNotEmpty) {
      final somme = bruts.fold<int>(0, (a, b) => a + b);
      moyenne = divisionArrondie(somme, bruts.length);
      moyenneSur20 = convertirSur20(moyenne, e.bareme);
      minimum = bruts.reduce((a, b) => a < b ? a : b);
      maximum = bruts.reduce((a, b) => a > b ? a : b);
      reussites = bruts.where((b) => convertirSur20(b, e.bareme) >= seuilAdmission).length;
    }
    return StatsEvaluation(
      bareme: e.bareme,
      nbEleves: eleves,
      nbSaisies: bruts.length,
      nbAbsents: absents,
      nbDispenses: dispenses,
      nbReussites: reussites,
      moyenne: moyenne,
      moyenneSur20: moyenneSur20,
      minimum: minimum,
      maximum: maximum,
    );
  }

  // -------------------------------------------------- Notes pour les moyennes

  /// Notes d'une classe pour le calcul des moyennes : les notes mensuelles
  /// saisies, remplacées par la moyenne pondérée des évaluations dans chaque
  /// (matière, mois) où il y en a. Dans ces cases, un élève sans note
  /// d'évaluation reste « non saisi » (une ancienne note directe est ignorée,
  /// pas supprimée).
  ///
  /// [absenceEgaleZero] : un absent compte pour 0 dans la moyenne des
  /// évaluations (option de l'établissement).
  Future<SaisiesEffectives> saisiesEffectives(
    int classeId, {
    bool absenceEgaleZero = false,
  }) async {
    final manuelles = await _notes.lireClasse(classeId);
    final evaluations = await _db.query(
      'evaluation',
      columns: ['id', 'matiere_id', 'mois', 'coefficient', 'bareme'],
      where: 'classe_id = ?',
      whereArgs: [classeId],
    );
    if (evaluations.isEmpty) return SaisiesEffectives(manuelles, const {});

    final inscriptions = [
      for (final l in await _db.query(
        'inscription',
        columns: ['id'],
        where: 'classe_id = ?',
        whereArgs: [classeId],
      ))
        l['id'] as int,
    ];
    final notesParEvaluation = <int, Map<int, Saisie>>{};
    final baremes = {for (final e in evaluations) e['id'] as int: e['bareme'] as int};
    final lignesNotes = await _db.rawQuery(
      '''
      SELECT n.evaluation_id AS evaluation, n.inscription_id AS inscription,
             n.etat AS etat, n.brut AS brut
      FROM evaluation_note n JOIN evaluation e ON e.id = n.evaluation_id
      WHERE e.classe_id = ?
      ''',
      [classeId],
    );
    for (final l in lignesNotes) {
      final evaluation = l['evaluation'] as int;
      notesParEvaluation.putIfAbsent(evaluation, () => {})[l['inscription'] as int] =
          _saisieDepuis(l['etat'] as String, l['brut'] as int?, baremes[evaluation]!);
    }

    final cases = <(int, int), List<Map<String, Object?>>>{};
    for (final e in evaluations) {
      cases.putIfAbsent((e['matiere_id'] as int, e['mois'] as int), () => []).add(e);
    }

    final resultat = <int, Map<int, Map<int, Saisie>>>{
      for (final entree in manuelles.entries)
        entree.key: {
          for (final m in entree.value.entries) m.key: Map<int, Saisie>.of(m.value),
        },
    };
    for (final entree in cases.entries) {
      final (matiereId, mois) = entree.key;
      for (final inscription in inscriptions) {
        resultat[inscription]?[matiereId]?.remove(mois);
        final saisie = noteDuMois(
          [
            for (final e in entree.value)
              if (notesParEvaluation[e['id'] as int]?[inscription] case final s?)
                NoteEvaluee(s, e['coefficient'] as int),
          ],
          absenceEgaleZero: absenceEgaleZero,
        );
        if (saisie != null) {
          resultat
              .putIfAbsent(inscription, () => {})
              .putIfAbsent(matiereId, () => {})[mois] = saisie;
        }
      }
    }
    return SaisiesEffectives(resultat, cases.keys.toSet());
  }

  // ---------------------------------------------------------------- Interne

  static Saisie _saisieDepuis(String etat, int? brut, int bareme) {
    switch (etat) {
      case 'absent':
        return const Saisie.absent();
      case 'dispense':
        return const Saisie.dispense();
      default:
        if (brut != null && brut >= 0 && brut <= centiemesMax(bareme)) {
          return bareme == baremeParDefaut
              ? Saisie.valeur(brut)
              : Saisie.surBareme(brut, bareme);
        }
        throw const ErreurGesco(
          'Une note d\'évaluation enregistrée est illisible. Restaurez une '
          'sauvegarde ou ressaisissez la note.',
        );
    }
  }

  static ({String etat, int? brut})? _versLigne(Saisie? saisie, int bareme) {
    if (saisie == null) return null;
    switch (saisie.etat) {
      case EtatNote.absent:
        return (etat: 'absent', brut: null);
      case EtatNote.dispense:
        return (etat: 'dispense', brut: null);
      case EtatNote.saisie:
        if (saisie.bareme != null) {
          if (saisie.bareme != bareme) {
            throw ErreurGesco(
              'Cette note est donnée sur ${saisie.bareme}, mais l\'évaluation '
              'est notée sur $bareme.',
            );
          }
          return (etat: 'saisie', brut: saisie.brut!);
        }
        if (bareme != baremeParDefaut) {
          throw ErreurGesco(
            'Cette évaluation est notée sur $bareme : saisissez la note sur $bareme.',
          );
        }
        return (etat: 'saisie', brut: saisie.centiemes!);
    }
  }

  static void _verifierModifiable(Evaluation e) {
    if (e.valide) {
      throw const ErreurGesco(
        'Cette évaluation est validée : annulez sa validation pour la modifier.',
      );
    }
  }

  static Future<void> _verifierMoisLibre(
    DatabaseExecutor db,
    int classeId,
    int mois,
  ) async {
    final verrou = await compter(
      db,
      'SELECT COUNT(*) FROM verrou_notes WHERE classe_id = ? AND mois = ?',
      [classeId, mois],
    );
    if (verrou > 0) {
      throw ErreurGesco(
        '${libelleMois(mois)} est verrouillé pour cette classe : déverrouillez '
        'le mois pour modifier ses évaluations.',
      );
    }
  }

  Future<void> _verifierEnseignant(DatabaseExecutor db, int matiereId) async {
    final limite = controle.enseignantLimite;
    if (limite == null) return;
    final l = await db.query(
      'matiere_classe',
      columns: ['enseignant_id'],
      where: 'id = ?',
      whereArgs: [matiereId],
    );
    if (l.isEmpty || l.first['enseignant_id'] != limite) {
      throw const ErreurGesco(
        'Vous ne pouvez gérer que les évaluations des matières qui vous sont confiées.',
      );
    }
  }

  static String _titreValide(String titre) {
    final t = titre.trim();
    if (t.isEmpty) throw const ErreurGesco('Le titre de l\'évaluation est obligatoire.');
    if (t.length > longueurMaxTitre) {
      throw const ErreurGesco(
        'Le titre est trop long ($longueurMaxTitre caractères au maximum).',
      );
    }
    return t;
  }

  static void _verifierMois(int mois) {
    if (!moisScolaires.contains(mois)) {
      throw const ErreurGesco('Ce mois est hors de l\'année scolaire (octobre à juin).');
    }
  }

  static void _verifierCoefficient(int coefficient) {
    if (coefficient <= 0 || coefficient > coefficientMax) {
      throw const ErreurGesco(
        'Le coefficient doit être strictement positif et inférieur à 100.',
      );
    }
  }

  static void _verifierBareme(int bareme) {
    if (!baremeValide(bareme)) {
      throw const ErreurGesco('Le barème doit être compris entre 1 et 1000.');
    }
  }

  static String? _dateValide(String? date) {
    if (date == null || date.trim().isEmpty) return null;
    final analysee = analyserDateIso(date.trim());
    if (analysee == null) {
      throw const ErreurGesco('La date de l\'évaluation est invalide.');
    }
    return dateVersIso(analysee);
  }
}
