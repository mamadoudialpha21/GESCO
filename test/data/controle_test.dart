import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_securite.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher refus([String action = '']) => throwsA(
      isA<ErreurGesco>().having(
        (e) => e.message,
        'message',
        allOf(contains('pas l\'autorisation'), contains(action)),
      ),
    );

Utilisateur compte(
  RoleUtilisateur role, {
  int id = 1,
  String identifiant = 'u1',
  Set<Permission>? permissions,
  int? enseignantId,
  bool actif = true,
}) =>
    Utilisateur(
      id: id,
      identifiant: identifiant,
      nomComplet: 'Compte $identifiant',
      role: role,
      actif: actif,
      creeLe: '2026-01-01T00:00:00',
      permissionsPersonnalisees: permissions,
      enseignantId: enseignantId,
    );

Eleve eleve(String matricule) => Eleve(
      matricule: matricule,
      nom: 'DIALLO',
      prenom: 'Aminata',
      sexe: 'F',
    );

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Session session;
  late Services s;

  setUp(() async {
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    session = Session();
    s = Services(gdb, session: session, iterations: 2);
  });

  tearDown(() async {
    await gdb.fermer();
  });

  /// Une année, une classe, une matière et un élève créés par l'administrateur.
  Future<({AnneeScolaire annee, Classe classe, MatiereClasse maths, int inscription})>
      donnees() async {
    session.ouvrir(compte(RoleUtilisateur.administrateur, id: 9, identifiant: 'chef'));
    final annee = await s.annees.creer('2026-2027');
    final classe = await s.classes.creer(anneeId: annee.id, nom: '10e A');
    final maths = await s.matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
    final inscription = await s.eleves.inscrire(
      eleve('2026-0001'),
      anneeId: annee.id,
      classeId: classe.id,
    );
    return (annee: annee, classe: classe, maths: maths, inscription: inscription);
  }

  group('Sans connexion', () {
    test('aucune opération n\'est possible tant que personne n\'est connecté', () async {
      await expectLater(
        s.annees.creer('2026-2027'),
        throwsA(
          isA<ErreurGesco>().having((e) => e.message, 'message', contains('Connectez-vous')),
        ),
      );
      await expectLater(s.classes.creer(anneeId: 1, nom: 'X'), throwsA(isA<ErreurGesco>()));
      await expectLater(
        s.etablissements.enregistrer(const Etablissement(nom: 'X')),
        throwsA(isA<ErreurGesco>()),
      );
      await expectLater(
        s.notes.enregistrer(
          inscriptionId: 1,
          matiereId: 1,
          mois: 10,
          saisie: Saisie.valeur(1000),
        ),
        throwsA(isA<ErreurGesco>()),
      );
    });

    test('la session sans contrôle (tests, outils) autorise tout', () async {
      final libre = Services(gdb);
      final annee = await libre.annees.creer('2026-2027');
      expect(annee.libelle, '2026-2027');
      expect(libre.session.controle, isFalse);
      expect(libre.session.connectee, isTrue);
    });

    test('une session verrouillée n\'autorise plus rien', () async {
      session.ouvrir(compte(RoleUtilisateur.administrateur));
      await s.annees.creer('2026-2027');
      session.verrouiller();
      await expectLater(s.annees.creer('2027-2028'), throwsA(isA<ErreurGesco>()));
      session.ouvrir(compte(RoleUtilisateur.administrateur));
      await s.annees.creer('2027-2028');
    });

    test('un compte désactivé n\'a aucune permission', () async {
      session.ouvrir(compte(RoleUtilisateur.administrateur, actif: false));
      await expectLater(s.annees.creer('2026-2027'), throwsA(isA<ErreurGesco>()));
    });
  });

  group('Rôle consultation', () {
    setUp(() async {
      await donnees();
      session.ouvrir(compte(RoleUtilisateur.consultation, id: 2, identifiant: 'lecteur'));
    });

    test('peut lire mais pas modifier', () async {
      expect(await s.annees.lister(), hasLength(1));
      expect(await s.classes.lister((await s.annees.lister()).first.id), hasLength(1));
      final annee = (await s.annees.lister()).first;
      final classe = (await s.classes.lister(annee.id)).first.classe;

      await expectLater(s.annees.creer('2027-2028'), refus('créer une année'));
      await expectLater(s.annees.activer(annee.id), refus());
      await expectLater(s.annees.supprimer(annee.id), refus());
      await expectLater(s.classes.creer(anneeId: annee.id, nom: 'Autre'), refus('créer une classe'));
      await expectLater(s.classes.modifier(classe.id, nom: 'X', niveau: ''), refus());
      await expectLater(s.classes.supprimer(classe.id), refus());
      await expectLater(
        s.matieres.ajouter(classeId: classe.id, nom: 'Physique', coefficient: 200),
        refus('ajouter une matière'),
      );
      await expectLater(s.matieres.copier(depuisClasseId: classe.id, versClasseId: classe.id), refus());
      await expectLater(s.matieres.reordonner(classe.id, []), refus());
      await expectLater(
        s.eleves.inscrire(eleve('2026-0002'), anneeId: annee.id, classeId: classe.id),
        refus('inscrire'),
      );
      await expectLater(s.eleves.supprimerInscription(1), refus('supprimer un élève'));
      await expectLater(
        s.etablissements.enregistrer(const Etablissement(nom: 'Pirate')),
        refus('modifier la fiche'),
      );
      await expectLater(s.configs.enregistrer(annee.id, ConfigResultats.defaut), refus());
      await expectLater(s.calendriers.enregistrer(annee.id, Calendrier.defaut), refus());
      await expectLater(s.calendriers.reinitialiser(annee.id), refus());
    });

    test('ne peut pas saisir de notes ni gérer les comptes', () async {
      await expectLater(
        s.notes.enregistrer(inscriptionId: 1, matiereId: 1, mois: 10, saisie: Saisie.valeur(1200)),
        refus('saisir des notes'),
      );
      await expectLater(
        s.utilisateurs.creer(
          identifiant: 'intrus',
          role: RoleUtilisateur.administrateur,
          motDePasse: 'Provisoire1',
        ),
        refus('créer un compte'),
      );
      await expectLater(s.utilisateurs.definirActif(9, false), refus());
      await expectLater(s.utilisateurs.supprimer(9), refus());
      await expectLater(s.utilisateurs.reinitialiserMotDePasse(9, 'Provisoire1'), refus());
      await expectLater(s.utilisateurs.nouveauCodeRecuperation(), refus());
      expect(await s.utilisateurs.compter(), 0);
    });

    test('rien n\'a changé après les refus', () async {
      final annee = (await s.annees.lister()).first;
      expect(await s.annees.lister(), hasLength(1));
      expect(await s.classes.lister(annee.id), hasLength(1));
      expect(await s.eleves.lister(annee.id), hasLength(1));
      expect((await s.etablissements.lire()).nom, isEmpty);
    });
  });

  group('Rôle saisie', () {
    test('saisit des notes mais ne touche pas aux classes', () async {
      final d = await donnees();
      session.ouvrir(compte(RoleUtilisateur.saisie, id: 3, identifiant: 'saisie'));
      await s.notes.enregistrer(
        inscriptionId: d.inscription,
        matiereId: d.maths.id,
        mois: 10,
        saisie: Saisie.valeur(1275),
      );
      final saisies = await s.notes.lireClasse(d.classe.id);
      expect(saisies[d.inscription]![d.maths.id]![10]!.centiemes, 1275);
      await expectLater(s.classes.supprimer(d.classe.id), refus());
      await expectLater(
        s.eleves.inscrire(eleve('2026-0002'), anneeId: d.annee.id, classeId: d.classe.id),
        refus(),
      );
    });

    test('lié à un enseignant, ne saisit que ses matières', () async {
      final d = await donnees();
      final physique = await s.matieres.ajouter(classeId: d.classe.id, nom: 'Physique', coefficient: 200);
      final prof = await gdb.db.insert('enseignant', {
        'nom': 'BARRY',
        'prenom': 'Oumar',
        'cree_le': '2026-10-01T08:00:00',
      });
      await gdb.db.update(
        'matiere_classe',
        {'enseignant_id': prof},
        where: 'id = ?',
        whereArgs: [d.maths.id],
      );
      session.ouvrir(
        compte(RoleUtilisateur.saisie, id: 4, identifiant: 'barry', enseignantId: prof),
      );
      expect(session.enseignantLimite, prof);

      await s.notes.enregistrer(
        inscriptionId: d.inscription,
        matiereId: d.maths.id,
        mois: 10,
        saisie: Saisie.valeur(1400),
      );
      await expectLater(
        s.notes.enregistrer(
          inscriptionId: d.inscription,
          matiereId: physique.id,
          mois: 10,
          saisie: Saisie.valeur(1400),
        ),
        throwsA(
          isA<ErreurGesco>().having((e) => e.message, 'message', contains('qui vous sont confiées')),
        ),
      );
      // Vider une case d'une matière qui n'est pas la sienne est aussi refusé.
      await expectLater(
        s.notes.enregistrer(
          inscriptionId: d.inscription,
          matiereId: physique.id,
          mois: 10,
          saisie: null,
        ),
        throwsA(isA<ErreurGesco>()),
      );
    });

    test('un compte de saisie sans enseignant associé n\'est pas limité', () async {
      final d = await donnees();
      session.ouvrir(compte(RoleUtilisateur.saisie, id: 3, identifiant: 'saisie'));
      expect(session.enseignantLimite, isNull);
      await s.notes.enregistrer(
        inscriptionId: d.inscription,
        matiereId: d.maths.id,
        mois: 11,
        saisie: Saisie.valeur(900),
      );
    });
  });

  group('Permissions personnalisées', () {
    test('une permission retirée au rôle est refusée, une ajoutée est accordée', () async {
      final d = await donnees();
      session.ouvrir(
        compte(
          RoleUtilisateur.consultation,
          id: 5,
          identifiant: 'secretaire',
          permissions: {Permission.elevesVoir, Permission.elevesGerer},
        ),
      );
      final inscription2 = await s.eleves.inscrire(
        eleve('2026-0002'),
        anneeId: d.annee.id,
        classeId: d.classe.id,
      );
      expect(inscription2, greaterThan(0));
      await expectLater(s.classes.creer(anneeId: d.annee.id, nom: 'Autre'), refus());
      await expectLater(s.eleves.supprimerInscription(inscription2), refus());
    });
  });

  group('Journal des opérations', () {
    test('chaque modification est notée avec son auteur', () async {
      final d = await donnees();
      await s.classes.modifier(d.classe.id, nom: '10e B', niveau: '10e');
      await s.matieres.modifier(d.maths.id, coefficient: 500);
      await s.etablissements.enregistrer(const Etablissement(nom: 'Groupe Scolaire Nialy'));

      final lignes = await s.journal.lister(limite: 50);
      final resume = [for (final l in lignes.reversed) '${l.action}/${l.entite}'];
      expect(
        resume,
        containsAllInOrder([
          'creation/annee',
          'creation/classe',
          'creation/matiere',
          'inscription/eleve',
          'modification/classe',
          'modification/matiere',
          'modification/etablissement',
        ]),
      );
      expect(lignes.every((l) => l.utilisateurNom.isEmpty), isTrue,
          reason: 'sans marquerContexte, l\'auteur n\'est pas renseigné en base');
    });

    test('l\'auteur est celui indiqué dans le contexte de la base', () async {
      await s.utilisateurs.creerPremierAdministrateur(
        identifiant: 'chef',
        nomComplet: 'Chef Établissement',
        motDePasse: 'Tombolia26',
      );
      final chef = (await s.utilisateurs.parIdentifiant('chef'))!;
      session.ouvrir(chef);
      await s.utilisateurs.marquerContexte(chef);
      await s.annees.creer('2026-2027');
      final l = (await s.journal.lister()).first;
      expect(l.utilisateurNom, 'Chef Établissement');
      expect(l.action, 'creation');
      expect(l.entite, 'annee');
      expect(l.details, '2026-2027');
    });

    test('une opération refusée n\'est pas journalisée', () async {
      await donnees();
      final avant = await s.journal.compter();
      session.ouvrir(compte(RoleUtilisateur.consultation, id: 2, identifiant: 'lecteur'));
      await expectLater(s.annees.creer('2027-2028'), throwsA(isA<ErreurGesco>()));
      expect(await s.journal.compter(), avant);
    });

    test('une opération qui échoue pour une autre raison n\'est pas journalisée', () async {
      await donnees();
      final avant = await s.journal.compter();
      await expectLater(s.annees.creer('2026-2027'), throwsA(isA<ErreurGesco>())); // doublon
      await expectLater(s.classes.supprimer(9999), throwsA(isA<ErreurGesco>()));
      expect(await s.journal.compter(), avant);
    });

    test('la suppression d\'un élève avec ses notes est signalée', () async {
      final d = await donnees();
      await s.notes.enregistrer(
        inscriptionId: d.inscription,
        matiereId: d.maths.id,
        mois: 10,
        saisie: Saisie.valeur(1000),
      );
      await s.eleves.supprimerInscription(d.inscription, avecNotes: true);
      final l = (await s.journal.lister()).first;
      expect(l.action, 'suppression');
      expect(l.entite, 'eleve');
      expect(l.details, contains('DIALLO Aminata'));
      expect(l.details, contains('notes supprimées'));
    });

    test('les opérations sur les comptes sont notées', () async {
      await donnees();
      final u = await s.utilisateurs.creer(
        identifiant: 'prof1',
        role: RoleUtilisateur.saisie,
        motDePasse: 'Provisoire1',
      );
      await s.utilisateurs.modifierProfil(u.id, nomComplet: 'P', role: RoleUtilisateur.direction);
      await s.utilisateurs.definirActif(u.id, false);
      await s.utilisateurs.reinitialiserMotDePasse(u.id, 'Provisoire2');
      await s.utilisateurs.supprimer(u.id);
      final actions = [
        for (final l in (await s.journal.lister(limite: 50)).reversed)
          if (l.entite == 'utilisateur') l.action,
      ];
      expect(actions, [
        'creation',
        'modification',
        'desactivation',
        'reinitialisation_mdp',
        'suppression',
      ]);
    });

    test('le journal ne contient jamais de mot de passe', () async {
      await donnees();
      await s.utilisateurs.creer(
        identifiant: 'prof1',
        role: RoleUtilisateur.saisie,
        motDePasse: 'Provisoire1',
      );
      final tout = (await s.journal.lister(limite: 100)).map((l) => l.details).join('|');
      expect(tout.contains('Provisoire1'), isFalse);
    });
  });

  group('JournalDepot', () {
    test('recherche, filtre par entité et pagination', () async {
      final d = await donnees();
      for (var i = 0; i < 7; i++) {
        await s.classes.creer(anneeId: d.annee.id, nom: 'Classe $i');
      }
      final total = await s.journal.compter();
      expect(total, greaterThanOrEqualTo(11));
      expect(await s.journal.compter(entite: 'classe'), 8);
      expect(await s.journal.compter(recherche: 'Classe 3'), 1);
      expect(await s.journal.compter(recherche: 'introuvable'), 0);

      final page1 = await s.journal.lister(limite: 5);
      final page2 = await s.journal.lister(limite: 5, decalage: 5);
      expect(page1, hasLength(5));
      expect(page2.map((e) => e.id).toSet().intersection(page1.map((e) => e.id).toSet()), isEmpty);
      // Du plus récent au plus ancien.
      final ids = (await s.journal.lister(limite: 100)).map((e) => e.id).toList();
      expect(ids, [...ids]..sort((a, b) => b.compareTo(a)));
      expect((await s.journal.recentes(3)), hasLength(3));
    });

    test('historique des notes : recherche et décompte', () async {
      final d = await donnees();
      await s.notes.enregistrer(
        inscriptionId: d.inscription,
        matiereId: d.maths.id,
        mois: 10,
        saisie: Saisie.valeur(1000),
      );
      await s.notes.enregistrer(
        inscriptionId: d.inscription,
        matiereId: d.maths.id,
        mois: 10,
        saisie: Saisie.valeur(1100),
      );
      expect(await s.journal.compterHistoriqueNotes(), 2);
      expect(await s.journal.compterHistoriqueNotes(recherche: 'Maths'), 2);
      expect(await s.journal.compterHistoriqueNotes(recherche: 'Physique'), 0);
      expect(await s.journal.compterHistoriqueNotes(inscriptionId: d.inscription), 2);
      final h = await s.journal.historiqueNotes(recherche: 'DIALLO');
      expect(h, hasLength(2));
      expect(h.first.ancienneValeur, 1000);
      expect(h.first.nouvelleValeur, 1100);
      expect(h.first.matiereNom, 'Maths');
    });

    test('journal des connexions : décompte avec recherche', () async {
      await s.utilisateurs.creerPremierAdministrateur(identifiant: 'chef', motDePasse: 'Tombolia26');
      await expectLater(s.utilisateurs.authentifier('chef', 'faux'), throwsA(isA<ErreurGesco>()));
      await s.utilisateurs.authentifier('chef', 'Tombolia26');
      expect(await s.journal.compterConnexions(), 3);
      expect(await s.journal.compterConnexions(recherche: 'echec'), 1);
      expect((await s.journal.listerConnexions(recherche: 'echec')).single.identifiant, 'chef');
    });
  });
}
