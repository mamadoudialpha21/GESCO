import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/depots/note_depot.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/ui/notes/grille_notes.dart';
import 'package:gesco/ui/notes/periode.dart';

const List<MatiereClasse> matieres = [
  MatiereClasse(id: 1, classeId: 10, nom: 'Maths', coefficient: 400, ordre: 1),
  MatiereClasse(id: 2, classeId: 10, nom: 'Français', coefficient: 300, ordre: 2),
];

const List<EleveInscrit> eleves = [
  EleveInscrit(
    inscriptionId: 1,
    eleveId: 1,
    classeId: 10,
    classeNom: '10e A',
    matricule: '2026-0001',
    nom: 'DIALLO',
    prenom: 'Aminata',
    sexe: 'F',
  ),
  EleveInscrit(
    inscriptionId: 2,
    eleveId: 2,
    classeId: 10,
    classeNom: '10e A',
    matricule: '2026-0002',
    nom: 'BARRY',
    prenom: 'Ibrahima',
    sexe: 'M',
  ),
  EleveInscrit(
    inscriptionId: 3,
    eleveId: 3,
    classeId: 10,
    classeNom: '10e A',
    matricule: '2026-0003',
    nom: 'CAMARA',
    prenom: 'Fatoumata',
    sexe: 'F',
  ),
];

/// Ce que la grille a demandé d'enregistrer.
class Appel {
  Appel(this.inscriptionId, this.matiereId, this.mois, this.saisie);

  final int inscriptionId;
  final int matiereId;
  final int mois;
  final Saisie? saisie;

  @override
  String toString() =>
      'Appel($inscriptionId, $matiereId, mois $mois, ${saisie?.etat.name} ${saisie?.centiemes})';
}

class Banc {
  final List<Appel> appels = [];
  Object? erreur;

  Future<void> enregistrer({
    required int inscriptionId,
    required int matiereId,
    required int mois,
    required Saisie? saisie,
  }) async {
    final e = erreur;
    if (e != null) throw e;
    appels.add(Appel(inscriptionId, matiereId, mois, saisie));
  }
}

/// Maths sur 40, français sur 20.
const List<MatiereClasse> matieresMixtes = [
  MatiereClasse(id: 1, classeId: 10, nom: 'Maths', coefficient: 400, ordre: 1, bareme: 40),
  MatiereClasse(id: 2, classeId: 10, nom: 'Français', coefficient: 300, ordre: 2),
];

SaisiesClasse saisiesDepart() => {
      1: {
        1: {10: const Saisie.valeur(1400)},
      },
    };

Future<Banc> afficher(
  WidgetTester tester, {
  Periode periode = const Periode.mois(10),
  SaisiesClasse? saisies,
  Banc? banc,
  double largeur = 1400,
  List<MatiereClasse> matieresAffichees = matieres,
  Set<(int, int)> casesEvaluees = const {},
  Set<int> moisVerrouilles = const {},
  Calendrier calendrier = Calendrier.defaut,
}) async {
  tester.view.physicalSize = Size(largeur, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final b = banc ?? Banc();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GrilleNotes(
          enregistrer: b.enregistrer,
          matieres: matieresAffichees,
          eleves: eleves,
          saisies: saisies ?? saisiesDepart(),
          config: ConfigResultats.defaut,
          periode: periode,
          casesEvaluees: casesEvaluees,
          moisVerrouilles: moisVerrouilles,
          calendrier: calendrier,
        ),
      ),
    ),
  );
  await tester.pump();
  return b;
}

Finder caseDe(int ligne, int colonne) => find.byKey(Key('case_${ligne}_$colonne'));
final Finder champ = find.byKey(const Key('champ_note'));

Future<void> ouvrir(WidgetTester tester, int ligne, int colonne) async {
  await tester.tap(caseDe(ligne, colonne));
  await tester.pump();
  await tester.pump();
}

Future<void> taper(WidgetTester tester, String texte) async {
  await tester.enterText(champ, texte);
  await tester.pump();
}

