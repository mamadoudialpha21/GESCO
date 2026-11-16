import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Emplacement du fichier de base de données sur l'appareil.
///
/// Sous Windows : `%APPDATA%\<organisation>\gesco\gesco.db`.
/// Ce dossier n'est pas supprimé lors d'une mise à jour de l'application.
Future<String> cheminBaseParDefaut() async {
  final dossier = await getApplicationSupportDirectory();
  await Directory(dossier.path).create(recursive: true);
  return p.join(dossier.path, 'gesco.db');
}
