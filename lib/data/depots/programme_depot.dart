import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/niveaux.dart';
import '../../domain/permissions.dart';
import '../controle.dart';
import '../erreurs.dart';
import 'aides.dart';

/// Une matière du programme d'un cycle (ou d'une option du lycée) pour une
/// année scolaire.
class MatiereProgramme {
  const MatiereProgramme({
    required this.id,
    required this.anneeId,
    required this.cycle,
    this.serie,
    required this.nom,
    required this.coefficient,
    this.bareme = 20,
    this.facultative = false,
    this.ordre = 0,
  });

  final int id;
  final int anneeId;
  final Cycle cycle;

  /// Option du lycée (SM, SE, SS) ; null hors lycée.
  final SerieLycee? serie;
  final String nom;

  /// En centièmes : 2,5 -> 250.
  final int coefficient;
  final int bareme;
  final bool facultative;
  final int ordre;
}

/// Ce qu'un changement du programme a fait dans les classes concernées.
class ResultatProgramme {
  const ResultatProgramme({
    this.classesConcernees = 0,
    this.ajoutees = 0,
    this.modifiees = 0,
    this.retirees = 0,
    this.conservees = const [],
  });

  /// Nombre de classes du cycle (ou de l'option) dans l'année.
  final int classesConcernees;

  /// Matières ajoutées dans des classes.
  final int ajoutees;

  /// Matières mises à jour (nom, coefficient...) dans des classes.
  final int modifiees;

  /// Matières retirées de classes.
  final int retirees;

  /// Classes où la matière n'a pas pu être modifiée ou retirée parce que des
  /// notes ou des évaluations existent (ou qu'une autre matière porte déjà le
  /// nom) : un message par classe.
  final List<String> conservees;

  /// Texte à afficher après l'opération.
  String get resume {
    if (classesConcernees == 0) {
      return 'Aucune classe n\'est encore rattachée à ce programme.';
    }
    final morceaux = <String>[
      if (ajoutees > 0) 'ajoutée dans ${pluriel(ajoutees, 'classe')}',
      if (modifiees > 0) 'mise à jour dans ${pluriel(modifiees, 'classe')}',
      if (retirees > 0) 'retirée de ${pluriel(retirees, 'classe')}',
    ];
    final base = morceaux.isEmpty
        ? 'Aucune classe à mettre à jour.'
        : 'Matière ${morceaux.join(', ')}.';
    return conservees.isEmpty ? base : '$base ${conservees.join(' ')}';
  }
}

/// Programme des cycles : les matières et leurs coefficients d'un cycle
/// (maternelle, primaire, collège) ou d'une option du lycée (SM, SE, SS),
/// propres à chaque année scolaire.
///
/// Une matière ajoutée au programme est **automatiquement ajoutée à chaque
/// classe** de ce cycle (de cette option) dans l'année ; une classe créée
/// ensuite reçoit tout le programme. Les notes déjà saisies ne sont jamais
/// perdues : une matière qui a des notes n'est pas retirée d'une classe.
class ProgrammeDepot {
  ProgrammeDepot(this._db, {this.controle = Controle.aucun});

  final Database _db;
  final Controle controle;

  static const int coefficientMax = 9999;

  static MatiereProgramme _depuis(Map<String, Object?> l) => MatiereProgramme(
        id: l['id'] as int,
        anneeId: l['annee_id'] as int,
        cycle: Cycle.depuisCle(l['cycle'] as String?)!,
        serie: SerieLycee.depuisCode(l['serie'] as String?),
        nom: l['nom'] as String,
        coefficient: l['coefficient'] as int,
        bareme: l['bareme'] as int,
        facultative: (l['facultative'] as int) == 1,
        ordre: l['ordre'] as int,
      );

  /// Matières du programme d'un cycle (et d'une option pour le lycée), dans
  /// l'ordre d'affichage.
  Future<List<MatiereProgramme>> lister(int anneeId, Cycle cycle, {SerieLycee? serie}) async {
    final lignes = await _db.query(
      'programme_matiere',
      where: 'annee_id = ? AND cycle = ? AND serie = ?',
      whereArgs: [anneeId, cycle.cle, _codeSerie(cycle, serie)],
      orderBy: 'ordre, id',
    );
    return [for (final l in lignes) _depuis(l)];
  }

