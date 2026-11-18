import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/modeles_securite.dart';
import 'package:gesco/domain/permissions.dart';

Utilisateur compte(RoleUtilisateur role, {int? enseignantId}) => Utilisateur(
      id: 1,
      identifiant: 'u1',
      nomComplet: 'Compte Un',
      role: role,
      actif: true,
      creeLe: '2026-01-01T00:00:00',
      enseignantId: enseignantId,
    );

void main() {
  final t0 = DateTime(2026, 11, 17, 8);

  group('Session avec contrôle', () {
    test('au départ, personne n\'est connecté et rien n\'est permis', () {
      final s = Session();
      expect(s.controle, isTrue);
      expect(s.connectee, isFalse);
      expect(s.aUtilisateur, isFalse);
      expect(s.peut(Permission.tableauDeBord), isFalse);
      expect(s.enseignantLimite, isNull);
    });

    test('ouvrir donne les permissions du rôle, fermer les retire', () {
      final s = Session();
      s.ouvrir(compte(RoleUtilisateur.consultation), maintenant: t0);
      expect(s.connectee, isTrue);
      expect(s.peut(Permission.notesVoir), isTrue);
      expect(s.peut(Permission.notesSaisir), isFalse);
      s.fermer();
      expect(s.connectee, isFalse);
      expect(s.utilisateur, isNull);
      expect(s.peut(Permission.notesVoir), isFalse);
    });

    test('verrouiller retire les permissions mais garde l\'utilisateur', () {
      final s = Session();
      s.ouvrir(compte(RoleUtilisateur.administrateur), maintenant: t0);
      s.verrouiller();
      expect(s.verrouillee, isTrue);
      expect(s.connectee, isFalse);
      expect(s.utilisateur, isNotNull);
      expect(s.peut(Permission.anneesGerer), isFalse);
      s.ouvrir(compte(RoleUtilisateur.administrateur), maintenant: t0);
      expect(s.verrouillee, isFalse);
      expect(s.peut(Permission.anneesGerer), isTrue);
    });

    test('verrouiller sans utilisateur ne fait rien', () {
      final s = Session();
      s.verrouiller();
      expect(s.verrouillee, isFalse);
    });

    test('notifie ses écouteurs', () {
      final s = Session();
      var appels = 0;
      s.addListener(() => appels++);
      s.ouvrir(compte(RoleUtilisateur.saisie), maintenant: t0);
      s.verrouiller();
      s.fermer();
      expect(appels, 3);
    });

    test('actualiser met à jour le compte connecté, pas un autre', () {
      final s = Session();
      s.ouvrir(compte(RoleUtilisateur.consultation), maintenant: t0);
      s.actualiser(compte(RoleUtilisateur.saisie));
      expect(s.peut(Permission.notesSaisir), isTrue);
      s.actualiser(
        Utilisateur(
          id: 99,
          identifiant: 'autre',
          nomComplet: '',
          role: RoleUtilisateur.administrateur,
          actif: true,
          creeLe: '2026-01-01T00:00:00',
        ),
      );
      expect(s.utilisateur!.id, 1);
      expect(s.peut(Permission.utilisateursGerer), isFalse);
    });

    test('la limite par enseignant ne concerne que le rôle saisie lié à un enseignant', () {
      final s = Session();
      s.ouvrir(compte(RoleUtilisateur.saisie, enseignantId: 7), maintenant: t0);
      expect(s.enseignantLimite, 7);
      s.ouvrir(compte(RoleUtilisateur.saisie), maintenant: t0);
      expect(s.enseignantLimite, isNull);
      s.ouvrir(compte(RoleUtilisateur.direction, enseignantId: 7), maintenant: t0);
      expect(s.enseignantLimite, isNull);
    });
  });

  group('Inactivité', () {
    test('verrouille après le délai sans activité', () {
      final s = Session(delaiInactivite: const Duration(minutes: 10));
      s.ouvrir(compte(RoleUtilisateur.administrateur), maintenant: t0);
      expect(s.verifierInactivite(t0.add(const Duration(minutes: 9, seconds: 59))), isFalse);
      expect(s.verrouillee, isFalse);
      expect(s.verifierInactivite(t0.add(const Duration(minutes: 10))), isTrue);
      expect(s.verrouillee, isTrue);
    });

    test('l\'activité repousse le verrouillage', () {
      final s = Session(delaiInactivite: const Duration(minutes: 10));
      s.ouvrir(compte(RoleUtilisateur.administrateur), maintenant: t0);
      s.activite(t0.add(const Duration(minutes: 8)));
      expect(s.verifierInactivite(t0.add(const Duration(minutes: 15))), isFalse);
      expect(s.verifierInactivite(t0.add(const Duration(minutes: 18))), isTrue);
    });

    test('une session déjà verrouillée n\'est pas verrouillée deux fois', () {
      final s = Session(delaiInactivite: const Duration(minutes: 1));
      s.ouvrir(compte(RoleUtilisateur.administrateur), maintenant: t0);
      expect(s.verifierInactivite(t0.add(const Duration(minutes: 2))), isTrue);
      expect(s.verifierInactivite(t0.add(const Duration(minutes: 3))), isFalse);
    });

    test('un délai nul désactive le verrouillage automatique', () {
      final s = Session(delaiInactivite: Duration.zero);
      s.ouvrir(compte(RoleUtilisateur.administrateur), maintenant: t0);
      expect(s.verifierInactivite(t0.add(const Duration(days: 3))), isFalse);
      expect(s.verrouillee, isFalse);
    });

    test('sans utilisateur, rien à verrouiller', () {
      final s = Session(delaiInactivite: const Duration(minutes: 1));
      expect(s.verifierInactivite(t0.add(const Duration(days: 1))), isFalse);
    });

    test('l\'activité d\'une session verrouillée est ignorée', () {
      final s = Session(delaiInactivite: const Duration(minutes: 1));
      s.ouvrir(compte(RoleUtilisateur.administrateur), maintenant: t0);
      s.verrouiller();
      s.activite(t0.add(const Duration(minutes: 30)));
      expect(s.verrouillee, isTrue);
    });
  });

  group('Session sans contrôle', () {
    test('tout est permis, aucune connexion n\'est demandée', () {
      final s = Session.sansControle();
      expect(s.controle, isFalse);
      expect(s.connectee, isTrue);
      expect(s.aUtilisateur, isTrue);
      for (final p in Permission.values) {
        expect(s.peut(p), isTrue);
      }
      expect(s.enseignantLimite, isNull);
      expect(s.verifierInactivite(DateTime(2100)), isFalse);
    });
  });
}
