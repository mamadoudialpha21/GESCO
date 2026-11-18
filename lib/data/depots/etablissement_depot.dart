import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/permissions.dart';
import '../controle.dart';
import '../images.dart';
import '../modeles_donnees.dart';

/// Lecture et enregistrement de la fiche de l'établissement (nom, adresse,
/// coordonnées, logo). Le logo est conservé dans la base : il suit les
/// sauvegardes et apparaît sur tous les documents imprimables.
class EtablissementDepot {
  EtablissementDepot(this._db, {this.controle = Controle.aucun});

  final Database _db;
  final Controle controle;

  Future<Etablissement> lire() async {
    final lignes = await _db.query('etablissement', where: 'id = 1');
    if (lignes.isEmpty) return const Etablissement();
    final l = lignes.first;
    return Etablissement(
      nom: (l['nom'] as String?) ?? '',
      adresse: (l['adresse'] as String?) ?? '',
      telephone: (l['telephone'] as String?) ?? '',
      email: (l['email'] as String?) ?? '',
      logo: l['logo'] as Uint8List?,
    );
  }

  /// Enregistre toute la fiche. Le logo est vérifié (PNG ou JPEG, 2 Mo max) ;
  /// un logo null supprime le logo existant.
  Future<void> enregistrer(Etablissement etablissement) async {
    controle.exiger(
      Permission.etablissementModifier,
      'modifier la fiche de l\'établissement',
    );
    final logo = etablissement.logo;
    if (logo != null) {
      verifierImage(logo, tailleMax: tailleMaxLogo, nom: 'Le logo');
    }
    await _db.insert(
      'etablissement',
      {
        'id': 1,
        'nom': etablissement.nom.trim(),
        'adresse': etablissement.adresse.trim(),
        'telephone': etablissement.telephone.trim(),
        'email': etablissement.email.trim(),
        'logo': logo,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await controle.noter(
      'modification',
      'etablissement',
      id: 1,
      details: etablissement.nom.trim(),
    );
  }
}
