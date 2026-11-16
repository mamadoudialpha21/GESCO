import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/depots/annee_depot.dart';
import 'package:gesco/data/depots/classe_depot.dart';
import 'package:gesco/data/depots/eleve_depot.dart';
import 'package:gesco/data/depots/matiere_depot.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/images.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher erreurContenant(String texte) => throwsA(
      isA<ErreurGesco>().having((e) => e.message, 'message', contains(texte)),
    );

final Matcher uneErreur = throwsA(isA<ErreurGesco>());

Uint8List png([int taille = 12]) {
  final octets = Uint8List(taille);
  octets.setRange(0, 8, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  return octets;
}

Eleve eleve(
  String matricule, {
  String nom = 'DIALLO',
  String prenom = 'Aminata',
  String sexe = 'F',
  String? naissance,
  Uint8List? photo,
}) =>
    Eleve(
      matricule: matricule,
      nom: nom,
      prenom: prenom,
      sexe: sexe,
      dateNaissance: naissance,
      photo: photo,
    );

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

  setUp(() async {
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    db = gdb.db;
    final horloge = DateTime(2026, 10, 1, 8);
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

  /// Inscrit un élève et retourne sa ligne de liste.
  Future<EleveInscrit> inscrireEtLire(
    Eleve e, {
    Classe? classe,
    int? annee,
  }) async {
    final a = annee ?? anneeId;
    final c = classe ?? classeA;
    final inscription = await eleves.inscrire(e, anneeId: a, classeId: c.id);
    final liste = await eleves.lister(a);
    return liste.firstWhere((x) => x.inscriptionId == inscription);
  }

  Future<int> noter(int inscription, int matiere, int mois, int valeur) =>
      db.insert('note', {
        'inscription_id': inscription,
        'matiere_id': matiere,
        'mois': mois,
        'etat': 'saisie',
        'valeur': valeur,
        'modifie_le': '2026-10-02',
      });

  group('inscrire', () {
    test('enregistre la fiche et l\'inscription', () async {
      final inscription = await eleves.inscrire(
        Eleve(
          matricule: '  2026-0001 ',
          nom: ' Diallo ',
          prenom: ' Aminata ',
          sexe: 'F',
          dateNaissance: '2011-03-05',
          lieuNaissance: 'Conakry',
          nomPere: 'Alpha Diallo',
          nomMere: 'Fatou Bah',
          contactParent: '+224 600 00 00 00',
          adresse: 'Tombolia',
          photo: png(),
        ),
        anneeId: anneeId,
        classeId: classeA.id,
      );
      expect(inscription, greaterThan(0));

      final liste = await eleves.lister(anneeId);
      expect(liste.length, 1);
      expect(liste.single.matricule, '2026-0001');
      expect(liste.single.nom, 'Diallo');
      expect(liste.single.prenom, 'Aminata');
      expect(liste.single.sexe, 'F');
      expect(liste.single.classeNom, '10e A');
      expect(liste.single.classeId, classeA.id);
      expect(liste.single.dateNaissance, '2011-03-05');
      expect(liste.single.nomComplet, 'DIALLO Aminata');

      final fiche = (await eleves.obtenir(liste.single.eleveId))!;
      expect(fiche.lieuNaissance, 'Conakry');
      expect(fiche.nomPere, 'Alpha Diallo');
      expect(fiche.nomMere, 'Fatou Bah');
      expect(fiche.contactParent, '+224 600 00 00 00');
      expect(fiche.adresse, 'Tombolia');
      expect(fiche.photo, png());
    });

    test('les champs facultatifs vides sont relus comme des chaînes vides',
        () async {
      final e = await inscrireEtLire(eleve('M001'));
      final fiche = (await eleves.obtenir(e.eleveId))!;
      expect(fiche.lieuNaissance, '');
      expect(fiche.nomPere, '');
      expect(fiche.adresse, '');
      expect(fiche.dateNaissance, isNull);
      expect(fiche.photo, isNull);
    });

    test('fiche invalide refusée, rien n\'est créé', () async {
      await expectLater(
        eleves.inscrire(eleve('M001', nom: ''), anneeId: anneeId, classeId: classeA.id),
        erreurContenant('nom est obligatoire'),
      );
      await expectLater(
        eleves.inscrire(
          eleve('M001', naissance: '2027-01-01'),
          anneeId: anneeId,
          classeId: classeA.id,
        ),
        erreurContenant('futur'),
      );
      expect(await db.query('eleve'), isEmpty);
      expect(await db.query('inscription'), isEmpty);
    });

    test('matricule déjà utilisé (casse ignorée) : refusé, rien n\'est créé',
        () async {
      await inscrireEtLire(eleve('M001'));
      await expectLater(
        eleves.inscrire(eleve('m001', prenom: 'Autre'), anneeId: anneeId, classeId: classeA.id),
        erreurContenant('déjà utilisé'),
      );
      expect((await db.query('eleve')).length, 1);
      expect((await db.query('inscription')).length, 1);
    });

    test('classe d\'une autre année ou inconnue refusée, rien n\'est créé',
        () async {
      final autreAnnee = await annees.creer('2027-2028');
      final classeAutreAnnee = await classes.creer(anneeId: autreAnnee.id, nom: '11e A');
      await expectLater(
        eleves.inscrire(eleve('M001'), anneeId: anneeId, classeId: classeAutreAnnee.id),
        erreurContenant('n\'existe pas pour l\'année'),
      );
      await expectLater(
        eleves.inscrire(eleve('M001'), anneeId: anneeId, classeId: 999),
        uneErreur,
      );
      expect(await db.query('eleve'), isEmpty);
    });

    test('photo invalide ou trop grande refusée ; exactement 1 Mo accepté',
        () async {
      await expectLater(
        eleves.inscrire(
          eleve('M001', photo: Uint8List.fromList([1, 2, 3])),
          anneeId: anneeId,
          classeId: classeA.id,
        ),
        erreurContenant('PNG ou JPEG'),
      );
      await expectLater(
        eleves.inscrire(
          eleve('M001', photo: png(tailleMaxPhoto + 1)),
          anneeId: anneeId,
          classeId: classeA.id,
        ),
        erreurContenant('trop volumineux'),
      );
      expect(await db.query('eleve'), isEmpty);
      await eleves.inscrire(
        eleve('M001', photo: png(tailleMaxPhoto)),
        anneeId: anneeId,
        classeId: classeA.id,
      );
      expect((await db.query('eleve')).length, 1);
    });

    test('aucune limite artificielle au nombre d\'élèves', () async {
      for (var i = 1; i <= 150; i++) {
        await eleves.inscrire(
          eleve('M$i', nom: 'Nom$i'),
          anneeId: anneeId,
          classeId: classeA.id,
        );
      }
      expect((await eleves.lister(anneeId)).length, 150);
    });
  });

  group('lister', () {
    test('tri par nom puis prénom, sans tenir compte des accents ni de la casse',
        () async {
      await inscrireEtLire(eleve('m1', nom: 'Bah', prenom: 'Zoé'));
      await inscrireEtLire(eleve('m2', nom: 'DIALLO', prenom: 'Aminata'));
      await inscrireEtLire(eleve('m3', nom: 'Diallo', prenom: 'Binta'));
      await inscrireEtLire(eleve('m4', nom: 'Éloi', prenom: 'Paul'));
      await inscrireEtLire(eleve('m5', nom: 'Camara', prenom: 'Élodie'));
      await inscrireEtLire(eleve('m6', nom: 'camara', prenom: 'Alice'));
      final ordre = (await eleves.lister(anneeId)).map((e) => e.matricule);
      expect(ordre, ['m1', 'm6', 'm5', 'm2', 'm3', 'm4']);
    });

    test('filtre par classe', () async {
      await inscrireEtLire(eleve('M1', nom: 'A'), classe: classeA);
      await inscrireEtLire(eleve('M2', nom: 'B'), classe: classeB);
      await inscrireEtLire(eleve('M3', nom: 'C'), classe: classeB);
      expect((await eleves.lister(anneeId)).length, 3);
      expect(
        (await eleves.lister(anneeId, classeId: classeA.id)).map((e) => e.matricule),
        ['M1'],
      );
      expect(
        (await eleves.lister(anneeId, classeId: classeB.id)).map((e) => e.matricule),
        ['M2', 'M3'],
      );
    });

    test('chaque année a sa propre liste', () async {
      final eleve1 = await inscrireEtLire(eleve('M1'));
      final autreAnnee = await annees.creer('2027-2028');
      final classe2 = await classes.creer(anneeId: autreAnnee.id, nom: '11e A');
      expect(await eleves.lister(autreAnnee.id), isEmpty);
      await eleves.inscrireExistant(
        eleveId: eleve1.eleveId,
        anneeId: autreAnnee.id,
        classeId: classe2.id,
      );
      expect((await eleves.lister(autreAnnee.id)).single.classeNom, '11e A');
      expect((await eleves.lister(anneeId)).single.classeNom, '10e A');
    });
  });

  test('obtenir : élève inconnu', () async {
    expect(await eleves.obtenir(999), isNull);
  });

  test('matricules : liste de tous les matricules', () async {
    await inscrireEtLire(eleve('M1', nom: 'A'));
    await inscrireEtLire(eleve('M2', nom: 'B'));
    expect(await eleves.matricules(), unorderedEquals(['M1', 'M2']));
  });

  group('modifier', () {
    test('met à jour la fiche et permet de retirer la photo et la date',
        () async {
      final e = await inscrireEtLire(
        eleve('M1', naissance: '2011-03-05', photo: png()),
      );
      final fiche = (await eleves.obtenir(e.eleveId))!;
      expect(fiche.photo, isNotNull);
      expect(fiche.dateNaissance, '2011-03-05');

      await eleves.modifier(
        fiche.copyWith(
          nom: 'Bah',
          adresse: 'Matoto',
          supprimerPhoto: true,
          supprimerDate: true,
        ),
      );
      final apres = (await eleves.obtenir(e.eleveId))!;
      expect(apres.nom, 'Bah');
      expect(apres.adresse, 'Matoto');
      expect(apres.photo, isNull);
      expect(apres.dateNaissance, isNull);
      expect(apres.matricule, 'M1');
    });

    test('sans toucher à la photo, elle est conservée', () async {
      final e = await inscrireEtLire(eleve('M1', photo: png()));
      final fiche = (await eleves.obtenir(e.eleveId))!;
      await eleves.modifier(fiche.copyWith(prenom: 'Autre'));
      final apres = (await eleves.obtenir(e.eleveId))!;
      expect(apres.photo, png());
      expect(apres.prenom, 'Autre');
    });

    test('garder son propre matricule est permis, prendre celui d\'un autre est refusé',
        () async {
      final a = await inscrireEtLire(eleve('M1', nom: 'A'));
      await inscrireEtLire(eleve('M2', nom: 'B'));
      final fiche = (await eleves.obtenir(a.eleveId))!;
      await eleves.modifier(fiche.copyWith(prenom: 'Nouveau'));
      await expectLater(
        eleves.modifier(fiche.copyWith(matricule: 'm2')),
        erreurContenant('déjà utilisé'),
      );
      expect((await eleves.obtenir(a.eleveId))!.matricule, 'M1');
    });

    test('fiche invalide ou élève inconnu refusés', () async {
      final a = await inscrireEtLire(eleve('M1'));
      final fiche = (await eleves.obtenir(a.eleveId))!;
      await expectLater(eleves.modifier(fiche.copyWith(nom: ' ')), erreurContenant('obligatoire'));
      await expectLater(
        eleves.modifier(
          const Eleve(id: 999, matricule: 'Z', nom: 'Z', prenom: 'Z', sexe: 'M'),
        ),
        erreurContenant('introuvable'),
      );
    });

    test('changer de classe (sans notes)', () async {
      final e = await inscrireEtLire(eleve('M1'));
      final fiche = (await eleves.obtenir(e.eleveId))!;
      await eleves.modifier(
        fiche.copyWith(prenom: 'Changée'),
        inscriptionId: e.inscriptionId,
        nouvelleClasseId: classeB.id,
      );
      final apres = (await eleves.lister(anneeId)).single;
      expect(apres.classeNom, '10e B');
      expect(apres.prenom, 'Changée');
    });

    test('changer de classe vers la même classe ne fait rien', () async {
      final e = await inscrireEtLire(eleve('M1'));
      final fiche = (await eleves.obtenir(e.eleveId))!;
      await eleves.modifier(
        fiche,
        inscriptionId: e.inscriptionId,
        nouvelleClasseId: classeA.id,
      );
      expect((await eleves.lister(anneeId)).single.classeNom, '10e A');
    });

    test('changer de classe refusé s\'il y a des notes : rien n\'est modifié',
        () async {
      final e = await inscrireEtLire(eleve('M1', prenom: 'Avant'));
      final maths = await matieres.ajouter(
        classeId: classeA.id,
        nom: 'Maths',
        coefficient: 400,
      );
      await noter(e.inscriptionId, maths.id, 10, 1500);
      final fiche = (await eleves.obtenir(e.eleveId))!;

      await expectLater(
        eleves.modifier(
          fiche.copyWith(prenom: 'Après'),
          inscriptionId: e.inscriptionId,
          nouvelleClasseId: classeB.id,
        ),
        erreurContenant('Impossible de changer de classe'),
      );
      // Tout ou rien : la fiche n'a pas été modifiée non plus.
      expect((await eleves.obtenir(e.eleveId))!.prenom, 'Avant');
      expect((await eleves.lister(anneeId)).single.classeNom, '10e A');
      expect((await db.query('note')).length, 1);
    });

    test('changer de classe vers une classe d\'une autre année refusé', () async {
      final e = await inscrireEtLire(eleve('M1'));
      final autreAnnee = await annees.creer('2027-2028');
      final classeAutre = await classes.creer(anneeId: autreAnnee.id, nom: '11e A');
      final fiche = (await eleves.obtenir(e.eleveId))!;
      await expectLater(
        eleves.modifier(
          fiche,
          inscriptionId: e.inscriptionId,
          nouvelleClasseId: classeAutre.id,
        ),
        erreurContenant('n\'existe pas pour l\'année'),
      );
      expect((await eleves.lister(anneeId)).single.classeNom, '10e A');
    });

    test('changer de classe sans indiquer l\'inscription est refusé', () async {
      final e = await inscrireEtLire(eleve('M1'));
      final fiche = (await eleves.obtenir(e.eleveId))!;
      await expectLater(
        eleves.modifier(fiche, nouvelleClasseId: classeB.id),
        erreurContenant('Inscription introuvable'),
      );
    });
  });

  group('réinscription', () {
    late AnneeScolaire annee2;
    late Classe classe2;

    setUp(() async {
      annee2 = await annees.creer('2027-2028');
      classe2 = await classes.creer(anneeId: annee2.id, nom: '11e A');
    });

    test('nonInscrits : élèves connus pas encore inscrits dans l\'année', () async {
      await inscrireEtLire(eleve('M1', nom: 'Bah'));
      await inscrireEtLire(eleve('M2', nom: 'Camara'));
      final candidats = await eleves.nonInscrits(annee2.id);
      expect(candidats.map((e) => e.matricule), ['M1', 'M2']);
      expect(await eleves.nonInscrits(anneeId), isEmpty);
    });

    test('inscrireExistant : l\'élève rejoint la nouvelle année, plus dans nonInscrits',
        () async {
      final e = await inscrireEtLire(eleve('M1'));
      await eleves.inscrireExistant(
        eleveId: e.eleveId,
        anneeId: annee2.id,
        classeId: classe2.id,
      );
      expect((await eleves.lister(annee2.id)).single.eleveId, e.eleveId);
      expect(await eleves.nonInscrits(annee2.id), isEmpty);
      // Sa fiche est unique, ses deux inscriptions sont distinctes.
      expect((await db.query('eleve')).length, 1);
      expect((await db.query('inscription')).length, 2);
    });

    test('déjà inscrit dans l\'année : refusé', () async {
      final e = await inscrireEtLire(eleve('M1'));
      await expectLater(
        eleves.inscrireExistant(eleveId: e.eleveId, anneeId: anneeId, classeId: classeB.id),
        erreurContenant('déjà inscrit'),
      );
    });

    test('élève inconnu ou classe d\'une autre année refusés', () async {
      final e = await inscrireEtLire(eleve('M1'));
      await expectLater(
        eleves.inscrireExistant(eleveId: 999, anneeId: annee2.id, classeId: classe2.id),
        erreurContenant('introuvable'),
      );
      await expectLater(
        eleves.inscrireExistant(eleveId: e.eleveId, anneeId: annee2.id, classeId: classeA.id),
        erreurContenant('n\'existe pas pour l\'année'),
      );
    });

    test('les notes de l\'ancienne année restent rattachées à l\'ancienne inscription',
        () async {
      final e = await inscrireEtLire(eleve('M1'));
      final maths = await matieres.ajouter(classeId: classeA.id, nom: 'Maths', coefficient: 400);
      await noter(e.inscriptionId, maths.id, 10, 1500);
      final nouvelle = await eleves.inscrireExistant(
        eleveId: e.eleveId,
        anneeId: annee2.id,
        classeId: classe2.id,
      );
      expect(await eleves.compterNotes(e.inscriptionId), 1);
      expect(await eleves.compterNotes(nouvelle), 0);
    });
  });

  group('supprimerInscription', () {
    test('sans notes : l\'inscription et la fiche sont supprimées', () async {
      final e = await inscrireEtLire(eleve('M1'));
      final fichesSupprimees = await eleves.supprimerInscription(e.inscriptionId);
      expect(fichesSupprimees, isTrue);
      expect(await eleves.lister(anneeId), isEmpty);
      expect(await db.query('eleve'), isEmpty);
    });

    test('si l\'élève a une autre inscription, sa fiche est conservée', () async {
      final e = await inscrireEtLire(eleve('M1'));
      final annee2 = await annees.creer('2027-2028');
      final classe2 = await classes.creer(anneeId: annee2.id, nom: '11e A');
      await eleves.inscrireExistant(
        eleveId: e.eleveId,
        anneeId: annee2.id,
        classeId: classe2.id,
      );
      final fichesSupprimees = await eleves.supprimerInscription(e.inscriptionId);
      expect(fichesSupprimees, isFalse);
      expect(await eleves.lister(anneeId), isEmpty);
      expect((await eleves.lister(annee2.id)).length, 1);
      expect((await db.query('eleve')).length, 1);
    });

    test('avec des notes : refusé tant qu\'on ne le demande pas explicitement',
        () async {
      final e = await inscrireEtLire(eleve('M1'));
      final maths = await matieres.ajouter(classeId: classeA.id, nom: 'Maths', coefficient: 400);
      await noter(e.inscriptionId, maths.id, 10, 1500);
      await noter(e.inscriptionId, maths.id, 11, 1200);
      expect(await eleves.compterNotes(e.inscriptionId), 2);

      await expectLater(
        eleves.supprimerInscription(e.inscriptionId),
        erreurContenant('2 notes'),
      );
      expect((await eleves.lister(anneeId)).length, 1);
      expect((await db.query('note')).length, 2);
    });

    test('avecNotes : supprime aussi ses notes, jamais celles des autres',
        () async {
      final a = await inscrireEtLire(eleve('M1', nom: 'A'));
      final b = await inscrireEtLire(eleve('M2', nom: 'B'));
      final maths = await matieres.ajouter(classeId: classeA.id, nom: 'Maths', coefficient: 400);
      await noter(a.inscriptionId, maths.id, 10, 1500);
      await noter(a.inscriptionId, maths.id, 11, 1200);
      await noter(b.inscriptionId, maths.id, 10, 900);

      final supprimee = await eleves.supprimerInscription(a.inscriptionId, avecNotes: true);
      expect(supprimee, isTrue);

      expect((await eleves.lister(anneeId)).map((e) => e.matricule), ['M2']);
      final notes = await db.query('note');
      expect(notes.length, 1);
      expect(notes.single['inscription_id'], b.inscriptionId);
      expect(notes.single['valeur'], 900);
      expect(await gdb.verifierIntegrite(), isEmpty);
    });

    test('inscription inconnue refusée', () async {
      await expectLater(eleves.supprimerInscription(999), erreurContenant('introuvable'));
    });
  });

  test('la classe d\'un élève inscrit ne peut pas être supprimée', () async {
    await inscrireEtLire(eleve('M1'));
    await expectLater(classes.supprimer(classeA.id), erreurContenant('1 élève'));
    // Après suppression de l'élève, la classe peut l'être.
    final e = (await eleves.lister(anneeId)).single;
    await eleves.supprimerInscription(e.inscriptionId);
    await classes.supprimer(classeA.id);
  });
}
