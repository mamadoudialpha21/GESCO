import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:gesco/ui/acces/porte_acces.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String contenuApp = 'CONTENU DE L\'APPLICATION';

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late EtatApp etat;

  Future<void> demarrer(WidgetTester tester, {bool avecAdmin = false}) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    gdb = (await tester.runAsync(() => GescoDatabase.ouvrir(
          fabrique: databaseFactoryFfi,
          chemin: inMemoryDatabasePath,
        )))!;
    etat = EtatApp(
      Services(gdb, session: Session(), iterations: 2),
      chemin: 'en mémoire',
    );
    await tester.runAsync(() async {
      if (avecAdmin) {
        await etat.services.utilisateurs.creerPremierAdministrateur(
          identifiant: 'admin',
          nomComplet: 'Directeur Test',
          motDePasse: 'Tombolia26',
        );
      }
      await etat.acces.charger();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: PorteAcces(etat: etat, construire: (_) => const Center(child: Text(contenuApp))),
      ),
    );
  }

  Future<void> fin(WidgetTester tester) async {
    // Démonte l'écran (arrête le minuteur d'inactivité) puis ferme la base.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => gdb.fermer());
  }

  /// Attend (en temps réel, pour laisser la base répondre) qu'un élément apparaisse.
  Future<void> attendre(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      if (f.evaluate().isNotEmpty) return;
    }
    fail('Élément introuvable : $f');
  }

  Future<void> saisir(WidgetTester tester, String cle, String texte) async {
    await tester.enterText(find.byKey(Key(cle)), texte);
    await tester.pump();
  }

  Future<void> toucher(WidgetTester tester, String cle) async {
    final f = find.byKey(Key(cle));
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await tester.pump();
  }

  Future<void> connecter(WidgetTester tester, String mdp) async {
    await saisir(tester, 'champ_identifiant', 'admin');
    await saisir(tester, 'champ_mot_de_passe', mdp);
    await toucher(tester, 'bouton_connexion');
  }

  testWidgets('premier démarrage : refuse les erreurs, crée l\'administrateur, affiche le code',
      (tester) async {
    await demarrer(tester);
    expect(find.text('Bienvenue dans GESCO'), findsOneWidget);
    expect(find.text(contenuApp), findsNothing);

    // Confirmation différente.
    await saisir(tester, 'premier_mot_de_passe', 'Tombolia26');
    await saisir(tester, 'premier_confirmation', 'Tombolia27');
    await toucher(tester, 'bouton_creer_admin');
    expect(find.textContaining('pas identiques'), findsOneWidget);

    // Mot de passe trop courant.
    await saisir(tester, 'premier_mot_de_passe', '123456');
    await saisir(tester, 'premier_confirmation', '123456');
    await toucher(tester, 'bouton_creer_admin');
    await attendre(tester, find.textContaining('trop courant'));
    expect(await tester.runAsync(() => etat.services.utilisateurs.compter()), 0);

    // Valide.
    await saisir(tester, 'premier_nom', 'Directeur Test');
    await saisir(tester, 'premier_mot_de_passe', 'Tombolia26');
    await saisir(tester, 'premier_confirmation', 'Tombolia26');
    await toucher(tester, 'bouton_creer_admin');
    await attendre(tester, find.byKey(const Key('code_recuperation')));
    final code = tester.widget<SelectableText>(find.byKey(const Key('code_recuperation'))).data!;
    expect(code, matches(RegExp(r'^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$')));
    expect(find.text(contenuApp), findsNothing);

    // « Commencer » reste bloqué tant que le code n'est pas noté.
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('bouton_commencer'))).onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('case_code_note')));
    await tester.pump();
    await toucher(tester, 'bouton_commencer');
    await attendre(tester, find.text(contenuApp));
    expect(etat.services.session.utilisateur!.identifiant, 'admin');
    expect(etat.services.session.peut(Permission.utilisateursGerer), isTrue);

    final contexte = await tester.runAsync(() => gdb.db.query('contexte'));
    expect(contexte!.first['utilisateur_nom'], 'Directeur Test');
    await fin(tester);
  });

  testWidgets('connexion : un mauvais mot de passe est refusé, le bon ouvre l\'application',
      (tester) async {
    await demarrer(tester, avecAdmin: true);
    expect(find.text('Connexion'), findsOneWidget);
    expect(find.text(contenuApp), findsNothing);

    await toucher(tester, 'bouton_connexion');
    expect(find.text('Saisissez votre identifiant.'), findsOneWidget);

    await connecter(tester, 'mauvais');
    await attendre(tester, find.text('Identifiant ou mot de passe incorrect.'));
    expect(find.text(contenuApp), findsNothing);

    await saisir(tester, 'champ_mot_de_passe', 'Tombolia26');
    await toucher(tester, 'bouton_connexion');
    await attendre(tester, find.text(contenuApp));
    expect(find.text('Connexion'), findsNothing);
    await fin(tester);
  });

  testWidgets('verrouillage : le contenu est masqué jusqu\'au bon mot de passe', (tester) async {
    await demarrer(tester, avecAdmin: true);
    await connecter(tester, 'Tombolia26');
    await attendre(tester, find.text(contenuApp));

    await tester.runAsync(() => etat.acces.verrouiller());
    await tester.pump();
    expect(find.text('Session verrouillée'), findsOneWidget);
    expect(find.text(contenuApp), findsNothing);
    expect(etat.services.session.peut(Permission.notesVoir), isFalse);

    await saisir(tester, 'champ_mot_de_passe', 'faux');
    await toucher(tester, 'bouton_connexion');
    await attendre(tester, find.text('Identifiant ou mot de passe incorrect.'));
    expect(find.text(contenuApp), findsNothing);

    await saisir(tester, 'champ_mot_de_passe', 'Tombolia26');
    await toucher(tester, 'bouton_connexion');
    await attendre(tester, find.text(contenuApp));
    expect(find.text('Session verrouillée'), findsNothing);
    expect(etat.services.session.peut(Permission.notesVoir), isTrue);
    await fin(tester);
  });

  testWidgets('inactivité : la session se verrouille toute seule', (tester) async {
    await demarrer(tester, avecAdmin: true);
    etat.services.session.delaiInactivite = const Duration(minutes: 5);
    await connecter(tester, 'Tombolia26');
    await attendre(tester, find.text(contenuApp));

    final verrouille = await tester.runAsync(
      () => etat.acces.verifierInactivite(DateTime.now().add(const Duration(minutes: 6))),
    );
    expect(verrouille, isTrue);
    await tester.pump();
    expect(find.text('Session verrouillée'), findsOneWidget);
    expect(find.text(contenuApp), findsNothing);

    final connexions = await tester.runAsync(
      () => gdb.db.query('journal_connexion', where: "evenement = 'verrouillage_inactivite'"),
    );
    expect(connexions, hasLength(1));
    await fin(tester);
  });

  testWidgets('« Changer d\'utilisateur » ramène à la connexion', (tester) async {
    await demarrer(tester, avecAdmin: true);
    await connecter(tester, 'Tombolia26');
    await attendre(tester, find.text(contenuApp));
    await tester.runAsync(() => etat.acces.verrouiller());
    await tester.pump();

    await toucher(tester, 'bouton_changer_utilisateur');
    await attendre(tester, find.text('Connexion'));
    expect(etat.services.session.utilisateur, isNull);
    expect(find.byKey(const Key('champ_identifiant')), findsOneWidget);
    await fin(tester);
  });

  testWidgets('compte créé par un administrateur : mot de passe à changer avant d\'entrer',
      (tester) async {
    await demarrer(tester, avecAdmin: true);
    await tester.runAsync(() async {
      await etat.services.utilisateurs.creer(
        identifiant: 'prof1',
        role: RoleUtilisateur.saisie,
        motDePasse: 'Provisoire1',
      );
    });
    await saisir(tester, 'champ_identifiant', 'prof1');
    await saisir(tester, 'champ_mot_de_passe', 'Provisoire1');
    await toucher(tester, 'bouton_connexion');
    await attendre(tester, find.text('Choisissez votre mot de passe'));
    expect(find.text(contenuApp), findsNothing);

    await saisir(tester, 'mdp_ancien', 'Provisoire1');
    await saisir(tester, 'mdp_nouveau', 'Provisoire1');
    await saisir(tester, 'mdp_confirmation', 'Provisoire1');
    await toucher(tester, 'bouton_changer_mdp');
    await attendre(tester, find.textContaining('différent de l\'ancien'));

    await saisir(tester, 'mdp_nouveau', 'MonSecret27');
    await saisir(tester, 'mdp_confirmation', 'MonSecret28');
    await toucher(tester, 'bouton_changer_mdp');
    expect(find.textContaining('pas identiques'), findsOneWidget);

    await saisir(tester, 'mdp_confirmation', 'MonSecret27');
    await toucher(tester, 'bouton_changer_mdp');
    await attendre(tester, find.text(contenuApp));
    expect(etat.services.session.peut(Permission.notesSaisir), isTrue);
    expect(etat.services.session.peut(Permission.utilisateursGerer), isFalse);
    await fin(tester);
  });

  testWidgets('mot de passe oublié : le code de récupération redonne l\'accès', (tester) async {
    await demarrer(tester);
    String? code;
    await tester.runAsync(() async {
      final r = await etat.acces.creerPremierAdministrateur(
        identifiant: 'admin',
        nomComplet: '',
        motDePasse: 'Tombolia26',
      );
      code = r.codeRecuperation;
      // Relit l'état : un compte existe, la porte d'accès passe à la connexion.
      await etat.acces.charger();
    });
    await tester.pump();
    expect(find.text('Connexion'), findsOneWidget);

    await toucher(tester, 'bouton_mot_de_passe_oublie');
    await tester.pumpAndSettle();
    expect(find.text('Récupérer l\'accès'), findsOneWidget);

    await saisir(tester, 'recup_identifiant', 'admin');
    await saisir(tester, 'recup_code', 'AAAA-AAAA-AAAA-AAAA');
    await saisir(tester, 'recup_nouveau', 'Retrouve2027');
    await saisir(tester, 'recup_confirmation', 'Retrouve2027');
    await toucher(tester, 'bouton_recuperer');
    await attendre(tester, find.text('Code de récupération incorrect.'));

    await saisir(tester, 'recup_code', code!);
    await toucher(tester, 'bouton_recuperer');
    await attendre(tester, find.byKey(const Key('nouveau_code_recuperation')));
    expect(
      tester.widget<SelectableText>(find.byKey(const Key('nouveau_code_recuperation'))).data,
      isNot(code),
    );
    await tester.tap(find.text('J\'ai noté le code'));
    await tester.pumpAndSettle();

    await connecter(tester, 'Retrouve2027');
    await attendre(tester, find.text(contenuApp));
    await fin(tester);
  });

  testWidgets('sans contrôle d\'accès, le contenu s\'ouvre directement', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final base = (await tester.runAsync(() => GescoDatabase.ouvrir(
          fabrique: databaseFactoryFfi,
          chemin: inMemoryDatabasePath,
        )))!;
    final libre = EtatApp(Services(base), chemin: 'en mémoire');
    await tester.pumpWidget(
      MaterialApp(
        home: PorteAcces(etat: libre, construire: (_) => const Text(contenuApp)),
      ),
    );
    expect(find.text(contenuApp), findsOneWidget);
    expect(find.text('Connexion'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => base.fermer());
  });
}
