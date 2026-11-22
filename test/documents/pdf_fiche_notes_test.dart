import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/documents/elements_pdf.dart';
import 'package:gesco/documents/modele_fiche_notes.dart';
import 'package:gesco/documents/pdf_fiche_notes.dart';
import 'package:gesco/documents/polices_pdf.dart';
import 'package:gesco/documents/styles_bulletin.dart';

import 'exemples.dart';

void verifierPdf(DocumentPdf pdf) {
  expect(String.fromCharCodes(pdf.octets.take(5)), '%PDF-');
  final fin = String.fromCharCodes(pdf.octets.sublist(pdf.octets.length - 16));
  expect(fin, contains('%%EOF'));
  expect(pdf.octets.length, greaterThan(3000));
}

FicheNotes fiche({
  int nbEleves = 20,
  String? matiere = 'Mathématiques',
  List<String> intitules = const ['Note 1', 'Note 2', 'Note 3'],
  bool avecMatricule = true,
  bool avecSexe = false,
  bool avecObservations = true,
  String enseignant = 'KANTE Moussa',
}) =>
    FicheNotes(
      entete: const EnteteEtablissement(
        nom: 'Groupe Scolaire Test',
        adresse: 'Tombolia, Conakry',
        telephone: '622 00 00 00',
        devise: 'Travail - Justice - Solidarité',
      ),
      classeNom: '10e A',
      anneeLibelle: '2026-2027',
      matiereNom: matiere,
      enseignant: enseignant,
      periode: 'Novembre',
      intitules: intitules,
      avecMatricule: avecMatricule,
      avecSexe: avecSexe,
      avecObservations: avecObservations,
      lignes: [
        for (var i = 1; i <= nbEleves; i++)
          LigneFicheNotes(
            numero: i,
            nom: 'ÉLÈVE${i.toString().padLeft(2, '0')} Aminata-Binta',
            matricule: '2026-${i.toString().padLeft(4, '0')}',
            sexe: i.isEven ? 'F' : 'M',
          ),
      ],
      dateEdition: DateTime(2026, 11, 22),
    );

void main() {
  late PolicesPdf p;
  setUpAll(() => p = polices());

  Future<DocumentPdf> generer(
    List<FicheNotes> fiches, {
    StyleBulletin style = StyleBulletin.classiqueBleu,
  }) =>
      genererFichesNotesPdf(fiches, style: style, polices: p);

  group('fiche de notes', () {
    for (final style in StyleBulletin.tous) {
      test('${style.nom} : PDF valide, une page pour vingt élèves', () async {
        final pdf = await generer([fiche()], style: style);
        verifierPdf(pdf);
        expect(pdf.pages, 1);
      });
    }

    test('une classe nombreuse continue sur plusieurs pages', () async {
      final pdf = await generer([fiche(nbEleves: 90)]);
      verifierPdf(pdf);
      expect(pdf.pages, greaterThan(1));
      expect(pdf.pages, lessThanOrEqualTo(5));
    });

    test('trente-cinq élèves : une ou deux pages', () async {
      final pdf = await generer([fiche(nbEleves: 35)]);
      verifierPdf(pdf);
      expect(pdf.pages, inInclusiveRange(1, 2));
    });

    test('toutes les options : sexe, dix colonnes, sans matricule ni observations', () async {
      final pdf = await generer([
        fiche(
          intitules: [for (var i = 1; i <= 10; i++) 'Note $i'],
          avecSexe: true,
          avecMatricule: false,
          avecObservations: false,
        ),
      ]);
      verifierPdf(pdf);
    });

    test('sans enseignant : la ligne reste à remplir à la main', () async {
      verifierPdf(await generer([fiche(enseignant: '')]));
    });

    test('classe vide : PDF valide avec un message', () async {
      final pdf = await generer([fiche(nbEleves: 0)]);
      verifierPdf(pdf);
      expect(pdf.pages, 1);
    });
  });

  group('liste de classe', () {
    test('sans matière ni colonne de notes', () async {
      final pdf = await generer([fiche(matiere: null, intitules: const [])]);
      verifierPdf(pdf);
      expect(pdf.pages, 1);
    });
  });

  group('plusieurs fiches', () {
    test('chaque fiche commence sur une nouvelle page', () async {
      final pdf = await generer([
        fiche(nbEleves: 10, matiere: 'Mathématiques'),
        fiche(nbEleves: 10, matiere: 'Français'),
        fiche(nbEleves: 10, matiere: 'Anglais'),
      ]);
      verifierPdf(pdf);
      expect(pdf.pages, 3);
    });

    test('aucune fiche : erreur claire', () async {
      expect(() => generer(const []), throwsArgumentError);
    });
  });

  group('orientation', () {
    test('portrait jusqu\'à sept colonnes, paysage au-delà', () {
      FicheNotes avec(int notes, {bool obs = true}) =>
          fiche(intitules: [for (var i = 0; i < notes; i++) 'N$i'], avecObservations: obs);
      expect(ficheEnPaysage(avec(3)), isFalse);
      expect(ficheEnPaysage(avec(6)), isFalse); // 6 + observations = 7
      expect(ficheEnPaysage(avec(7)), isTrue);
      expect(ficheEnPaysage(avec(7, obs: false)), isFalse);
      expect(ficheEnPaysage(avec(8, obs: false)), isTrue);
    });
  });
}
