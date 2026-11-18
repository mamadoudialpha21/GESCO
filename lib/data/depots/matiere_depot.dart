import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/permissions.dart';
import '../controle.dart';
import '../erreurs.dart';
import '../modeles_donnees.dart';
import 'aides.dart';

/// Matières et coefficients d'une classe.
///
/// Chaque classe a ses propres matières, en nombre libre (aucune limite
/// artificielle). Les coefficients sont en centièmes (2,5 -> 250) et
/// modifiables à tout moment : les notes brutes ne sont jamais touchées.
class MatiereDepot {
  MatiereDepot(this._db, {this.controle = Controle.aucun});

  final Database _db;
  final Controle controle;

  static const int coefficientMax = 9999;

  static MatiereClasse _depuis(Map<String, Object?> l) => MatiereClasse(
        id: l['id'] as int,
        classeId: l['classe_id'] as int,
        nom: l['nom'] as String,
        coefficient: l['coefficient'] as int,
        ordre: l['ordre'] as int,
      );

  /// Matières d'une classe, dans l'ordre d'affichage.
  Future<List<MatiereClasse>> lister(int classeId) async {
    final lignes = await _db.query(
      'matiere_classe',
      where: 'classe_id = ?',
      whereArgs: [classeId],
      orderBy: 'ordre, id',
    );
    return [for (final l in lignes) _depuis(l)];
  }

  /// Nombre de notes (toutes périodes) enregistrées pour une matière.
  Future<int> nbNotes(int matiereId) => compter(
        _db,
        'SELECT COUNT(*) FROM note WHERE matiere_id = ?',
        [matiereId],
      );

  Future<MatiereClasse> ajouter({
    required int classeId,
    required String nom,
    required int coefficient,
  }) async {
    controle.exiger(Permission.classesGerer, 'ajouter une matière');
    final nomValide = _nomValide(nom);
    _verifierCoefficient(coefficient);
    final matiere = await _db.transaction<MatiereClasse>((txn) async {
      await _verifierClasse(txn, classeId);
      await _verifierNomLibre(txn, classeId, nomValide);
      final ordre = await _prochainOrdre(txn, classeId);
      final id = await txn.insert('matiere_classe', {
        'classe_id': classeId,
        'nom': nomValide,
        'coefficient': coefficient,
        'ordre': ordre,
      });
      return MatiereClasse(
        id: id,
        classeId: classeId,
        nom: nomValide,
        coefficient: coefficient,
        ordre: ordre,
      );
    });
    await controle.noter('creation', 'matiere', id: matiere.id, details: nomValide);
    return matiere;
  }

