import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../app/services.dart';
import '../data/depots/aides.dart';
import '../data/depots/parametre_depot.dart';
import '../data/erreurs.dart';
import '../data/gesco_database.dart';
import '../domain/permissions.dart';
import 'format_sauvegarde.dart';

/// Origine d'une sauvegarde.
enum TypeSauvegarde {
  manuelle('manuelle', 'Manuelle'),
  automatique('automatique', 'Automatique'),
  securite('securite', 'Avant une restauration'),

  /// Copie du fichier faite par GESCO avant une mise à jour de la base
  /// (pas dans l'historique en base : retrouvée dans le dossier des sauvegardes).
  migration('migration', 'Avant une mise à jour');

  const TypeSauvegarde(this.cle, this.libelle);

  final String cle;
  final String libelle;

  static TypeSauvegarde depuisCle(String cle) =>
      values.firstWhere((t) => t.cle == cle, orElse: () => TypeSauvegarde.manuelle);
}

/// Une ligne de l'historique des sauvegardes.
class Sauvegarde {
  const Sauvegarde({
    this.id,
    required this.chemin,
    required this.taille,
    required this.creeLe,
    required this.type,
    required this.verifiee,
    this.utilisateur = '',
    this.existe = true,
  });

  final int? id;
  final String chemin;
  final int taille;
  final DateTime creeLe;
  final TypeSauvegarde type;

  /// Le fichier a été relu et contrôlé après son écriture.
  final bool verifiee;
  final String utilisateur;

  /// Le fichier est toujours à l'endroit indiqué (une clé USB peut avoir été retirée).
  final bool existe;

  String get nom => p.basename(chemin);
}

/// Réglages des sauvegardes automatiques.
class ConfigSauvegarde {
  const ConfigSauvegarde({
    this.auto = true,
    this.heure = 18,
    this.minute = 0,
    this.conserver = 7,
    this.dossierExterne = '',
  });

  final bool auto;
  final int heure;
  final int minute;

  /// Nombre de sauvegardes automatiques valides conservées.
  final int conserver;

  /// Dossier d'une clé USB ou d'un disque externe où copier aussi chaque
  /// sauvegarde automatique (vide : aucune copie).
  final String dossierExterne;

  String get heureTexte =>
      '${heure.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  ConfigSauvegarde copie({
    bool? auto,
    int? heure,
    int? minute,
    int? conserver,
    String? dossierExterne,
  }) =>
      ConfigSauvegarde(
        auto: auto ?? this.auto,
        heure: heure ?? this.heure,
        minute: minute ?? this.minute,
        conserver: conserver ?? this.conserver,
        dossierExterne: dossierExterne ?? this.dossierExterne,
      );
}

/// Ce qu'on lit dans une base : version du schéma, contenu, état de santé.
class ResumeBase {
  const ResumeBase({
    required this.versionSchema,
    required this.contenu,
    required this.etablissement,
    required this.annee,
    this.problemes = const [],
  });

  final int versionSchema;
  final Map<String, int> contenu;
  final String etablissement;
  final String annee;
  final List<String> problemes;
}

/// Résultat du contrôle d'un fichier de sauvegarde.
class ResultatVerification {
  const ResultatVerification({
    required this.chemin,
    this.manifeste,
    this.base,
    this.problemes = const [],
  });

  final String chemin;
  final ManifesteSauvegarde? manifeste;
  final ResumeBase? base;
  final List<String> problemes;

  bool get valide => problemes.isEmpty && manifeste != null;
}

/// Ce que l'utilisateur voit avant de confirmer une restauration.
class ApercuRestauration {
  const ApercuRestauration({
    required this.verification,
    required this.actuelle,
    this.avertissements = const [],
  });

  final ResultatVerification verification;
  final ResumeBase actuelle;
  final List<String> avertissements;

  bool get possible => verification.valide;
}

/// Les neuf étapes d'une restauration, telles qu'elles sont affichées.
enum EtapeRestauration {
  choix(1, 'Choisir la sauvegarde'),
  verification(2, 'Vérifier le fichier'),
  comparaison(3, 'Comparer avec les données actuelles'),
  confirmation(4, 'Confirmer la restauration'),
  securite(5, 'Sauvegarde de sécurité des données actuelles'),
  remplacement(6, 'Remplacement des données'),
  reouverture(7, 'Réouverture de la base'),
  controle(8, 'Contrôle des données restaurées'),
  termine(9, 'Terminé');

