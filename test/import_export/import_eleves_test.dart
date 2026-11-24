import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/import_export/exports_excel.dart';
import 'package:gesco/import_export/import_eleves.dart';
import 'package:gesco/import_export/lecture_tableur.dart';
import 'package:gesco/import_export/modele_export.dart';
import 'package:gesco/tableur/classeur.dart';
import 'package:gesco/tableur/xlsx.dart';

Cellule cel(Object? v) => switch (v) {
      null => const Cellule(),
      Cellule c => c,
      String s => Cellule(texte: s),
      int n => Cellule(texte: '$n', nombre: n.toDouble()),
      DateTime d => Cellule(
          texte: '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
          date: d,
        ),
      _ => throw ArgumentError('type de cellule non prévu'),
    };

const titres = ['Matricule', 'Nom', 'Prénom', 'Sexe', 'Date de naissance', 'Classe'];

/// Tableau dont la première ligne de données porte le numéro Excel 2.
TableLue tableau(List<String> entetes, List<List<Object?>> lignes) => TableLue(
      nomFeuille: 'Élèves',
      ligneEntete: 1,
      entetes: entetes,
      lignes: [
        for (var i = 0; i < lignes.length; i++)
          LigneTable(2 + i, [for (final v in lignes[i]) cel(v)]),
      ],
    );

final DateTime aujourdhui = DateTime(2026, 11, 22);

ContexteImportEleves contexte({
  List<IdentiteEleve> existants = const [],
  int? classeParDefautId,
  bool depassement = false,
  List<ClasseImport>? classes,
}) =>
    ContexteImportEleves(
      anneeLibelle: '2026-2027',
      maintenant: aujourdhui,
      classes: classes ?? const [ClasseImport(id: 1, nom: '10e A'), ClasseImport(id: 2, nom: '10e B')],
      existants: existants,
      classeParDefautId: classeParDefautId,
      autoriserDepassement: depassement,
    );

RapportImportEleves analyser(
  List<List<Object?>> lignes, {
  List<String> entetes = titres,
  ContexteImportEleves? ctx,
}) =>
    analyserImportEleves(
      table: tableau(entetes, lignes),
      association: associerColonnes(entetes),
      ctx: ctx ?? contexte(),
    );

List<Object?> ligneOk(
  String matricule, {
  Object? nom = 'BARRY',
  String prenom = 'Mamadou',
  Object? sexe = 'M',
  Object? naissance = '05/03/2011',
  Object? classe = '10e A',
}) =>
    [matricule, nom, prenom, sexe, naissance, classe];

