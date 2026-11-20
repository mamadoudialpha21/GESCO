import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/documents/modele_bulletin.dart';
import 'package:gesco/documents/pdf_bulletin.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late PolicesPdf p;
  setUpAll(() => p = polices());

  Future<DocumentPdf> generer(
    List<Bulletin> bulletins, {
    StyleBulletin style = StyleBulletin.classiqueBleu,
  }) =>
      genererBulletinsPdf(bulletins, style: style, polices: p);

  group('les huit styles', () {
    test('la liste contient les huit styles demandés, sans doublon', () {
      expect(StyleBulletin.tous.length, 8);
      expect({for (final s in StyleBulletin.tous) s.id}.length, 8);
      expect([for (final s in StyleBulletin.tous) s.nom], [
        'Classique bleu',
        'Couleurs guinéennes',
        'Élégant rose',
        'Moderne anthracite',
        'Minimaliste noir et blanc',
        'Bleu et or',
        'Vert sauge',
        'Violet',
      ]);
    });

    test('retrouver un style par son identifiant, style classique si inconnu', () {
      for (final s in StyleBulletin.tous) {
        expect(StyleBulletin.parId(s.id), same(s));
      }
      expect(StyleBulletin.parId('inconnu'), same(StyleBulletin.classiqueBleu));
      expect(StyleBulletin.parId(null), same(StyleBulletin.classiqueBleu));
    });

    for (final style in StyleBulletin.tous) {
      test('${style.nom} : un PDF valide d\'une seule page A4', () async {
        final pdf = await generer([bulletinExemple()], style: style);
        verifierPdf(pdf);
        expect(pdf.pages, 1);
      });
    }
  });

  group('contenu variable', () {
    test('mensuel, trimestriel et annuel', () async {
      for (final type in TypeBulletin.values) {
        final pdf = await generer([bulletinExemple(type: type)]);
        verifierPdf(pdf);
        expect(pdf.pages, 1, reason: '$type');
      }
    });

    test('sans image ni appréciation', () async {
      final pdf = await generer([
        bulletinExemple(
          avecImages: false,
          avecAppreciationsMatieres: false,
          avecAppreciationGenerale: false,
        ),
      ]);
      verifierPdf(pdf);
      expect(pdf.pages, 1);
    });

    test('élève sans aucune note', () async {
      final pdf = await generer([bulletinExemple(avecMoyenne: false)]);
      verifierPdf(pdf);
      expect(pdf.pages, 1);
    });

    test('résultat incomplet', () async {
      verifierPdf(await generer([bulletinExemple(incomplet: true)]));
    });

    test('classe sans matière', () async {
      final b = bulletinExemple(nbMatieres: 0, avecMoyenne: false);
      expect(b.lignes, isEmpty);
      final pdf = await generer([b]);
      verifierPdf(pdf);
      expect(pdf.pages, 1);
    });

    test('caractères français, noms longs et signes particuliers', () async {
      final pdf = await generer([
        bulletinExemple(
          nom: 'ŒUVRE-ÇAÏDOU',
          prenom: 'Zoé-Éléonore « Æsha » – N\'Zérékoré',
          matricule: 'n° 2026/0012',
        ),
      ]);
      verifierPdf(pdf);
    });

    test('images illisibles : ignorées sans faire échouer le document', () async {
      final b = bulletinExemple();
      final abime = Bulletin(
        type: b.type,
        periodeLibelle: b.periodeLibelle,
        anneeLibelle: b.anneeLibelle,
        etablissementNom: b.etablissementNom,
        logo: Uint8List.fromList([1, 2, 3, 4]),
        signature: Uint8List(0),
        cachet: Uint8List.fromList([9, 9, 9]),
        classeNom: b.classeNom,
        eleveNom: b.eleveNom,
        elevePrenom: b.elevePrenom,
        matricule: b.matricule,
        sexe: b.sexe,
        photo: Uint8List.fromList([0, 0, 0]),
        lignes: b.lignes,
        effectif: b.effectif,
      );
      final pdf = await generer([abime]);
      verifierPdf(pdf);
      expect(pdf.pages, 1);
    });
  });

  group('nombre de matières et de pages', () {
    test('beaucoup de matières tiennent sur une page A4', () async {
      for (final n in [1, 8, 12, 16, 20]) {
        final pdf = await generer([bulletinExemple(nbMatieres: n, avecAppreciationsMatieres: false)]);
        expect(pdf.pages, 1, reason: '$n matières');
      }
    });

    test('douze matières avec appréciations de chaque matière : une page', () async {
      final pdf = await generer([bulletinExemple(nbMatieres: 12)]);
      expect(pdf.pages, 1);
    });

    test('un très grand nombre de matières continue sur la page suivante', () async {
      final pdf = await generer([bulletinExemple(nbMatieres: 30)]);
      verifierPdf(pdf);
      expect(pdf.pages, greaterThan(1));
      expect(pdf.pages, lessThanOrEqualTo(3));
    });

    test('une page par bulletin pour toute une classe', () async {
      final liste = [
        for (var i = 0; i < 6; i++) bulletinExemple(nom: 'ELEVE$i', matricule: '2026-00$i'),
      ];
      final pdf = await generer(liste);
      verifierPdf(pdf);
      expect(pdf.pages, 6);
    });

    test('quarante bulletins : un fichier de taille raisonnable', () async {
      final pdf = await generer([
        for (var i = 0; i < 40; i++) bulletinExemple(nom: 'ELEVE$i', matricule: '2026-$i'),
      ]);
      verifierPdf(pdf);
      expect(pdf.pages, 40);
      // Logo, cachet, signature et polices ne doivent pas être répétés à chaque
      // page : une classe entière reste bien en dessous de quelques mégaoctets.
      expect(pdf.octets.length, lessThan(3 * 1024 * 1024));
    });
  });

  group('erreurs', () {
    test('aucun bulletin : erreur claire', () async {
      await expectLater(generer(const []), throwsA(isA<ArgumentError>()));
    });
  });

  group('polices de l\'application', () {
    test('chargées depuis les ressources déclarées dans pubspec.yaml', () async {
      final depuisRessources = await PolicesPdf.charger();
      final pdf = await genererBulletinsPdf(
        [bulletinExemple()],
        style: StyleBulletin.elegantRose,
        polices: depuisRessources,
      );
      verifierPdf(pdf);
      expect(pdf.pages, 1);
    });
  });
}
