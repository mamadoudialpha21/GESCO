import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/controle.dart';
import 'package:gesco/data/depots/annee_depot.dart';
import 'package:gesco/data/depots/classe_depot.dart';
import 'package:gesco/data/depots/enseignant_depot.dart';
import 'package:gesco/data/depots/matiere_depot.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher erreurContenant(String texte) => throwsA(
      isA<ErreurGesco>().having((e) => e.message, 'message', contains(texte)),
    );

Uint8List png() {
  final octets = Uint8List(12);
  octets.setRange(0, 8, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  return octets;
}

/// Utilisateur connecté sans aucune permission.
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
  late EnseignantDepot enseignants;
  late ClasseDepot classes;
  late MatiereDepot matieres;
  late AnneeDepot annees;
  late int anneeId;

  setUp(() async {
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    db = gdb.db;
    enseignants = EnseignantDepot(db, maintenant: () => DateTime(2026, 10, 1, 8));
    classes = ClasseDepot(db);
    matieres = MatiereDepot(db);
    annees = AnneeDepot(db);
    anneeId = (await annees.creer('2026-2027')).id;
  });

  tearDown(() async {
    await gdb.fermer();
  });

  Enseignant prof(
    String nom, {
    String prenom = 'Alpha',
    String matricule = '',
    String? sexe,
    String email = '',
    bool actif = true,
  }) =>
      Enseignant(
        nom: nom,
        prenom: prenom,
        matricule: matricule,
        sexe: sexe,
        email: email,
        actif: actif,
      );

  group('fiche', () {
    test('création puis lecture de tous les champs', () async {
      final id = await enseignants.creer(
        Enseignant(
          nom: ' Barry ',
          prenom: ' Fatoumata ',
          matricule: 'ENS-01',
          sexe: 'F',
          telephone: '622 00 00 00',
          email: 'f.barry@exemple.gn',
          specialite: 'Mathématiques',
          peutSaisir: false,
          signature: png(),
        ),
      );
      final e = (await enseignants.obtenir(id))!;
      expect(e.nom, 'Barry');
      expect(e.prenom, 'Fatoumata');
      expect(e.nomComplet, 'BARRY Fatoumata');
      expect(e.matricule, 'ENS-01');
      expect(e.sexe, 'F');
      expect(e.telephone, '622 00 00 00');
      expect(e.email, 'f.barry@exemple.gn');
      expect(e.specialite, 'Mathématiques');
      expect(e.actif, isTrue);
      expect(e.peutSaisir, isFalse);
      expect(e.signature, isNotNull);
    });

    test('un enseignant inconnu retourne null', () async {
      expect(await enseignants.obtenir(999), isNull);
    });

    test('le nom et le prénom sont obligatoires', () async {
      await expectLater(
        enseignants.creer(const Enseignant(nom: ' ', prenom: 'A')),
        erreurContenant('Le nom est obligatoire'),
      );
      await expectLater(
        enseignants.creer(const Enseignant(nom: 'A', prenom: '')),
        erreurContenant('Le prénom est obligatoire'),
      );
    });

    test('adresse e-mail, sexe et signature sont vérifiés', () async {
      await expectLater(
        enseignants.creer(prof('A', email: 'pas-un-courriel')),
        erreurContenant('e-mail est invalide'),
      );
      await expectLater(
        enseignants.creer(prof('A', sexe: 'X')),
        erreurContenant('Le sexe'),
      );
      await expectLater(
        enseignants.creer(
          Enseignant(nom: 'A', prenom: 'B', signature: Uint8List.fromList([1, 2, 3])),
        ),
        throwsA(isA<ErreurGesco>()),
      );
      expect(await enseignants.lister(), isEmpty);
    });

    test('un matricule déjà utilisé est refusé (sans tenir compte de la casse)',
        () async {
      await enseignants.creer(prof('A', matricule: 'ens-01'));
      await expectLater(
        enseignants.creer(prof('B', matricule: 'ENS-01')),
        erreurContenant('déjà utilisé'),
      );
    });

    test('plusieurs enseignants peuvent ne pas avoir de matricule', () async {
      await enseignants.creer(prof('A'));
      await enseignants.creer(prof('B'));
      expect((await enseignants.lister()).length, 2);
    });

    test('modification', () async {
      final id = await enseignants.creer(prof('Barry', matricule: 'E1'));
      final e = (await enseignants.obtenir(id))!;
      await enseignants.modifier(
        e.copyWith(prenom: 'Nouveau', actif: false, matricule: 'E2'),
      );
      final apres = (await enseignants.obtenir(id))!;
      expect(apres.prenom, 'Nouveau');
      expect(apres.actif, isFalse);
      expect(apres.matricule, 'E2');
    });

    test('on peut garder son propre matricule en modifiant la fiche', () async {
      final id = await enseignants.creer(prof('Barry', matricule: 'E1'));
      final e = (await enseignants.obtenir(id))!;
      await enseignants.modifier(e.copyWith(telephone: '1'));
      expect((await enseignants.obtenir(id))!.telephone, '1');
    });

    test('modifier un enseignant inconnu est refusé', () async {
      await expectLater(
        enseignants.modifier(const Enseignant(id: 999, nom: 'A', prenom: 'B')),
        erreurContenant('introuvable'),
      );
    });

    test('retirer la signature', () async {
      final id = await enseignants.creer(
        Enseignant(nom: 'A', prenom: 'B', signature: png()),
      );
      final e = (await enseignants.obtenir(id))!;
      await enseignants.modifier(e.copyWith(supprimerSignature: true));
      expect((await enseignants.obtenir(id))!.signature, isNull);
    });
  });

  group('liste', () {
    test('triée par nom puis prénom, sans tenir compte des accents', () async {
      await enseignants.creer(prof('Sow', prenom: 'Zeinab'));
      await enseignants.creer(prof('Émile', prenom: 'Paul'));
      await enseignants.creer(prof('Barry', prenom: 'Mariama'));
      await enseignants.creer(prof('Barry', prenom: 'Aly'));
      final noms = [
        for (final r in await enseignants.lister())
          '${r.enseignant.nom} ${r.enseignant.prenom}',
      ];
      expect(noms, ['Barry Aly', 'Barry Mariama', 'Émile Paul', 'Sow Zeinab']);
    });

    test('actifs seulement', () async {
      await enseignants.creer(prof('A'));
      await enseignants.creer(prof('B', actif: false));
      final actifs = await enseignants.lister(actifsSeulement: true);
      expect(actifs.map((r) => r.enseignant.nom), ['A']);
      expect((await enseignants.lister()).length, 2);
    });

    test('compte les matières et les classes de l\'année, sans doublon', () async {
      final id = await enseignants.creer(prof('Barry'));
      final c1 = await classes.creer(anneeId: anneeId, nom: '10e A');
      final c2 = await classes.creer(anneeId: anneeId, nom: '10e B');
      final c3 = await classes.creer(anneeId: anneeId, nom: '10e C');
      await matieres.ajouter(classeId: c1.id, nom: 'Maths', coefficient: 400, enseignantId: id);
      await matieres.ajouter(classeId: c1.id, nom: 'Physique', coefficient: 300, enseignantId: id);
      await matieres.ajouter(classeId: c2.id, nom: 'Maths', coefficient: 400, enseignantId: id);
      // c1 : matières + professeur principal (une seule classe comptée).
      await classes.modifier(
        c1.id,
        nom: c1.nom,
        niveau: c1.niveau,
        reglages: ReglagesClasse(profPrincipalId: id),
      );
      await enseignants.definirClassesConfiees(id, anneeId, {c3.id});

      final r = (await enseignants.lister(anneeId: anneeId)).single;
      expect(r.nbMatieres, 3);
      expect(r.nbClasses, 3);

      final sansAnnee = (await enseignants.lister()).single;
      expect(sansAnnee.nbMatieres, 0);
      expect(sansAnnee.nbClasses, 0);
    });
  });

  group('suppression', () {
    test('un enseignant sans affectation est supprimé', () async {
      final id = await enseignants.creer(prof('Barry'));
      await enseignants.supprimer(id);
      expect(await enseignants.obtenir(id), isNull);
    });

    test('refusée tant qu\'il enseigne une matière', () async {
      final id = await enseignants.creer(prof('Barry'));
      final c = await classes.creer(anneeId: anneeId, nom: '10e A');
      await matieres.ajouter(classeId: c.id, nom: 'Maths', coefficient: 400, enseignantId: id);
      await expectLater(
        enseignants.supprimer(id),
        erreurContenant('il enseigne 1 matière'),
      );
      expect(await enseignants.obtenir(id), isNotNull);
    });

    test('refusée s\'il est professeur principal ou a des classes confiées',
        () async {
      final id = await enseignants.creer(prof('Barry'));
      final c = await classes.creer(anneeId: anneeId, nom: '10e A');
      await classes.modifier(
        c.id,
        nom: c.nom,
        niveau: c.niveau,
        reglages: ReglagesClasse(profPrincipalId: id),
      );
      await expectLater(
        enseignants.supprimer(id),
        erreurContenant('professeur principal'),
      );
      await classes.modifier(
        c.id,
        nom: c.nom,
        niveau: c.niveau,
        reglages: const ReglagesClasse(),
      );
      await enseignants.definirClassesConfiees(id, anneeId, {c.id});
      await expectLater(
        enseignants.supprimer(id),
        erreurContenant('lui est confiée'),
      );
    });

    test('refusée si un compte utilisateur lui est lié, et propose de désactiver',
        () async {
      final id = await enseignants.creer(prof('Barry'));
      await db.insert('utilisateur', {
        'identifiant': 'barry',
        'role': 'saisie',
        'mot_de_passe_hash': 'x',
        'sel': 'x',
        'iterations': 1,
        'enseignant_id': id,
        'cree_le': '2026-10-01',
      });
      await expectLater(
        enseignants.supprimer(id),
        erreurContenant('désactiver'),
      );
    });

    test('un enseignant inconnu est refusé', () async {
      await expectLater(enseignants.supprimer(999), erreurContenant('introuvable'));
    });
  });

  group('affectations', () {
    test('matières enseignées, par année', () async {
      final id = await enseignants.creer(prof('Barry'));
      final c = await classes.creer(anneeId: anneeId, nom: '10e A');
      final m = await matieres.ajouter(
        classeId: c.id,
        nom: 'Maths',
        coefficient: 400,
        enseignantId: id,
      );
      final autre = await annees.creer('2027-2028');
      final c2 = await classes.creer(anneeId: autre.id, nom: '11e A');
      await matieres.ajouter(classeId: c2.id, nom: 'Physique', coefficient: 300, enseignantId: id);

      final cetteAnnee = await enseignants.matieres(id, anneeId: anneeId);
      expect(cetteAnnee.single.matiereId, m.id);
      expect(cetteAnnee.single.matiereNom, 'Maths');
      expect(cetteAnnee.single.classeNom, '10e A');
      expect((await enseignants.matieres(id)).length, 2);
    });

    test('classes confiées : remplacées pour l\'année, sans toucher aux autres',
        () async {
      final id = await enseignants.creer(prof('Barry'));
      final c1 = await classes.creer(anneeId: anneeId, nom: '10e A');
      final c2 = await classes.creer(anneeId: anneeId, nom: '10e B');
      final autre = await annees.creer('2027-2028');
      final c3 = await classes.creer(anneeId: autre.id, nom: '11e A');

      await enseignants.definirClassesConfiees(id, anneeId, {c1.id, c2.id});
      await enseignants.definirClassesConfiees(id, autre.id, {c3.id});
      expect(await enseignants.classesConfiees(id, anneeId), {c1.id, c2.id});

      await enseignants.definirClassesConfiees(id, anneeId, {c2.id});
      expect(await enseignants.classesConfiees(id, anneeId), {c2.id});
      expect(await enseignants.classesConfiees(id, autre.id), {c3.id});

      await enseignants.definirClassesConfiees(id, anneeId, {});
      expect(await enseignants.classesConfiees(id, anneeId), isEmpty);
      expect(await enseignants.classesConfiees(id, autre.id), {c3.id});
    });

    test('une classe d\'une autre année est refusée, rien n\'est modifié',
        () async {
      final id = await enseignants.creer(prof('Barry'));
      final c1 = await classes.creer(anneeId: anneeId, nom: '10e A');
      final autre = await annees.creer('2027-2028');
      final c3 = await classes.creer(anneeId: autre.id, nom: '11e A');
      await enseignants.definirClassesConfiees(id, anneeId, {c1.id});
      await expectLater(
        enseignants.definirClassesConfiees(id, anneeId, {c3.id}),
        erreurContenant('n\'existe pas pour cette année'),
      );
      expect(await enseignants.classesConfiees(id, anneeId), {c1.id});
    });

    test('enseignant inconnu', () async {
      await expectLater(
        enseignants.definirClassesConfiees(999, anneeId, {}),
        erreurContenant('introuvable'),
      );
    });

    test('toutes les classes de l\'enseignant : matière, confiée, principale',
        () async {
      final id = await enseignants.creer(prof('Barry'));
      final c1 = await classes.creer(anneeId: anneeId, nom: '10e A');
      final c2 = await classes.creer(anneeId: anneeId, nom: '10e B');
      final c3 = await classes.creer(anneeId: anneeId, nom: '10e C');
      await classes.creer(anneeId: anneeId, nom: '10e D');
      await matieres.ajouter(classeId: c1.id, nom: 'Maths', coefficient: 400, enseignantId: id);
      await enseignants.definirClassesConfiees(id, anneeId, {c2.id, c1.id});
      await classes.modifier(
        c3.id,
        nom: c3.nom,
        niveau: c3.niveau,
        reglages: ReglagesClasse(profPrincipalId: id),
      );
      expect(
        await enseignants.classesDeLEnseignant(id, anneeId),
        {c1.id, c2.id, c3.id},
      );
    });
  });

  group('permissions', () {
    test('sans permission, aucune écriture n\'est possible', () async {
      final controle = const Controle(autorisations: _AucuneAutorisation());
      final refuse = EnseignantDepot(db, controle: controle);
      await expectLater(
        refuse.creer(prof('A')),
        erreurContenant('autorisation'),
      );
      final id = await enseignants.creer(prof('B'));
      await expectLater(
        refuse.modifier(Enseignant(id: id, nom: 'C', prenom: 'D')),
        erreurContenant('autorisation'),
      );
      await expectLater(refuse.supprimer(id), erreurContenant('autorisation'));
      await expectLater(
        refuse.definirClassesConfiees(id, anneeId, {}),
        erreurContenant('autorisation'),
      );
      expect((await enseignants.obtenir(id))!.nom, 'B');
    });
  });
}
