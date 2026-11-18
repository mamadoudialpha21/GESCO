import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/permissions.dart';
import '../../domain/recherche.dart';
import '../controle.dart';
import '../erreurs.dart';
import '../modeles_donnees.dart';
import '../validation_eleve.dart';
import 'aides.dart';

/// Élèves et inscriptions.
///
/// Les informations personnelles d'un élève sont enregistrées une seule fois
/// et réutilisées chaque année ; l'inscription relie l'élève à une classe pour
/// une année scolaire donnée. Les notes, classements et bulletins s'appuient
/// sur l'inscription.
class EleveDepot {
  EleveDepot(
    this._db, {
    DateTime Function()? maintenant,
    this.controle = Controle.aucun,
  }) : _maintenant = maintenant ?? DateTime.now;

  final Database _db;
  final DateTime Function() _maintenant;
  final Controle controle;

  static const String _requeteListe = '''
    SELECT i.id AS inscription_id, i.eleve_id, i.classe_id, c.nom AS classe_nom,
           e.matricule, e.nom, e.prenom, e.sexe, e.date_naissance
    FROM inscription i
    JOIN eleve e ON e.id = i.eleve_id
    JOIN classe c ON c.id = i.classe_id
    WHERE i.annee_id = ?
    ''';

  static const String _requeteListeClasse = '''
    SELECT i.id AS inscription_id, i.eleve_id, i.classe_id, c.nom AS classe_nom,
           e.matricule, e.nom, e.prenom, e.sexe, e.date_naissance
    FROM inscription i
    JOIN eleve e ON e.id = i.eleve_id
    JOIN classe c ON c.id = i.classe_id
    WHERE i.annee_id = ? AND i.classe_id = ?
    ''';

  static const String _requeteNonInscrits = '''
    SELECT e.id, e.matricule, e.nom, e.prenom, e.sexe, e.date_naissance,
           e.lieu_naissance, e.nom_pere, e.nom_mere, e.contact_parent, e.adresse
    FROM eleve e
    WHERE NOT EXISTS (
      SELECT 1 FROM inscription i
      WHERE i.eleve_id = e.id AND i.annee_id = ?
    )
    ''';

  /// Élèves inscrits pour l'année, éventuellement dans une seule classe,
  /// triés par nom puis prénom (sans tenir compte des accents ni de la casse).
  Future<List<EleveInscrit>> lister(int anneeId, {int? classeId}) async {
    final lignes = classeId == null
        ? await _db.rawQuery(_requeteListe, [anneeId])
        : await _db.rawQuery(_requeteListeClasse, [anneeId, classeId]);
    final liste = [
      for (final l in lignes)
        EleveInscrit(
          inscriptionId: l['inscription_id'] as int,
          eleveId: l['eleve_id'] as int,
          classeId: l['classe_id'] as int,
          classeNom: l['classe_nom'] as String,
          matricule: l['matricule'] as String,
          nom: l['nom'] as String,
          prenom: l['prenom'] as String,
          sexe: l['sexe'] as String,
          dateNaissance: l['date_naissance'] as String?,
        ),
    ];
    liste.sort((a, b) {
      final parNom = normaliserRecherche(a.nom).compareTo(normaliserRecherche(b.nom));
      if (parNom != 0) return parNom;
      final parPrenom =
          normaliserRecherche(a.prenom).compareTo(normaliserRecherche(b.prenom));
      if (parPrenom != 0) return parPrenom;
      return a.inscriptionId.compareTo(b.inscriptionId);
    });
    return liste;
  }

  /// Fiche complète d'un élève (avec la photo), ou null.
  Future<Eleve?> obtenir(int eleveId) async {
    final lignes = await _db.query(
      'eleve',
      where: 'id = ?',
      whereArgs: [eleveId],
    );
    return lignes.isEmpty ? null : _depuis(lignes.first);
  }

  /// Élèves connus qui ne sont pas encore inscrits pour [anneeId] (par
  /// exemple pour les réinscrire à la rentrée suivante). Sans la photo.
  Future<List<Eleve>> nonInscrits(int anneeId) async {
    final lignes = await _db.rawQuery(_requeteNonInscrits, [anneeId]);
    final liste = [for (final l in lignes) _depuis(l)];
    liste.sort((a, b) {
      final parNom = normaliserRecherche(a.nom).compareTo(normaliserRecherche(b.nom));
      if (parNom != 0) return parNom;
      return normaliserRecherche(a.prenom).compareTo(normaliserRecherche(b.prenom));
    });
    return liste;
  }

  /// Tous les matricules existants (pour proposer le suivant).
  Future<List<String>> matricules() async {
    final lignes = await _db.query('eleve', columns: ['matricule']);
    return [for (final l in lignes) l['matricule'] as String];
  }

  /// Nombre de notes enregistrées pour une inscription.
  Future<int> compterNotes(int inscriptionId) => compter(
        _db,
        'SELECT COUNT(*) FROM note WHERE inscription_id = ?',
        [inscriptionId],
      );