  /// Nombre de matières du programme de chaque cycle et option d'une année
  /// (clé : `cycle` ou `lycee:SM`).
  Future<Map<String, int>> comptes(int anneeId) async {
    final lignes = await _db.rawQuery(
      'SELECT cycle, serie, COUNT(*) AS n FROM programme_matiere '
      'WHERE annee_id = ? GROUP BY cycle, serie',
      [anneeId],
    );
    return {
      for (final l in lignes)
        cleProgramme(
          Cycle.depuisCle(l['cycle'] as String?)!,
          SerieLycee.depuisCode(l['serie'] as String?),
        ): l['n'] as int,
    };
  }

  /// Clé d'un programme dans [comptes].
  static String cleProgramme(Cycle cycle, SerieLycee? serie) =>
      cycle == Cycle.lycee && serie != null ? 'lycee:${serie.code}' : cycle.cle;

  /// Ajoute une matière au programme et dans toutes les classes concernées.
  Future<(MatiereProgramme, ResultatProgramme)> ajouter({
    required int anneeId,
    required Cycle cycle,
    SerieLycee? serie,
    required String nom,
    required int coefficient,
    int bareme = 20,
    bool facultative = false,
  }) async {
    controle.exiger(Permission.classesGerer, 'modifier le programme d\'un cycle');
    final nomValide = _nomValide(nom);
    _verifierCoefficient(coefficient);
    _verifierBareme(bareme);
    final code = _codeSerie(cycle, serie, obligatoire: true);
    late MatiereProgramme matiere;
    late ResultatProgramme resultat;
    await _db.transaction<void>((txn) async {
      await _verifierAnnee(txn, anneeId);
      await _verifierNomLibre(txn, anneeId, cycle, code, nomValide);
      final ordre = await compter(
        txn,
        'SELECT COALESCE(MAX(ordre), -1) + 1 FROM programme_matiere '
        'WHERE annee_id = ? AND cycle = ? AND serie = ?',
        [anneeId, cycle.cle, code],
      );
      final id = await txn.insert('programme_matiere', {
        'annee_id': anneeId,
        'cycle': cycle.cle,
        'serie': code,
        'nom': nomValide,
        'coefficient': coefficient,
        'bareme': bareme,
        'facultative': facultative ? 1 : 0,
        'ordre': ordre,
      });
      matiere = MatiereProgramme(
        id: id,
        anneeId: anneeId,
        cycle: cycle,
        serie: serie,
        nom: nomValide,
        coefficient: coefficient,
        bareme: bareme,
        facultative: facultative,
        ordre: ordre,
      );
      resultat = await _propager(txn, matiere);
    });
    await controle.noter('creation', 'programme', id: matiere.id, details: '${_libelle(cycle, serie)} : $nomValide');
    return (matiere, resultat);
  }