  const EtapeRestauration(this.numero, this.libelle);

  final int numero;
  final String libelle;
}

class ResultatSauvegarde {
  const ResultatSauvegarde(this.sauvegarde, {this.copieExterne, this.avertissement});

  final Sauvegarde sauvegarde;

  /// Chemin de la copie faite dans le dossier externe, s'il y en a une.
  final String? copieExterne;

  /// Pourquoi une copie demandée n'a pas pu être faite (la sauvegarde, elle, est valide).
  final String? avertissement;
}

class ResultatRestauration {
  const ResultatRestauration({
    required this.reussie,
    required this.message,
    this.retourArriere = false,
    this.securite,
    this.manifeste,
  });

  final bool reussie;

  /// Vrai si la restauration a échoué et que les données précédentes ont été
  /// remises en place et rouvertes.
  final bool retourArriere;
  final String message;
  final Sauvegarde? securite;
  final ManifesteSauvegarde? manifeste;
}

/// Sauvegarde, vérification, historique et restauration de la base GESCO.
///
/// Une sauvegarde est une archive .zip (voir `docs/FORMAT_SAUVEGARDE.md`) qui
/// contient une copie cohérente de la base, son descriptif et une notice.
/// Elle est relue et contrôlée après son écriture : une sauvegarde qui ne
/// passe pas le contrôle n'est jamais enregistrée dans l'historique.
class ServiceSauvegarde {
  ServiceSauvegarde(
    this.services, {
    required this.fabrique,
    required this.cheminBase,
    String? dossier,
    DateTime Function()? maintenant,
    this.versionApplication = versionApplicationGesco,
  })  : dossierInterne = dossier ?? p.join(p.dirname(cheminBase), 'sauvegardes'),
        _maintenant = maintenant ?? DateTime.now;

  final Services services;

  /// Fabrique SQLite (FFI sur ordinateur) servant à contrôler les copies.
  final DatabaseFactory fabrique;

  /// Fichier de la base en cours d'utilisation.
  final String cheminBase;

  /// Dossier où GESCO range ses sauvegardes.
  final String dossierInterne;
  final String versionApplication;
  final DateTime Function() _maintenant;

  Database get _db => services.gdb.db;

  static const List<String> _tablesObligatoires = [
    'etablissement',
    'annee_scolaire',
    'classe',
    'eleve',
    'inscription',
    'note',
  ];

  static const Map<String, String> _compteurs = {
    'eleves': 'eleve',
    'inscriptions': 'inscription',
    'classes': 'classe',
    'matieres': 'matiere_classe',
    'evaluations': 'evaluation',
    'notes': 'note',
    'notes_evaluations': 'evaluation_note',
    'enseignants': 'enseignant',
    'comptes': 'utilisateur',
  };

  // ------------------------------------------------------------ Réglages

  /// Réglages enregistrés (valeurs par défaut tant que rien n'a été choisi).
  Future<ConfigSauvegarde> config() async {
    final pr = services.parametres;
    var heure = 18;
    var minute = 0;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(
      (await pr.lire(CleParametre.sauvegardeHeure)) ?? '',
    );
    if (m != null) {
      final h = int.parse(m.group(1)!);
      final mi = int.parse(m.group(2)!);
      if (h <= 23 && mi <= 59) {
        heure = h;
        minute = mi;
      }
    }
    final conserver = await pr.lireEntier(CleParametre.sauvegardeConserver, 7);
    return ConfigSauvegarde(
      auto: await pr.lireBool(CleParametre.sauvegardeAuto, true),
      heure: heure,
      minute: minute,
      conserver: conserver < 1 || conserver > 60 ? 7 : conserver,
      dossierExterne: (await pr.lire(CleParametre.sauvegardeDossierExterne)) ?? '',
    );
  }

  Future<void> enregistrerConfig(ConfigSauvegarde c) async {
    services.controle.exiger(Permission.sauvegardeGerer, 'modifier les réglages de sauvegarde');
    if (c.heure < 0 || c.heure > 23 || c.minute < 0 || c.minute > 59) {
      throw const ErreurGesco('L\'heure de sauvegarde n\'est pas valide.');
    }
    if (c.conserver < 1 || c.conserver > 60) {
      throw const ErreurGesco('Le nombre de sauvegardes à conserver doit être compris entre 1 et 60.');
    }
    final pr = services.parametres;
    await pr.ecrireBool(CleParametre.sauvegardeAuto, c.auto);
    await pr.ecrire(CleParametre.sauvegardeHeure, c.heureTexte);
    await pr.ecrire(CleParametre.sauvegardeConserver, '${c.conserver}');
    await pr.ecrire(CleParametre.sauvegardeDossierExterne, c.dossierExterne.trim());
    await services.controle.noter(
      'modification',
      'sauvegarde',
      details: 'sauvegarde automatique ${c.auto ? 'à ${c.heureTexte}, ${c.conserver} conservées' : 'désactivée'}',
    );
  }

