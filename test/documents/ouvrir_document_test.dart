import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/documents/elements_pdf.dart';
import 'package:gesco/documents/ouvrir_document.dart';

DocumentPdf pdf(List<int> octets) =>
    DocumentPdf(octets: Uint8List.fromList(octets), pages: 1);

void main() {
  group('nom de fichier sûr', () {
    test('accents et espaces', () {
      expect(nomDeFichierSur('Bulletin Élève Diallo Aminata'), 'Bulletin_Eleve_Diallo_Aminata');
      expect(nomDeFichierSur('Classement 10e A — Trimestre 1'), 'Classement_10e_A_Trimestre_1');
      expect(nomDeFichierSur('Œuvre Çà'), 'OEuvre_Ca');
    });

    test('caractères interdits sous Windows', () {
      expect(nomDeFichierSur(r'a/b\c:d*e?f"g<h>i|j'), 'a_b_c_d_e_f_g_h_i_j');
    });

    test('jamais vide, jamais de point ni de tiret bas en bout', () {
      expect(nomDeFichierSur(''), 'document');
      expect(nomDeFichierSur('...'), 'document');
      expect(nomDeFichierSur('  __x__  '), 'x');
      expect(nomDeFichierSur('../../secret'), 'secret');
    });

    test('longueur limitée', () {
      expect(nomDeFichierSur('a' * 300).length, 80);
    });
  });

  group('enregistrement du PDF', () {
    late Directory dossier;
    final instant = DateTime(2026, 11, 20, 8, 5, 9);

    setUp(() => dossier = Directory.systemTemp.createTempSync('gesco_pdf_'));
    tearDown(() => dossier.deleteSync(recursive: true));

    test('nom horodaté, contenu intact, aucun fichier temporaire', () async {
      final f = await enregistrerPdf(
        pdf([37, 80, 68, 70, 45, 1, 2, 3]),
        'Bulletin Élève',
        dossier: dossier,
        maintenant: instant,
      );
      expect(f.path.endsWith('Bulletin_Eleve_20261120-080509.pdf'), isTrue);
      expect(f.readAsBytesSync(), [37, 80, 68, 70, 45, 1, 2, 3]);
      expect([for (final e in dossier.listSync()) e.path.split(Platform.pathSeparator).last],
          ['Bulletin_Eleve_20261120-080509.pdf']);
    });

    test('ne remplace jamais un fichier existant', () async {
      final a = await enregistrerPdf(pdf([1]), 'Doc', dossier: dossier, maintenant: instant);
      final b = await enregistrerPdf(pdf([2]), 'Doc', dossier: dossier, maintenant: instant);
      final c = await enregistrerPdf(pdf([3]), 'Doc', dossier: dossier, maintenant: instant);
      expect({a.path, b.path, c.path}.length, 3);
      expect(b.path.endsWith('_2.pdf'), isTrue);
      expect(c.path.endsWith('_3.pdf'), isTrue);
      expect(a.readAsBytesSync(), [1]);
      expect(b.readAsBytesSync(), [2]);
      expect(c.readAsBytesSync(), [3]);
    });

    test('crée le dossier s\'il n\'existe pas', () async {
      final sous = Directory('${dossier.path}/a/b');
      final f = await enregistrerPdf(pdf([1]), 'Doc', dossier: sous, maintenant: instant);
      expect(f.existsSync(), isTrue);
    });
  });
}
