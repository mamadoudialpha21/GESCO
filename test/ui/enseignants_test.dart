import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/ui/inscriptions/dialogues_mouvements.dart';
import 'package:gesco/ui/parametres/onglet_enseignants.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ce que la fenêtre a renvoyé en se fermant.
class Retour<T> {
  T? valeur;
  bool ferme = false;
}

/// Affiche [dialogue] au-dessus d'une page vide, sur un grand écran de test.
Future<Retour<T>> ouvrir<T>(WidgetTester tester, Widget dialogue) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final retour = Retour<T>();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                retour.valeur = await showDialog<T>(
                  context: context,
                  builder: (_) => dialogue,
                );
                retour.ferme = true;
              },
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
  return retour;
}

void main() {
  sqfliteFfiInit();

  group('DialogueSortie', () {
    testWidgets('renvoie le type, la date et le motif saisis', (tester) async {
      final retour = await ouvrir<ChoixSortie>(
        tester,
        const DialogueSortie(nomEleve: 'Aminata Diallo'),
      );
      await tester.tap(find.text('Abandon des études'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('champ_date_sortie')), '15/10/2026');
      await tester.enterText(find.byKey(const Key('champ_motif_sortie')), '  Déménagement ');
      await tester.tap(find.byKey(const Key('bouton_valider_sortie')));
      await tester.pumpAndSettle();

      expect(retour.ferme, isTrue);
      final choix = retour.valeur!;
      expect(choix.statut, StatutInscription.abandon);
      expect(choix.motif, 'Déménagement');
      expect((choix.date.year, choix.date.month, choix.date.day), (2026, 10, 15));
    });

    testWidgets('par défaut : départ, motif vide', (tester) async {
      final retour = await ouvrir<ChoixSortie>(
        tester,
        const DialogueSortie(nomEleve: 'Aminata Diallo'),
      );
      await tester.tap(find.byKey(const Key('bouton_valider_sortie')));
      await tester.pumpAndSettle();

      expect(retour.valeur!.statut, StatutInscription.depart);
      expect(retour.valeur!.motif, '');
    });

    testWidgets('une date invalide est refusée et la fenêtre reste ouverte', (tester) async {
      final retour = await ouvrir<ChoixSortie>(
        tester,
        const DialogueSortie(nomEleve: 'Aminata Diallo'),
      );
      await tester.enterText(find.byKey(const Key('champ_date_sortie')), '31/02/2026');
      await tester.tap(find.byKey(const Key('bouton_valider_sortie')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Date invalide'), findsOneWidget);
      expect(retour.ferme, isFalse);
    });

    testWidgets('Annuler ne renvoie rien', (tester) async {
      final retour = await ouvrir<ChoixSortie>(
        tester,
        const DialogueSortie(nomEleve: 'Aminata Diallo'),
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(retour.ferme, isTrue);
      expect(retour.valeur, isNull);
    });
  });

  group('DialogueTransfert', () {
    const classeA = ClasseResume(
      classe: Classe(id: 10, anneeId: 1, niveau: '', nom: '10e A'),
      nbMatieres: 3,
      nbEleves: 20,
    );
    const classeB = ClasseResume(
      classe: Classe(id: 11, anneeId: 1, niveau: '', nom: '10e B', capacite: 30),
      nbMatieres: 3,
      nbEleves: 25,
    );
    const classeC = ClasseResume(
      classe: Classe(id: 12, anneeId: 1, niveau: '', nom: '10e C'),
      nbMatieres: 3,
      nbEleves: 10,
    );

    testWidgets('propose les autres classes et renvoie la première par défaut', (tester) async {
      final retour = await ouvrir<ChoixTransfert>(
        tester,
        const DialogueTransfert(
          nomEleve: 'Aminata Diallo',
          classeActuelleId: 10,
          classes: [classeA, classeB, classeC],
          nbNotes: 0,
        ),
      );
      expect(find.textContaining('n\'a pas encore de notes'), findsOneWidget);
      // La classe actuelle n'est pas proposée ; la capacité s'affiche.
      expect(find.text('10e B (25 / 30)'), findsOneWidget);
      expect(find.text('10e A (20)'), findsNothing);

      await tester.tap(find.byKey(const Key('bouton_valider_transfert')));
      await tester.pumpAndSettle();
      expect(retour.valeur!.classeId, 11);
      expect(retour.valeur!.motif, '');
    });

    testWidgets('choisir une autre classe et un motif', (tester) async {
      final retour = await ouvrir<ChoixTransfert>(
        tester,
        const DialogueTransfert(
          nomEleve: 'Aminata Diallo',
          classeActuelleId: 10,
          classes: [classeA, classeB, classeC],
          nbNotes: 4,
        ),
      );
      expect(find.textContaining('a 4 notes'), findsOneWidget);

      await tester.tap(find.byKey(const Key('choix_classe_transfert')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10e C (10)').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  Redoublement ');
      await tester.tap(find.byKey(const Key('bouton_valider_transfert')));
      await tester.pumpAndSettle();

      expect(retour.valeur!.classeId, 12);
      expect(retour.valeur!.motif, 'Redoublement');
    });

    testWidgets('sans autre classe, le transfert est impossible', (tester) async {
      await ouvrir<ChoixTransfert>(
        tester,
        const DialogueTransfert(
          nomEleve: 'Aminata Diallo',
          classeActuelleId: 10,
          classes: [classeA],
          nbNotes: 0,
        ),
      );
      expect(find.textContaining('pas d\'autre classe'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('bouton_valider_transfert')))
            .onPressed,
        isNull,
      );
    });
  });

  group('OngletEnseignants', () {
    late GescoDatabase gdb;
    late EtatApp etat;

    Future<void> demarrer(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      gdb = (await tester.runAsync(() => GescoDatabase.ouvrir(
            fabrique: databaseFactoryFfi,
            chemin: inMemoryDatabasePath,
          )))!;
      etat = EtatApp(
        Services(gdb, session: Session.sansControle(), iterations: 2),
        chemin: 'en mémoire',
      );
      await tester.runAsync(() async {
        await etat.services.annees.creer('2026-2027', activer: true);
        await etat.charger();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: etat,
              builder: (context, _) => OngletEnseignants(etat: etat),
            ),
          ),
        ),
      );
    }

    Future<void> fin(WidgetTester tester) async {
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

    Future<void> ajouter(WidgetTester tester, String nom, String prenom, {String specialite = ''}) async {
      await tester.tap(find.byKey(const Key('bouton_nouvel_enseignant')));
      await tester.pumpAndSettle();
      await saisir(tester, 'enseignant_nom', nom);
      await saisir(tester, 'enseignant_prenom', prenom);
      if (specialite.isNotEmpty) await saisir(tester, 'enseignant_specialite', specialite);
      await tester.tap(find.byKey(const Key('bouton_valider_enseignant')));
      await tester.pump();
    }

    testWidgets('liste vide, puis création d\'un enseignant', (tester) async {
      await demarrer(tester);
      await attendre(tester, find.text('Aucun enseignant enregistré.'));

      await ajouter(tester, 'Diallo', 'Aminata', specialite: 'Mathématiques');
      await attendre(tester, find.text('DIALLO Aminata'));

      expect(find.textContaining('Mathématiques'), findsOneWidget);
      final lignes = await tester.runAsync(() => gdb.db.query('enseignant'));
      expect(lignes, hasLength(1));
      expect(lignes!.first['nom'], 'Diallo');
      expect(lignes.first['specialite'], 'Mathématiques');
      await fin(tester);
    });

    testWidgets('le nom et le prénom sont obligatoires', (tester) async {
      await demarrer(tester);
      await attendre(tester, find.text('Aucun enseignant enregistré.'));

      await tester.tap(find.byKey(const Key('bouton_nouvel_enseignant')));
      await tester.pumpAndSettle();
      await saisir(tester, 'enseignant_nom', 'Diallo');
      await tester.tap(find.byKey(const Key('bouton_valider_enseignant')));
      await tester.pump();

      expect(find.text('Le nom et le prénom sont obligatoires.'), findsOneWidget);
      expect(await tester.runAsync(() => gdb.db.query('enseignant')), isEmpty);
      await fin(tester);
    });

    testWidgets('une erreur de la base (matricule en double) est affichée', (tester) async {
      await demarrer(tester);
      await tester.runAsync(() => etat.services.enseignants.creer(
            const Enseignant(nom: 'Barry', prenom: 'Oumar', matricule: 'E-01'),
          ));
      etat.donneesModifiees();
      await attendre(tester, find.text('BARRY Oumar'));

      await tester.tap(find.byKey(const Key('bouton_nouvel_enseignant')));
      await tester.pumpAndSettle();
      await saisir(tester, 'enseignant_nom', 'Camara');
      await saisir(tester, 'enseignant_prenom', 'Fatou');
      await saisir(tester, 'enseignant_matricule', 'E-01');
      await tester.tap(find.byKey(const Key('bouton_valider_enseignant')));
      await tester.pump();
      await attendre(tester, find.textContaining('matricule'));

      expect(await tester.runAsync(() => gdb.db.query('enseignant')), hasLength(1));
      await fin(tester);
    });

    testWidgets('désactiver puis réactiver un enseignant', (tester) async {
      await demarrer(tester);
      await tester.runAsync(() => etat.services.enseignants.creer(
            const Enseignant(nom: 'Barry', prenom: 'Oumar'),
          ));
      etat.donneesModifiees();
      await attendre(tester, find.text('BARRY Oumar'));

      await tester.tap(find.byTooltip('Désactiver'));
      await tester.pump();
      await attendre(tester, find.text('Inactif'));
      var lignes = await tester.runAsync(() => gdb.db.query('enseignant'));
      expect(lignes!.first['actif'], 0);

      await tester.tap(find.byTooltip('Réactiver'));
      await tester.pump();
      await attendre(tester, find.byTooltip('Désactiver'));
      expect(find.text('Inactif'), findsNothing);
      lignes = await tester.runAsync(() => gdb.db.query('enseignant'));
      expect(lignes!.first['actif'], 1);
      await fin(tester);
    });

    testWidgets('la recherche et le filtre des inactifs', (tester) async {
      await demarrer(tester);
      await tester.runAsync(() async {
        await etat.services.enseignants.creer(const Enseignant(nom: 'Barry', prenom: 'Oumar'));
        await etat.services.enseignants.creer(
          const Enseignant(nom: 'Camara', prenom: 'Fatou', actif: false),
        );
      });
      etat.donneesModifiees();
      await attendre(tester, find.text('CAMARA Fatou'));
      expect(find.text('BARRY Oumar'), findsOneWidget);

      // Recherche sans tenir compte des accents ni des majuscules.
      await saisir(tester, 'recherche_enseignant', 'cámara');
      expect(find.text('CAMARA Fatou'), findsOneWidget);
      expect(find.text('BARRY Oumar'), findsNothing);

      await saisir(tester, 'recherche_enseignant', 'inconnu');
      expect(find.text('Aucun enseignant ne correspond.'), findsOneWidget);

      await saisir(tester, 'recherche_enseignant', '');
      await tester.tap(find.text('Afficher les inactifs'));
      await tester.pump();
      expect(find.text('CAMARA Fatou'), findsNothing);
      expect(find.text('BARRY Oumar'), findsOneWidget);
      await fin(tester);
    });

    testWidgets('confier une classe, puis suppression refusée', (tester) async {
      await demarrer(tester);
      late int enseignantId;
      late int classeId;
      await tester.runAsync(() async {
        final annee = etat.anneeId!;
        enseignantId = await etat.services.enseignants.creer(
          const Enseignant(nom: 'Barry', prenom: 'Oumar'),
        );
        classeId = (await etat.services.classes.creer(anneeId: annee, nom: '10e A')).id;
      });
      etat.donneesModifiees();
      await attendre(tester, find.text('BARRY Oumar'));

      await tester.tap(find.byTooltip('Matières et classes'));
      await tester.pump();
      await attendre(tester, find.byKey(Key('classe_confiee_$classeId')));
      await tester.tap(find.byKey(Key('classe_confiee_$classeId')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('bouton_valider_classes_confiees')));
      await tester.pump();
      await attendre(tester, find.textContaining('1 classe'));

      final confiees = await tester.runAsync(
        () => etat.services.enseignants.classesConfiees(enseignantId, etat.anneeId!),
      );
      expect(confiees, {classeId});

      // Il a maintenant une classe : la suppression est refusée.
      await tester.tap(find.byTooltip('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer').last);
      await tester.pump();
      await attendre(tester, find.textContaining('Impossible de supprimer'));
      expect(await tester.runAsync(() => gdb.db.query('enseignant')), hasLength(1));
      await fin(tester);
    });

    testWidgets('supprimer un enseignant sans affectation', (tester) async {
      await demarrer(tester);
      await tester.runAsync(() => etat.services.enseignants.creer(
            const Enseignant(nom: 'Barry', prenom: 'Oumar'),
          ));
      etat.donneesModifiees();
      await attendre(tester, find.text('BARRY Oumar'));

      await tester.tap(find.byTooltip('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer').last);
      await tester.pump();
      await attendre(tester, find.text('Aucun enseignant enregistré.'));
      expect(await tester.runAsync(() => gdb.db.query('enseignant')), isEmpty);
      await fin(tester);
    });
  });
}