  // ------------------------------------------------------------ Création

  String get _nomUtilisateur {
    final u = services.session.utilisateur;
    if (u == null) return 'Système';
    return u.nomComplet.trim().isEmpty ? u.identifiant : u.nomComplet;
  }

  /// Sauvegarde demandée par l'utilisateur, dans [destination] (clé USB,
  /// disque externe...) ou, à défaut, dans le dossier de GESCO.
  Future<ResultatSauvegarde> creerManuelle({Directory? destination}) {
    services.controle.exiger(Permission.sauvegardeGerer, 'créer une sauvegarde');
    return _creer(TypeSauvegarde.manuelle, destination: destination, utilisateur: _nomUtilisateur);
  }

  /// Sauvegarde automatique : action du système, sans compte connecté. Copiée
  /// aussi dans le dossier externe des réglages, s'il y en a un.
  Future<ResultatSauvegarde> creerAutomatique() async {
    final c = await config();
    final r = await _creer(TypeSauvegarde.automatique, utilisateur: 'Système');
    await _rotationInterne(c.conserver);
    var externe = r.copieExterne;
    var avertissement = r.avertissement;
    if (c.dossierExterne.isNotEmpty) {
      try {
        final dossier = Directory(c.dossierExterne);
        await dossier.create(recursive: true);
        final copie = File(p.join(dossier.path, r.sauvegarde.nom));
        await File(r.sauvegarde.chemin).copy(copie.path);
        final verif = await verifierFichier(copie.path);
        if (!verif.valide) {
          await _supprimerSiExiste(copie);
          throw ErreurGesco(verif.problemes.join(' ; '));
        }
        externe = copie.path;
        await _rotationExterne(dossier, c.conserver);
      } catch (e) {
        avertissement = 'La copie vers « ${c.dossierExterne} » a échoué : $e';
      }
    }
    return ResultatSauvegarde(r.sauvegarde, copieExterne: externe, avertissement: avertissement);
  }

  // -------------------------------------------------------- Planification

