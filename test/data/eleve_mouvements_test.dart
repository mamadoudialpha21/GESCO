import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/controle.dart';
import 'package:gesco/data/depots/annee_depot.dart';
import 'package:gesco/data/depots/classe_depot.dart';
import 'package:gesco/data/depots/eleve_depot.dart';
import 'package:gesco/data/depots/journal_depot.dart';
import 'package:gesco/data/depots/matiere_depot.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher erreurContenant(String texte) => throwsA(
      isA<ErreurGesco>().having((e) => e.message, 'message', contains(texte)),
    );

Matcher aConfirmer(String sujet, [String? texte]) => throwsA(
      isA<ErreurAConfirmer>()
          .having((e) => e.sujet, 'sujet', sujet)
          .having((e) => e.message, 'message', contains(texte ?? '')),
    );

class _AucuneAutorisation implements Autorisations {
  const _AucuneAutorisation();

  @override
  bool peut(Permission p) => false;

  @override
  bool get aUtilisateur => true;

  @override
  int? get enseignantLimite => null;
}

Eleve eleve(
  String matricule, {
  String nom = 'DIALLO',
  String prenom = 'Aminata',
  String sexe = 'F',
}) =>
    Eleve(matricule: matricule, nom: nom, prenom: prenom, sexe: sexe);

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Database db;
  late AnneeDepot annees;
  late ClasseDepot classes;
  late MatiereDepot matieres;
  late EleveDepot eleves;
  late int anneeId;
  late Classe classeA;
  late Classe classeB;
  var horloge = DateTime(2026, 10, 1, 8);

  setUp(() async {
    horloge = DateTime(2026, 10, 1, 8);
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    db = gdb.db;
    annees = AnneeDepot(db, maintenant: () => horloge);
    classes = ClasseDepot(db);
    matieres = MatiereDepot(db);
    eleves = EleveDepot(db, maintenant: () => horloge);
    anneeId = (await annees.creer('2026-2027')).id;
    classeA = await classes.creer(anneeId: anneeId, nom: '10e A');
    classeB = await classes.creer(anneeId: anneeId, nom: '10e B');
  });

  tearDown(() async {
    await gdb.fermer();
  });

  Future<int> inscrire(String matricule, {Classe? classe, String sexe = 'F'}) =>
      eleves.inscrire(
        eleve(matricule, nom: 'NOM$matricule', sexe: sexe),
        anneeId: anneeId,
        classeId: (classe ?? classeA).id,
      );

  Future<EleveInscrit> ligne(int inscriptionId, {bool archives = false}) async {
    final liste = await eleves.lister(anneeId, inclureArchives: archives);
    return liste.firstWhere((e) => e.inscriptionId == inscriptionId);
  }

  Future<int> note(int inscription, int matiere, int mois, int valeur) =>
      db.insert('note', {
        'inscription_id': inscription,
        'matiere_id': matiere,
        'mois': mois,
        'etat': 'saisie',
        'valeur': valeur,
        'modifie_le': '2026-10-02',
      });

  Future<int> evaluation(int classe, int matiere, int mois) => db.insert('evaluation', {
        'classe_id': classe,
        'matiere_id': matiere,
        'mois': mois,
        'type': 'devoir',
        'titre': 'Devoir 1',
        'coefficient': 100,
        'bareme': 20,
        'valide': 0,
        'cree_le': '2026-10-02',
      });

  Future<int> noteEvaluation(int evaluation, int inscription, int brut) =>
      db.insert('evaluation_note', {
        'evaluation_id': evaluation,
        'inscription_id': inscription,
        'etat': 'saisie',
        'brut': brut,
        'modifie_le': '2026-10-02',
      });

  Future<int> compterLignes(String table) async =>
      (await db.query(table)).length;

  group('fiche élève : nouveaux champs', () {
    test('téléphone et tuteur sont enregistrés puis relus', () async {
      final id = await eleves.inscrire(
        const Eleve(
          matricule: 'M1',
          nom: 'BAH',
          prenom: 'Oumou',
          sexe: 'F',
          telephone: ' 620 11 22 33 ',
          nomTuteur: 'Mamadou Bah',
          contactTuteur: '664 00 00 00',
        ),
        anneeId: anneeId,
        classeId: classeA.id,
      );
      final l = await ligne(id);
      final e = (await eleves.obtenir(l.eleveId))!;
      expect(e.telephone, '620 11 22 33');
      expect(e.nomTuteur, 'Mamadou Bah');
      expect(e.contactTuteur, '664 00 00 00');
      expect(e.archive, isFalse);
    });

    test('longueurs maximales vérifiées', () async {
      final trop = 'x' * 121;
      await expectLater(
        eleves.inscrire(
          Eleve(matricule: 'M1', nom: 'A', prenom: 'B', sexe: 'F', nomTuteur: trop),
          anneeId: anneeId,
          classeId: classeA.id,
        ),
        erreurContenant('Le nom du tuteur est trop long'),
      );
      await expectLater(
        eleves.inscrire(
          Eleve(matricule: 'M1', nom: 'A', prenom: 'B', sexe: 'F', telephone: trop),
          anneeId: anneeId,
          classeId: classeA.id,
        ),
        erreurContenant('Le téléphone est trop long'),
      );
      expect(await compterLignes('eleve'), 0);
    });

    test('modifier la fiche ne change pas l\'état archivé', () async {
      final id = await inscrire('M1');
      final l = await ligne(id);
      await eleves.enregistrerSortie(id, StatutInscription.depart);
      await eleves.archiver(l.eleveId);
      final fiche = (await eleves.obtenir(l.eleveId))!;
      expect(fiche.archive, isTrue);
      await eleves.modifier(fiche.copyWith(prenom: 'Autre', archive: false));
      expect((await eleves.obtenir(l.eleveId))!.archive, isTrue);
    });
  });

  group('archivage du dossier', () {
    test('refusé tant que l\'élève suit une classe de l\'année active', () async {
      final id = await inscrire('M1');
      final l = await ligne(id);
      await expectLater(
        eleves.archiver(l.eleveId),
        erreurContenant('enregistrez d\'abord son départ'),
      );
      expect((await eleves.obtenir(l.eleveId))!.archive, isFalse);
    });

    test('après le départ : le dossier disparaît des listes courantes', () async {
      final id = await inscrire('M1');
      await inscrire('M2');
      final l = await ligne(id);
      await eleves.enregistrerSortie(id, StatutInscription.depart);
      await eleves.archiver(l.eleveId);

      expect((await eleves.lister(anneeId)).length, 1);
      final tous = await eleves.lister(anneeId, inclureArchives: true);
      expect(tous.length, 2);
      expect(tous.firstWhere((e) => e.eleveId == l.eleveId).archive, isTrue);
      // Ses données sont conservées.
      expect(await compterLignes('inscription'), 2);
    });

    test('un élève archivé n\'est pas proposé pour la réinscription', () async {
      final id = await inscrire('M1');
      final l = await ligne(id);
      await eleves.enregistrerSortie(id, StatutInscription.abandon);
      await eleves.archiver(l.eleveId);
      final suivante = await annees.creer('2027-2028');
      expect(await eleves.nonInscrits(suivante.id), isEmpty);
      await expectLater(
        eleves.inscrireExistant(
          eleveId: l.eleveId,
          anneeId: suivante.id,
          classeId: (await classes.creer(anneeId: suivante.id, nom: '11e A')).id,
        ),
        erreurContenant('archivé'),
      );
    });

    test('désarchiver remet le dossier dans les listes', () async {
      final id = await inscrire('M1');
      final l = await ligne(id);
      await eleves.enregistrerSortie(id, StatutInscription.depart);
      await eleves.archiver(l.eleveId);
      await eleves.archiver(l.eleveId, archive: false);
      expect((await eleves.lister(anneeId)).length, 1);
      expect((await eleves.obtenir(l.eleveId))!.archive, isFalse);
    });

    test('élève inconnu', () async {
      await expectLater(eleves.archiver(999), erreurContenant('introuvable'));
    });
  });

  group('départ, abandon et reprise', () {
    test('le départ est enregistré avec sa date et son motif', () async {
      final id = await inscrire('M1');
      horloge = DateTime(2026, 12, 5, 9);
      await eleves.enregistrerSortie(
        id,
        StatutInscription.depart,
        motif: '  Déménagement  ',
      );
      final l = await ligne(id);
      expect(l.statut, StatutInscription.depart);
      expect(l.actif, isFalse);
      final lignes = await db.query('inscription', where: 'id = ?', whereArgs: [id]);
      expect(lignes.single['date_sortie'], '2026-12-05');
      expect(lignes.single['motif_sortie'], 'Déménagement');
    });

    test('la date de sortie peut être choisie', () async {
      final id = await inscrire('M1');
      horloge = DateTime(2026, 12, 1, 9);
      await eleves.enregistrerSortie(
        id,
        StatutInscription.abandon,
        date: DateTime(2026, 11, 20),
      );
      final lignes = await db.query('inscription', where: 'id = ?', whereArgs: [id]);
      expect(lignes.single['statut'], 'abandon');
      expect(lignes.single['date_sortie'], '2026-11-20');
    });

    test('les notes sont conservées', () async {
      final id = await inscrire('M1');
      final maths = await matieres.ajouter(classeId: classeA.id, nom: 'Maths', coefficient: 400);
      await note(id, maths.id, 10, 1500);
      await eleves.enregistrerSortie(id, StatutInscription.depart);
      expect(await compterLignes('note'), 1);
      expect(await eleves.compterNotes(id), 1);
    });

    test('refusé : statut « inscrit », double sortie, date future, motif trop long',
        () async {
      final id = await inscrire('M1');
      await expectLater(
        eleves.enregistrerSortie(id, StatutInscription.inscrit),
        erreurContenant('départ'),
      );
      await expectLater(
        eleves.enregistrerSortie(
          id,
          StatutInscription.depart,
          date: DateTime(2027, 3, 1),
        ),
        erreurContenant('futur'),
      );
      await expectLater(
        eleves.enregistrerSortie(
          id,
          StatutInscription.depart,
          motif: 'x' * 201,
        ),
        erreurContenant('motif est trop long'),
      );
      expect((await ligne(id)).statut, StatutInscription.inscrit);

      await eleves.enregistrerSortie(id, StatutInscription.depart);
      await expectLater(
        eleves.enregistrerSortie(id, StatutInscription.abandon),
        erreurContenant('déjà enregistré'),
      );
    });

    test('inscription inconnue', () async {
      await expectLater(
        eleves.enregistrerSortie(999, StatutInscription.depart),
        erreurContenant('Inscription introuvable'),
      );
      await expectLater(eleves.reprendre(999), erreurContenant('Inscription introuvable'));
    });

    test('la reprise remet l\'élève dans sa classe', () async {
      final id = await inscrire('M1');
      await eleves.enregistrerSortie(id, StatutInscription.abandon, motif: 'Maladie');
      await eleves.reprendre(id, motif: 'Retour');
      final l = await ligne(id);
      expect(l.statut, StatutInscription.inscrit);
      final lignes = await db.query('inscription', where: 'id = ?', whereArgs: [id]);
      expect(lignes.single['date_sortie'], isNull);
      expect(lignes.single['motif_sortie'], isNull);
    });

    test('reprendre un élève qui suit déjà sa classe est refusé', () async {
      final id = await inscrire('M1');
      await expectLater(eleves.reprendre(id), erreurContenant('suit déjà'));
    });

    test('les effectifs distinguent partis et abandons', () async {
      final a = await inscrire('M1', sexe: 'F');
      final b = await inscrire('M2', sexe: 'M');
      await inscrire('M3', sexe: 'M');
      await eleves.enregistrerSortie(a, StatutInscription.depart);
      await eleves.enregistrerSortie(b, StatutInscription.abandon);
      final e = await annees.effectifs(anneeId);
      expect(e.eleves, 3);
      expect(e.departs, 1);
      expect(e.abandons, 1);
      expect(e.actifs, 1);
      expect(e.filles, 1);
      expect(e.garcons, 2);

      final resume = (await classes.lister(anneeId)).firstWhere((c) => c.classe.id == classeA.id);
      expect(resume.nbEleves, 3);
      expect(resume.nbActifs, 1);
      expect(resume.nbGarcons, 1);
      expect(resume.nbFilles, 0);
    });

    test('impossible dans une année archivée', () async {
      final id = await inscrire('M1');
      await annees.creer('2027-2028', activer: true);
      await annees.archiver(anneeId);
      await expectLater(
        eleves.enregistrerSortie(id, StatutInscription.depart),
        erreurContenant('archivée'),
      );
    });
  });

  group('capacité des classes', () {
    late Classe petite;

    setUp(() async {
      petite = await classes.creer(
        anneeId: anneeId,
        nom: 'Petite',
        reglages: const ReglagesClasse(capacite: 2),
      );
    });

    test('une classe pleine demande confirmation, puis accepte', () async {
      await inscrire('M1', classe: petite);
      await inscrire('M2', classe: petite);
      await expectLater(
        eleves.inscrire(eleve('M3'), anneeId: anneeId, classeId: petite.id),
        aConfirmer('capacite', 'est pleine'),
      );
      expect(await compterLignes('eleve'), 2);

      await eleves.inscrire(
        eleve('M3'),
        anneeId: anneeId,
        classeId: petite.id,
        depasserCapacite: true,
      );
      expect(await compterLignes('eleve'), 3);
    });

    test('un élève parti libère sa place', () async {
      final a = await inscrire('M1', classe: petite);
      await inscrire('M2', classe: petite);
      await eleves.enregistrerSortie(a, StatutInscription.depart);
      await inscrire('M3', classe: petite);
      expect(
        (await classes.lister(anneeId)).firstWhere((c) => c.classe.id == petite.id).nbActifs,
        2,
      );
    });

    test('la reprise dans une classe pleine demande confirmation', () async {
      final a = await inscrire('M1', classe: petite);
      await inscrire('M2', classe: petite);
      await eleves.enregistrerSortie(a, StatutInscription.depart);
      await inscrire('M3', classe: petite);
      await expectLater(eleves.reprendre(a), aConfirmer('capacite'));
      await eleves.reprendre(a, depasserCapacite: true);
      expect((await ligne(a)).statut, StatutInscription.inscrit);
    });

    test('la réinscription et le changement de classe la respectent aussi',
        () async {
      await inscrire('M1', classe: petite);
      await inscrire('M2', classe: petite);
      final autre = await inscrire('M3');
      final l = await ligne(autre);
      final fiche = (await eleves.obtenir(l.eleveId))!;
      await expectLater(
        eleves.modifier(fiche, inscriptionId: autre, nouvelleClasseId: petite.id),
        aConfirmer('capacite'),
      );
      expect((await ligne(autre)).classeId, classeA.id);
      await eleves.modifier(
        fiche,
        inscriptionId: autre,
        nouvelleClasseId: petite.id,
        depasserCapacite: true,
      );
      expect((await ligne(autre)).classeId, petite.id);

      final suivante = await annees.creer('2027-2028');
      final petite2 = await classes.creer(
        anneeId: suivante.id,
        nom: 'P2',
        reglages: const ReglagesClasse(capacite: 1),
      );
      await eleves.inscrireExistant(
        eleveId: l.eleveId,
        anneeId: suivante.id,
        classeId: petite2.id,
      );
      final b = (await eleves.lister(anneeId)).firstWhere((e) => e.nom == 'NOMM1');
      await expectLater(
        eleves.inscrireExistant(
          eleveId: b.eleveId,
          anneeId: suivante.id,
          classeId: petite2.id,
        ),
        aConfirmer('capacite'),
      );
    });

    test('sans capacité, la classe n\'est jamais pleine', () async {
      for (var i = 0; i < 5; i++) {
        await inscrire('M$i');
      }
      expect((await eleves.lister(anneeId)).length, 5);
    });
  });

  group('mouvements d\'inscription', () {
    test('inscription, réinscription et changement de classe sont historisés',
        () async {
      final id = await inscrire('M1');
      final l = await ligne(id);
      final fiche = (await eleves.obtenir(l.eleveId))!;
      await eleves.modifier(fiche, inscriptionId: id, nouvelleClasseId: classeB.id);
      final suivante = await annees.creer('2027-2028');
      final c = await classes.creer(anneeId: suivante.id, nom: '11e A');
      final id2 = await eleves.inscrireExistant(
        eleveId: l.eleveId,
        anneeId: suivante.id,
        classeId: c.id,
      );

      final premiere = await eleves.mouvements(inscriptionId: id);
      expect(premiere.map((m) => m.type), ['changement_classe', 'inscription']);
      expect(premiere.first.classeOrigineNom, '10e A');
      expect(premiere.first.classeDestinationNom, '10e B');
      expect(premiere.first.libelleType, 'Changement de classe');

      final seconde = await eleves.mouvements(inscriptionId: id2);
      expect(seconde.single.type, 'reinscription');
      expect(seconde.single.anneeLibelle, '2027-2028');

      expect((await eleves.mouvements(eleveId: l.eleveId)).length, 3);
      expect((await eleves.mouvements(anneeId: suivante.id)).length, 1);
      expect((await eleves.mouvements(limite: 2)).length, 2);
    });

    test('départ puis reprise : motif, classe et nom de l\'élève', () async {
      final id = await inscrire('M1');
      await eleves.enregistrerSortie(id, StatutInscription.depart, motif: 'Voyage');
      await eleves.reprendre(id, motif: 'Retour');
      final liste = await eleves.mouvements(inscriptionId: id);
      expect(liste.map((m) => m.type), ['reprise', 'depart', 'inscription']);
      expect(liste[1].motif, 'Voyage');
      expect(liste[1].classeOrigineNom, '10e A');
      expect(liste[0].classeDestinationNom, '10e A');
      expect(liste[0].eleveNom, 'NOMM1 Aminata');
    });

    test('l\'auteur de l\'opération est conservé', () async {
      await db.update(
        'contexte',
        {'utilisateur_nom': 'Directrice'},
        where: 'id = 1',
      );
      final id = await inscrire('M1');
      final m = (await eleves.mouvements(inscriptionId: id)).single;
      expect(m.utilisateur, 'Directrice');
    });

    test('les inscriptions d\'un élève, de la plus récente à la plus ancienne',
        () async {
      final id = await inscrire('M1');
      final l = await ligne(id);
      await eleves.enregistrerSortie(id, StatutInscription.depart, motif: 'Raison');
      final suivante = await annees.creer('2027-2028');
      final c = await classes.creer(anneeId: suivante.id, nom: '11e A');
      await eleves.inscrireExistant(eleveId: l.eleveId, anneeId: suivante.id, classeId: c.id);

      final h = await eleves.inscriptionsDeLEleve(l.eleveId);
      expect(h.map((i) => i.anneeLibelle), ['2027-2028', '2026-2027']);
      expect(h.first.classeNom, '11e A');
      expect(h.first.statut, StatutInscription.inscrit);
      expect(h.last.statut, StatutInscription.depart);
      expect(h.last.motifSortie, 'Raison');
      expect(h.last.dateSortie, '2026-10-01');
    });

    test('supprimer l\'inscription supprime ses mouvements', () async {
      final id = await inscrire('M1');
      await eleves.enregistrerSortie(id, StatutInscription.depart);
      await eleves.supprimerInscription(id);
      expect(await compterLignes('mouvement_inscription'), 0);
    });
  });

  group('transfert de classe avec notes', () {
    late MatiereClasse mathsA;
    late MatiereClasse francaisA;
    late MatiereClasse mathsB;
    late MatiereClasse anglaisB;
    late int ins;

    setUp(() async {
      mathsA = await matieres.ajouter(classeId: classeA.id, nom: 'Maths', coefficient: 400);
      francaisA = await matieres.ajouter(classeId: classeA.id, nom: 'Français', coefficient: 300);
      mathsB = await matieres.ajouter(classeId: classeB.id, nom: 'MATHS', coefficient: 500);
      anglaisB = await matieres.ajouter(classeId: classeB.id, nom: 'Anglais', coefficient: 200);
      ins = await inscrire('M1');
    });

    test('sans notes : simple changement de classe', () async {
      final r = await eleves.transferer(ins, classeB.id, motif: 'Équilibrage');
      expect(r.notesReprises, 0);
      expect(r.aDesPertes, isFalse);
      expect((await ligne(ins)).classeId, classeB.id);
      final m = (await eleves.mouvements(inscriptionId: ins)).first;
      expect(m.type, 'changement_classe');
      expect(m.motif, 'Équilibrage');
    });

    test('les notes des matières de même nom suivent l\'élève', () async {
      await note(ins, mathsA.id, 10, 1250);
      await note(ins, mathsA.id, 11, 1475);
      final r = await eleves.transferer(ins, classeB.id);
      expect(r.notesReprises, 2);
      expect(r.notesPerdues, 0);
      final notes = await db.query('note', orderBy: 'mois');
      expect(notes.map((n) => n['matiere_id']), [mathsB.id, mathsB.id]);
      expect(notes.map((n) => n['valeur']), [1250, 1475]);
      expect((await ligne(ins)).classeId, classeB.id);
    });

    test('les notes sans matière équivalente demandent confirmation', () async {
      await note(ins, mathsA.id, 10, 1250);
      await note(ins, francaisA.id, 10, 900);
      await expectLater(
        eleves.transferer(ins, classeB.id),
        aConfirmer('pertes', '1 note mensuelle'),
      );
      // Rien n'a changé.
      expect((await ligne(ins)).classeId, classeA.id);
      expect(await compterLignes('note'), 2);
      expect((await db.query('note', where: 'matiere_id = ?', whereArgs: [mathsA.id])).length, 1);

      final r = await eleves.transferer(ins, classeB.id, confirmerPertes: true);
      expect(r.notesReprises, 1);
      expect(r.notesSansMatiere, 1);
      expect(await compterLignes('note'), 1);
      expect((await db.query('note')).single['matiere_id'], mathsB.id);
    });

    test('les notes d\'évaluation sont supprimées avec confirmation', () async {
      final ev = await evaluation(classeA.id, mathsA.id, 10);
      await noteEvaluation(ev, ins, 1500);
      await note(ins, mathsA.id, 11, 1000);
      await expectLater(
        eleves.transferer(ins, classeB.id),
        aConfirmer('pertes', 'd\'évaluation'),
      );
      expect(await compterLignes('evaluation_note'), 1);

      final r = await eleves.transferer(ins, classeB.id, confirmerPertes: true);
      expect(r.notesEvaluation, 1);
      expect(r.notesReprises, 1);
      expect(await compterLignes('evaluation_note'), 0);
      // L'évaluation elle-même reste dans la classe quittée.
      expect(await compterLignes('evaluation'), 1);
    });

    test('l\'aperçu ne modifie rien', () async {
      await note(ins, mathsA.id, 10, 1250);
      await note(ins, francaisA.id, 10, 900);
      final ev = await evaluation(classeA.id, mathsA.id, 11);
      await noteEvaluation(ev, ins, 1500);
      final a = await eleves.apercuTransfert(ins, classeB.id);
      expect(a.notesReprises, 1);
      expect(a.notesSansMatiere, 1);
      expect(a.notesEvaluation, 1);
      expect(a.notesPerdues, 2);
      expect(a.aDesPertes, isTrue);
      expect((await ligne(ins)).classeId, classeA.id);
      expect(await compterLignes('note'), 2);
      expect(await compterLignes('evaluation_note'), 1);
    });

    test('le drapeau de transfert retombe à zéro, même après un refus', () async {
      await note(ins, francaisA.id, 10, 900);
      await expectLater(eleves.transferer(ins, classeB.id), aConfirmer('pertes'));
      expect((await db.query('contexte')).single['transfert'], 0);
      await eleves.transferer(ins, classeB.id, confirmerPertes: true);
      expect((await db.query('contexte')).single['transfert'], 0);
    });

    test('après le transfert, seules les matières de la nouvelle classe sont acceptées',
        () async {
      await note(ins, mathsA.id, 10, 1250);
      await eleves.transferer(ins, classeB.id);
      await note(ins, anglaisB.id, 10, 1000);
      await expectLater(
        note(ins, francaisA.id, 10, 1000),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('refusé : même classe, autre année, élève parti', () async {
      await expectLater(
        eleves.transferer(ins, classeA.id),
        erreurContenant('déjà dans cette classe'),
      );
      final suivante = await annees.creer('2027-2028');
      final autre = await classes.creer(anneeId: suivante.id, nom: '11e A');
      await expectLater(
        eleves.transferer(ins, autre.id),
        erreurContenant('n\'existe pas pour l\'année'),
      );
      await eleves.enregistrerSortie(ins, StatutInscription.depart);
      await expectLater(
        eleves.transferer(ins, classeB.id),
        erreurContenant('reprenez-le'),
      );
      expect((await ligne(ins)).classeId, classeA.id);
    });

    test('refusé si un mois contenant ses notes est verrouillé', () async {
      await note(ins, mathsA.id, 10, 1250);
      await note(ins, mathsA.id, 11, 1250);
      await db.insert('verrou_notes', {
        'classe_id': classeB.id,
        'mois': 11,
        'verrouille_le': '2026-11-30',
      });
      await expectLater(
        eleves.transferer(ins, classeB.id),
        erreurContenant('Novembre'),
      );
      await db.delete('verrou_notes');
      await db.insert('verrou_notes', {
        'classe_id': classeA.id,
        'mois': 10,
        'verrouille_le': '2026-10-31',
      });
      await expectLater(
        eleves.transferer(ins, classeB.id),
        erreurContenant('Octobre'),
      );
      expect((await ligne(ins)).classeId, classeA.id);
    });

    test('un mois verrouillé sans note de l\'élève ne bloque pas', () async {
      await note(ins, mathsA.id, 10, 1250);
      await db.insert('verrou_notes', {
        'classe_id': classeB.id,
        'mois': 12,
        'verrouille_le': '2026-12-20',
      });
      await eleves.transferer(ins, classeB.id);
      expect((await ligne(ins)).classeId, classeB.id);
    });

    test('refusé si une de ses notes appartient à une évaluation validée',
        () async {
      final ev = await evaluation(classeA.id, mathsA.id, 10);
      await noteEvaluation(ev, ins, 1500);
      await db.update('evaluation', {'valide': 1}, where: 'id = ?', whereArgs: [ev]);
      await expectLater(
        eleves.transferer(ins, classeB.id, confirmerPertes: true),
        erreurContenant('évaluations validées'),
      );
      expect(await compterLignes('evaluation_note'), 1);
    });

    test('la classe d\'arrivée pleine demande confirmation', () async {
      await classes.modifier(
        classeB.id,
        nom: classeB.nom,
        niveau: classeB.niveau,
        reglages: const ReglagesClasse(capacite: 1),
      );
      await inscrire('M2', classe: classeB);
      await expectLater(eleves.transferer(ins, classeB.id), aConfirmer('capacite'));
      await eleves.transferer(ins, classeB.id, depasserCapacite: true);
      expect((await ligne(ins)).classeId, classeB.id);
    });

    test('changer de classe depuis la fiche avec notes oriente vers le transfert',
        () async {
      await note(ins, mathsA.id, 10, 1250);
      final l = await ligne(ins);
      final fiche = (await eleves.obtenir(l.eleveId))!;
      await expectLater(
        eleves.modifier(fiche, inscriptionId: ins, nouvelleClasseId: classeB.id),
        erreurContenant('Transférer'),
      );
    });
  });

  group('suppression et notes d\'évaluation', () {
    test('compterNotes inclut les notes d\'évaluation', () async {
      final maths = await matieres.ajouter(classeId: classeA.id, nom: 'Maths', coefficient: 400);
      final ins = await inscrire('M1');
      await note(ins, maths.id, 10, 1000);
      final ev = await evaluation(classeA.id, maths.id, 10);
      await noteEvaluation(ev, ins, 1200);
      expect(await eleves.compterNotes(ins), 2);
    });

    test('refusée sans confirmation, complète avec', () async {
      final maths = await matieres.ajouter(classeId: classeA.id, nom: 'Maths', coefficient: 400);
      final ins = await inscrire('M1');
      final ev = await evaluation(classeA.id, maths.id, 10);
      await noteEvaluation(ev, ins, 1200);
      await expectLater(
        eleves.supprimerInscription(ins),
        erreurContenant('1 note est enregistrée'),
      );
      expect(await compterLignes('evaluation_note'), 1);

      final fiche = await eleves.supprimerInscription(ins, avecNotes: true);
      expect(fiche, isTrue);
      expect(await compterLignes('evaluation_note'), 0);
      expect(await compterLignes('inscription'), 0);
    });

    test('impossible dans une année archivée (message clair)', () async {
      final maths = await matieres.ajouter(classeId: classeA.id, nom: 'Maths', coefficient: 400);
      final ins = await inscrire('M1');
      await note(ins, maths.id, 10, 1000);
      await annees.creer('2027-2028', activer: true);
      await annees.archiver(anneeId);
      await expectLater(
        eleves.supprimerInscription(ins, avecNotes: true),
        erreurContenant('archivée'),
      );
      expect(await compterLignes('note'), 1);
      expect(await compterLignes('inscription'), 1);
    });
  });

  group('permissions et journal', () {
    test('sans permission, aucune opération d\'écriture n\'est possible', () async {
      final id = await inscrire('M1');
      final l = await ligne(id);
      final refuse = EleveDepot(
        db,
        controle: const Controle(autorisations: _AucuneAutorisation()),
      );
      await expectLater(
        refuse.enregistrerSortie(id, StatutInscription.depart),
        erreurContenant('autorisation'),
      );
      await expectLater(refuse.reprendre(id), erreurContenant('autorisation'));
      await expectLater(
        refuse.transferer(id, classeB.id),
        erreurContenant('autorisation'),
      );
      await expectLater(refuse.archiver(l.eleveId), erreurContenant('autorisation'));
      await expectLater(
        refuse.inscrire(eleve('M9'), anneeId: anneeId, classeId: classeA.id),
        erreurContenant('autorisation'),
      );
      expect((await ligne(id)).statut, StatutInscription.inscrit);
    });

    test('départ, transfert et archivage sont inscrits au journal', () async {
      final journal = JournalDepot(db);
      final suivi = EleveDepot(
        db,
        maintenant: () => horloge,
        controle: Controle(journal: journal),
      );
      final id = await suivi.inscrire(
        eleve('M1'),
        anneeId: anneeId,
        classeId: classeA.id,
      );
      await suivi.transferer(id, classeB.id);
      await suivi.enregistrerSortie(id, StatutInscription.abandon, motif: 'Raison');
      final l = (await suivi.lister(anneeId)).single;
      await suivi.archiver(l.eleveId);
      final actions = [for (final e in await journal.recentes(20)) e.action];
      expect(actions, containsAll(['inscription', 'transfert', 'abandon', 'archivage']));
    });
  });
}
