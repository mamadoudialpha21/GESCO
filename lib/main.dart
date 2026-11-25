import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app/bulletins_auto.dart';
import 'app/etat_app.dart';
import 'app/gestion_base_app.dart';
import 'data/emplacements.dart';
import 'documents/ouvrir_document.dart';
import 'documents/polices_pdf.dart';
import 'ui/acces/porte_acces.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Windows, macOS, Linux : SQLite embarqué via FFI. Aucun accès réseau.
    sqfliteFfiInit();
    final chemin = await cheminBaseParDefaut();
    // La base, la session, les bulletins automatiques et la sauvegarde
    // automatique quotidienne sont rassemblés dans `GestionBaseApp` : après la
    // restauration d'une sauvegarde, tout est reconstruit sur la base restaurée.
    final gestion = await GestionBaseApp.demarrer(
      fabrique: databaseFactoryFfi,
      chemin: chemin,
      // Bulletins individuels régénérés à chaque saisie de notes (réglage
      // « Bulletins automatiques », activé par défaut).
      creerBulletinsAuto: (services) => BulletinsAuto(
        services: services,
        dossierRacine: dossierDocuments,
        chargerPolices: PolicesPdf.charger,
      )..demarrer(),
    );
    runApp(GescoHote(gestion: gestion));
  } catch (erreur) {
    runApp(EcranErreurDemarrage(message: erreur.toString()));
  }
}

/// Affiche l'application et la reconstruit entièrement quand l'état change
/// (après la restauration d'une sauvegarde).
class GescoHote extends StatelessWidget {
  const GescoHote({super.key, required this.gestion});

  final GestionBaseApp gestion;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EtatApp>(
      valueListenable: gestion.etat,
      builder: (context, etat, _) => GescoApp(key: ObjectKey(etat), etat: etat),
    );
  }
}

class GescoApp extends StatelessWidget {
  const GescoApp({super.key, required this.etat});

  final EtatApp etat;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GESCO',
      debugShowCheckedModeBanner: false,
      theme: construireTheme(),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: PorteAcces(etat: etat),
    );
  }
}

/// Affiché si la base de données ne peut pas être ouverte au démarrage.
class EcranErreurDemarrage extends StatelessWidget {
  const EcranErreurDemarrage({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GESCO',
      debugShowCheckedModeBanner: false,
      theme: construireTheme(),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.error, color: CouleursGesco.rouge, size: 32),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'GESCO ne peut pas ouvrir sa base de données',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SelectableText(message),
                    const SizedBox(height: 16),
                    const Text(
                      'Vos données n\'ont pas été modifiées. Vérifiez que GESCO '
                      'n\'est pas déjà ouvert dans une autre fenêtre, puis '
                      'relancez-le. Si le problème persiste, restaurez une '
                      'sauvegarde.',
                      style: TextStyle(color: CouleursGesco.gris),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
