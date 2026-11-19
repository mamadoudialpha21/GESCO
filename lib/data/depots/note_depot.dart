import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/bareme.dart';
import '../../domain/modeles.dart';
import '../../domain/periodes.dart';
import '../../domain/permissions.dart';
import '../controle.dart';
import '../erreurs.dart';
import '../modeles_notation.dart';
import 'aides.dart';
import 'erreurs_notes.dart';

/// Toutes les saisies d'une classe : inscription -> matière -> mois -> saisie.
typedef SaisiesClasse = Map<int, Map<int, Map<int, Saisie>>>;

/// Lecture et enregistrement des notes. Les notes brutes sont conservées
/// telles que saisies (en centièmes) ; les moyennes ne sont jamais stockées.
class NoteDepot {
  NoteDepot(
    this._db, {
    DateTime Function()? maintenant,
    this.controle = Controle.aucun,
  }) : _maintenant = maintenant ?? DateTime.now;

  final Database _db;
  final DateTime Function() _maintenant;
  final Controle controle;

  /// Toutes les saisies des élèves actuellement inscrits dans [classeId]
  /// (tous mois confondus).
  Future<SaisiesClasse> lireClasse(int classeId) async {
    final lignes = await _db.rawQuery(
      '''
      SELECT n.inscription_id, n.matiere_id, n.mois, n.etat, n.valeur,
             n.brut, n.bareme
      FROM note n
      JOIN inscription i ON i.id = n.inscription_id
      WHERE i.classe_id = ?
      ''',
      [classeId],
    );
    final resultat = <int, Map<int, Map<int, Saisie>>>{};
    for (final l in lignes) {
      final saisie = _saisieDepuis(
        l['etat'] as String,
        l['valeur'] as int?,
        l['brut'] as int?,
        l['bareme'] as int?,
      );
      resultat
          .putIfAbsent(l['inscription_id'] as int, () => {})
          .putIfAbsent(l['matiere_id'] as int, () => {})[l['mois'] as int] = saisie;
    }
    return resultat;
  }

