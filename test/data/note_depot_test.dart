import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/depots/annee_depot.dart';
import 'package:gesco/data/depots/classe_depot.dart';
import 'package:gesco/data/depots/eleve_depot.dart';
import 'package:gesco/data/depots/matiere_depot.dart';
import 'package:gesco/data/depots/note_depot.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher erreurContenant(String texte) => throwsA(
      isA<ErreurGesco>().having((e) => e.message, 'message', contains(texte)),
    );

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Database db;
  late NoteDepot notes;
  late EleveDepot eleves;
  late int anneeId;
  late Classe classeA;
  late Classe classeB;
  late MatiereClasse maths;
  late MatiereClasse francais;
  late MatiereClasse matiereB;
  late int aminata;
  late int ibrahima;
  late int eleveB;

  setUp(() async {
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    db = gdb.db;
    final horloge = DateTime(2026, 11, 5, 9, 30);
    final annees = AnneeDepot(db, maintenant: () => horloge);
    final classes = ClasseDepot(db);
    final matieres = MatiereDepot(db);
    eleves = EleveDepot(db, maintenant: () => horloge);
    notes = NoteDepot(db, maintenant: () => horloge);

    anneeId = (await annees.creer('2026-2027')).id;
    classeA = await classes.creer(anneeId: anneeId, nom: '10e A');
    classeB = await classes.creer(anneeId: anneeId, nom: '10e B');
    maths = await matieres.ajouter(classeId: classeA.id, nom: 'Maths', coefficient: 400);
    francais =
        await matieres.ajouter(classeId: classeA.id, nom: 'Français', coefficient: 300);
    matiereB = await matieres.ajouter(classeId: classeB.id, nom: 'Maths', coefficient: 400);

    Future<int> inscrire(String matricule, String nom, int classeId) =>
        eleves.inscrire(
          Eleve(matricule: matricule, nom: nom, prenom: 'X', sexe: 'F'),
          anneeId: anneeId,
          classeId: classeId,
        );
    aminata = await inscrire('2026-0001', 'DIALLO', classeA.id);
    ibrahima = await inscrire('2026-0002', 'BARRY', classeA.id);
    eleveB = await inscrire('2026-0003', 'SOW', classeB.id);
  });

  tearDown(() async => gdb.fermer());

  Future<void> noter(int inscription, int matiere, int mois, Saisie? s) =>
      notes.enregistrer(
        inscriptionId: inscription,
        matiereId: matiere,
        mois: mois,
        saisie: s,
      );

  group('enregistrer et lire', () {
    test('une classe sans note donne une lecture vide', () async {
      expect(await notes.lireClasse(classeA.id), isEmpty);
      expect(await notes.compterClasse(classeA.id), 0);
      expect(await notes.compterAnnee(anneeId), 0);
    });

    test('une note enregistrée est relue à l\'identique (en centièmes)', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1475));
      final lu = await notes.lireClasse(classeA.id);
      final s = lu[aminata]![maths.id]![10]!;
      expect(s.etat, EtatNote.saisie);
      expect(s.centiemes, 1475);
    });

    test('zéro est conservé comme une vraie note', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(0));
      final s = (await notes.lireClasse(classeA.id))[aminata]![maths.id]![10]!;
      expect(s.estNumerique, isTrue);
      expect(s.centiemes, 0);
    });

    test('absent et dispensé n\'ont pas de valeur', () async {
      await noter(aminata, maths.id, 10, const Saisie.absent());
      await noter(aminata, francais.id, 10, const Saisie.dispense());
      final lu = (await notes.lireClasse(classeA.id))[aminata]!;
      expect(lu[maths.id]![10]!.etat, EtatNote.absent);
      expect(lu[maths.id]![10]!.centiemes, isNull);
      expect(lu[francais.id]![10]!.etat, EtatNote.dispense);
      expect(lu[francais.id]![10]!.centiemes, isNull);
    });

    test('modifier une note remplace l\'ancienne (une seule ligne par case)', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      await noter(aminata, maths.id, 10, const Saisie.valeur(1250));
      expect(await notes.compterClasse(classeA.id), 1);
      final s = (await notes.lireClasse(classeA.id))[aminata]![maths.id]![10]!;
      expect(s.centiemes, 1250);
    });

    test('une note peut devenir absent puis redevenir une note', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      await noter(aminata, maths.id, 10, const Saisie.absent());
      var s = (await notes.lireClasse(classeA.id))[aminata]![maths.id]![10]!;
      expect(s.etat, EtatNote.absent);
      await noter(aminata, maths.id, 10, const Saisie.valeur(800));
      s = (await notes.lireClasse(classeA.id))[aminata]![maths.id]![10]!;
      expect(s.centiemes, 800);
      expect(await notes.compterClasse(classeA.id), 1);
    });

    test('vider une case supprime la note (« non saisie », jamais zéro)', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      await noter(aminata, maths.id, 10, null);
      expect(await notes.lireClasse(classeA.id), isEmpty);
      expect(await notes.compterClasse(classeA.id), 0);
    });

    test('vider une case déjà vide ne fait rien', () async {
      await noter(aminata, maths.id, 10, null);
      expect(await notes.compterClasse(classeA.id), 0);
    });

    test('les mois et les matières sont indépendants', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      await noter(aminata, maths.id, 11, const Saisie.valeur(1100));
      await noter(aminata, francais.id, 10, const Saisie.valeur(1200));
      await noter(ibrahima, maths.id, 10, const Saisie.valeur(1300));
      final lu = await notes.lireClasse(classeA.id);
      expect(lu[aminata]![maths.id]![10]!.centiemes, 1000);
      expect(lu[aminata]![maths.id]![11]!.centiemes, 1100);
      expect(lu[aminata]![francais.id]![10]!.centiemes, 1200);
      expect(lu[ibrahima]![maths.id]![10]!.centiemes, 1300);
      expect(await notes.compterClasse(classeA.id), 4);
    });

    test('les 9 mois de l\'année scolaire sont acceptés', () async {
      for (final mois in [10, 11, 12, 1, 2, 3, 4, 5, 6]) {
        await noter(aminata, maths.id, mois, Saisie.valeur(mois * 100));
      }
      final lu = (await notes.lireClasse(classeA.id))[aminata]![maths.id]!;
      expect(lu.keys.toSet(), {10, 11, 12, 1, 2, 3, 4, 5, 6});
      expect(lu[6]!.centiemes, 600);
    });

    test('une classe ne voit pas les notes d\'une autre classe', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      await noter(eleveB, matiereB.id, 10, const Saisie.valeur(1600));
      final a = await notes.lireClasse(classeA.id);
      final b = await notes.lireClasse(classeB.id);
      expect(a.keys, [aminata]);
      expect(b.keys, [eleveB]);
      expect(await notes.compterClasse(classeA.id), 1);
      expect(await notes.compterClasse(classeB.id), 1);
      expect(await notes.compterAnnee(anneeId), 2);
    });

    test('la date de modification est enregistrée', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      final lignes = await db.query('note');
      expect(lignes.single['modifie_le'], '2026-11-05T09:30:00.000');
    });
  });

  group('refus', () {
    test('mois hors de l\'année scolaire', () async {
      for (final mois in [0, 7, 8, 9, 13]) {
        await expectLater(
          noter(aminata, maths.id, mois, const Saisie.valeur(1000)),
          erreurContenant('hors de l\'année scolaire'),
          reason: 'mois $mois',
        );
      }
      expect(await notes.compterClasse(classeA.id), 0);
    });

    test('matière d\'une autre classe', () async {
      await expectLater(
        noter(aminata, matiereB.id, 10, const Saisie.valeur(1000)),
        erreurContenant('n\'appartient pas à la classe'),
      );
      expect(await notes.compterAnnee(anneeId), 0);
    });

    test('élève ou matière inexistants', () async {
      await expectLater(
        noter(99999, maths.id, 10, const Saisie.valeur(1000)),
        throwsA(isA<ErreurGesco>()),
      );
      await expectLater(
        noter(aminata, 99999, 10, const Saisie.valeur(1000)),
        throwsA(isA<ErreurGesco>()),
      );
    });

    test('une note refusée ne modifie pas la note existante', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      await expectLater(
        noter(aminata, maths.id, 7, const Saisie.valeur(1500)),
        throwsA(isA<ErreurGesco>()),
      );
      final s = (await notes.lireClasse(classeA.id))[aminata]![maths.id]![10]!;
      expect(s.centiemes, 1000);
    });
  });

  group('lien avec les autres données', () {
    test('un élève qui a des notes ne peut pas changer de classe', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      expect(await eleves.compterNotes(aminata), 1);
      await expectLater(
        db.update('inscription', {'classe_id': classeB.id},
            where: 'id = ?', whereArgs: [aminata]),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('supprimer l\'élève (avec accord) supprime ses notes', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      await noter(ibrahima, maths.id, 10, const Saisie.valeur(1200));
      await eleves.supprimerInscription(aminata, avecNotes: true);
      final lu = await notes.lireClasse(classeA.id);
      expect(lu.keys, [ibrahima]);
      expect(await notes.compterClasse(classeA.id), 1);
    });

    test('supprimer une matière qui a des notes est refusé par la base', () async {
      await noter(aminata, maths.id, 10, const Saisie.valeur(1000));
      await expectLater(
        db.delete('matiere_classe', where: 'id = ?', whereArgs: [maths.id]),
        throwsA(isA<DatabaseException>()),
      );
      expect(await notes.compterClasse(classeA.id), 1);
    });

    test('une valeur hors de 0 à 20 est refusée avant la base', () async {
      await expectLater(
        noter(aminata, maths.id, 10, const Saisie.valeur(1000))
            .then((_) => notes.enregistrer(
                  inscriptionId: aminata,
                  matiereId: maths.id,
                  mois: 10,
                  saisie: const _SaisieHorsLimite(),
                )),
        erreurContenant('entre 0 et 20'),
      );
    });
  });
}

/// Saisie invalide fabriquée pour tester la défense de la couche données
/// (les constructeurs de [Saisie] refusent déjà ces valeurs).
class _SaisieHorsLimite implements Saisie {
  const _SaisieHorsLimite();

  @override
  EtatNote get etat => EtatNote.saisie;

  @override
  int? get centiemes => 2500;

  @override
  bool get estNumerique => true;
}
