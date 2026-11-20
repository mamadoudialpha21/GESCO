/// Classe d'exemple partagée par les tests des documents (bulletins, classements).
library;

import 'package:gesco/app/calcul_classe.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/modeles.dart';

EleveInscrit eleve(
  int id,
  String nom, {
  StatutInscription statut = StatutInscription.inscrit,
  String? dateNaissance,
}) =>
    EleveInscrit(
      inscriptionId: id,
      eleveId: id,
      classeId: 1,
      classeNom: '10e A',
      matricule: 'M$id',
      nom: nom,
      prenom: 'X',
      sexe: id.isEven ? 'F' : 'M',
      dateNaissance: dateNaissance,
      statut: statut,
    );

MatiereClasse matiere(int id, String nom, {int coefficient = 100, bool facultative = false}) =>
    MatiereClasse(
      id: id,
      classeId: 1,
      nom: nom,
      coefficient: coefficient,
      ordre: id,
      facultative: facultative,
    );

Saisie note(int centiemes) => Saisie.valeur(centiemes);

/// Maths (1), Français (2), Dessin (3, facultative). Novembre = mois 11,
/// janvier = mois 1. Élèves : 1 BARRY, 2 CAMARA, 3 DIALLO, 4 SOW (parti), 5 TOURE.
CalculClasse classe() => CalculClasse(
      classe: ClasseResume(
        classe: const Classe(id: 1, anneeId: 1, niveau: '10e année', nom: '10e A'),
        nbMatieres: 3,
        nbEleves: 5,
      ),
      eleves: [
        eleve(1, 'BARRY', dateNaissance: '2011-03-05'),
        eleve(2, 'CAMARA'),
        eleve(3, 'DIALLO'),
        eleve(4, 'SOW', statut: StatutInscription.depart),
        eleve(5, 'TOURE'),
      ],
      matieres: [
        matiere(1, 'Maths'),
        matiere(2, 'Français'),
        matiere(3, 'Dessin', coefficient: 150, facultative: true),
      ],
      config: ConfigResultats.defaut,
      calendrier: Calendrier.defaut,
      saisies: {
        1: {
          1: {11: note(1600), 1: note(1800)},
          2: {11: note(1600), 1: note(1800)},
          3: {11: note(1200)},
        },
        2: {
          1: {11: note(1400)},
          2: {11: note(1800)},
        },
        3: {
          1: {11: note(1400)},
          2: {11: note(600)},
        },
        4: {
          1: {11: note(1800)},
          2: {11: note(1800)},
        },
      },
    );

const etablissement = Etablissement(
  nom: 'Groupe Scolaire Test',
  adresse: 'Tombolia, Conakry',
  telephone: '622 00 00 00',
  email: 'contact@test.gn',
  devise: 'Travail - Justice - Solidarité',
  infosAdmin: 'Agrément n° 123',
  directeur: 'M. Camara',
);