  /// Enregistre le contenu d'une case. [saisie] null = case vidée (la note est
  /// supprimée : « non saisie », jamais zéro).
  ///
  /// La note doit être exprimée sur le barème de la matière : sur 20, une
  /// `Saisie.valeur` ; sur 10, 40, 100..., une `Saisie.surBareme` du même
  /// barème. La note ramenée sur 20 est celle des moyennes ; la note d'origine
  /// reste enregistrée.
  ///
  /// Quand la matière a des évaluations dans le mois, la note du mois en est
  /// calculée : la saisie directe est alors refusée (vider la case reste
  /// possible, pour effacer une ancienne note).
  Future<void> enregistrer({
    required int inscriptionId,
    required int matiereId,
    required int mois,
    required Saisie? saisie,
  }) async {
    controle.exiger(Permission.notesSaisir, 'saisir des notes');
    await _verifierEnseignant(matiereId);
    if (!moisScolaires.contains(mois)) {
      throw const ErreurGesco('Ce mois est hors de l\'année scolaire (octobre à juin).');
    }
    if (saisie != null && saisie.estNumerique) {
      final v = saisie.centiemes!;
      if (v < 0 || v > 2000) {
        throw const ErreurGesco('La note doit être comprise entre 0 et 20.');
      }
    }
    try {
      await _db.transaction((txn) async {
        if (saisie == null) {
          await txn.delete(
            'note',
            where: 'inscription_id = ? AND matiere_id = ? AND mois = ?',
            whereArgs: [inscriptionId, matiereId, mois],
          );
          return;
        }
        final liens = await txn.rawQuery(
          '''
          SELECT i.classe_id AS classe_eleve, m.classe_id AS classe_matiere,
                 m.bareme AS bareme
          FROM inscription i, matiere_classe m
          WHERE i.id = ? AND m.id = ?
          ''',
          [inscriptionId, matiereId],
        );
        if (liens.isEmpty) {
          throw const ErreurGesco(
            'L\'élève ou la matière n\'existe plus : rechargez la page.',
          );
        }
        if (liens.first['classe_eleve'] != liens.first['classe_matiere']) {
          throw const ErreurGesco(
            'Cette matière n\'appartient pas à la classe de l\'élève.',
          );
        }
        final bareme = (liens.first['bareme'] as int?) ?? baremeParDefaut;
        if (saisie.estNumerique) {
          if (saisie.bareme != null && saisie.bareme != bareme) {
            throw ErreurGesco(
              'Cette note est donnée sur ${saisie.bareme}, mais la matière '
              'est notée sur $bareme.',
            );
          }
          if (saisie.bareme == null && bareme != baremeParDefaut) {
            throw ErreurGesco(
              'Cette matière est notée sur $bareme : saisissez la note sur $bareme.',
            );
          }
        }
        final evaluations = await compter(
          txn,
          'SELECT COUNT(*) FROM evaluation WHERE matiere_id = ? AND mois = ?',
          [matiereId, mois],
        );
        if (evaluations > 0) {
          throw ErreurGesco(
            'La note de ce mois est calculée à partir de '
            '${pluriel(evaluations, 'évaluation')} : modifiez les notes des '
            'évaluations plutôt que la note du mois.',
          );
        }
        final conversion = saisie.estNumerique && bareme != baremeParDefaut;
        final valeurs = <String, Object?>{
          'etat': _nomEtat(saisie.etat),
          'valeur': saisie.centiemes,
          'brut': conversion ? saisie.brut : null,
          'bareme': conversion ? bareme : null,
          'modifie_le': _maintenant().toIso8601String(),
        };
        final modifiees = await txn.update(
          'note',
          valeurs,
          where: 'inscription_id = ? AND matiere_id = ? AND mois = ?',
          whereArgs: [inscriptionId, matiereId, mois],
        );
        if (modifiees == 0) {
          await txn.insert('note', {
            'inscription_id': inscriptionId,
            'matiere_id': matiereId,
            'mois': mois,
            ...valeurs,
          });
        }
      });
    } on DatabaseException catch (e) {
      final texte = e.toString();
      final traduite = erreurDeDeclencheur(e);
      if (texte.contains('Matiere hors classe')) {
        throw const ErreurGesco(
          'Cette matière n\'appartient pas à la classe de l\'élève.',
        );
      }
      if (traduite != null) throw traduite;
      if (texte.contains('FOREIGN KEY')) {
        throw const ErreurGesco(
          'L\'élève ou la matière n\'existe plus : rechargez la page.',
        );
      }
      rethrow;
    }
  }

  /// Un compte de saisie lié à un enseignant ne peut toucher qu'aux matières
  /// qui lui sont confiées.
  Future<void> _verifierEnseignant(int matiereId) async {
    final limite = controle.enseignantLimite;
    if (limite == null) return;
    final l = await _db.query(
      'matiere_classe',
      columns: ['enseignant_id'],
      where: 'id = ?',
      whereArgs: [matiereId],
    );
    if (l.isEmpty || l.first['enseignant_id'] != limite) {
      throw const ErreurGesco(
        'Vous ne pouvez saisir que les notes des matières qui vous sont confiées.',
      );
    }
  }

  // ------------------------------------------------------------ Verrouillage

  /// Mois verrouillés d'une classe, avec qui les a verrouillés et quand.
  Future<List<VerrouMois>> verrous(int classeId) async {
    final lignes = await _db.query(
      'verrou_notes',
      where: 'classe_id = ?',
      whereArgs: [classeId],
    );
    final liste = [
      for (final l in lignes)
        VerrouMois(
          mois: l['mois'] as int,
          verrouilleLe: l['verrouille_le'] as String,
          utilisateurNom: (l['utilisateur_nom'] as String?) ?? '',
        ),
    ];
    liste.sort(
      (a, b) => moisScolaires.indexOf(a.mois).compareTo(moisScolaires.indexOf(b.mois)),
    );
    return liste;
  }