  /// Modifie une matière du programme et la met à jour dans les classes
  /// concernées (là où elle porte encore son ancien nom). Les notes déjà saisies
  /// ne bougent pas ; le barème ne change pas dans une classe où des notes ou
  /// des évaluations existent.
  Future<ResultatProgramme> modifier(
    int id, {
    String? nom,
    int? coefficient,
    int? bareme,
    bool? facultative,
  }) async {
    controle.exiger(Permission.classesGerer, 'modifier le programme d\'un cycle');
    final nomValide = nom == null ? null : _nomValide(nom);
    if (coefficient != null) _verifierCoefficient(coefficient);
    if (bareme != null) _verifierBareme(bareme);
    late ResultatProgramme resultat;
    late MatiereProgramme apres;
    await _db.transaction<void>((txn) async {
      final avant = await _lire(txn, id);
      if (nomValide != null && nomValide.toLowerCase() != avant.nom.toLowerCase()) {
        await _verifierNomLibre(
          txn,
          avant.anneeId,
          avant.cycle,
          _codeSerie(avant.cycle, avant.serie),
          nomValide,
        );
      }
      await txn.update(
        'programme_matiere',
        {
          if (nomValide != null) 'nom': nomValide,
          if (coefficient != null) 'coefficient': coefficient,
          if (bareme != null) 'bareme': bareme,
          if (facultative != null) 'facultative': facultative ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      apres = await _lire(txn, id);
      resultat = await _propager(txn, apres, ancienNom: avant.nom);
    });
    await controle.noter('modification', 'programme', id: id, details: apres.nom);
    return resultat;
  }

  /// Retire une matière du programme et des classes où elle n'a ni note ni
  /// évaluation ; elle reste dans les autres (le résultat les indique).
  Future<ResultatProgramme> supprimer(int id) async {
    controle.exiger(Permission.classesGerer, 'modifier le programme d\'un cycle');
    late ResultatProgramme resultat;
    late MatiereProgramme matiere;
    await _db.transaction<void>((txn) async {
      matiere = await _lire(txn, id);
      final classes = await _classesConcernees(txn, matiere.anneeId, matiere.cycle, matiere.serie);
      var retirees = 0;
      final conservees = <String>[];
      for (final classe in classes) {
        final cible = await _matiereDeClasse(txn, classe.id, matiere.nom);
        if (cible == null) continue;
        if (await _aDesDonnees(txn, cible)) {
          conservees.add(
            '« ${matiere.nom} » reste dans la classe ${classe.nom} : des notes ou des '
            'évaluations y sont enregistrées.',
          );
          continue;
        }
        await txn.delete('matiere_classe', where: 'id = ?', whereArgs: [cible]);
        retirees++;
      }
      await txn.delete('programme_matiere', where: 'id = ?', whereArgs: [id]);
      resultat = ResultatProgramme(
        classesConcernees: classes.length,
        retirees: retirees,
        conservees: conservees,
      );
    });
    await controle.noter('suppression', 'programme', id: id, details: matiere.nom);
    return resultat;
  }

  /// Définit l'ordre d'affichage du programme. [idsDansLOrdre] doit contenir
  /// exactement les matières du programme, chacune une fois.
  Future<void> reordonner(
    int anneeId,
    Cycle cycle,
    List<int> idsDansLOrdre, {
    SerieLycee? serie,
  }) async {
    controle.exiger(Permission.classesGerer, 'modifier le programme d\'un cycle');
    final code = _codeSerie(cycle, serie);
    await _db.transaction<void>((txn) async {
      final actuelles = await txn.query(
        'programme_matiere',
        columns: ['id'],
        where: 'annee_id = ? AND cycle = ? AND serie = ?',
        whereArgs: [anneeId, cycle.cle, code],
      );
      final ids = {for (final l in actuelles) l['id'] as int};
      final demandes = idsDansLOrdre.toSet();
      if (demandes.length != idsDansLOrdre.length ||
          demandes.length != ids.length ||
          !ids.containsAll(demandes)) {
        throw const ErreurGesco('L\'ordre demandé ne correspond pas aux matières du programme.');
      }
      for (var i = 0; i < idsDansLOrdre.length; i++) {
        await txn.update(
          'programme_matiere',
          {'ordre': i},
          where: 'id = ?',
          whereArgs: [idsDansLOrdre[i]],
        );
      }
    });
  }

  /// Ajoute à toutes les classes du cycle (de l'option) les matières du
  /// programme qui leur manquent. Les matières existantes ne sont pas touchées.
  Future<ResultatProgramme> appliquer(int anneeId, Cycle cycle, {SerieLycee? serie}) async {
    controle.exiger(Permission.classesGerer, 'appliquer le programme d\'un cycle');
    _codeSerie(cycle, serie, obligatoire: true);
    late ResultatProgramme resultat;
    await _db.transaction<void>((txn) async {
      await _verifierAnnee(txn, anneeId);
      final classes = await _classesConcernees(txn, anneeId, cycle, serie);
      var ajoutees = 0;
      for (final classe in classes) {
        ajoutees += await appliquerALaClasse(txn, classe.id);
      }
      resultat = ResultatProgramme(classesConcernees: classes.length, ajoutees: ajoutees);
    });
    if (resultat.ajoutees > 0) {
      await controle.noter(
        'application',
        'programme',
        id: anneeId,
        details: '${_libelle(cycle, serie)} : ${resultat.ajoutees} matière(s) ajoutée(s)',
      );
    }
    return resultat;
  }

  /// Classes d'une année rattachées à un cycle (et à une option du lycée).
  Future<List<({int id, String nom})>> classes(int anneeId, Cycle cycle, {SerieLycee? serie}) =>
      _classesConcernees(_db, anneeId, cycle, serie);

  /// Ajoute à la classe les matières du programme de son cycle (et de son
  /// option) qu'elle n'a pas encore ; retourne leur nombre. Une classe sans
  /// niveau du catalogue, ou de lycée sans option, ne reçoit rien.
  static Future<int> appliquerALaClasse(DatabaseExecutor db, int classeId) async {
    final lignes = await db.query(
      'classe',
      columns: ['annee_id', 'niveau_code', 'serie'],
      where: 'id = ?',
      whereArgs: [classeId],
    );
    if (lignes.isEmpty) return 0;
    final cycle = cycleDuNiveau(lignes.first['niveau_code'] as int?);
    if (cycle == null) return 0;
    final serie = (lignes.first['serie'] as String?) ?? '';
    if (cycle == Cycle.lycee && serie.isEmpty) return 0;
    final programme = await db.query(
      'programme_matiere',
      where: 'annee_id = ? AND cycle = ? AND serie = ?',
      whereArgs: [lignes.first['annee_id'], cycle.cle, cycle == Cycle.lycee ? serie : ''],
      orderBy: 'ordre, id',
    );
    if (programme.isEmpty) return 0;
    final presentes = {
      for (final l in await db.query(
        'matiere_classe',
        columns: ['nom'],
        where: 'classe_id = ?',
        whereArgs: [classeId],
      ))
        (l['nom'] as String).toLowerCase(),
    };
    var ordre = await compter(
      db,
      'SELECT COALESCE(MAX(ordre), -1) + 1 FROM matiere_classe WHERE classe_id = ?',
      [classeId],
    );
    var ajoutees = 0;
    for (final m in programme) {
      final nom = m['nom'] as String;
      if (presentes.contains(nom.toLowerCase())) continue;
      await db.insert('matiere_classe', {
        'classe_id': classeId,
        'nom': nom,
        'coefficient': m['coefficient'],
        'ordre': ordre++,
        'bareme': m['bareme'],
        'facultative': m['facultative'],
      });
      ajoutees++;
    }
    return ajoutees;
  }

  /// Copie le programme d'une année dans une autre (nouvelle année).
  static Future<void> copierProgramme(DatabaseExecutor db, int source, int cible) async {
    final lignes = await db.query(
      'programme_matiere',
      where: 'annee_id = ?',
      whereArgs: [source],
      orderBy: 'cycle, serie, ordre, id',
    );
    for (final l in lignes) {
      await db.insert('programme_matiere', {
        'annee_id': cible,
        'cycle': l['cycle'],
        'serie': l['serie'],
        'nom': l['nom'],
        'coefficient': l['coefficient'],
        'bareme': l['bareme'],
        'facultative': l['facultative'],
        'ordre': l['ordre'],
      });
    }
  }

  // ------------------------------------------------------------ Internes

  /// Répercute la matière du programme dans les classes du cycle : l'ajoute
  /// là où elle manque, la met à jour là où elle porte [ancienNom].
  static Future<ResultatProgramme> _propager(
    DatabaseExecutor db,
    MatiereProgramme m, {
    String? ancienNom,
  }) async {
    final classes = await _classesConcernees(db, m.anneeId, m.cycle, m.serie);
    var ajoutees = 0;
    var modifiees = 0;
    final conservees = <String>[];
    for (final classe in classes) {
      final existante = await _matiereDeClasse(db, classe.id, ancienNom ?? m.nom);
      if (existante == null) {
        if (ancienNom != null) {
          // Matière du programme absente de cette classe (retirée à la main) :
          // on ne la remet pas à l'occasion d'une simple modification.
          continue;
        }
        final ordre = await compter(
          db,
          'SELECT COALESCE(MAX(ordre), -1) + 1 FROM matiere_classe WHERE classe_id = ?',
          [classe.id],
        );
        await db.insert('matiere_classe', {
          'classe_id': classe.id,
          'nom': m.nom,
          'coefficient': m.coefficient,
          'ordre': ordre,
          'bareme': m.bareme,
          'facultative': m.facultative ? 1 : 0,
        });
        ajoutees++;
        continue;
      }
      if (ancienNom == null) continue; // ajout : la matière existe déjà, rien à faire
      final valeurs = <String, Object?>{
        'coefficient': m.coefficient,
        'facultative': m.facultative ? 1 : 0,
      };
      if (ancienNom != m.nom) {
        final autre = await _matiereDeClasse(db, classe.id, m.nom);
        if (autre != null && autre != existante) {
          conservees.add(
            'La matière « $ancienNom » de la classe ${classe.nom} garde son nom : '
            '« ${m.nom} » y existe déjà.',
          );
        } else {
          valeurs['nom'] = m.nom;
        }
      }
      final bareme = (await db.query(
        'matiere_classe',
        columns: ['bareme'],
        where: 'id = ?',
        whereArgs: [existante],
      ))
          .first['bareme'] as int;
      if (bareme != m.bareme) {
        if (await _aDesDonnees(db, existante)) {
          conservees.add(
            'Le barème de « ${m.nom} » reste $bareme dans la classe ${classe.nom} : '
            'des notes ou des évaluations y sont enregistrées.',
          );
        } else {
          valeurs['bareme'] = m.bareme;
        }
      }
      await db.update('matiere_classe', valeurs, where: 'id = ?', whereArgs: [existante]);
      modifiees++;
    }
    return ResultatProgramme(
      classesConcernees: classes.length,
      ajoutees: ajoutees,
      modifiees: modifiees,
      conservees: conservees,
    );
  }

  static Future<List<({int id, String nom})>> _classesConcernees(
    DatabaseExecutor db,
    int anneeId,
    Cycle cycle,
    SerieLycee? serie,
  ) async {
    final lignes = await db.query(
      'classe',
      columns: ['id', 'nom', 'niveau_code', 'serie'],
      where: 'annee_id = ?',
      whereArgs: [anneeId],
      orderBy: 'id',
    );
    return [
      for (final l in lignes)
        if (cycleDuNiveau(l['niveau_code'] as int?) == cycle &&
            (cycle != Cycle.lycee || l['serie'] == serie?.code))
          (id: l['id'] as int, nom: l['nom'] as String),
    ];
  }

  /// Identifiant de la matière de la classe qui porte ce nom (sans tenir
  /// compte de la casse), ou null.
  static Future<int?> _matiereDeClasse(DatabaseExecutor db, int classeId, String nom) async {
    final lignes = await db.query(
      'matiere_classe',
      columns: ['id', 'nom'],
      where: 'classe_id = ?',
      whereArgs: [classeId],
    );
    final cible = nom.toLowerCase();
    for (final l in lignes) {
      if ((l['nom'] as String).toLowerCase() == cible) return l['id'] as int;
    }
    return null;
  }

  /// Vrai si la matière de classe a des notes ou des évaluations.
  static Future<bool> _aDesDonnees(DatabaseExecutor db, int matiereId) async {
    final notes = await compter(db, 'SELECT COUNT(*) FROM note WHERE matiere_id = ?', [matiereId]);
    if (notes > 0) return true;
    final evaluations = await compter(
      db,
      'SELECT COUNT(*) FROM evaluation WHERE matiere_id = ?',
      [matiereId],
    );
    return evaluations > 0;
  }

  static Future<MatiereProgramme> _lire(DatabaseExecutor db, int id) async {
    final lignes = await db.query('programme_matiere', where: 'id = ?', whereArgs: [id]);
    if (lignes.isEmpty) throw const ErreurGesco('Matière du programme introuvable.');
    return _depuis(lignes.first);
  }

  static Future<void> _verifierAnnee(DatabaseExecutor db, int anneeId) async {
    final n = await compter(db, 'SELECT COUNT(*) FROM annee_scolaire WHERE id = ?', [anneeId]);
    if (n == 0) throw const ErreurGesco('Année scolaire introuvable.');
  }

  static Future<void> _verifierNomLibre(
    DatabaseExecutor db,
    int anneeId,
    Cycle cycle,
    String serie,
    String nom,
  ) async {
    // Comparaison faite en Dart : lower() de SQLite ignore les lettres accentuées.
    final existantes = await db.query(
      'programme_matiere',
      columns: ['nom'],
      where: 'annee_id = ? AND cycle = ? AND serie = ?',
      whereArgs: [anneeId, cycle.cle, serie],
    );
    final cible = nom.toLowerCase();
    for (final l in existantes) {
      if ((l['nom'] as String).toLowerCase() == cible) {
        throw ErreurGesco('La matière « $nom » existe déjà dans ce programme.');
      }
    }
  }

  /// Code d'option enregistré : SM, SE, SS pour le lycée, chaîne vide sinon.
  /// Avec [obligatoire], le lycée exige une option.
  static String _codeSerie(Cycle cycle, SerieLycee? serie, {bool obligatoire = false}) {
    if (cycle != Cycle.lycee) {
      if (serie != null) {
        throw ErreurGesco('Une option n\'existe que pour le lycée (${cycle.libelle} n\'en a pas).');
      }
      return '';
    }
    if (serie == null) {
      if (obligatoire) {
        throw const ErreurGesco(
          'Choisissez l\'option du lycée (sciences mathématiques, expérimentales ou sociales).',
        );
      }
      return '';
    }
    return serie.code;
  }

  static String _libelle(Cycle cycle, SerieLycee? serie) =>
      serie == null ? cycle.libelle : '${cycle.libelle} ${serie.code}';

  static String _nomValide(String nom) {
    final n = nom.trim();
    if (n.isEmpty) throw const ErreurGesco('Le nom de la matière est obligatoire.');
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

  static void _verifierBareme(int bareme) {
    if (bareme < 1 || bareme > 1000) {
      throw const ErreurGesco('Le barème doit être compris entre 1 et 1000.');
    }
  }
}