  /// Dernier moment où une sauvegarde automatique aurait dû avoir lieu : l'heure
  /// choisie, aujourd'hui si elle est passée, sinon hier.
  static DateTime derniereEcheance(DateTime maintenant, int heure, int minute) {
    final aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day, heure, minute);
    return maintenant.isBefore(aujourdhui)
        ? DateTime(maintenant.year, maintenant.month, maintenant.day - 1, heure, minute)
        : aujourdhui;
  }

  /// Une sauvegarde automatique est due si elles sont activées et qu'aucune
  /// sauvegarde automatique valide n'a été faite depuis la dernière échéance.
  /// C'est aussi le cas au démarrage de GESCO après un jour où l'ordinateur
  /// était éteint : la sauvegarde manquée est rattrapée.
  Future<bool> sauvegardeDue() async {
    final c = await config();
    if (!c.auto) return false;
    final derniere = await derniereAutomatique();
    if (derniere == null) return true;
    final echeance = derniereEcheance(_maintenant(), c.heure, c.minute);
    return derniere.creeLe.isBefore(echeance);
  }

  /// Fait la sauvegarde automatique si elle est due (null sinon).
  Future<ResultatSauvegarde?> executerSiDue() async {
    if (!await sauvegardeDue()) return null;
    return creerAutomatique();
  }

  String _nomArchive(DateTime d, TypeSauvegarde type) {
    String d2(int n) => n.toString().padLeft(2, '0');
    return 'GESCO_sauvegarde_${d.year}-${d2(d.month)}-${d2(d.day)}_'
        '${d2(d.hour)}${d2(d.minute)}${d2(d.second)}_${type.cle}.zip';
  }

  File _fichierLibre(Directory dossier, String nom) {
    var f = File(p.join(dossier.path, nom));
    var n = 2;
    while (f.existsSync()) {
      f = File(p.join(dossier.path, '${p.basenameWithoutExtension(nom)}_$n.zip'));
      n++;
    }
    return f;
  }

  Future<void> _supprimerSiExiste(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // Un fichier déjà ouvert ailleurs : on le laisse, sans bloquer.
    }
  }

  Future<ResultatSauvegarde> _creer(
    TypeSauvegarde type, {
    Directory? destination,
    required String utilisateur,
  }) async {
    final interne = Directory(dossierInterne);
    try {
      await interne.create(recursive: true);
    } on FileSystemException catch (e) {
      throw ErreurGesco(
        'Le dossier des sauvegardes de GESCO (« ${interne.path} ») n\'est pas accessible '
        '(${e.osError?.message ?? e.message}).',
      );
    }
    final dossier = destination ?? interne;
    try {
      await dossier.create(recursive: true);
    } on FileSystemException catch (e) {
      throw ErreurGesco(
        'Le dossier « ${dossier.path} » n\'est pas accessible (${e.osError?.message ?? e.message}). '
        'Vérifiez que la clé USB ou le disque est branché.',
      );
    }
    final instant = _maintenant();
    final copie = File(p.join(interne.path, '.copie_${instant.microsecondsSinceEpoch}.db'));
    try {
      // VACUUM INTO produit une copie cohérente de la base, même si elle est
      // en cours d'utilisation, sans la fermer.
      await _db.execute("VACUUM INTO '${copie.path.replaceAll("'", "''")}'");
      final resume = await _resumerFichier(copie.path);
      if (resume.problemes.isNotEmpty) {
        throw ErreurGesco(
          'La copie de la base n\'est pas valide (${resume.problemes.take(3).join(' ; ')}). '
          'Aucune sauvegarde n\'a été enregistrée.',
        );
      }
      final base = await copie.readAsBytes();
      final manifeste = ManifesteSauvegarde(
        versionSchema: resume.versionSchema,
        versionApplication: versionApplication,
        creeLe: horodatage(instant),
        type: type.cle,
        utilisateur: utilisateur,
        etablissement: resume.etablissement,
        annee: resume.annee,
        contenu: resume.contenu,
        sha256: empreinte(base),
        taille: base.length,
      );
      final archive = construireArchive(base, manifeste, date: instant);
      final finale = _fichierLibre(dossier, _nomArchive(instant, type));
      final partiel = File('${finale.path}.partiel');
      await partiel.writeAsBytes(archive, flush: true);
      await partiel.rename(finale.path);

      // Relecture : la sauvegarde n'existe que si elle se relit correctement.
      final verif = await verifierFichier(finale.path);
      if (!verif.valide) {
        await _supprimerSiExiste(finale);
        throw ErreurGesco(
          'La sauvegarde écrite n\'a pas passé le contrôle (${verif.problemes.take(3).join(' ; ')}). '
          'Elle a été supprimée.',
        );
      }
      final taille = await finale.length();
      final id = await _db.insert('sauvegarde', {
        'chemin': finale.path,
        'taille': taille,
        'cree_le': horodatage(instant),
        'type': type.cle,
        'verifiee': 1,
        'utilisateur_nom': utilisateur,
      });
      await services.controle.noter(
        'creation',
        'sauvegarde',
        id: id,
        details: '${type.libelle.toLowerCase()} : ${p.basename(finale.path)}',
      );
      return ResultatSauvegarde(
        Sauvegarde(
          id: id,
          chemin: finale.path,
          taille: taille,
          creeLe: instant,
          type: type,
          verifiee: true,
          utilisateur: utilisateur,
        ),
      );
    } on FileSystemException catch (e) {
      throw ErreurGesco(
        'La sauvegarde n\'a pas pu être écrite (${e.osError?.message ?? e.message}). '
        'Vérifiez l\'espace disponible et l\'accès au dossier.',
      );
    } finally {
      await _supprimerSiExiste(copie);
    }
  }

  // ------------------------------------------------------------ Rotation

  Future<void> _rotationInterne(int conserver) async {
    final lignes = await _db.query(
      'sauvegarde',
      where: "type = 'automatique' AND verifiee = 1",
      orderBy: 'cree_le DESC, id DESC',
    );
    for (final l in lignes.skip(conserver)) {
      await _supprimerSiExiste(File(l['chemin'] as String));
      await _db.delete('sauvegarde', where: 'id = ?', whereArgs: [l['id']]);
    }
  }

  Future<void> _rotationExterne(Directory dossier, int conserver) async {
    final motif = RegExp(r'^GESCO_sauvegarde_.*_automatique(_\d+)?\.zip$');
    final fichiers = [
      for (final f in dossier.listSync())
        if (f is File && motif.hasMatch(p.basename(f.path))) f,
    ]..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    for (final f in fichiers.skip(conserver)) {
      await _supprimerSiExiste(f);
    }
  }

  // ---------------------------------------------------------- Historique

  /// Historique, de la plus récente à la plus ancienne : sauvegardes de la
  /// base et copies faites avant une mise à jour de la base.
  Future<List<Sauvegarde>> historique() async {
    services.controle.exiger(Permission.sauvegardeGerer, 'consulter les sauvegardes');
    final lignes = await _db.query('sauvegarde', orderBy: 'cree_le DESC, id DESC');
    final liste = <Sauvegarde>[
      for (final l in lignes)
        Sauvegarde(
          id: l['id'] as int,
          chemin: l['chemin'] as String,
          taille: l['taille'] as int,
          creeLe: DateTime.tryParse(l['cree_le'] as String) ?? DateTime.fromMillisecondsSinceEpoch(0),
          type: TypeSauvegarde.depuisCle(l['type'] as String),
          verifiee: (l['verifiee'] as int) == 1,
          utilisateur: l['utilisateur_nom'] as String,
          existe: File(l['chemin'] as String).existsSync(),
        ),
    ];
    final dossier = Directory(dossierInterne);
    if (dossier.existsSync()) {
      for (final f in dossier.listSync()) {
        if (f is File && p.basename(f.path).startsWith(GescoDatabase.prefixeAvantMiseAJour)) {
          final stat = f.statSync();
          liste.add(Sauvegarde(
            chemin: f.path,
            taille: stat.size,
            creeLe: stat.modified,
            type: TypeSauvegarde.migration,
            verifiee: true,
            utilisateur: 'Système',
          ));
        }
      }
      liste.sort((a, b) => b.creeLe.compareTo(a.creeLe));
    }
    return liste;
  }

  /// Dernière sauvegarde automatique valide dont le fichier existe encore.
  Future<Sauvegarde?> derniereAutomatique() async {
    final lignes = await _db.query(
      'sauvegarde',
      where: "type = 'automatique' AND verifiee = 1",
      orderBy: 'cree_le DESC, id DESC',
    );
    for (final l in lignes) {
      if (File(l['chemin'] as String).existsSync()) {
        return Sauvegarde(
          id: l['id'] as int,
          chemin: l['chemin'] as String,
          taille: l['taille'] as int,
          creeLe: DateTime.parse(l['cree_le'] as String),
          type: TypeSauvegarde.automatique,
          verifiee: true,
          utilisateur: l['utilisateur_nom'] as String,
        );
      }
    }
    return null;
  }

  /// Contrôle de nouveau une sauvegarde de l'historique et met à jour son état.
  Future<ResultatVerification> verifier(Sauvegarde s) async {
    services.controle.exiger(Permission.sauvegardeGerer, 'vérifier une sauvegarde');
    final r = await verifierFichier(s.chemin);
    final id = s.id;
    if (id != null) {
      await _db.update(
        'sauvegarde',
        {'verifiee': r.valide ? 1 : 0},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    return r;
  }

  /// Supprime une sauvegarde : le fichier et sa ligne d'historique.
  Future<void> supprimer(Sauvegarde s) async {
    services.controle.exiger(Permission.sauvegardeGerer, 'supprimer une sauvegarde');
    await _supprimerSiExiste(File(s.chemin));
    final id = s.id;
    if (id != null) await _db.delete('sauvegarde', where: 'id = ?', whereArgs: [id]);
    await services.controle.noter('suppression', 'sauvegarde', id: id, details: s.nom);
  }

  // ---------------------------------------------------------- Vérification

  /// Contrôle complet d'un fichier de sauvegarde, sans rien modifier : archive
  /// lisible, descriptif reconnu, empreinte de la base exacte, base saine,
  /// version compatible avec cette version de GESCO.
  Future<ResultatVerification> verifierFichier(String chemin) async {
    final fichier = File(chemin);
    if (!await fichier.exists()) {
      return ResultatVerification(
        chemin: chemin,
        problemes: ['Le fichier est introuvable : $chemin'],
      );
    }
    final ArchiveLue archive;
    try {
      archive = lireArchive(await fichier.readAsBytes());
    } on ErreurGesco catch (e) {
      return ResultatVerification(chemin: chemin, problemes: [e.message]);
    } on FileSystemException catch (e) {
      return ResultatVerification(
        chemin: chemin,
        problemes: ['Le fichier ne peut pas être lu : ${e.osError?.message ?? e.message}'],
      );
    }
    final problemes = <String>[];
    if (archive.manifeste.versionSchema > GescoDatabase.versionSchema) {
      problemes.add(
        'Cette sauvegarde vient d\'une version plus récente de GESCO (base en version '
        '${archive.manifeste.versionSchema}, cette version gère jusqu\'à '
        '${GescoDatabase.versionSchema}). Installez la dernière version de GESCO.',
      );
    }
    final temporaire = File(p.join(
      Directory.systemTemp.path,
      'gesco_verif_${_maintenant().microsecondsSinceEpoch}.db',
    ));
    ResumeBase? resume;
    try {
      await temporaire.writeAsBytes(archive.base, flush: true);
      resume = await _resumerFichier(temporaire.path);
      problemes.addAll(resume.problemes);
    } on FileSystemException catch (e) {
      problemes.add('Contrôle impossible : ${e.osError?.message ?? e.message}');
    } finally {
      await _supprimerSiExiste(temporaire);
    }
    return ResultatVerification(
      chemin: chemin,
      manifeste: archive.manifeste,
      base: resume,
      problemes: problemes,
    );
  }

  /// Résumé d'un fichier de base : ouvert en lecture seule.
  Future<ResumeBase> _resumerFichier(String chemin) async {
    Database? db;
    try {
      db = await fabrique.openDatabase(
        chemin,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      return await _resumer(db);
    } catch (e) {
      return ResumeBase(
        versionSchema: 0,
        contenu: const {},
        etablissement: '',
        annee: '',
        problemes: ['La base de données ne s\'ouvre pas ($e).'],
      );
    } finally {
      await db?.close();
    }
  }

  Future<ResumeBase> _resumer(Database db) async {
    final problemes = <String>[];
    final version = await db.getVersion();
    for (final l in await db.rawQuery('PRAGMA integrity_check')) {
      final t = l.values.first?.toString() ?? '';
      if (t != 'ok') problemes.add('Intégrité : $t');
    }
    for (final l in await db.rawQuery('PRAGMA foreign_key_check')) {
      problemes.add('Clé étrangère invalide : table ${l['table']}');
    }
    final tables = {
      for (final l in await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
        l['name'] as String,
    };
    for (final t in _tablesObligatoires) {
      if (!tables.contains(t)) problemes.add('Table « $t » absente : ce n\'est pas une base GESCO.');
    }
    final contenu = <String, int>{};
    for (final e in _compteurs.entries) {
      if (tables.contains(e.value)) {
        final l = await db.rawQuery('SELECT COUNT(*) AS n FROM ${e.value}');
        contenu[e.key] = (l.first['n'] as int?) ?? 0;
      }
    }
    var etablissement = '';
    var annee = '';
    if (tables.contains('etablissement')) {
      final l = await db.rawQuery('SELECT nom FROM etablissement WHERE id = 1');
      if (l.isNotEmpty) etablissement = '${l.first['nom'] ?? ''}';
    }
    if (tables.contains('annee_scolaire')) {
      final l = await db.rawQuery('SELECT libelle FROM annee_scolaire WHERE active = 1');
      if (l.isNotEmpty) annee = '${l.first['libelle'] ?? ''}';
    }
    return ResumeBase(
      versionSchema: version,
      contenu: contenu,
      etablissement: etablissement,
      annee: annee,
      problemes: problemes,
    );
  }

  /// Résumé des données actuelles (pour les comparer à une sauvegarde).
  Future<ResumeBase> resumeActuel() => _resumer(_db);

  // ----------------------------------------------------------- Restauration

  /// Étapes 2 et 3 : contrôle du fichier choisi et comparaison avec les
  /// données actuelles. Ne modifie rien.
  Future<ApercuRestauration> preparerRestauration(String chemin) async {
    services.controle.exiger(Permission.sauvegardeRestaurer, 'restaurer une sauvegarde');
    final verification = await verifierFichier(chemin);
    final actuelle = await resumeActuel();
    final avertissements = <String>[];
    final m = verification.manifeste;
    if (verification.valide && m != null) {
      final date = m.date;
      if (date != null) {
        final jours = _maintenant().difference(date).inDays;
        if (jours >= 1) {
          avertissements.add(
            'Cette sauvegarde a $jours jour${jours > 1 ? 's' : ''} : '
            'tout ce qui a été saisi depuis sera perdu.',
          );
        }
      }
      final notesActuelles = (actuelle.contenu['notes'] ?? 0) + (actuelle.contenu['notes_evaluations'] ?? 0);
      final notesSauvegarde = (m.contenu['notes'] ?? 0) + (m.contenu['notes_evaluations'] ?? 0);
      if (notesActuelles > notesSauvegarde) {
        avertissements.add(
          'Les données actuelles contiennent ${notesActuelles - notesSauvegarde} note(s) de plus '
          'que la sauvegarde.',
        );
      }
      if (m.versionSchema < GescoDatabase.versionSchema) {
        avertissements.add(
          'Cette sauvegarde vient d\'une version plus ancienne de GESCO : la base sera mise à '
          'jour automatiquement après la restauration.',
        );
      }
    }
    return ApercuRestauration(
      verification: verification,
      actuelle: actuelle,
      avertissements: avertissements,
    );
  }

  Future<void> _supprimerAnnexes(String chemin) async {
    for (final suffixe in ['-wal', '-shm', '-journal']) {
      await _supprimerSiExiste(File('$chemin$suffixe'));
    }
  }

  /// Étapes 5 à 9 : sauvegarde de sécurité, remplacement de la base,
  /// réouverture, contrôle. Si quelque chose échoue après le remplacement,
  /// les données précédentes sont remises en place et rouvertes.
  ///
  /// [fermerBase] doit fermer la base ouverte (et arrêter ce qui l'utilise) ;
  /// [ouvrirBase] doit la rouvrir depuis [cheminBase] et conserver la
  /// nouvelle connexion : après la restauration, cet objet ne doit plus être
  /// utilisé, l'application repart de la base rouverte.
  ///
  /// Une [ErreurGesco] est levée, sans que rien ne soit modifié, si le fichier
  /// est refusé ou si la sauvegarde de sécurité échoue.
  Future<ResultatRestauration> restaurer(
    String chemin, {
    required Future<void> Function() fermerBase,
    required Future<GescoDatabase> Function() ouvrirBase,
    void Function(EtapeRestauration etape)? progression,
  }) async {
    services.controle.exiger(Permission.sauvegardeRestaurer, 'restaurer une sauvegarde');
    final utilisateur = _nomUtilisateur;

    // Étape 2 : le fichier, relu entièrement.
    progression?.call(EtapeRestauration.verification);
    final fichier = File(chemin);
    if (!await fichier.exists()) {
      throw ErreurGesco('Le fichier de sauvegarde est introuvable : $chemin');
    }
    final ArchiveLue archive = lireArchive(await fichier.readAsBytes());
    if (archive.manifeste.versionSchema > GescoDatabase.versionSchema) {
      throw const ErreurGesco(
        'Cette sauvegarde vient d\'une version plus récente de GESCO : installez la dernière '
        'version de GESCO pour la restaurer.',
      );
    }
    final restauree = File('$cheminBase.restauration');
    await _supprimerSiExiste(restauree);
    await restauree.writeAsBytes(archive.base, flush: true);
    final resume = await _resumerFichier(restauree.path);
    if (resume.problemes.isNotEmpty) {
      await _supprimerSiExiste(restauree);
      throw ErreurGesco(
        'La base de cette sauvegarde est abîmée (${resume.problemes.take(3).join(' ; ')}). '
        'Rien n\'a été modifié.',
      );
    }

    // Étape 5 : les données actuelles sont sauvegardées avant d'être remplacées.
    progression?.call(EtapeRestauration.securite);
    final Sauvegarde securite;
    try {
      securite = (await _creer(TypeSauvegarde.securite, utilisateur: utilisateur)).sauvegarde;
    } catch (e) {
      await _supprimerSiExiste(restauree);
      final message = e is ErreurGesco ? e.message : '$e';
      throw ErreurGesco(
        'La sauvegarde de sécurité des données actuelles a échoué ($message). '
        'La restauration est annulée : rien n\'a été modifié.',
      );
    }

    // Étape 6 : remplacement du fichier de la base.
    progression?.call(EtapeRestauration.remplacement);
    try {
      await fermerBase();
    } catch (e) {
      await _supprimerSiExiste(restauree);
      throw ErreurGesco('La base n\'a pas pu être fermée ($e) : rien n\'a été modifié.');
    }
    final base = File(cheminBase);
    final ancienne = File('$cheminBase.avant-restauration');
    var ancienneEcartee = false;
    GescoDatabase? ouverte;
    Object? echec;
    try {
      await _supprimerAnnexes(cheminBase);
      await _supprimerSiExiste(ancienne);
      await base.rename(ancienne.path);
      ancienneEcartee = true;
      await restauree.rename(cheminBase);

      // Étapes 7 et 8 : réouverture (mises à jour de la base comprises) et contrôle.
      progression?.call(EtapeRestauration.reouverture);
      ouverte = await ouvrirBase();
      progression?.call(EtapeRestauration.controle);
      final problemes = await ouverte.verifierIntegrite();
      if (problemes.isNotEmpty) {
        throw ErreurGesco('contrôle des données restaurées : ${problemes.take(3).join(' ; ')}');
      }
      final apres = await _resumer(ouverte.db);
      if (apres.problemes.isNotEmpty) {
        throw ErreurGesco('contrôle des données restaurées : ${apres.problemes.take(3).join(' ; ')}');
      }
      await _noterRestauration(ouverte.db, securite, archive.manifeste, utilisateur);
    } catch (e) {
      echec = e;
    }

    if (echec == null) {
      await _supprimerSiExiste(ancienne);
      progression?.call(EtapeRestauration.termine);
      return ResultatRestauration(
        reussie: true,
        message: 'La sauvegarde du ${archive.manifeste.creeLe.replaceFirst('T', ' à ')} a été '
            'restaurée. Reconnectez-vous : les comptes sont ceux de la sauvegarde.',
        securite: securite,
        manifeste: archive.manifeste,
      );
    }

    // Retour arrière : les données d'avant sont remises en place, puis rouvertes.
    String? grave;
    var remises = !ancienneEcartee; // les données d'avant sont-elles à leur place ?
    try {
      if (ouverte != null) {
        try {
          await ouverte.fermer();
        } catch (_) {
          // Déjà fermée.
        }
      }
      if (ancienneEcartee) {
        await _supprimerAnnexes(cheminBase);
        await _supprimerSiExiste(base);
        await ancienne.rename(cheminBase);
        remises = true;
      }
      await _supprimerSiExiste(restauree);
    } catch (e2) {
      grave = '$e2';
    }
    if (grave == null) {
      try {
        await ouvrirBase();
      } catch (e3) {
        grave = 'réouverture impossible : $e3';
      }
    }
    final cause = echec is ErreurGesco ? echec.message : '$echec';
    if (grave == null) {
      return ResultatRestauration(
        reussie: false,
        retourArriere: true,
        message: 'La restauration a échoué ($cause). Vos données précédentes ont été remises en '
            'place : rien n\'a changé.',
        securite: securite,
        manifeste: archive.manifeste,
      );
    }
    final ou = remises ? cheminBase : ancienne.path;
    return ResultatRestauration(
      reussie: false,
      message: 'La restauration a échoué ($cause) et les données précédentes n\'ont pas pu être '
          'rouvertes automatiquement ($grave). Elles sont conservées dans « $ou » ; '
          'une sauvegarde de sécurité se trouve aussi dans « ${securite.chemin} ».',
      securite: securite,
      manifeste: archive.manifeste,
    );
  }

  Future<void> _noterRestauration(
    Database db,
    Sauvegarde securite,
    ManifesteSauvegarde manifeste,
    String utilisateur,
  ) async {
    final instant = horodatage(_maintenant());
    // La sauvegarde de sécurité a été enregistrée dans la base d'avant : on
    // l'ajoute à l'historique de la base restaurée, pour qu'elle reste visible.
    await db.insert('sauvegarde', {
      'chemin': securite.chemin,
      'taille': securite.taille,
      'cree_le': horodatage(securite.creeLe),
      'type': TypeSauvegarde.securite.cle,
      'verifiee': 1,
      'utilisateur_nom': securite.utilisateur,
    });
    await db.insert('journal', {
      'date_heure': instant,
      'utilisateur_id': null,
      'utilisateur_nom': utilisateur,
      'action': 'restauration',
      'entite': 'sauvegarde',
      'entite_id': null,
      'details': 'sauvegarde du ${manifeste.creeLe} restaurée ; données précédentes copiées dans '
          '${p.basename(securite.chemin)}',
    });
  }
}