  /// Numéros des mois verrouillés d'une classe.
  Future<Set<int>> moisVerrouilles(int classeId) async =>
      {for (final v in await verrous(classeId)) v.mois};

  /// Verrouille un mois d'une classe : plus aucune note (mensuelle ou
  /// d'évaluation) ne peut y être ajoutée, modifiée ni supprimée. Sans effet
  /// si le mois est déjà verrouillé.
  Future<void> verrouiller(int classeId, int mois) async {
    controle.exiger(Permission.notesVerrouiller, 'verrouiller les notes');
    if (!moisScolaires.contains(mois)) {
      throw const ErreurGesco('Ce mois est hors de l\'année scolaire (octobre à juin).');
    }
    final nom = await _classeNom(classeId);
    final deja = await compter(
      _db,
      'SELECT COUNT(*) FROM verrou_notes WHERE classe_id = ? AND mois = ?',
      [classeId, mois],
    );
    if (deja > 0) return;
    final contexte = await _db.query('contexte', columns: ['utilisateur_nom'], where: 'id = 1');
    await _db.insert('verrou_notes', {
      'classe_id': classeId,
      'mois': mois,
      'verrouille_le': horodatage(_maintenant()),
      'utilisateur_nom':
          contexte.isEmpty ? '' : (contexte.first['utilisateur_nom'] as String? ?? ''),
    });
    await controle.noter(
      'verrouillage',
      'classe',
      id: classeId,
      details: '$nom : ${libelleMois(mois)}',
    );
  }

  /// Déverrouille un mois d'une classe.
  Future<void> deverrouiller(int classeId, int mois) async {
    controle.exiger(Permission.notesVerrouiller, 'déverrouiller les notes');
    final nom = await _classeNom(classeId);
    final supprimes = await _db.delete(
      'verrou_notes',
      where: 'classe_id = ? AND mois = ?',
      whereArgs: [classeId, mois],
    );
    if (supprimes == 0) return;
    await controle.noter(
      'deverrouillage',
      'classe',
      id: classeId,
      details: '$nom : ${libelleMois(mois)}',
    );
  }

  Future<String> _classeNom(int classeId) async {
    final l = await _db.query('classe', columns: ['nom'], where: 'id = ?', whereArgs: [classeId]);
    if (l.isEmpty) throw const ErreurGesco('Classe introuvable.');
    return l.first['nom'] as String;
  }

  // -------------------------------------------------------------- Historique

  static const int historiqueParPage = 100;

  /// Historique des notes (saisies, modifications, suppressions), le plus
  /// récent d'abord. Chaque ligne indique qui, quand, l'ancienne et la nouvelle
  /// valeur. Les noms sont recopiés : l'historique survit à la suppression
  /// d'un élève.
  Future<List<EntreeHistoriqueNote>> historique({
    int? classeId,
    int? inscriptionId,
    int? matiereId,
    int? mois,
    String? source,
    int limite = historiqueParPage,
    int decalage = 0,
  }) async {
    controle.exiger(Permission.journalVoir, 'consulter l\'historique des notes');
    final filtre = _filtreHistorique(
      classeId: classeId,
      inscriptionId: inscriptionId,
      matiereId: matiereId,
      mois: mois,
      source: source,
    );
    final lignes = await _db.rawQuery(
      'SELECT * FROM historique_note ${filtre.sql} ORDER BY date_heure DESC, id DESC '
      'LIMIT ? OFFSET ?',
      [...filtre.arguments, limite, decalage],
    );
    return [
      for (final l in lignes)
        EntreeHistoriqueNote(
          id: l['id'] as int,
          dateHeure: l['date_heure'] as String,
          utilisateurNom: (l['utilisateur_nom'] as String?) ?? '',
          source: l['source'] as String,
          operation: l['operation'] as String,
          inscriptionId: l['inscription_id'] as int,
          matiereId: l['matiere_id'] as int?,
          mois: l['mois'] as int?,
          evaluationId: l['evaluation_id'] as int?,
          bareme: l['bareme'] as int?,
          eleveNom: (l['eleve_nom'] as String?) ?? '',
          matiereNom: (l['matiere_nom'] as String?) ?? '',
          classeNom: (l['classe_nom'] as String?) ?? '',
          ancienEtat: l['ancien_etat'] as String?,
          ancienneValeur: l['ancienne_valeur'] as int?,
          nouvelEtat: l['nouvel_etat'] as String?,
          nouvelleValeur: l['nouvelle_valeur'] as int?,
        ),
    ];
  }

