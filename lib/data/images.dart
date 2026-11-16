import 'erreurs.dart';

/// Formats d'image acceptés (compatibles avec la génération des PDF).
enum TypeImage { png, jpeg }

/// Taille maximale d'un logo : 2 Mo.
const int tailleMaxLogo = 2 * 1024 * 1024;

/// Taille maximale d'une photo d'élève : 1 Mo.
const int tailleMaxPhoto = 1024 * 1024;

/// Reconnaît PNG et JPEG d'après leurs premiers octets (et non d'après
/// l'extension du fichier, qui peut être fausse). Null si format inconnu.
TypeImage? detecterTypeImage(List<int> octets) {
  const signaturePng = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (octets.length >= signaturePng.length) {
    var estPng = true;
    for (var i = 0; i < signaturePng.length; i++) {
      if (octets[i] != signaturePng[i]) {
        estPng = false;
        break;
      }
    }
    if (estPng) return TypeImage.png;
  }
  if (octets.length >= 3 &&
      octets[0] == 0xFF &&
      octets[1] == 0xD8 &&
      octets[2] == 0xFF) {
    return TypeImage.jpeg;
  }
  return null;
}

/// Lève une [ErreurGesco] si [octets] n'est pas une image PNG/JPEG de taille
/// acceptable. [nom] est le sujet de la phrase : « Le logo », « La photo ».
void verifierImage(
  List<int> octets, {
  required int tailleMax,
  required String nom,
}) {
  if (octets.isEmpty) {
    throw ErreurGesco('$nom est vide.');
  }
  if (octets.length > tailleMax) {
    throw ErreurGesco(
      '$nom est trop volumineux (maximum ${tailleMax ~/ 1024} Ko).',
    );
  }
  if (detecterTypeImage(octets) == null) {
    throw ErreurGesco('$nom doit être une image PNG ou JPEG.');
  }
}
