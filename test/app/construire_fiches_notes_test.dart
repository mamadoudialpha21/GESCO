import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/app/construire_fiches_notes.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_notation.dart';
import 'package:gesco/documents/modele_fiche_notes.dart';

import 'classe_exemple.dart';

void main() {
  // Élèves : 1 BARRY (M), 2 CAMARA (F), 3 DIALLO (M), 4 SOW (parti), 5 TOURE (M).
  final eleves = [
    eleve(1, 'BARRY'),
    eleve(2, 'CAMARA'),
    eleve(3, 'DIALLO'),
    eleve(4, 'SOW', statut: StatutInscription.depart),
    eleve(5, 'TOURE', statut: StatutInscription.abandon),
  ];

  group('titres des colonnes', () {
    test('titres saisis : virgules, points-virgules et lignes, sans vides', () {
      expect(
        intitulesFiche(' Interro 1 , Devoir;Composition\n\n, ', 5),
        ['Interro 1', 'Devoir', 'Composition'],
      );
    });

    test('sans titre : « Note 1 », « Note 2 »... selon le nombre demandé', () {
      expect(intitulesFiche('', 3), ['Note 1', 'Note 2', 'Note 3']);
      expect(intitulesFiche('  ', 2), ['Note 1', 'Note 2']);
    });

    test('une seule colonne : « Note »', () {
      expect(intitulesFiche('', 1), ['Note']);
    });

    test('nombre ramené entre 1 et le maximum', () {
      expect(intitulesFiche('', 0), ['Note']);
      expect(intitulesFiche('', 99), hasLength(colonnesNotesMax));
      expect(intitulesFiche(List.filled(30, 'x').join(','), 2), hasLength(colonnesNotesMax));
    });
  });

  group('fiche de notes d\'une matière', () {
    final maths = const MatiereClasse(
        id: 1, classeId: 1, nom: 'Maths', coefficient: 100, ordre: 1, enseignantId: 7);
    final francais = const MatiereClasse(
        id: 2, classeId: 1, nom: 'Français', coefficient: 100, ordre: 2, bareme: 10);

    List<FicheNotes> fiches({OptionsFicheNotes options = const OptionsFicheNotes()}) =>
        construireFichesNotes(
          etablissement: etablissement,
          anneeLibelle: '2026-2027',
          classeNom: '10e A',
          eleves: eleves,
          matieres: [maths, francais],
          enseignants: const {7: 'KANTE Moussa'},
          options: options,
          dateEdition: DateTime(2026, 11, 22),
        );

    test('une fiche par matière, dans l\'ordre donné', () {
      final f = fiches();
      expect([for (final x in f) x.matiereNom], ['Maths', 'Français']);
      expect(f.every((x) => !x.estListe), isTrue);
      expect(f.first.titre, 'FICHE DE NOTES');
    });

    test('seuls les élèves qui suivent la classe figurent, numérotés dans l\'ordre reçu', () {
      final l = fiches().first.lignes;
      expect([for (final x in l) x.numero], [1, 2, 3]);
      expect([for (final x in l) x.nom], ['BARRY X', 'CAMARA X', 'DIALLO X']);
      expect([for (final x in l) x.matricule], ['M1', 'M2', 'M3']);
      expect([for (final x in l) x.sexe], ['M', 'F', 'M']);
      expect(fiches().first.nbFilles, 1);
      expect(fiches().first.nbGarcons, 2);
    });

    test('enseignant de la matière, ou vide quand elle n\'en a pas', () {
      final f = fiches();
      expect(f[0].enseignant, 'KANTE Moussa');
      expect(f[1].enseignant, '');
    });

    test('barème de chaque matière', () {
      final f = fiches();
      expect(f[0].bareme, 20);
      expect(f[1].bareme, 10);
    });

    test('en-tête, classe, année et date d\'édition', () {
      final f = fiches().first;
      expect(f.entete.nom, 'Groupe Scolaire Test');
      expect(f.entete.adresse, 'Tombolia, Conakry');
      expect(f.classeNom, '10e A');
      expect(f.anneeLibelle, '2026-2027');
      expect(f.dateEdition, DateTime(2026, 11, 22));
    });

    test('options : période sans espaces autour, colonnes et affichages', () {
      final f = fiches(
        options: const OptionsFicheNotes(
          periode: '  Novembre ',
          intitules: ['Devoir', 'Compo'],
          avecMatricule: false,
          avecSexe: true,
          avecObservations: false,
        ),
      ).first;
      expect(f.periode, 'Novembre');
      expect(f.intitules, ['Devoir', 'Compo']);
      expect(f.avecMatricule, isFalse);
      expect(f.avecSexe, isTrue);
      expect(f.avecObservations, isFalse);
    });

    test('aucune matière : aucune fiche', () {
      expect(
        construireFichesNotes(
          etablissement: etablissement,
          anneeLibelle: '',
          classeNom: '10e A',
          eleves: eleves,
          matieres: const [],
        ),
        isEmpty,
      );
    });
  });

  group('liste de classe', () {
    test('sans matière ni colonne de notes', () {
      final l = construireListeClasse(
        etablissement: etablissement,
        anneeLibelle: '2026-2027',
        classeNom: '10e A',
        eleves: eleves,
        options: const OptionsFicheNotes(avecSexe: true),
      );
      expect(l.estListe, isTrue);
      expect(l.titre, 'LISTE DE CLASSE');
      expect(l.matiereNom, isNull);
      expect(l.intitules, isEmpty);
      expect(l.avecSexe, isTrue);
      expect(l.lignes, hasLength(3));
    });
  });

  group('fiche d\'une évaluation', () {
    const maths = MatiereClasse(
        id: 1, classeId: 1, nom: 'Maths', coefficient: 100, ordre: 1, enseignantId: 7);
    Evaluation evaluation({String? date, int bareme = 20}) => Evaluation(
          id: 3,
          classeId: 1,
          matiereId: 1,
          mois: 11,
          type: TypeEvaluation.devoir,
          titre: 'Devoir n° 2',
          date: date,
          bareme: bareme,
        );

    test('une colonne au titre de l\'évaluation, son barème et son mois', () {
      final f = construireFicheEvaluation(
        etablissement: etablissement,
        anneeLibelle: '2026-2027',
        classeNom: '10e A',
        eleves: eleves,
        evaluation: evaluation(date: '2026-11-17', bareme: 40),
        matiere: maths,
        enseignant: 'KANTE Moussa',
      );
      expect(f.matiereNom, 'Maths');
      expect(f.enseignant, 'KANTE Moussa');
      expect(f.bareme, 40);
      expect(f.periode, 'Novembre');
      expect(f.evaluation, 'Devoir n° 2 du 17/11/2026');
      expect(f.intitules, ['Devoir n° 2']);
      expect(f.lignes, hasLength(3));
    });

    test('sans date : seulement le titre', () {
      final f = construireFicheEvaluation(
        etablissement: etablissement,
        anneeLibelle: '',
        classeNom: '10e A',
        eleves: eleves,
        evaluation: evaluation(),
        matiere: maths,
      );
      expect(f.evaluation, 'Devoir n° 2');
      expect(f.enseignant, '');
    });
  });
}
