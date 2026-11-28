import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_absences.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_notation.dart';
import 'package:gesco/data/modeles_securite.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:gesco/import_export/liste_vierge.dart';
import 'package:gesco/import_export/service_export.dart';
import 'package:gesco/tableur/classeur.dart';
import 'package:gesco/tableur/xlsx.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/niveaux.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher erreurContenant(String texte) => throwsA(
      isA<ErreurGesco>().having((e) => e.message, 'message', contains(texte)),
    );

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Services s;
  late ServiceExport service;
  late Directory dossier;
  late int annee;
  late int classeA, classeB;
  late int maths, francais, dessin, histoire, calcul;
  late int ens1, ens2, ens3;
  late int barry, diallo, sow, camara;

  final instant = DateTime(2026, 11, 22, 10, 30, 15);

  setUp(() async {
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    s = Services(gdb, session: Session.sansControle(), iterations: 2);
    service = ServiceExport(s, maintenant: () => instant);
    dossier = Directory.systemTemp.createTempSync('gesco_export_');

    await s.etablissements.enregistrer(const Etablissement(nom: 'Groupe Scolaire Test'));
    annee = (await s.annees.creer('2026-2027', activer: true)).id;
    // Ces tests portent sur l'ancien modèle (trimestres) : on le fixe explicitement.
    await s.calendriers.enregistrer(annee, Calendrier.deuxTrimestres, cycle: Cycle.college);
    await s.calendriers.enregistrer(annee, Calendrier.trimestres, cycle: Cycle.primaire);
    ens1 = await s.enseignants.creer(const Enseignant(nom: 'DIALLO', prenom: 'Aminata'));
    ens2 = await s.enseignants.creer(const Enseignant(nom: 'BAH', prenom: 'Oumar'));
    ens3 = await s.enseignants.creer(const Enseignant(nom: 'SYLLA', prenom: 'Kadiatou'));

    // Collège (deux trimestres) et primaire (trois trimestres).
    classeA = (await s.classes.creer(anneeId: annee, nom: '10e A', niveauCode: 10)).id;
    classeB = (await s.classes.creer(anneeId: annee, nom: '3e B', niveauCode: 3)).id;
    maths = (await s.matieres.ajouter(
            classeId: classeA, nom: 'Maths', coefficient: 100, enseignantId: ens1))
        .id;
    francais = (await s.matieres.ajouter(
            classeId: classeA, nom: 'Français', coefficient: 100, enseignantId: ens1))
        .id;
    dessin = (await s.matieres.ajouter(
            classeId: classeA, nom: 'Dessin', coefficient: 100, enseignantId: ens2))
        .id;
    histoire = (await s.matieres.ajouter(
            classeId: classeA, nom: 'Histoire', coefficient: 100, enseignantId: ens3))
        .id;
    calcul = (await s.matieres.ajouter(
            classeId: classeB, nom: 'Calcul', coefficient: 100, enseignantId: ens2))
        .id;

    Future<int> inscrire(String matricule, String nom, String prenom, String sexe, int classe) =>
        s.eleves.inscrire(
          Eleve(
            matricule: matricule,
            nom: nom,
            prenom: prenom,
            sexe: sexe,
            dateNaissance: '2011-03-05',
          ),
          anneeId: annee,
          classeId: classe,
        );
    barry = await inscrire('2026-0001', 'BARRY', 'Mamadou', 'M', classeA);
    diallo = await inscrire('2026-0002', 'DIALLO', 'Aminata', 'F', classeA);
    sow = await inscrire('2026-0003', 'SOW', 'Ibrahima', 'M', classeA);
    camara = await inscrire('2026-0004', 'CAMARA', 'Fatou', 'F', classeB);
    await s.eleves.enregistrerSortie(sow, StatutInscription.depart, motif: 'Déménagement');

    Future<void> note(int ins, int matiere, int centiemes) => s.notes.enregistrer(
          inscriptionId: ins,
          matiereId: matiere,
          mois: 11,
          saisie: Saisie.valeur(centiemes),
        );
    await note(barry, maths, 1600);
    await note(diallo, maths, 800);
    await note(camara, calcul, 1500);

    // Français : une évaluation de novembre, validée (ne peut plus recevoir de notes).
    final dictee = await s.evaluations.creer(
      classeId: classeA,
      matiereId: francais,
      mois: 11,
      titre: 'Dictée',
      type: TypeEvaluation.devoir,
      date: '2026-11-04',
    );
    await s.evaluations.enregistrerLot(dictee.id, {
      barry: const Saisie.valeur(1400),
      diallo: const Saisie.valeur(1000),
    });
    await s.evaluations.valider(dictee.id);
    // Histoire : seulement une évaluation validée.
    final controle = await s.evaluations.creer(
      classeId: classeA,
      matiereId: histoire,
      mois: 11,
      titre: 'Contrôle',
    );
    await s.evaluations.valider(controle.id);
    // Dessin : une évaluation ouverte, qui servira de colonne.
    await s.evaluations.creer(
      classeId: classeA,
      matiereId: dessin,
      mois: 11,
      titre: 'Croquis',
      type: TypeEvaluation.devoir,
      date: '2026-11-10',
      bareme: 10,
    );

    await s.absences.ajouter(Absence(
      inscriptionId: barry,
      date: '2026-11-03',
      justifiee: true,
      motif: 'Paludisme',
    ));
    await s.absences.ajouter(Absence(
      inscriptionId: barry,
      date: '2026-11-05',
      type: TypeAbsence.retard,
      dureeMinutes: 15,
    ));
  });

  tearDown(() async {
    await gdb.fermer();
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  /// Construit l'export puis relit le classeur : les onglets annoncés doivent
  /// être exactement ceux du fichier.
  Future<(FichierExcel, ClasseurLu)> exporter(
    TypeExport type, {
    OptionsExport options = const OptionsExport(),
  }) async {
    final f = await service.construire(type, anneeId: annee, options: options);
    final lu = lireClasseur(f.octets);
    expect([for (final x in lu.feuilles) x.nom], f.feuilles);
    return (f, lu);
  }

  group('les dix exports', () {
    test('liste complète des élèves : tous, partis compris, triés par nom', () async {
      final (f, lu) = await exporter(TypeExport.eleves);
      expect(f.feuilles, ['Élèves']);
      expect(f.nomBase, 'Liste complète des élèves 2026-2027');
      final feuille = lu.feuille('Élèves')!;
      expect([for (var i = 5; i < 9; i++) feuille.cellule(i, 1).texte],
          ['2026-0001', '2026-0004', '2026-0002', '2026-0003']);
      expect(feuille.cellule(0, 0).texte, 'Groupe Scolaire Test');
      expect(feuille.cellule(5, 5).date, DateTime(2011, 3, 5));
      expect(feuille.cellule(6, 14).texte, '3e B');
      expect(feuille.cellule(8, 16).texte, 'Parti');
      expect(feuille.cellule(9, 1).vide, isTrue);
    });

    test('élèves par classe : une feuille par classe, ou une seule', () async {
      final (f, _) = await exporter(TypeExport.elevesParClasse);
      expect([...f.feuilles]..sort(), ['10e A', '3e B']);

      final (g, lu) = await exporter(
        TypeExport.elevesParClasse,
        options: OptionsExport(classeId: classeB),
      );
      expect(g.feuilles, ['3e B']);
      expect(g.nomBase, contains('3e B'));
      expect(lu.feuilles.single.cellule(5, 2).texte, 'CAMARA');
    });

    test('notes par matière : une feuille par matière de la classe', () async {
      final (f, lu) = await exporter(
        TypeExport.notesParMatiere,
        options: OptionsExport(classeId: classeA),
      );
      expect(f.feuilles, ['Notes Maths', 'Notes Français', 'Notes Dessin', 'Notes Histoire']);
      final feuille = lu.feuille('Notes Maths')!;
      // Colonnes : N°, matricule, nom, prénom, puis octobre, novembre...
      expect(feuille.cellule(4, 5).texte, 'Novembre');
      expect(feuille.cellule(5, 2).texte, 'BARRY');
      expect(feuille.cellule(5, 5).nombre, 16.0);
      expect(feuille.cellule(6, 5).nombre, 8.0);
      expect(feuille.cellule(7, 2).vide, isTrue, reason: 'SOW, parti, ne figure pas');

      final (g, _) = await exporter(
        TypeExport.notesParMatiere,
        options: OptionsExport(classeId: classeA, matiereId: dessin),
      );
      expect(g.feuilles, ['Notes Dessin']);
    });

    test('notes par matière : la classe est obligatoire', () async {
      expect(
        () => service.construire(TypeExport.notesParMatiere, anneeId: annee),
        erreurContenant('Choisissez une classe'),
      );
    });

    test('notes par classe : les évaluations validées comptent dans la moyenne', () async {
      final (f, lu) = await exporter(
        TypeExport.notesParClasse,
        options: const OptionsExport(cle: 'm11'),
      );
      expect([...f.feuilles]..sort(), ['Classe 10e A', 'Classe 3e B']);
      final a = lu.feuille('Classe 10e A')!;
      expect(a.cellule(4, 4).texte, 'Maths\ncoef. 1');
      expect(a.cellule(5, 2).texte, 'BARRY');
      expect(a.cellule(5, 4).nombre, 16.0);
      expect(a.cellule(5, 5).nombre, 14.0, reason: 'note de la dictée validée');
      expect(a.cellule(6, 2).texte, 'DIALLO');
      expect(a.cellule(6, 5).nombre, 10.0);
      expect(a.cellule(7, 2).vide, isTrue);
      final b = lu.feuille('Classe 3e B')!;
      expect(b.cellule(5, 4).nombre, 15.0);
    });

    test('résultats trimestriels : seule la classe qui a ce trimestre est exportée', () async {
      final (f, _) = await exporter(
        TypeExport.resultatsTrimestriels,
        options: const OptionsExport(cle: 't1'),
      );
      expect(f.feuilles.length, 2);
      expect(f.avertissements, isEmpty);

      final (g, lu) = await exporter(
        TypeExport.resultatsTrimestriels,
        options: const OptionsExport(cle: 't3'),
      );
      expect(g.feuilles, ['Résultats 3e B']);
      expect(g.avertissements.single, contains('10e A'));
      expect(lu.feuilles.single.cellule(1, 0).texte, 'Résultats : Trimestre 3');
    });

    test('résultats trimestriels : un trimestre est exigé', () async {
      for (final cle in ['annee', 'm11']) {
        expect(
          () => service.construire(
            TypeExport.resultatsTrimestriels,
            anneeId: annee,
            options: OptionsExport(cle: cle),
          ),
          erreurContenant('Choisissez une période'),
        );
      }
    });

    test('résultats trimestriels : période inconnue de toutes les classes', () async {
      expect(
        () => service.construire(
          TypeExport.resultatsTrimestriels,
          anneeId: annee,
          options: const OptionsExport(cle: 'zz'),
        ),
        erreurContenant('Aucune classe n\'a la période choisie'),
      );
    });

    test('résultats annuels : une feuille par classe', () async {
      final (f, lu) = await exporter(TypeExport.resultatsAnnuels);
      expect([...f.feuilles]..sort(), ['Résultats 10e A', 'Résultats 3e B']);
      final a = lu.feuille('Résultats 10e A')!;
      expect(a.cellule(1, 0).texte, 'Résultats annuels');
      // BARRY, DIALLO puis SOW (parti) avec sa remarque.
      expect(a.cellule(7, 2).texte, 'SOW');
      expect(a.cellule(7, 11).texte, 'Parti', reason: 'colonne Remarque (collège : deux trimestres)');
    });

    test('classements : général, ou dans une matière', () async {
      final (f, lu) = await exporter(
        TypeExport.classements,
        options: OptionsExport(classeId: classeA, cle: 'm11'),
      );
      expect(f.feuilles, ['Classement 10e A']);
      final feuille = lu.feuilles.single;
      expect(feuille.cellule(5, 0).nombre, 1);
      expect(feuille.cellule(5, 3).texte, 'BARRY');
      expect(feuille.cellule(6, 3).texte, 'DIALLO');

      final (g, lu2) = await exporter(
        TypeExport.classements,
        options: OptionsExport(classeId: classeA, matiereId: maths, cle: 'm11'),
      );
      expect(g.feuilles, ['Maths 10e A']);
      expect(lu2.feuilles.single.cellule(1, 0).texte, 'Classement en Maths');
      expect(lu2.feuilles.single.cellule(5, 6).nombre, 16.0);
    });

    test('classements : une matière d\'une autre classe est refusée', () async {
      expect(
        () => service.construire(
          TypeExport.classements,
          anneeId: annee,
          options: OptionsExport(classeId: classeB, matiereId: maths, cle: 'm11'),
        ),
        erreurContenant('n\'appartient pas à la classe'),
      );
    });

    test('absences : totaux par élève puis détail', () async {
      final (f, lu) = await exporter(TypeExport.absences);
      expect(f.feuilles, ['Totaux', 'Détail']);
      final totaux = lu.feuille('Totaux')!;
      // Classe, matricule, nom, prénom, absences, justifiées, injustifiées,
      // retards, retards justifiés, minutes.
      var barryLigne = -1;
      for (var i = 5; i < totaux.nbLignes; i++) {
        if (totaux.cellule(i, 1).texte == '2026-0001') barryLigne = i;
      }
      expect(barryLigne, greaterThan(0));
      expect(
        [for (var c = 4; c < 10; c++) totaux.cellule(barryLigne, c).nombre],
        [1.0, 1.0, 0.0, 1.0, 0.0, 15.0],
      );
      final detail = lu.feuille('Détail')!;
      expect(detail.cellule(5, 0).date, DateTime(2026, 11, 3));
      expect(detail.cellule(5, 7).texte, 'Paludisme');
      expect(detail.cellule(6, 4).texte, 'Retard');

      final (g, _) = await exporter(
        TypeExport.absences,
        options: OptionsExport(classeId: classeB),
      );
      expect(g.nomBase, contains('3e B'));
    });

    test('statistiques générales : établissement et classes', () async {
      final (f, lu) = await exporter(
        TypeExport.statistiques,
        options: const OptionsExport(cle: 'm11'),
      );
      expect(f.feuilles, ['Établissement', 'Classes']);
      final ecole = lu.feuille('Établissement')!;
      expect(ecole.cellule(5, 0).texte, 'Nombre de classes');
      expect(ecole.cellule(5, 1).nombre, 2);
      expect(ecole.cellule(6, 0).texte, 'Élèves inscrits');
      expect(ecole.cellule(6, 1).nombre, 3, reason: 'BARRY, DIALLO, CAMARA (SOW est parti)');
    });

    test('admis et non admis', () async {
      final (f, lu) = await exporter(
        TypeExport.admis,
        options: const OptionsExport(cle: 'm11'),
      );
      expect(f.feuilles, ['Admis', 'Non admis']);
      final admis = [
        for (var i = 5; i < lu.feuille('Admis')!.nbLignes; i++) lu.feuille('Admis')!.cellule(i, 3).texte,
      ];
      final non = [
        for (var i = 5; i < lu.feuille('Non admis')!.nbLignes; i++)
          lu.feuille('Non admis')!.cellule(i, 3).texte,
      ];
      expect(admis, containsAll(['BARRY', 'CAMARA']));
      expect(non, ['DIALLO']);
      expect(admis, isNot(contains('SOW')));
    });
  });

  group('rien à exporter, mauvais choix', () {
    test('année sans élève ni classe', () async {
      final vide = (await s.annees.creer('2027-2028')).id;
      expect(() => service.construire(TypeExport.eleves, anneeId: vide),
          erreurContenant('Aucun élève'));
      expect(() => service.construire(TypeExport.elevesParClasse, anneeId: vide),
          erreurContenant('Aucune classe'));
      expect(() => service.construire(TypeExport.resultatsAnnuels, anneeId: vide),
          erreurContenant('Aucune classe'));
      expect(() => service.construire(TypeExport.absences, anneeId: vide),
          erreurContenant('Aucune classe'));
    });

    test('année ou classe inconnue', () async {
      expect(() => service.construire(TypeExport.eleves, anneeId: 999),
          erreurContenant('Année scolaire introuvable'));
      expect(
        () => service.construire(
          TypeExport.elevesParClasse,
          anneeId: annee,
          options: const OptionsExport(classeId: 999),
        ),
        erreurContenant('n\'existe pas'),
      );
    });

    test('sans le droit d\'exporter : refusé', () async {
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
      final restreint = ServiceExport(Services(gdb, session: session, iterations: 2));
      expect(() => restreint.construire(TypeExport.eleves, anneeId: annee),
          erreurContenant('autorisation'));
      expect(
        () => restreint.listesVierges(
          anneeId: annee,
          options: const OptionsListeVierge(mois: 11),
        ),
        erreurContenant('autorisation'),
      );
    });

    test('un export est inscrit au journal', () async {
      await service.construire(TypeExport.eleves, anneeId: annee);
      final lignes = await gdb.db.query('journal', where: "action = 'export'");
      expect(lignes.length, 1);
      expect(lignes.single['details'], contains('Liste complète des élèves'));
    });
  });

  group('enregistrement vérifié', () {
    test('fichier .xlsx relu, nom horodaté, jamais écrasé', () async {
      final f = await service.construire(TypeExport.eleves, anneeId: annee);
      final a = await service.enregistrer(f, dossier: dossier);
      expect(a.fichier.existsSync(), isTrue);
      expect(a.fichier.path, endsWith('Liste_complete_des_eleves_2026-2027_20261122-103015.xlsx'));
      expect(a.nbFeuilles, 1);
      expect(lireClasseur(a.fichier.readAsBytesSync()).feuilles.length, 1);

      // Même seconde : un second fichier, le premier reste intact.
      final b = await service.enregistrer(f, dossier: dossier);
      expect(b.fichier.path, isNot(a.fichier.path));
      expect(b.fichier.path, endsWith('_2.xlsx'));
      expect(a.fichier.existsSync(), isTrue);
      expect([for (final e in dossier.listSync()) e.path.endsWith('.tmp')], everyElement(isFalse));
    });

    test('un fichier qui ne s\'ouvre pas comme annoncé est supprimé et signalé', () async {
      final f = await service.construire(TypeExport.eleves, anneeId: annee);
      final faux = FichierExcel(
        nomBase: 'Faux',
        octets: f.octets,
        feuilles: const ['Une', 'Deux', 'Trois'],
      );
      await expectLater(
        () => service.enregistrer(faux, dossier: dossier),
        erreurContenant('n\'a pas pu être vérifié'),
      );
      expect(dossier.listSync(), isEmpty, reason: 'aucun fichier douteux n\'est laissé');
    });

    test('contenu qui n\'est pas un classeur : supprimé et signalé', () async {
      final faux = FichierExcel(
        nomBase: 'Abime',
        octets: Uint8List.fromList([1, 2, 3, 4]),
        feuilles: const ['Une'],
      );
      await expectLater(
        () => service.enregistrer(faux, dossier: dossier),
        erreurContenant('n\'a pas pu être vérifié'),
      );
      expect(dossier.listSync(), isEmpty);
    });
  });

  group('listes vierges', () {
    const novembre = OptionsListeVierge(mois: 11);

    Future<List<(FichierExcel, ClasseurLu)>> creer({
      OptionsListeVierge options = novembre,
      int? classeId,
      int? enseignantId,
    }) async {
      final fichiers = await service.listesVierges(
        anneeId: annee,
        options: options,
        classeId: classeId,
        enseignantId: enseignantId,
      );
      return [
        for (final f in fichiers) (f, lireClasseur(f.octets)),
      ];
    }

    test('un fichier par classe et par enseignant, matières validées omises', () async {
      final fichiers = await creer();
      expect(
        [for (final (f, _) in fichiers) f.nomBase]..sort(),
        [
          'Liste notes 10e A BAH Oumar Novembre',
          'Liste notes 10e A DIALLO Aminata Novembre',
          'Liste notes 3e B BAH Oumar Novembre',
        ],
      );
      // DIALLO : Français (dictée validée) est omis ; Histoire (SYLLA) aussi.
      final diallo = fichiers.firstWhere((x) => x.$1.nomBase.contains('DIALLO'));
      expect(diallo.$1.feuilles, ['Maths', feuilleTechnique]);
      expect(diallo.$1.avertissements.length, 2);
      expect(diallo.$1.avertissements.join(' '), contains('Français'));
      expect(diallo.$1.avertissements.join(' '), contains('Histoire'));
      // Les remarques concernent tous les fichiers de l'envoi.
      for (final (f, _) in fichiers) {
        expect(f.avertissements.length, 2);
      }
    });

    test('contenu d\'une liste : en-tête, élèves actifs seulement, colonnes par défaut', () async {
      final fichiers = await creer(classeId: classeA, enseignantId: ens1);
      final (f, lu) = fichiers.single;
      expect(f.feuilles, ['Maths', feuilleTechnique]);
      final feuilleMaths = lu.feuille('Maths')!;
      expect(feuilleMaths.cellule(0, 0).texte, 'Groupe Scolaire Test');
      expect(feuilleMaths.cellule(3, 2).texte, '10e A');
      expect(feuilleMaths.cellule(4, 2).texte, 'Maths');
      expect(feuilleMaths.cellule(5, 2).texte, 'DIALLO Aminata');
      expect(feuilleMaths.cellule(6, 2).texte, 'Novembre');
      expect(feuilleMaths.cellule(ligneEnteteTableau, 3).texte, startsWith('Interrogation 1'));
      expect(feuilleMaths.cellule(ligneEnteteTableau, 4).texte, startsWith('Interrogation 2'));
      expect(feuilleMaths.cellule(premiereLigneEleves, colonneMatricule).texte, '2026-0001');
      expect(feuilleMaths.cellule(premiereLigneEleves + 1, colonneMatricule).texte, '2026-0002');
      expect(feuilleMaths.cellule(premiereLigneEleves + 2, colonneMatricule).vide, isTrue,
          reason: 'SOW est parti');

      final t = lu.feuille(feuilleTechnique)!;
      expect(t.cellule(1, 1).texte, formatListeNotes);
      expect(t.cellule(3, 1).nombre, classeA.toDouble());
      expect(t.cellule(4, 1).nombre, ens1.toDouble());
      expect(t.cellule(8, 1).nombre, maths.toDouble());
      expect(t.cellule(8, 9).nombre, 0, reason: 'évaluation à créer à l\'import');
    });

    test('évaluation existante : sa colonne, son barème et son identifiant', () async {
      final fichiers = await creer(classeId: classeA, enseignantId: ens2);
      final (f, lu) = fichiers.single;
      expect(f.feuilles, ['Dessin', feuilleTechnique]);
      final dessinFeuille = lu.feuille('Dessin')!;
      expect(dessinFeuille.cellule(ligneEnteteTableau, 3).texte, 'Croquis\n(sur 10)');
      expect(dessinFeuille.cellule(ligneEnteteTableau, 4).texte, 'Observations');
      final t = lu.feuille(feuilleTechnique)!;
      expect(t.cellule(8, 4).texte, 'Croquis');
      expect(t.cellule(8, 5).texte, 'devoir');
      expect(t.cellule(8, 7).nombre, 10.0);
      final id = (await s.evaluations.lister(classeId: classeA, matiereId: dessin)).single.evaluation.id;
      expect(t.cellule(8, 9).nombre, id.toDouble());
    });

    test('un enseignant, plusieurs classes : un fichier par classe', () async {
      final fichiers = await creer(enseignantId: ens2);
      expect([for (final (f, _) in fichiers) f.nomBase]..sort(),
          ['Liste notes 10e A BAH Oumar Novembre', 'Liste notes 3e B BAH Oumar Novembre']);
    });

    test('choix de colonnes, composition et sans observations', () async {
      final fichiers = await creer(
        classeId: classeB,
        options: const OptionsListeVierge(
          mois: 12,
          nbInterrogations: 1,
          nbDevoirs: 1,
          avecComposition: true,
          avecObservations: false,
        ),
      );
      final (f, lu) = fichiers.single;
      expect(f.nomBase, endsWith('Décembre'));
      final calculFeuille = lu.feuille('Calcul')!;
      expect([for (var c = 3; c < 7; c++) calculFeuille.cellule(ligneEnteteTableau, c).texte],
          ['Interrogation\n(sur 20)', 'Devoir\n(sur 20)', 'Composition\n(sur 20)', '']);
    });

    test('toutes les matières de l\'enseignant sont validées : rien à créer', () async {
      expect(
        () => service.listesVierges(
          anneeId: annee,
          options: novembre,
          classeId: classeA,
          enseignantId: ens3,
        ),
        erreurContenant('validées'),
      );
    });

    test('mois invalide, enseignant ou classe inconnus', () async {
      expect(
        () => service.listesVierges(anneeId: annee, options: const OptionsListeVierge(mois: 7)),
        erreurContenant('Choisissez un mois'),
      );
      expect(
        () => service.listesVierges(anneeId: annee, options: novembre, enseignantId: 999),
        erreurContenant('Enseignant introuvable'),
      );
      expect(
        () => service.listesVierges(anneeId: annee, options: novembre, classeId: 999),
        erreurContenant('n\'existe pas'),
      );
    });

    test('les listes se sauvegardent en fichiers distincts', () async {
      final fichiers = await service.listesVierges(anneeId: annee, options: novembre);
      final chemins = <String>{};
      for (final f in fichiers) {
        chemins.add((await service.enregistrer(f, dossier: dossier)).fichier.path);
      }
      expect(chemins.length, fichiers.length);
      expect(dossier.listSync().length, fichiers.length);
    });

    test('une matière sans enseignant : fichier à part, case enseignant à remplir', () async {
      await s.matieres.ajouter(classeId: classeB, nom: 'Dessin libre', coefficient: 100);
      final fichiers = await creer(classeId: classeB);
      final sans = fichiers.firstWhere((x) => x.$1.nomBase.contains('sans enseignant'));
      expect(sans.$1.feuilles, ['Dessin libre', feuilleTechnique]);
      final feuille = sans.$2.feuille('Dessin libre')!;
      expect(feuille.cellule(5, 2).vide, isTrue);
      expect(sans.$2.feuille(feuilleTechnique)!.cellule(4, 1).nombre, 0.0);
    });
  });

  group('mois proposé', () {
    test('le mois en cours s\'il est dans l\'année scolaire, sinon octobre', () {
      expect(moisParDefaut(DateTime(2026, 11, 22)), 11);
      expect(moisParDefaut(DateTime(2027, 1, 5)), 1);
      expect(moisParDefaut(DateTime(2027, 6, 30)), 6);
      expect(moisParDefaut(DateTime(2027, 8, 1)), 10);
      expect(moisParDefaut(DateTime(2027, 9, 15)), 10);
    });
  });
}
