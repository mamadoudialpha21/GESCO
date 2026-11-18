import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/domain/mot_de_passe.dart';
import 'package:gesco/domain/permissions.dart';

void main() {
  group('Permissions et rôles', () {
    test('un administrateur a toutes les permissions, quoi qu\'on lui configure', () {
      expect(
        permissionsEffectives(RoleUtilisateur.administrateur, {Permission.notesVoir}),
        Permission.values.toSet(),
      );
      expect(
        permissionsEffectives(RoleUtilisateur.administrateur, null),
        Permission.values.toSet(),
      );
    });

    test('la consultation ne contient aucune permission de modification', () {
      final p = permissionsDuRole(RoleUtilisateur.consultation);
      for (final interdite in [
        Permission.notesSaisir,
        Permission.anneesGerer,
        Permission.classesGerer,
        Permission.elevesGerer,
        Permission.elevesSupprimer,
        Permission.etablissementModifier,
        Permission.parametresGerer,
        Permission.utilisateursGerer,
        Permission.sauvegardeRestaurer,
        Permission.journalVoir,
      ]) {
        expect(p.contains(interdite), isFalse, reason: interdite.cle);
      }
      expect(p, contains(Permission.notesVoir));
      expect(p, contains(Permission.documentsGenerer));
    });

    test('le rôle saisie peut saisir mais ni gérer les comptes ni restaurer', () {
      final p = permissionsDuRole(RoleUtilisateur.saisie);
      expect(p, contains(Permission.notesSaisir));
      expect(p, contains(Permission.evaluationsGerer));
      expect(p.contains(Permission.utilisateursGerer), isFalse);
      expect(p.contains(Permission.classesGerer), isFalse);
      expect(p.contains(Permission.sauvegardeRestaurer), isFalse);
    });

    test('la direction gère tout sauf les comptes et la restauration', () {
      final p = permissionsDuRole(RoleUtilisateur.direction);
      expect(p, contains(Permission.anneesGerer));
      expect(p, contains(Permission.journalVoir));
      expect(p.contains(Permission.utilisateursGerer), isFalse);
      expect(p.contains(Permission.sauvegardeRestaurer), isFalse);
    });

    test('une liste personnalisée remplace celle du rôle', () {
      final p = permissionsEffectives(
        RoleUtilisateur.consultation,
        {Permission.notesVoir, Permission.notesSaisir},
      );
      expect(p, {Permission.notesVoir, Permission.notesSaisir});
    });

    test('chaque permission a une clé unique et retrouvable', () {
      final cles = Permission.values.map((p) => p.cle).toList();
      expect(cles.toSet().length, cles.length);
      for (final p in Permission.values) {
        expect(Permission.depuisCle(p.cle), p);
      }
      expect(Permission.depuisCle('inconnue'), isNull);
    });

    test('un rôle inconnu retombe sur la consultation', () {
      expect(RoleUtilisateurInfo.depuisCle('nimportequoi'), RoleUtilisateur.consultation);
      for (final r in RoleUtilisateur.values) {
        expect(RoleUtilisateurInfo.depuisCle(r.cle), r);
      }
    });

    test('les groupes couvrent toutes les permissions', () {
      final total = permissionsParGroupe().values.fold<int>(0, (a, l) => a + l.length);
      expect(total, Permission.values.length);
    });
  });

  group('Identifiants', () {
    test('accepte des identifiants simples', () {
      for (final i in ['admin', 'm.diallo', 'prof-maths', 'a_b', 'ABC123']) {
        expect(validerIdentifiant(i), isNull, reason: i);
      }
    });

    test('refuse trop court, trop long, accents ou espaces', () {
      expect(validerIdentifiant('ab'), isNotNull);
      expect(validerIdentifiant('a' * 31), isNotNull);
      expect(validerIdentifiant('élève'), isNotNull);
      expect(validerIdentifiant('deux mots'), isNotNull);
      expect(validerIdentifiant('a@b'), isNotNull);
    });

    test('les espaces autour sont ignorés', () {
      expect(validerIdentifiant('  admin  '), isNull);
    });
  });

  group('Mots de passe', () {
    test('accepte un mot de passe correct', () {
      expect(validerMotDePasse('Tombolia26'), isNull);
    });

    test('refuse trop court', () {
      expect(validerMotDePasse('abc12'), isNotNull);
    });

    test('refuse les mots de passe courants, sans tenir compte de la casse', () {
      expect(validerMotDePasse('123456'), isNotNull);
      expect(validerMotDePasse('Password'), isNotNull);
      expect(validerMotDePasse('AZERTY'), isNotNull);
    });

    test('refuse un mot de passe identique à l\'identifiant', () {
      expect(validerMotDePasse('professeur', identifiant: 'Professeur'), isNotNull);
      expect(validerMotDePasse('professeur', identifiant: 'autre'), isNull);
    });

    test('refuse les espaces seuls et le même caractère répété', () {
      expect(validerMotDePasse('       '), isNotNull);
      expect(validerMotDePasse('aaaaaaaa'), isNotNull);
    });

    test('refuse un mot de passe démesuré', () {
      expect(validerMotDePasse('a1' * 65), isNotNull);
    });
  });
}
