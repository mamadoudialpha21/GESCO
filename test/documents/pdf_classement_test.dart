import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/documents/modele_classement.dart';
import 'package:gesco/documents/pdf_classement.dart';
import 'package:gesco/documents/polices_pdf.dart';
import 'package:gesco/documents/styles_bulletin.dart';

import 'exemples.dart';

void verifierPdf(DocumentPdf pdf) {
  expect(String.fromCharCodes(pdf.octets.take(5)), '%PDF-');
  final fin = String.fromCharCodes(pdf.octets.sublist(pdf.octets.length - 16));
  expect(fin, contains('%%EOF'));
  expect(pdf.octets.length, greaterThan(5000));
}

void main() {
  late PolicesPdf p;
  setUpAll(() => p = polices());

  Future<DocumentPdf> generer(
    DocumentClassement d, {
    StyleBulletin style = StyleBulletin.classiqueBleu,
  }) =>
      genererClassementPdf(d, style: style, polices: p);

  group('classement général', () {
    for (final style in StyleBulletin.tous) {
      test('${style.nom} : PDF valide', () async {
        final pdf = await generer(classementExemple(), style: style);
        verifierPdf(pdf);
        expect(pdf.pages, 1);
      });
    }

    test('une classe nombreuse continue sur plusieurs pages', () async {
      final pdf = await generer(classementExemple(nbEleves: 90));
      verifierPdf(pdf);
      expect(pdf.pages, greaterThan(1));
      expect(pdf.pages, lessThanOrEqualTo(4));
    });

    test('quarante élèves : une ou deux pages', () async {
      final pdf = await generer(classementExemple(nbEleves: 40));
      verifierPdf(pdf);
      expect(pdf.pages, inInclusiveRange(1, 2));
    });
  });

  group('autres présentations', () {
    test('résultats annuels avec colonnes de périodes', () async {
      final pdf = await generer(classementExemple(annuel: true));
      verifierPdf(pdf);
      expect(pdf.pages, 1);
    });

    test('classement dans une matière, sans décision ni statistiques', () async {
      final pdf = await generer(classementExemple(parMatiere: true, avecStats: false));
      verifierPdf(pdf);
      expect(pdf.pages, 1);
    });

    test('sans image', () async {
      verifierPdf(await generer(classementExemple(avecImages: false)));
    });

    test('classe sans élève', () async {
      final base = classementExemple(avecStats: false, avecImages: false);
      final vide = DocumentClassement(
        entete: base.entete,
        titre: base.titre,
        classeNom: base.classeNom,
        lignes: const [],
      );
      final pdf = await generer(vide);
      verifierPdf(pdf);
      expect(pdf.pages, 1);
    });
  });
}
