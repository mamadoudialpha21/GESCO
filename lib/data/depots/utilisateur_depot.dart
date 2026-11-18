import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/mot_de_passe.dart';
import '../../domain/permissions.dart';
import '../controle.dart';
import '../erreurs.dart';
import '../modeles_securite.dart';
import '../securite.dart';
import 'aides.dart';
import 'parametre_depot.dart';

/// Comptes utilisateurs : création, connexion sécurisée, mots de passe,
/// verrouillage après échecs, code de récupération.
class UtilisateurDepot {
  UtilisateurDepot(
    this._db, {
    DateTime Function()? maintenant,
    this.iterations = Hachage.iterationsParDefaut,
    this.controle = Controle.aucun,
  })  : _maintenant = maintenant ?? DateTime.now,
        _parametres = ParametreDepot(_db);

  final Database _db;
  final DateTime Function() _maintenant;
  final ParametreDepot _parametres;

  /// Contrôle d'accès : seuls les comptes autorisés gèrent les comptes.
  final Controle controle;

  /// Itérations PBKDF2 pour les nouveaux mots de passe (les tests en utilisent
  /// très peu pour aller vite).
  final int iterations;

  /// Échecs de connexion successifs avant verrouillage du compte.
  static const int echecsMax = 5;
  static const Duration dureeVerrou = Duration(minutes: 5);
  static const Duration dureeVerrouRecuperation = Duration(minutes: 15);

  static const String messageIdentifiantsIncorrects =
      'Identifiant ou mot de passe incorrect.';

  // ------------------------------------------------------------- Lecture

  Future<int> compter() async {
    final l = await _db.rawQuery('SELECT COUNT(*) AS n FROM utilisateur');
    return l.first['n'] as int;
  }

  Future<bool> aucunUtilisateur() async => await compter() == 0;

  Future<List<Utilisateur>> lister() async {
    final l = await _db.query('utilisateur', orderBy: 'identifiant COLLATE NOCASE');
    return [for (final r in l) _depuis(r)];
  }

  Future<Utilisateur?> obtenir(int id) async {
    final l = await _db.query('utilisateur', where: 'id = ?', whereArgs: [id]);
    return l.isEmpty ? null : _depuis(l.first);
  }

  Future<Utilisateur?> parIdentifiant(String identifiant) async {
    final l = await _db.query(
      'utilisateur',
      where: 'identifiant = ?',
      whereArgs: [identifiant.trim()],
    );
    return l.isEmpty ? null : _depuis(l.first);
  }

  Utilisateur _depuis(Map<String, Object?> l) {
    Set<Permission>? permissions;
    final texte = l['permissions'] as String?;
    if (texte != null) {
      try {
        permissions = {
          for (final c in jsonDecode(texte) as List)
            if (Permission.depuisCle(c as String) != null) Permission.depuisCle(c)!,
        };
      } catch (_) {
        // Liste illisible : on retombe sur les permissions du rôle.
        permissions = null;
      }
    }
    return Utilisateur(
      id: l['id'] as int,
      identifiant: l['identifiant'] as String,
      nomComplet: l['nom_complet'] as String,
      role: RoleUtilisateurInfo.depuisCle(l['role'] as String),
      actif: (l['actif'] as int) == 1,
      creeLe: l['cree_le'] as String,
      permissionsPersonnalisees: permissions,
      enseignantId: l['enseignant_id'] as int?,
      doitChangerMotDePasse: (l['doit_changer_mdp'] as int) == 1,
      derniereConnexion: l['derniere_connexion'] as String?,
      verrouilleJusqua: l['verrouille_jusqua'] as String?,
    );
  }

  // ------------------------------------------------------------ Création

  /// Crée le tout premier compte (administrateur) d'une installation.
  /// Retourne aussi le code de récupération, à montrer une seule fois.
  Future<({Utilisateur utilisateur, String codeRecuperation})>
      creerPremierAdministrateur({
    required String identifiant,
    String nomComplet = '',
    required String motDePasse,
  }) async {
    if (await compter() > 0) {
      throw const ErreurGesco(
        'Un compte existe déjà : la création du premier administrateur '
        'n\'est plus possible.',
      );
    }
    final u = await _inserer(
      identifiant: identifiant,
      nomComplet: nomComplet,
      role: RoleUtilisateur.administrateur,
      motDePasse: motDePasse,
      doitChanger: false,
    );
    final code = await _definirCodeRecuperation();
    await _noterConnexion(u.id, u.identifiant, 'creation_compte', 'Premier administrateur');
    return (utilisateur: u, codeRecuperation: code);
  }

