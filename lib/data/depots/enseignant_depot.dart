import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/permissions.dart';
import '../../domain/recherche.dart';
import '../controle.dart';
import '../erreurs.dart';
import '../images.dart';
import '../modeles_donnees.dart';
import 'aides.dart';

/// Enseignants : fiche, matières enseignées, classes confiées.
///
/// Un enseignant n'est pas lié à une année : ses affectations (matières et
/// classes) le sont, puisque les classes sont propres à chaque année.
class EnseignantDepot {
  EnseignantDepot(this._db, {this.controle = Controle.aucun, DateTime Function()? maintenant})
      : _maintenant = maintenant ?? DateTime.now;

  final Database _db;
  final Controle controle;
  final DateTime Function() _maintenant;

  static const int longueurMaxNom = 60;
  static const int longueurMaxTexte = 120;

  static Enseignant _depuis(Map<String, Object?> l) => Enseignant(
        id: l['id'] as int,
        matricule: (l['matricule'] as String?) ?? '',
        nom: l['nom'] as String,
        prenom: l['prenom'] as String,
        sexe: l['sexe'] as String?,
        telephone: (l['telephone'] as String?) ?? '',
        email: (l['email'] as String?) ?? '',
        specialite: (l['specialite'] as String?) ?? '',
        actif: ((l['actif'] as int?) ?? 1) == 1,
        peutSaisir: ((l['peut_saisir'] as int?) ?? 1) == 1,
        signature: l['signature'] as Uint8List?,
      );

  /// Enseignants triés par nom puis prénom. Si [anneeId] est donné, le nombre
  /// de matières et de classes concerne cette année (sinon 0).
  Future<List<EnseignantResume>> lister({
    int? anneeId,
    bool actifsSeulement = false,
  }) async {
    final lignes = await _db.query(
      'enseignant',
      columns: [
        'id',
        'matricule',
        'nom',
        'prenom',
        'sexe',
        'telephone',
        'email',
        'specialite',
        'actif',
        'peut_saisir',
      ],
      where: actifsSeulement ? 'actif = 1' : null,
    );
    final matieres = <int, int>{};
    final classes = <int, Set<int>>{};
    if (anneeId != null) {
      final m = await _db.rawQuery(
        '''
        SELECT mc.enseignant_id AS ens, mc.classe_id AS classe
        FROM matiere_classe mc JOIN classe c ON c.id = mc.classe_id
        WHERE c.annee_id = ? AND mc.enseignant_id IS NOT NULL
        ''',
        [anneeId],
      );
      for (final r in m) {
        final ens = r['ens'] as int;
        matieres[ens] = (matieres[ens] ?? 0) + 1;
        (classes[ens] ??= {}).add(r['classe'] as int);
      }
      final p = await _db.rawQuery(
        '''
        SELECT c.prof_principal_id AS ens, c.id AS classe FROM classe c
        WHERE c.annee_id = ? AND c.prof_principal_id IS NOT NULL
        ''',
        [anneeId],
      );
      for (final r in p) {
        (classes[r['ens'] as int] ??= {}).add(r['classe'] as int);
      }
      final conf = await _db.rawQuery(
        '''
        SELECT ec.enseignant_id AS ens, ec.classe_id AS classe
        FROM enseignant_classe ec JOIN classe c ON c.id = ec.classe_id
        WHERE c.annee_id = ?
        ''',
        [anneeId],
      );
      for (final r in conf) {
        (classes[r['ens'] as int] ??= {}).add(r['classe'] as int);
      }
    }
    final liste = [
      for (final l in lignes)
        EnseignantResume(
          enseignant: _depuis(l),
          nbMatieres: matieres[l['id'] as int] ?? 0,
          nbClasses: classes[l['id'] as int]?.length ?? 0,
        ),
    ];
    liste.sort((a, b) {
      final parNom = normaliserRecherche(a.enseignant.nom)
          .compareTo(normaliserRecherche(b.enseignant.nom));
      if (parNom != 0) return parNom;
      final parPrenom = normaliserRecherche(a.enseignant.prenom)
          .compareTo(normaliserRecherche(b.enseignant.prenom));
      if (parPrenom != 0) return parPrenom;
      return a.enseignant.id.compareTo(b.enseignant.id);
    });
    return liste;
  }

  /// Fiche complète (avec la signature), ou null.
  Future<Enseignant?> obtenir(int id) async {
    final lignes = await _db.query('enseignant', where: 'id = ?', whereArgs: [id]);
    return lignes.isEmpty ? null : _depuis(lignes.first);
  }

  /// Crée un enseignant et retourne son identifiant.
  Future<int> creer(Enseignant enseignant) async {
    controle.exiger(Permission.enseignantsGerer, 'ajouter un enseignant');
    _verifier(enseignant);
    final id = await _db.transaction<int>((txn) async {
      await _verifierMatriculeLibre(txn, enseignant.matricule);
      return txn.insert('enseignant', {
        ..._valeurs(enseignant),
        'cree_le': horodatage(_maintenant()),
      });
    });
    await controle.noter(
      'creation',
      'enseignant',
      id: id,
      details: enseignant.nomComplet,
    );
    return id;
  }

