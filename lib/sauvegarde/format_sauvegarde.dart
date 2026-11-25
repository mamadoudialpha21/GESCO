import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../data/erreurs.dart';
import 'zip_simple.dart';

/// Version de GESCO qui écrit les sauvegardes. À garder égale à celle de
/// `pubspec.yaml` (elle sert seulement à informer l'utilisateur).
const String versionApplicationGesco = '0.4.0';

/// Nom du fichier de base de données dans l'archive.
const String nomBaseDansArchive = 'gesco.db';

/// Nom du descriptif dans l'archive.
const String nomManifeste = 'manifeste.json';

/// Nom de la notice lisible dans l'archive.
const String nomNotice = 'LISEZ-MOI.txt';

/// Descriptif d'une sauvegarde, écrit dans l'archive (`manifeste.json`).
///
/// Format documenté dans `docs/FORMAT_SAUVEGARDE.md`.
class ManifesteSauvegarde {
  const ManifesteSauvegarde({
    required this.versionSchema,
    required this.versionApplication,
    required this.creeLe,
    required this.type,
    required this.utilisateur,
    required this.etablissement,
    required this.annee,
    required this.contenu,
    required this.sha256,
    required this.taille,
  });

  /// Nom du format, pour reconnaître une sauvegarde GESCO.
  static const String format = 'GESCO-SAUVEGARDE';

  /// Version du format de l'archive.
  static const int versionFormat = 1;

  /// Version du schéma de la base contenue (`PRAGMA user_version`).
  final int versionSchema;
  final String versionApplication;

  /// Date et heure locales de la copie, au format ISO 8601.
  final String creeLe;

  /// manuelle, automatique, securite.
  final String type;

  /// Nom de la personne connectée (ou « Système » pour une sauvegarde automatique).
  final String utilisateur;
  final String etablissement;

  /// Année scolaire active au moment de la copie (libellé), ou vide.
  final String annee;

  /// Nombre de lignes de quelques tables : élèves, classes, notes, comptes...
  final Map<String, int> contenu;

  /// Empreinte SHA-256 (hexadécimale) du fichier `gesco.db` de l'archive.
  final String sha256;

  /// Taille en octets de `gesco.db`.
  final int taille;

  DateTime? get date => DateTime.tryParse(creeLe);

  Map<String, Object?> toJson() => {
        'format': format,
        'version_format': versionFormat,
        'version_schema': versionSchema,
        'version_application': versionApplication,
        'cree_le': creeLe,
        'type': type,
        'utilisateur': utilisateur,
        'etablissement': etablissement,
        'annee': annee,
        'contenu': contenu,
        'base': {'fichier': nomBaseDansArchive, 'sha256': sha256, 'taille': taille},
      };

  factory ManifesteSauvegarde.depuisJson(Object? json) {
    ErreurGesco invalide(String detail) => ErreurGesco(
          'Ce fichier n\'est pas une sauvegarde GESCO reconnue ($detail).',
        );
    if (json is! Map) throw invalide('descriptif illisible');
    if (json['format'] != format) throw invalide('format inconnu');
    final v = json['version_format'];
    if (v is! int) throw invalide('version du format absente');
    if (v > versionFormat) {
      throw const ErreurGesco(
        'Cette sauvegarde a été créée par une version plus récente de GESCO. '
        'Installez la dernière version de GESCO pour la restaurer.',
      );
    }
    final base = json['base'];
    if (base is! Map || base['sha256'] is! String || base['taille'] is! int) {
      throw invalide('empreinte de la base absente');
    }
    final schema = json['version_schema'];
    if (schema is! int) throw invalide('version de la base absente');
    final contenu = json['contenu'];
    return ManifesteSauvegarde(
      versionSchema: schema,
      versionApplication: '${json['version_application'] ?? ''}',
      creeLe: '${json['cree_le'] ?? ''}',
      type: '${json['type'] ?? ''}',
      utilisateur: '${json['utilisateur'] ?? ''}',
      etablissement: '${json['etablissement'] ?? ''}',
      annee: '${json['annee'] ?? ''}',
      contenu: {
        if (contenu is Map)
          for (final e in contenu.entries)
            if (e.value is int) '${e.key}': e.value as int,
      },
      sha256: base['sha256'] as String,
      taille: base['taille'] as int,
    );
  }
}

