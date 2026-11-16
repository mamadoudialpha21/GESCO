import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/images.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/validation_eleve.dart';

Uint8List png([int taille = 12]) {
  final octets = Uint8List(taille);
  octets.setRange(0, 8, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  return octets;
}

void main() {
  final maintenant = DateTime(2026, 10, 1, 8);

  Eleve valide({
    String matricule = 'M001',
    String nom = 'DIALLO',
    String prenom = 'Aminata',
    String sexe = 'F',
    String? naissance = '2011-03-05',
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

  List<String> erreurs(Eleve e) => erreursEleve(e, maintenant: maintenant);

  test('une fiche complète est valide', () {
    expect(erreurs(valide()), isEmpty);
  });

  test('une fiche minimale est valide (date et photo facultatives)', () {
    expect(erreurs(valide(naissance: null)), isEmpty);
  });

  test('nom, prénom et matricule obligatoires', () {
    expect(erreurs(valide(nom: '  ')), ['Le nom est obligatoire.']);
    expect(erreurs(valide(prenom: '')), ['Le prénom est obligatoire.']);
    expect(erreurs(valide(matricule: ' ')), ['Le matricule est obligatoire.']);
  });

  test('le sexe doit être M ou F', () {
    expect(erreurs(valide(sexe: 'X')), hasLength(1));
    expect(erreurs(valide(sexe: '')), hasLength(1));
    expect(erreurs(valide(sexe: 'M')), isEmpty);
  });

  test('longueurs maximales', () {
    expect(erreurs(valide(nom: 'x' * 60)), isEmpty);
    expect(erreurs(valide(nom: 'x' * 61)), ['Le nom est trop long (60 caractères maximum).']);
    expect(erreurs(valide(prenom: 'x' * 61)), hasLength(1));
    expect(erreurs(valide(matricule: 'x' * 40)), isEmpty);
    expect(erreurs(valide(matricule: 'x' * 41)), hasLength(1));
    final longue = valide().copyWith(adresse: 'x' * 121);
    expect(erreurs(longue), ['L\'adresse est trop long (120 caractères maximum).']);
    expect(erreurs(valide().copyWith(adresse: 'x' * 120)), isEmpty);
  });

  group('date de naissance', () {
    test('invalide', () {
      expect(erreurs(valide(naissance: '2011-02-30')), ['La date de naissance est invalide.']);
      expect(erreurs(valide(naissance: '05/03/2011')), ['La date de naissance est invalide.']);
      expect(erreurs(valide(naissance: '')), ['La date de naissance est invalide.']);
    });

    test('dans le futur refusée, aujourd\'hui acceptée', () {
      expect(
        erreurs(valide(naissance: '2026-10-02')),
        ['La date de naissance ne peut pas être dans le futur.'],
      );
      expect(erreurs(valide(naissance: '2026-10-01')), isEmpty);
      expect(erreurs(valide(naissance: '2026-09-30')), isEmpty);
    });
  });

  group('photo', () {
    test('PNG valide acceptée', () {
      expect(erreurs(valide(photo: png())), isEmpty);
    });

    test('limite de 1 Mo : exactement 1 Mo accepté, 1 octet de plus refusé', () {
      expect(erreurs(valide(photo: png(tailleMaxPhoto))), isEmpty);
      expect(
        erreurs(valide(photo: png(tailleMaxPhoto + 1))),
        ['La photo est trop volumineux (maximum 1024 Ko).'],
      );
    });

    test('format inconnu refusé', () {
      expect(
        erreurs(valide(photo: Uint8List.fromList([1, 2, 3, 4]))),
        ['La photo doit être une image PNG ou JPEG.'],
      );
    });
  });

  test('toutes les erreurs sont listées ensemble', () {
    final e = Eleve(
      matricule: '',
      nom: '',
      prenom: '',
      sexe: '?',
      dateNaissance: 'xx',
    );
    expect(erreurs(e), hasLength(5));
  });

  group('Eleve', () {
    test('nomComplet : nom en majuscules, prénom tel quel', () {
      expect(valide(nom: 'Diallo', prenom: 'Aminata').nomComplet, 'DIALLO Aminata');
    });

    test('copyWith conserve les autres champs et permet de retirer date et photo', () {
      final e = valide(photo: png()).copyWith(nomPere: 'Alpha');
      expect(e.nomPere, 'Alpha');
      expect(e.nom, 'DIALLO');
      expect(e.photo, isNotNull);
      final sans = e.copyWith(supprimerPhoto: true, supprimerDate: true);
      expect(sans.photo, isNull);
      expect(sans.dateNaissance, isNull);
      expect(sans.nomPere, 'Alpha');
    });
  });
}
