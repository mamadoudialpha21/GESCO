import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/calcul_classe.dart';
import 'package:gesco/app/construire_bulletins.dart';
import 'package:gesco/data/depots/appreciation_depot.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/documents/modele_bulletin.dart';
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

List<Bulletin> bulletins({
  Portee portee = const Portee.mois(11),
  TypeBulletin type = TypeBulletin.mensuel,
  String periodeLibelle = 'Novembre',
  Map<int, AppreciationEleve> appreciations = const {},
  Map<int, Map<int, String>> appreciationsMatieres = const {},
  Map<int, Eleve> fiches = const {},
  Set<int>? inscriptions,
  DateTime? dateEdition,
}) =>
    construireBulletins(
      calcul: classe(),
      portee: portee,
      periodeLibelle: periodeLibelle,
      type: type,
      etablissement: etablissement,
      anneeLibelle: '2026-2027',
      appreciations: appreciations,
      appreciationsMatieres: appreciationsMatieres,
      fiches: fiches,
      inscriptions: inscriptions,
      dateEdition: dateEdition,
    );

Bulletin de(List<Bulletin> liste, String nom) => liste.firstWhere((b) => b.eleveNom == nom);

void main() {
  group('élèves concernés', () {
    test('un bulletin par élève actif, dans l\'ordre de la classe', () {
      expect([for (final b in bulletins()) b.eleveNom], ['BARRY', 'CAMARA', 'DIALLO', 'TOURE']);
    });

    test('un élève parti n\'a pas de bulletin, sauf demande explicite', () {
      final sow = bulletins(inscriptions: {4}).single;
      expect(sow.eleveNom, 'SOW');
      // Ses notes figurent, mais il n'est pas classé et ne compte pas dans l'effectif.
      expect(sow.moyenne, 1800);
      expect(sow.rang, isNull);
      expect(sow.effectif, 3);
    });

    test('une sélection garde l\'ordre de la classe', () {
      expect([for (final b in bulletins(inscriptions: {3, 1})) b.eleveNom], ['BARRY', 'DIALLO']);
    });

    test('sélection vide : aucun bulletin', () {
      expect(bulletins(inscriptions: {}), isEmpty);
    });
  });

  group('résultats d\'ensemble', () {
    test('moyenne, rang ex æquo, mention, décision et statistiques de la classe', () {
      final b = de(bulletins(), 'BARRY');
      expect(b.moyenne, 1600);
      expect(b.rang, 1);
      expect(b.exAequo, isTrue);
      expect(b.effectif, 3);
      expect(b.moyenneClasse, 1400);
      expect(b.meilleureMoyenne, 1600);
      expect(b.plusFaibleMoyenne, 1000);
      expect(b.mention, 'Très bien');
      expect(b.decision, 'Admis(e)');
      expect(b.incomplet, isFalse);
    });

    test('le rang suivant saute et n\'est pas ex æquo', () {
      final b = de(bulletins(), 'DIALLO');
      expect(b.moyenne, 1000);
      expect(b.rang, 3);
      expect(b.exAequo, isFalse);
    });

    test('un élève sans note n\'a ni moyenne, ni rang, ni mention', () {
      final b = de(bulletins(), 'TOURE');
      expect(b.moyenne, isNull);
      expect(b.rang, isNull);
      expect(b.exAequo, isFalse);
      expect(b.mention, '');
      expect(b.decision, '');
      expect(b.lignes.every((l) => l.note == null), isTrue);
    });

    test('un mois sans note : aucun classement', () {
      final liste = bulletins(portee: const Portee.mois(12), periodeLibelle: 'Décembre');
      expect(liste.every((b) => b.moyenne == null && b.rang == null), isTrue);
      expect(liste.first.effectif, 0);
      expect(liste.first.moyenneClasse, isNull);
      expect(liste.first.lignes.every((l) => l.moyenneClasse == null), isTrue);
    });
  });

  group('lignes par matière', () {
    test('note, rang et statistiques de la classe, élèves actifs seulement', () {
      final lignes = de(bulletins(), 'BARRY').lignes;
      expect([for (final l in lignes) l.matiere], ['Maths', 'Français', 'Dessin']);

      final maths = lignes[0];
      expect(maths.coefficient, 100);
      expect(maths.note, 1600);
      expect(maths.rang, 1);
      // 1600, 1400, 1400 : la note 18 de l'élève parti est ignorée.
      expect(maths.moyenneClasse, 1467);
      expect(maths.minClasse, 1400);
      expect(maths.maxClasse, 1600);

      final francais = lignes[1];
      expect(francais.note, 1600);
      expect(francais.rang, 2);
      expect(francais.moyenneClasse, 1333);
      expect(francais.minClasse, 600);
      expect(francais.maxClasse, 1800);
    });

    test('matière facultative : signalée, avec son coefficient', () {
      final b = de(bulletins(), 'BARRY');
      final dessin = b.lignes[2];
      expect(dessin.facultative, isTrue);
      expect(dessin.coefficient, 150);
      expect(dessin.note, 1200);
      expect(dessin.rang, 1);
      expect(dessin.moyenneClasse, 1200);
      expect(b.lignes[0].facultative, isFalse);
      // Elle ne change pas la moyenne générale.
      expect(b.moyenne, 1600);
    });

    test('élève sans note dans une matière : note et rang vides', () {
      final dessin = de(bulletins(), 'CAMARA').lignes[2];
      expect(dessin.note, isNull);
      expect(dessin.rang, isNull);
      expect(dessin.moyenneClasse, 1200);
    });
  });

  group('appréciations', () {
    test('générale, décision du conseil et par matière', () {
      final liste = bulletins(
        appreciations: {
          1: const AppreciationEleve(
            appreciation: 'Très bon trimestre.',
            decision: 'Félicitations du conseil',
          ),
        },
        appreciationsMatieres: {
          1: {1: 'Excellent en maths.', 3: 'Appliqué.'},
        },
      );
      final barry = de(liste, 'BARRY');
      expect(barry.appreciation, 'Très bon trimestre.');
      expect(barry.decisionConseil, 'Félicitations du conseil');
      expect(barry.lignes[0].appreciation, 'Excellent en maths.');
      expect(barry.lignes[1].appreciation, '');
      expect(barry.lignes[2].appreciation, 'Appliqué.');

      final camara = de(liste, 'CAMARA');
      expect(camara.appreciation, '');
      expect(camara.decisionConseil, '');
      expect(camara.lignes.every((l) => l.appreciation.isEmpty), isTrue);
    });
  });

  group('en-tête et fiche de l\'élève', () {
    test('établissement, classe, titre et année', () {
      final b = de(bulletins(), 'BARRY');
      expect(b.etablissementNom, 'Groupe Scolaire Test');
      expect(b.adresse, 'Tombolia, Conakry');
      expect(b.telephone, '622 00 00 00');
      expect(b.email, 'contact@test.gn');
      expect(b.devise, 'Travail - Justice - Solidarité');
      expect(b.infosAdmin, 'Agrément n° 123');
      expect(b.directeur, 'M. Camara');
      expect(b.classeNom, '10e A');
      expect(b.niveau, '10e année');
      expect(b.anneeLibelle, '2026-2027');
      expect(b.periodeLibelle, 'Novembre');
      expect(b.titre, 'BULLETIN DU MOIS DE NOVEMBRE');
      expect(b.matricule, 'M1');
      expect(b.nomComplet, 'BARRY X');
    });

    test('sans fiche : la date d\'inscription suffit, pas de photo ni de lieu', () {
      final b = de(bulletins(), 'BARRY');
      expect(b.dateNaissance, '2011-03-05');
      expect(b.lieuNaissance, '');
      expect(b.photo, isNull);
      expect(b.naissance, 'Né le 05/03/2011');
      expect(de(bulletins(), 'CAMARA').naissance, '');
    });

    test('avec la fiche : lieu de naissance et photo', () {
      final photo = Uint8List.fromList([1, 2, 3]);
      final fiche = Eleve(
        id: 1,
        matricule: 'M1',
        nom: 'BARRY',
        prenom: 'X',
        sexe: 'M',
        dateNaissance: '2011-03-05',
        lieuNaissance: 'Conakry',
        photo: photo,
      );
      final b = de(bulletins(fiches: {1: fiche}), 'BARRY');
      expect(b.photo, photo);
      expect(b.naissance, 'Né le 05/03/2011 à Conakry');
    });

    test('la date d\'édition demandée est reportée', () {
      final date = DateTime(2026, 11, 20);
      expect(bulletins(dateEdition: date).every((b) => b.dateEdition == date), isTrue);
    });
  });

  group('bulletin annuel', () {
    test('récapitulatif des périodes et moyenne annuelle', () {
      final b = de(
        bulletins(
          portee: const Portee.annee(),
          type: TypeBulletin.annuel,
          periodeLibelle: 'Année scolaire',
        ),
        'BARRY',
      );
      expect([for (final p in b.periodes) p.libelle], ['Trimestre 1', 'Trimestre 2', 'Trimestre 3']);
      expect([for (final p in b.periodes) p.moyenne], [1600, 1800, null]);
      expect([for (final p in b.periodes) p.rang], [1, 1, null]);
      // Moyenne des périodes qui ont une moyenne : (16 + 18) / 2.
      expect(b.moyenne, 1700);
      expect(b.rang, 1);
      expect(b.titre, 'BULLETIN ANNUEL');
    });

    test('mensuel et trimestriel : pas de récapitulatif', () {
      expect(de(bulletins(), 'BARRY').periodes, isEmpty);
      final t1 = bulletins(
        portee: Portee.periode(Calendrier.defaut.periodes.first),
        type: TypeBulletin.periodique,
        periodeLibelle: 'Trimestre 1',
      );
      expect(de(t1, 'BARRY').periodes, isEmpty);
      expect(de(t1, 'BARRY').titre, 'BULLETIN DU TRIMESTRE 1');
    });
  });
}
