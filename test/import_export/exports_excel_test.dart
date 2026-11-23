import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/calcul_classe.dart';
import 'package:gesco/data/modeles_absences.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/periodes.dart';
import 'package:gesco/import_export/exports_excel.dart';
import 'package:gesco/import_export/modele_export.dart';
import 'package:gesco/tableur/classeur.dart';
import 'package:gesco/tableur/xlsx.dart';

import '../app/classe_exemple.dart' as ex;

/// Valeur écrite dans la cellule (ligne, colonne) d'une feuille.
Object? val(FeuilleEcrite f, int ligne, int colonne) => f.lignes[ligne][colonne]?.valeur;

/// Texte des cellules d'une ligne.
List<Object?> ligne(FeuilleEcrite f, int l) => [for (final c in f.lignes[l]) c?.valeur];

final ctx = ContexteExport(
  etablissement: 'Groupe Scolaire Test',
  annee: '2026-2027',
  date: DateTime(2026, 11, 22),
);

/// Les trois lignes d'en-tête, une ligne vide, puis le titre des colonnes.
const int entete = 4;
const int premiere = 5;

void main() {
  final c = ex.classe();
  const novembre = Portee.mois(11);

  group('en-tête commun', () {
    test('établissement, titre, année et date d\'édition', () {
      final f = feuilleNotesClasse(ctx, c, novembre);
      expect(val(f, 0, 0), 'Groupe Scolaire Test');
      expect(val(f, 1, 0), 'Notes de la classe 10e A');
      expect(val(f, 2, 0), 'Année scolaire 2026-2027  ·  Novembre  ·  Édité le 22/11/2026');
      expect(f.lignes[3], isEmpty);
    });

    test('établissement sans nom : libellé de remplacement', () {
      final f = feuilleNotesClasse(
        ContexteExport(etablissement: '', annee: '', date: DateTime(2026, 1, 5)),
        c,
        novembre,
      );
      expect(val(f, 0, 0), 'Établissement');
      expect(val(f, 2, 0), 'Novembre  ·  Édité le 05/01/2026');
    });
  });

  group('liste des élèves', () {
    const eleves = [
      EleveExport(
        eleve: Eleve(
          matricule: '2026-0001',
          nom: 'BARRY',
          prenom: 'Mamadou',
          sexe: 'M',
          dateNaissance: '2011-03-05',
          lieuNaissance: 'Conakry',
          adresse: 'Tombolia',
          telephone: '622000001',
          nomPere: 'Alpha Barry',
          nomMere: 'Aïssatou Diallo',
          contactParent: '622000002',
          nomTuteur: 'Oncle Bah',
          contactTuteur: '622000003',
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
          classeId: 1,
          classeNom: '10e A',
          matricule: '2026-0002',
          nom: 'DIALLO',
          prenom: 'Aminata',
          sexe: 'F',
          statut: StatutInscription.depart,
        ),
      ),
    ];

    test('une ligne par élève, toutes les colonnes de la fiche', () {
      final f = feuilleEleves(ctx, 'Élèves', 'Liste complète des élèves', eleves);
      expect(ligne(f, entete), colonnesEleves);
      expect(val(f, 2, 0), contains('2 élèves'));

      final b = ligne(f, premiere);
      expect(b[0], 1);
      expect(b[1], '2026-0001');
      expect(b[2], 'BARRY');
      expect(b[3], 'Mamadou');
      expect(b[4], 'M');
      expect(b[5], DateTime(2011, 3, 5));
      expect(b[6], 'Conakry');
      expect(b[7], 'Tombolia');
      expect(b[8], '622000001');
      expect(b[9], 'Alpha Barry');
      expect(b[10], 'Aïssatou Diallo');
      expect(b[11], '622000002');
      expect(b[12], 'Oncle Bah');
      expect(b[13], '622000003');
      expect(b[14], '10e A');
      expect(b[15], '2026-2027');
      expect(b[16], 'Inscrit');

      final d = ligne(f, premiere + 1);
      expect(d[0], 2);
      expect(d[5], isNull, reason: 'date de naissance inconnue : cellule vide');
      expect(d[16], 'Parti');
    });

    test('une date illisible est conservée telle quelle', () {
      const e = EleveExport(
        eleve: Eleve(
          matricule: 'X',
          nom: 'A',
          prenom: 'B',
          sexe: 'M',
          dateNaissance: 'vers 2011',
        ),
        inscription: EleveInscrit(
          inscriptionId: 1,
          eleveId: 1,
          classeId: 1,
          classeNom: '10e A',
          matricule: 'X',
          nom: 'A',
          prenom: 'B',
          sexe: 'M',
        ),
      );
      final f = feuilleEleves(ctx, 'Élèves', 'Élèves', const [e]);
      expect(val(f, premiere, 5), 'vers 2011');
    });

    test('un seul élève : pas de pluriel', () {
      final f = feuilleEleves(ctx, 'Élèves', 'Élèves', [eleves.first]);
      expect(val(f, 2, 0), contains('1 élève'));
      expect(val(f, 2, 0), isNot(contains('1 élèves')));
    });
  });

  group('notes par matière', () {
    test('une colonne par mois, moyennes de période, moyenne annuelle et rang', () {
      final maths = c.matieres.first;
      final f = feuilleNotesMatiere(ctx, c, maths);
      expect(f.nom, 'Notes Maths');
      expect(val(f, 1, 0), 'Notes de Maths');
      expect(val(f, 2, 0), contains('coefficient 1'));
      expect(ligne(f, entete), [
        'N°',
        'Matricule',
        'Nom',
        'Prénom',
        for (final m in moisScolaires) libelleMois(m),
        'Moyenne Trimestre 1',
        'Moyenne Trimestre 2',
        'Moyenne Trimestre 3',
        'Moyenne annuelle',
        'Rang annuel',
      ]);

      // Élèves actifs seulement : SOW (parti) n'y figure pas.
      expect(f.lignes.length, premiere + 4);
      expect([for (var i = 0; i < 4; i++) val(f, premiere + i, 2)],
          ['BARRY', 'CAMARA', 'DIALLO', 'TOURE']);
      expect([for (var i = 0; i < 4; i++) val(f, premiere + i, 0)], [1, 2, 3, 4]);

      final barry = ligne(f, premiere);
      final iNovembre = 4 + moisScolaires.indexOf(11);
      final iJanvier = 4 + moisScolaires.indexOf(1);
      expect(barry[iNovembre], 16.0);
      expect(barry[iJanvier], 18.0);
      expect(barry[4 + moisScolaires.indexOf(12)], isNull, reason: 'pas de note en décembre');

      // Moyennes lues dans le moteur : le fichier ne recalcule rien.
      final donnees = c.donnees.first;
      final annuelle = c.moteur.noteMatiere(donnees, maths.id, const Portee.annee())!;
      expect(barry[4 + 9 + 3], annuelle / 100);
      final t1 = c.moteur.noteMatiere(donnees, maths.id, Portee.periode(c.calendrier.periodes[0]))!;
      expect(barry[4 + 9], t1 / 100);

      final rangs = {
        for (final r in c.moteur.classementMatiere(maths.id, const Portee.annee()))
          r.inscriptionId: r.rang,
      };
      expect(barry[4 + 9 + 4], rangs[1]);

      final toure = ligne(f, premiere + 3);
      expect(toure.sublist(4), everyElement(isNull), reason: 'aucune note : cellules vides');
    });

    test('les notes sont des nombres triables, pas du texte', () {
      final f = feuilleNotesMatiere(ctx, c, c.matieres.first);
      final cellule = f.lignes[premiere][4 + moisScolaires.indexOf(11)]!;
      expect(cellule.valeur, isA<double>());
      expect(cellule.style, StyleCellule.note);
    });
  });

  group('notes par classe', () {
    test('une colonne par matière avec son coefficient, puis moyenne et décision', () {
      final f = feuilleNotesClasse(ctx, c, novembre);
      expect(f.nom, 'Classe 10e A');
      expect(ligne(f, entete), [
        'N°',
        'Matricule',
        'Nom',
        'Prénom',
        'Maths\ncoef. 1',
        'Français\ncoef. 1',
        'Dessin\ncoef. 1,5 (facultative)',
        'Moyenne',
        'Rang',
        'Mention',
        'Décision',
      ]);
      expect(f.lignes.length, premiere + 4);

      final barry = ligne(f, premiere);
      expect(barry[4], 16.0);
      expect(barry[5], 16.0);
      expect(barry[6], 12.0);
      final r = c.resultats(novembre).firstWhere((x) => x.inscriptionId == 1);
      expect(barry[7], r.moyenne! / 100);
      expect(barry[8], r.rang);
      expect(barry[9], r.mention);
      expect(barry[10], r.decision);

      final toure = ligne(f, premiere + 3);
      expect(toure[2], 'TOURE');
      expect(toure[4], isNull);
      expect(toure[7], isNull, reason: 'pas de moyenne sans note');
      expect(toure[8], isNull);
    });
  });

  group('résultats', () {
    test('annuels : moyenne de chaque période et remarque pour les départs', () {
      final f = feuilleResultats(ctx, c, const Portee.annee());
      expect(f.nom, 'Résultats 10e A');
      expect(val(f, 1, 0), 'Résultats annuels');
      expect(ligne(f, entete), [
        'N°',
        'Matricule',
        'Nom',
        'Prénom',
        'Sexe',
        'Moyenne Trimestre 1',
        'Moyenne Trimestre 2',
        'Moyenne Trimestre 3',
        'Moyenne annuelle',
        'Rang',
        'Mention',
        'Décision',
        'Remarque',
      ]);
      // Tous les élèves, partis compris.
      expect(f.lignes.length, premiere + 5);
      final sow = ligne(f, premiere + 3);
      expect(sow[2], 'SOW');
      expect(sow[12], 'Parti');
      expect(sow[9], isNull, reason: 'un élève parti n\'est pas classé');

      final barry = ligne(f, premiere);
      final annuelle = c.resultats(const Portee.annee()).firstWhere((x) => x.inscriptionId == 1);
      expect(barry[8], annuelle.moyenne! / 100);
      expect(barry[9], annuelle.rang);
    });

    test('d\'un trimestre : une seule colonne de moyenne', () {
      final t1 = Portee.periode(c.calendrier.periodes.first);
      final f = feuilleResultats(ctx, c, t1);
      expect(val(f, 1, 0), 'Résultats : Trimestre 1');
      expect(ligne(f, entete).sublist(5, 6), ['Moyenne']);
      expect(ligne(f, entete).length, 10);
    });
  });

  group('classements', () {
    test('général : même ordre que l\'écran, non classés à la fin', () {
      final f = feuilleClassement(ctx, c, novembre);
      final attendu = lignesClassement(c, novembre);
      expect([for (var i = 0; i < attendu.length; i++) val(f, premiere + i, 2)],
          [for (final l in attendu) l.eleve.matricule]);
      expect(val(f, premiere, 0), 1);
      for (var i = 0; i < attendu.length; i++) {
        expect(val(f, premiere + i, 1), attendu[i].exAequo ? 'oui' : '');
        expect(val(f, premiere + i, 0), attendu[i].rang);
      }
      // SOW (parti) : sans rang, avec sa remarque.
      final iSow = attendu.indexWhere((l) => l.eleve.nom == 'SOW');
      expect(val(f, premiere + iSow, 0), isNull);
      expect(val(f, premiere + iSow, 9), 'Parti');
    });

    test('dans une matière : colonne « Note » et pas de décision', () {
      final dessin = c.matieres.last;
      final f = feuilleClassement(ctx, c, novembre, matiere: dessin);
      expect(val(f, 1, 0), 'Classement en Dessin');
      expect(ligne(f, entete), [
        'Rang',
        'Ex æquo',
        'Matricule',
        'Nom',
        'Prénom',
        'Sexe',
        'Note',
        'Mention',
        'Remarque',
      ]);
      expect(f.nom, 'Dessin 10e A');
    });
  });

  group('absences et retards', () {
    final eleves = [ex.eleve(1, 'BARRY'), ex.eleve(2, 'CAMARA')];
    final totaux = {
      1: const TotauxAbsences(
        absences: 3,
        absencesJustifiees: 1,
        retards: 2,
        retardsJustifies: 1,
        minutesRetard: 25,
      ),
    };
    final detail = [
      const Absence(
        inscriptionId: 1,
        date: '2026-11-03',
        justifiee: true,
        motif: 'Paludisme',
        eleveNom: 'BARRY X',
        matricule: 'M1',
        classeNom: '10e A',
      ),
      const Absence(
        inscriptionId: 1,
        date: '2026-11-05',
        type: TypeAbsence.retard,
        dureeMinutes: 15,
        eleveNom: 'BARRY X',
        matricule: 'M1',
        classeNom: '10e A',
      ),
    ];

    test('totaux par élève et ligne de total', () {
      final feuilles = feuillesAbsences(ctx, eleves, totaux, detail);
      expect([for (final f in feuilles) f.nom], ['Totaux', 'Détail']);
      final t = feuilles.first;
      expect(ligne(t, premiere).sublist(1), ['M1', 'BARRY', 'X', 3, 1, 2, 2, 1, 25]);
      expect(ligne(t, premiere + 1).sublist(4), [0, 0, 0, 0, 0, 0],
          reason: 'un élève sans absence a des zéros');
      expect(ligne(t, premiere + 2)[0], 'TOTAL');
      expect(ligne(t, premiere + 2).sublist(4), [3, 1, 2, 2, 1, 25]);
    });

    test('détail jour par jour : dates, durée du retard, motif', () {
      final j = feuillesAbsences(ctx, eleves, totaux, detail).last;
      expect(ligne(j, premiere), [
        DateTime(2026, 11, 3),
        '10e A',
        'M1',
        'BARRY X',
        'Absence',
        'Oui',
        null,
        'Paludisme',
      ]);
      final retard = ligne(j, premiere + 1);
      expect(retard[4], 'Retard');
      expect(retard[5], 'Non');
      expect(retard[6], 15);
    });
  });

  group('statistiques', () {
    test('établissement et classes reprennent les chiffres de la classe', () {
      final s = c.stats(novembre);
      final feuilles = feuillesStatistiques(
        ctx,
        [ClassePortee(c, novembre)],
        libelle: 'Novembre',
      );
      expect([for (final f in feuilles) f.nom], ['Établissement', 'Classes']);
      final ecole = feuilles.first;
      Object? valeur(String indicateur) {
        for (var i = premiere; i < ecole.lignes.length; i++) {
          if (val(ecole, i, 0) == indicateur) return val(ecole, i, 1);
        }
        fail('Indicateur absent : $indicateur');
      }

      expect(valeur('Nombre de classes'), 1);
      expect(valeur('Élèves inscrits'), s.effectif);
      expect(valeur('dont filles'), s.filles);
      expect(valeur('dont garçons'), s.garcons);
      expect(valeur('Élèves évalués'), s.evalues);
      expect(valeur('Admis'), s.admis);
      expect(valeur('Non admis'), s.nonAdmis);
      expect(valeur('Taux de réussite (%)'), s.tauxReussiteCentiemes! / 100);
      expect(valeur('Moyenne générale (de tous les élèves évalués)'), s.moyenneClasse! / 100);
      expect(valeur('Meilleure moyenne'), s.meilleureMoyenne! / 100);
      expect(valeur('Plus faible moyenne'), s.plusFaibleMoyenne! / 100);

      final classe = ligne(feuilles.last, premiere);
      expect(classe[0], '10e A');
      expect(classe[1], s.effectif);
      expect(classe[8], s.moyenneClasse! / 100);
    });

    test('plusieurs classes : moyenne exacte de tous les élèves évalués', () {
      // Deux fois la même classe : la moyenne générale reste celle de la classe.
      final s = c.stats(novembre);
      final feuilles = feuillesStatistiques(
        ctx,
        [ClassePortee(c, novembre), ClassePortee(c, novembre)],
        libelle: 'Novembre',
      );
      final ecole = feuilles.first;
      expect(val(ecole, premiere, 1), 2);
      expect(val(ecole, premiere + 1, 1), s.effectif * 2);
      expect(val(ecole, premiere + 8, 1), s.moyenneClasse! / 100);
    });
  });

  group('admis et non admis', () {
    test('séparés par le seuil d\'admission, numérotés', () {
      final feuilles = feuillesAdmis(ctx, [ClassePortee(c, novembre)], libelle: 'Novembre');
      expect([for (final f in feuilles) f.nom], ['Admis', 'Non admis']);
      final seuil = c.config.seuilAdmission / 100;
      final evalues = c.stats(novembre).evalues;

      List<List<Object?>> corps(FeuilleEcrite f) =>
          [for (var i = premiere; i < f.lignes.length; i++) ligne(f, i)];
      final admis = corps(feuilles.first);
      final non = corps(feuilles.last);
      expect(admis.length + non.length, evalues);
      for (final l in admis) {
        expect(l[6] as double, greaterThanOrEqualTo(seuil));
      }
      for (final l in non) {
        expect(l[6] as double, lessThan(seuil));
      }
      expect([for (final l in admis) l[0]], [for (var i = 1; i <= admis.length; i++) i]);
      // Le parti (SOW, 18/20) et TOURE (sans note) ne figurent dans aucune liste.
      for (final l in [...admis, ...non]) {
        expect(l[3], isNot('SOW'));
        expect(l[3], isNot('TOURE'));
      }
    });
  });

  group('relecture des fichiers produits', () {
    test('toutes les feuilles s\'ouvrent et gardent leurs valeurs', () {
      final feuilles = [
        feuilleNotesClasse(ctx, c, novembre),
        feuilleNotesMatiere(ctx, c, c.matieres.first),
        ...feuillesAbsences(ctx, [ex.eleve(1, 'BARRY')], const {}, const []),
      ];
      final lu = lireClasseur(ecrireClasseur(feuilles));
      expect([for (final f in lu.feuilles) f.nom],
          ['Classe 10e A', 'Notes Maths', 'Totaux', 'Détail']);

      final classe = lu.feuilles.first;
      expect(classe.cellule(0, 0).texte, 'Groupe Scolaire Test');
      expect(classe.cellule(entete, 5).texte, contains('Français'));
      expect(classe.cellule(premiere, 4).nombre, 16.0);
      expect(classe.cellule(premiere, 2).texte, 'BARRY');
      expect(classe.cellule(premiere + 3, 4).vide, isTrue);

      final maths = lu.feuille('Notes Maths')!;
      final iNov = 4 + moisScolaires.indexOf(11);
      expect(maths.cellule(premiere, iNov).nombre, 16.0);
    });
  });
}
