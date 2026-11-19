/// Lecture et affichage de ce que l'utilisateur tape dans une case de note.
///
/// Dart pur : testable sans interface ni base de données.
library;

import 'arrondi.dart';
import 'bareme.dart';
import 'modeles.dart';

/// Texte affiché dans une case absente / dispensée.
const String texteAbsent = 'ABS';
const String texteDispense = 'DISP';

/// Résultat de la lecture d'un texte saisi : case vidée, saisie valide ou
/// saisie invalide (avec un message à afficher).
class LectureNote {
  const LectureNote.vide()
      : saisie = null,
        erreur = null;

  const LectureNote.valide(Saisie this.saisie) : erreur = null;

  const LectureNote.invalide(String this.erreur) : saisie = null;

  /// Contenu à enregistrer (null si la case est vidée ou invalide).
  final Saisie? saisie;

  /// Message d'erreur (null si la saisie est valide ou vide).
  final String? erreur;

  bool get estInvalide => erreur != null;
  bool get estVide => saisie == null && erreur == null;
  bool get estValide => saisie != null;
}

String _sansAccents(String texte) => texte
    .toLowerCase()
    .replaceAll('é', 'e')
    .replaceAll('è', 'e')
    .replaceAll('ê', 'e');

/// Lit un texte tapé dans une case de note.
///
/// - vide : la case est vidée (note « non saisie ») ;
/// - `A`, `ABS`, `absent` : élève absent ;
/// - `D`, `DISP`, `dispensé` : élève dispensé ;
/// - un nombre de 0 à [bareme] (20 par défaut), virgule ou point, 2 décimales
///   au plus. Sur un barème autre que 20, la note est conservée telle quelle
///   et convertie sur 20 pour les moyennes.
LectureNote lireNoteSaisie(String texte, {int bareme = baremeParDefaut}) {
  final brut = texte.trim();
  if (brut.isEmpty) return const LectureNote.vide();

  final mot = _sansAccents(brut);
  if (mot == 'a' || mot == 'abs' || mot == 'absent' || mot == 'absente') {
    return const LectureNote.valide(Saisie.absent());
  }
  if (mot == 'd' ||
      mot == 'disp' ||
      mot == 'dispense' ||
      mot == 'dispensee') {
    return const LectureNote.valide(Saisie.dispense());
  }

  final valeur = analyserNoteSurBareme(brut, bareme);
  if (valeur != null) {
    return LectureNote.valide(
      bareme == baremeParDefaut
          ? Saisie.valeur(valeur)
          : Saisie.surBareme(valeur, bareme),
    );
  }

  final nombre = RegExp(r'^(\d+)(?:[.,](\d*))?$').firstMatch(brut);
  if (nombre != null) {
    final decimales = nombre.group(2) ?? '';
    if (decimales.length > 2) {
      return LectureNote.invalide(
        '« $brut » a trop de décimales : 2 chiffres au plus après la virgule.',
      );
    }
    return LectureNote.invalide(
      '« $brut » dépasse $bareme : la note doit être entre 0 et $bareme.',
    );
  }
  return LectureNote.invalide(
    '« $brut » n\'est pas une note valide : entrez un nombre de 0 à $bareme '
    '(ex. ${_exemple(bareme)}), A pour absent ou D pour dispensé.',
  );
}

/// Exemple de note décimale plausible pour un barème (14,5 sur 20).
String _exemple(int bareme) => '${bareme * 7 ~/ 10},5';

/// Texte affiché pour le contenu d'une case (vide si « non saisie »).
String texteSaisie(Saisie? saisie) {
  if (saisie == null) return '';
  switch (saisie.etat) {
    case EtatNote.saisie:
      return formaterCentiemes(saisie.centiemesSaisis);
    case EtatNote.absent:
      return texteAbsent;
    case EtatNote.dispense:
      return texteDispense;
  }
}

/// Moyenne (centièmes, arrondie demi vers le haut) des valeurs non nulles,
/// ou null s'il n'y en a aucune. Les valeurs nulles (case vide, absent,
/// dispensé) sont ignorées : elles ne comptent jamais comme zéro.
int? moyenneDe(Iterable<int?> centiemes) {
  var somme = 0;
  var nombre = 0;
  for (final v in centiemes) {
    if (v != null) {
      somme += v;
      nombre++;
    }
  }
  if (nombre == 0) return null;
  return divisionArrondie(somme, nombre);
}
