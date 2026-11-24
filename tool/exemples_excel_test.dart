// Produit des classeurs Excel d'exemple dans `captures/`.
//
// Sert à vérifier le rendu réel des fichiers (styles, largeurs, cases à
// remplir) : la CI les publie sur la branche « captures ».
//
// Lancer :  flutter test tool/exemples_excel_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/data/modeles_absences.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_notation.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/import_export/exports_excel.dart';
import 'package:gesco/import_export/liste_vierge.dart';
import 'package:gesco/import_export/modele_export.dart';
import 'package:gesco/tableur/xlsx.dart';

import '../test/app/classe_exemple.dart' as ex;

void main() {
  test('classeurs Excel d\'exemple', () {
    final dossier = Directory('captures')..createSync(recursive: true);
    final ctx = ContexteExport(
      etablissement: 'Groupe Scolaire Nialy International',
      annee: '2026-2027',
      date: DateTime(2026, 11, 22),
    );
    final c = ex.classe();
    const novembre = Portee.mois(11);
    final classes = [ClassePortee(c, novembre)];

    final eleves = [
      for (final e in c.eleves)
        EleveExport(
          eleve: Eleve(
            matricule: e.matricule,
            nom: e.nom,
            prenom: e.prenom,
            sexe: e.sexe,
            dateNaissance: e.dateNaissance,
            lieuNaissance: 'Conakry',
            adresse: 'Tombolia',
            telephone: '622000001',
            nomPere: 'Alpha Barry',
            contactParent: '622000002',
          ),
          inscription: e,
        ),
    ];

    final feuilles = [
      feuilleEleves(ctx, 'Élèves', 'Liste complète des élèves', eleves),
      feuilleNotesClasse(ctx, c, novembre),
      feuilleNotesMatiere(ctx, c, c.matieres.first),
      feuilleResultats(ctx, c, const Portee.annee()),
      feuilleClassement(ctx, c, novembre),
      ...feuillesStatistiques(ctx, classes, libelle: 'Novembre'),
      ...feuillesAdmis(ctx, classes, libelle: 'Novembre'),
      ...feuillesAbsences(
        ctx,
        [ex.eleve(1, 'BARRY'), ex.eleve(2, 'CAMARA')],
        const {
          1: TotauxAbsences(
            absences: 3,
            absencesJustifiees: 1,
            retards: 2,
            retardsJustifies: 1,
            minutesRetard: 25,
          ),
        },
        const [
          Absence(
            inscriptionId: 1,
            date: '2026-11-03',
            justifiee: true,
            motif: 'Paludisme',
            eleveNom: 'BARRY X',
            matricule: 'M1',
            classeNom: '10e A',
          ),
        ],
      ),
    ];
    File('${dossier.path}/export_exemple.xlsx').writeAsBytesSync(ecrireClasseur(feuilles));

    const classe = Classe(id: 1, anneeId: 1, niveau: '10e année', nom: '10e A');
    MatiereClasse matiere(int id, String nom) => MatiereClasse(
          id: id,
          classeId: 1,
          nom: nom,
          coefficient: 100,
          ordre: id,
          enseignantId: 7,
        );
    const colonnes = [
      ColonneVierge(
        titre: 'Interrogation 1',
        type: TypeEvaluation.interrogation,
        mois: 11,
        bareme: 20,
      ),
      ColonneVierge(
        titre: 'Interrogation 2',
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
      ),
    ];
    final liste = ListeVierge(
      classe: classe,
      enseignantId: 7,
      enseignantNom: 'DIALLO Aminata',
      eleves: [
        for (var i = 1; i <= 12; i++)
          EleveInscrit(
            inscriptionId: i,
            eleveId: i,
            classeId: 1,
            classeNom: '10e A',
            matricule: '2026-${i.toString().padLeft(4, '0')}',
            nom: 'ELEVE$i',
            prenom: 'Prénom$i',
            sexe: 'M',
          ),
      ],
      matieres: [
        MatiereVierge(matiere: matiere(1, 'Mathématiques'), colonnes: colonnes),
        MatiereVierge(matiere: matiere(2, 'Français'), colonnes: colonnes),
      ],
    );
    File('${dossier.path}/liste_vierge_exemple.xlsx')
        .writeAsBytesSync(ecrireClasseur(construireListeVierge(ctx, liste, mois: 11)));
  });
}