  /// Crée un nouvel élève et l'inscrit dans [classeId] pour [anneeId].
  /// Retourne l'identifiant de l'inscription. Tout ou rien.
  Future<int> inscrire(
    Eleve eleve, {
    required int anneeId,
    required int classeId,
  }) async {
    controle.exiger(Permission.elevesGerer, 'inscrire un élève');
    _verifier(eleve);
    final id = await _db.transaction<int>((txn) async {
      await _verifierClasse(txn, classeId, anneeId);
      await _verifierMatriculeLibre(txn, eleve.matricule);
      final eleveId = await txn.insert('eleve', _valeurs(eleve));
      return _inscrire(txn, eleveId, classeId, anneeId);
    });
    await controle.noter(
      'inscription',
      'eleve',
      id: id,
      details: '${eleve.nom.trim()} ${eleve.prenom.trim()} (${eleve.matricule.trim()})',
    );
    return id;
  }

  /// Inscrit un élève déjà connu (réinscription d'une année à l'autre).
  Future<int> inscrireExistant({
    required int eleveId,
    required int anneeId,
    required int classeId,
  }) async {
    controle.exiger(Permission.elevesGerer, 'inscrire un élève');
    final id = await _db.transaction<int>((txn) async {
      final existe = await compter(
        txn,
        'SELECT COUNT(*) FROM eleve WHERE id = ?',
        [eleveId],
      );
      if (existe == 0) throw const ErreurGesco('Élève introuvable.');
      await _verifierClasse(txn, classeId, anneeId);
      final deja = await compter(
        txn,
        'SELECT COUNT(*) FROM inscription WHERE eleve_id = ? AND annee_id = ?',
        [eleveId, anneeId],
      );
      if (deja > 0) {
        throw const ErreurGesco(
          'Cet élève est déjà inscrit pour cette année scolaire.',
        );
      }
      return _inscrire(txn, eleveId, classeId, anneeId);
    });
    await controle.noter('reinscription', 'eleve', id: id, details: 'élève n° $eleveId');
    return id;
  }

  /// Modifie la fiche d'un élève ([Eleve.id] doit exister). Si
  /// [nouvelleClasseId] est fourni, change aussi sa classe pour l'inscription
  /// [inscriptionId] (refusé si des notes existent déjà). Tout ou rien.
  Future<void> modifier(
    Eleve eleve, {
    int? inscriptionId,
    int? nouvelleClasseId,
  }) async {
    controle.exiger(Permission.elevesGerer, 'modifier un élève');
    _verifier(eleve);
    await _db.transaction<void>((txn) async {
      final existe = await compter(
        txn,
        'SELECT COUNT(*) FROM eleve WHERE id = ?',
        [eleve.id],
      );
      if (existe == 0) throw const ErreurGesco('Élève introuvable.');
      await _verifierMatriculeLibre(txn, eleve.matricule, sauf: eleve.id);
      await txn.update(
        'eleve',
        _valeurs(eleve),
        where: 'id = ?',
        whereArgs: [eleve.id],
      );
      if (nouvelleClasseId != null) {
        if (inscriptionId == null) {
          throw const ErreurGesco('Inscription introuvable.');
        }
        await _changerDeClasse(txn, inscriptionId, nouvelleClasseId);
      }
    });
    await controle.noter(
      'modification',
      'eleve',
      id: eleve.id,
      details: '${eleve.nom.trim()} ${eleve.prenom.trim()}'
          '${nouvelleClasseId == null ? '' : ' (changement de classe)'}',
    );
  }

  /// Supprime l'inscription d'un élève pour son année.
  ///
  /// - Refusé s'il existe des notes, sauf si [avecNotes] est vrai : elles sont
  ///   alors supprimées avec l'inscription (action irréversible, à confirmer).
  /// - Si l'élève n'a plus aucune inscription, sa fiche est supprimée aussi.
  ///
  /// Retourne vrai si la fiche de l'élève a été supprimée.
  Future<bool> supprimerInscription(
    int inscriptionId, {
    bool avecNotes = false,
  }) async {
    controle.exiger(Permission.elevesSupprimer, 'supprimer un élève');
    var details = '';
    final fiche = await _db.transaction<bool>((txn) async {
      final lignes = await txn.query(
        'inscription',
        where: 'id = ?',
        whereArgs: [inscriptionId],
      );
      if (lignes.isEmpty) throw const ErreurGesco('Inscription introuvable.');
      final eleveId = lignes.first['eleve_id'] as int;
      final identite = await txn.query(
        'eleve',
        columns: ['nom', 'prenom', 'matricule'],
        where: 'id = ?',
        whereArgs: [eleveId],
      );
      if (identite.isNotEmpty) {
        final e = identite.first;
        details = '${e['nom']} ${e['prenom']} (${e['matricule']})';
      }

      final notes = await compter(
        txn,
        'SELECT COUNT(*) FROM note WHERE inscription_id = ?',
        [inscriptionId],
      );
      if (notes > 0 && !avecNotes) {
        throw ErreurGesco(
          'Impossible de supprimer cet élève : ${pluriel(notes, 'note')} '
          '${notes > 1 ? 'sont enregistrées' : 'est enregistrée'}.',
        );
      }
      if (notes > 0) {
        await txn.delete(
          'note',
          where: 'inscription_id = ?',
          whereArgs: [inscriptionId],
        );
      }
      await txn.delete('inscription', where: 'id = ?', whereArgs: [inscriptionId]);

      final restantes = await compter(
        txn,
        'SELECT COUNT(*) FROM inscription WHERE eleve_id = ?',
        [eleveId],
      );
      if (restantes == 0) {
        await txn.delete('eleve', where: 'id = ?', whereArgs: [eleveId]);
        return true;
      }
      return false;
    });
    await controle.noter(
      'suppression',
      'eleve',
      id: inscriptionId,
      details: avecNotes ? '$details (notes supprimées)' : details,
    );
    return fiche;
  }