void main() {
  group('associerColonnes', () {
    test('titres des exports de GESCO : tout est reconnu, « N° » et « Situation » ignorés', () {
      expect(associerColonnes(colonnesEleves), [
        null,
        ChampEleve.matricule,
        ChampEleve.nom,
        ChampEleve.prenom,
        ChampEleve.sexe,
        ChampEleve.dateNaissance,
        ChampEleve.lieuNaissance,
        ChampEleve.adresse,
        ChampEleve.telephone,
        ChampEleve.nomPere,
        ChampEleve.nomMere,
        ChampEleve.contactParent,
        ChampEleve.nomTuteur,
        ChampEleve.contactTuteur,
        ChampEleve.classe,
        ChampEleve.anneeScolaire,
        null,
      ]);
    });

    test('majuscules, accents et séparateurs ne comptent pas', () {
      expect(
        associerColonnes(['MATRICULE', 'nom_de_famille', 'PRENOMS', 'Genre', 'Date_Naissance', 'Divers']),
        [
          ChampEleve.matricule,
          ChampEleve.nom,
          ChampEleve.prenom,
          ChampEleve.sexe,
          ChampEleve.dateNaissance,
          null,
        ],
      );
    });

    test('un champ n\'est proposé que pour une seule colonne', () {
      expect(associerColonnes(['Nom', 'Nom']), [ChampEleve.nom, null]);
    });

    test('colonne sans titre : ignorée', () {
      expect(associerColonnes(['', 'Nom']), [null, ChampEleve.nom]);
    });
  });

  group('fichier correct', () {
    test('élèves lus avec leurs informations', () {
      final r = analyser([
        ligneOk('2026-0001'),
        ligneOk('2026-0002',
            nom: 'Diallo', prenom: 'Aminata', sexe: 'Féminin', naissance: DateTime(2012, 7, 9), classe: '10e b'),
      ]);
      expect(r.problemesFichier, isEmpty);
      expect(r.nbAImporter, 2);
      expect(r.nbErreurs, 0);
      final a = r.lignes[0];
      expect(a.numero, 2);
      expect(a.eleve!.matricule, '2026-0001');
      expect(a.eleve!.nom, 'BARRY');
      expect(a.eleve!.sexe, 'M');
      expect(a.eleve!.dateNaissance, '2011-03-05');
      expect(a.classeId, 1);
      final b = r.lignes[1];
      expect(b.eleve!.sexe, 'F');
      expect(b.eleve!.dateNaissance, '2012-07-09');
      expect(b.classeId, 2);
      expect(b.classe, '10e B', reason: 'nom de la classe tel qu\'enregistré dans GESCO');
      expect(r.effectifParClasse, {'10e A': 1, '10e B': 1});
      expect(r.peutImporter(ignorerErreurs: false), isTrue);
    });

    test('numéro de série Excel pris pour une date', () {
      final r = analyser([ligneOk('2026-0001', naissance: 40607)]);
      expect(r.lignes.single.eleve!.dateNaissance, '2011-03-05');
    });

    test('colonnes facultatives : lieu, adresse, parents, tuteur', () {
      const entetes = [
        'Matricule', 'Nom', 'Prénom', 'Sexe', 'Classe', 'Lieu de naissance', 'Adresse',
        'Téléphone', 'Nom du père', 'Nom de la mère', 'Contact des parents', 'Nom du tuteur',
        'Contact du tuteur',
      ];
      final r = analyser([
        [
          '2026-0001', 'BARRY', 'Mamadou', 'M', '10e A', 'Conakry', 'Tombolia', 622000001,
          'Alpha', 'Fatou', '622000002', 'Oncle', '622000003',
        ],
      ], entetes: entetes);
      final e = r.lignes.single.eleve!;
      expect(e.lieuNaissance, 'Conakry');
      expect(e.adresse, 'Tombolia');
      expect(e.telephone, '622000001');
      expect(e.nomPere, 'Alpha');
      expect(e.nomMere, 'Fatou');
      expect(e.contactParent, '622000002');
      expect(e.nomTuteur, 'Oncle');
      expect(e.contactTuteur, '622000003');
    });

    test('espaces superflus retirés', () {
      final r = analyser([ligneOk('  2026-0001 ', nom: '  BARRY  ', prenom: 'Mamadou   Alpha')]);
      final e = r.lignes.single.eleve!;
      expect(e.matricule, '2026-0001');
      expect(e.nom, 'BARRY');
      expect(e.prenom, 'Mamadou Alpha');
    });

    test('lignes vides ignorées et comptées', () {
      final r = analyser([
        ligneOk('2026-0001'),
        [null, null, null, null, null, null],
        ligneOk('2026-0002', nom: 'DIALLO'),
      ]);
      expect(r.lignes.length, 2);
      expect(r.nbLignesVides, 1);
      expect(r.remarquesFichier, contains('1 ligne vide ignorée.'));
    });

    test('âge inhabituel : avertissement, la ligne reste importable', () {
      final r = analyser([ligneOk('2026-0001', naissance: '01/01/2026')]);
      final l = r.lignes.single;
      expect(l.aImporter, isTrue);
      expect(l.avertissements.single, contains('Âge inhabituel'));
      expect(r.nbAvertissements, 1);
    });
  });

  group('problèmes du fichier', () {
    test('champ obligatoire non associé : aucune ligne n\'est vérifiée', () {
      final r = analyser([
        ['2026-0001', 'Mamadou', 'M', '10e A'],
      ], entetes: ['Matricule', 'Prénom', 'Sexe', 'Classe']);
      expect(r.bloque, isTrue);
      expect(r.problemesFichier.single, contains('« Nom »'));
      expect(r.lignes, isEmpty);
      expect(r.peutImporter(ignorerErreurs: true), isFalse);
    });

    test('deux colonnes pour le même champ', () {
      final r = analyserImportEleves(
        table: tableau(['Nom', 'Autre nom', 'Prénom', 'Sexe', 'Classe'], [
          ['BARRY', 'x', 'Mamadou', 'M', '10e A'],
        ]),
        association: const [
          ChampEleve.nom,
          ChampEleve.nom,
          ChampEleve.prenom,
          ChampEleve.sexe,
          ChampEleve.classe,
        ],
        ctx: contexte(),
      );
      expect(r.problemesFichier.single, contains('associé à deux colonnes'));
      expect(r.problemesFichier.single, contains('« Autre nom »'));
    });

    test('ni colonne « Classe » ni classe par défaut', () {
      final r = analyser([
        ['2026-0001', 'BARRY', 'Mamadou', 'M'],
      ], entetes: ['Matricule', 'Nom', 'Prénom', 'Sexe']);
      expect(r.problemesFichier.single, contains('classe de tous les élèves'));
    });

    test('classe par défaut : la colonne « Classe » n\'est plus nécessaire', () {
      final r = analyser(
        [
          ['2026-0001', 'BARRY', 'Mamadou', 'M'],
        ],
        entetes: ['Matricule', 'Nom', 'Prénom', 'Sexe'],
        ctx: contexte(classeParDefautId: 2),
      );
      expect(r.problemesFichier, isEmpty);
      expect(r.lignes.single.classeId, 2);
      expect(r.lignes.single.classe, '10e B');
    });

    test('tableau sans ligne d\'élève', () {
      final r = analyser(const []);
      expect(r.problemesFichier.single, contains('aucune ligne d\'élève'));
    });
  });

  group('erreurs par ligne', () {
    String premiereErreur(List<Object?> ligne, {ContexteImportEleves? ctx}) {
      final r = analyser([ligne], ctx: ctx);
      final l = r.lignes.single;
      expect(l.enErreur, isTrue);
      expect(l.aImporter, isFalse);
      expect(l.eleve, isNull);
      return l.erreurs.first;
    }

    test('sexe non reconnu : un seul message', () {
      final r = analyser([ligneOk('2026-0001', sexe: 'X')]);
      expect(r.lignes.single.erreurs, hasLength(1));
      expect(r.lignes.single.erreurs.single, contains('« X » non reconnu'));
    });

    test('sexe vide', () {
      expect(premiereErreur(ligneOk('2026-0001', sexe: null)), contains('sexe'));
    });

    test('sexe écrit de plusieurs façons', () {
      final r = analyser([
        ligneOk('1', sexe: 'm'),
        ligneOk('2', nom: 'A', sexe: 'Garçon'),
        ligneOk('3', nom: 'B', sexe: 'fille'),
        ligneOk('4', nom: 'C', sexe: 'F'),
        ligneOk('5', nom: 'D', sexe: 'Masculin'),
      ]);
      expect([for (final l in r.lignes) l.eleve!.sexe], ['M', 'M', 'F', 'F', 'M']);
    });

    test('date illisible, avec année sur deux chiffres', () {
      expect(premiereErreur(ligneOk('2026-0001', naissance: 'bientôt')), contains('illisible'));
      expect(premiereErreur(ligneOk('2026-0001', naissance: '5/3/11')), contains('illisible'));
      expect(premiereErreur(ligneOk('2026-0001', naissance: '31/02/2011')), contains('illisible'));
    });

    test('date dans le futur', () {
      expect(premiereErreur(ligneOk('2026-0001', naissance: '01/01/2027')), contains('futur'));
    });

    test('nom ou prénom vide', () {
      expect(premiereErreur(ligneOk('2026-0001', nom: '')), contains('nom est obligatoire'));
      expect(premiereErreur(ligneOk('2026-0001', prenom: '')), contains('prénom est obligatoire'));
    });

    test('classe inconnue : les classes existantes sont rappelées', () {
      final e = premiereErreur(ligneOk('2026-0001', classe: '11e Z'));
      expect(e, contains('« 11e Z » inconnue'));
      expect(e, contains('10e A, 10e B'));
    });

    test('classe vide sans classe par défaut', () {
      expect(premiereErreur(ligneOk('2026-0001', classe: null)), 'Classe manquante.');
    });

    test('classe vide avec classe par défaut : la classe par défaut', () {
      final r = analyser([ligneOk('2026-0001', classe: null)], ctx: contexte(classeParDefautId: 1));
      expect(r.lignes.single.classeId, 1);
      expect(r.lignes.single.aImporter, isTrue);
    });

    test('année scolaire différente de l\'année en cours', () {
      const entetes = [...titres, 'Année scolaire'];
      final r = analyser([
        [...ligneOk('2026-0001'), '2025-2026'],
        [...ligneOk('2026-0002', nom: 'DIALLO'), '2026/2027'],
        [...ligneOk('2026-0003', nom: 'SOW'), null],
      ], entetes: entetes);
      expect(r.lignes[0].erreurs.single, contains('différente de l\'année en cours (2026-2027)'));
      expect(r.lignes[1].aImporter, isTrue, reason: '2026/2027 = 2026-2027');
      expect(r.lignes[2].aImporter, isTrue, reason: 'cellule vide : année en cours');
    });

    test('cellule contenant une formule', () {
      final e = premiereErreur(ligneOk('2026-0001', nom: const Cellule(texte: '=B9', formule: true)));
      expect(e, contains('formule'));
    });

    test('plusieurs erreurs sur la même ligne', () {
      final r = analyser([ligneOk('2026-0001', nom: '', sexe: 'X', classe: '11e Z')]);
      expect(r.lignes.single.erreurs.length, greaterThanOrEqualTo(3));
    });

    test('matricule trop long', () {
      expect(premiereErreur(ligneOk('X' * 41)), contains('matricule est trop long'));
    });
  });

  group('matricules', () {
    test('doublon dans le fichier : la deuxième ligne est refusée', () {
      final r = analyser([ligneOk('2026-0001'), ligneOk('2026-0001', nom: 'DIALLO')]);
      expect(r.lignes[0].aImporter, isTrue);
      expect(r.lignes[1].erreurs.single, contains('Doublon dans le fichier'));
      expect(r.lignes[1].erreurs.single, contains('ligne 2'));
    });

    test('majuscules ignorées dans les doublons', () {
      final r = analyser([ligneOk('abc-1'), ligneOk('ABC-1', nom: 'DIALLO')]);
      expect(r.lignes[1].enErreur, isTrue);
    });

    test('même matricule et même identité : déjà présent, ignoré sans erreur', () {
      final r = analyser(
        [ligneOk('2026-0001', nom: 'barry', prenom: 'MAMADOU')],
        ctx: contexte(existants: const [
          IdentiteEleve(matricule: '2026-0001', nom: 'BARRY', prenom: 'Mamadou'),
        ]),
      );
      final l = r.lignes.single;
      expect(l.dejaPresent, isTrue);
      expect(l.enErreur, isFalse);
      expect(l.aImporter, isFalse);
      expect(r.nbDejaPresents, 1);
      expect(r.nbAImporter, 0);
      expect(r.peutImporter(ignorerErreurs: false), isFalse, reason: 'rien à importer');
    });

    test('même matricule, autre personne : erreur, rien n\'est écrasé', () {
      final r = analyser(
        [ligneOk('2026-0001')],
        ctx: contexte(existants: const [
          IdentiteEleve(matricule: '2026-0001', nom: 'SOW', prenom: 'Ali'),
        ]),
      );
      expect(r.lignes.single.erreurs.single, contains('appartient déjà à SOW Ali'));
      expect(r.lignes.single.dejaPresent, isFalse);
    });

    test('dossier archivé signalé', () {
      final r = analyser(
        [ligneOk('2026-0001')],
        ctx: contexte(existants: const [
          IdentiteEleve(matricule: '2026-0001', nom: 'SOW', prenom: 'Ali', archive: true),
        ]),
      );
      expect(r.lignes.single.erreurs.single, contains('archivé'));
    });

    test('matricule vide : GESCO en attribue un, sans reprendre un numéro utilisé', () {
      final r = analyser(
        [
          ligneOk(''),
          ligneOk('2026-0005', nom: 'DIALLO'),
          ligneOk('', nom: 'SOW'),
        ],
        ctx: contexte(existants: const [
          IdentiteEleve(matricule: '2026-0001', nom: 'A', prenom: 'A'),
          IdentiteEleve(matricule: '2026-0002', nom: 'B', prenom: 'B'),
        ]),
      );
      expect(r.lignes[0].matricule, '2026-0006');
      expect(r.lignes[0].matriculeGenere, isTrue);
      expect(r.lignes[1].matricule, '2026-0005');
      expect(r.lignes[1].matriculeGenere, isFalse);
      expect(r.lignes[2].matricule, '2026-0007');
      expect(r.lignes.every((l) => l.aImporter), isTrue);
      expect(r.remarquesFichier.first, contains('2 matricules vides'));
    });

    test('pas de colonne « Matricule » : tous générés, signalé une fois', () {
      final r = analyser(
        [
          ['BARRY', 'Mamadou', 'M', '10e A'],
          ['DIALLO', 'Aminata', 'F', '10e A'],
        ],
        entetes: ['Nom', 'Prénom', 'Sexe', 'Classe'],
      );
      expect([for (final l in r.lignes) l.matricule], ['2026-0001', '2026-0002']);
      expect(r.remarquesFichier.single, contains('Aucune colonne « Matricule »'));
    });
  });

  group('personnes déjà connues', () {
    test('même nom, prénom et date de naissance qu\'un élève existant : avertissement', () {
      final r = analyser(
        [ligneOk('2026-0009')],
        ctx: contexte(existants: const [
          IdentiteEleve(
            matricule: '2026-0001',
            nom: 'BARRY',
            prenom: 'Mamadou',
            dateNaissance: '2011-03-05',
          ),
        ]),
      );
      final l = r.lignes.single;
      expect(l.aImporter, isTrue, reason: 'avertissement seulement');
      expect(l.avertissements.single, contains('existe déjà dans GESCO'));
      expect(l.avertissements.single, contains('2026-0001'));
    });

    test('même personne deux fois dans le fichier', () {
      final r = analyser([ligneOk('2026-0001'), ligneOk('2026-0002')]);
      expect(r.lignes[0].avertissements, isEmpty);
      expect(r.lignes[1].avertissements.single, contains('ligne 2'));
      expect(r.lignes[1].aImporter, isTrue);
    });

    test('dates de naissance différentes : pas d\'avertissement', () {
      final r = analyser([ligneOk('2026-0001'), ligneOk('2026-0002', naissance: '06/03/2011')]);
      expect(r.nbAvertissements, 0);
    });
  });

  group('capacité des classes', () {
    const pleine = [ClasseImport(id: 1, nom: '10e A', capacite: 2, nbActifs: 1)];

    test('la classe pleine refuse les élèves en trop', () {
      final r = analyser(
        [ligneOk('1'), ligneOk('2', nom: 'DIALLO'), ligneOk('3', nom: 'SOW')],
        ctx: contexte(classes: pleine),
      );
      expect(r.lignes[0].aImporter, isTrue);
      expect(r.lignes[1].erreurs.single, contains('est pleine (capacité 2, 1 élève déjà inscrit)'));
      expect(r.lignes[2].enErreur, isTrue);
    });

    test('dépassement autorisé : simple avertissement', () {
      final r = analyser(
        [ligneOk('1'), ligneOk('2', nom: 'DIALLO')],
        ctx: contexte(classes: pleine, depassement: true),
      );
      expect(r.nbErreurs, 0);
      expect(r.lignes[1].avertissements.single, contains('Dépassement autorisé'));
    });

    test('les lignes déjà présentes ou en erreur ne prennent pas de place', () {
      final r = analyser(
        [ligneOk('1', sexe: 'X'), ligneOk('2', nom: 'DIALLO')],
        ctx: contexte(classes: pleine),
      );
      expect(r.lignes[1].aImporter, isTrue);
    });
  });

  group('décision d\'importer', () {
    test('une erreur bloque, sauf accord pour ignorer les lignes en erreur', () {
      final r = analyser([ligneOk('1'), ligneOk('2', nom: 'DIALLO', sexe: 'X')]);
      expect(r.nbAImporter, 1);
      expect(r.nbErreurs, 1);
      expect(r.peutImporter(ignorerErreurs: false), isFalse);
      expect(r.peutImporter(ignorerErreurs: true), isTrue);
    });

    test('que des erreurs : rien à importer même en les ignorant', () {
      final r = analyser([ligneOk('1', sexe: 'X')]);
      expect(r.peutImporter(ignorerErreurs: true), isFalse);
    });
  });

  group('rapport et modèle Excel', () {
    test('le rapport ne liste que les lignes à signaler', () {
      final r = analyser([
        ligneOk('1'),
        ligneOk('2', nom: 'DIALLO', sexe: 'X'),
        ligneOk('3', nom: 'SOW', naissance: '01/01/2026'),
      ]);
      final f = feuilleRapportImportEleves(
        etablissement: 'Groupe Test',
        anneeLibelle: '2026-2027',
        nomFichier: 'eleves.xlsx',
        date: aujourdhui,
        rapport: r,
      );
      expect(f.nom, 'Rapport');
      expect(f.lignes[0].first!.valeur, 'Groupe Test');
      expect(f.lignes[3].first!.valeur, '2 à importer  ·  0 déjà présents  ·  1 en erreur  ·  1 avec remarque');
      final entete = f.lignes.indexWhere((l) => l.isNotEmpty && l.first?.valeur == 'Ligne');
      expect(entete, greaterThan(0));
      final donnees = f.lignes.sublist(entete + 1);
      expect(donnees, hasLength(2));
      expect(donnees[0][0]!.valeur, 3, reason: 'numéro de ligne Excel');
      expect(donnees[0][5]!.valeur, 'Erreur');
      expect(donnees[1][5]!.valeur, 'À importer (remarque)');
    });

    test('le modèle se relit avec les titres reconnus', () {
      final f = feuilleModeleImportEleves(etablissement: 'Groupe Test', anneeLibelle: '2026-2027');
      final lu = lireClasseur(ecrireClasseur([f]));
      final feuille = lu.feuilles.single;
      final i = trouverLigneEntete(feuille, titresConnusEleves)!;
      final table = lireTable(feuille, indexEntete: i);
      expect(table.lignes, isEmpty, reason: 'cases vides : rien à importer tel quel');
      final assoc = associerColonnes(table.entetes);
      expect(assoc.whereType<ChampEleve>().toSet(), {
        for (final c in ChampEleve.values)
          if (c != ChampEleve.anneeScolaire) c,
      });
    });
  });

  group('aller-retour : liste exportée puis réimportée', () {
    test('la liste des élèves exportée est relue et se vérifie sans erreur', () {
      const eleves = [
        EleveExport(
          eleve: Eleve(
            matricule: '2026-0001',
            nom: 'BARRY',
            prenom: 'Mamadou',
            sexe: 'M',
            dateNaissance: '2011-03-05',
            lieuNaissance: 'Conakry',
            telephone: '622000001',
            nomPere: 'Alpha Barry',
          ),
          inscription: EleveInscrit(
            inscriptionId: 1,
            eleveId: 1,
            classeId: 1,
            classeNom: '10e A',
            matricule: '2026-0001',
            nom: 'BARRY',
            prenom: 'Mamadou',
            sexe: 'M',
          ),
        ),
        EleveExport(
          eleve: Eleve(matricule: '2026-0002', nom: 'DIALLO', prenom: 'Aminata', sexe: 'F'),
          inscription: EleveInscrit(
            inscriptionId: 2,
            eleveId: 2,
            classeId: 2,
            classeNom: '10e B',
            matricule: '2026-0002',
            nom: 'DIALLO',
            prenom: 'Aminata',
            sexe: 'F',
            statut: StatutInscription.depart,
          ),
        ),
      ];
      final export = feuilleEleves(
        ContexteExport(etablissement: 'Groupe Test', annee: '2026-2027', date: aujourdhui),
        'Élèves',
        'Liste complète des élèves',
        eleves,
      );
      final lu = lireClasseur(ecrireClasseur([export])).feuilles.single;

      final i = trouverLigneEntete(lu, titresConnusEleves);
      expect(i, 4, reason: 'trois lignes d\'en-tête, une ligne vide, puis les titres');
      final table = lireTable(lu, indexEntete: i!);
      expect(table.ligneEntete, 5);
      expect(table.lignes.map((l) => l.numero), [6, 7]);

      final r = analyserImportEleves(
        table: table,
        association: associerColonnes(table.entetes),
        ctx: contexte(),
      );
      expect(r.problemesFichier, isEmpty);
      expect(r.nbErreurs, 0);
      expect(r.nbAImporter, 2);
      final a = r.lignes[0].eleve!;
      expect(a.matricule, '2026-0001');
      expect(a.dateNaissance, '2011-03-05');
      expect(a.lieuNaissance, 'Conakry');
      expect(a.telephone, '622000001');
      expect(a.nomPere, 'Alpha Barry');
      expect(r.lignes[1].classeId, 2);
    });

    test('réimporter la même liste dans une base qui la contient : tout est « déjà présent »', () {
      final r = analyser(
        [ligneOk('2026-0001'), ligneOk('2026-0002', nom: 'DIALLO', prenom: 'Aminata')],
        ctx: contexte(existants: const [
          IdentiteEleve(matricule: '2026-0001', nom: 'BARRY', prenom: 'Mamadou'),
          IdentiteEleve(matricule: '2026-0002', nom: 'DIALLO', prenom: 'Aminata'),
        ]),
      );
      expect(r.nbDejaPresents, 2);
      expect(r.nbAImporter, 0);
      expect(r.nbErreurs, 0);
    });
  });
}