  Future<void> modifier(Enseignant enseignant) async {
    controle.exiger(Permission.enseignantsGerer, 'modifier un enseignant');
    _verifier(enseignant);
    await _db.transaction<void>((txn) async {
      final existe = await compter(
        txn,
        'SELECT COUNT(*) FROM enseignant WHERE id = ?',
        [enseignant.id],
      );
      if (existe == 0) throw const ErreurGesco('Enseignant introuvable.');
      await _verifierMatriculeLibre(txn, enseignant.matricule, sauf: enseignant.id);
      await txn.update(
        'enseignant',
        _valeurs(enseignant),
        where: 'id = ?',
        whereArgs: [enseignant.id],
      );
    });
    await controle.noter(
      'modification',
      'enseignant',
      id: enseignant.id,
      details: enseignant.nomComplet,
    );
  }

  /// Supprime un enseignant. Refusé tant qu'il enseigne une matière, est
  /// professeur principal, a des classes confiées ou possède un compte :
  /// il suffit alors de le désactiver.
  Future<void> supprimer(int id) async {
    controle.exiger(Permission.enseignantsGerer, 'supprimer un enseignant');
    final enseignant = await obtenir(id);
    if (enseignant == null) throw const ErreurGesco('Enseignant introuvable.');
    final raisons = <String>[];
    final matieres = await compter(
      _db,
      'SELECT COUNT(*) FROM matiere_classe WHERE enseignant_id = ?',
      [id],
    );
    if (matieres > 0) raisons.add('il enseigne ${pluriel(matieres, 'matière')}');
    final principal = await compter(
      _db,
      'SELECT COUNT(*) FROM classe WHERE prof_principal_id = ?',
      [id],
    );
    if (principal > 0) {
      raisons.add('il est professeur principal de ${pluriel(principal, 'classe')}');
    }
    final confiees = await compter(
      _db,
      'SELECT COUNT(*) FROM enseignant_classe WHERE enseignant_id = ?',
      [id],
    );
    if (confiees > 0) raisons.add('${pluriel(confiees, 'classe')} lui ${confiees > 1 ? 'sont confiées' : 'est confiée'}');
    final comptes = await compter(
      _db,
      'SELECT COUNT(*) FROM utilisateur WHERE enseignant_id = ?',
      [id],
    );
    if (comptes > 0) raisons.add('un compte utilisateur lui est lié');
    if (raisons.isNotEmpty) {
      throw ErreurGesco(
        'Impossible de supprimer ${enseignant.nomComplet} : ${raisons.join(', ')}. '
        'Vous pouvez le désactiver à la place.',
      );
    }
    await _db.delete('enseignant', where: 'id = ?', whereArgs: [id]);
    await controle.noter('suppression', 'enseignant', id: id, details: enseignant.nomComplet);
  }

  /// Matières enseignées par [enseignantId], pour [anneeId] ou toutes les
  /// années, triées par année, classe puis matière.
  Future<List<AffectationMatiere>> matieres(int enseignantId, {int? anneeId}) async {
    final lignes = await _db.rawQuery(
      '''
      SELECT mc.id AS matiere_id, mc.nom AS matiere_nom, c.id AS classe_id,
             c.nom AS classe_nom, c.annee_id AS annee_id
      FROM matiere_classe mc JOIN classe c ON c.id = mc.classe_id
      WHERE mc.enseignant_id = ? ${anneeId == null ? '' : 'AND c.annee_id = ?'}
      ORDER BY c.annee_id DESC, c.niveau COLLATE NOCASE, c.nom COLLATE NOCASE,
               mc.ordre, mc.id
      ''',
      [enseignantId, if (anneeId != null) anneeId],
    );
    return [
      for (final l in lignes)
        AffectationMatiere(
          matiereId: l['matiere_id'] as int,
          matiereNom: l['matiere_nom'] as String,
          classeId: l['classe_id'] as int,
          classeNom: l['classe_nom'] as String,
          anneeId: l['annee_id'] as int,
        ),
    ];
  }

  /// Identifiants des classes de [anneeId] confiées à l'enseignant (hors
  /// matières enseignées et professeur principal).
  Future<Set<int>> classesConfiees(int enseignantId, int anneeId) async {
    final lignes = await _db.rawQuery(
      '''
      SELECT ec.classe_id AS classe FROM enseignant_classe ec
      JOIN classe c ON c.id = ec.classe_id
      WHERE ec.enseignant_id = ? AND c.annee_id = ?
      ''',
      [enseignantId, anneeId],
    );
    return {for (final l in lignes) l['classe'] as int};
  }

