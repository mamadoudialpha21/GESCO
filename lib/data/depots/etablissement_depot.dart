import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/permissions.dart';
import '../controle.dart';
import '../erreurs.dart';
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
      directeur: (l['directeur'] as String?) ?? '',
      devise: (l['devise'] as String?) ?? '',
      infosAdmin: (l['infos_admin'] as String?) ?? '',
      signatureDirecteur: l['signature_directeur'] as Uint8List?,
      cachet: l['cachet'] as Uint8List?,
    );
  }

  static const int longueurMaxDirecteur = 120;
  static const int longueurMaxDevise = 200;
  static const int longueurMaxInfos = 600;

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
    final signature = etablissement.signatureDirecteur;
    if (signature != null) {
      verifierImage(signature, tailleMax: tailleMaxLogo, nom: 'La signature');
    }
    final cachet = etablissement.cachet;
    if (cachet != null) {
      verifierImage(cachet, tailleMax: tailleMaxLogo, nom: 'Le cachet');
    }
    void longueur(String valeur, int max, String nom) {
      if (valeur.trim().length > max) {
        throw ErreurGesco('$nom est trop long ($max caractères au maximum).');
      }
    }

    longueur(etablissement.directeur, longueurMaxDirecteur, 'Le nom du directeur');
    longueur(etablissement.devise, longueurMaxDevise, 'La devise');
    longueur(etablissement.infosAdmin, longueurMaxInfos, 'Les informations administratives');
    await _db.insert(
      'etablissement',
      {
        'id': 1,
        'nom': etablissement.nom.trim(),
        'adresse': etablissement.adresse.trim(),
        'telephone': etablissement.telephone.trim(),
        'email': etablissement.email.trim(),
        'logo': logo,
        'directeur': etablissement.directeur.trim(),
        'devise': etablissement.devise.trim(),
        'infos_admin': etablissement.infosAdmin.trim(),
        'signature_directeur': signature,
        'cachet': cachet,
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
