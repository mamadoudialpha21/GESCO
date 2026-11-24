import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/periodes.dart';
import '../../domain/permissions.dart';
import '../../domain/recherche.dart';
import '../controle.dart';
import '../erreurs.dart';
import '../modeles_donnees.dart';
import '../validation_eleve.dart';
import 'aides.dart';

/// Un élève à créer lors d'un import : sa fiche, sa classe et la ligne du
/// fichier d'où il vient (pour les messages d'erreur).
class EleveAImporter {
  const EleveAImporter({required this.eleve, required this.classeId, required this.ligne});

  final Eleve eleve;
  final int classeId;

  /// Numéro de la ligne dans le fichier Excel.
  final int ligne;
}

/// Élèves et inscriptions.
///
/// Les informations personnelles d'un élève sont enregistrées une seule fois
/// et réutilisées chaque année ; l'inscription relie l'élève à une classe pour
/// une année scolaire donnée. Les notes, classements et bulletins s'appuient
/// sur l'inscription.
///
/// Chaque inscription garde son historique (inscription, changement de classe,
/// départ, abandon, reprise) dans les mouvements d'inscription.
class EleveDepot {
  EleveDepot(
    this._db, {
    DateTime Function()? maintenant,
    this.controle = Controle.aucun,
  }) : _maintenant = maintenant ?? DateTime.now;

  final Database _db;
  final DateTime Function() _maintenant;
  final Controle controle;

  static const int longueurMaxMotif = 200;