  /// Crée un compte. Par défaut, l'utilisateur devra changer son mot de passe
  /// à la première connexion.
  Future<Utilisateur> creer({
    required String identifiant,
    String nomComplet = '',
    required RoleUtilisateur role,
    required String motDePasse,
    int? enseignantId,
    Set<Permission>? permissions,
    bool doitChanger = true,
  }) async {
    controle.exiger(Permission.utilisateursGerer, 'créer un compte');
    final u = await _inserer(
      identifiant: identifiant,
      nomComplet: nomComplet,
      role: role,
      motDePasse: motDePasse,
      enseignantId: enseignantId,
      permissions: permissions,
      doitChanger: doitChanger,
    );
    await _noterConnexion(u.id, u.identifiant, 'creation_compte', role.libelle);
    await controle.noter('creation', 'utilisateur', id: u.id, details: '${u.identifiant} (${role.libelle})');
    return u;
  }

  Future<Utilisateur> _inserer({
    required String identifiant,
    required String nomComplet,
    required RoleUtilisateur role,
    required String motDePasse,
    int? enseignantId,
    Set<Permission>? permissions,
    required bool doitChanger,
  }) async {
    final erreur = validerIdentifiant(identifiant) ??
        validerMotDePasse(motDePasse, identifiant: identifiant);
    if (erreur != null) throw ErreurGesco(erreur);
    if (nomComplet.trim().length > 80) {
      throw const ErreurGesco('Le nom complet est trop long (80 caractères au maximum).');
    }
    final sel = Hachage.genererSel();
    final id = identifiant.trim();
    try {
      final nouveau = await _db.insert('utilisateur', {
        'identifiant': id,
        'nom_complet': nomComplet.trim(),
        'role': role.cle,
        'mot_de_passe_hash': Hachage.hacher(motDePasse, sel, iterations),
        'sel': sel,
        'iterations': iterations,
        'actif': 1,
        'permissions': role == RoleUtilisateur.administrateur
            ? null
            : _encoderPermissions(permissions),
        'enseignant_id': enseignantId,
        'doit_changer_mdp': doitChanger ? 1 : 0,
        'cree_le': horodatage(_maintenant()),
      });
      return (await obtenir(nouveau))!;
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw const ErreurGesco('Cet identifiant est déjà utilisé.');
      }
      rethrow;
    }
  }

  String? _encoderPermissions(Set<Permission>? permissions) => permissions == null
      ? null
      : jsonEncode([for (final p in permissions) p.cle]..sort());

  // ---------------------------------------------------------- Modification

  /// Met à jour le profil d'un compte. [permissions] null = permissions du
  /// rôle. Refuse de retirer le dernier administrateur actif.
  Future<void> modifierProfil(
    int id, {
    required String nomComplet,
    required RoleUtilisateur role,
    int? enseignantId,
    Set<Permission>? permissions,
  }) async {
    controle.exiger(Permission.utilisateursGerer, 'modifier un compte');
    if (nomComplet.trim().length > 80) {
      throw const ErreurGesco('Le nom complet est trop long (80 caractères au maximum).');
    }
    final actuel = await obtenir(id);
    if (actuel == null) throw const ErreurGesco('Ce compte n\'existe plus.');
    if (actuel.role == RoleUtilisateur.administrateur &&
        role != RoleUtilisateur.administrateur &&
        actuel.actif) {
      await _garderUnAdministrateur(_db, id);
    }
    await _db.update(
      'utilisateur',
      {
        'nom_complet': nomComplet.trim(),
        'role': role.cle,
        'enseignant_id': enseignantId,
        'permissions': role == RoleUtilisateur.administrateur
            ? null
            : _encoderPermissions(permissions),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await controle.noter(
      'modification',
      'utilisateur',
      id: id,
      details: '${actuel.identifiant} : ${role.libelle}'
          '${permissions == null ? '' : ' (permissions personnalisées)'}',
    );
  }

  /// Active ou désactive un compte. Le dernier administrateur actif ne peut
  /// pas être désactivé.
  Future<void> definirActif(int id, bool actif) async {
    controle.exiger(Permission.utilisateursGerer, 'activer ou désactiver un compte');
    final u = await obtenir(id);
    if (u == null) throw const ErreurGesco('Ce compte n\'existe plus.');
    if (!actif && u.actif && u.role == RoleUtilisateur.administrateur) {
      await _garderUnAdministrateur(_db, id);
    }
    await _db.update(
      'utilisateur',
      {
        'actif': actif ? 1 : 0,
        if (actif) 'echecs_connexion': 0,
        if (actif) 'verrouille_jusqua': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _noterConnexion(
      id,
      u.identifiant,
      actif ? 'compte_active' : 'compte_desactive',
    );
    await controle.noter(
      actif ? 'activation' : 'desactivation',
      'utilisateur',
      id: id,
      details: u.identifiant,
    );
  }

  /// Supprime un compte (l'historique garde le nom de son auteur). Refuse la
  /// suppression de son propre compte et du dernier administrateur actif.
  Future<void> supprimer(int id, {int? parId}) async {
    controle.exiger(Permission.utilisateursGerer, 'supprimer un compte');
    final u = await obtenir(id);
    if (u == null) return;
    if (parId == id) {
      throw const ErreurGesco('Vous ne pouvez pas supprimer votre propre compte.');
    }
    if (u.role == RoleUtilisateur.administrateur && u.actif) {
      await _garderUnAdministrateur(_db, id);
    }
    await _db.delete('utilisateur', where: 'id = ?', whereArgs: [id]);
    await _noterConnexion(null, u.identifiant, 'compte_supprime');
    await controle.noter('suppression', 'utilisateur', id: id, details: u.identifiant);
  }

  Future<void> _garderUnAdministrateur(DatabaseExecutor db, int idExclu) async {
    final l = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM utilisateur '
      "WHERE role = 'administrateur' AND actif = 1 AND id <> ?",
      [idExclu],
    );
    if ((l.first['n'] as int) == 0) {
      throw const ErreurGesco(
        'Il doit toujours rester au moins un administrateur actif.',
      );
    }
  }

  // -------------------------------------------------------- Mots de passe

  /// Un administrateur donne un nouveau mot de passe à un compte ; il devra
  /// le changer à sa prochaine connexion (sauf si [doitChanger] est faux).
  Future<void> reinitialiserMotDePasse(
    int id,
    String nouveau, {
    bool doitChanger = true,
  }) async {
    controle.exiger(Permission.utilisateursGerer, 'réinitialiser un mot de passe');
    final u = await obtenir(id);
    if (u == null) throw const ErreurGesco('Ce compte n\'existe plus.');
    final erreur = validerMotDePasse(nouveau, identifiant: u.identifiant);
    if (erreur != null) throw ErreurGesco(erreur);
    await _ecrireMotDePasse(id, nouveau, doitChanger: doitChanger);
    await _noterConnexion(id, u.identifiant, 'mot_de_passe_reinitialise');
    await controle.noter('reinitialisation_mdp', 'utilisateur', id: id, details: u.identifiant);
  }

  /// L'utilisateur change son propre mot de passe.
  Future<void> changerMotDePasse(
    int id, {
    required String ancien,
    required String nouveau,
  }) async {
    final l = await _db.query('utilisateur', where: 'id = ?', whereArgs: [id]);
    if (l.isEmpty) throw const ErreurGesco('Ce compte n\'existe plus.');
    final u = _depuis(l.first);
    final ok = Hachage.verifier(
      ancien,
      hash: l.first['mot_de_passe_hash'] as String,
      sel: l.first['sel'] as String,
      iterations: l.first['iterations'] as int,
    );
    if (!ok) throw const ErreurGesco('Le mot de passe actuel est incorrect.');
    if (nouveau == ancien) {
      throw const ErreurGesco(
        'Le nouveau mot de passe doit être différent de l\'ancien.',
      );
    }
    final erreur = validerMotDePasse(nouveau, identifiant: u.identifiant);
    if (erreur != null) throw ErreurGesco(erreur);
    await _ecrireMotDePasse(id, nouveau, doitChanger: false);
    await _noterConnexion(id, u.identifiant, 'mot_de_passe_change');
  }

  Future<void> _ecrireMotDePasse(
    int id,
    String motDePasse, {
    required bool doitChanger,
  }) async {
    final sel = Hachage.genererSel();
    await _db.update(
      'utilisateur',
      {
        'mot_de_passe_hash': Hachage.hacher(motDePasse, sel, iterations),
        'sel': sel,
        'iterations': iterations,
        'doit_changer_mdp': doitChanger ? 1 : 0,
        'echecs_connexion': 0,
        'verrouille_jusqua': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ------------------------------------------------------------ Connexion

  /// Vérifie les identifiants et ouvre la session. Lève une [ErreurGesco] au
  /// message clair en cas d'échec ; chaque tentative est journalisée.
  Future<Utilisateur> authentifier(String identifiant, String motDePasse) async {
    final saisi = identifiant.trim();
    final l = await _db.query('utilisateur', where: 'identifiant = ?', whereArgs: [saisi]);
    if (l.isEmpty) {
      // Même durée de calcul que pour un compte existant.
      Hachage.hacher(motDePasse, Hachage.genererSel(), iterations);
      await _noterConnexion(null, saisi, 'echec', 'Identifiant inconnu');
      throw const ErreurGesco(messageIdentifiantsIncorrects);
    }
    final ligne = l.first;
    final u = _depuis(ligne);
    final maintenant = _maintenant();

    final verrou = DateTime.tryParse(u.verrouilleJusqua ?? '');
    if (verrou != null && verrou.isAfter(maintenant)) {
      await _noterConnexion(u.id, u.identifiant, 'refus_verrou');
      throw ErreurGesco(
        'Ce compte est verrouillé après plusieurs échecs. '
        'Réessayez à ${_heure(verrou)}.',
      );
    }

    final ok = Hachage.verifier(
      motDePasse,
      hash: ligne['mot_de_passe_hash'] as String,
      sel: ligne['sel'] as String,
      iterations: ligne['iterations'] as int,
    );
    if (!ok) {
      final echecs = (ligne['echecs_connexion'] as int) + 1;
      if (echecs >= echecsMax) {
        final jusqua = maintenant.add(dureeVerrou);
        await _db.update(
          'utilisateur',
          {'echecs_connexion': 0, 'verrouille_jusqua': horodatage(jusqua)},
          where: 'id = ?',
          whereArgs: [u.id],
        );
        await _noterConnexion(u.id, u.identifiant, 'verrouillage', '$echecsMax échecs');
        throw ErreurGesco(
          'Trop d\'échecs : ce compte est verrouillé jusqu\'à ${_heure(jusqua)}.',
        );
      }
      await _db.update(
        'utilisateur',
        {'echecs_connexion': echecs},
        where: 'id = ?',
        whereArgs: [u.id],
      );
      await _noterConnexion(u.id, u.identifiant, 'echec', 'Mot de passe incorrect');
      throw const ErreurGesco(messageIdentifiantsIncorrects);
    }

    if (!u.actif) {
      await _noterConnexion(u.id, u.identifiant, 'refus_inactif');
      throw const ErreurGesco(
        'Ce compte est désactivé. Demandez à un administrateur de le réactiver.',
      );
    }

    await _db.update(
      'utilisateur',
      {
        'echecs_connexion': 0,
        'verrouille_jusqua': null,
        'derniere_connexion': horodatage(maintenant),
      },
      where: 'id = ?',
      whereArgs: [u.id],
    );
    await _noterConnexion(u.id, u.identifiant, 'connexion');
    return (await obtenir(u.id))!;
  }

  /// Journalise la fermeture de session et efface l'utilisateur courant.
  Future<void> enregistrerDeconnexion(Utilisateur u, {bool inactivite = false}) async {
    await _noterConnexion(
      u.id,
      u.identifiant,
      inactivite ? 'deconnexion_inactivite' : 'deconnexion',
    );
    await marquerContexte(null);
  }

  /// Journalise le verrouillage de la session (manuel ou par inactivité) :
  /// personne n'est plus censé agir, l'historique ne signe donc plus.
  Future<void> enregistrerVerrouillage(Utilisateur u, {required bool inactivite}) async {
    await _noterConnexion(
      u.id,
      u.identifiant,
      inactivite ? 'verrouillage_inactivite' : 'verrouillage_manuel',
    );
    await marquerContexte(null);
  }

  /// Indique à la base qui est connecté : l'historique des notes signe ainsi
  /// chaque modification.
  Future<void> marquerContexte(Utilisateur? u) async {
    await _db.update('contexte', {
      'utilisateur_id': u?.id,
      'utilisateur_nom': u?.nomAffiche ?? '',
    });
  }

  String _heure(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _noterConnexion(
    int? utilisateurId,
    String identifiant,
    String evenement, [
    String detail = '',
  ]) async {
    await _db.insert('journal_connexion', {
      'date_heure': horodatage(_maintenant()),
      'utilisateur_id': utilisateurId,
      'identifiant': identifiant,
      'evenement': evenement,
      'detail': detail,
    });
  }

  // ------------------------------------------------- Code de récupération

  /// Génère un nouveau code de récupération (l'ancien devient inutilisable).
  /// À montrer une seule fois à l'administrateur.
  Future<String> nouveauCodeRecuperation() async {
    controle.exiger(
      Permission.utilisateursGerer,
      'générer un code de récupération',
    );
    return _definirCodeRecuperation();
  }

  Future<bool> aUnCodeRecuperation() async =>
      await _parametres.lire(CleParametre.recuperationHash) != null;

  Future<String> _definirCodeRecuperation() async {
    final code = Hachage.genererCodeRecuperation();
    final sel = Hachage.genererSel();
    await _parametres.ecrire(CleParametre.recuperationSel, sel);
    await _parametres.ecrire(CleParametre.recuperationIterations, '$iterations');
    await _parametres.ecrire(
      CleParametre.recuperationHash,
      Hachage.hacher(Hachage.normaliserCode(code), sel, iterations),
    );
    await _parametres.supprimer(CleParametre.recuperationEchecs);
    await _parametres.supprimer(CleParametre.recuperationVerrouJusqua);
    return code;
  }

  /// Redonne accès à un administrateur qui a perdu son mot de passe. Retourne
  /// le nouveau code de récupération (l'ancien est consommé).
  Future<String> reinitialiserParCodeRecuperation({
    required String identifiant,
    required String code,
    required String nouveauMotDePasse,
  }) async {
    final maintenant = _maintenant();
    final verrou = DateTime.tryParse(
      await _parametres.lire(CleParametre.recuperationVerrouJusqua) ?? '',
    );
    if (verrou != null && verrou.isAfter(maintenant)) {
      throw ErreurGesco(
        'Trop d\'essais : la récupération est bloquée jusqu\'à ${_heure(verrou)}.',
      );
    }
    final hash = await _parametres.lire(CleParametre.recuperationHash);
    final sel = await _parametres.lire(CleParametre.recuperationSel);
    if (hash == null || sel == null) {
      throw const ErreurGesco(
        'Aucun code de récupération n\'a été défini pour cette installation.',
      );
    }
    final iter = await _parametres.lireEntier(
      CleParametre.recuperationIterations,
      iterations,
    );
    final ok = Hachage.verifier(
      Hachage.normaliserCode(code),
      hash: hash,
      sel: sel,
      iterations: iter,
    );
    if (!ok) {
      final echecs = await _parametres.lireEntier(CleParametre.recuperationEchecs, 0) + 1;
      if (echecs >= echecsMax) {
        await _parametres.supprimer(CleParametre.recuperationEchecs);
        await _parametres.ecrire(
          CleParametre.recuperationVerrouJusqua,
          horodatage(maintenant.add(dureeVerrouRecuperation)),
        );
      } else {
        await _parametres.ecrire(CleParametre.recuperationEchecs, '$echecs');
      }
      await _noterConnexion(null, identifiant.trim(), 'recuperation_echec');
      throw const ErreurGesco('Code de récupération incorrect.');
    }
    final u = await parIdentifiant(identifiant);
    if (u == null || u.role != RoleUtilisateur.administrateur) {
      throw const ErreurGesco(
        'Cet identifiant n\'existe pas ou n\'est pas celui d\'un administrateur.',
      );
    }
    final erreur = validerMotDePasse(nouveauMotDePasse, identifiant: u.identifiant);
    if (erreur != null) throw ErreurGesco(erreur);
    await _ecrireMotDePasse(u.id, nouveauMotDePasse, doitChanger: false);
    await _db.update('utilisateur', {'actif': 1}, where: 'id = ?', whereArgs: [u.id]);
    await _noterConnexion(u.id, u.identifiant, 'recuperation');
    return _definirCodeRecuperation();
  }
}
