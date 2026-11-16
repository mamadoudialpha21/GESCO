import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/main.dart';
import 'package:gesco/ui/commun/chargeur.dart';
import 'package:gesco/ui/commun/composants.dart';
import 'package:gesco/ui/commun/dialogues.dart';
import 'package:gesco/ui/theme.dart';

// Ce fichier existe aussi pour empêcher « flutter create » d'ajouter son test
// modèle (qui ne correspond pas à cette application).
void main() {
  testWidgets('écran d\'erreur de démarrage', (tester) async {
    await tester.pumpWidget(
      const EcranErreurDemarrage(message: 'Fichier verrouillé'),
    );
    expect(
      find.text('GESCO ne peut pas ouvrir sa base de données'),
      findsOneWidget,
    );
    expect(find.text('Fichier verrouillé'), findsOneWidget);
  });

  group('Chargeur', () {
    testWidgets('affiche les données chargées', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Chargeur<int>(
            cle: 1,
            charger: () async => 42,
            builder: (context, valeur) => Text('valeur $valeur'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('valeur 42'), findsOneWidget);
    });

    testWidgets('recharge quand la clé change', (tester) async {
      Widget construire(int cle, int valeur) => MaterialApp(
            home: Chargeur<int>(
              cle: cle,
              charger: () async => valeur,
              builder: (context, v) => Text('valeur $v'),
            ),
          );

      await tester.pumpWidget(construire(1, 42));
      await tester.pumpAndSettle();
      expect(find.text('valeur 42'), findsOneWidget);

      await tester.pumpWidget(construire(2, 43));
      await tester.pumpAndSettle();
      expect(find.text('valeur 43'), findsOneWidget);
      expect(find.text('valeur 42'), findsNothing);
    });

    testWidgets('ne recharge pas quand la clé est identique', (tester) async {
      var appels = 0;
      Widget construire() => MaterialApp(
            home: Chargeur<int>(
              cle: 'identique',
              charger: () async => ++appels,
              builder: (context, v) => Text('appel $v'),
            ),
          );

      await tester.pumpWidget(construire());
      await tester.pumpAndSettle();
      await tester.pumpWidget(construire());
      await tester.pumpAndSettle();
      expect(appels, 1);
      expect(find.text('appel 1'), findsOneWidget);
    });

    testWidgets('signale une erreur de chargement', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Chargeur<int>(
            cle: 1,
            charger: () async => throw StateError('panne'),
            builder: (context, valeur) => Text('valeur $valeur'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Erreur de chargement'), findsOneWidget);
    });
  });

  group('executer (notifications)', () {
    Widget page(Future<bool>? Function(BuildContext) action) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => action(context),
                child: const Text('go'),
              ),
            ),
          ),
        );

    testWidgets('succès : message de confirmation', (tester) async {
      await tester.pumpWidget(
        page((context) => executer(context, () async {}, succes: 'Bien enregistré')),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Bien enregistré'), findsOneWidget);
    });

    testWidgets('erreur métier : son message est affiché tel quel', (tester) async {
      await tester.pumpWidget(
        page(
          (context) => executer(
            context,
            () async => throw const ErreurGesco('Classe en double'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Classe en double'), findsOneWidget);
    });

    testWidgets('erreur inattendue : signalée comme telle', (tester) async {
      await tester.pumpWidget(
        page((context) => executer(context, () async => throw StateError('x'))),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Erreur inattendue'), findsOneWidget);
    });
  });

  testWidgets('confirmer : retourne vrai ou faux selon le bouton', (tester) async {
    bool? reponse;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                reponse = await confirmer(
                  context,
                  titre: 'Supprimer',
                  message: 'Sûr ?',
                  libelleConfirmer: 'Oui, supprimer',
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Sûr ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(reponse, isFalse);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oui, supprimer'));
    await tester.pumpAndSettle();
    expect(reponse, isTrue);
  });

  testWidgets('composants : message vide et étiquette', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: MessageVide('Rien à afficher')),
              Etiquette('Active', couleur: CouleursGesco.vert, fond: CouleursGesco.vertClair),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Rien à afficher'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
  });

  test('codes couleur : vert bon, orange moyen, rouge insuffisant', () {
    expect(couleurNiveau(NiveauResultat.bon), CouleursGesco.vert);
    expect(couleurNiveau(NiveauResultat.moyen), CouleursGesco.orange);
    expect(couleurNiveau(NiveauResultat.insuffisant), CouleursGesco.rouge);
    expect(fondNiveau(NiveauResultat.bon), CouleursGesco.vertClair);
    expect(fondNiveau(NiveauResultat.moyen), CouleursGesco.orangeClair);
    expect(fondNiveau(NiveauResultat.insuffisant), CouleursGesco.rougeClair);
  });
}
