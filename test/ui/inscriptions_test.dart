import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/ui/inscriptions/dialogue_eleve.dart';
import 'package:gesco/ui/inscriptions/dialogue_reinscription.dart';

const List<Classe> classes = [
  Classe(id: 10, anneeId: 1, niveau: '', nom: '10e A'),
  Classe(id: 11, anneeId: 1, niveau: '', nom: '10e B'),
];

/// Ce que le dialogue a renvoyé en se fermant.
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

TextField champ(WidgetTester tester, String cle) =>
    tester.widget<TextField>(find.byKey(Key(cle)));

String texte(WidgetTester tester, String cle) => champ(tester, cle).controller!.text;

Future<void> saisir(WidgetTester tester, String cle, String valeur) async {
  await tester.enterText(find.byKey(Key(cle)), valeur);
  await tester.pump();
}

Future<void> remplirMinimum(WidgetTester tester) async {
  await saisir(tester, 'champ_nom', '  Diallo ');
  await saisir(tester, 'champ_prenom', 'Aminata');
  await tester.tap(find.text('Féminin'));
  await tester.pump();
}

Future<void> appuyer(WidgetTester tester, String libelle) async {
  await tester.tap(find.text(libelle));
  await tester.pumpAndSettle();
}

void main() {
  group('DialogueEleve - création', () {
    testWidgets('propose le matricule suivant et enregistre les valeurs saisies',
        (tester) async {
      Eleve? recu;
      int? classeRecue;
      final retour = await ouvrir<Object>(
        tester,
        DialogueEleve(
          classes: classes,
          matricules: const ['2026-0003', 'ancien'],
          prefixeMatricule: '2026',
          enregistrer: (eleve, classeId) async {
            recu = eleve;
            classeRecue = classeId;
          },
        ),
      );

      expect(find.text('Inscrire un élève'), findsOneWidget);
      expect(texte(tester, 'champ_matricule'), '2026-0004');

      await remplirMinimum(tester);
      await saisir(tester, 'champ_date', '5/3/2011');
      await saisir(tester, 'champ_lieu', 'Conakry');
      await saisir(tester, 'champ_pere', 'Alpha Diallo');
      await saisir(tester, 'champ_mere', 'Fatou Bah');
      await saisir(tester, 'champ_contact', '+224 600 00 00 00');
      await saisir(tester, 'champ_adresse', 'Tombolia');
      await appuyer(tester, 'Enregistrer');

      final eleve = recu;
      expect(eleve, isNotNull);
      expect(eleve!.id, 0);
      expect(eleve.matricule, '2026-0004');
      expect(eleve.nom, 'Diallo');
      expect(eleve.prenom, 'Aminata');
      expect(eleve.sexe, 'F');
      expect(eleve.dateNaissance, '2011-03-05');
      expect(eleve.lieuNaissance, 'Conakry');
      expect(eleve.nomPere, 'Alpha Diallo');
      expect(eleve.nomMere, 'Fatou Bah');
      expect(eleve.contactParent, '+224 600 00 00 00');
      expect(eleve.adresse, 'Tombolia');
      expect(eleve.photo, isNull);
      expect(classeRecue, 10, reason: 'première classe présélectionnée');
      expect(retour.ferme, isTrue);
      expect(find.byType(DialogueEleve), findsNothing);
    });

    testWidgets('la classe présélectionnée est celle du filtre', (tester) async {
      int? classeRecue;
      await ouvrir<Object>(
        tester,
        DialogueEleve(
          classes: classes,
          matricules: const [],
          prefixeMatricule: '2026',
          classeInitiale: 11,
          enregistrer: (eleve, classeId) async => classeRecue = classeId,
        ),
      );
      await remplirMinimum(tester);
      await appuyer(tester, 'Enregistrer');
      expect(classeRecue, 11);
    });

    testWidgets('sans année reconnue, le matricule proposé est numérique',
        (tester) async {
      await ouvrir<Object>(
        tester,
        DialogueEleve(
          classes: classes,
          matricules: const [],
          prefixeMatricule: '',
          enregistrer: (eleve, classeId) async {},
        ),
      );
      expect(texte(tester, 'champ_matricule'), '0001');
    });

    testWidgets('formulaire vide : erreurs affichées, rien n\'est enregistré',
        (tester) async {
      var appels = 0;
      final retour = await ouvrir<Object>(
        tester,
        DialogueEleve(
          classes: classes,
          matricules: const [],
          prefixeMatricule: '2026',
          enregistrer: (eleve, classeId) async => appels++,
        ),
      );
      await appuyer(tester, 'Enregistrer');

      expect(find.byKey(const Key('erreurs_formulaire')), findsOneWidget);
      expect(find.text('Le nom est obligatoire.'), findsOneWidget);
      expect(find.text('Le prénom est obligatoire.'), findsOneWidget);
      expect(
        find.text('Le sexe doit être renseigné (masculin ou féminin).'),
        findsOneWidget,
      );
      expect(appels, 0);
      expect(retour.ferme, isFalse);
      expect(find.byType(DialogueEleve), findsOneWidget);
    });

    testWidgets('date illisible : message sur le champ, rien n\'est enregistré',
        (tester) async {
      var appels = 0;
      await ouvrir<Object>(
        tester,
        DialogueEleve(
          classes: classes,
          matricules: const [],
          prefixeMatricule: '2026',
          enregistrer: (eleve, classeId) async => appels++,
        ),
      );
      await remplirMinimum(tester);
      await saisir(tester, 'champ_date', 'xx');
      await appuyer(tester, 'Enregistrer');

      expect(
        find.text('Date invalide : utilisez JJ/MM/AAAA (ex. 05/03/2011).'),
        findsOneWidget,
      );
      expect(appels, 0);
    });

    testWidgets('date inexistante (31/02) refusée', (tester) async {
      var appels = 0;
      await ouvrir<Object>(
        tester,
        DialogueEleve(
          classes: classes,
          matricules: const [],
          prefixeMatricule: '2026',
          enregistrer: (eleve, classeId) async => appels++,
        ),
      );
      await remplirMinimum(tester);
      await saisir(tester, 'champ_date', '31/02/2011');
      await appuyer(tester, 'Enregistrer');
      expect(appels, 0);
      expect(find.textContaining('Date invalide'), findsOneWidget);
    });

    testWidgets('date de naissance dans le futur refusée', (tester) async {
      var appels = 0;
      await ouvrir<Object>(
        tester,
        DialogueEleve(
          classes: classes,
          matricules: const [],
          prefixeMatricule: '2026',
          enregistrer: (eleve, classeId) async => appels++,
        ),
      );
      await remplirMinimum(tester);
      final demain = DateTime.now().add(const Duration(days: 2));
      await saisir(
        tester,
        'champ_date',
        '${demain.day}/${demain.month}/${demain.year}',
      );
      await appuyer(tester, 'Enregistrer');
      expect(appels, 0);
      expect(
        find.text('La date de naissance ne peut pas être dans le futur.'),
        findsOneWidget,
      );
    });

    testWidgets('refus de l\'enregistrement : le message s\'affiche et la saisie est conservée',
        (tester) async {
      final retour = await ouvrir<Object>(
        tester,
        DialogueEleve(
          classes: classes,
          matricules: const [],
          prefixeMatricule: '2026',
          enregistrer: (eleve, classeId) async {
            throw const ErreurGesco('Le matricule « 2026-0001 » est déjà utilisé.');
          },
        ),
      );
      await remplirMinimum(tester);
      await saisir(tester, 'champ_lieu', 'Conakry');
      await appuyer(tester, 'Enregistrer');

      expect(
        find.text('Le matricule « 2026-0001 » est déjà utilisé.'),
        findsOneWidget,
      );
      expect(retour.ferme, isFalse);
      expect(texte(tester, 'champ_prenom'), 'Aminata');
      expect(texte(tester, 'champ_lieu'), 'Conakry');

      // Le bouton est de nouveau utilisable après le refus.
      final bouton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Enregistrer'),
      );
      expect(bouton.onPressed, isNotNull);
    });

    testWidgets('Enregistrer et ajouter un autre : vide le formulaire et passe au matricule suivant',
        (tester) async {
      final recus = <Eleve>[];
      final retour = await ouvrir<Object>(
        tester,
        DialogueEleve(
          classes: classes,
          matricules: const [],
          prefixeMatricule: '2026',
          classeInitiale: 11,
          enregistrer: (eleve, classeId) async => recus.add(eleve),
        ),
      );
      expect(texte(tester, 'champ_matricule'), '2026-0001');
      await remplirMinimum(tester);
      await saisir(tester, 'champ_pere', 'Alpha');
      await appuyer(tester, 'Enregistrer et ajouter un autre');

      expect(recus.length, 1);
      expect(recus.single.matricule, '2026-0001');
      expect(retour.ferme, isFalse);
      expect(texte(tester, 'champ_nom'), '');
      expect(texte(tester, 'champ_prenom'), '');
      expect(texte(tester, 'champ_pere'), '');
      expect(texte(tester, 'champ_matricule'), '2026-0002');
      expect(find.text('1 élève enregistré pendant cette saisie.'), findsOneWidget);
      expect(find.text('Fermer'), findsOneWidget);

      // Le sexe a été remis à zéro : il faut le choisir de nouveau.
      await saisir(tester, 'champ_nom', 'Bah');
      await saisir(tester, 'champ_prenom', 'Mariama');
      await appuyer(tester, 'Enregistrer');
      expect(recus.length, 1, reason: 'sexe non renseigné : refusé');
      await tester.tap(find.text('Masculin'));
      await tester.pump();
      await appuyer(tester, 'Enregistrer');

      expect(recus.length, 2);
      expect(recus.last.matricule, '2026-0002');
      expect(recus.last.sexe, 'M');
      expect(retour.ferme, isTrue);
    });

    testWidgets('Annuler ferme sans enregistrer', (tester) async {
      var appels = 0;
      final retour = await ouvrir<Object>(
        tester,
        DialogueEleve(
          classes: classes,
          matricules: const [],
          prefixeMatricule: '2026',
          enregistrer: (eleve, classeId) async => appels++,
        ),
      );
      await appuyer(tester, 'Annuler');
      expect(appels, 0);
      expect(retour.ferme, isTrue);
    });
  });

  group('DialogueEleve - modification', () {
    const existant = Eleve(
      id: 5,
      matricule: 'M-77',
      nom: 'DIALLO',
      prenom: 'Aminata',
      sexe: 'F',
      dateNaissance: '2011-03-05',
      lieuNaissance: 'Conakry',
      nomPere: 'Alpha',
      nomMere: 'Fatou',
      contactParent: '600',
      adresse: 'Tombolia',
    );

    testWidgets('les champs sont préremplis, l\'identité est conservée à l\'enregistrement',
        (tester) async {
      Eleve? recu;
      await ouvrir<Object>(
        tester,
        DialogueEleve(
          classes: classes,
          matricules: const ['M-77'],
          prefixeMatricule: '2026',
          classeInitiale: 11,
          eleve: existant,
          enregistrer: (eleve, classeId) async => recu = eleve,
        ),
      );
      expect(find.text('Modifier l\'élève'), findsOneWidget);
      expect(find.text('Enregistrer et ajouter un autre'), findsNothing);
      expect(texte(tester, 'champ_matricule'), 'M-77');
      expect(texte(tester, 'champ_nom'), 'DIALLO');
      expect(texte(tester, 'champ_date'), '05/03/2011');
      expect(texte(tester, 'champ_adresse'), 'Tombolia');

      await saisir(tester, 'champ_adresse', 'Matoto');
      await appuyer(tester, 'Enregistrer');

      expect(recu!.id, 5);
      expect(recu!.matricule, 'M-77');
      expect(recu!.sexe, 'F');
      expect(recu!.dateNaissance, '2011-03-05');
      expect(recu!.adresse, 'Matoto');
    });

    testWidgets('on peut effacer la date de naissance', (tester) async {
      Eleve? recu;
      await ouvrir<Object>(
        tester,
        DialogueEleve(
          classes: classes,
          matricules: const [],
          prefixeMatricule: '2026',
          classeInitiale: 10,
          eleve: existant,
          enregistrer: (eleve, classeId) async => recu = eleve,
        ),
      );
      await saisir(tester, 'champ_date', '');
      await appuyer(tester, 'Enregistrer');
      expect(recu, isNotNull);
      expect(recu!.dateNaissance, isNull);
    });

    testWidgets('sans notes, la classe peut être changée', (tester) async {
      await ouvrir<Object>(
        tester,
        DialogueEleve(
          classes: classes,
          matricules: const [],
          prefixeMatricule: '2026',
          classeInitiale: 10,
          eleve: existant,
          enregistrer: (eleve, classeId) async {},
        ),
      );
      final liste = tester.widget<DropdownButton<int>>(find.byKey(const Key('liste_classe')));
      expect(liste.onChanged, isNotNull);
      expect(find.textContaining('Classe verrouillée'), findsNothing);
    });

    testWidgets('avec des notes, la classe est verrouillée et le dit', (tester) async {
      await ouvrir<Object>(
        tester,
        DialogueEleve(
          classes: classes,
          matricules: const [],
          prefixeMatricule: '2026',
          classeInitiale: 10,
          eleve: existant,
          nbNotes: 3,
          enregistrer: (eleve, classeId) async {},
        ),
      );
      final liste = tester.widget<DropdownButton<int>>(find.byKey(const Key('liste_classe')));
      expect(liste.onChanged, isNull);
      expect(
        find.text('Classe verrouillée : 3 notes sont déjà enregistrées.'),
        findsOneWidget,
      );
    });

    testWidgets('une seule note : accord au singulier', (tester) async {
      await ouvrir<Object>(
        tester,
        DialogueEleve(
          classes: classes,
          matricules: const [],
          prefixeMatricule: '2026',
          classeInitiale: 10,
          eleve: existant,
          nbNotes: 1,
          enregistrer: (eleve, classeId) async {},
        ),
      );
      expect(
        find.text('Classe verrouillée : 1 note est déjà enregistrée.'),
        findsOneWidget,
      );
    });
  });

  group('DialogueReinscription', () {
    const candidats = [
      Eleve(id: 1, matricule: 'M1', nom: 'Bah', prenom: 'Zoé', sexe: 'F'),
      Eleve(id: 2, matricule: 'M2', nom: 'Camara', prenom: 'Ibrahima', sexe: 'M'),
      Eleve(id: 3, matricule: 'M3', nom: 'Diallo', prenom: 'Aminata', sexe: 'F'),
    ];

    DialogueReinscription dialogue({int? classeInitiale}) => DialogueReinscription(
          candidats: candidats,
          classes: classes,
          classeInitiale: classeInitiale,
        );

    testWidgets('au départ rien n\'est sélectionné et le bouton est inactif',
        (tester) async {
      await ouvrir<ChoixReinscription>(tester, dialogue());
      expect(find.byType(CheckboxListTile), findsNWidgets(3));
      expect(find.textContaining('0 sélectionné'), findsOneWidget);
      final bouton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Réinscrire'),
      );
      expect(bouton.onPressed, isNull);
    });

    testWidgets('tout sélectionner, en retirer un, valider', (tester) async {
      final retour = await ouvrir<ChoixReinscription>(
        tester,
        dialogue(classeInitiale: 11),
      );
      await appuyer(tester, 'Tout sélectionner');
      expect(find.textContaining('3 sélectionnés'), findsOneWidget);
      expect(find.text('Tout désélectionner'), findsOneWidget);

      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      expect(find.textContaining('2 sélectionnés'), findsOneWidget);

      await appuyer(tester, 'Réinscrire (2)');
      final choix = retour.valeur;
      expect(choix, isNotNull);
      expect(choix!.eleveIds, [2, 3]);
      expect(choix.classeId, 11);
    });

    testWidgets('la recherche ignore accents et casse, et « tout sélectionner » ne touche que les élèves affichés',
        (tester) async {
      final retour = await ouvrir<ChoixReinscription>(tester, dialogue());
      await saisir(tester, 'recherche_reinscription', 'ZOE');
      expect(find.byType(CheckboxListTile), findsNWidgets(1));
      expect(find.text('BAH Zoé'), findsOneWidget);

      await appuyer(tester, 'Tout sélectionner');
      await saisir(tester, 'recherche_reinscription', '');
      expect(find.textContaining('1 sélectionné'), findsOneWidget);

      await appuyer(tester, 'Réinscrire (1)');
      expect(retour.valeur!.eleveIds, [1]);
      expect(retour.valeur!.classeId, 10, reason: 'première classe par défaut');
    });

    testWidgets('recherche sans résultat', (tester) async {
      await ouvrir<ChoixReinscription>(tester, dialogue());
      await saisir(tester, 'recherche_reinscription', 'zzz');
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text('Aucun élève ne correspond à la recherche.'), findsOneWidget);
    });

    testWidgets('Annuler ne renvoie rien', (tester) async {
      final retour = await ouvrir<ChoixReinscription>(tester, dialogue());
      await appuyer(tester, 'Tout sélectionner');
      await appuyer(tester, 'Annuler');
      expect(retour.ferme, isTrue);
      expect(retour.valeur, isNull);
    });
  });
}
