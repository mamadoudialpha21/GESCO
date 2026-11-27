import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/gestion_base.dart';
import 'package:gesco/app/planificateur_sauvegarde.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_securite.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:gesco/sauvegarde/service_sauvegarde.dart';
import 'package:gesco/ui/securite/onglet_sauvegardes.dart';
import 'package:gesco/ui/securite/page_securite.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Restauration pilotée par le test : ferme et rouvre la vraie base sur
/// disque, et compte les redémarrages demandés par l'écran.
class GestionTest implements GestionBase {
  GestionTest(this.service, this.fermer, this.ouvrir);

  final ServiceSauvegarde service;
  final Future<void> Function() fermer;
  final Future<GescoDatabase> Function() ouvrir;
  int redemarrages = 0;

  @override
  Future<ResultatRestauration> restaurer(
    String chemin, {
    void Function(EtapeRestauration etape)? progression,
  }) =>
      service.restaurer(chemin, fermerBase: fermer, ouvrirBase: ouvrir, progression: progression);

  @override
  Future<void> redemarrer() async => redemarrages++;
}

Utilisateur agent(Set<Permission> droits) => Utilisateur(
      id: 1,
      identifiant: 'agent',
      nomComplet: 'Agent',
      role: RoleUtilisateur.consultation,
      actif: true,
      creeLe: '2026-01-01',
      permissionsPersonnalisees: droits,
    );

/// Un test qui reste bloqué échoue au bout de deux minutes (et non dix).
void testSauv(String nom, Future<void> Function(WidgetTester) corps) =>
    testWidgets(nom, corps, timeout: const Timeout(Duration(minutes: 2)));

/// Service dont la sauvegarde automatique échoue toujours (dossier inaccessible).
class ServiceEnEchec extends ServiceSauvegarde {
  ServiceEnEchec(super.services, {required super.fabrique, required super.cheminBase});

  @override
  Future<ResultatSauvegarde?> executerSiDue() async {
    throw const ErreurGesco(
      'Le dossier des sauvegardes de GESCO (« sauvegardes ») n\'est pas accessible (simulé).',
    );
  }
}