  /// Modifie le nom et/ou le coefficient. Les notes déjà saisies restent
  /// inchangées ; seules les moyennes seront recalculées.
  Future<void> modifier(int id, {String? nom, int? coefficient}) async {
    controle.exiger(Permission.classesGerer, 'modifier une matière');
    final nomValide = nom == null ? null : _nomValide(nom);
    if (coefficient != null) _verifierCoefficient(coefficient);
    var modifiee = false;
    await _db.transaction<void>((txn) async {
      final lignes = await txn.query(
        'matiere_classe',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (lignes.isEmpty) throw const ErreurGesco('Matière introuvable.');
      final classeId = lignes.first['classe_id'] as int;
      if (nomValide != null) {
        await _verifierNomLibre(txn, classeId, nomValide, sauf: id);
      }
      final valeurs = <String, Object?>{
        if (nomValide != null) 'nom': nomValide,
        if (coefficient != null) 'coefficient': coefficient,
      };
      if (valeurs.isEmpty) return;
      await txn.update(
        'matiere_classe',
        valeurs,
        where: 'id = ?',
        whereArgs: [id],
      );
      modifiee = true;
    });
    if (modifiee) {
      await controle.noter(
        'modification',
        'matiere',
        id: id,
        details: [
          if (nomValide != null) nomValide,
          if (coefficient != null) 'coefficient $coefficient',
        ].join(', '),
      );
    }
  }

  /// Supprime une matière. Refusé si des notes y sont rattachées : on ne perd
  /// jamais de notes par accident.
  Future<void> supprimer(int id) async {
    controle.exiger(Permission.classesGerer, 'supprimer une matière');
    final lignes = await _db.query(
      'matiere_classe',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (lignes.isEmpty) throw const ErreurGesco('Matière introuvable.');
    final nom = lignes.first['nom'] as String;
    final notes = await nbNotes(id);
    if (notes > 0) {
      throw ErreurGesco(
        'Impossible de supprimer la matière « $nom » : '
        '${pluriel(notes, 'note')} y '
        '${notes > 1 ? 'sont enregistrées' : 'est enregistrée'}.',
      );
    }
    await _db.delete('matiere_classe', where: 'id = ?', whereArgs: [id]);
    await controle.noter('suppression', 'matiere', id: id, details: nom);
  }

  /// Définit l'ordre d'affichage. [idsDansLOrdre] doit contenir exactement
  /// les matières de la classe, chacune une fois.
  Future<void> reordonner(int classeId, List<int> idsDansLOrdre) async {
    controle.exiger(Permission.classesGerer, 'réordonner les matières');
    await _db.transaction<void>((txn) async {
      final actuelles = await txn.query(
        'matiere_classe',
        columns: ['id'],
        where: 'classe_id = ?',
        whereArgs: [classeId],
      );
      final idsActuels = {for (final l in actuelles) l['id'] as int};
      final idsDemandes = idsDansLOrdre.toSet();
      if (idsDemandes.length != idsDansLOrdre.length ||
          idsDemandes.length != idsActuels.length ||
          !idsActuels.containsAll(idsDemandes)) {
        throw const ErreurGesco(
          'L\'ordre demandé ne correspond pas aux matières de la classe.',
        );
      }
      for (var i = 0; i < idsDansLOrdre.length; i++) {
        await txn.update(
          'matiere_classe',
          {'ordre': i},
          where: 'id = ?',
          whereArgs: [idsDansLOrdre[i]],
        );
      }
    });
  }

  /// Copie dans [versClasseId] les matières de [depuisClasseId] qui n'y
  /// existent pas encore (comparaison du nom sans tenir compte de la casse).
  /// Retourne le nombre de matières ajoutées.
  Future<int> copier({
    required int depuisClasseId,
    required int versClasseId,
  }) async {
    controle.exiger(Permission.classesGerer, 'copier des matières');
    if (depuisClasseId == versClasseId) {
      throw const ErreurGesco(
        'Choisissez une classe différente comme source de la copie.',
      );
    }
    final ajoutees = await _db.transaction<int>((txn) async {
      await _verifierClasse(txn, depuisClasseId);
      await _verifierClasse(txn, versClasseId);
      final sources = await txn.query(
        'matiere_classe',
        where: 'classe_id = ?',
        whereArgs: [depuisClasseId],
        orderBy: 'ordre, id',
      );
      final presentes = {
        for (final l in await txn.query(
          'matiere_classe',
          columns: ['nom'],
          where: 'classe_id = ?',
          whereArgs: [versClasseId],
        ))
          (l['nom'] as String).toLowerCase(),
      };
      var ordre = await _prochainOrdre(txn, versClasseId);
      var copiees = 0;
      for (final s in sources) {
        final nom = s['nom'] as String;
        if (presentes.contains(nom.toLowerCase())) continue;
        await txn.insert('matiere_classe', {
          'classe_id': versClasseId,
          'nom': nom,
          'coefficient': s['coefficient'],
          'ordre': ordre++,
        });
        copiees++;
      }
      return copiees;
    });
    if (ajoutees > 0) {
      await controle.noter(
        'copie',
        'matiere',
        id: versClasseId,
        details: '$ajoutees matière(s) copiée(s)',
      );
    }
    return ajoutees;
  }

  static String _nomValide(String nom) {
    final n = nom.trim();
    if (n.isEmpty) {
      throw const ErreurGesco('Le nom de la matière est obligatoire.');
    }
    if (n.length > 80) {
      throw const ErreurGesco('Le nom de la matière est trop long (80 caractères maximum).');
    }
    return n;
  }

  static void _verifierCoefficient(int coefficient) {
    if (coefficient <= 0 || coefficient > coefficientMax) {
      throw const ErreurGesco(
        'Le coefficient doit être strictement positif et inférieur à 100.',
      );
    }
  }

  static Future<void> _verifierClasse(DatabaseExecutor db, int classeId) async {
    final existe = await compter(
      db,
      'SELECT COUNT(*) FROM classe WHERE id = ?',
      [classeId],
    );
    if (existe == 0) throw const ErreurGesco('Classe introuvable.');
  }

  static Future<void> _verifierNomLibre(
    DatabaseExecutor db,
    int classeId,
    String nom, {
    int? sauf,
  }) async {
    // Comparaison faite en Dart : la fonction lower() de SQLite ne gère pas
    // les lettres accentuées (« Éducation » et « éducation » seraient
    // considérées comme différentes).
    final existantes = await db.query(
      'matiere_classe',
      columns: ['id', 'nom'],
      where: 'classe_id = ?',
      whereArgs: [classeId],
    );
    final cible = nom.toLowerCase();
    for (final l in existantes) {
      if (l['id'] != sauf && (l['nom'] as String).toLowerCase() == cible) {
        throw ErreurGesco('La matière « $nom » existe déjà dans cette classe.');
      }
    }
  }

  static Future<int> _prochainOrdre(DatabaseExecutor db, int classeId) async {
    final lignes = await db.rawQuery(
      'SELECT COALESCE(MAX(ordre), -1) + 1 FROM matiere_classe '
      'WHERE classe_id = ?',
      [classeId],
    );
    return (lignes.first.values.first as int?) ?? 0;
  }
}
