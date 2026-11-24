import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_notation.dart';
import 'package:gesco/domain/modeles.dart' show Saisie;
import 'package:gesco/import_export/import_notes.dart';
import 'package:gesco/import_export/lecture_tableur.dart';
import 'package:gesco/import_export/liste_vierge.dart';
import 'package:gesco/import_export/modele_export.dart';
import 'package:gesco/tableur/classeur.dart';
import 'package:gesco/tableur/xlsx.dart';

Cellule cel(Object? v) => switch (v) {
      null => const Cellule(),
      Cellule c => c,
      String s => Cellule(texte: s),
      int n => Cellule(texte: '$n', nombre: n.toDouble()),
      double d => Cellule(texte: d == d.roundToDouble() ? '${d.toInt()}' : '$d', nombre: d),
      _ => throw ArgumentError('type de cellule non prévu'),
    };

/// Tableau dont la première ligne de données porte le numéro Excel 2.
TableLue tableau(List<String> entetes, List<List<Object?>> lignes) => TableLue(
      nomFeuille: 'Maths',
      ligneEntete: 1,
      entetes: entetes,
      lignes: [
        for (var i = 0; i < lignes.length; i++)
          LigneTable(2 + i, [for (final v in lignes[i]) cel(v)]),
      ],
    );

EleveInscrit eleve(
  int id,
  String matricule,
  String nom,
  String prenom, {
  int classeId = 1,
  String classeNom = '10e A',
  StatutInscription statut = StatutInscription.inscrit,
}) =>
    EleveInscrit(
      inscriptionId: 10 + id,
      eleveId: id,
      classeId: classeId,
      classeNom: classeNom,
      matricule: matricule,
      nom: nom,
      prenom: prenom,
      sexe: 'M',
      statut: statut,
    );

final diallo = eleve(1, '2026-0001', 'DIALLO', 'Mamadou'); // inscription 11
final barry = eleve(2, '2026-0002', 'BARRY', 'Fatoumata'); // 12
final camara = eleve(3, '2026-0003', 'CAMARA', 'Ibrahima'); // 13
final sow = eleve(4, '2026-0004', 'SOW', 'Aissatou', statut: StatutInscription.depart); // 14
final bah = eleve(5, '2026-0005', 'BAH', 'Oumar', classeId: 2, classeNom: '10e B'); // 15