void main() {
  sqfliteFfiInit();

  late Directory tmp;
  late String cheminBase;
  late GescoDatabase gdb;
  late Services services;
  late ServiceSauvegarde service;
  late EtatApp etat;
  late GestionTest gestion;
  late int annee;
  late int classe;
  PlanificateurSauvegarde? planificateur;
  String? dossierChoisi;
  String? fichierChoisi;
  var quittes = 0;

  final instant = DateTime(2026, 11, 25, 19, 0, 0);

  Future<GescoDatabase> ouvrirBase() async {
    gdb = await GescoDatabase.ouvrir(fabrique: databaseFactoryFfi, chemin: cheminBase);
    return gdb;
  }

  Future<int> inscrire(String matricule, String nom, String prenom) {
    final admin = Services(gdb, session: Session.sansControle(), iterations: 2);
    return admin.eleves.inscrire(
      Eleve(matricule: matricule, nom: nom, prenom: prenom, sexe: 'M'),
      anneeId: annee,
      classeId: classe,
    );
  }

  Future<int> nbEleves() async {
    final admin = Services(gdb, session: Session.sansControle(), iterations: 2);
    return (await admin.eleves.lister(annee, classeId: classe)).length;
  }

  /// Base sur disque avec deux élèves, services et état de l'application.
  Future<void> preparer(
    WidgetTester tester, {
    Session? session,
    bool dossierBloque = false,
    bool avecPlanificateur = false,
  }) async {
    tester.view.physicalSize = const Size(1500, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    dossierChoisi = null;
    fichierChoisi = null;
    quittes = 0;
    planificateur = null;
    tmp = Directory.systemTemp.createTempSync('gesco_sauvegardes_ui_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    cheminBase = p.join(tmp.path, 'gesco.db');
    if (dossierBloque) File(p.join(tmp.path, 'sauvegardes')).writeAsStringSync('je bloque le dossier');

    await tester.runAsync(() async {
      await ouvrirBase();
      final admin = Services(gdb, session: Session.sansControle(), iterations: 2);
      await admin.etablissements.enregistrer(const Etablissement(nom: 'Groupe Scolaire Test'));
      annee = (await admin.annees.creer('2026-2027', activer: true)).id;
      classe = (await admin.classes.creer(anneeId: annee, nom: '10e A', niveauCode: 10)).id;
      await inscrire('2026-0001', 'BARRY', 'Mamadou');
      await inscrire('2026-0002', 'DIALLO', 'Aminata');
    });
    services = session == null
        ? Services(gdb, session: Session.sansControle(), iterations: 2)
        : Services(gdb, session: session, iterations: 2);
    service = ServiceSauvegarde(
      services,
      fabrique: databaseFactoryFfi,
      cheminBase: cheminBase,
      maintenant: () => instant,
    );
    if (avecPlanificateur) {
      planificateur = PlanificateurSauvegarde(
        service,
        delaiDemarrage: const Duration(hours: 1),
        intervalle: const Duration(hours: 1),
      );
    }
    gestion = GestionTest(service, () => gdb.fermer(), ouvrirBase);
    etat = EtatApp(
      services,
      chemin: cheminBase,
      sauvegarde: service,
      planificateurSauvegarde: planificateur,
      gestionBase: gestion,
    );
  }

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OngletSauvegardes(
            etat: etat,
            selecteurDossier: () async => dossierChoisi,
            selecteurFichier: () async => fichierChoisi,
            quitter: () => quittes++,
          ),
        ),
      ),
    );
  }

  Future<void> attendre(WidgetTester tester, Finder f, {int essais = 100}) async {
    for (var i = 0; i < essais; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      if (f.evaluate().isNotEmpty) return;
    }
    fail('Élément introuvable : $f');
  }

  Future<void> fin(WidgetTester tester) async {
    planificateur?.arreter();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => gdb.fermer());
  }

  Future<void> toucher(WidgetTester tester, String cle) async {
    await tester.ensureVisible(find.byKey(Key(cle)));
    await tester.tap(find.byKey(Key(cle)));
    await tester.pump();
  }

  Future<void> choisirDansListe(WidgetTester tester, String cle, String libelle) async {
    await tester.ensureVisible(find.byKey(Key(cle)));
    await tester.tap(find.byKey(Key(cle)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(libelle).last);
    await tester.pumpAndSettle();
  }

  bool actif(WidgetTester tester, String cle) =>
      tester.widget<FilledButton>(find.byKey(Key(cle))).onPressed != null;

  String texte(WidgetTester tester, String cle) => tester.widget<Text>(find.byKey(Key(cle))).data!;

  String texteSelectionnable(WidgetTester tester, String cle) =>
      tester.widget<SelectableText>(find.byKey(Key(cle))).data!;

  String corrompre(String chemin) {
    final b = File(chemin).readAsBytesSync();
    b[b.length ~/ 2] ^= 0xFF;
    final copie = p.join(tmp.path, 'abimee.zip');
    File(copie).writeAsBytesSync(b);
    return copie;
  }

  testSauv('réglages par défaut, aucune sauvegarde, rien à enregistrer', (tester) async {
    await preparer(tester);
    await afficher(tester);
    await attendre(tester, find.byKey(const Key('sauv_auto')));

    expect(tester.widget<SwitchListTile>(find.byKey(const Key('sauv_auto'))).value, isTrue);
    expect(find.text('18 h'), findsOneWidget);
    expect(find.text('00'), findsOneWidget);
    expect(find.text('7 dernières'), findsOneWidget);
    expect(texte(tester, 'sauv_externe_texte'), contains('aucune'));
    expect(texte(tester, 'sauv_derniere_auto'), 'Aucune sauvegarde automatique pour le moment.');
    expect(actif(tester, 'sauv_config_enregistrer'), isFalse);
    expect(find.byKey(const Key('sauv_erreur_auto')), findsNothing);
    await fin(tester);
  });

  testSauv('sauvegarde manuelle : créée, contrôlée, affichée dans l\'historique', (tester) async {
    await preparer(tester);
    await afficher(tester);
    await attendre(tester, find.byKey(const Key('sauv_auto')));

    await toucher(tester, 'sauv_creer');
    await attendre(tester, find.byKey(const Key('sauv_resultat')));
    const nom = 'GESCO_sauvegarde_2026-11-25_190000_manuelle.zip';
    expect(texteSelectionnable(tester, 'sauv_resultat_texte'), contains(nom));
    expect(File(p.join(tmp.path, 'sauvegardes', nom)).existsSync(), isTrue);

    await attendre(tester, find.byKey(const Key('sauv_ligne_0')));
    expect(find.text('Manuelle · 25/11/2026 19:00'), findsOneWidget);
    expect(find.byKey(const Key('sauv_historique_vide')), findsNothing);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    await fin(tester);
  });

  testSauv('sauvegarde sur une clé USB : le fichier est écrit dans le dossier choisi', (tester) async {
    await preparer(tester);
    final usb = p.join(tmp.path, 'usb');
    dossierChoisi = usb;
    await afficher(tester);
    await attendre(tester, find.byKey(const Key('sauv_auto')));

    await toucher(tester, 'sauv_creer_externe');
    await attendre(tester, find.byKey(const Key('sauv_resultat')));
    final fichiers = Directory(usb).listSync().whereType<File>().toList();
    expect(fichiers, hasLength(1));
    expect(texteSelectionnable(tester, 'sauv_resultat_texte'), contains(usb));
    final v = await tester.runAsync(() => service.verifierFichier(fichiers.single.path));
    expect(v!.valide, isTrue);

    // Aucun dossier choisi (boîte fermée) : rien n'est créé.
    dossierChoisi = null;
    await toucher(tester, 'sauv_creer_externe');
    await tester.pump(const Duration(milliseconds: 200));
    expect(Directory(usb).listSync().whereType<File>(), hasLength(1));
    await fin(tester);
  });

  testSauv('réglages : modifiés, enregistrés, relus ; auto désactivée grise l\'heure', (tester) async {
    await preparer(tester);
    await afficher(tester);
    await attendre(tester, find.byKey(const Key('sauv_auto')));

    await choisirDansListe(tester, 'sauv_heure', '07 h');
    await choisirDansListe(tester, 'sauv_conserver', '10 dernières');
    dossierChoisi = 'D:\\Cle';
    await toucher(tester, 'sauv_externe_choisir');
    await tester.pump();
    expect(texte(tester, 'sauv_externe_texte'), contains('D:\\Cle'));
    expect(actif(tester, 'sauv_config_enregistrer'), isTrue);

    await toucher(tester, 'sauv_config_enregistrer');
    await tester.pump();
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
      if (!actif(tester, 'sauv_config_enregistrer')) break;
    }
    expect(actif(tester, 'sauv_config_enregistrer'), isFalse);
    final c = (await tester.runAsync(() => service.config()))!;
    expect(c.heureTexte, '07:00');
    expect(c.conserver, 10);
    expect(c.dossierExterne, 'D:\\Cle');
    expect(c.auto, isTrue);

    await toucher(tester, 'sauv_externe_retirer');
    expect(texte(tester, 'sauv_externe_texte'), contains('aucune'));
    await toucher(tester, 'sauv_auto');
    expect(
      tester.widget<DropdownButton<int>>(find.byKey(const Key('sauv_heure'))).onChanged,
      isNull,
    );
    await toucher(tester, 'sauv_config_enregistrer');
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
      if (!actif(tester, 'sauv_config_enregistrer')) break;
    }
    final c2 = (await tester.runAsync(() => service.config()))!;
    expect(c2.auto, isFalse);
    expect(c2.dossierExterne, '');
    await fin(tester);
  });

  testSauv('contrôle d\'une sauvegarde : valide, puis abîmée', (tester) async {
    await preparer(tester);
    late Sauvegarde s;
    await tester.runAsync(() async => s = (await service.creerManuelle()).sauvegarde);
    await afficher(tester);
    await attendre(tester, find.byKey(const Key('sauv_ligne_0')));

    await toucher(tester, 'sauv_verifier_0');
    await attendre(tester, find.byKey(const Key('sauv_verif_dialogue')));
    expect(find.text('Sauvegarde valide'), findsOneWidget);
    expect(find.byKey(const Key('sauv_verif_ok')), findsOneWidget);
    expect(find.textContaining('2 élève(s)'), findsOneWidget);
    await toucher(tester, 'sauv_verif_fermer');
    await tester.pumpAndSettle();

    // Le fichier est abîmé : le contrôle le dit et l'historique le signale.
    final b = File(s.chemin).readAsBytesSync();
    b[b.length ~/ 2] ^= 0xFF;
    File(s.chemin).writeAsBytesSync(b);
    await toucher(tester, 'sauv_verifier_0');
    await attendre(tester, find.byKey(const Key('sauv_verif_probleme_0')));
    expect(find.text('Sauvegarde non valide'), findsOneWidget);
    await toucher(tester, 'sauv_verif_fermer');
    await tester.pumpAndSettle();
    await attendre(tester, find.byIcon(Icons.error_outline));
    expect(find.textContaining('contrôle en échec'), findsOneWidget);
    await fin(tester);
  });

  testSauv('suppression : confirmation puis fichier et ligne supprimés', (tester) async {
    await preparer(tester);
    late Sauvegarde s;
    await tester.runAsync(() async => s = (await service.creerManuelle()).sauvegarde);
    await afficher(tester);
    await attendre(tester, find.byKey(const Key('sauv_ligne_0')));

    await toucher(tester, 'sauv_supprimer_0');
    await tester.pumpAndSettle();
    expect(find.text('Supprimer cette sauvegarde ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(File(s.chemin).existsSync(), isTrue);

    await toucher(tester, 'sauv_supprimer_0');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pump();
    await attendre(tester, find.byKey(const Key('sauv_historique_vide')));
    expect(File(s.chemin).existsSync(), isFalse);
    await fin(tester);
  });

  testSauv('fichier de l\'historique introuvable (clé retirée) : signalé, sans restauration possible',
      (tester) async {
    await preparer(tester);
    final usb = Directory(p.join(tmp.path, 'usb'));
    late Sauvegarde s;
    await tester.runAsync(() async => s = (await service.creerManuelle(destination: usb)).sauvegarde);
    File(s.chemin).deleteSync();
    await afficher(tester);
    await attendre(tester, find.byKey(const Key('sauv_ligne_0')));
    expect(find.textContaining('fichier introuvable'), findsOneWidget);
    expect(find.byKey(const Key('sauv_restaurer_0')), findsNothing);
    expect(find.byKey(const Key('sauv_verifier_0')), findsNothing);
    await fin(tester);
  });

  testSauv('restauration : aperçu, confirmation obligatoire, remplacement, redémarrage', (tester) async {
    await preparer(tester);
    await tester.runAsync(() async {
      await service.creerManuelle(); // 2 élèves
      await inscrire('2026-0003', 'CAMARA', 'Fatou');
    });
    await afficher(tester);
    await attendre(tester, find.byKey(const Key('sauv_ligne_0')));

    await toucher(tester, 'sauv_restaurer_0');
    await attendre(tester, find.byKey(const Key('sauv_apercu')));
    // Les neuf étapes sont affichées ; la confirmation est la quatrième.
    for (var n = 1; n <= 9; n++) {
      expect(find.byKey(Key('sauv_etape_$n')), findsOneWidget);
    }
    expect(texte(tester, 'sauv_cmp_eleves_sauvegarde'), '2');
    expect(texte(tester, 'sauv_cmp_eleves_actuelle'), '3');
    expect(texte(tester, 'sauv_cmp_comptes_sauvegarde'), '0');
    expect(find.text('Groupe Scolaire Test'), findsNWidgets(2));
    expect(actif(tester, 'sauv_restaurer_lancer'), isFalse);

    await toucher(tester, 'sauv_confirmer_case');
    expect(actif(tester, 'sauv_restaurer_lancer'), isTrue);
    await toucher(tester, 'sauv_restaurer_lancer');
    await attendre(tester, find.byKey(const Key('sauv_fin')), essais: 200);
    expect(texteSelectionnable(tester, 'sauv_fin_message'), contains('a été restaurée'));
    expect(find.byKey(const Key('sauv_fin_securite')), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(9));
    expect(find.byIcon(Icons.cancel), findsNothing);
    expect(gestion.redemarrages, 0);

    await toucher(tester, 'sauv_restaurer_termine');
    await tester.pumpAndSettle();
    expect(gestion.redemarrages, 1);
    expect(find.byKey(const Key('sauv_restauration')), findsNothing);
    expect(await tester.runAsync(nbEleves), 2);

    // La sauvegarde de sécurité des données d'avant existe et est valide.
    final dossier = Directory(p.join(tmp.path, 'sauvegardes'));
    final securite = dossier
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).endsWith('_securite.zip'))
        .toList();
    expect(securite, hasLength(1));
    final v = await tester.runAsync(() => service.verifierFichier(securite.single.path));
    expect(v!.valide, isTrue);
    expect(v.manifeste!.contenu['eleves'], 3);
    await fin(tester);
  });

  testSauv('restauration : annuler ne change rien', (tester) async {
    await preparer(tester);
    await tester.runAsync(() async {
      await service.creerManuelle();
      await inscrire('2026-0003', 'CAMARA', 'Fatou');
    });
    await afficher(tester);
    await attendre(tester, find.byKey(const Key('sauv_ligne_0')));
    await toucher(tester, 'sauv_restaurer_0');
    await attendre(tester, find.byKey(const Key('sauv_apercu')));
    await toucher(tester, 'sauv_restaurer_annuler');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sauv_restauration')), findsNothing);
    expect(await tester.runAsync(nbEleves), 3);
    expect(gestion.redemarrages, 0);
    await fin(tester);
  });

  testSauv('restauration d\'un fichier abîmé : refusée, données intactes, aucun bouton Restaurer',
      (tester) async {
    await preparer(tester);
    late Sauvegarde s;
    await tester.runAsync(() async => s = (await service.creerManuelle()).sauvegarde);
    await tester.runAsync(() async => inscrire('2026-0003', 'CAMARA', 'Fatou'));
    fichierChoisi = corrompre(s.chemin);
    await afficher(tester);
    await attendre(tester, find.byKey(const Key('sauv_restaurer_fichier')));

    await toucher(tester, 'sauv_restaurer_fichier');
    await attendre(tester, find.byKey(const Key('sauv_refus')));
    expect(find.textContaining('n\'ont pas été modifiées'), findsOneWidget);
    expect(find.byKey(const Key('sauv_refus_probleme_0')), findsOneWidget);
    expect(find.byKey(const Key('sauv_restaurer_lancer')), findsNothing);
    expect(find.byIcon(Icons.cancel), findsOneWidget);
    await toucher(tester, 'sauv_restaurer_fermer');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sauv_restauration')), findsNothing);
    expect(await tester.runAsync(nbEleves), 3);
    expect(gestion.redemarrages, 0);

    // Fichier choisi puis boîte fermée : rien ne s'ouvre.
    fichierChoisi = null;
    await toucher(tester, 'sauv_restaurer_fichier');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('sauv_restauration')), findsNothing);
    await fin(tester);
  });

  testSauv('restauration d\'un fichier qui n\'est pas une sauvegarde : refusée avec explication',
      (tester) async {
    await preparer(tester);
    final texteSeul = File(p.join(tmp.path, 'liste.zip'))
      ..writeAsStringSync('ceci est un simple texte et pas une sauvegarde GESCO du tout');
    fichierChoisi = texteSeul.path;
    await afficher(tester);
    await attendre(tester, find.byKey(const Key('sauv_restaurer_fichier')));
    await toucher(tester, 'sauv_restaurer_fichier');
    await attendre(tester, find.byKey(const Key('sauv_refus')));
    expect(texteSelectionnable(tester, 'sauv_refus_probleme_0'), contains('pas une sauvegarde GESCO'));
    expect(await tester.runAsync(nbEleves), 2);
    await toucher(tester, 'sauv_restaurer_fermer');
    await tester.pumpAndSettle();
    await fin(tester);
  });

  testSauv('sans le droit de restaurer : sauvegarder oui, restaurer non', (tester) async {
    final session = Session()..ouvrir(agent({Permission.sauvegardeGerer}));
    await preparer(tester, session: session);
    await tester.runAsync(() => service.creerManuelle());
    await afficher(tester);
    await attendre(tester, find.byKey(const Key('sauv_ligne_0')));

    expect(find.byKey(const Key('sauv_creer')), findsOneWidget);
    expect(find.byKey(const Key('sauv_verifier_0')), findsOneWidget);
    expect(find.byKey(const Key('sauv_restaurer_0')), findsNothing);
    expect(find.byKey(const Key('sauv_restaurer_fichier')), findsNothing);
    expect(find.byKey(const Key('sauv_restaurer_refuse')), findsOneWidget);
    await fin(tester);
  });

  testSauv('échec de la sauvegarde automatique : l\'erreur est affichée, jamais silencieuse',
      (tester) async {
    // Le comportement du planificateur lui-même (erreur conservée, pause avant
    // une nouvelle tentative, réussite qui efface l'erreur) est vérifié par
    // test/app/planificateur_sauvegarde_test.dart sur une vraie base. Ici on
    // vérifie l'affichage : le service simule l'échec, sans minuterie réelle.
    await preparer(tester);
    final enEchec = ServiceEnEchec(
      services,
      fabrique: databaseFactoryFfi,
      cheminBase: cheminBase,
    );
    planificateur = PlanificateurSauvegarde(
      enEchec,
      delaiDemarrage: const Duration(hours: 1),
      intervalle: const Duration(hours: 1),
    );
    etat = EtatApp(
      services,
      chemin: cheminBase,
      sauvegarde: service,
      planificateurSauvegarde: planificateur,
      gestionBase: gestion,
    );
    planificateur!.demarrer();
    final tentative = planificateur!.verifier();
    await tester.pump();
    await tentative;
    expect(planificateur!.derniereErreur, contains('n\'est pas accessible'));

    await afficher(tester);
    await attendre(tester, find.byKey(const Key('sauv_erreur_auto')));
    expect(
      texteSelectionnable(tester, 'sauv_erreur_auto'),
      startsWith('La dernière sauvegarde automatique a échoué'),
    );
    await fin(tester);
  });

  testSauv('la page Sécurité n\'a l\'onglet Sauvegardes qu\'avec le droit', (tester) async {
    final session = Session()..ouvrir(agent({Permission.sauvegardeGerer}));
    await preparer(tester, session: session);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PageSecurite(etat: etat))));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Tab, 'Sauvegardes'), findsOneWidget);
    await attendre(tester, find.byKey(const Key('sauv_creer')));
    await fin(tester);

    final autre = Session()..ouvrir(agent({Permission.notesSaisir}));
    await preparer(tester, session: autre);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PageSecurite(etat: etat))));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Tab, 'Sauvegardes'), findsNothing);
    expect(find.widgetWithText(Tab, 'Mon compte'), findsOneWidget);
    await fin(tester);
  });

  testSauv('quitter GESCO est proposé si la base ne peut pas être rouverte', (tester) async {
    await preparer(tester);
    await tester.runAsync(() => service.creerManuelle());
    // La réouverture échoue deux fois (restauration, puis retour arrière).
    gestion = GestionTest(service, () => gdb.fermer(), () async => throw StateError('disque indisponible'));
    etat = EtatApp(
      services,
      chemin: cheminBase,
      sauvegarde: service,
      gestionBase: gestion,
    );
    await afficher(tester);
    await attendre(tester, find.byKey(const Key('sauv_ligne_0')));
    await toucher(tester, 'sauv_restaurer_0');
    await attendre(tester, find.byKey(const Key('sauv_apercu')));
    await toucher(tester, 'sauv_confirmer_case');
    await toucher(tester, 'sauv_restaurer_lancer');
    await attendre(tester, find.byKey(const Key('sauv_fin')), essais: 200);

    expect(texteSelectionnable(tester, 'sauv_fin_message'), contains('disque indisponible'));
    expect(find.byIcon(Icons.cancel), findsOneWidget);
    expect(find.byKey(const Key('sauv_restaurer_termine')), findsNothing);
    await toucher(tester, 'sauv_restaurer_quitter');
    expect(quittes, 1);
    expect(gestion.redemarrages, 0);

    // La base a déjà été fermée par la restauration.
    await tester.pumpWidget(const SizedBox());
  });
}
