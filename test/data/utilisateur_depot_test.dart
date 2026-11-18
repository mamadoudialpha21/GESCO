import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/depots/annee_depot.dart';
import 'package:gesco/data/depots/classe_depot.dart';
import 'package:gesco/data/depots/eleve_depot.dart';
import 'package:gesco/data/depots/matiere_depot.dart';
import 'package:gesco/data/depots/note_depot.dart';
import 'package:gesco/data/depots/parametre_depot.dart';
import 'package:gesco/data/depots/utilisateur_depot.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher erreurContenant(String texte) => throwsA(
      isA<ErreurGesco>().having((e) => e.message, 'message', contains(texte)),
    );

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Database db;
  late UtilisateurDepot depot;
  var horloge = DateTime(2026, 11, 17, 8, 0, 0);

  setUp(() async {
    horloge = DateTime(2026, 11, 17, 8, 0, 0);
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    db = gdb.db;
    depot = UtilisateurDepot(db, maintenant: () => horloge, iterations: 2);
  });

  tearDown(() async {
    await gdb.fermer();
  });

  Future<Utilisateur> admin() async {
    final r = await depot.creerPremierAdministrateur(
      identifiant: 'admin',
      nomComplet: 'Directeur Test',
      motDePasse: 'Tombolia26',
    );
    return r.utilisateur;
  }

  Future<List<String>> evenements() async => [
        for (final l in await db.query('journal_connexion', orderBy: 'id'))
          l['evenement'] as String,
      ];

  group('Premier administrateur', () {
    test('une base neuve n\'a aucun compte', () async {
      expect(await depot.aucunUtilisateur(), isTrue);
      expect(await depot.compter(), 0);
    });

    test('crée un administrateur et un code de récupération', () async {
      final r = await depot.creerPremierAdministrateur(
        identifiant: ' admin ',
        nomComplet: 'Directeur Test',
        motDePasse: 'Tombolia26',
      );
      expect(r.utilisateur.identifiant, 'admin');
      expect(r.utilisateur.role, RoleUtilisateur.administrateur);
      expect(r.utilisateur.actif, isTrue);
      expect(r.utilisateur.doitChangerMotDePasse, isFalse);
      expect(r.codeRecuperation, matches(RegExp(r'^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$')));
      expect(await depot.aUnCodeRecuperation(), isTrue);
      expect(await depot.aucunUtilisateur(), isFalse);
    });

    test('ne peut être créé qu\'une seule fois', () async {
      await admin();
      expect(
        depot.creerPremierAdministrateur(identifiant: 'autre', motDePasse: 'Tombolia27'),
        erreurContenant('existe déjà'),
      );
    });

    test('refuse un mot de passe faible ou un identifiant invalide', () async {
      expect(
        depot.creerPremierAdministrateur(identifiant: 'admin', motDePasse: '123456'),
        erreurContenant('courant'),
      );
      expect(
        depot.creerPremierAdministrateur(identifiant: 'a', motDePasse: 'Tombolia26'),
        erreurContenant('au moins 3'),
      );
      expect(await depot.compter(), 0);
    });

    test('le mot de passe et le code ne sont jamais enregistrés en clair', () async {
      final r = await depot.creerPremierAdministrateur(
        identifiant: 'admin',
        motDePasse: 'Tombolia26',
      );
      final texte = [
        for (final t in ['utilisateur', 'parametre', 'journal_connexion', 'journal'])
          ...(await db.query(t)).map((l) => l.values.join('|')),
      ].join('\n');
      expect(texte.contains('Tombolia26'), isFalse);
      expect(texte.contains(r.codeRecuperation), isFalse);
      expect(texte.contains(r.codeRecuperation.replaceAll('-', '')), isFalse);
    });
  });

  group('Création et profil', () {
    test('crée un compte qui devra changer son mot de passe', () async {
      await admin();
      final u = await depot.creer(
        identifiant: 'prof1',
        nomComplet: 'Professeur Un',
        role: RoleUtilisateur.saisie,
        motDePasse: 'Provisoire1',
      );
      expect(u.role, RoleUtilisateur.saisie);
      expect(u.doitChangerMotDePasse, isTrue);
      expect(u.permissionsPersonnalisees, isNull);
      expect(u.peut(Permission.notesSaisir), isTrue);
      expect(u.peut(Permission.utilisateursGerer), isFalse);
    });

    test('refuse un identifiant déjà pris, sans tenir compte de la casse', () async {
      await admin();
      expect(
        depot.creer(identifiant: 'ADMIN', role: RoleUtilisateur.consultation, motDePasse: 'Tombolia27'),
        erreurContenant('déjà utilisé'),
      );
    });

    test('enregistre des permissions personnalisées et les relit', () async {
      await admin();
      final u = await depot.creer(
        identifiant: 'secretaire',
        role: RoleUtilisateur.consultation,
        motDePasse: 'Provisoire1',
        permissions: {Permission.notesVoir, Permission.elevesGerer},
      );
      final relu = (await depot.obtenir(u.id))!;
      expect(relu.permissionsPersonnalisees, {Permission.notesVoir, Permission.elevesGerer});
      expect(relu.peut(Permission.elevesGerer), isTrue);
      expect(relu.peut(Permission.tableauDeBord), isFalse);
    });

    test('un administrateur ne garde pas de permissions personnalisées', () async {
      await admin();
      final u = await depot.creer(
        identifiant: 'admin2',
        role: RoleUtilisateur.administrateur,
        motDePasse: 'Provisoire1',
        permissions: {Permission.notesVoir},
      );
      expect(u.permissionsPersonnalisees, isNull);
      expect(u.permissions, Permission.values.toSet());
    });

    test('modifie le nom, le rôle et les permissions', () async {
      await admin();
      final u = await depot.creer(
        identifiant: 'prof1',
        role: RoleUtilisateur.consultation,
        motDePasse: 'Provisoire1',
      );
      await depot.modifierProfil(
        u.id,
        nomComplet: 'Nouveau Nom',
        role: RoleUtilisateur.saisie,
        permissions: null,
      );
      final relu = (await depot.obtenir(u.id))!;
      expect(relu.nomComplet, 'Nouveau Nom');
      expect(relu.role, RoleUtilisateur.saisie);
      expect(relu.identifiant, 'prof1');
    });

    test('refuse un nom complet démesuré', () async {
      await admin();
      expect(
        depot.creer(
          identifiant: 'prof1',
          nomComplet: 'x' * 81,
          role: RoleUtilisateur.consultation,
          motDePasse: 'Provisoire1',
        ),
        erreurContenant('trop long'),
      );
    });

    test('le nom affiché est l\'identifiant quand le nom est vide', () async {
      await admin();
      final u = await depot.creer(
        identifiant: 'prof1',
        role: RoleUtilisateur.consultation,
        motDePasse: 'Provisoire1',
      );
      expect(u.nomAffiche, 'prof1');
    });

    test('la liste est triée par identifiant sans tenir compte de la casse', () async {
      await admin();
      await depot.creer(identifiant: 'Zoe', role: RoleUtilisateur.consultation, motDePasse: 'Provisoire1');
      await depot.creer(identifiant: 'bob', role: RoleUtilisateur.consultation, motDePasse: 'Provisoire1');
      final noms = [for (final u in await depot.lister()) u.identifiant];
      expect(noms, ['admin', 'bob', 'Zoe']);
    });
  });

  group('Connexion', () {
    test('un bon mot de passe ouvre la session et note la connexion', () async {
      await admin();
      horloge = DateTime(2026, 11, 17, 9, 30, 15);
      final u = await depot.authentifier('admin', 'Tombolia26');
      expect(u.identifiant, 'admin');
      expect(u.derniereConnexion, '2026-11-17T09:30:15');
      expect(await evenements(), contains('connexion'));
    });

    test('l\'identifiant est insensible à la casse, le mot de passe non', () async {
      await admin();
      expect((await depot.authentifier('ADMIN', 'Tombolia26')).identifiant, 'admin');
      expect(
        depot.authentifier('admin', 'tombolia26'),
        erreurContenant(UtilisateurDepot.messageIdentifiantsIncorrects),
      );
    });

    test('même message pour un identifiant inconnu et un mauvais mot de passe', () async {
      await admin();
      Object? e1;
      Object? e2;
      try {
        await depot.authentifier('inconnu', 'Tombolia26');
      } on ErreurGesco catch (e) {
        e1 = e.message;
      }
      try {
        await depot.authentifier('admin', 'mauvais');
      } on ErreurGesco catch (e) {
        e2 = e.message;
      }
      expect(e1, UtilisateurDepot.messageIdentifiantsIncorrects);
      expect(e2, e1);
    });

    test('les échecs sont journalisés sans le mot de passe tenté', () async {
      await admin();
      await expectLater(depot.authentifier('admin', 'SecretTente9'), throwsA(isA<ErreurGesco>()));
      final lignes = await db.query('journal_connexion', where: "evenement = 'echec'");
      expect(lignes, hasLength(1));
      expect(lignes.first.values.join('|').contains('SecretTente9'), isFalse);
    });

    test('un compte désactivé ne peut plus se connecter', () async {
      await admin();
      final u = await depot.creer(
        identifiant: 'prof1',
        role: RoleUtilisateur.saisie,
        motDePasse: 'Provisoire1',
      );
      await depot.definirActif(u.id, false);
      expect(depot.authentifier('prof1', 'Provisoire1'), erreurContenant('désactivé'));
      await depot.definirActif(u.id, true);
      expect((await depot.authentifier('prof1', 'Provisoire1')).identifiant, 'prof1');
    });

    test('un mauvais mot de passe sur un compte désactivé ne révèle pas son état', () async {
      await admin();
      final u = await depot.creer(
        identifiant: 'prof1',
        role: RoleUtilisateur.saisie,
        motDePasse: 'Provisoire1',
      );
      await depot.definirActif(u.id, false);
      expect(
        depot.authentifier('prof1', 'mauvais'),
        erreurContenant(UtilisateurDepot.messageIdentifiantsIncorrects),
      );
    });
  });

  group('Verrouillage après échecs', () {
    test('5 échecs verrouillent le compte, même avec le bon mot de passe', () async {
      await admin();
      for (var i = 0; i < UtilisateurDepot.echecsMax - 1; i++) {
        await expectLater(
          depot.authentifier('admin', 'faux$i'),
          erreurContenant(UtilisateurDepot.messageIdentifiantsIncorrects),
        );
      }
      await expectLater(depot.authentifier('admin', 'faux!'), erreurContenant('verrouillé'));
      await expectLater(depot.authentifier('admin', 'Tombolia26'), erreurContenant('verrouillé'));
      expect(await evenements(), containsAll(['verrouillage', 'refus_verrou']));
    });

    test('le verrou expire au bout de 5 minutes', () async {
      await admin();
      for (var i = 0; i < UtilisateurDepot.echecsMax; i++) {
        await expectLater(depot.authentifier('admin', 'faux$i'), throwsA(isA<ErreurGesco>()));
      }
      horloge = horloge.add(const Duration(minutes: 4, seconds: 59));
      await expectLater(depot.authentifier('admin', 'Tombolia26'), erreurContenant('verrouillé'));
      horloge = horloge.add(const Duration(seconds: 2));
      expect((await depot.authentifier('admin', 'Tombolia26')).identifiant, 'admin');
    });

    test('une connexion réussie remet le compteur d\'échecs à zéro', () async {
      await admin();
      for (var i = 0; i < 4; i++) {
        await expectLater(depot.authentifier('admin', 'faux$i'), throwsA(isA<ErreurGesco>()));
      }
      await depot.authentifier('admin', 'Tombolia26');
      for (var i = 0; i < 4; i++) {
        await expectLater(
          depot.authentifier('admin', 'faux$i'),
          erreurContenant(UtilisateurDepot.messageIdentifiantsIncorrects),
        );
      }
      expect((await depot.authentifier('admin', 'Tombolia26')).identifiant, 'admin');
    });

    test('un administrateur peut réactiver un compte verrouillé', () async {
      await admin();
      for (var i = 0; i < UtilisateurDepot.echecsMax; i++) {
        await expectLater(depot.authentifier('admin', 'faux$i'), throwsA(isA<ErreurGesco>()));
      }
      final u = (await depot.parIdentifiant('admin'))!;
      await depot.definirActif(u.id, true);
      expect((await depot.authentifier('admin', 'Tombolia26')).identifiant, 'admin');
    });
  });

  group('Mots de passe', () {
    test('l\'utilisateur change son mot de passe avec l\'ancien', () async {
      final a = await admin();
      await depot.changerMotDePasse(a.id, ancien: 'Tombolia26', nouveau: 'Nouveau2027');
      await expectLater(
        depot.authentifier('admin', 'Tombolia26'),
        erreurContenant(UtilisateurDepot.messageIdentifiantsIncorrects),
      );
      expect((await depot.authentifier('admin', 'Nouveau2027')).identifiant, 'admin');
    });

    test('refuse un ancien mot de passe faux, identique ou un nouveau trop faible', () async {
      final a = await admin();
      await expectLater(
        depot.changerMotDePasse(a.id, ancien: 'faux', nouveau: 'Nouveau2027'),
        erreurContenant('actuel est incorrect'),
      );
      await expectLater(
        depot.changerMotDePasse(a.id, ancien: 'Tombolia26', nouveau: 'Tombolia26'),
        erreurContenant('différent'),
      );
      await expectLater(
        depot.changerMotDePasse(a.id, ancien: 'Tombolia26', nouveau: '123'),
        erreurContenant('au moins'),
      );
      expect((await depot.authentifier('admin', 'Tombolia26')).identifiant, 'admin');
    });

    test('le changement lève l\'obligation de changer le mot de passe', () async {
      await admin();
      final u = await depot.creer(
        identifiant: 'prof1',
        role: RoleUtilisateur.saisie,
        motDePasse: 'Provisoire1',
      );
      expect(u.doitChangerMotDePasse, isTrue);
      await depot.changerMotDePasse(u.id, ancien: 'Provisoire1', nouveau: 'MonSecret27');
      expect((await depot.obtenir(u.id))!.doitChangerMotDePasse, isFalse);
    });

    test('la réinitialisation par un administrateur impose un nouveau changement', () async {
      await admin();
      final u = await depot.creer(
        identifiant: 'prof1',
        role: RoleUtilisateur.saisie,
        motDePasse: 'Provisoire1',
      );
      await depot.changerMotDePasse(u.id, ancien: 'Provisoire1', nouveau: 'MonSecret27');
      await depot.reinitialiserMotDePasse(u.id, 'Provisoire2');
      final connecte = await depot.authentifier('prof1', 'Provisoire2');
      expect(connecte.doitChangerMotDePasse, isTrue);
      await expectLater(
        depot.authentifier('prof1', 'MonSecret27'),
        erreurContenant(UtilisateurDepot.messageIdentifiantsIncorrects),
      );
    });

    test('la réinitialisation refuse un mot de passe faible', () async {
      await admin();
      final u = await depot.creer(
        identifiant: 'prof1',
        role: RoleUtilisateur.saisie,
        motDePasse: 'Provisoire1',
      );
      await expectLater(depot.reinitialiserMotDePasse(u.id, 'abc'), erreurContenant('au moins'));
    });

    test('chaque compte a son propre sel : deux mêmes mots de passe, deux empreintes', () async {
      await admin();
      await depot.creer(identifiant: 'a1', role: RoleUtilisateur.consultation, motDePasse: 'Provisoire1');
      await depot.creer(identifiant: 'b1', role: RoleUtilisateur.consultation, motDePasse: 'Provisoire1');
      final lignes = await db.query('utilisateur', where: "identifiant IN ('a1', 'b1')");
      expect(lignes[0]['mot_de_passe_hash'], isNot(lignes[1]['mot_de_passe_hash']));
      expect(lignes[0]['sel'], isNot(lignes[1]['sel']));
    });

    test('les anciens comptes restent valables si le nombre d\'itérations augmente', () async {
      await admin();
      final plusSolide = UtilisateurDepot(db, maintenant: () => horloge, iterations: 5);
      expect((await plusSolide.authentifier('admin', 'Tombolia26')).identifiant, 'admin');
    });
  });

  group('Protection du dernier administrateur', () {
    test('ne peut pas être désactivé, supprimé ni rétrogradé', () async {
      final a = await admin();
      await expectLater(depot.definirActif(a.id, false), erreurContenant('au moins un administrateur'));
      await expectLater(depot.supprimer(a.id), erreurContenant('au moins un administrateur'));
      await expectLater(
        depot.modifierProfil(a.id, nomComplet: 'x', role: RoleUtilisateur.direction),
        erreurContenant('au moins un administrateur'),
      );
      expect((await depot.obtenir(a.id))!.role, RoleUtilisateur.administrateur);
      expect((await depot.obtenir(a.id))!.actif, isTrue);
    });

    test('avec un second administrateur actif, le premier peut être rétrogradé', () async {
      final a = await admin();
      await depot.creer(
        identifiant: 'admin2',
        role: RoleUtilisateur.administrateur,
        motDePasse: 'Provisoire1',
      );
      await depot.modifierProfil(a.id, nomComplet: 'x', role: RoleUtilisateur.direction);
      expect((await depot.obtenir(a.id))!.role, RoleUtilisateur.direction);
    });

    test('un second administrateur désactivé ne compte pas', () async {
      final a = await admin();
      final b = await depot.creer(
        identifiant: 'admin2',
        role: RoleUtilisateur.administrateur,
        motDePasse: 'Provisoire1',
      );
      await depot.definirActif(b.id, false);
      await expectLater(depot.definirActif(a.id, false), erreurContenant('au moins un administrateur'));
    });

    test('on ne peut pas supprimer son propre compte', () async {
      final a = await admin();
      final b = await depot.creer(
        identifiant: 'admin2',
        role: RoleUtilisateur.administrateur,
        motDePasse: 'Provisoire1',
      );
      await expectLater(depot.supprimer(a.id, parId: a.id), erreurContenant('propre compte'));
      await depot.supprimer(b.id, parId: a.id);
      expect(await depot.compter(), 1);
    });

    test('supprimer un compte inconnu ne fait rien', () async {
      await admin();
      await depot.supprimer(9999);
      expect(await depot.compter(), 1);
    });
  });

  group('Code de récupération', () {
    test('redonne l\'accès à l\'administrateur et change le code', () async {
      final r = await depot.creerPremierAdministrateur(
        identifiant: 'admin',
        motDePasse: 'Tombolia26',
      );
      final nouveau = await depot.reinitialiserParCodeRecuperation(
        identifiant: 'admin',
        code: r.codeRecuperation.toLowerCase().replaceAll('-', ' '),
        nouveauMotDePasse: 'Retrouve2027',
      );
      expect(nouveau, isNot(r.codeRecuperation));
      expect((await depot.authentifier('admin', 'Retrouve2027')).identifiant, 'admin');
      // L'ancien code est consommé.
      await expectLater(
        depot.reinitialiserParCodeRecuperation(
          identifiant: 'admin',
          code: r.codeRecuperation,
          nouveauMotDePasse: 'Autre2027',
        ),
        erreurContenant('incorrect'),
      );
      expect(await evenements(), contains('recuperation'));
    });

    test('réactive et déverrouille le compte récupéré', () async {
      final r = await depot.creerPremierAdministrateur(
        identifiant: 'admin',
        motDePasse: 'Tombolia26',
      );
      for (var i = 0; i < UtilisateurDepot.echecsMax; i++) {
        await expectLater(depot.authentifier('admin', 'faux$i'), throwsA(isA<ErreurGesco>()));
      }
      await depot.reinitialiserParCodeRecuperation(
        identifiant: 'admin',
        code: r.codeRecuperation,
        nouveauMotDePasse: 'Retrouve2027',
      );
      expect((await depot.authentifier('admin', 'Retrouve2027')).identifiant, 'admin');
    });

    test('refuse un mauvais code, et bloque après 5 essais', () async {
      final r = await depot.creerPremierAdministrateur(
        identifiant: 'admin',
        motDePasse: 'Tombolia26',
      );
      for (var i = 0; i < UtilisateurDepot.echecsMax; i++) {
        await expectLater(
          depot.reinitialiserParCodeRecuperation(
            identifiant: 'admin',
            code: 'AAAA-AAAA-AAAA-AAA$i',
            nouveauMotDePasse: 'Retrouve2027',
          ),
          erreurContenant('incorrect'),
        );
      }
      // Même le bon code est refusé pendant le blocage.
      await expectLater(
        depot.reinitialiserParCodeRecuperation(
          identifiant: 'admin',
          code: r.codeRecuperation,
          nouveauMotDePasse: 'Retrouve2027',
        ),
        erreurContenant('bloquée'),
      );
      horloge = horloge.add(UtilisateurDepot.dureeVerrouRecuperation + const Duration(seconds: 1));
      await depot.reinitialiserParCodeRecuperation(
        identifiant: 'admin',
        code: r.codeRecuperation,
        nouveauMotDePasse: 'Retrouve2027',
      );
      expect((await depot.authentifier('admin', 'Retrouve2027')).identifiant, 'admin');
    });

    test('ne fonctionne que pour un administrateur', () async {
      final r = await depot.creerPremierAdministrateur(
        identifiant: 'admin',
        motDePasse: 'Tombolia26',
      );
      await depot.creer(identifiant: 'prof1', role: RoleUtilisateur.saisie, motDePasse: 'Provisoire1');
      await expectLater(
        depot.reinitialiserParCodeRecuperation(
          identifiant: 'prof1',
          code: r.codeRecuperation,
          nouveauMotDePasse: 'Retrouve2027',
        ),
        erreurContenant('administrateur'),
      );
      await expectLater(
        depot.reinitialiserParCodeRecuperation(
          identifiant: 'inconnu',
          code: r.codeRecuperation,
          nouveauMotDePasse: 'Retrouve2027',
        ),
        erreurContenant('administrateur'),
      );
    });

    test('un nouveau code rend l\'ancien inutilisable', () async {
      final r = await depot.creerPremierAdministrateur(
        identifiant: 'admin',
        motDePasse: 'Tombolia26',
      );
      final nouveau = await depot.nouveauCodeRecuperation();
      expect(nouveau, isNot(r.codeRecuperation));
      await expectLater(
        depot.reinitialiserParCodeRecuperation(
          identifiant: 'admin',
          code: r.codeRecuperation,
          nouveauMotDePasse: 'Retrouve2027',
        ),
        erreurContenant('incorrect'),
      );
    });

    test('sans code défini, la récupération est impossible', () async {
      await db.insert('utilisateur', {
        'identifiant': 'admin',
        'role': 'administrateur',
        'mot_de_passe_hash': 'x',
        'sel': 'x',
        'iterations': 1,
        'cree_le': '2026-01-01T00:00:00',
      });
      await expectLater(
        depot.reinitialiserParCodeRecuperation(
          identifiant: 'admin',
          code: 'AAAA-AAAA-AAAA-AAAA',
          nouveauMotDePasse: 'Retrouve2027',
        ),
        erreurContenant('Aucun code'),
      );
    });
  });

  group('Déconnexion et signature de l\'historique', () {
    test('marquerContexte signe les modifications de notes', () async {
      final a = await admin();
      final annees = AnneeDepot(db, maintenant: () => horloge);
      final classes = ClasseDepot(db);
      final matieres = MatiereDepot(db);
      final eleves = EleveDepot(db, maintenant: () => horloge);
      final notes = NoteDepot(db, maintenant: () => horloge);

      final annee = await annees.creer('2026-2027');
      final classe = await classes.creer(anneeId: annee.id, nom: '10e A');
      final maths = await matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
      final inscription = await eleves.inscrire(
        const Eleve(
          id: 0,
          matricule: '2026-0001',
          nom: 'DIALLO',
          prenom: 'Aminata',
          sexe: 'F',
        ),
        anneeId: annee.id,
        classeId: classe.id,
      );

      await depot.marquerContexte(a);
      await notes.enregistrer(
        inscriptionId: inscription,
        matiereId: maths.id,
        mois: 10,
        saisie: Saisie.valeur(1450),
      );
      await depot.marquerContexte(null);
      await notes.enregistrer(
        inscriptionId: inscription,
        matiereId: maths.id,
        mois: 10,
        saisie: Saisie.valeur(1500),
      );

      final h = await db.query('historique_note', orderBy: 'id');
      expect(h, hasLength(2));
      expect(h[0]['utilisateur_nom'], 'Directeur Test');
      expect(h[0]['nouvelle_valeur'], 1450);
      expect(h[1]['utilisateur_nom'], '');
      expect(h[1]['ancienne_valeur'], 1450);
      expect(h[1]['nouvelle_valeur'], 1500);
    });

    test('la déconnexion et le verrouillage sont journalisés et effacent le contexte', () async {
      final a = await admin();
      await depot.marquerContexte(a);
      await depot.enregistrerVerrouillage(a, inactivite: true);
      var c = (await db.query('contexte')).first;
      expect(c['utilisateur_id'], isNull);
      expect(c['utilisateur_nom'], '');

      await depot.marquerContexte(a);
      await depot.enregistrerDeconnexion(a);
      c = (await db.query('contexte')).first;
      expect(c['utilisateur_id'], isNull);
      expect(await evenements(), containsAll(['verrouillage_inactivite', 'deconnexion']));
    });
  });

  group('Paramètres', () {
    test('lecture, écriture, valeurs par défaut', () async {
      final p = ParametreDepot(db);
      expect(await p.lire('x'), isNull);
      expect(await p.lireEntier('n', 30), 30);
      expect(await p.lireBool('b', true), isTrue);
      await p.ecrire('n', '45');
      await p.ecrireBool('b', false);
      expect(await p.lireEntier('n', 30), 45);
      expect(await p.lireBool('b', true), isFalse);
      await p.ecrire('n', 'abc');
      expect(await p.lireEntier('n', 30), 30);
      await p.supprimer('n');
      expect(await p.lire('n'), isNull);
      expect(await p.tous(), {'b': '0'});
    });
  });
}
