import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/modeles.dart';
import '../../domain/periodes.dart';
import '../erreurs.dart';
import 'aides.dart';

/// Toutes les saisies d'une classe : inscription -> matière -> mois -> saisie.
typedef SaisiesClasse = Map<int, Map<int, Map<int, Saisie>>>;

/// Lecture et enregistrement des notes. Les notes brutes sont conservées
/// telles que saisies (en centièmes) ; les moyennes ne sont jamais stockées.
class NoteDepot {
  NoteDepot(this._db, {DateTime Function()? maintenant})
      : _maintenant = maintenant ?? DateTime.now;

  final Database _db;
  final DateTime Function() _maintenant;

  /// Toutes les saisies des élèves actuellement inscrits dans [classeId]
  /// (tous mois confondus).
  Future<SaisiesClasse> lireClasse(int classeId) async {
    final lignes = await _db.rawQuery(
      '''
      SELECT n.inscription_id, n.matiere_id, n.mois, n.etat, n.valeur
      FROM note n
      JOIN inscription i ON i.id = n.inscription_id
      WHERE i.classe_id = ?
      ''',
      [classeId],
    );
    final resultat = <int, Map<int, Map<int, Saisie>>>{};
    for (final l in lignes) {
      final saisie = _saisieDepuis(l['etat'] as String, l['valeur'] as int?);
      resultat
          .putIfAbsent(l['inscription_id'] as int, () => {})
          .putIfAbsent(l['matiere_id'] as int, () => {})[l['mois'] as int] = saisie;
    }
    return resultat;
  }

  /// Enregistre le contenu d'une case. [saisie] null = case vidée (la note est
  /// supprimée : « non saisie », jamais zéro).
  Future<void> enregistrer({
    required int inscriptionId,
    required int matiereId,
    required int mois,
    required Saisie? saisie,
  }) async {
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
          SELECT i.classe_id AS classe_eleve, m.classe_id AS classe_matiere
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
        final valeurs = <String, Object?>{
          'etat': _nomEtat(saisie.etat),
          'valeur': saisie.centiemes,
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
      if (texte.contains('Matiere hors classe')) {
        throw const ErreurGesco(
          'Cette matière n\'appartient pas à la classe de l\'élève.',
        );
      }
      if (texte.contains('FOREIGN KEY')) {
        throw const ErreurGesco(
          'L\'élève ou la matière n\'existe plus : rechargez la page.',
        );
      }
      rethrow;
    }
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

  static Saisie _saisieDepuis(String etat, int? valeur) {
    switch (etat) {
      case 'saisie':
        if (valeur == null || valeur < 0 || valeur > 2000) break;
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