/// Empreinte SHA-256 en hexadécimal.
String empreinte(List<int> octets) => sha256.convert(octets).toString();

/// Texte de la notice placée dans chaque archive : elle explique comment
/// retrouver les données même sans GESCO.
String noticeSauvegarde(ManifesteSauvegarde m) => '''
SAUVEGARDE GESCO
================

Cette archive (fichier .zip) est une sauvegarde complète de GESCO.
Créée le : ${m.creeLe}
Établissement : ${m.etablissement.isEmpty ? '(non renseigné)' : m.etablissement}
Par : ${m.utilisateur}
Version de GESCO : ${m.versionApplication}

Contenu
-------
- gesco.db       : la base de données SQLite de GESCO (élèves, classes, notes,
                   évaluations, enseignants, comptes utilisateurs avec leurs
                   permissions, paramètres et journaux). Les mots de passe y
                   sont enregistrés sous forme hachée, jamais en clair.
- manifeste.json : le descriptif de la sauvegarde (version, date, empreinte
                   SHA-256 de gesco.db, nombre d'élèves, de notes...).
- LISEZ-MOI.txt  : ce fichier.

Restaurer sur cet ordinateur ou sur un autre
--------------------------------------------
1. Installez GESCO (même version ou plus récente).
2. Ouvrez GESCO, connectez-vous, puis Sécurité > Sauvegardes >
   « Restaurer une sauvegarde » et choisissez ce fichier.
3. GESCO vérifie le fichier, fait une sauvegarde de sécurité des données
   actuelles, puis remplace les données. En cas de problème, les données
   précédentes sont remises en place automatiquement.

Ne modifiez pas le contenu de l'archive : GESCO refuse un fichier dont
l'empreinte ne correspond plus.
''';

/// Construit l'archive d'une sauvegarde.
Uint8List construireArchive(Uint8List base, ManifesteSauvegarde manifeste, {DateTime? date}) {
  final json = const JsonEncoder.withIndent('  ').convert(manifeste.toJson());
  return ecrireZip(
    [
      EntreeZip(nomManifeste, Uint8List.fromList(utf8.encode(json))),
      EntreeZip(nomNotice, Uint8List.fromList(utf8.encode(noticeSauvegarde(manifeste)))),
      EntreeZip(nomBaseDansArchive, base),
    ],
    date: date,
    compresser: (e) => e.nom == nomBaseDansArchive,
  );
}

/// Contenu lu et contrôlé d'une archive.
class ArchiveLue {
  const ArchiveLue(this.manifeste, this.base);

  final ManifesteSauvegarde manifeste;
  final Uint8List base;
}

/// Lit une archive : structure, descriptif, taille et empreinte de la base.
/// Lève une [ErreurGesco] lisible au moindre doute.
ArchiveLue lireArchive(Uint8List octets) {
  final entrees = lireZip(octets);
  EntreeZip? cherche(String nom) {
    for (final e in entrees) {
      if (e.nom == nom) return e;
    }
    return null;
  }

  final descriptif = cherche(nomManifeste);
  final base = cherche(nomBaseDansArchive);
  if (descriptif == null || base == null) {
    throw const ErreurGesco(
      'Ce fichier est une archive, mais pas une sauvegarde GESCO '
      '(manifeste.json ou gesco.db manquant).',
    );
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(descriptif.octets));
  } catch (_) {
    throw const ErreurGesco('Le descriptif de la sauvegarde est illisible.');
  }
  final manifeste = ManifesteSauvegarde.depuisJson(json);
  if (base.octets.length != manifeste.taille) {
    throw const ErreurGesco(
      'La base de données de la sauvegarde est incomplète (taille différente de celle annoncée).',
    );
  }
  if (empreinte(base.octets) != manifeste.sha256) {
    throw const ErreurGesco(
      'La base de données de la sauvegarde a été modifiée ou abîmée '
      '(empreinte SHA-256 différente de celle annoncée) : elle ne sera pas utilisée.',
    );
  }
  return ArchiveLue(manifeste, base.octets);
}
