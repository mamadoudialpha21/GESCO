import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../data/erreurs.dart';

/// Un fichier contenu dans une archive.
class EntreeZip {
  const EntreeZip(this.nom, this.octets);

  final String nom;
  final Uint8List octets;
}

/// Lecture et écriture d'archives .zip (format standard : Windows, macOS et
/// tous les outils de compression savent les ouvrir). Seules les fonctions
/// utiles aux sauvegardes sont gérées : méthodes « stockée » et « deflate »,
/// pas de mot de passe, pas de zip64 (fichiers de moins de 4 Go).

int _crcTable(int n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
}

final List<int> _table = [for (var n = 0; n < 256; n++) _crcTable(n)];

/// Somme de contrôle CRC-32 (celle des fichiers .zip).
int crc32(List<int> octets) {
  var c = 0xFFFFFFFF;
  for (final b in octets) {
    c = _table[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

const int _signatureLocale = 0x04034b50;
const int _signatureCentrale = 0x02014b50;
const int _signatureFin = 0x06054b50;
const int _methodeStockee = 0;
const int _methodeDeflate = 8;
const int _tailleMax = 0x7FFFFFFF;

int _heureDos(DateTime d) => (d.hour << 11) | (d.minute << 5) | (d.second ~/ 2);

int _dateDos(DateTime d) {
  final annee = d.year < 1980 ? 1980 : d.year;
  return ((annee - 1980) << 9) | (d.month << 5) | d.day;
}

/// Construit une archive. Les fichiers dont [compresser] est vrai sont
/// compressés (deflate) quand cela les rend plus petits.
Uint8List ecrireZip(
  List<EntreeZip> entrees, {
  DateTime? date,
  bool Function(EntreeZip)? compresser,
}) {
  final maintenant = date ?? DateTime.now();
  final corps = BytesBuilder(copy: false);
  final annuaire = BytesBuilder(copy: false);

  for (final e in entrees) {
    if (e.octets.length > _tailleMax) {
      throw ErreurGesco('Le fichier « ${e.nom} » est trop volumineux pour une archive.');
    }
    final nom = utf8.encode(e.nom);
    var methode = _methodeStockee;
    var donnees = e.octets;
    if (compresser?.call(e) ?? false) {
      final comprime = Uint8List.fromList(ZLibCodec(raw: true, level: 6).encode(e.octets));
      if (comprime.length < e.octets.length) {
        methode = _methodeDeflate;
        donnees = comprime;
      }
    }
    final crc = crc32(e.octets);
    final decalage = corps.length;

    final local = ByteData(30)
      ..setUint32(0, _signatureLocale, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 0x0800, Endian.little) // noms en UTF-8
      ..setUint16(8, methode, Endian.little)
      ..setUint16(10, _heureDos(maintenant), Endian.little)
      ..setUint16(12, _dateDos(maintenant), Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, donnees.length, Endian.little)
      ..setUint32(22, e.octets.length, Endian.little)
      ..setUint16(26, nom.length, Endian.little)
      ..setUint16(28, 0, Endian.little);
    corps
      ..add(local.buffer.asUint8List())
      ..add(nom)
      ..add(donnees);

    final central = ByteData(46)
      ..setUint32(0, _signatureCentrale, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0x0800, Endian.little)
      ..setUint16(10, methode, Endian.little)
      ..setUint16(12, _heureDos(maintenant), Endian.little)
      ..setUint16(14, _dateDos(maintenant), Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, donnees.length, Endian.little)
      ..setUint32(24, e.octets.length, Endian.little)
      ..setUint16(28, nom.length, Endian.little)
      ..setUint16(30, 0, Endian.little)
      ..setUint16(32, 0, Endian.little)
      ..setUint16(34, 0, Endian.little)
      ..setUint16(36, 0, Endian.little)
      ..setUint32(38, 0, Endian.little)
      ..setUint32(42, decalage, Endian.little);
    annuaire
      ..add(central.buffer.asUint8List())
      ..add(nom);
  }

  final debutAnnuaire = corps.length;
  final fin = ByteData(22)
    ..setUint32(0, _signatureFin, Endian.little)
    ..setUint16(4, 0, Endian.little)
    ..setUint16(6, 0, Endian.little)
    ..setUint16(8, entrees.length, Endian.little)
    ..setUint16(10, entrees.length, Endian.little)
    ..setUint32(12, annuaire.length, Endian.little)
    ..setUint32(16, debutAnnuaire, Endian.little)
    ..setUint16(20, 0, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(corps.takeBytes())
        ..add(annuaire.takeBytes())
        ..add(fin.buffer.asUint8List()))
      .takeBytes();
}

ErreurGesco _illisible([String? detail]) => ErreurGesco(
      'Ce fichier n\'est pas une sauvegarde GESCO lisible'
      '${detail == null ? '' : ' ($detail)'}. '
      'Il est peut-être incomplet ou abîmé : refaites la copie depuis son emplacement d\'origine.',
    );

/// Lit toutes les entrées d'une archive et vérifie leur somme de contrôle.
List<EntreeZip> lireZip(Uint8List octets) {
  if (octets.length < 22) throw _illisible('fichier trop court');
  final vue = ByteData.sublistView(octets);

  // Fin d'archive : on la cherche en partant de la fin (un commentaire est possible).
  var fin = -1;
  final plusHaut = octets.length - 22;
  final plusBas = plusHaut > 65535 ? plusHaut - 65535 : 0;
  for (var i = plusHaut; i >= plusBas; i--) {
    if (vue.getUint32(i, Endian.little) == _signatureFin) {
      fin = i;
      break;
    }
  }
  if (fin < 0) throw _illisible('fin d\'archive introuvable');

  final nombre = vue.getUint16(fin + 10, Endian.little);
  final decalageAnnuaire = vue.getUint32(fin + 16, Endian.little);
  if (decalageAnnuaire >= octets.length) throw _illisible('annuaire hors du fichier');

  final entrees = <EntreeZip>[];
  var p = decalageAnnuaire;
  for (var i = 0; i < nombre; i++) {
    if (p + 46 > octets.length || vue.getUint32(p, Endian.little) != _signatureCentrale) {
      throw _illisible('annuaire abîmé');
    }
    final methode = vue.getUint16(p + 10, Endian.little);
    final crc = vue.getUint32(p + 16, Endian.little);
    final tailleComprimee = vue.getUint32(p + 20, Endian.little);
    final tailleReelle = vue.getUint32(p + 24, Endian.little);
    final longNom = vue.getUint16(p + 28, Endian.little);
    final longExtra = vue.getUint16(p + 30, Endian.little);
    final longCommentaire = vue.getUint16(p + 32, Endian.little);
    final decalageLocal = vue.getUint32(p + 42, Endian.little);
    if (p + 46 + longNom > octets.length) throw _illisible('nom hors du fichier');
    final nom = utf8.decode(octets.sublist(p + 46, p + 46 + longNom), allowMalformed: true);
    p += 46 + longNom + longExtra + longCommentaire;

    if (decalageLocal + 30 > octets.length ||
        vue.getUint32(decalageLocal, Endian.little) != _signatureLocale) {
      throw _illisible('en-tête de « $nom » abîmé');
    }
    final localNom = vue.getUint16(decalageLocal + 26, Endian.little);
    final localExtra = vue.getUint16(decalageLocal + 28, Endian.little);
    final debut = decalageLocal + 30 + localNom + localExtra;
    final finDonnees = debut + tailleComprimee;
    if (finDonnees > octets.length) throw _illisible('« $nom » est tronqué');

    final brut = Uint8List.sublistView(octets, debut, finDonnees);
    final Uint8List contenu;
    if (methode == _methodeStockee) {
      contenu = brut;
    } else if (methode == _methodeDeflate) {
      try {
        contenu = Uint8List.fromList(ZLibCodec(raw: true).decode(brut));
      } catch (_) {
        throw _illisible('« $nom » ne se décompresse pas');
      }
    } else {
      throw _illisible('méthode de compression $methode non gérée');
    }
    if (contenu.length != tailleReelle || crc32(contenu) != crc) {
      throw _illisible('« $nom » est abîmé (somme de contrôle différente)');
    }
    entrees.add(EntreeZip(nom, contenu));
  }
  return entrees;
}