  /// Nombre de lignes d'historique correspondant aux mêmes filtres.
  Future<int> compterHistorique({
    int? classeId,
    int? inscriptionId,
    int? matiereId,
    int? mois,
    String? source,
  }) {
    controle.exiger(Permission.journalVoir, 'consulter l\'historique des notes');
    final filtre = _filtreHistorique(
      classeId: classeId,
      inscriptionId: inscriptionId,
      matiereId: matiereId,
      mois: mois,
      source: source,
    );
    return compter(_db, 'SELECT COUNT(*) FROM historique_note ${filtre.sql}', filtre.arguments);
  }

  static ({String sql, List<Object?> arguments}) _filtreHistorique({
    int? classeId,
    int? inscriptionId,
    int? matiereId,
    int? mois,
    String? source,
  }) {
    final conditions = <String>[];
    final arguments = <Object?>[];
    if (classeId != null) {
      conditions.add('inscription_id IN (SELECT id FROM inscription WHERE classe_id = ?)');
      arguments.add(classeId);
    }
    if (inscriptionId != null) {
      conditions.add('inscription_id = ?');
      arguments.add(inscriptionId);
    }
    if (matiereId != null) {
      conditions.add('matiere_id = ?');
      arguments.add(matiereId);
    }
    if (mois != null) {
      conditions.add('mois = ?');
      arguments.add(mois);
    }
    if (source != null) {
      conditions.add('source = ?');
      arguments.add(source);
    }
    return (
      sql: conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}',
      arguments: arguments,
    );
  }

  /// Nombre de notes (y compris absences et dispenses) d'une classe.
  Future<int> compterClasse(int classeId) => compter(
        _db,
        '''
        SELECT COUNT(*) FROM note n
        JOIN inscription i ON i.id = n.inscription_id
        WHERE i.classe_id = ?
        ''',
        [classeId],
      );

  /// Nombre de notes (y compris absences et dispenses) d'une année scolaire.
  Future<int> compterAnnee(int anneeId) => compter(
        _db,
        '''
        SELECT COUNT(*) FROM note n
        JOIN inscription i ON i.id = n.inscription_id
        WHERE i.annee_id = ?
        ''',
        [anneeId],
      );

  static String _nomEtat(EtatNote etat) => switch (etat) {
        EtatNote.saisie => 'saisie',
        EtatNote.absent => 'absent',
        EtatNote.dispense => 'dispense',
      };

  static Saisie _saisieDepuis(String etat, int? valeur, int? brut, int? bareme) {
    switch (etat) {
      case 'saisie':
        if (valeur == null || valeur < 0 || valeur > 2000) break;
        if (brut != null &&
            bareme != null &&
            baremeValide(bareme) &&
            brut >= 0 &&
            brut <= centiemesMax(bareme) &&
            convertirSur20(brut, bareme) == valeur) {
          return Saisie.surBareme(brut, bareme);
        }
        return Saisie.valeur(valeur);
      case 'absent':
        return const Saisie.absent();
      case 'dispense':
        return const Saisie.dispense();
    }
    throw const ErreurGesco(
      'Une note enregistrée est illisible. Restaurez une sauvegarde ou '
      'ressaisissez la note.',
    );
  }
}
