import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_notation.dart';
import 'package:gesco/import_export/liste_vierge.dart';
import 'package:gesco/import_export/modele_export.dart';
import 'package:gesco/tableur/classeur.dart';
import 'package:gesco/tableur/xlsx.dart';

Object? val(FeuilleEcrite f, int ligne, int colonne) {
  if (ligne >= f.lignes.length || colonne >= f.lignes[ligne].length) return null;
  return f.lignes[ligne][colonne]?.valeur;
}

final ctx = ContexteExport(
  etablissement: 'Groupe Scolaire Test',
  annee: '2026-2027',
  date: DateTime(2026, 11, 22),
);

MatiereClasse matiere(int id, String nom, {int bareme = 20, int? enseignantId}) => MatiereClasse(
      id: id,
      classeId: 1,
      nom: nom,
      coefficient: 100,
      ordre: id,
      bareme: bareme,
      enseignantId: enseignantId,
    );

Evaluation evaluation(
  int id, {
  int matiereId = 1,
  int mois = 11,
  String titre = 'Interrogation 1',
  TypeEvaluation type = TypeEvaluation.interrogation,
  String? date,
  int coefficient = 100,
  int bareme = 20,
  bool valide = false,
}) =>
    Evaluation(
      id: id,
      classeId: 1,
      matiereId: matiereId,
      mois: mois,
      type: type,
      titre: titre,
      date: date,
      coefficient: coefficient,
      bareme: bareme,
      valide: valide,
    );

EleveInscrit eleve(int id, String nom, String prenom) => EleveInscrit(
      inscriptionId: id,
      eleveId: id,
      classeId: 1,
      classeNom: '10e A',
      matricule: '2026-000$id',
      nom: nom,
      prenom: prenom,
      sexe: 'M',
    );

const classe = Classe(id: 1, anneeId: 1, niveau: '10e année', nom: '10e A');

