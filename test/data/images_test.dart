import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/images.dart';

void main() {
  const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0];
  const jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0];

  group('detecterTypeImage', () {
    test('reconnaît PNG et JPEG d\'après leurs premiers octets', () {
      expect(detecterTypeImage(png), TypeImage.png);
      expect(detecterTypeImage(jpeg), TypeImage.jpeg);
    });

    test('refuse le reste', () {
      expect(detecterTypeImage(const []), isNull);
      expect(detecterTypeImage(const [1, 2, 3]), isNull);
      expect(detecterTypeImage('GIF89a'.codeUnits), isNull);
      expect(detecterTypeImage('%PDF-1.7'.codeUnits), isNull);
      // PNG tronqué (signature incomplète)
      expect(detecterTypeImage(png.sublist(0, 7)), isNull);
      // Signature PNG presque correcte
      expect(detecterTypeImage([...png.sublist(0, 7), 0x0B]), isNull);
      // JPEG tronqué
      expect(detecterTypeImage(const [0xFF, 0xD8]), isNull);
    });
  });

  group('verifierImage', () {
    test('accepte une image valide dans la limite de taille', () {
      verifierImage(png, tailleMax: 100, nom: 'Le logo');
      verifierImage(jpeg, tailleMax: jpeg.length, nom: 'La photo');
    });

    test('refuse vide, trop gros et format inconnu avec un message clair', () {
      expect(
        () => verifierImage(const [], tailleMax: 100, nom: 'Le logo'),
        throwsA(
          isA<ErreurGesco>().having((e) => e.message, 'message', 'Le logo est vide.'),
        ),
      );
      expect(
        () => verifierImage(png, tailleMax: 5, nom: 'La photo'),
        throwsA(
          isA<ErreurGesco>().having(
            (e) => e.message,
            'message',
            contains('La photo est trop volumineux'),
          ),
        ),
      );
      expect(
        () => verifierImage(const [1, 2, 3], tailleMax: 100, nom: 'Le logo'),
        throwsA(
          isA<ErreurGesco>().having((e) => e.message, 'message', contains('PNG ou JPEG')),
        ),
      );
    });

    test('tailles maximales : logo 2 Mo, photo 1 Mo', () {
      expect(tailleMaxLogo, 2 * 1024 * 1024);
      expect(tailleMaxPhoto, 1024 * 1024);
    });
  });
}
