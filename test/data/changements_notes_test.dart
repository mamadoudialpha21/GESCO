import 'dart:async';

import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/changements_notes.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_notation.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Services s;
  late int classe;
  late int matiere;
  late int eleve;
  late List<ChangementNotes> recus;
  late StreamSubscription<ChangementNotes> abonnement;

  setUp(() async {
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    s = Services(gdb, session: Session.sansControle(), iterations: 2);
    final annee = (await s.annees.creer('2026-2027', activer: true)).id;
    classe = (await s.classes.creer(anneeId: annee, nom: '7e A', niveauCode: 7)).id;
    matiere = (await s.matieres.ajouter(classeId: classe, nom: 'Maths', coefficient: 100)).id;
    eleve = await s.eleves.inscrire(
      Eleve(matricule: '2026-0001', nom: 'BARRY', prenom: 'Awa', sexe: 'F'),
      anneeId: annee,
      classeId: classe,
    );
    recus = [];
    abonnement = s.notifications.flux.listen(recus.add);
  });

  tearDown(() async {
    await abonnement.cancel();
    await s.notifications.fermer();
    await gdb.fermer();
  });

  Future<void> laisserArriver() => Future<void>.delayed(Duration.zero);

  test('enregistrer une note du mois signale la classe et le mois', () async {
    await s.notes.enregistrer(
      inscriptionId: eleve,
      matiereId: matiere,
      mois: 11,
      saisie: const Saisie.valeur(1400),
    );
    await laisserArriver();
    expect(recus.length, 1);
    expect(recus.single.classeId, classe);
    expect(recus.single.mois, 11);
    expect(recus.single.composition, isFalse);
  });

  test('effacer une note signale aussi', () async {
    await s.notes.enregistrer(
        inscriptionId: eleve, matiereId: matiere, mois: 11, saisie: const Saisie.valeur(1400));
    await s.notes.enregistrer(inscriptionId: eleve, matiereId: matiere, mois: 11, saisie: null);
    await laisserArriver();
    expect(recus.length, 2);
  });

  test('une saisie refusée ne signale rien', () async {
    await expectLater(
      s.notes.enregistrer(
        inscriptionId: 999999, // élève inexistant
        matiereId: matiere,
        mois: 11,
        saisie: const Saisie.valeur(1000),
      ),
      throwsA(isA<ErreurGesco>()),
    );
    await expectLater(
      s.notes.enregistrer(
        inscriptionId: eleve,
        matiereId: matiere,
        mois: 7,
        saisie: const Saisie.valeur(1000),
      ),
      throwsA(isA<ErreurGesco>()),
    );
    await laisserArriver();
    expect(recus, isEmpty);
  });

  test('une composition ou un examen est signalé comme tel, pas un devoir', () async {
    Future<Evaluation> eval(TypeEvaluation type, int mois) => s.evaluations.creer(
          classeId: classe,
          matiereId: matiere,
          mois: mois,
          titre: type.libelle,
          type: type,
        );
    final devoir = await eval(TypeEvaluation.devoir, 10);
    final composition = await eval(TypeEvaluation.composition, 12);
    final examen = await eval(TypeEvaluation.examen, 1);

    await s.evaluations.enregistrerNote(
        evaluationId: devoir.id, inscriptionId: eleve, saisie: const Saisie.valeur(1200));
    await s.evaluations.enregistrerNote(
        evaluationId: composition.id, inscriptionId: eleve, saisie: const Saisie.valeur(1500));
    await s.evaluations.enregistrerLot(examen.id, {eleve: const Saisie.valeur(1000)});
    await laisserArriver();

    expect([for (final c in recus) (c.mois, c.composition)],
        [(10, false), (12, true), (1, true)]);
    expect(recus.every((c) => c.classeId == classe), isTrue);
  });

  test('supprimer une évaluation signale son mois', () async {
    final e = await s.evaluations.creer(
      classeId: classe,
      matiereId: matiere,
      mois: 12,
      titre: 'Devoir',
      type: TypeEvaluation.composition,
    );
    await s.evaluations.supprimer(e.id);
    await laisserArriver();
    expect(recus.single.mois, 12);
    expect(recus.single.composition, isTrue);
  });

  test('modifier le coefficient d\'une évaluation signale son mois', () async {
    final e = await s.evaluations.creer(
      classeId: classe,
      matiereId: matiere,
      mois: 11,
      titre: 'Devoir',
    );
    await s.evaluations.modifier(e.id, coefficient: 200);
    await laisserArriver();
    expect(recus.single.mois, 11);
  });

  test('sans écouteur, les dépôts fonctionnent normalement', () async {
    await abonnement.cancel();
    await s.notes.enregistrer(
        inscriptionId: eleve, matiereId: matiere, mois: 11, saisie: const Saisie.valeur(1400));
    final lues = await s.notes.lireClasse(classe);
    expect(lues[eleve]![matiere]![11]!.centiemes, 1400);
    abonnement = s.notifications.flux.listen(recus.add);
  });

  test('ChangementNotes : description lisible', () {
    expect(const ChangementNotes(3, 11).toString(), contains('classe 3'));
    expect(const ChangementNotes(3, 11, composition: true).toString(), contains('composition'));
  });
}