  // --------------------------------------------------------------- Interne

  void _verifier(Eleve eleve) {
    final erreurs = erreursEleve(eleve, maintenant: _maintenant());
    if (erreurs.isNotEmpty) throw ErreurGesco(erreurs.join('\n'));
  }

  static Map<String, Object?> _valeurs(Eleve e) => {
        'matricule': e.matricule.trim(),
        'nom': e.nom.trim(),
        'prenom': e.prenom.trim(),
        'sexe': e.sexe,
        'date_naissance': e.dateNaissance,
        'lieu_naissance': _texteOuNull(e.lieuNaissance),
        'nom_pere': _texteOuNull(e.nomPere),
        'nom_mere': _texteOuNull(e.nomMere),
        'contact_parent': _texteOuNull(e.contactParent),
        'adresse': _texteOuNull(e.adresse),
        'photo': e.photo,
      };

  static String? _texteOuNull(String texte) {
    final t = texte.trim();
    return t.isEmpty ? null : t;
  }

  static Eleve _depuis(Map<String, Object?> l) => Eleve(
        id: l['id'] as int,
        matricule: l['matricule'] as String,
        nom: l['nom'] as String,
        prenom: l['prenom'] as String,
        sexe: l['sexe'] as String,
        dateNaissance: l['date_naissance'] as String?,
        lieuNaissance: (l['lieu_naissance'] as String?) ?? '',
        nomPere: (l['nom_pere'] as String?) ?? '',
        nomMere: (l['nom_mere'] as String?) ?? '',
        contactParent: (l['contact_parent'] as String?) ?? '',
        adresse: (l['adresse'] as String?) ?? '',
        photo: l['photo'] as Uint8List?,
      );

  Future<int> _inscrire(
    DatabaseExecutor db,
    int eleveId,
    int classeId,
    int anneeId,
  ) {
    return db.insert('inscription', {
      'eleve_id': eleveId,
      'classe_id': classeId,
      'annee_id': anneeId,
      'date_inscription': _maintenant().toIso8601String(),
    });
  }

  static Future<void> _verifierClasse(
    DatabaseExecutor db,
    int classeId,
    int anneeId,
  ) async {
    final ok = await compter(
      db,
      'SELECT COUNT(*) FROM classe WHERE id = ? AND annee_id = ?',
      [classeId, anneeId],
    );
    if (ok == 0) {
      throw const ErreurGesco(
        'Cette classe n\'existe pas pour l\'année scolaire choisie.',
      );
    }
  }

  static Future<void> _verifierMatriculeLibre(
    DatabaseExecutor db,
    String matricule, {
    int? sauf,
  }) async {
    // Comparaison faite en Dart (lower() de SQLite ignore les accents).
    final existants = await db.query('eleve', columns: ['id', 'matricule']);
    final cible = matricule.trim().toLowerCase();
    for (final l in existants) {
      if (l['id'] != sauf && (l['matricule'] as String).toLowerCase() == cible) {
        throw ErreurGesco('Le matricule « ${matricule.trim()} » est déjà utilisé.');
      }
    }
  }

  static Future<void> _changerDeClasse(
    DatabaseExecutor db,
    int inscriptionId,
    int nouvelleClasseId,
  ) async {
    final lignes = await db.query(
      'inscription',
      where: 'id = ?',
      whereArgs: [inscriptionId],
    );
    if (lignes.isEmpty) throw const ErreurGesco('Inscription introuvable.');
    final classeActuelle = lignes.first['classe_id'] as int;
    final anneeId = lignes.first['annee_id'] as int;
    if (classeActuelle == nouvelleClasseId) return;

    await _verifierClasse(db, nouvelleClasseId, anneeId);
    final notes = await compter(
      db,
      'SELECT COUNT(*) FROM note WHERE inscription_id = ?',
      [inscriptionId],
    );
    if (notes > 0) {
      throw ErreurGesco(
        'Impossible de changer de classe : ${pluriel(notes, 'note')} '
        '${notes > 1 ? 'sont déjà enregistrées' : 'est déjà enregistrée'} '
        'pour les matières de la classe actuelle.',
      );
    }
    await db.update(
      'inscription',
      {'classe_id': nouvelleClasseId},
      where: 'id = ?',
      whereArgs: [inscriptionId],
    );
  }
}
