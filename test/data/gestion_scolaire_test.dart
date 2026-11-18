import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/controle.dart';
import 'package:gesco/data/depots/annee_depot.dart';
import 'package:gesco/data/depots/classe_depot.dart';
import 'package:gesco/data/depots/eleve_depot.dart';
import 'package:gesco/data/depots/enseignant_depot.dart';
import 'package:gesco/data/depots/etablissement_depot.dart';
import 'package:gesco/data/depots/matiere_depot.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/images.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher erreurContenant(String texte) => throwsA(
      isA<ErreurGesco>().having((e) => e.message, 'message', contains(texte)),
    );

Uint8List png([int taille = 12]) {
  final octets = Uint8List(taille);
  octets.setRange(0, 8, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  return octets;
}

class _AucuneAutorisation implements Autorisations {
  const _AucuneAutorisation();

  @override
  bool peut(Permission p) => false;

  @override
  bool get aUtilisateur => true;

  @override
  int? get enseignantLimite => null;
}

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Database db;
  late EtablissementDepot etablissements;
  late AnneeDepot annees;
  late ClasseDepot classes;
  late MatiereDepot matieres;
  late EleveDepot eleves;
  late EnseignantDepot enseignants;
  late int anneeId;

  setUp(() async {
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    db = gdb.db;
    etablissements = EtablissementDepot(db);
    annees = AnneeDepot(db, maintenant: () => DateTime.utc(2026, 10, 1, 8));
    classes = ClasseDepot(db);
    matieres = MatiereDepot(db);
    eleves = EleveDepot(db, maintenant: () => DateTime(2026, 10, 1, 8));
    enseignants = EnseignantDepot(db);
    anneeId = (await annees.creer('2026-2027')).id;
  });

  tearDown(() async {
    await gdb.fermer();
  });

  Future<int> prof(String nom) =>
      enseignants.creer(Enseignant(nom: nom, prenom: 'Alpha'));

  group('établissement : directeur, devise, signature, cachet', () {
    test('tous les champs sont enregistrés puis relus', () async {
      await etablissements.enregistrer(
        Etablissement(
          nom: 'Groupe Scolaire Test',
          directeur: '  Mme Camara  ',
          devise: ' Travail - Justice - Solidarité ',
          infosAdmin: 'Agrément n° 123\nBP 45 Conakry',
          signatureDirecteur: png(),
          cachet: png(20),
        ),
      );
      final e = await etablissements.lire();
      expect(e.directeur, 'Mme Camara');
      expect(e.devise, 'Travail - Justice - Solidarité');
      expect(e.infosAdmin, 'Agrément n° 123\nBP 45 Conakry');
      expect(e.signatureDirecteur, png());
      expect(e.cachet, png(20));
    });

    test('la fiche vide a des champs vides', () async {
      final e = await etablissements.lire();
      expect(e.directeur, '');
      expect(e.devise, '');
      expect(e.infosAdmin, '');
      expect(e.signatureDirecteur, isNull);
      expect(e.cachet, isNull);
    });

    test('supprimer la signature et le cachet', () async {
      await etablissements.enregistrer(
        Etablissement(nom: 'X', signatureDirecteur: png(), cachet: png()),
      );
      final e = await etablissements.lire();
      await etablissements.enregistrer(
        e.copyWith(supprimerSignature: true, supprimerCachet: true),
      );
      final apres = await etablissements.lire();
      expect(apres.signatureDirecteur, isNull);
      expect(apres.cachet, isNull);
      expect(apres.nom, 'X');
    });

    test('signature ou cachet invalides refusés, rien n\'est modifié', () async {
      await etablissements.enregistrer(const Etablissement(nom: 'Avant'));
      await expectLater(
        etablissements.enregistrer(
          Etablissement(nom: 'Après', signatureDirecteur: Uint8List.fromList([1, 2])),
        ),
        erreurContenant('La signature'),
      );
      await expectLater(
        etablissements.enregistrer(
          Etablissement(nom: 'Après', cachet: Uint8List.fromList([1, 2])),
        ),
        erreurContenant('Le cachet'),
      );
      expect((await etablissements.lire()).nom, 'Avant');
    });

    test('limites de taille des images', () async {
      await etablissements.enregistrer(
        Etablissement(nom: 'X', cachet: png(tailleMaxLogo)),
      );
      await expectLater(
        etablissements.enregistrer(
          Etablissement(nom: 'X', cachet: png(tailleMaxLogo + 1)),
        ),
        erreurContenant('trop volumineux'),
      );
    });

    test('longueurs maximales du directeur, de la devise et des informations',
        () async {
      await expectLater(
        etablissements.enregistrer(Etablissement(directeur: 'x' * 121)),
        erreurContenant('Le nom du directeur est trop long'),
      );
      await expectLater(
        etablissements.enregistrer(Etablissement(devise: 'x' * 201)),
        erreurContenant('La devise est trop long'),
      );
      await expectLater(
        etablissements.enregistrer(Etablissement(infosAdmin: 'x' * 601)),
        erreurContenant('Les informations administratives'),
      );
      await etablissements.enregistrer(Etablissement(directeur: 'x' * 120));
      expect((await etablissements.lire()).directeur.length, 120);
    });

    test('sans permission, la fiche ne peut pas être modifiée', () async {
      final refuse = EtablissementDepot(
        db,
        controle: const Controle(autorisations: _AucuneAutorisation()),
      );
      await expectLater(
        refuse.enregistrer(const Etablissement(nom: 'Pirate')),
        erreurContenant('autorisation'),
      );
    });
  });

  group('années : renommer, archiver, effectifs', () {
    test('renommer une année', () async {
      await annees.renommer(anneeId, ' 2026/2027 ');
      expect((await annees.obtenir(anneeId))!.libelle, '2026/2027');
    });

    test('renommer : doublon, libellé vide ou année inconnue refusés', () async {
      final autre = await annees.creer('2027-2028');
      await expectLater(
        annees.renommer(autre.id, '2026-2027'),
        erreurContenant('existe déjà'),
      );
      await expectLater(annees.renommer(autre.id, '  '), throwsA(isA<ErreurGesco>()));
      await expectLater(annees.renommer(999, 'X'), erreurContenant('introuvable'));
      // Garder son propre nom est permis.
      await annees.renommer(autre.id, '2027-2028');
      expect((await annees.obtenir(autre.id))!.libelle, '2027-2028');
    });

    test('archiver : l\'année active est refusée', () async {
      await expectLater(
        annees.archiver(anneeId),
        erreurContenant('c\'est l\'année active'),
      );
      expect((await annees.obtenir(anneeId))!.archivee, isFalse);
    });

    test('archiver une année terminée, puis la rouvrir', () async {
      await annees.creer('2027-2028', activer: true);
      await annees.archiver(anneeId);
      expect((await annees.obtenir(anneeId))!.archivee, isTrue);
      await annees.archiver(anneeId, archivee: false);
      expect((await annees.obtenir(anneeId))!.archivee, isFalse);
    });

    test('une année archivée ne peut pas être activée avant réouverture',
        () async {
      final suivante = await annees.creer('2027-2028', activer: true);
      await annees.archiver(anneeId);
      await expectLater(annees.activer(anneeId), erreurContenant('archivée'));
      await annees.archiver(anneeId, archivee: false);
      await annees.activer(anneeId);
      expect((await annees.active())!.id, anneeId);
      expect((await annees.obtenir(suivante.id))!.active, isFalse);
    });

    test('année archivée : les notes ne sont plus modifiables (base de données)',
        () async {
      final c = await classes.creer(anneeId: anneeId, nom: '10e A');
      final m = await matieres.ajouter(classeId: c.id, nom: 'Maths', coefficient: 400);
      final ins = await eleves.inscrire(
        const Eleve(matricule: 'M1', nom: 'A', prenom: 'B', sexe: 'F'),
        anneeId: anneeId,
        classeId: c.id,
      );
      await annees.creer('2027-2028', activer: true);
      await annees.archiver(anneeId);
      await expectLater(
        db.insert('note', {
          'inscription_id': ins,
          'matiere_id': m.id,
          'mois': 10,
          'etat': 'saisie',
          'valeur': 1000,
          'modifie_le': '2026-10-02',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await annees.archiver(anneeId, archivee: false);
      await db.insert('note', {
        'inscription_id': ins,
        'matiere_id': m.id,
        'mois': 10,
        'etat': 'saisie',
        'valeur': 1000,
        'modifie_le': '2026-10-02',
      });
    });

    test('archiver une année inconnue est refusé', () async {
      await expectLater(annees.archiver(999), erreurContenant('introuvable'));
    });

    test('effectifs d\'une année vide', () async {
      final e = await annees.effectifs(anneeId);
      expect(e.classes, 0);
      expect(e.eleves, 0);
      expect(e.actifs, 0);
    });

    test('effectifs : classes, élèves, filles et garçons', () async {
      final c1 = await classes.creer(anneeId: anneeId, nom: '10e A');
      final c2 = await classes.creer(anneeId: anneeId, nom: '10e B');
      for (final (matricule, sexe, classe) in [
        ('M1', 'F', c1),
        ('M2', 'M', c1),
        ('M3', 'F', c2),
      ]) {
        await eleves.inscrire(
          Eleve(matricule: matricule, nom: 'N$matricule', prenom: 'P', sexe: sexe),
          anneeId: anneeId,
          classeId: classe.id,
        );
      }
      final e = await annees.effectifs(anneeId);
      expect(e.classes, 2);
      expect(e.eleves, 3);
      expect(e.filles, 2);
      expect(e.garcons, 1);
      expect(e.departs, 0);
      expect(e.abandons, 0);
      expect(e.actifs, 3);
    });

    test('copier une année reprend capacité, professeur principal, barèmes et matières facultatives',
        () async {
      final p = await prof('Barry');
      final c = await classes.creer(
        anneeId: anneeId,
        nom: '10e A',
        niveau: '10e',
        reglages: ReglagesClasse(capacite: 40, profPrincipalId: p),
      );
      await matieres.ajouter(
        classeId: c.id,
        nom: 'Maths',
        coefficient: 400,
        bareme: 40,
        enseignantId: p,
      );
      await matieres.ajouter(
        classeId: c.id,
        nom: 'Dessin',
        coefficient: 100,
        facultative: true,
      );
      final suivante = await annees.creer('2027-2028', copierDepuisAnneeId: anneeId);
      final copie = (await classes.lister(suivante.id)).single;
      expect(copie.classe.nom, '10e A');
      expect(copie.classe.capacite, 40);
      expect(copie.classe.profPrincipalId, p);
      final liste = await matieres.lister(copie.classe.id);
      expect(liste.map((m) => m.nom), ['Maths', 'Dessin']);
      expect(liste[0].bareme, 40);
      expect(liste[0].enseignantId, p);
      expect(liste[1].facultative, isTrue);
      expect(liste[1].enseignantId, isNull);
      // Aucun élève ni note n'est copié.
      expect(copie.nbEleves, 0);
    });
  });

  group('classes : capacité et professeur principal', () {
    test('créer avec capacité et professeur principal', () async {
      final p = await prof('Barry');
      final c = await classes.creer(
        anneeId: anneeId,
        nom: '10e A',
        reglages: ReglagesClasse(capacite: 45, profPrincipalId: p),
      );
      expect(c.capacite, 45);
      expect(c.profPrincipalId, p);
      final relue = (await classes.obtenir(c.id))!;
      expect(relue.capacite, 45);
      expect(relue.profPrincipalId, p);
      final resume = (await classes.lister(anneeId)).single;
      expect(resume.profPrincipalNom, 'Barry Alpha');
    });

    test('sans réglages : capacité non limitée et aucun professeur principal',
        () async {
      final c = await classes.creer(anneeId: anneeId, nom: '10e A');
      expect(c.capacite, isNull);
      expect(c.profPrincipalId, isNull);
      expect((await classes.lister(anneeId)).single.profPrincipalNom, '');
    });

    test('capacité hors limites refusée (0, négative, plus de 500)', () async {
      for (final capacite in [0, -1, 501]) {
        await expectLater(
          classes.creer(
            anneeId: anneeId,
            nom: 'C$capacite',
            reglages: ReglagesClasse(capacite: capacite),
          ),
          erreurContenant('entre 1 et 500'),
        );
      }
      expect(await classes.lister(anneeId), isEmpty);
      await classes.creer(
        anneeId: anneeId,
        nom: 'Max',
        reglages: const ReglagesClasse(capacite: 500),
      );
    });

    test('professeur principal inconnu refusé', () async {
      await expectLater(
        classes.creer(
          anneeId: anneeId,
          nom: '10e A',
          reglages: const ReglagesClasse(profPrincipalId: 999),
        ),
        erreurContenant('Enseignant introuvable'),
      );
      expect(await classes.lister(anneeId), isEmpty);
    });

    test('modifier la capacité et le professeur principal', () async {
      final p = await prof('Barry');
      final c = await classes.creer(anneeId: anneeId, nom: '10e A');
      await classes.modifier(
        c.id,
        nom: '10e A',
        niveau: '',
        reglages: ReglagesClasse(capacite: 30, profPrincipalId: p),
      );
      expect((await classes.obtenir(c.id))!.capacite, 30);
      expect((await classes.obtenir(c.id))!.profPrincipalId, p);
      // Retirer les deux.
      await classes.modifier(
        c.id,
        nom: '10e A',
        niveau: '',
        reglages: const ReglagesClasse(),
      );
      expect((await classes.obtenir(c.id))!.capacite, isNull);
      expect((await classes.obtenir(c.id))!.profPrincipalId, isNull);
    });

    test('modifier le nom sans réglages garde la capacité et le professeur',
        () async {
      final p = await prof('Barry');
      final c = await classes.creer(
        anneeId: anneeId,
        nom: '10e A',
        reglages: ReglagesClasse(capacite: 30, profPrincipalId: p),
      );
      await classes.modifier(c.id, nom: '10e Z', niveau: '10e');
      final relue = (await classes.obtenir(c.id))!;
      expect(relue.nom, '10e Z');
      expect(relue.capacite, 30);
      expect(relue.profPrincipalId, p);
    });

    test('capacité inférieure à l\'effectif actuel refusée', () async {
      final c = await classes.creer(anneeId: anneeId, nom: '10e A');
      for (var i = 0; i < 3; i++) {
        await eleves.inscrire(
          Eleve(matricule: 'M$i', nom: 'N$i', prenom: 'P', sexe: 'F'),
          anneeId: anneeId,
          classeId: c.id,
        );
      }
      await expectLater(
        classes.modifier(
          c.id,
          nom: c.nom,
          niveau: c.niveau,
          reglages: const ReglagesClasse(capacite: 2),
        ),
        erreurContenant('inférieure à l\'effectif'),
      );
      await classes.modifier(
        c.id,
        nom: c.nom,
        niveau: c.niveau,
        reglages: const ReglagesClasse(capacite: 3),
      );
      expect((await classes.obtenir(c.id))!.capacite, 3);
    });

    test('un élève parti ne compte pas dans l\'effectif pour la capacité',
        () async {
      final c = await classes.creer(anneeId: anneeId, nom: '10e A');
      final a = await eleves.inscrire(
        const Eleve(matricule: 'M1', nom: 'A', prenom: 'P', sexe: 'F'),
        anneeId: anneeId,
        classeId: c.id,
      );
      await eleves.inscrire(
        const Eleve(matricule: 'M2', nom: 'B', prenom: 'P', sexe: 'F'),
        anneeId: anneeId,
        classeId: c.id,
      );
      await eleves.enregistrerSortie(a, StatutInscription.depart);
      await classes.modifier(
        c.id,
        nom: c.nom,
        niveau: c.niveau,
        reglages: const ReglagesClasse(capacite: 1),
      );
      expect((await classes.obtenir(c.id))!.capacite, 1);
    });

    test('effectifs de la liste : total, actifs, filles, garçons', () async {
      final c = await classes.creer(anneeId: anneeId, nom: '10e A');
      final ids = <int>[];
      for (final (matricule, sexe) in [('M1', 'F'), ('M2', 'M'), ('M3', 'M')]) {
        ids.add(
          await eleves.inscrire(
            Eleve(matricule: matricule, nom: 'N$matricule', prenom: 'P', sexe: sexe),
            anneeId: anneeId,
            classeId: c.id,
          ),
        );
      }
      await eleves.enregistrerSortie(ids[1], StatutInscription.abandon);
      final r = (await classes.lister(anneeId)).single;
      expect(r.nbEleves, 3);
      expect(r.nbActifs, 2);
      expect(r.nbFilles, 1);
      expect(r.nbGarcons, 1);
    });

    test('sans permission, la capacité ne peut pas être modifiée', () async {
      final c = await classes.creer(anneeId: anneeId, nom: '10e A');
      final refuse = ClasseDepot(
        db,
        controle: const Controle(autorisations: _AucuneAutorisation()),
      );
      await expectLater(
        refuse.modifier(
          c.id,
          nom: c.nom,
          niveau: c.niveau,
          reglages: const ReglagesClasse(capacite: 10),
        ),
        erreurContenant('autorisation'),
      );
    });
  });

  group('matières : barème, facultative, enseignant', () {
    late Classe classe;

    setUp(() async {
      classe = await classes.creer(anneeId: anneeId, nom: '10e A');
    });

    test('valeurs par défaut : barème 20, obligatoire, sans enseignant', () async {
      final m = await matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
      expect(m.bareme, 20);
      expect(m.facultative, isFalse);
      expect(m.enseignantId, isNull);
    });

    test('ajouter avec barème, facultative et enseignant, puis relire', () async {
      final p = await prof('Barry');
      final m = await matieres.ajouter(
        classeId: classe.id,
        nom: 'Dessin',
        coefficient: 100,
        bareme: 10,
        facultative: true,
        enseignantId: p,
      );
      final relue = (await matieres.lister(classe.id)).single;
      expect(relue.id, m.id);
      expect(relue.bareme, 10);
      expect(relue.facultative, isTrue);
      expect(relue.enseignantId, p);
    });

    test('barèmes usuels acceptés, barèmes hors limites refusés', () async {
      var i = 0;
      for (final bareme in [10, 20, 40, 100, 1, 1000]) {
        await matieres.ajouter(
          classeId: classe.id,
          nom: 'M${i++}',
          coefficient: 100,
          bareme: bareme,
        );
      }
      for (final bareme in [0, -5, 1001]) {
        await expectLater(
          matieres.ajouter(
            classeId: classe.id,
            nom: 'X$bareme',
            coefficient: 100,
            bareme: bareme,
          ),
          erreurContenant('entre 1 et 1000'),
        );
      }
      expect((await matieres.lister(classe.id)).length, 6);
    });

    test('enseignant inconnu refusé', () async {
      await expectLater(
        matieres.ajouter(
          classeId: classe.id,
          nom: 'Maths',
          coefficient: 400,
          enseignantId: 999,
        ),
        erreurContenant('Enseignant introuvable'),
      );
      expect(await matieres.lister(classe.id), isEmpty);
    });

    test('modifier le barème, le caractère facultatif et l\'enseignant', () async {
      final p = await prof('Barry');
      final m = await matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
      await matieres.modifier(m.id, bareme: 40, facultative: true, enseignantId: p);
      var relue = (await matieres.lister(classe.id)).single;
      expect(relue.bareme, 40);
      expect(relue.facultative, isTrue);
      expect(relue.enseignantId, p);
      expect(relue.coefficient, 400);

      await matieres.modifier(m.id, facultative: false, retirerEnseignant: true);
      relue = (await matieres.lister(classe.id)).single;
      expect(relue.facultative, isFalse);
      expect(relue.enseignantId, isNull);
      expect(relue.bareme, 40);
    });

    test('modifier sans toucher à l\'enseignant le conserve', () async {
      final p = await prof('Barry');
      final m = await matieres.ajouter(
        classeId: classe.id,
        nom: 'Maths',
        coefficient: 400,
        enseignantId: p,
      );
      await matieres.modifier(m.id, coefficient: 500);
      expect((await matieres.lister(classe.id)).single.enseignantId, p);
    });

    test('le barème ne peut plus changer dès qu\'une note existe', () async {
      final m = await matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
      final ins = await eleves.inscrire(
        const Eleve(matricule: 'M1', nom: 'A', prenom: 'B', sexe: 'F'),
        anneeId: anneeId,
        classeId: classe.id,
      );
      await db.insert('note', {
        'inscription_id': ins,
        'matiere_id': m.id,
        'mois': 10,
        'etat': 'saisie',
        'valeur': 1000,
        'modifie_le': '2026-10-02',
      });
      await expectLater(
        matieres.modifier(m.id, bareme: 10),
        erreurContenant('ne peut plus changer'),
      );
      expect((await matieres.lister(classe.id)).single.bareme, 20);
      // Redonner le même barème est sans effet et permis.
      await matieres.modifier(m.id, bareme: 20, coefficient: 300);
      expect((await matieres.lister(classe.id)).single.coefficient, 300);
    });

    test('le barème ne peut plus changer dès qu\'une évaluation existe', () async {
      final m = await matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
      await db.insert('evaluation', {
        'classe_id': classe.id,
        'matiere_id': m.id,
        'mois': 10,
        'type': 'devoir',
        'titre': 'Devoir 1',
        'coefficient': 100,
        'bareme': 20,
        'valide': 0,
        'cree_le': '2026-10-02',
      });
      expect(await matieres.nbEvaluations(m.id), 1);
      await expectLater(
        matieres.modifier(m.id, bareme: 10),
        erreurContenant('1 évaluation'),
      );
    });

    test('le nombre de notes compte aussi les notes d\'évaluation', () async {
      final m = await matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
      final ins = await eleves.inscrire(
        const Eleve(matricule: 'M1', nom: 'A', prenom: 'B', sexe: 'F'),
        anneeId: anneeId,
        classeId: classe.id,
      );
      final ev = await db.insert('evaluation', {
        'classe_id': classe.id,
        'matiere_id': m.id,
        'mois': 10,
        'type': 'devoir',
        'titre': 'Devoir 1',
        'coefficient': 100,
        'bareme': 20,
        'valide': 0,
        'cree_le': '2026-10-02',
      });
      await db.insert('evaluation_note', {
        'evaluation_id': ev,
        'inscription_id': ins,
        'etat': 'saisie',
        'brut': 1200,
        'modifie_le': '2026-10-02',
      });
      expect(await matieres.nbNotes(m.id), 1);
      await expectLater(
        matieres.supprimer(m.id),
        erreurContenant('1 note y est enregistrée'),
      );
    });

    test('supprimer une matière qui a des évaluations sans notes est refusé',
        () async {
      final m = await matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
      await db.insert('evaluation', {
        'classe_id': classe.id,
        'matiere_id': m.id,
        'mois': 10,
        'type': 'devoir',
        'titre': 'Devoir 1',
        'coefficient': 100,
        'bareme': 20,
        'valide': 0,
        'cree_le': '2026-10-02',
      });
      await expectLater(
        matieres.supprimer(m.id),
        erreurContenant('Supprimez-les d\'abord'),
      );
    });

    test('copier des matières reprend barème et caractère facultatif', () async {
      final autre = await classes.creer(anneeId: anneeId, nom: '10e B');
      await matieres.ajouter(
        classeId: classe.id,
        nom: 'Maths',
        coefficient: 400,
        bareme: 40,
      );
      await matieres.ajouter(
        classeId: classe.id,
        nom: 'Dessin',
        coefficient: 100,
        facultative: true,
      );
      expect(
        await matieres.copier(depuisClasseId: classe.id, versClasseId: autre.id),
        2,
      );
      final copie = await matieres.lister(autre.id);
      expect(copie[0].bareme, 40);
      expect(copie[1].facultative, isTrue);
    });

    test('sans permission, une matière ne peut pas être ajoutée', () async {
      final refuse = MatiereDepot(
        db,
        controle: const Controle(autorisations: _AucuneAutorisation()),
      );
      await expectLater(
        refuse.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400),
        erreurContenant('autorisation'),
      );
    });
  });
}