  /// Remplace les classes confiées à l'enseignant pour [anneeId]. Les
  /// classes d'autres années ne sont pas touchées.
  Future<void> definirClassesConfiees(
    int enseignantId,
    int anneeId,
    Set<int> classeIds,
  ) async {
    controle.exiger(Permission.enseignantsGerer, 'confier des classes');
    await _db.transaction<void>((txn) async {
      final existe = await compter(
        txn,
        'SELECT COUNT(*) FROM enseignant WHERE id = ?',
        [enseignantId],
      );
      if (existe == 0) throw const ErreurGesco('Enseignant introuvable.');
      for (final classeId in classeIds) {
        final ok = await compter(
          txn,
          'SELECT COUNT(*) FROM classe WHERE id = ? AND annee_id = ?',
          [classeId, anneeId],
        );
        if (ok == 0) {
          throw const ErreurGesco(
            'Une des classes choisies n\'existe pas pour cette année scolaire.',
          );
        }
      }
      await txn.rawDelete(
        'DELETE FROM enseignant_classe WHERE enseignant_id = ? AND classe_id IN '
        '(SELECT id FROM classe WHERE annee_id = ?)',
        [enseignantId, anneeId],
      );
      for (final classeId in classeIds) {
        await txn.insert('enseignant_classe', {
          'enseignant_id': enseignantId,
          'classe_id': classeId,
        });
      }
    });
    await controle.noter(
      'modification',
      'enseignant',
      id: enseignantId,
      details: 'classes confiées : ${classeIds.length}',
    );
  }

  /// Toutes les classes de [anneeId] auxquelles l'enseignant est rattaché
  /// (matière enseignée, classe confiée ou professeur principal).
  Future<Set<int>> classesDeLEnseignant(int enseignantId, int anneeId) async {
    final lignes = await _db.rawQuery(
      '''
      SELECT mc.classe_id AS classe FROM matiere_classe mc
        JOIN classe c ON c.id = mc.classe_id
        WHERE mc.enseignant_id = ?1 AND c.annee_id = ?2
      UNION
      SELECT ec.classe_id FROM enseignant_classe ec
        JOIN classe c ON c.id = ec.classe_id
        WHERE ec.enseignant_id = ?1 AND c.annee_id = ?2
      UNION
      SELECT c.id FROM classe c
        WHERE c.prof_principal_id = ?1 AND c.annee_id = ?2
      ''',
      [enseignantId, anneeId],
    );
    return {for (final l in lignes) l['classe'] as int};
  }

  // --------------------------------------------------------------- Interne

  void _verifier(Enseignant e) {
    final erreurs = <String>[];
    void obligatoire(String valeur, String nom, int max) {
      final v = valeur.trim();
      if (v.isEmpty) {
        erreurs.add('$nom est obligatoire.');
      } else if (v.length > max) {
        erreurs.add('$nom est trop long ($max caractères maximum).');
      }
    }

    void facultatif(String valeur, String nom) {
      if (valeur.trim().length > longueurMaxTexte) {
        erreurs.add('$nom est trop long ($longueurMaxTexte caractères maximum).');
      }
    }

    obligatoire(e.nom, 'Le nom', longueurMaxNom);
    obligatoire(e.prenom, 'Le prénom', longueurMaxNom);
    facultatif(e.matricule, 'Le matricule');
    facultatif(e.telephone, 'Le téléphone');
    facultatif(e.email, 'L\'adresse e-mail');
    facultatif(e.specialite, 'La spécialité');
    if (e.sexe != null && e.sexe != 'M' && e.sexe != 'F') {
      erreurs.add('Le sexe doit être masculin ou féminin.');
    }
    final courriel = e.email.trim();
    if (courriel.isNotEmpty && !_courrielValide(courriel)) {
      erreurs.add('L\'adresse e-mail est invalide.');
    }
    final signature = e.signature;
    if (signature != null) {
      try {
        verifierImage(signature, tailleMax: tailleMaxLogo, nom: 'La signature');
      } on ErreurGesco catch (erreur) {
        erreurs.add(erreur.message);
      }
    }
    if (erreurs.isNotEmpty) throw ErreurGesco(erreurs.join('\n'));
  }

  static bool _courrielValide(String s) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);

  static String? _texteOuNull(String texte) {
    final t = texte.trim();
    return t.isEmpty ? null : t;
  }

  static Map<String, Object?> _valeurs(Enseignant e) => {
        'matricule': _texteOuNull(e.matricule),
        'nom': e.nom.trim(),
        'prenom': e.prenom.trim(),
        'sexe': e.sexe,
        'telephone': _texteOuNull(e.telephone),
        'email': _texteOuNull(e.email),
        'specialite': _texteOuNull(e.specialite),
        'actif': e.actif ? 1 : 0,
        'peut_saisir': e.peutSaisir ? 1 : 0,
        'signature': e.signature,
      };

  static Future<void> _verifierMatriculeLibre(
    DatabaseExecutor db,
    String matricule, {
    int? sauf,
  }) async {
    final m = matricule.trim();
    if (m.isEmpty) return;
    final existants = await db.query(
      'enseignant',
      columns: ['id', 'matricule'],
      where: 'matricule IS NOT NULL',
    );
    final cible = m.toLowerCase();
    for (final l in existants) {
      if (l['id'] != sauf && (l['matricule'] as String).toLowerCase() == cible) {
        throw ErreurGesco('Le matricule « $m » est déjà utilisé.');
      }
    }
  }
}
