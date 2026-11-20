import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/construire_classement.dart';
import 'package:gesco/documents/modele_classement.dart';
import 'package:gesco/domain/calendrier.dart';

import 'classe_exemple.dart';

DocumentClassement classement({
  Portee portee = const Portee.mois(11),
  String periodeLibelle = 'Novembre',
  int? matiereId,
  bool detaillerPeriodes = false,
}) =>
    construireClassement(
      calcul: classe(),
      portee: portee,
      periodeLibelle: periodeLibelle,
      etablissement: etablissement,
      anneeLibelle: '2026-2027',
      matiereId: matiereId,
      detaillerPeriodes: detaillerPeriodes,
      dateEdition: DateTime(2026, 11, 20),
    );

LigneDocClassement ligne(DocumentClassement d, String debutNom) =>
    d.lignes.firstWhere((l) => l.nom.startsWith(debutNom));

void main() {
  group('classement général', () {
    test('titre, classe, année et en-tête de l\'établissement', () {
      final d = classement();
      expect(d.titre, 'CLASSEMENT GÉNÉRAL');
      expect(d.sousTitre, 'Novembre');
      expect(d.classeNom, '10e A');
      expect(d.anneeLibelle, '2026-2027');
      expect(d.libelleMoyenne, 'Moyenne');
      expect(d.avecDecision, isTrue);
      expect(d.periodes, isEmpty);
      expect(d.entete.nom, 'Groupe Scolaire Test');
      expect(d.entete.adresse, 'Tombolia, Conakry');
      expect(d.entete.infosAdmin, 'Agrément n° 123');
      expect(d.directeur, 'M. Camara');
      expect(d.dateEdition, DateTime(2026, 11, 20));
    });

    test('classés par rang avec ex æquo, puis non classés avec leur observation', () {
      final d = classement();
      expect([for (final l in d.lignes) l.nom.split(' ').first],
          ['BARRY', 'CAMARA', 'DIALLO', 'SOW', 'TOURE']);
      expect([for (final l in d.lignes) l.rang], [1, 1, 3, null, null]);
      expect([for (final l in d.lignes) l.exAequo], [true, true, false, false, false]);
      expect([for (final l in d.lignes) l.moyenne], [1600, 1600, 1000, 1800, null]);
      expect([for (final l in d.lignes) l.observation], ['', '', '', 'Parti', 'Sans note']);

      final barry = ligne(d, 'BARRY');
      expect(barry.nom, 'BARRY X');
      expect(barry.matricule, 'M1');
      expect(barry.mention, 'Très bien');
      expect(barry.decision, 'Admis(e)');
    });

    test('statistiques de la classe : élèves actifs seulement', () {
      final s = classement().stats!;
      expect(s.effectif, 4);
      expect(s.evalues, 3);
      expect(s.admis, 3);
      expect(s.moyenneClasse, 1400);
      expect(s.meilleureMoyenne, 1600);
      expect(s.plusFaibleMoyenne, 1000);
    });
  });

  group('classement dans une matière', () {
    test('note sur 20, pas de décision ni de statistiques', () {
      final d = classement(matiereId: 1);
      expect(d.titre, 'CLASSEMENT EN MATHS');
      expect(d.libelleMoyenne, 'Note /20');
      expect(d.avecDecision, isFalse);
      expect(d.stats, isNull);
      expect([for (final l in d.lignes) l.rang], [1, 2, 2, null, null]);
      expect([for (final l in d.lignes) l.moyenne], [1600, 1400, 1400, 1800, null]);
      expect(d.lignes.every((l) => l.decision.isEmpty), isTrue);
    });

    test('les colonnes de périodes sont ignorées', () {
      expect(classement(matiereId: 1, detaillerPeriodes: true).periodes, isEmpty);
    });
  });

  group('résultats annuels', () {
    DocumentClassement annuel() => classement(
          portee: const Portee.annee(),
          periodeLibelle: 'Année entière',
          detaillerPeriodes: true,
        );

    test('titre et colonnes de périodes', () {
      final d = annuel();
      expect(d.titre, 'RÉSULTATS ANNUELS');
      expect(d.periodes, ['Trimestre 1', 'Trimestre 2', 'Trimestre 3']);
      expect(d.sousTitre, 'Année entière');
    });

    test('moyenne de chaque période et moyenne annuelle', () {
      final d = annuel();
      final barry = ligne(d, 'BARRY');
      expect(barry.moyennesPeriodes, [1600, 1800, null]);
      expect(barry.moyenne, 1700);
      expect(barry.rang, 1);
      expect(ligne(d, 'CAMARA').moyennesPeriodes, [1600, null, null]);
      expect(ligne(d, 'TOURE').moyennesPeriodes, [null, null, null]);
    });

    test('sans le détail des périodes : classement annuel simple', () {
      final d = classement(portee: const Portee.annee(), periodeLibelle: 'Année entière');
      expect(d.titre, 'CLASSEMENT GÉNÉRAL');
      expect(d.periodes, isEmpty);
      expect(d.lignes.first.moyennesPeriodes, isEmpty);
    });
  });
}