  /// Élèves inscrits pour l'année, éventuellement dans une seule classe,
  /// triés par nom puis prénom (sans tenir compte des accents ni de la casse).
  /// Les élèves partis ou ayant abandonné restent listés (voir
  /// [EleveInscrit.statut]) ; les dossiers archivés ne le sont que si
  /// [inclureArchives] est vrai.
  Future<List<EleveInscrit>> lister(
    int anneeId, {
    int? classeId,
    bool inclureArchives = false,
  }) async {
    final lignes = await _db.rawQuery(
      '''
      SELECT i.id AS inscription_id, i.eleve_id, i.classe_id, c.nom AS classe_nom,
             i.statut, e.archive,
             e.matricule, e.nom, e.prenom, e.sexe, e.date_naissance
      FROM inscription i
      JOIN eleve e ON e.id = i.eleve_id
      JOIN classe c ON c.id = i.classe_id
      WHERE i.annee_id = ?
        ${classeId == null ? '' : 'AND i.classe_id = ?'}
        ${inclureArchives ? '' : 'AND e.archive = 0'}
      ''',
      [anneeId, if (classeId != null) classeId],
    );
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
          statut: StatutInscription.depuisCle(l['statut'] as String?),
          archive: ((l['archive'] as int?) ?? 0) == 1,
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

  /// Fiches complètes (sans la photo) des élèves inscrits pour l'année, avec
  /// leur inscription : pour les exports Excel. Triées comme [lister]. Les
  /// dossiers archivés sont exclus.
  Future<List<(Eleve, EleveInscrit)>> fichesInscrits(int anneeId) async {
    final lignes = await _db.rawQuery(
      '''
      SELECT e.id, e.matricule, e.nom, e.prenom, e.sexe, e.date_naissance,
             e.lieu_naissance, e.nom_pere, e.nom_mere, e.contact_parent,
             e.adresse, e.telephone, e.nom_tuteur, e.contact_tuteur, e.archive,
             i.id AS inscription_id, i.classe_id, c.nom AS classe_nom, i.statut
      FROM inscription i
      JOIN eleve e ON e.id = i.eleve_id
      JOIN classe c ON c.id = i.classe_id
      WHERE i.annee_id = ? AND e.archive = 0
      ''',
      [anneeId],
    );
    final liste = [
      for (final l in lignes)
        (
          _depuis(l),
          EleveInscrit(
            inscriptionId: l['inscription_id'] as int,
            eleveId: l['id'] as int,
            classeId: l['classe_id'] as int,
            classeNom: l['classe_nom'] as String,
            matricule: l['matricule'] as String,
            nom: l['nom'] as String,
            prenom: l['prenom'] as String,
            sexe: l['sexe'] as String,
            dateNaissance: l['date_naissance'] as String?,
            statut: StatutInscription.depuisCle(l['statut'] as String?),
          ),
        ),
    ];
    liste.sort((a, b) {
      final parNom = normaliserRecherche(a.$1.nom).compareTo(normaliserRecherche(b.$1.nom));
      if (parNom != 0) return parNom;
      final parPrenom =
          normaliserRecherche(a.$1.prenom).compareTo(normaliserRecherche(b.$1.prenom));
      if (parPrenom != 0) return parPrenom;
      return a.$2.inscriptionId.compareTo(b.$2.inscriptionId);
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

  /// Élèves connus (non archivés) qui ne sont pas encore inscrits pour
  /// [anneeId] (par exemple pour les réinscrire à la rentrée suivante).
  /// Sans la photo.
  Future<List<Eleve>> nonInscrits(int anneeId) async {
    final lignes = await _db.rawQuery(
      '''
      SELECT e.id, e.matricule, e.nom, e.prenom, e.sexe, e.date_naissance,
             e.lieu_naissance, e.nom_pere, e.nom_mere, e.contact_parent,
             e.adresse, e.telephone, e.nom_tuteur, e.contact_tuteur, e.archive
      FROM eleve e
      WHERE e.archive = 0 AND NOT EXISTS (
        SELECT 1 FROM inscription i
        WHERE i.eleve_id = e.id AND i.annee_id = ?
      )
      ''',
      [anneeId],
    );
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

  /// Identité de tous les élèves enregistrés, dossiers archivés compris :
  /// sert à repérer les doublons avant un import.
  Future<List<IdentiteEleve>> identites() async {
    final lignes = await _db.query(
      'eleve',
      columns: ['matricule', 'nom', 'prenom', 'date_naissance', 'archive'],
    );
    return [
      for (final l in lignes)
        IdentiteEleve(
          matricule: l['matricule'] as String,
          nom: l['nom'] as String,
          prenom: l['prenom'] as String,
          dateNaissance: l['date_naissance'] as String?,
          archive: ((l['archive'] as int?) ?? 0) == 1,
        ),
    ];
  }

  /// Nombre de notes (mensuelles et d'évaluations) enregistrées pour une
  /// inscription.
  Future<int> compterNotes(int inscriptionId) => _compterNotes(_db, inscriptionId);

  static Future<int> _compterNotes(DatabaseExecutor db, int inscriptionId) async {
    final mensuelles = await compter(
      db,
      'SELECT COUNT(*) FROM note WHERE inscription_id = ?',
      [inscriptionId],
    );
    final evaluations = await compter(
      db,
      'SELECT COUNT(*) FROM evaluation_note WHERE inscription_id = ?',
      [inscriptionId],
    );
    return mensuelles + evaluations;
  }

  /// Inscriptions d'un élève, de la plus récente à la plus ancienne.
  Future<List<InscriptionHistorique>> inscriptionsDeLEleve(int eleveId) async {
    final lignes = await _db.rawQuery(
      '''
      SELECT i.id, i.annee_id, a.libelle AS annee_libelle, i.classe_id,
             c.nom AS classe_nom, i.statut, i.date_inscription, i.date_sortie,
             i.motif_sortie
      FROM inscription i
      JOIN annee_scolaire a ON a.id = i.annee_id
      JOIN classe c ON c.id = i.classe_id
      WHERE i.eleve_id = ?
      ORDER BY a.libelle DESC, i.id DESC
      ''',
      [eleveId],
    );
    return [
      for (final l in lignes)
        InscriptionHistorique(
          inscriptionId: l['id'] as int,
          anneeId: l['annee_id'] as int,
          anneeLibelle: l['annee_libelle'] as String,
          classeId: l['classe_id'] as int,
          classeNom: l['classe_nom'] as String,
          statut: StatutInscription.depuisCle(l['statut'] as String?),
          dateInscription: l['date_inscription'] as String,
          dateSortie: l['date_sortie'] as String?,
          motifSortie: (l['motif_sortie'] as String?) ?? '',
        ),
    ];
  }

  /// Mouvements d'inscription, du plus récent au plus ancien. Filtrable par
  /// élève, par année ou par inscription ; [limite] borne la liste.
  Future<List<MouvementInscription>> mouvements({
    int? eleveId,
    int? anneeId,
    int? inscriptionId,
    int? limite,
  }) async {
    final conditions = <String>[];
    final arguments = <Object?>[];
    if (eleveId != null) {
      conditions.add('i.eleve_id = ?');
      arguments.add(eleveId);
    }
    if (anneeId != null) {
      conditions.add('i.annee_id = ?');
      arguments.add(anneeId);
    }
    if (inscriptionId != null) {
      conditions.add('m.inscription_id = ?');
      arguments.add(inscriptionId);
    }
    final lignes = await _db.rawQuery(
      '''
      SELECT m.id, m.inscription_id, m.type, m.date_mouvement, m.motif,
             m.utilisateur_nom,
             co.nom AS origine_nom, cd.nom AS destination_nom,
             e.nom AS eleve_nom, e.prenom AS eleve_prenom,
             a.libelle AS annee_libelle
      FROM mouvement_inscription m
      JOIN inscription i ON i.id = m.inscription_id
      JOIN eleve e ON e.id = i.eleve_id
      JOIN annee_scolaire a ON a.id = i.annee_id
      LEFT JOIN classe co ON co.id = m.classe_origine_id
      LEFT JOIN classe cd ON cd.id = m.classe_destination_id
      ${conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}'}
      ORDER BY m.date_mouvement DESC, m.id DESC
      ${limite == null ? '' : 'LIMIT $limite'}
      ''',
      arguments,
    );
    return [
      for (final l in lignes)
        MouvementInscription(
          id: l['id'] as int,
          inscriptionId: l['inscription_id'] as int,
          type: l['type'] as String,
          date: l['date_mouvement'] as String,
          classeOrigineNom: (l['origine_nom'] as String?) ?? '',
          classeDestinationNom: (l['destination_nom'] as String?) ?? '',
          motif: (l['motif'] as String?) ?? '',
          utilisateur: (l['utilisateur_nom'] as String?) ?? '',
          eleveNom: '${(l['eleve_nom'] as String).toUpperCase()} ${l['eleve_prenom']}',
          anneeLibelle: l['annee_libelle'] as String,
        ),
    ];
  }

  // ------------------------------------------------------------ Inscription

  /// Crée un nouvel élève et l'inscrit dans [classeId] pour [anneeId].
  /// Retourne l'identifiant de l'inscription. Tout ou rien.
  ///
  /// Si la classe est pleine, lève une [ErreurAConfirmer] ('capacite') sauf
  /// si [depasserCapacite] est vrai.
  Future<int> inscrire(
    Eleve eleve, {
    required int anneeId,
    required int classeId,
    bool depasserCapacite = false,
  }) async {
    controle.exiger(Permission.elevesGerer, 'inscrire un élève');
    _verifier(eleve);
    final id = await _db.transaction<int>((txn) async {
      await _verifierAnneeOuverte(txn, anneeId);
      await _verifierClasse(txn, classeId, anneeId);
      await _verifierCapacite(txn, classeId, depasserCapacite);
      await _verifierMatriculeLibre(txn, eleve.matricule);
      final eleveId = await txn.insert('eleve', _valeurs(eleve));
      return _inscrire(txn, eleveId, classeId, anneeId, 'inscription');
    });
    await controle.noter(
      'inscription',
      'eleve',
      id: id,
      details: '${eleve.nom.trim()} ${eleve.prenom.trim()} (${eleve.matricule.trim()})',
    );
    return id;
  }

  /// Crée tous les élèves de [lot] et les inscrit dans leur classe pour
  /// [anneeId], en une seule transaction : si une seule ligne est refusée,
  /// **rien** n'est enregistré et l'erreur indique la ligne du fichier.
  ///
  /// Chaque fiche passe les mêmes contrôles qu'une inscription manuelle
  /// (champs, matricule libre, classe de l'année, capacité sauf
  /// [depasserCapacite], année non archivée). Retourne le nombre d'élèves créés.
  Future<int> importerLot(
    List<EleveAImporter> lot, {
    required int anneeId,
    bool depasserCapacite = false,
    String source = '',
  }) async {
    controle.exiger(Permission.importExport, 'importer des élèves');
    controle.exiger(Permission.elevesGerer, 'inscrire un élève');
    if (lot.isEmpty) throw const ErreurGesco('Aucun élève à importer.');
    final nb = await _db.transaction<int>((txn) async {
      await _verifierAnneeOuverte(txn, anneeId);
      final pris = {
        for (final l in await txn.query('eleve', columns: ['matricule']))
          (l['matricule'] as String).toLowerCase(),
      };
      final classesVerifiees = <int>{};
      for (final e in lot) {
        try {
          _verifier(e.eleve);
          if (classesVerifiees.add(e.classeId)) {
            await _verifierClasse(txn, e.classeId, anneeId);
          }
          if (!pris.add(e.eleve.matricule.trim().toLowerCase())) {
            throw ErreurGesco('Le matricule « ${e.eleve.matricule.trim()} » est déjà utilisé.');
          }
          await _verifierCapacite(txn, e.classeId, depasserCapacite);
          final eleveId = await txn.insert('eleve', _valeurs(e.eleve));
          await _inscrire(txn, eleveId, e.classeId, anneeId, 'inscription');
        } on ErreurGesco catch (err) {
          throw ErreurGesco(
            'Ligne ${e.ligne} : ${err.message}\nAucun élève n\'a été importé.',
          );
        }
      }
      return lot.length;
    });
    await controle.noter(
      'import_eleves',
      'eleve',
      details: '${pluriel(nb, 'élève')} importé${nb > 1 ? 's' : ''} depuis Excel'
          '${source.isEmpty ? '' : ' ($source)'}',
    );
    return nb;
  }

  /// Inscrit un élève déjà connu (réinscription d'une année à l'autre).
  Future<int> inscrireExistant({
    required int eleveId,
    required int anneeId,
    required int classeId,
    bool depasserCapacite = false,
  }) async {
    controle.exiger(Permission.elevesGerer, 'inscrire un élève');
    final id = await _db.transaction<int>((txn) async {
      final lignes = await txn.query(
        'eleve',
        columns: ['archive'],
        where: 'id = ?',
        whereArgs: [eleveId],
      );
      if (lignes.isEmpty) throw const ErreurGesco('Élève introuvable.');
      if ((lignes.first['archive'] as int? ?? 0) == 1) {
        throw const ErreurGesco(
          'Ce dossier est archivé : désarchivez-le avant de le réinscrire.',
        );
      }
      await _verifierAnneeOuverte(txn, anneeId);
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
      await _verifierCapacite(txn, classeId, depasserCapacite);
      return _inscrire(txn, eleveId, classeId, anneeId, 'reinscription');
    });
    await controle.noter('reinscription', 'eleve', id: id, details: 'élève n° $eleveId');
    return id;
  }

  /// Modifie la fiche d'un élève ([Eleve.id] doit exister). Si
  /// [nouvelleClasseId] est fourni, change aussi sa classe pour l'inscription
  /// [inscriptionId] (refusé si des notes existent déjà : utiliser alors
  /// [transferer]). L'état « archivé » n'est pas modifié ici (voir
  /// [archiver]). Tout ou rien.
  Future<void> modifier(
    Eleve eleve, {
    int? inscriptionId,
    int? nouvelleClasseId,
    bool depasserCapacite = false,
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
        await _changerDeClasse(txn, inscriptionId, nouvelleClasseId, depasserCapacite);
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

  /// Archive (ou désarchive) le dossier d'un élève : il disparaît des listes
  /// courantes, des classements et des statistiques, mais toutes ses données
  /// sont conservées. Refusé tant qu'il suit une classe de l'année active
  /// (enregistrer d'abord son départ).
  Future<void> archiver(int eleveId, {bool archive = true}) async {
    controle.exiger(
      Permission.elevesSupprimer,
      archive ? 'archiver un dossier élève' : 'désarchiver un dossier élève',
    );
    String details = '';
    await _db.transaction<void>((txn) async {
      final lignes = await txn.query('eleve', where: 'id = ?', whereArgs: [eleveId]);
      if (lignes.isEmpty) throw const ErreurGesco('Élève introuvable.');
      final l = lignes.first;
      details = '${l['nom']} ${l['prenom']} (${l['matricule']})';
      if (((l['archive'] as int?) ?? 0) == (archive ? 1 : 0)) return;
      if (archive) {
        final actifs = await compter(
          txn,
          '''
          SELECT COUNT(*) FROM inscription i
          JOIN annee_scolaire a ON a.id = i.annee_id
          WHERE i.eleve_id = ? AND a.active = 1 AND i.statut = 'inscrit'
          ''',
          [eleveId],
        );
        if (actifs > 0) {
          throw const ErreurGesco(
            'Impossible d\'archiver un élève qui suit une classe de l\'année '
            'active : enregistrez d\'abord son départ.',
          );
        }
      }
      await txn.update(
        'eleve',
        {'archive': archive ? 1 : 0},
        where: 'id = ?',
        whereArgs: [eleveId],
      );
    });
    await controle.noter(
      archive ? 'archivage' : 'desarchivage',
      'eleve',
      id: eleveId,
      details: details,
    );
  }

  // ------------------------------------------------- Départ, abandon, reprise

  /// Enregistre le départ ou l'abandon d'un élève en cours d'année. Ses notes
  /// sont conservées, mais il n'apparaît plus dans les classements ni dans
  /// les statistiques et ne compte plus dans l'effectif de la classe.
  Future<void> enregistrerSortie(
    int inscriptionId,
    StatutInscription statut, {
    String motif = '',
    DateTime? date,
  }) async {
    controle.exiger(Permission.elevesGerer, 'enregistrer un départ ou un abandon');
    if (statut == StatutInscription.inscrit) {
      throw const ErreurGesco('Choisissez « départ » ou « abandon ».');
    }
    final motifValide = _motifValide(motif);
    final dateSortie = date ?? _maintenant();
    if (dateSortie.isAfter(_maintenant().add(const Duration(days: 1)))) {
      throw const ErreurGesco('La date de sortie ne peut pas être dans le futur.');
    }
    var details = '';
    await _db.transaction<void>((txn) async {
      final ins = await _inscription(txn, inscriptionId);
      await _verifierAnneeOuverte(txn, ins.anneeId);
      if (ins.statut != StatutInscription.inscrit) {
        throw ErreurGesco(
          'Cet élève est déjà enregistré comme « ${ins.statut.libelle.toLowerCase()} ».',
        );
      }
      details = await _identite(txn, ins.eleveId);
      await txn.update(
        'inscription',
        {
          'statut': statut.cle,
          'date_sortie': horodatage(dateSortie).substring(0, 10),
          'motif_sortie': motifValide.isEmpty ? null : motifValide,
        },
        where: 'id = ?',
        whereArgs: [inscriptionId],
      );
      await _mouvement(
        txn,
        inscriptionId,
        statut.cle,
        origine: ins.classeId,
        motif: motifValide,
      );
    });
    await controle.noter(
      statut == StatutInscription.depart ? 'depart' : 'abandon',
      'eleve',
      id: inscriptionId,
      details: motifValide.isEmpty ? details : '$details — $motifValide',
    );
  }

  /// Remet un élève parti ou ayant abandonné dans sa classe.
  Future<void> reprendre(
    int inscriptionId, {
    String motif = '',
    bool depasserCapacite = false,
  }) async {
    controle.exiger(Permission.elevesGerer, 'reprendre un élève');
    final motifValide = _motifValide(motif);
    var details = '';
    await _db.transaction<void>((txn) async {
      final ins = await _inscription(txn, inscriptionId);
      await _verifierAnneeOuverte(txn, ins.anneeId);
      if (ins.statut == StatutInscription.inscrit) {
        throw const ErreurGesco('Cet élève suit déjà sa classe.');
      }
      await _verifierCapacite(txn, ins.classeId, depasserCapacite);
      details = await _identite(txn, ins.eleveId);
      await txn.update(
        'inscription',
        {'statut': 'inscrit', 'date_sortie': null, 'motif_sortie': null},
        where: 'id = ?',
        whereArgs: [inscriptionId],
      );
      await _mouvement(
        txn,
        inscriptionId,
        'reprise',
        destination: ins.classeId,
        motif: motifValide,
      );
    });
    await controle.noter('reprise', 'eleve', id: inscriptionId, details: details);
  }

  // --------------------------------------------------------------- Transfert

  /// Ce que ferait [transferer] des notes, sans rien modifier. Lève une
  /// [ErreurGesco] si le transfert est impossible (autre année, mois
  /// verrouillé...).
  Future<ApercuTransfert> apercuTransfert(
    int inscriptionId,
    int nouvelleClasseId,
  ) async {
    final plan = await _planifierTransfert(_db, inscriptionId, nouvelleClasseId);
    return plan.apercu;
  }

  /// Change un élève de classe en gardant ses notes mensuelles : chaque note
  /// est reportée sur la matière de même nom de la nouvelle classe. Les notes
  /// sans matière équivalente et les notes d'évaluation (propres à la classe
  /// quittée) sont supprimées, mais seulement si [confirmerPertes] est vrai ;
  /// sinon une [ErreurAConfirmer] ('pertes') décrit ce qui serait perdu.
  /// Tout ou rien.
  Future<ApercuTransfert> transferer(
    int inscriptionId,
    int nouvelleClasseId, {
    String motif = '',
    bool confirmerPertes = false,
    bool depasserCapacite = false,
  }) async {
    controle.exiger(Permission.elevesGerer, 'changer un élève de classe');
    final motifValide = _motifValide(motif);
    var details = '';
    final apercu = await _db.transaction<ApercuTransfert>((txn) async {
      final plan = await _planifierTransfert(txn, inscriptionId, nouvelleClasseId);
      await _verifierCapacite(txn, nouvelleClasseId, depasserCapacite);
      if (plan.apercu.aDesPertes && !confirmerPertes) {
        throw ErreurAConfirmer(_messagePertes(plan.apercu), 'pertes');
      }
      details = await _identite(txn, plan.eleveId);

      // Le drapeau « transfert » autorise le déplacement des notes d'une
      // classe à l'autre ; il retombe à 0 dans la même transaction.
      await txn.update('contexte', {'transfert': 1}, where: 'id = 1');
      try {
        for (final (noteId, matiereId) in plan.reports) {
          await txn.update(
            'note',
            {'matiere_id': matiereId},
            where: 'id = ?',
            whereArgs: [noteId],
          );
        }
        for (final noteId in plan.notesASupprimer) {
          await txn.delete('note', where: 'id = ?', whereArgs: [noteId]);
        }
        await txn.delete(
          'evaluation_note',
          where: 'inscription_id = ?',
          whereArgs: [inscriptionId],
        );
        await txn.update(
          'inscription',
          {'classe_id': nouvelleClasseId},
          where: 'id = ?',
          whereArgs: [inscriptionId],
        );
      } finally {
        await txn.update('contexte', {'transfert': 0}, where: 'id = 1');
      }
      await _mouvement(
        txn,
        inscriptionId,
        'changement_classe',
        origine: plan.classeActuelleId,
        destination: nouvelleClasseId,
        motif: motifValide,
      );
      return plan.apercu;
    });
    await controle.noter(
      'transfert',
      'eleve',
      id: inscriptionId,
      details: '$details (${apercu.notesReprises} note(s) reprise(s)'
          '${apercu.aDesPertes ? ', ${apercu.notesPerdues} supprimée(s)' : ''})',
    );
    return apercu;
  }

  static String _messagePertes(ApercuTransfert a) {
    final parties = <String>[];
    if (a.notesSansMatiere > 0) {
      parties.add(
        '${pluriel(a.notesSansMatiere, 'note mensuelle')} '
        '${a.notesSansMatiere > 1 ? 'n\'ont' : 'n\'a'} pas de matière de même nom '
        'dans la nouvelle classe',
      );
    }
    if (a.notesEvaluation > 0) {
      parties.add(
        '${pluriel(a.notesEvaluation, 'note')} d\'évaluation '
        '${a.notesEvaluation > 1 ? 'sont propres' : 'est propre'} '
        'à la classe quittée',
      );
    }
    return 'Le transfert supprimera des notes : ${parties.join(' ; ')}. '
        'Cette action est irréversible.';
  }

  Future<_PlanTransfert> _planifierTransfert(
    DatabaseExecutor db,
    int inscriptionId,
    int nouvelleClasseId,
  ) async {
    final ins = await _inscription(db, inscriptionId);
    await _verifierAnneeOuverte(db, ins.anneeId);
    if (ins.statut != StatutInscription.inscrit) {
      throw const ErreurGesco(
        'Cet élève n\'est plus dans la classe : reprenez-le avant de le changer de classe.',
      );
    }
    if (ins.classeId == nouvelleClasseId) {
      throw const ErreurGesco('L\'élève est déjà dans cette classe.');
    }
    await _verifierClasse(db, nouvelleClasseId, ins.anneeId);

    // Mois concernés par des notes, comparés aux mois verrouillés des deux
    // classes : une période figée ne doit pas changer.
    final moisNotes = <int>{
      for (final l in await db.rawQuery(
        'SELECT DISTINCT mois FROM note WHERE inscription_id = ?',
        [inscriptionId],
      ))
        l['mois'] as int,
      for (final l in await db.rawQuery(
        '''
        SELECT DISTINCT e.mois AS mois FROM evaluation_note n
        JOIN evaluation e ON e.id = n.evaluation_id
        WHERE n.inscription_id = ?
        ''',
        [inscriptionId],
      ))
        l['mois'] as int,
    };
    if (moisNotes.isNotEmpty) {
      final verrous = await db.query(
        'verrou_notes',
        columns: ['mois'],
        where: 'classe_id IN (?, ?)',
        whereArgs: [ins.classeId, nouvelleClasseId],
      );
      final bloques = {for (final l in verrous) l['mois'] as int}
          .intersection(moisNotes)
          .toList()
        ..sort();
      if (bloques.isNotEmpty) {
        throw ErreurGesco(
          'Impossible de changer cet élève de classe : '
          '${bloques.length > 1 ? 'les mois' : 'le mois'} '
          '${bloques.map(libelleMois).join(', ')} '
          '${bloques.length > 1 ? 'sont verrouillés' : 'est verrouillé'} '
          'et contiennent ses notes. Déverrouillez-les d\'abord.',
        );
      }
      final validees = await compter(
        db,
        '''
        SELECT COUNT(*) FROM evaluation_note n
        JOIN evaluation e ON e.id = n.evaluation_id
        WHERE n.inscription_id = ? AND e.valide = 1
        ''',
        [inscriptionId],
      );
      if (validees > 0) {
        throw const ErreurGesco(
          'Impossible de changer cet élève de classe : certaines de ses notes '
          'appartiennent à des évaluations validées.',
        );
      }
    }

    final anciennes = await db.query(
      'matiere_classe',
      columns: ['id', 'nom'],
      where: 'classe_id = ?',
      whereArgs: [ins.classeId],
    );
    final nouvelles = await db.query(
      'matiere_classe',
      columns: ['id', 'nom'],
      where: 'classe_id = ?',
      whereArgs: [nouvelleClasseId],
      orderBy: 'ordre, id',
    );
    final parNom = <String, int>{};
    for (final m in nouvelles) {
      parNom.putIfAbsent(normaliserRecherche(m['nom'] as String), () => m['id'] as int);
    }
    // Une matière de la nouvelle classe ne reçoit les notes que d'une seule
    // ancienne matière (cas de deux noms qui ne diffèrent que par la casse).
    final equivalent = <int, int>{};
    final utilisees = <int>{};
    for (final m in anciennes) {
      final cible = parNom[normaliserRecherche(m['nom'] as String)];
      if (cible != null && utilisees.add(cible)) equivalent[m['id'] as int] = cible;
    }

    final notes = await db.query(
      'note',
      columns: ['id', 'matiere_id'],
      where: 'inscription_id = ?',
      whereArgs: [inscriptionId],
    );
    final reports = <(int, int)>[];
    final aSupprimer = <int>[];
    for (final n in notes) {
      final cible = equivalent[n['matiere_id'] as int];
      if (cible == null) {
        aSupprimer.add(n['id'] as int);
      } else {
        reports.add((n['id'] as int, cible));
      }
    }
    final notesEvaluation = await compter(
      db,
      'SELECT COUNT(*) FROM evaluation_note WHERE inscription_id = ?',
      [inscriptionId],
    );
    return _PlanTransfert(
      eleveId: ins.eleveId,
      classeActuelleId: ins.classeId,
      reports: reports,
      notesASupprimer: aSupprimer,
      apercu: ApercuTransfert(
        notesReprises: reports.length,
        notesSansMatiere: aSupprimer.length,
        notesEvaluation: notesEvaluation,
      ),
    );
  }

  // ------------------------------------------------------------ Suppression

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
    final bool fiche;
    try {
      fiche = await _db.transaction<bool>((txn) async {
        final lignes = await txn.query(
          'inscription',
          where: 'id = ?',
          whereArgs: [inscriptionId],
        );
        if (lignes.isEmpty) throw const ErreurGesco('Inscription introuvable.');
        final eleveId = lignes.first['eleve_id'] as int;
        await _verifierAnneeOuverte(txn, lignes.first['annee_id'] as int);
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

        final notes = await _compterNotes(txn, inscriptionId);
        if (notes > 0 && !avecNotes) {
          throw ErreurGesco(
            'Impossible de supprimer cet élève : ${pluriel(notes, 'note')} '
            '${notes > 1 ? 'sont enregistrées' : 'est enregistrée'}.',
          );
        }
        if (notes > 0) {
          await txn.delete(
            'evaluation_note',
            where: 'inscription_id = ?',
            whereArgs: [inscriptionId],
          );
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
    } on DatabaseException catch (e) {
      final texte = e.toString();
      if (texte.contains('Annee archivee')) {
        throw const ErreurGesco(
          'Cette année scolaire est archivée : rouvrez-la avant de supprimer un élève.',
        );
      }
      if (texte.contains('Mois verrouille')) {
        throw const ErreurGesco(
          'Un mois est verrouillé et contient des notes de cet élève : '
          'déverrouillez-le d\'abord.',
        );
      }
      if (texte.contains('Evaluation validee')) {
        throw const ErreurGesco(
          'Une évaluation validée contient des notes de cet élève : '
          'rouvrez-la d\'abord.',
        );
      }
      rethrow;
    }
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

  static String _motifValide(String motif) {
    final m = motif.trim();
    if (m.length > longueurMaxMotif) {
      throw const ErreurGesco(
        'Le motif est trop long ($longueurMaxMotif caractères maximum).',
      );
    }
    return m;
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
        'telephone': _texteOuNull(e.telephone),
        'nom_tuteur': _texteOuNull(e.nomTuteur),
        'contact_tuteur': _texteOuNull(e.contactTuteur),
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
        telephone: (l['telephone'] as String?) ?? '',
        nomTuteur: (l['nom_tuteur'] as String?) ?? '',
        contactTuteur: (l['contact_tuteur'] as String?) ?? '',
        archive: ((l['archive'] as int?) ?? 0) == 1,
      );

  Future<int> _inscrire(
    DatabaseExecutor db,
    int eleveId,
    int classeId,
    int anneeId,
    String typeMouvement,
  ) async {
    final id = await db.insert('inscription', {
      'eleve_id': eleveId,
      'classe_id': classeId,
      'annee_id': anneeId,
      'date_inscription': _maintenant().toIso8601String(),
    });
    await _mouvement(db, id, typeMouvement, destination: classeId);
    return id;
  }

  Future<void> _mouvement(
    DatabaseExecutor db,
    int inscriptionId,
    String type, {
    int? origine,
    int? destination,
    String motif = '',
  }) async {
    await db.rawInsert(
      '''
      INSERT INTO mouvement_inscription (
        inscription_id, type, date_mouvement, classe_origine_id,
        classe_destination_id, motif, utilisateur_nom
      ) VALUES (?, ?, ?, ?, ?, ?,
        COALESCE((SELECT utilisateur_nom FROM contexte WHERE id = 1), ''))
      ''',
      [inscriptionId, type, horodatage(_maintenant()), origine, destination, motif],
    );
  }

  static Future<_Inscription> _inscription(DatabaseExecutor db, int id) async {
    final lignes = await db.query('inscription', where: 'id = ?', whereArgs: [id]);
    if (lignes.isEmpty) throw const ErreurGesco('Inscription introuvable.');
    final l = lignes.first;
    return _Inscription(
      eleveId: l['eleve_id'] as int,
      classeId: l['classe_id'] as int,
      anneeId: l['annee_id'] as int,
      statut: StatutInscription.depuisCle(l['statut'] as String?),
    );
  }

  static Future<String> _identite(DatabaseExecutor db, int eleveId) async {
    final l = await db.query(
      'eleve',
      columns: ['nom', 'prenom', 'matricule'],
      where: 'id = ?',
      whereArgs: [eleveId],
    );
    if (l.isEmpty) return '';
    return '${l.first['nom']} ${l.first['prenom']} (${l.first['matricule']})';
  }

  static Future<void> _verifierAnneeOuverte(DatabaseExecutor db, int anneeId) async {
    final archivee = await compter(
      db,
      'SELECT COUNT(*) FROM annee_scolaire WHERE id = ? AND archivee = 1',
      [anneeId],
    );
    if (archivee > 0) {
      throw const ErreurGesco(
        'Cette année scolaire est archivée : elle n\'est plus modifiable. '
        'Rouvrez-la pour changer les inscriptions.',
      );
    }
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

  /// Refuse (avec possibilité de confirmer) l'arrivée d'un élève dans une
  /// classe qui a atteint sa capacité. Seuls les élèves qui suivent la
  /// classe comptent.
  static Future<void> _verifierCapacite(
    DatabaseExecutor db,
    int classeId,
    bool depasser,
  ) async {
    if (depasser) return;
    final lignes = await db.query(
      'classe',
      columns: ['nom', 'capacite'],
      where: 'id = ?',
      whereArgs: [classeId],
    );
    if (lignes.isEmpty) return;
    final capacite = lignes.first['capacite'] as int?;
    if (capacite == null) return;
    final actifs = await compter(
      db,
      "SELECT COUNT(*) FROM inscription WHERE classe_id = ? AND statut = 'inscrit'",
      [classeId],
    );
    if (actifs >= capacite) {
      throw ErreurAConfirmer(
        'La classe « ${lignes.first['nom']} » est pleine ($actifs élève(s) '
        'pour une capacité de $capacite).',
        'capacite',
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

  Future<void> _changerDeClasse(
    DatabaseExecutor db,
    int inscriptionId,
    int nouvelleClasseId,
    bool depasserCapacite,
  ) async {
    final ins = await _inscription(db, inscriptionId);
    if (ins.classeId == nouvelleClasseId) return;

    await _verifierAnneeOuverte(db, ins.anneeId);
    await _verifierClasse(db, nouvelleClasseId, ins.anneeId);
    final notes = await _compterNotes(db, inscriptionId);
    if (notes > 0) {
      throw ErreurGesco(
        'Impossible de changer de classe : ${pluriel(notes, 'note')} '
        '${notes > 1 ? 'sont déjà enregistrées' : 'est déjà enregistrée'} '
        'pour les matières de la classe actuelle. Utilisez « Transférer » '
        'pour reporter les notes sur la nouvelle classe.',
      );
    }
    if (ins.statut == StatutInscription.inscrit) {
      await _verifierCapacite(db, nouvelleClasseId, depasserCapacite);
    }
    await db.update(
      'inscription',
      {'classe_id': nouvelleClasseId},
      where: 'id = ?',
      whereArgs: [inscriptionId],
    );
    await _mouvement(
      db,
      inscriptionId,
      'changement_classe',
      origine: ins.classeId,
      destination: nouvelleClasseId,
    );
  }
}

class _Inscription {
  const _Inscription({
    required this.eleveId,
    required this.classeId,
    required this.anneeId,
    required this.statut,
  });

  final int eleveId;
  final int classeId;
  final int anneeId;
  final StatutInscription statut;
}

class _PlanTransfert {
  const _PlanTransfert({
    required this.eleveId,
    required this.classeActuelleId,
    required this.reports,
    required this.notesASupprimer,
    required this.apercu,
  });

  final int eleveId;
  final int classeActuelleId;

  /// (identifiant de la note, identifiant de la matière de la nouvelle classe).
  final List<(int, int)> reports;
  final List<int> notesASupprimer;
  final ApercuTransfert apercu;
}
