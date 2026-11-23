/// Enregistrement des PDF sur l'appareil et ouverture dans le lecteur par défaut.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'elements_pdf.dart';

/// Ouvre un fichier avec le programme par défaut du système ; retourne vrai si
/// la commande a été acceptée.
typedef Ouvreur = Future<bool> Function(String chemin);

/// Dossier où GESCO enregistre les documents : « Documents\GESCO ».
Future<Directory> dossierDocuments() async {
  final base = await getApplicationDocumentsDirectory();
  final dossier = Directory(p.join(base.path, 'GESCO'));
  await dossier.create(recursive: true);
  return dossier;
}

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i',
  'ô': 'o', 'ö': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ÿ': 'y', 'ç': 'c', 'œ': 'oe', 'æ': 'ae',
  'À': 'A', 'Â': 'A', 'Ä': 'A', 'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E', 'Î': 'I', 'Ï': 'I',
  'Ô': 'O', 'Ö': 'O', 'Ù': 'U', 'Û': 'U', 'Ü': 'U', 'Ç': 'C', 'Œ': 'OE', 'Æ': 'AE',
};

/// Nom de fichier sûr pour tous les systèmes : sans accent, sans espace ni
/// caractère interdit sous Windows. Jamais vide.
String nomDeFichierSur(String nom) {
  final sb = StringBuffer();
  for (final c in nom.split('')) {
    sb.write(_accents[c] ?? c);
  }
  var s = sb.toString().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  s = s.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^[._]+|[._]+$'), '');
  if (s.length > 80) s = s.substring(0, 80);
  return s.isEmpty ? 'document' : s;
}

/// Enregistre [octets] dans [dossier] (par défaut « Documents\GESCO ») sous un
/// nom qui ne remplace jamais un fichier existant :
/// `nom_AAAAMMJJ-HHMMSS.extension`, suivi de `_2`, `_3`... en cas de collision.
///
/// L'écriture passe par un fichier temporaire : un arrêt en cours d'écriture
/// ne laisse jamais un fichier tronqué. Après l'écriture, la taille du fichier
/// est relue : une erreur est levée si elle ne correspond pas.
Future<File> enregistrerFichier(
  List<int> octets,
  String nom,
  String extension, {
  Directory? dossier,
  DateTime? maintenant,
}) async {
  final cible = dossier ?? await dossierDocuments();
  await cible.create(recursive: true);
  final t = maintenant ?? DateTime.now();
  String deux(int n) => n.toString().padLeft(2, '0');
  final horodatage =
      '${t.year}${deux(t.month)}${deux(t.day)}-${deux(t.hour)}${deux(t.minute)}${deux(t.second)}';
  final base = '${nomDeFichierSur(nom)}_$horodatage';

  var fichier = File(p.join(cible.path, '$base.$extension'));
  for (var i = 2; fichier.existsSync(); i++) {
    fichier = File(p.join(cible.path, '${base}_$i.$extension'));
  }
  final temporaire = File('${fichier.path}.tmp');
  await temporaire.writeAsBytes(octets, flush: true);
  await temporaire.rename(fichier.path);
  if (await fichier.length() != octets.length) {
    throw FileSystemException('Le fichier enregistré est incomplet.', fichier.path);
  }
  return fichier;
}

/// Enregistre le PDF dans [dossier] (par défaut « Documents\GESCO ») sous un
/// nom qui ne remplace jamais un fichier existant (voir [enregistrerFichier]).
Future<File> enregistrerPdf(
  DocumentPdf pdf,
  String nom, {
  Directory? dossier,
  DateTime? maintenant,
}) =>
    enregistrerFichier(pdf.octets, nom, 'pdf', dossier: dossier, maintenant: maintenant);

/// Écrit [octets] dans [cible] en remplaçant le fichier existant, sans jamais
/// laisser un fichier tronqué : l'écriture passe par un fichier temporaire
/// renommé une fois complet. Crée le dossier au besoin.
Future<void> ecrireEnRemplacant(File cible, List<int> octets) async {
  await cible.parent.create(recursive: true);
  final temporaire = File('${cible.path}.tmp');
  await temporaire.writeAsBytes(octets, flush: true);
  try {
    await temporaire.rename(cible.path);
  } catch (_) {
    // Fichier verrouillé (ouvert dans un lecteur) : ne pas laisser de reste.
    if (temporaire.existsSync()) await temporaire.delete();
    rethrow;
  }
}

/// Ouvre le fichier avec le lecteur PDF par défaut (Windows, macOS, Linux).
/// Retourne faux si le système n'a pas pu l'ouvrir.
Future<bool> ouvrirFichier(String chemin) async {
  try {
    final ProcessResult r;
    if (Platform.isWindows) {
      // Le premier argument vide est le titre de fenêtre attendu par « start ».
      r = await Process.run('cmd', ['/c', 'start', '', chemin]);
    } else if (Platform.isMacOS) {
      r = await Process.run('open', [chemin]);
    } else {
      r = await Process.run('xdg-open', [chemin]);
    }
    return r.exitCode == 0;
  } on ProcessException {
    return false;
  }
}
