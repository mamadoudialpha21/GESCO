import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_securite.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/modeles.dart' show Saisie;
import 'package:gesco/domain/permissions.dart';
import 'package:gesco/import_export/import_notes.dart';
import 'package:gesco/import_export/lecture_tableur.dart';
import 'package:gesco/import_export/liste_vierge.dart';
import 'package:gesco/import_export/modele_export.dart';
import 'package:gesco/import_export/service_import_notes.dart';
import 'package:gesco/tableur/classeur.dart';
import 'package:gesco/tableur/xlsx.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher erreurContenant(String texte) => throwsA(
      isA<ErreurGesco>().having((e) => e.message, 'message', contains(texte)),
    );

const periode = PeriodeScolaire(cle: 't1', libelle: 'Trimestre 1', mois: [10, 11, 12]);

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Services s;
  late ServiceImportNotes service;
  late Directory dossier;
  late int annee;
  late int classeId;
  late Classe classe;
  late MatiereClasse maths;
  late int barry, diallo, camara;

  final instant = DateTime(2026, 11, 24, 10, 30, 15);

  setUp(() async {
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    s = Services(gdb, session: Session.sansControle(), iterations: 2);
    service = ServiceImportNotes(s, maintenant: () => instant);
    dossier = Directory.systemTemp.createTempSync('gesco_import_notes_');

    await s.etablissements.enregistrer(const Etablissement(nom: 'Groupe Scolaire Test'));
    annee = (await s.annees.creer('2026-2027', activer: true)).id;
    classeId = (await s.classes.creer(anneeId: annee, nom: '10e A', niveauCode: 10)).id;
    classe = (await s.classes.obtenir(classeId))!;
    maths = await s.matieres.ajouter(classeId: classeId, nom: 'Maths', coefficient: 100);
    await s.matieres.ajouter(classeId: classeId, nom: 'Français', coefficient: 100);

    Future<int> inscrire(String matricule, String nom, String prenom) => s.eleves.inscrire(
          Eleve(matricule: matricule, nom: nom, prenom: prenom, sexe: 'M'),
          anneeId: annee,
          classeId: classeId,
        );
    barry = await inscrire('2026-0001', 'BARRY', 'Mamadou');
    diallo = await inscrire('2026-0002', 'DIALLO', 'Aminata');
    camara = await inscrire('2026-0003', 'CAMARA', 'Fatou');
    final sow = await inscrire('2026-0004', 'SOW', 'Ibrahima');
    await s.eleves.enregistrerSortie(sow, StatutInscription.depart);
  });

  tearDown(() async {
    await gdb.fermer();
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  /// Liste vierge de Maths produite par GESCO (octobre), remplie comme le
  /// ferait un enseignant : [valeurs] = (matricule, colonne de notes, valeur).
  Future<ClasseurLu> listeRemplie(List<(String, int, Object?)> valeurs) async {
    final evals = [
      for (final r in await s.evaluations.lister(classeId: classeId)) r.evaluation,
    ];
    final colonnes = planifierColonnes(
      matiere: maths,
      evaluations: evals,
      options: const OptionsListeVierge(mois: 10),
    );
    final eleves = [
      for (final e in await s.eleves.lister(annee, classeId: classeId))
        if (e.actif) e,
    ];
    final feuilles = construireListeVierge(
      ContexteExport(etablissement: 'Groupe Scolaire Test', annee: '2026-2027', date: instant),
      ListeVierge(
        classe: classe,
        matieres: [MatiereVierge(matiere: maths, colonnes: colonnes)],
        eleves: eleves,
      ),
      mois: 10,
    );
    for (final (matricule, c, v) in valeurs) {
      final i = eleves.indexWhere((e) => e.matricule == matricule);
      feuilles[0].lignes[premiereLigneEleves + i][premiereColonneNotes + c] =
          CelluleEcrite(v, StyleCellule.note);
    }
    return service.ouvrir(ecrireClasseur(feuilles));
  }

  Future<ContexteImportNotes> contexte({bool remplacer = false}) => service.contexte(
        anneeId: annee,
        classe: classe,
        matiere: maths,
        periode: periode,
        remplacerExistantes: remplacer,
      );

  Future<RapportImportNotes> verifier(
    ClasseurLu classeur,
    ContexteImportNotes ctx,
  ) async {
    final p = service.reconnaitreListeGesco(classeur, ctx)!;
    expect(p.problemes, isEmpty);
    return analyserImportNotes(table: p.table!, mapping: p.mapping!, ctx: ctx);
  }

  Future<Map<String, Map<int, Saisie>>> notesParTitre() async {
    final liste = await s.evaluations.lister(classeId: classeId, matiereId: maths.id);
    return {
      for (final r in liste) r.evaluation.titre: await s.evaluations.lireNotes(r.evaluation.id),
    };
  }

  group('contexte', () {
    test('élèves, évaluations, notes existantes et mois verrouillés viennent de la base', () async {
      final e = await s.evaluations.creer(
        classeId: classeId,
        matiereId: maths.id,
        mois: 10,
        titre: 'Devoir 1',
      );
      await s.evaluations.enregistrerLot(e.id, {barry: const Saisie.valeur(1200)});
      await s.notes.verrouiller(classeId, 11);

      final ctx = await contexte();
      expect(ctx.classeNom, '10e A');
      expect(ctx.matiereNom, 'Maths');
      expect(ctx.matiereBareme, 20);
      expect(ctx.anneeLibelle, '2026-2027');
      expect(ctx.trimestreLibelle, 'Trimestre 1');
      expect(ctx.moisTrimestre, [10, 11, 12]);
      expect(ctx.eleves.map((x) => x.matricule).toSet(),
          {'2026-0001', '2026-0002', '2026-0003', '2026-0004'});
      expect(ctx.evaluations.single.titre, 'Devoir 1');
      expect(ctx.notesExistantes[e.id], {barry: const Saisie.valeur(1200)});
      expect(ctx.moisVerrouilles, {11});
      expect(ctx.remplacerExistantes, isFalse);
    });
  });

  group('liste GESCO remplie : vérifier, importer, contrôler', () {
    test('import complet : évaluations créées, notes écrites et relues', () async {
      final classeur = await listeRemplie([
        ('2026-0001', 0, 14.5),
        ('2026-0001', 1, 'ABS'),
        ('2026-0002', 0, 8),
        ('2026-0002', 1, 12.25),
      ]);
      final ctx = await contexte();
      final rapport = await verifier(classeur, ctx);
      expect(rapport.problemesFichier, isEmpty);
      expect(rapport.nbNotesAEcrire, 4);
      expect(rapport.nbEvaluationsACreer, 2);
      expect(rapport.nbLignesSansNote, 1);

      final bilan = await service.importer(
        rapport,
        classe: classe,
        matiere: maths,
        ignorerErreurs: false,
      );
      expect(bilan.nbEvaluationsCreees, 2);
      expect(bilan.nbNotes, 4);
      expect(bilan.nbVerifiees, 4);
      expect(bilan.nbRemplacees, 0);
      expect(bilan.nbLignesSansNote, 1);

      expect(await notesParTitre(), {
        'Interrogation 1': {barry: const Saisie.valeur(1450), diallo: const Saisie.valeur(800)},
        'Interrogation 2': {barry: const Saisie.absent(), diallo: const Saisie.valeur(1225)},
      });
    });

    test('réimporter le même fichier : rien à écrire, aucune évaluation en double', () async {
      final valeurs = [
        ('2026-0001', 0, 14.5),
        ('2026-0002', 1, 12.25),
      ];
      final premier = await listeRemplie(valeurs);
      final r1 = await verifier(premier, await contexte());
      await service.importer(r1, classe: classe, matiere: maths, ignorerErreurs: false);

      // Même fichier, relu : les évaluations existent maintenant.
      final ctx = await contexte();
      final r2 = await verifier(premier, ctx);
      expect(r2.problemesFichier, isEmpty);
      expect(r2.nbNotesAEcrire, 0);
      expect(r2.nbEvaluationsACreer, 0);
      expect(r2.nbIdentiques, 2);
      await expectLater(
        service.importer(r2, classe: classe, matiere: maths, ignorerErreurs: false),
        erreurContenant('Aucune note à importer'),
      );
      expect((await notesParTitre()).keys, ['Interrogation 1', 'Interrogation 2']);
    });

    test('une note différente n\'écrase rien, sauf demande explicite', () async {
      final r1 = await verifier(
        await listeRemplie([('2026-0001', 0, 10), ('2026-0002', 0, 11)]),
        await contexte(),
      );
      await service.importer(r1, classe: classe, matiere: maths, ignorerErreurs: false);

      // L'enseignant rend une autre version : 15 pour BARRY, 11 inchangé, 9 en plus.
      final autre = await listeRemplie([
        ('2026-0001', 0, 15),
        ('2026-0002', 0, 11),
        ('2026-0003', 0, 9),
      ]);
      final r2 = await verifier(autre, await contexte());
      expect(r2.nbConservees, 1);
      expect(r2.nbIdentiques, 1);
      expect(r2.nbNotesAEcrire, 1);
      final bilan = await service.importer(
        r2,
        classe: classe,
        matiere: maths,
        ignorerErreurs: false,
      );
      expect(bilan.nbNotes, 1);
      expect(bilan.nbConservees, 1);
      expect((await notesParTitre())['Interrogation 1'], {
        barry: const Saisie.valeur(1000),
        diallo: const Saisie.valeur(1100),
        camara: const Saisie.valeur(900),
      });

      // Avec l'accord de l'utilisateur, la note de BARRY est remplacée.
      final r3 = await verifier(autre, await contexte(remplacer: true));
      expect(r3.nbNotesRemplacees, 1);
      final bilan3 = await service.importer(
        r3,
        classe: classe,
        matiere: maths,
        ignorerErreurs: false,
      );
      expect(bilan3.nbNotes, 1);
      expect(bilan3.nbRemplacees, 1);
      expect((await notesParTitre())['Interrogation 1']![barry], const Saisie.valeur(1500));
      // L'ancienne valeur reste dans l'historique.
      final h = await s.notes.historique(classeId: classeId, inscriptionId: barry);
      expect(h.first.ancienTexte, '10,00 / 20');
      expect(h.first.nouveauTexte, '15,00 / 20');
    });

    test('lignes en erreur : refus tant qu\'on ne choisit pas de les ignorer', () async {
      final classeur = await listeRemplie([
        ('2026-0001', 0, 25), // hors barème
        ('2026-0002', 0, 12),
        ('2026-0003', 0, 'bien'),
      ]);
      final rapport = await verifier(classeur, await contexte());
      expect(rapport.nbLignesErreur, 2);
      expect(rapport.nbNotesAEcrire, 1);
      await expectLater(
        service.importer(rapport, classe: classe, matiere: maths, ignorerErreurs: false),
        erreurContenant('lignes sont en erreur'),
      );
      expect(await notesParTitre(), isEmpty);

      final bilan = await service.importer(
        rapport,
        classe: classe,
        matiere: maths,
        ignorerErreurs: true,
      );
      expect(bilan.nbNotes, 1);
      expect(bilan.nbLignesEnErreur, 2);
      expect((await notesParTitre())['Interrogation 1'], {diallo: const Saisie.valeur(1200)});
    });

    test('mois verrouillé : le fichier est refusé avec explication', () async {
      await s.notes.verrouiller(classeId, 10);
      final classeur = await listeRemplie([('2026-0001', 0, 14)]);
      final rapport = await verifier(classeur, await contexte());
      expect(rapport.bloque, isTrue);
      expect(rapport.problemesFichier.first, contains('Octobre est verrouillé'));
      await expectLater(
        service.importer(rapport, classe: classe, matiere: maths, ignorerErreurs: true),
        erreurContenant('problème'),
      );
      expect(await notesParTitre(), isEmpty);
    });

    test('évaluation validée depuis la création de la liste : refusé', () async {
      final e = await s.evaluations.creer(
        classeId: classeId,
        matiereId: maths.id,
        mois: 10,
        titre: 'Interrogation 1',
      );
      final classeur = await listeRemplie([('2026-0001', 0, 14)]);
      await s.evaluations.enregistrerLot(e.id, {barry: const Saisie.valeur(900)});
      await s.evaluations.valider(e.id);
      final rapport = await verifier(classeur, await contexte());
      expect(rapport.bloque, isTrue);
      expect(rapport.problemesFichier.single, contains('est validée'));
    });

    test('liste d\'une autre classe : refusée avant toute vérification', () async {
      final classeur = await listeRemplie([('2026-0001', 0, 14)]);
      final autreId = (await s.classes.creer(anneeId: annee, nom: '10e B', niveauCode: 10)).id;
      final autre = (await s.classes.obtenir(autreId))!;
      final matiereAutre = await s.matieres.ajouter(
        classeId: autreId,
        nom: 'Maths',
        coefficient: 100,
      );
      final ctx = await service.contexte(
        anneeId: annee,
        classe: autre,
        matiere: matiereAutre,
        periode: periode,
      );
      final p = service.reconnaitreListeGesco(classeur, ctx)!;
      expect(p.utilisable, isFalse);
      expect(p.problemes.first, contains('10e A'));
    });
  });

  group('autres classeurs Excel', () {
    Uint8List classeurQuelconque() => ecrireClasseur([
          FeuilleEcrite('Page de garde', [
            [const CelluleEcrite('Notes du premier trimestre')],
          ]),
          FeuilleEcrite('Notes', [
            [const CelluleEcrite('Collège de test')],
            <CelluleEcrite?>[],
            [
              const CelluleEcrite('Matricule'),
              const CelluleEcrite('Nom et prénom'),
              const CelluleEcrite('Interrogation 1 (sur 20)'),
            ],
            [
              const CelluleEcrite('2026-0001'),
              const CelluleEcrite('BARRY Mamadou'),
              const CelluleEcrite(13.5),
            ],
            [
              const CelluleEcrite('2026-0002'),
              const CelluleEcrite('DIALLO Aminata'),
              const CelluleEcrite('ABS'),
            ],
          ]),
        ]);

    test('la feuille et la ligne de titres sont repérées', () {
      final classeur = service.ouvrir(classeurQuelconque());
      final feuilles = service.feuilles(classeur);
      expect(feuilles.map((f) => f.nom), ['Page de garde', 'Notes']);
      expect(feuilles[1].indexEntete, 2);
      expect(service.feuilleProposee(classeur), 1);
      // Pas de feuille « GESCO » : ce n'est pas une liste produite par GESCO.
      expect(service.reconnaitreListeGesco(classeur, ContexteImportNotes(
            classeId: 1,
            classeNom: '10e A',
            matiereId: 1,
            matiereNom: 'Maths',
            matiereBareme: 20,
            anneeLibelle: '2026-2027',
            trimestreLibelle: 'Trimestre 1',
            moisTrimestre: const [10, 11, 12],
            eleves: const [],
            evaluations: const [],
          )),
          isNull);
    });

    test('association automatique puis import', () async {
      final classeur = service.ouvrir(classeurQuelconque());
      final ctx = await contexte();
      final f = classeur.feuilles[1];
      final table = lireTable(f, indexEntete: service.feuilles(classeur)[1].indexEntete!);
      final mapping = proposerAssociationNotes(table: table, ctx: ctx, moisParDefaut: 10);
      expect(mapping.colonnes.keys, [2]);
      final rapport = analyserImportNotes(table: table, mapping: mapping, ctx: ctx);
      expect(rapport.problemesFichier, isEmpty);
      expect(rapport.nbNotesAEcrire, 2);

      final bilan = await service.importer(
        rapport,
        classe: classe,
        matiere: maths,
        ignorerErreurs: false,
      );
      expect(bilan.nbEvaluationsCreees, 1);
      expect(bilan.nbVerifiees, 2);
      expect(await notesParTitre(), {
        'Interrogation 1': {barry: const Saisie.valeur(1350), diallo: const Saisie.absent()},
      });
    });

    test('un fichier qui n\'est pas un classeur Excel est refusé clairement', () {
      expect(
        () => service.ouvrir(Uint8List.fromList([1, 2, 3, 4])),
        erreurContenant('n\'est pas un classeur Excel'),
      );
    });
  });

  group('rapport et droits', () {
    test('le rapport est écrit dans un fichier Excel relisible, sans écraser l\'ancien', () async {
      final classeur = await listeRemplie([('2026-0001', 0, 25), ('2026-0002', 0, 12)]);
      final ctx = await contexte();
      final rapport = await verifier(classeur, ctx);
      final premier = await service.enregistrerRapport(
        rapport,
        ctx: ctx,
        nomFichier: 'maths.xlsx',
        dossier: dossier,
      );
      expect(premier.fichier.existsSync(), isTrue);
      expect(premier.nbFeuilles, 2);
      final relu = lireClasseur(await premier.fichier.readAsBytes());
      expect(relu.feuilles.map((f) => f.nom), ['Rapport', 'Colonnes']);
      final texte = [
        for (final l in relu.feuilles[0].lignes)
          for (final c in l) c.texte,
      ].join('|');
      expect(texte, contains('maths.xlsx'));
      expect(texte, contains('dépasse 20'));

      final second = await service.enregistrerRapport(
        rapport,
        ctx: ctx,
        nomFichier: 'maths.xlsx',
        dossier: dossier,
      );
      expect(second.fichier.path, isNot(premier.fichier.path));
      expect(premier.fichier.existsSync(), isTrue);
    });

    test('sans le droit d\'importer : ouvrir et importer sont refusés', () async {
      final classeur = await listeRemplie([('2026-0001', 0, 14)]);
      final rapport = await verifier(classeur, await contexte());
      final session = Session()
        ..ouvrir(const Utilisateur(
          id: 1,
          identifiant: 'lecteur',
          nomComplet: 'Lecteur',
          role: RoleUtilisateur.consultation,
          actif: true,
          creeLe: '2026-01-01',
          permissionsPersonnalisees: {Permission.tableauDeBord, Permission.elevesVoir},
        ));
      final restreint = ServiceImportNotes(Services(gdb, session: session, iterations: 2));
      expect(() => restreint.ouvrir(Uint8List(0)), erreurContenant('autorisation'));
      await expectLater(
        restreint.importer(rapport, classe: classe, matiere: maths, ignorerErreurs: false),
        erreurContenant('autorisation'),
      );
      expect(await notesParTitre(), isEmpty);
    });
  });
}