Future<void> entree(WidgetTester tester) async {
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

String texteDe(WidgetTester tester, Key cle) {
  final texte = find.descendant(of: find.byKey(cle), matching: find.byType(Text));
  return tester.widget<Text>(texte.first).data ?? '';
}

void main() {
  group('affichage', () {
    testWidgets('élèves, matières, coefficients et notes existantes', (tester) async {
      await afficher(tester);

      expect(find.text('DIALLO Aminata'), findsOneWidget);
      expect(find.text('BARRY Ibrahima'), findsOneWidget);
      expect(find.text('CAMARA Fatoumata'), findsOneWidget);
      expect(find.text('2026-0002'), findsOneWidget);
      expect(find.text('Maths'), findsOneWidget);
      expect(find.text('Français'), findsOneWidget);
      expect(find.text('coef 4'), findsOneWidget);
      expect(find.text('coef 3'), findsOneWidget);
      // La note existante de Aminata en maths.
      expect(find.descendant(of: caseDe(0, 0), matching: find.text('14,00')),
          findsOneWidget);
      // Cases vides : rien d'écrit, surtout pas 0.
      expect(find.descendant(of: caseDe(1, 0), matching: find.byType(Text)),
          findsNothing);
      expect(find.text('0,00'), findsNothing);
    });

    testWidgets('les colonnes remplissent la largeur quand le tableau est étroit',
        (tester) async {
      await afficher(tester);
      // Deux matières seulement : sans étirement, « Mention » serait vers
      // x = 570 ; étirée, la colonne s'étend jusqu'au bord droit.
      expect(find.text('Mention'), findsOneWidget);
      expect(tester.getCenter(find.text('Mention')).dx, greaterThan(1150));
    });

    testWidgets('sur un écran étroit le tableau défile au lieu de se comprimer',
        (tester) async {
      await afficher(tester, largeur: 500);
      // Largeur naturelle des colonnes conservée : « Mention » est hors écran.
      expect(tester.getCenter(find.text('Mention')).dx, greaterThan(500));
      expect(tester.takeException(), isNull);
    });

    test('les titres de colonne très longs sont légèrement réduits', () {
      expect(taillePoliceTitre('Maths'), 12.5);
      expect(taillePoliceTitre('Physique-Chimie'), 12.5);
      expect(taillePoliceTitre('Histoire-Géographie'), 12.5);
      expect(taillePoliceTitre('Informatique'), 12);
      expect(taillePoliceTitre('Mathématiques'), 11.5);
    });

    test('les colonnes de matière s\'élargissent pour les mots longs', () {
      final courte = largeurColonneMatiere('SVT');
      final longue = largeurColonneMatiere('Mathématiques');
      expect(courte, largeurColonneMatiere('Maths'));
      expect(longue, greaterThan(courte));
      expect(longue, lessThanOrEqualTo(112));
    });

    testWidgets('moyenne et rang calculés tout de suite', (tester) async {
      await afficher(tester);
      // Aminata : seule matière notée = maths 14 -> moyenne 14,00 ; 1re.
      expect(texteDe(tester, const Key('moyenne_0')), '14,00');
      expect(texteDe(tester, const Key('rang_0')), '1er');
      // Les autres n'ont aucune note : pas de moyenne, pas de rang.
      expect(find.byKey(const Key('moyenne_1')), findsNothing);
      expect(find.byKey(const Key('rang_1')), findsNothing);
    });

    testWidgets('avancement et état au repos', (tester) async {
      await afficher(tester);
      expect(tester.widget<Text>(find.byKey(const Key('avancement'))).data,
          'Octobre : 1 / 6 cases renseignées');
      expect(find.textContaining('Cliquez sur une case'), findsOneWidget);
    });

    testWidgets('ligne « moyenne de la classe »', (tester) async {
      await afficher(
        tester,
        saisies: {
          1: {
            1: {10: const Saisie.valeur(1400)},
          },
          2: {
            1: {10: const Saisie.valeur(1001)},
          },
        },
      );
      expect(find.text('Moyenne de la classe'), findsOneWidget);
      // Colonne maths : (1400 + 1001) / 2 = 1200,5 -> 12,01 (demi vers le haut).
      expect(find.text('12,01'), findsWidgets);
    });
  });

  group('saisie', () {
    testWidgets('Entrée enregistre la note et passe à l\'élève suivant', (tester) async {
      final banc = await afficher(tester);

      await ouvrir(tester, 1, 0);
      expect(champ, findsOneWidget);
      await taper(tester, '12,5');
      await entree(tester);

      expect(banc.appels, hasLength(1));
      final a = banc.appels.single;
      expect([a.inscriptionId, a.matiereId, a.mois], [2, 1, 10]);
      expect(a.saisie!.etat, EtatNote.saisie);
      expect(a.saisie!.centiemes, 1250);

      // La case suivante (élève 3, maths) est ouverte ; celle de l'élève 2 affiche la note.
      expect(champ, findsOneWidget);
      expect(caseDe(2, 0), findsNothing);
      expect(find.descendant(of: caseDe(1, 0), matching: find.text('12,50')),
          findsOneWidget);
      expect(find.text('Enregistré automatiquement'), findsOneWidget);
    });

    testWidgets('moyenne pondérée et rangs mis à jour en direct', (tester) async {
      await afficher(tester);

      await ouvrir(tester, 1, 0);
      await taper(tester, '12,5');
      await entree(tester); // passe à la ligne 2, maths
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      await ouvrir(tester, 1, 1);
      await taper(tester, '9');
      await entree(tester);

      // Ibrahima : (12,5 x 4 + 9 x 3) / 7 = 11,00.
      expect(texteDe(tester, const Key('moyenne_1')), '11,00');
      expect(texteDe(tester, const Key('rang_1')), '2e');
      expect(texteDe(tester, const Key('rang_0')), '1er');
    });

    testWidgets('« A » = absent : affiché ABS, jamais compté comme zéro', (tester) async {
      final banc = await afficher(tester);

      await ouvrir(tester, 0, 1);
      await taper(tester, 'a');
      await entree(tester);

      expect(banc.appels.single.saisie!.etat, EtatNote.absent);
      expect(banc.appels.single.saisie!.centiemes, isNull);
      expect(find.descendant(of: caseDe(0, 1), matching: find.text('ABS')),
          findsOneWidget);
      // La moyenne reste 14,00 (pas tirée vers le bas par un zéro) mais le
      // résultat est signalé incomplet.
      expect(texteDe(tester, const Key('moyenne_0')), '14,00');
      expect(find.text('*'), findsWidgets);
    });

    testWidgets('« D » = dispensé', (tester) async {
      final banc = await afficher(tester);
      await ouvrir(tester, 0, 1);
      await taper(tester, 'D');
      await entree(tester);
      expect(banc.appels.single.saisie!.etat, EtatNote.dispense);
      expect(find.descendant(of: caseDe(0, 1), matching: find.text('DISP')),
          findsOneWidget);
    });

    testWidgets('un vrai zéro est enregistré et compte dans la moyenne', (tester) async {
      final banc = await afficher(tester);
      await ouvrir(tester, 0, 1);
      await taper(tester, '0');
      await entree(tester);
      expect(banc.appels.single.saisie!.centiemes, 0);
      // (14 x 4 + 0 x 3) / 7 = 8,00
      expect(texteDe(tester, const Key('moyenne_0')), '8,00');
    });

    testWidgets('vider une case supprime la note', (tester) async {
      final banc = await afficher(tester);
      await ouvrir(tester, 0, 0);
      await taper(tester, '');
      await entree(tester);

      expect(banc.appels, hasLength(1));
      expect(banc.appels.single.saisie, isNull);
      expect(find.descendant(of: caseDe(0, 0), matching: find.byType(Text)),
          findsNothing);
      expect(find.byKey(const Key('moyenne_0')), findsNothing);
    });

    testWidgets('même valeur : aucun enregistrement inutile', (tester) async {
      final banc = await afficher(tester);
      await ouvrir(tester, 0, 0);
      await taper(tester, '14');
      await entree(tester);
      expect(banc.appels, isEmpty);
    });

    testWidgets('note invalide : refusée, case conservée, message clair', (tester) async {
      final banc = await afficher(tester);
      await ouvrir(tester, 1, 0);
      await taper(tester, '25');
      await entree(tester);

      expect(banc.appels, isEmpty);
      expect(champ, findsOneWidget, reason: 'la case reste ouverte pour corriger');
      expect(find.textContaining('dépasse 20'), findsOneWidget);

      // Corriger efface le message et permet d'enregistrer.
      await taper(tester, '15');
      expect(find.textContaining('dépasse 20'), findsNothing);
      await entree(tester);
      expect(banc.appels.single.saisie!.centiemes, 1500);
    });

    testWidgets('texte quelconque refusé', (tester) async {
      final banc = await afficher(tester);
      await ouvrir(tester, 1, 0);
      await taper(tester, 'xyz');
      await entree(tester);
      expect(banc.appels, isEmpty);
      expect(find.textContaining('n\'est pas une note valide'), findsOneWidget);
    });

    testWidgets('cliquer sur une autre case valide la saisie en cours', (tester) async {
      final banc = await afficher(tester);
      await ouvrir(tester, 1, 0);
      await taper(tester, '10');
      await tester.tap(caseDe(2, 1));
      await tester.pump();
      await tester.pump();

      expect(banc.appels, hasLength(1));
      expect(banc.appels.single.saisie!.centiemes, 1000);
      expect(champ, findsOneWidget, reason: 'la nouvelle case est ouverte');
      expect(find.descendant(of: caseDe(1, 0), matching: find.text('10,00')),
          findsOneWidget);
    });

    testWidgets('enregistrement automatique après une courte pause', (tester) async {
      final banc = await afficher(tester);
      await ouvrir(tester, 1, 0);
      await taper(tester, '15');
      expect(banc.appels, isEmpty);

      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();

      expect(banc.appels, hasLength(1));
      expect(banc.appels.single.saisie!.centiemes, 1500);
      expect(champ, findsOneWidget, reason: 'on peut continuer à taper');
    });

    testWidgets('Échap abandonne la frappe non enregistrée', (tester) async {
      final banc = await afficher(tester);
      await ouvrir(tester, 1, 0);
      await taper(tester, '19');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(banc.appels, isEmpty);
      expect(champ, findsNothing);
      expect(find.descendant(of: caseDe(1, 0), matching: find.byType(Text)),
          findsNothing);
    });

    testWidgets('Tab passe à la matière suivante, flèche bas à l\'élève suivant',
        (tester) async {
      final banc = await afficher(tester);
      await ouvrir(tester, 0, 0);
      await taper(tester, '14');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      expect(champ, findsOneWidget);
      expect(caseDe(0, 0), findsOneWidget, reason: 'la case 0,0 n\'est plus ouverte');
      expect(caseDe(0, 1), findsNothing, reason: 'la case 0,1 est ouverte');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump();
      expect(caseDe(1, 1), findsNothing, reason: 'la case 1,1 est ouverte');
      expect(caseDe(0, 1), findsOneWidget);
      expect(banc.appels, isEmpty, reason: 'rien n\'a changé');
    });

    testWidgets('Entrée sur le dernier élève ferme la case', (tester) async {
      final banc = await afficher(tester);
      await ouvrir(tester, 2, 0);
      await taper(tester, '11');
      await entree(tester);
      expect(banc.appels.single.inscriptionId, 3);
      expect(champ, findsNothing);
    });
  });

  group('erreur d\'enregistrement', () {
    testWidgets('la note est remise comme avant et l\'erreur est affichée', (tester) async {
      final banc = Banc()..erreur = const ErreurGesco('Disque plein');
      await afficher(tester, banc: banc);

      await ouvrir(tester, 1, 0);
      await taper(tester, '12');
      await entree(tester);
      await tester.pump();

      expect(find.textContaining('Note non enregistrée : Disque plein'), findsOneWidget);
      // La case est revenue à l'état d'avant (vide) : la fausse note ne reste pas.
      expect(find.descendant(of: caseDe(1, 0), matching: find.text('12,00')),
          findsNothing);
      expect(find.byKey(const Key('moyenne_1')), findsNothing);
    });
  });

  group('trimestre et année (lecture seule)', () {
    SaisiesClasse saisiesTrimestre() => {
          1: {
            1: {
              10: const Saisie.valeur(1400),
              11: const Saisie.valeur(1000),
            },
          },
          2: {
            1: {10: const Saisie.valeur(600)},
          },
        };

    testWidgets('trimestre 1 : moyennes calculées, aucune case modifiable', (tester) async {
      final banc = await afficher(
        tester,
        periode: const Periode.trimestre(1),
        saisies: saisiesTrimestre(),
      );

      expect(caseDe(0, 0), findsNothing);
      expect(caseDe(1, 0), findsNothing);
      expect(champ, findsNothing);
      expect(find.textContaining('lecture seule'), findsOneWidget);

      // Aminata : maths = (14 + 10) / 2 = 12,00 -> moyenne du trimestre 12,00.
      expect(texteDe(tester, const Key('moyenne_0')), '12,00');
      expect(texteDe(tester, const Key('rang_0')), '1er');
      // Ibrahima : 6,00 -> non admis.
      expect(texteDe(tester, const Key('moyenne_1')), '6,00');
      expect(find.text('Admis(e)'), findsOneWidget);
      expect(find.text('Non admis(e)'), findsOneWidget);
      expect(find.text('Assez bien'), findsOneWidget);
      expect(banc.appels, isEmpty);
    });

    testWidgets('année : trimestres et moyenne annuelle', (tester) async {
      await afficher(
        tester,
        periode: const Periode.annee(),
        saisies: saisiesTrimestre(),
      );
      expect(find.text('Trimestre 1'), findsOneWidget);
      expect(find.text('Trimestre 2'), findsOneWidget);
      expect(find.text('Trimestre 3'), findsOneWidget);
      expect(find.text('Moy. annuelle'), findsOneWidget);
      // Seul le trimestre 1 est renseigné : moyenne annuelle = moyenne du T1.
      expect(texteDe(tester, const Key('moyenne_0')), '12,00');
      expect(find.text('Admis(e) en classe supérieure'), findsOneWidget);
      expect(find.text('Redouble'), findsOneWidget);
    });
  });

  group('Periode', () {
    test('mois proposé au départ', () {
      expect(Periode.moisDe(DateTime(2026, 2, 3)), const Periode.mois(2));
      expect(Periode.moisDe(DateTime(2026, 10, 15)), const Periode.mois(10));
      expect(Periode.moisDe(DateTime(2026, 8, 1)), const Periode.mois(10),
          reason: 'hors année scolaire : octobre');
    });

    test('ordre d\'affichage et libellés', () {
      expect(periodesAffichees, hasLength(13));
      expect(periodesAffichees.map((p) => p.libelle).take(5),
          ['Octobre', 'Novembre', 'Décembre', 'Trimestre 1', 'Janvier']);
      expect(periodesAffichees.last.libelle, 'Année');
      expect(periodesAffichees.where((p) => p.saisissable), hasLength(9));
      expect(periodesAffichees.toSet(), hasLength(13));
    });
  });

  group('barèmes, évaluations et mois verrouillés', () {
    Finder lecture(int ligne, int colonne) =>
        find.byKey(Key('case_lecture_${ligne}_$colonne'));

    testWidgets('une matière sur 40 : en-tête, saisie sur 40, conversion sur 20',
        (tester) async {
      final banc = await afficher(tester, matieresAffichees: matieresMixtes);

      expect(find.text('coef 4 · /40'), findsOneWidget);
      expect(find.text('coef 3'), findsOneWidget);

      await ouvrir(tester, 1, 0);
      await taper(tester, '31');
      await entree(tester);

      final a = banc.appels.single;
      expect([a.inscriptionId, a.matiereId, a.mois], [2, 1, 10]);
      expect(a.saisie!.brut, 3100);
      expect(a.saisie!.bareme, 40);
      expect(a.saisie!.centiemes, 1550, reason: '31 sur 40 = 15,50 sur 20');
      // La case affiche la note telle qu'elle a été tapée (sur 40).
      expect(find.descendant(of: caseDe(1, 0), matching: find.text('31,00')),
          findsOneWidget);
      // La moyenne de l'élève est calculée sur 20.
      expect(texteDe(tester, const Key('moyenne_1')), '15,50');
    });

    testWidgets('une note qui dépasse le barème de la matière est refusée',
        (tester) async {
      final banc = await afficher(tester, matieresAffichees: matieresMixtes);
      await ouvrir(tester, 1, 0);
      await taper(tester, '41');
      await entree(tester);

      expect(banc.appels, isEmpty);
      expect(find.textContaining('dépasse 40'), findsOneWidget);
      // 25 est valide sur 40 (alors qu'elle dépasserait 20).
      await taper(tester, '25');
      await entree(tester);
      expect(banc.appels.single.saisie!.centiemes, 1250);
    });

    testWidgets('une note déjà enregistrée sur 40 se réaffiche sur 40', (tester) async {
      await afficher(
        tester,
        matieresAffichees: matieresMixtes,
        saisies: {
          1: {
            1: {10: const Saisie.surBareme(3100, 40)},
          },
        },
      );
      expect(find.descendant(of: caseDe(0, 0), matching: find.text('31,00')),
          findsOneWidget);
      expect(texteDe(tester, const Key('moyenne_0')), '15,50');
    });

    testWidgets('note calculée d\'après les évaluations : case en lecture seule',
        (tester) async {
      final banc = await afficher(
        tester,
        casesEvaluees: {(1, 10)},
        saisies: {
          2: {
            1: {10: const Saisie.valeur(1450)},
          },
        },
      );
      // Maths (colonne 0) : cases en lecture seule, note affichée.
      expect(lecture(0, 0), findsOneWidget);
      expect(lecture(1, 0), findsOneWidget);
      expect(find.descendant(of: lecture(1, 0), matching: find.text('14,50')),
          findsOneWidget);
      await tester.tap(lecture(0, 0));
      await tester.pump();
      expect(champ, findsNothing, reason: 'la case ne s\'ouvre pas');
      expect(banc.appels, isEmpty);

      // Français (colonne 1) reste modifiable.
      await ouvrir(tester, 0, 1);
      expect(champ, findsOneWidget);
    });

    testWidgets('Tab saute la colonne calculée d\'après les évaluations',
        (tester) async {
      // Français (matière 2) est calculé d'après ses évaluations.
      final banc = await afficher(tester, casesEvaluees: {(2, 10)});
      await ouvrir(tester, 0, 0);
      await taper(tester, '15');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      // La case suivante est celle de l'élève suivant en maths (1, 0).
      expect(champ, findsOneWidget);
      expect(caseDe(1, 0), findsNothing, reason: 'la case 1,0 est ouverte');
      expect(caseDe(0, 0), findsOneWidget);
      expect(banc.appels.single.saisie!.centiemes, 1500);
    });

    testWidgets('mois verrouillé : plus aucune case modifiable', (tester) async {
      final banc = await afficher(tester, moisVerrouilles: {10});
      expect(lecture(0, 0), findsOneWidget);
      expect(lecture(0, 1), findsOneWidget);
      expect(caseDe(0, 0), findsNothing);
      await tester.tap(lecture(1, 1));
      await tester.pump();
      expect(champ, findsNothing);
      expect(banc.appels, isEmpty);
    });

    testWidgets('un autre mois que le mois verrouillé reste modifiable', (tester) async {
      await afficher(
        tester,
        periode: const Periode.mois(11),
        moisVerrouilles: {10},
      );
      expect(lecture(0, 0), findsNothing);
      await ouvrir(tester, 0, 0);
      expect(champ, findsOneWidget);
    });
  });

  group('calendrier configurable', () {
    // Maths d'Aminata : 10, 12, 14 et 16 en octobre, novembre, décembre, janvier.
    SaisiesClasse saisiesQuatreMois() => {
          1: {
            1: {
              10: const Saisie.valeur(1000),
              11: const Saisie.valeur(1200),
              12: const Saisie.valeur(1400),
              1: const Saisie.valeur(1600),
            },
          },
        };

    testWidgets('trimestres : la période 1 regroupe octobre à décembre', (tester) async {
      await afficher(
        tester,
        periode: const Periode.trimestre(1),
        saisies: saisiesQuatreMois(),
      );
      expect(texteDe(tester, const Key('moyenne_0')), '12,00');
    });

    testWidgets('semestres : le semestre 1 regroupe octobre à janvier', (tester) async {
      await afficher(
        tester,
        periode: const Periode.trimestre(1, etiquette: 'Semestre 1'),
        saisies: saisiesQuatreMois(),
        calendrier: Calendrier.semestres,
      );
      // (10 + 12 + 14 + 16) / 4 = 13,00
      expect(texteDe(tester, const Key('moyenne_0')), '13,00');
      expect(find.textContaining('Semestre 1'), findsWidgets);
    });

    testWidgets('semestres : l\'année a deux colonnes de période', (tester) async {
      await afficher(
        tester,
        periode: const Periode.annee(),
        saisies: saisiesQuatreMois(),
        calendrier: Calendrier.semestres,
      );
      expect(find.text('Semestre 1'), findsOneWidget);
      expect(find.text('Semestre 2'), findsOneWidget);
      expect(find.text('Trimestre 3'), findsNothing);
      // Seul le semestre 1 est renseigné : moyenne annuelle = 13,00.
      expect(texteDe(tester, const Key('moyenne_0')), '13,00');
    });

    testWidgets('séquences : moyenne d\'une séquence de deux mois', (tester) async {
      final calendrier = Calendrier.trimestres.copyWith(
        sequences: Calendrier.sequencesProposees,
      );
      await afficher(
        tester,
        periode: const Periode.sequence(1, etiquette: 'Séquence 1'),
        saisies: saisiesQuatreMois(),
        calendrier: calendrier,
      );
      // Séquence 1 = octobre et novembre : (10 + 12) / 2 = 11,00
      expect(texteDe(tester, const Key('moyenne_0')), '11,00');
      expect(caseDe(0, 0), findsNothing, reason: 'une séquence est en lecture seule');
    });

    testWidgets('moyennes mensuelles masquées : seules les notes restent', (tester) async {
      await afficher(
        tester,
        calendrier: Calendrier.defaut.copyWith(moyenneMensuelle: false),
      );
      expect(find.byKey(const Key('moyenne_0')), findsNothing);
      expect(find.byKey(const Key('rang_0')), findsNothing);
      expect(caseDe(0, 0), findsOneWidget, reason: 'la saisie reste possible');
    });

    testWidgets('moyennes mensuelles masquées : le trimestre garde sa moyenne',
        (tester) async {
      await afficher(
        tester,
        periode: const Periode.trimestre(1),
        saisies: saisiesQuatreMois(),
        calendrier: Calendrier.defaut.copyWith(moyenneMensuelle: false),
      );
      expect(texteDe(tester, const Key('moyenne_0')), '12,00');
    });

    test('periodesDuCalendrier : trimestres (ordre par défaut)', () {
      final p = periodesDuCalendrier(Calendrier.defaut);
      expect(p, periodesAffichees);
      expect(p, hasLength(13));
    });

    test('periodesDuCalendrier : semestres', () {
      final p = periodesDuCalendrier(Calendrier.semestres);
      expect(p.map((x) => x.libelle), [
        'Octobre', 'Novembre', 'Décembre', 'Janvier', 'Semestre 1',
        'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Semestre 2', 'Année',
      ]);
    });

    test('periodesDuCalendrier : une séquence précède la période qui la termine', () {
      final calendrier = Calendrier.trimestres.copyWith(
        sequences: Calendrier.sequencesProposees,
      );
      final p = periodesDuCalendrier(calendrier);
      expect(p, hasLength(9 + 6 + 3 + 1));
      expect(p.map((x) => x.libelle).take(7), [
        'Octobre', 'Novembre', 'Séquence 1', 'Décembre', 'Séquence 2',
        'Trimestre 1', 'Janvier',
      ]);
      expect(p.where((x) => x.genre == GenrePeriode.sequence), hasLength(6));
    });

    test('periode.portee : numéro de période et de séquence', () {
      final calendrier = Calendrier.semestres;
      final portee = const Periode.trimestre(2).portee(calendrier);
      expect(portee.periodeChoisie!.cle, 's2');
      expect(const Periode.mois(3).portee(calendrier).moisChoisi, 3);
      expect(const Periode.annee().portee(calendrier).annuelle, isTrue);
    });

    test('l\'étiquette ne compte pas dans l\'égalité', () {
      expect(const Periode.trimestre(1, etiquette: 'Semestre 1'), const Periode.trimestre(1));
    });
  });
}