void main() {
  const options = OptionsListeVierge(mois: 11);

  group('planifierColonnes', () {
    test('sans évaluation : deux interrogations par défaut, barème de la matière', () {
      final colonnes = planifierColonnes(
        matiere: matiere(1, 'Maths', bareme: 10),
        evaluations: const [],
        options: options,
      );
      expect([for (final c in colonnes) c.titre], ['Interrogation 1', 'Interrogation 2']);
      expect([for (final c in colonnes) c.type],
          [TypeEvaluation.interrogation, TypeEvaluation.interrogation]);
      expect([for (final c in colonnes) c.bareme], [10, 10]);
      expect([for (final c in colonnes) c.mois], [11, 11]);
      expect([for (final c in colonnes) c.evaluationId], [null, null]);
      expect([for (final c in colonnes) c.coefficient], [100, 100]);
    });

    test('interrogations, devoirs et composition selon les choix', () {
      final colonnes = planifierColonnes(
        matiere: matiere(1, 'Maths'),
        evaluations: const [],
        options: const OptionsListeVierge(
          mois: 12,
          nbInterrogations: 1,
          nbDevoirs: 2,
          avecComposition: true,
        ),
      );
      expect([for (final c in colonnes) c.titre],
          ['Interrogation', 'Devoir 1', 'Devoir 2', 'Composition']);
      expect([for (final c in colonnes) c.type], [
        TypeEvaluation.interrogation,
        TypeEvaluation.devoir,
        TypeEvaluation.devoir,
        TypeEvaluation.composition,
      ]);
      expect(colonnes.every((c) => c.mois == 12), isTrue);
    });

    test('rien de demandé : une colonne « Évaluation » au moins', () {
      final colonnes = planifierColonnes(
        matiere: matiere(1, 'Maths'),
        evaluations: const [],
        options: const OptionsListeVierge(mois: 11, nbInterrogations: 0),
      );
      expect([for (final c in colonnes) c.titre], ['Évaluation']);
      expect(colonnes.single.type, TypeEvaluation.evaluation);
    });

    test('nombres limités', () {
      final colonnes = planifierColonnes(
        matiere: matiere(1, 'Maths'),
        evaluations: const [],
        options: const OptionsListeVierge(mois: 11, nbInterrogations: 99, nbDevoirs: 99),
      );
      expect(colonnes.length, interrogationsMax + devoirsMax);
      final negatif = planifierColonnes(
        matiere: matiere(1, 'Maths'),
        evaluations: const [],
        options: const OptionsListeVierge(mois: 11, nbInterrogations: -3, nbDevoirs: 1),
      );
      expect([for (final c in negatif) c.titre], ['Devoir']);
    });

    test('évaluations existantes du mois : elles servent de colonnes, dans l\'ordre des dates', () {
      final colonnes = planifierColonnes(
        matiere: matiere(1, 'Maths'),
        evaluations: [
          evaluation(5, titre: 'Composition', type: TypeEvaluation.composition, date: '2026-11-28', coefficient: 200, bareme: 40),
          evaluation(3, titre: 'Interro A', date: '2026-11-04'),
          evaluation(4, titre: 'Interro B', date: '2026-11-04'),
          evaluation(6, mois: 12, titre: 'Autre mois'),
          evaluation(7, matiereId: 2, titre: 'Autre matière'),
        ],
        options: options,
      );
      expect([for (final c in colonnes) c.titre], ['Interro A', 'Interro B', 'Composition']);
      expect([for (final c in colonnes) c.evaluationId], [3, 4, 5]);
      expect(colonnes.last.coefficient, 200);
      expect(colonnes.last.bareme, 40);
      expect(colonnes.last.type, TypeEvaluation.composition);
    });

    test('une évaluation validée ne reçoit plus de notes : pas de colonne', () {
      final colonnes = planifierColonnes(
        matiere: matiere(1, 'Maths'),
        evaluations: [
          evaluation(3, titre: 'Fermée', valide: true),
          evaluation(4, titre: 'Ouverte'),
        ],
        options: options,
      );
      expect([for (final c in colonnes) c.titre], ['Ouverte']);
    });

    test('toutes validées : aucune colonne (et pas de doublon créé à l\'import)', () {
      final colonnes = planifierColonnes(
        matiere: matiere(1, 'Maths'),
        evaluations: [evaluation(3, valide: true)],
        options: options,
      );
      expect(colonnes, isEmpty);
    });
  });

  group('nomsOngletsUniques', () {
    test('noms valides, tous différents, sans tenir compte des majuscules', () {
      expect(nomsOngletsUniques(['Maths', 'MATHS', 'Maths']), ['Maths', 'MATHS (2)', 'Maths (3)']);
    });

    test('caractères interdits et longueur limitée à 31', () {
      final noms = nomsOngletsUniques(['Sciences/Physiques: TP?', 'A' * 40, 'A' * 40]);
      expect(noms[0], 'Sciences Physiques TP');
      expect(noms[1].length, 31);
      expect(noms[2].length, lessThanOrEqualTo(31));
      expect(noms[2], endsWith(' (2)'));
      expect(noms[1], isNot(noms[2]));
    });

    test('noms réservés', () {
      expect(nomsOngletsUniques(['GESCO', 'Maths'], reserves: {'gesco'}), ['GESCO (2)', 'Maths']);
    });
  });

  group('construireListeVierge', () {
    final liste = ListeVierge(
      classe: classe,
      enseignantId: 7,
      enseignantNom: 'DIALLO Aminata',
      eleves: [eleve(1, 'BARRY', 'Mamadou'), eleve(2, 'CAMARA', 'Fatou'), eleve(3, 'SOW', 'Ibrahima')],
      matieres: [
        MatiereVierge(
          matiere: matiere(1, 'Maths', enseignantId: 7),
          colonnes: const [
            ColonneVierge(
              titre: 'Interrogation 1',
              type: TypeEvaluation.interrogation,
              mois: 11,
              bareme: 20,
            ),
            ColonneVierge(
              titre: 'Composition',
              type: TypeEvaluation.composition,
              mois: 11,
              bareme: 40,
              coefficient: 200,
              evaluationId: 9,
            ),
          ],
        ),
        MatiereVierge(
          matiere: matiere(2, 'Français', enseignantId: 7),
          colonnes: const [
            ColonneVierge(
              titre: 'Dictée',
              type: TypeEvaluation.devoir,
              mois: 11,
              bareme: 10,
            ),
          ],
        ),
      ],
    );

    test('une feuille par matière, puis la feuille GESCO', () {
      final feuilles = construireListeVierge(ctx, liste, mois: 11);
      expect([for (final f in feuilles) f.nom], ['Maths', 'Français', feuilleTechnique]);
    });

    test('en-tête : établissement, année, classe, matière, enseignant, période', () {
      final maths = construireListeVierge(ctx, liste, mois: 11).first;
      expect(val(maths, 0, 0), 'Groupe Scolaire Test');
      expect(val(maths, 1, 0), 'LISTE DE NOTES À REMPLIR');
      expect([val(maths, 2, 0), val(maths, 2, 2)], ['Année scolaire :', '2026-2027']);
      expect([val(maths, 3, 0), val(maths, 3, 2)], ['Classe :', '10e A']);
      expect([val(maths, 4, 0), val(maths, 4, 2)], ['Matière :', 'Maths']);
      expect([val(maths, 5, 0), val(maths, 5, 2)], ['Enseignant :', 'DIALLO Aminata']);
      expect([val(maths, 6, 0), val(maths, 6, 2)], ['Période :', 'Novembre']);
      expect(val(maths, 7, 0), contains('ABS'));
      expect(val(maths, 7, 0), contains('DISP'));
    });

    test('tableau : matricule, nom et prénom, une case jaune par note', () {
      final maths = construireListeVierge(ctx, liste, mois: 11).first;
      expect(maths.lignes.length, premiereLigneEleves + 3);
      expect([for (final c in maths.lignes[ligneEnteteTableau]) c?.valeur], [
        'N°',
        'Matricule',
        'Nom et prénom',
        'Interrogation 1\n(sur 20)',
        'Composition\n(sur 40)',
        'Observations',
      ]);
      final premier = maths.lignes[premiereLigneEleves];
      expect(premier[0]?.valeur, 1);
      expect(premier[colonneMatricule]?.valeur, '2026-0001');
      expect(premier[colonneNom]?.valeur, 'BARRY Mamadou');
      for (var c = premiereColonneNotes; c < premier.length; c++) {
        expect(premier[c]?.valeur, isNull, reason: 'case à remplir par l\'enseignant');
        expect(premier[c]?.style, StyleCellule.saisie);
      }
      expect(maths.lignes[premiereLigneEleves + 2][colonneNom]?.valeur, 'SOW Ibrahima');
      expect(maths.largeurs.length, 6);
    });

    test('sans la colonne Observations', () {
      final maths = construireListeVierge(ctx, liste, mois: 11, avecObservations: false).first;
      expect(maths.lignes[ligneEnteteTableau].length, 5);
      expect(maths.largeurs.length, 5);
    });

    test('enseignant inconnu : case jaune à remplir à la main', () {
      final sans = ListeVierge(
        classe: classe,
        eleves: [eleve(1, 'BARRY', 'Mamadou')],
        matieres: liste.matieres,
      );
      final maths = construireListeVierge(ctx, sans, mois: 11).first;
      expect(maths.lignes[5][2]?.valeur, isNull);
      expect(maths.lignes[5][2]?.style, StyleCellule.saisie);
    });

    test('classe sans élève : l\'en-tête est là, le tableau est vide', () {
      final vide = ListeVierge(classe: classe, eleves: const [], matieres: liste.matieres);
      final maths = construireListeVierge(ctx, vide, mois: 11).first;
      expect(maths.lignes.length, premiereLigneEleves);
    });

    test('noms de matières identiques ou réservés : onglets distincts', () {
      final doublons = ListeVierge(
        classe: classe,
        eleves: [eleve(1, 'BARRY', 'Mamadou')],
        matieres: [
          MatiereVierge(matiere: matiere(1, 'Maths'), colonnes: liste.matieres.first.colonnes),
          MatiereVierge(matiere: matiere(2, 'MATHS'), colonnes: liste.matieres.first.colonnes),
          MatiereVierge(matiere: matiere(3, 'GESCO'), colonnes: liste.matieres.first.colonnes),
        ],
      );
      final noms = [for (final f in construireListeVierge(ctx, doublons, mois: 11)) f.nom];
      expect(noms, ['Maths', 'MATHS (2)', 'GESCO (2)', 'GESCO']);
    });
  });

  group('feuille technique GESCO', () {
    final liste = ListeVierge(
      classe: classe,
      enseignantId: 7,
      enseignantNom: 'DIALLO Aminata',
      eleves: [eleve(1, 'BARRY', 'Mamadou'), eleve(2, 'CAMARA', 'Fatou')],
      matieres: [
        MatiereVierge(
          matiere: matiere(1, 'Maths', enseignantId: 7),
          colonnes: const [
            ColonneVierge(
              titre: 'Interrogation 1',
              type: TypeEvaluation.interrogation,
              mois: 11,
              bareme: 20,
            ),
            ColonneVierge(
              titre: 'Composition',
              type: TypeEvaluation.composition,
              mois: 11,
              bareme: 40,
              coefficient: 200,
              evaluationId: 9,
            ),
          ],
        ),
        MatiereVierge(
          matiere: matiere(2, 'Français', enseignantId: 7),
          colonnes: const [
            ColonneVierge(titre: 'Dictée', type: TypeEvaluation.devoir, mois: 11, bareme: 10),
          ],
        ),
      ],
    );

    test('relue depuis le fichier : format, classe, enseignant, mois', () {
      final lu = lireClasseur(ecrireClasseur(construireListeVierge(ctx, liste, mois: 11)));
      final t = lu.feuille(feuilleTechnique)!;
      expect([t.cellule(1, 0).texte, t.cellule(1, 1).texte, t.cellule(1, 2).nombre],
          ['format', formatListeNotes, versionFormatListeNotes.toDouble()]);
      expect([t.cellule(3, 0).texte, t.cellule(3, 1).nombre, t.cellule(3, 2).texte],
          ['classe_id', 1.0, '10e A']);
      expect([t.cellule(4, 0).texte, t.cellule(4, 1).nombre, t.cellule(4, 2).texte],
          ['enseignant_id', 7.0, 'DIALLO Aminata']);
      expect([t.cellule(5, 0).texte, t.cellule(5, 1).nombre], ['mois', 11.0]);
    });

    test('une ligne par colonne de notes avec tous ses paramètres', () {
      final lu = lireClasseur(ecrireClasseur(construireListeVierge(ctx, liste, mois: 11)));
      final t = lu.feuille(feuilleTechnique)!;
      expect([for (final c in t.lignes[7]) c.texte], [
        'feuille',
        'matiere_id',
        'matiere',
        'colonne',
        'titre',
        'type',
        'mois',
        'bareme',
        'coefficient',
        'evaluation_id',
        'ligne_debut',
        'ligne_fin',
      ]);
      List<Object?> ligne(int l) => [
            t.cellule(l, 0).texte,
            t.cellule(l, 1).nombre,
            t.cellule(l, 2).texte,
            t.cellule(l, 3).nombre,
            t.cellule(l, 4).texte,
            t.cellule(l, 5).texte,
            t.cellule(l, 6).nombre,
            t.cellule(l, 7).nombre,
            t.cellule(l, 8).nombre,
            t.cellule(l, 9).nombre,
            t.cellule(l, 10).nombre,
            t.cellule(l, 11).nombre,
          ];
      expect(ligne(8), ['Maths', 1.0, 'Maths', 4.0, 'Interrogation 1', 'interrogation', 11.0, 20.0, 100.0, 0.0, 11.0, 12.0]);
      expect(ligne(9), ['Maths', 1.0, 'Maths', 5.0, 'Composition', 'composition', 11.0, 40.0, 200.0, 9.0, 11.0, 12.0]);
      expect(ligne(10), ['Français', 2.0, 'Français', 4.0, 'Dictée', 'devoir', 11.0, 10.0, 100.0, 0.0, 11.0, 12.0]);
      expect(t.lignes.length, 11);
    });

    test('cohérente avec les feuilles de matière : titre, colonne et lignes d\'élèves', () {
      final lu = lireClasseur(ecrireClasseur(construireListeVierge(ctx, liste, mois: 11)));
      final t = lu.feuille(feuilleTechnique)!;
      for (var l = 8; l < t.lignes.length; l++) {
        final feuille = lu.feuille(t.cellule(l, 0).texte)!;
        final colonne = t.cellule(l, 3).nombre!.toInt() - 1;
        final titre = t.cellule(l, 4).texte;
        final entete = feuille.cellule(ligneEnteteTableau, colonne).texte;
        expect(entete, startsWith(titre), reason: 'colonne $colonne de ${feuille.nom}');

        // Les lignes ligne_debut..ligne_fin (numéros Excel) sont exactement celles des élèves.
        final debut = t.cellule(l, 10).nombre!.toInt() - 1;
        final fin = t.cellule(l, 11).nombre!.toInt() - 1;
        expect(feuille.cellule(debut, colonneMatricule).texte, '2026-0001');
        expect(feuille.cellule(fin, colonneMatricule).texte, '2026-0002');
        expect(feuille.cellule(debut - 1, colonneMatricule).texte, 'Matricule');
        expect(feuille.cellule(fin + 1, colonneMatricule).vide, isTrue);
      }
    });

    test('les cases à remplir sont vides à la relecture', () {
      final lu = lireClasseur(ecrireClasseur(construireListeVierge(ctx, liste, mois: 11)));
      final maths = lu.feuille('Maths')!;
      expect(maths.cellule(premiereLigneEleves, premiereColonneNotes).vide, isTrue);
      expect(maths.cellule(premiereLigneEleves, premiereColonneNotes + 1).vide, isTrue);
      expect(maths.cellule(premiereLigneEleves, colonneNom).texte, 'BARRY Mamadou');
    });

    test('enseignant inconnu : identifiant 0', () {
      final sans = ListeVierge(classe: classe, eleves: liste.eleves, matieres: liste.matieres);
      final lu = lireClasseur(ecrireClasseur(construireListeVierge(ctx, sans, mois: 11)));
      final t = lu.feuille(feuilleTechnique)!;
      expect(t.cellule(4, 1).nombre, 0.0);
      expect(t.cellule(4, 2).texte, '');
    });
  });
}