Evaluation evaluation(
  int id, {
  int matiereId = 5,
  int mois = 10,
  String titre = 'Interrogation 1',
  TypeEvaluation type = TypeEvaluation.interrogation,
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
      coefficient: coefficient,
      bareme: bareme,
      valide: valide,
    );

ContexteImportNotes contexte({
  List<Evaluation> evaluations = const [],
  Map<int, Map<int, Saisie>> notes = const {},
  Set<int> verrous = const {},
  bool remplacer = false,
  List<EleveInscrit>? eleves,
  int classeId = 1,
  int matiereId = 5,
  String matiereNom = 'Maths',
  String annee = '2026-2027',
}) =>
    ContexteImportNotes(
      classeId: classeId,
      classeNom: classeId == 1 ? '10e A' : '10e B',
      matiereId: matiereId,
      matiereNom: matiereNom,
      matiereBareme: 20,
      anneeLibelle: annee,
      trimestreLibelle: 'Trimestre 1',
      moisTrimestre: const [10, 11, 12],
      eleves: eleves ?? [diallo, barry, camara, sow, bah],
      evaluations: evaluations,
      notesExistantes: notes,
      moisVerrouilles: verrous,
      remplacerExistantes: remplacer,
    );

CibleColonne nouvelle(String titre, {int mois = 10, int bareme = 20, int? annonce, int coefficient = 100}) =>
    CibleColonne(
      titre: titre,
      type: TypeEvaluation.interrogation,
      mois: mois,
      bareme: bareme,
      coefficient: coefficient,
      baremeAnnonce: annonce,
    );

CibleColonne existante(int id, {int? annonce}) => CibleColonne(
      evaluationId: id,
      titre: 'x',
      mois: 10,
      bareme: 20,
      baremeAnnonce: annonce,
    );

const entetes3 = ['Matricule', 'Nom', 'Note'];

RapportImportNotes analyser(
  List<List<Object?>> lignes, {
  Map<int, CibleColonne>? colonnes,
  MappingNotes? mapping,
  ContexteImportNotes? ctx,
  List<String> entetes = entetes3,
}) =>
    analyserImportNotes(
      table: tableau(entetes, lignes),
      mapping: mapping ??
          MappingNotes(
            colonneMatricule: 0,
            colonneNom: 1,
            colonnes: colonnes ?? {2: nouvelle('Interrogation 1')},
          ),
      ctx: ctx ?? contexte(),
    );

LigneImportNotes ligne(RapportImportNotes r, int numero) =>
    r.lignes.firstWhere((l) => l.numero == numero);

void main() {
  group('colonne à créer', () {
    test('crée l\'évaluation et n\'écrit que les notes remises', () {
      final r = analyser([
        ['2026-0001', 'DIALLO Mamadou', 14.5],
        ['2026-0002', 'BARRY Fatoumata', 'ABS'],
        ['2026-0003', 'CAMARA Ibrahima', null],
      ]);
      expect(r.bloque, isFalse);
      expect(r.lignes, hasLength(3));
      expect(r.plan, hasLength(1));
      final colonne = r.plan.single;
      expect(colonne.creer, isTrue);
      expect(colonne.titre, 'Interrogation 1');
      expect(colonne.mois, 10);
      expect(colonne.bareme, 20);
      expect(colonne.coefficient, 100);
      expect(colonne.notes, {11: const Saisie.valeur(1450), 12: const Saisie.absent()});
      expect(r.nbNotesAEcrire, 2);
      expect(r.nbEvaluationsACreer, 1);
      expect(ligne(r, 4).sansNote, isTrue);
      expect(r.nbLignesSansNote, 1);
      expect(r.colonnes.single.nbNouvelles, 2);
      expect(r.colonnes.single.nbVides, 1);
      expect(r.colonnes.single.nbSansNote, 1);
      expect(r.remarquesFichier.any((t) => t.contains('sera créée')), isTrue);
      expect(r.peutImporter(ignorerErreurs: false), isTrue);
    });

    test('une colonne sans aucune note valide ne crée pas d\'évaluation', () {
      final r = analyser([
        ['2026-0001', 'DIALLO Mamadou', null],
        ['2026-0002', 'BARRY Fatoumata', null],
      ]);
      expect(r.plan, isEmpty);
      expect(r.nbNotesAEcrire, 0);
      expect(r.remarquesFichier.any((t) => t.contains('ne sera pas créée')), isTrue);
      expect(r.peutImporter(ignorerErreurs: true), isFalse);
    });

    test('titre, mois, barème et coefficient de la colonne sont repris', () {
      final r = analyser(
        [
          ['2026-0001', 'DIALLO Mamadou', 7.5],
        ],
        colonnes: {2: nouvelle('Devoir 1', mois: 11, bareme: 10, coefficient: 150)},
      );
      final c = r.plan.single;
      expect(c.mois, 11);
      expect(c.bareme, 10);
      expect(c.coefficient, 150);
      expect(c.notes, {11: const Saisie.surBareme(750, 10)});
      expect(r.remarquesFichier.any((t) => t.contains('coefficient 1,5')), isTrue);
    });

    test('même titre et même mois qu\'une évaluation existante : elle est reprise', () {
      final r = analyser(
        [
          ['2026-0001', 'DIALLO Mamadou', 7],
          ['2026-0002', 'BARRY Fatoumata', 12],
        ],
        colonnes: {2: nouvelle('interrogation 1')},
        ctx: contexte(evaluations: [evaluation(100, bareme: 10, coefficient: 200)]),
      );
      expect(r.bloque, isFalse);
      final c = r.plan.single;
      expect(c.creer, isFalse);
      expect(c.evaluationId, 100);
      // Le barème et le coefficient de GESCO l'emportent sur ceux du fichier.
      expect(c.bareme, 10);
      expect(c.coefficient, 200);
      expect(r.colonnes.single.reprise, isTrue);
      expect(r.nbEvaluationsACreer, 0);
      expect(r.remarquesFichier.any((t) => t.contains('aucune évaluation en double')), isTrue);
      expect(c.notes, {11: const Saisie.surBareme(700, 10)});
      // 12 sur 10 est hors barème : lu sur le barème de l'évaluation existante.
      expect(r.nbLignesErreur, 1);
      expect(ligne(r, 3).erreurs.single, contains('dépasse 10'));
    });
  });

  group('évaluation existante et notes déjà enregistrées', () {
    final notesExistantes = {
      100: {11: const Saisie.valeur(1450), 12: const Saisie.valeur(1000)},
    };
    final lignes = [
      ['2026-0001', 'DIALLO Mamadou', '14,5'],
      ['2026-0002', 'BARRY Fatoumata', '15'],
      ['2026-0003', 'CAMARA Ibrahima', '9'],
    ];

    test('une note différente n\'écrase jamais l\'ancienne par défaut', () {
      final r = analyser(
        lignes,
        colonnes: {2: existante(100)},
        ctx: contexte(evaluations: [evaluation(100)], notes: notesExistantes),
      );
      expect(r.bloque, isFalse);
      expect(r.plan.single.evaluationId, 100);
      expect(r.plan.single.notes, {13: const Saisie.valeur(900)});
      expect(r.nbIdentiques, 1);
      expect(r.nbConservees, 1);
      expect(r.nbNotesRemplacees, 0);
      expect(ligne(r, 3).cases[2]!.etat, EtatCaseNote.conflit);
      expect(ligne(r, 3).avertissements.single, contains('conservée'));
      expect(ligne(r, 3).enErreur, isFalse);
    });

    test('avec « remplacer », la note différente est remplacée', () {
      final r = analyser(
        lignes,
        colonnes: {2: existante(100)},
        ctx: contexte(
          evaluations: [evaluation(100)],
          notes: notesExistantes,
          remplacer: true,
        ),
      );
      expect(r.plan.single.notes, {12: const Saisie.valeur(1500), 13: const Saisie.valeur(900)});
      expect(r.nbNotesRemplacees, 1);
      expect(r.nbConservees, 0);
      expect(ligne(r, 3).cases[2]!.etat, EtatCaseNote.remplacee);
      expect(ligne(r, 3).avertissements.single, contains('remplacée'));
      expect(r.colonnes.single.nbRemplacees, 1);
      expect(r.colonnes.single.nbNouvelles, 1);
    });

    test('un fichier déjà importé ne donne rien à écrire', () {
      final r = analyser(
        [
          ['2026-0001', 'DIALLO Mamadou', 14.5],
          ['2026-0002', 'BARRY Fatoumata', 10],
        ],
        colonnes: {2: existante(100)},
        ctx: contexte(evaluations: [evaluation(100)], notes: notesExistantes),
      );
      expect(r.nbNotesAEcrire, 0);
      expect(r.nbIdentiques, 2);
      expect(r.peutImporter(ignorerErreurs: true), isFalse);
    });

    test('une case vide n\'efface jamais une note existante', () {
      final r = analyser(
        [
          ['2026-0001', 'DIALLO Mamadou', null],
        ],
        colonnes: {2: existante(100)},
        ctx: contexte(evaluations: [evaluation(100)], notes: notesExistantes, remplacer: true),
      );
      expect(r.plan, isEmpty);
      expect(ligne(r, 2).cases[2]!.etat, EtatCaseNote.vide);
      expect(ligne(r, 2).cases[2]!.ancienne, const Saisie.valeur(1450));
    });

    test('le nombre d\'élèves sans note tient compte des notes existantes', () {
      final r = analyser(
        [
          ['2026-0003', 'CAMARA Ibrahima', 8],
        ],
        colonnes: {2: existante(100)},
        ctx: contexte(evaluations: [evaluation(100)], notes: notesExistantes),
      );
      // Trois élèves actifs : 11 et 12 ont déjà une note, 13 va en recevoir une.
      expect(r.colonnes.single.nbSansNote, 0);
    });

    test('une note existante absente ou dispensée est comparée comme les autres', () {
      final r = analyser(
        [
          ['2026-0001', 'DIALLO Mamadou', 'abs'],
          ['2026-0002', 'BARRY Fatoumata', 'D'],
        ],
        colonnes: {2: existante(100)},
        ctx: contexte(
          evaluations: [evaluation(100)],
          notes: {
            100: {11: const Saisie.absent(), 12: const Saisie.absent()},
          },
        ),
      );
      expect(ligne(r, 2).cases[2]!.etat, EtatCaseNote.identique);
      expect(ligne(r, 3).cases[2]!.etat, EtatCaseNote.conflit);
    });

    test('un barème différent est lu sur le barème de l\'évaluation', () {
      final r = analyser(
        [
          ['2026-0001', 'DIALLO Mamadou', '7,5'],
          ['2026-0002', 'BARRY Fatoumata', 12],
        ],
        colonnes: {2: existante(101)},
        ctx: contexte(evaluations: [evaluation(101, bareme: 10)]),
      );
      expect(ligne(r, 2).cases[2]!.saisie, const Saisie.surBareme(750, 10));
      expect(ligne(r, 3).enErreur, isTrue);
      expect(ligne(r, 3).erreurs.single, contains('dépasse 10'));
    });
  });

  group('validité des notes', () {
    test('hors barème, texte, trop de décimales, formule et date sont refusés', () {
      final r = analyser([
        ['2026-0001', 'DIALLO Mamadou', 25],
        ['2026-0002', 'BARRY Fatoumata', 'bien'],
        ['2026-0003', 'CAMARA Ibrahima', 14.123],
      ]);
      expect(r.nbLignesErreur, 3);
      expect(ligne(r, 2).erreurs.single, contains('dépasse 20'));
      expect(ligne(r, 3).erreurs.single, contains('n\'est pas une note valide'));
      expect(ligne(r, 4).erreurs.single, contains('trop de décimales'));
      expect(r.plan, isEmpty);
      expect(r.colonnes.single.nbErreurs, 3);

      final r2 = analyser([
        ['2026-0001', 'DIALLO Mamadou', const Cellule(texte: '=B2+1', formule: true)],
        [
          '2026-0002',
          'BARRY Fatoumata',
          Cellule(texte: '2026-01-02', date: DateTime(2026, 1, 2)),
        ],
        ['2026-0003', 'CAMARA Ibrahima', -3],
      ]);
      expect(ligne(r2, 2).erreurs.single, contains('formule'));
      expect(ligne(r2, 3).erreurs.single, contains('est une date'));
      expect(ligne(r2, 4).enErreur, isTrue);
    });

    test('virgule, point, ABS, DISP et arrondi de calcul sont acceptés', () {
      final r = analyser([
        ['2026-0001', 'DIALLO Mamadou', '14,25'],
        ['2026-0002', 'BARRY Fatoumata', '9.5'],
        ['2026-0003', 'CAMARA Ibrahima', 1.1 * 3],
      ]);
      expect(r.plan.single.notes, {
        11: const Saisie.valeur(1425),
        12: const Saisie.valeur(950),
        13: const Saisie.valeur(330),
      });
      final r2 = analyser([
        ['2026-0001', 'DIALLO Mamadou', 'Absent'],
        ['2026-0002', 'BARRY Fatoumata', 'disp'],
        ['2026-0003', 'CAMARA Ibrahima', 0],
      ]);
      expect(r2.plan.single.notes, {
        11: const Saisie.absent(),
        12: const Saisie.dispense(),
        13: const Saisie.valeur(0),
      });
    });

    test('une ligne en erreur n\'est jamais importée à moitié', () {
      final r = analyser(
        [
          ['2026-0001', 'DIALLO Mamadou', 25, 12],
          ['2026-0002', 'BARRY Fatoumata', 12, 13],
        ],
        entetes: const ['Matricule', 'Nom', 'Interro 1', 'Interro 2'],
        colonnes: {2: nouvelle('Interro 1'), 3: nouvelle('Interro 2')},
      );
      expect(r.nbLignesErreur, 1);
      expect(r.plan[0].notes.keys, [12]);
      expect(r.plan[1].notes.keys, [12]);
      expect(r.peutImporter(ignorerErreurs: false), isFalse);
      expect(r.peutImporter(ignorerErreurs: true), isTrue);
      expect(r.nbNotesAEcrire, 2);
    });
  });

  group('reconnaissance des élèves', () {
    test('matricule inconnu, autre classe, élève parti, nom différent', () {
      final r = analyser([
        ['2026-0999', 'DIALLO Mamadou', 10],
        ['2026-0005', 'BAH Oumar', 10],
        ['2026-0004', 'SOW Aissatou', 10],
        ['2026-0001', 'FALL Awa', 10],
        ['2026-0002', 'Fatoumata BARRY', 10],
      ]);
      expect(ligne(r, 2).erreurs.single, contains('inconnu'));
      expect(ligne(r, 2).erreurs.single, contains('DIALLO Mamadou'));
      expect(ligne(r, 2).erreurs.single, contains('2026-0001'));
      expect(ligne(r, 3).erreurs.single, contains('10e B'));
      expect(ligne(r, 4).erreurs.single, contains('a quitté la classe'));
      expect(ligne(r, 5).erreurs.single, contains('vérifiez la ligne'));
      expect(ligne(r, 6).enErreur, isFalse);
      expect(r.plan.single.notes.keys, [12]);
    });

    test('matricule avec espaces et majuscules : reconnu', () {
      final r = analyser([
        ['  2026-0001 ', 'diallo mamadou', 10],
      ]);
      expect(ligne(r, 2).eleve?.inscriptionId, 11);
      expect(r.nbLignesErreur, 0);
    });

    test('sans colonne matricule : reconnus par le nom, dans n\'importe quel ordre', () {
      final r = analyser(
        [
          ['DIALLO Mamadou', 12],
          ['ibrahima camara', 11],
          ['INCONNU Paul', 10],
        ],
        entetes: const ['Nom et prénom', 'Note'],
        mapping: MappingNotes(colonneNom: 0, colonnes: {1: nouvelle('Interrogation 1')}),
      );
      expect(r.plan.single.notes.keys, [11, 13]);
      expect(ligne(r, 4).erreurs.single, contains('Aucun élève'));
      expect(r.remarquesFichier.any((t) => t.contains('pas de colonne matricule')), isTrue);
      // Pas une remarque par ligne quand le fichier n'a pas de matricule.
      expect(ligne(r, 2).avertissements, isEmpty);
    });

    test('nom et prénom dans deux colonnes', () {
      final r = analyser(
        [
          ['DIALLO', 'Mamadou', 12],
        ],
        entetes: const ['Nom', 'Prénom', 'Note'],
        mapping: MappingNotes(
          colonneNom: 0,
          colonnePrenom: 1,
          colonnes: {2: nouvelle('Interrogation 1')},
        ),
      );
      expect(ligne(r, 2).eleve?.inscriptionId, 11);
    });

    test('matricule vide : reconnu par le nom, avec une remarque', () {
      final r = analyser([
        ['', 'BARRY Fatoumata', 13],
      ]);
      expect(ligne(r, 2).eleve?.inscriptionId, 12);
      expect(ligne(r, 2).enErreur, isFalse);
      expect(ligne(r, 2).avertissements.single, contains('reconnu par son nom'));
    });

    test('deux élèves de même nom sans matricule : refusé', () {
      final r = analyser(
        [
          ['', 'DIALLO Mamadou', 13],
        ],
        ctx: contexte(eleves: [diallo, eleve(7, '2026-0007', 'DIALLO', 'Mamadou')]),
      );
      expect(ligne(r, 2).erreurs.single, contains('Plusieurs élèves'));
    });

    test('ligne sans note et élève inconnu : simple remarque', () {
      final r = analyser([
        ['2026-0999', 'ZZZ Test', null],
        ['2026-0001', 'DIALLO Mamadou', 12],
      ]);
      expect(ligne(r, 2).enErreur, isFalse);
      expect(ligne(r, 2).avertissements.single, contains('ignorée'));
      expect(r.nbLignesErreur, 0);
      expect(r.plan.single.notes.keys, [11]);
    });

    test('notes sans identité : refusé', () {
      final r = analyser([
        ['', '', 12],
      ]);
      expect(ligne(r, 2).erreurs.single, contains('ni matricule ni nom'));
    });

    test('un élève sur deux lignes : les deux lignes sont refusées', () {
      final r = analyser([
        ['2026-0001', 'DIALLO Mamadou', 12],
        ['2026-0002', 'BARRY Fatoumata', 13],
        ['2026-0001', 'DIALLO Mamadou', 14],
      ]);
      expect(ligne(r, 2).erreurs.single, contains('plusieurs lignes (2, 4)'));
      expect(ligne(r, 4).erreurs.single, contains('plusieurs lignes (2, 4)'));
      expect(ligne(r, 3).enErreur, isFalse);
      expect(r.plan.single.notes.keys, [12]);
    });

    test('lignes vides ignorées ; élèves absents du fichier signalés', () {
      final r = analyser([
        ['2026-0001', 'DIALLO Mamadou', 12],
        [null, null, null],
        [null, null, null],
      ]);
      expect(r.nbLignesVides, 2);
      expect(r.lignes, hasLength(1));
      expect([for (final e in r.absentsDuFichier) e.inscriptionId], [12, 13]);
      expect(r.remarquesFichier.any((t) => t.contains('ne figurent pas dans le fichier')), isTrue);
    });

    test('matricule ou nom écrit par une formule : refusé', () {
      final r = analyser([
        [const Cellule(texte: '=A1', formule: true), 'DIALLO Mamadou', 12],
      ]);
      expect(ligne(r, 2).erreurs.single, contains('formule'));
    });
  });

  group('problèmes qui bloquent tout', () {
    List<String> problemes(
      Map<int, CibleColonne> colonnes, {
      ContexteImportNotes? ctx,
      List<List<Object?>>? lignes,
      MappingNotes? mapping,
      List<String> entetes = entetes3,
    }) {
      final r = analyser(
        lignes ??
            [
              ['2026-0001', 'DIALLO Mamadou', 12],
            ],
        entetes: entetes,
        colonnes: colonnes,
        mapping: mapping,
        ctx: ctx,
      );
      expect(r.bloque, isTrue);
      expect(r.lignes, isEmpty);
      expect(r.peutImporter(ignorerErreurs: true), isFalse);
      return r.problemesFichier;
    }

    test('évaluation validée', () {
      final p = problemes(
        {2: existante(100)},
        ctx: contexte(evaluations: [evaluation(100, valide: true)]),
      );
      expect(p.single, contains('est validée'));
    });

    test('mois verrouillé (évaluation existante et colonne à créer)', () {
      final p1 = problemes(
        {2: existante(100)},
        ctx: contexte(evaluations: [evaluation(100)], verrous: {10}),
      );
      expect(p1.single, contains('Octobre est verrouillé'));
      final p2 = problemes({2: nouvelle('Devoir 1', mois: 11)}, ctx: contexte(verrous: {11}));
      expect(p2.single, contains('Novembre est verrouillé'));
    });

    test('mois hors de la période choisie', () {
      final p1 = problemes(
        {2: existante(100)},
        ctx: contexte(evaluations: [evaluation(100, mois: 2)]),
      );
      expect(p1.single, contains('hors de Trimestre 1'));
      final p2 = problemes({2: nouvelle('Devoir 1', mois: 2)});
      expect(p2.single, contains('doit être un mois de Trimestre 1'));
    });

    test('évaluation d\'une autre matière ou inexistante', () {
      final p = problemes(
        {2: existante(200)},
        ctx: contexte(evaluations: [evaluation(200, matiereId: 6)]),
      );
      expect(p.single, contains('n\'existe pas pour la matière Maths'));
    });

    test('barème annoncé par le fichier différent de celui de l\'évaluation', () {
      final p = problemes(
        {2: existante(101, annonce: 20)},
        ctx: contexte(evaluations: [evaluation(101, bareme: 10)]),
      );
      expect(p.single, contains('notée sur 20 dans le fichier'));
      expect(p.single, contains('sur 10'));
    });

    test('deux colonnes pour la même évaluation', () {
      final p1 = problemes(
        {2: existante(100), 3: existante(100)},
        ctx: contexte(evaluations: [evaluation(100)]),
        entetes: const ['Matricule', 'Nom', 'A', 'B'],
        lignes: [
          ['2026-0001', 'DIALLO Mamadou', 12, 13],
        ],
      );
      expect(p1.single, contains('visent la même évaluation'));
      final p2 = problemes(
        {2: nouvelle('Devoir 1'), 3: nouvelle('devoir 1')},
        entetes: const ['Matricule', 'Nom', 'A', 'B'],
        lignes: [
          ['2026-0001', 'DIALLO Mamadou', 12, 13],
        ],
      );
      expect(p2.single, contains('visent la même évaluation'));
      // Même titre mais mois différents : deux évaluations distinctes.
      final r = analyser(
        [
          ['2026-0001', 'DIALLO Mamadou', 12, 13],
        ],
        entetes: const ['Matricule', 'Nom', 'A', 'B'],
        colonnes: {2: nouvelle('Devoir 1'), 3: nouvelle('Devoir 1', mois: 11)},
      );
      expect(r.bloque, isFalse);
      expect(r.nbEvaluationsACreer, 2);
    });

    test('colonne d\'identité utilisée pour des notes, aucune colonne de notes', () {
      final p1 = problemes({0: nouvelle('Devoir 1')});
      expect(p1.any((t) => t.contains('sert à reconnaître les élèves')), isTrue);
      final p2 = problemes(const {});
      expect(p2.single, contains('Aucune colonne de notes'));
    });

    test('aucune colonne d\'identité', () {
      final p = problemes(
        const {},
        mapping: MappingNotes(colonnes: {2: nouvelle('Devoir 1')}),
      );
      expect(p.single, contains('reconnaître les élèves'));
    });

    test('tableau vide', () {
      final p = problemes({2: nouvelle('Devoir 1')}, lignes: const []);
      expect(p.single, contains('aucune ligne'));
    });

    test('titre vide, trop long, barème ou coefficient invalides', () {
      expect(problemes({2: nouvelle('  ')}).single, contains('pas de titre'));
      expect(problemes({2: nouvelle('x' * 81)}).single, contains('trop long'));
      expect(problemes({2: nouvelle('Devoir 1', bareme: 0)}).single, contains('barème'));
      expect(
        problemes({2: nouvelle('Devoir 1', coefficient: 0)}).single,
        contains('coefficient'),
      );
    });
  });

  group('fichier GESCO (liste vierge remplie)', () {
    final contexteExport = ContexteExport(
      etablissement: 'Groupe Scolaire Test',
      annee: '2026-2027',
      date: DateTime(2026, 11, 22),
    );
    const classe = Classe(id: 1, anneeId: 1, niveau: '10e année', nom: '10e A');
    const maths = MatiereClasse(id: 5, classeId: 1, nom: 'Maths', coefficient: 100, ordre: 1);
    const francais = MatiereClasse(id: 6, classeId: 1, nom: 'Français', coefficient: 100, ordre: 2);

    /// Classeur de la liste Maths (une évaluation existante et une à créer) et
    /// Français, rempli comme le ferait un enseignant.
    ClasseurLu classeurRempli({void Function(List<FeuilleEcrite>)? modifier}) {
      final liste = ListeVierge(
        classe: classe,
        matieres: [
          MatiereVierge(matiere: maths, colonnes: [
            const ColonneVierge(
              titre: 'Interrogation 1',
              type: TypeEvaluation.interrogation,
              mois: 10,
              bareme: 20,
              evaluationId: 100,
            ),
            const ColonneVierge(
              titre: 'Interrogation 2',
              type: TypeEvaluation.interrogation,
              mois: 10,
              bareme: 20,
            ),
          ]),
          MatiereVierge(matiere: francais, colonnes: [
            const ColonneVierge(
              titre: 'Devoir 1',
              type: TypeEvaluation.devoir,
              mois: 10,
              bareme: 20,
            ),
          ]),
        ],
        eleves: [diallo, barry, camara],
        enseignantId: 7,
        enseignantNom: 'M. Bah',
      );
      final feuilles = construireListeVierge(contexteExport, liste, mois: 10);
      void poser(int k, int i, int c, Object? v) {
        feuilles[k].lignes[premiereLigneEleves + i][premiereColonneNotes + c] =
            CelluleEcrite(v, StyleCellule.note);
      }

      poser(0, 0, 0, 14.5);
      poser(0, 0, 1, 'ABS');
      poser(0, 1, 0, 12);
      poser(0, 1, 1, 9.25);
      poser(1, 0, 0, 16);
      modifier?.call(feuilles);
      return lireClasseur(ecrireClasseur(feuilles));
    }

    test('la feuille technique est lue', () {
      final liste = lireFeuilleTechnique(classeurRempli());
      expect(liste, isNotNull);
      expect(liste!.versionSupportee, isTrue);
      expect(liste.classeId, 1);
      expect(liste.classeNom, '10e A');
      expect(liste.annee, '2026-2027');
      expect(liste.mois, 10);
      expect(liste.colonnes, hasLength(3));
      final c = liste.colonnes.first;
      expect(c.matiereId, 5);
      expect(c.titre, 'Interrogation 1');
      expect(c.evaluationId, 100);
      expect(c.colonne, premiereColonneNotes + 1);
      expect(c.ligneDebut, premiereLigneEleves + 1);
      expect(c.ligneFin, premiereLigneEleves + 3);
      expect(liste.colonnes[1].evaluationId, 0);
      expect(liste.colonnes[2].matiereId, 6);
    });

    test('un classeur sans feuille GESCO n\'est pas une liste GESCO', () {
      final classeur = lireClasseur(ecrireClasseur([
        FeuilleEcrite('Notes', [
          [const CelluleEcrite('Nom')],
        ]),
      ]));
      expect(lireFeuilleTechnique(classeur), isNull);
    });

    test('round trip : liste vierge remplie -> association -> vérification', () {
      final classeur = classeurRempli();
      final ctx = contexte(evaluations: [evaluation(100)]);
      final proposition = proposerDepuisListeGesco(
        classeur: classeur,
        liste: lireFeuilleTechnique(classeur)!,
        ctx: ctx,
      );
      expect(proposition.problemes, isEmpty);
      expect(proposition.utilisable, isTrue);
      final mapping = proposition.mapping!;
      expect(mapping.colonneMatricule, colonneMatricule);
      expect(mapping.colonneNom, colonneNom);
      expect(mapping.colonnes.keys, [premiereColonneNotes, premiereColonneNotes + 1]);
      expect(mapping.colonnes[premiereColonneNotes]!.evaluationId, 100);
      expect(mapping.colonnes[premiereColonneNotes + 1]!.nouvelle, isTrue);
      expect(proposition.table!.lignes, hasLength(3));

      final r = analyserImportNotes(table: proposition.table!, mapping: mapping, ctx: ctx);
      expect(r.problemesFichier, isEmpty);
      expect(r.nbLignesErreur, 0);
      expect(r.plan, hasLength(2));
      expect(r.plan[0].evaluationId, 100);
      expect(r.plan[0].notes, {11: const Saisie.valeur(1450), 12: const Saisie.valeur(1200)});
      expect(r.plan[1].creer, isTrue);
      expect(r.plan[1].titre, 'Interrogation 2');
      expect(r.plan[1].notes, {11: const Saisie.absent(), 12: const Saisie.valeur(925)});
      expect(r.nbNotesAEcrire, 4);
      expect(r.nbEvaluationsACreer, 1);
      // L'élève sans aucune note remise n'est pas une erreur.
      expect(r.nbLignesSansNote, 1);
    });

    test('la matière choisie décide de la feuille lue', () {
      final classeur = classeurRempli();
      final proposition = proposerDepuisListeGesco(
        classeur: classeur,
        liste: lireFeuilleTechnique(classeur)!,
        ctx: contexte(matiereId: 6, matiereNom: 'Français'),
      );
      expect(proposition.utilisable, isTrue);
      expect(proposition.table!.nomFeuille, 'Français');
      final r = analyserImportNotes(
        table: proposition.table!,
        mapping: proposition.mapping!,
        ctx: contexte(matiereId: 6, matiereNom: 'Français'),
      );
      expect(r.plan.single.titre, 'Devoir 1');
      expect(r.plan.single.notes, {11: const Saisie.valeur(1600)});
    });

    test('réimporter le même fichier ne crée rien de plus', () {
      final classeur = classeurRempli();
      final liste = lireFeuilleTechnique(classeur)!;
      // Après un premier import : l'évaluation 101 a été créée avec ses notes.
      final ctx = contexte(
        evaluations: [evaluation(100), evaluation(101, titre: 'Interrogation 2')],
        notes: {
          100: {11: const Saisie.valeur(1450), 12: const Saisie.valeur(1200)},
          101: {11: const Saisie.absent(), 12: const Saisie.valeur(925)},
        },
      );
      final proposition = proposerDepuisListeGesco(classeur: classeur, liste: liste, ctx: ctx);
      final r = analyserImportNotes(
        table: proposition.table!,
        mapping: proposition.mapping!,
        ctx: ctx,
      );
      expect(r.problemesFichier, isEmpty);
      expect(r.nbNotesAEcrire, 0);
      expect(r.nbEvaluationsACreer, 0);
      expect(r.nbIdentiques, 4);
      expect(r.colonnes[1].reprise, isTrue);
    });

    test('autre classe, autre année, autre matière : refusé avec explication', () {
      final classeur = classeurRempli();
      final liste = lireFeuilleTechnique(classeur)!;
      final autreClasse = proposerDepuisListeGesco(
        classeur: classeur,
        liste: liste,
        ctx: contexte(classeId: 2),
      );
      expect(autreClasse.utilisable, isFalse);
      expect(autreClasse.problemes.first, contains('liste de la classe « 10e A »'));

      final autreAnnee = proposerDepuisListeGesco(
        classeur: classeur,
        liste: liste,
        ctx: contexte(annee: '2025-2026'),
      );
      expect(autreAnnee.problemes.single, contains('année scolaire 2026-2027'));

      final autreMatiere = proposerDepuisListeGesco(
        classeur: classeur,
        liste: liste,
        ctx: contexte(matiereId: 9, matiereNom: 'Chimie'),
      );
      expect(autreMatiere.problemes.single, contains('aucune colonne pour la matière Chimie'));
      expect(autreMatiere.problemes.single, contains('Maths'));
    });

    test('colonne insérée par l\'enseignant : refusé plutôt que de décaler les notes', () {
      final classeur = classeurRempli(modifier: (feuilles) {
        for (final ligne in feuilles[0].lignes.skip(premiereLigneEleves - 1)) {
          ligne.insert(premiereColonneNotes, null);
        }
      });
      final proposition = proposerDepuisListeGesco(
        classeur: classeur,
        liste: lireFeuilleTechnique(classeur)!,
        ctx: contexte(evaluations: [evaluation(100)]),
      );
      expect(proposition.utilisable, isFalse);
      expect(proposition.problemes.single, contains('n\'est plus à sa place'));
    });

    test('ligne de titres déplacée : refusé', () {
      final classeur = classeurRempli(modifier: (feuilles) {
        feuilles[0].lignes.insert(3, <CelluleEcrite?>[]);
      });
      final proposition = proposerDepuisListeGesco(
        classeur: classeur,
        liste: lireFeuilleTechnique(classeur)!,
        ctx: contexte(evaluations: [evaluation(100)]),
      );
      expect(proposition.utilisable, isFalse);
      expect(proposition.problemes.single, contains('a été modifié'));
    });

    test('barème de l\'évaluation changé depuis la liste : refusé à la vérification', () {
      final classeur = classeurRempli();
      final ctx = contexte(evaluations: [evaluation(100, bareme: 10)]);
      final proposition = proposerDepuisListeGesco(
        classeur: classeur,
        liste: lireFeuilleTechnique(classeur)!,
        ctx: ctx,
      );
      final r = analyserImportNotes(
        table: proposition.table!,
        mapping: proposition.mapping!,
        ctx: ctx,
      );
      expect(r.bloque, isTrue);
      expect(r.problemesFichier.single, contains('notée sur 20 dans le fichier'));
    });
  });

  group('association automatique d\'un autre fichier', () {
    const entetes = [
      'N°',
      'Matricule',
      'Nom et prénom',
      'Interrogation 1 (sur 20)',
      'Devoir 1 (sur 10)',
      'Moyenne',
      'Observations',
      'Sexe',
    ];
    final lignes = [
      [1, '2026-0001', 'DIALLO Mamadou', 14.5, 'ABS', 12.0, 'Bien', 'M'],
      [2, '2026-0002', 'BARRY Fatoumata', 12, 7, 9.5, '', 'F'],
      [3, '2026-0003', 'CAMARA Ibrahima', 9, '', 9.0, 'Passable', 'M'],
    ];

    test('reconnaît matricule, nom et colonnes de notes ; ignore le reste', () {
      final m = proposerAssociationNotes(
        table: tableau(entetes, lignes),
        ctx: contexte(),
        moisParDefaut: 11,
      );
      expect(m.colonneMatricule, 1);
      expect(m.colonneNom, 2);
      expect(m.colonnePrenom, isNull);
      expect(m.colonnes.keys, [3, 4]);
      final c3 = m.colonnes[3]!;
      expect(c3.nouvelle, isTrue);
      expect(c3.titre, 'Interrogation 1');
      expect(c3.type, TypeEvaluation.interrogation);
      expect(c3.mois, 11);
      expect(c3.bareme, 20);
      expect(c3.baremeAnnonce, 20);
      final c4 = m.colonnes[4]!;
      expect(c4.titre, 'Devoir 1');
      expect(c4.type, TypeEvaluation.devoir);
      expect(c4.bareme, 10);
      expect(c4.baremeAnnonce, 10);
    });

    test('reprend l\'évaluation existante de même titre dans la période', () {
      final m = proposerAssociationNotes(
        table: tableau(entetes, lignes),
        ctx: contexte(evaluations: [
          evaluation(100, titre: 'Devoir 1', mois: 12, bareme: 10, type: TypeEvaluation.devoir),
          evaluation(101, titre: 'Devoir 1', mois: 11, bareme: 10, type: TypeEvaluation.devoir),
          evaluation(102, titre: 'Devoir 1', mois: 3, bareme: 10),
          evaluation(103, titre: 'Interrogation 1', matiereId: 6),
        ]),
        moisParDefaut: 11,
      );
      // Le mois par défaut départage ; le mois hors période et l'autre matière
      // sont ignorés.
      expect(m.colonnes[4]!.evaluationId, 101);
      expect(m.colonnes[3]!.nouvelle, isTrue);
    });

    test('nom et prénom dans deux colonnes ; en-têtes sans accent ni majuscule', () {
      final m = proposerAssociationNotes(
        table: tableau(
          const ['NOM', 'prenom', 'MATRICULE', 'Note'],
          [
            ['DIALLO', 'Mamadou', '2026-0001', 12],
            ['BARRY', 'Fatoumata', '2026-0002', 14],
          ],
        ),
        ctx: contexte(),
        moisParDefaut: 10,
      );
      expect(m.colonneNom, 0);
      expect(m.colonnePrenom, 1);
      expect(m.colonneMatricule, 2);
      expect(m.colonnes.keys, [3]);
      expect(m.colonnes[3]!.titre, 'Note');
      expect(m.colonnes[3]!.bareme, 20);
      expect(m.colonnes[3]!.baremeAnnonce, isNull);
    });

    test('une colonne de texte n\'est pas une colonne de notes', () {
      final m = proposerAssociationNotes(
        table: tableau(
          const ['Matricule', 'Nom', 'Commentaire libre', 'Devoir'],
          [
            ['2026-0001', 'DIALLO Mamadou', 'très bien', 12],
            ['2026-0002', 'BARRY Fatoumata', 'à revoir', 14],
          ],
        ),
        ctx: contexte(),
        moisParDefaut: 10,
      );
      expect(m.colonnes.keys, [3]);
    });

    test('la proposition se vérifie ensuite comme toute association', () {
      final table = tableau(entetes, lignes);
      final ctx = contexte();
      final r = analyserImportNotes(
        table: table,
        mapping: proposerAssociationNotes(table: table, ctx: ctx, moisParDefaut: 11),
        ctx: ctx,
      );
      expect(r.problemesFichier, isEmpty);
      expect(r.plan, hasLength(2));
      expect(r.plan[0].notes, {
        11: const Saisie.valeur(1450),
        12: const Saisie.valeur(1200),
        13: const Saisie.valeur(900),
      });
      expect(r.plan[1].bareme, 10);
      expect(r.plan[1].notes, {11: const Saisie.absent(), 12: const Saisie.surBareme(700, 10)});
    });
  });

  group('petites fonctions', () {
    test('separerBaremeDuTitre', () {
      expect(separerBaremeDuTitre('Devoir 1\n(sur 20)'), (titre: 'Devoir 1', bareme: 20));
      expect(separerBaremeDuTitre('Interro 2 /10'), (titre: 'Interro 2', bareme: 10));
      expect(separerBaremeDuTitre('Devoir 3 (sur 40)'), (titre: 'Devoir 3', bareme: 40));
      expect(separerBaremeDuTitre('Composition'), (titre: 'Composition', bareme: null));
      expect(separerBaremeDuTitre('  Devoir  surveillé '), (titre: 'Devoir surveillé', bareme: null));
    });

    test('typeDepuisTitre', () {
      expect(typeDepuisTitre('Interrogation 1'), TypeEvaluation.interrogation);
      expect(typeDepuisTitre('interro écrite'), TypeEvaluation.interrogation);
      expect(typeDepuisTitre('Composition du 1er trimestre'), TypeEvaluation.composition);
      expect(typeDepuisTitre('Examen blanc'), TypeEvaluation.examen);
      expect(typeDepuisTitre('Devoir surveillé'), TypeEvaluation.devoir);
      expect(typeDepuisTitre('Dev 2'), TypeEvaluation.devoir);
      expect(typeDepuisTitre('Travail de groupe'), TypeEvaluation.evaluation);
    });
  });

  group('rapport Excel', () {
    test('deux feuilles : problèmes et lignes en erreur, bilan par colonne', () {
      final ctx = contexte();
      final r = analyser([
        ['2026-0001', 'DIALLO Mamadou', 25],
        ['2026-0002', 'BARRY Fatoumata', 12],
        ['2026-0999', 'ZZZ', 10],
      ]);
      final feuilles = feuillesRapportImportNotes(
        etablissement: 'Groupe Scolaire Test',
        nomFichier: 'maths.xlsx',
        date: DateTime(2026, 11, 24),
        ctx: ctx,
        rapport: r,
      );
      expect(feuilles.map((f) => f.nom), ['Rapport', 'Colonnes']);
      final texte = [
        for (final l in feuilles[0].lignes)
          for (final c in l) c?.valeur?.toString() ?? '',
      ].join('|');
      expect(texte, contains('maths.xlsx'));
      expect(texte, contains('dépasse 20'));
      expect(texte, contains('inconnu'));
      expect(texte, contains('Erreur (ligne ignorée)'));
      // Le classeur s'écrit et se relit.
      final relu = lireClasseur(ecrireClasseur(feuilles));
      expect(relu.feuille('Rapport'), isNotNull);
      expect(relu.feuille('Colonnes'), isNotNull);
    });

    test('un fichier bloqué n\'a que la feuille « Rapport »', () {
      final r = analyser(
        const [],
        colonnes: {2: nouvelle('Devoir 1')},
      );
      final feuilles = feuillesRapportImportNotes(
        etablissement: '',
        nomFichier: 'vide.xlsx',
        date: DateTime(2026, 11, 24),
        ctx: contexte(),
        rapport: r,
      );
      expect(feuilles.map((f) => f.nom), ['Rapport']);
      final texte = [
        for (final l in feuilles[0].lignes)
          for (final c in l) c?.valeur?.toString() ?? '',
      ].join('|');
      expect(texte, contains('Problème'));
    });
  });
}
