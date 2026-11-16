import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/data/depots/annee_depot.dart';
import 'package:gesco/data/depots/classe_depot.dart';
import 'package:gesco/data/depots/config_resultats_depot.dart';
import 'package:gesco/data/depots/etablissement_depot.dart';
import 'package:gesco/data/depots/matiere_depot.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/images.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Vérifie qu'une action échoue avec une [ErreurGesco] dont le message
/// contient [texte].
Matcher erreurContenant(String texte) => throwsA(
      isA<ErreurGesco>().having((e) => e.message, 'message', contains(texte)),
    );

final Matcher uneErreur = throwsA(isA<ErreurGesco>());

const List<int> _signaturePng = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

Uint8List imagePng([int taille = 12]) {
  final octets = Uint8List(taille);
  octets.setRange(0, _signaturePng.length, _signaturePng);
  return octets;
}

Uint8List imageJpeg() => Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Database db;
  late EtablissementDepot etablissements;
  late AnneeDepot annees;
  late ConfigResultatsDepot configs;
  late ClasseDepot classes;
  late MatiereDepot matieres;

  setUp(() async {
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    db = gdb.db;
    etablissements = EtablissementDepot(db);
    annees = AnneeDepot(db, maintenant: () => DateTime.utc(2026, 10, 1, 8));
    configs = ConfigResultatsDepot(db);
    classes = ClasseDepot(db);
    matieres = MatiereDepot(db);
  });

  tearDown(() async {
    await gdb.fermer();
  });

  /// Inscrit un nouvel élève dans une classe et retourne l'id d'inscription.
  Future<int> inscrireEleve(int classeId, int anneeId, String matricule) async {
    final eleve = await db.insert('eleve', {
      'matricule': matricule,
      'nom': 'DIALLO',
      'prenom': 'Aminata',
      'sexe': 'F',
    });
    return db.insert('inscription', {
      'eleve_id': eleve,
      'classe_id': classeId,
      'annee_id': anneeId,
      'date_inscription': '2026-10-01',
    });
  }

  Future<int> ajouterNote(int inscription, int matiere, int mois, int valeur) =>
      db.insert('note', {
        'inscription_id': inscription,
        'matiere_id': matiere,
        'mois': mois,
        'etat': 'saisie',
        'valeur': valeur,
        'modifie_le': '2026-10-02',
      });

  group('établissement', () {
    test('fiche vide sur une base neuve', () async {
      final e = await etablissements.lire();
      expect(e.nom, '');
      expect(e.adresse, '');
      expect(e.logo, isNull);
    });

    test('enregistrer puis relire (espaces superflus retirés)', () async {
      final logo = imagePng();
      await etablissements.enregistrer(
        Etablissement(
          nom: '  Groupe Scolaire Test  ',
          adresse: 'Tombolia, Conakry',
          telephone: '+224 600 00 00 00',
          email: 'contact@ecole.gn',
          logo: logo,
        ),
      );
      final e = await etablissements.lire();
      expect(e.nom, 'Groupe Scolaire Test');
      expect(e.adresse, 'Tombolia, Conakry');
      expect(e.telephone, '+224 600 00 00 00');
      expect(e.email, 'contact@ecole.gn');
      expect(e.logo, logo);
    });

    test('un logo JPEG est accepté', () async {
      await etablissements.enregistrer(Etablissement(nom: 'X', logo: imageJpeg()));
      expect((await etablissements.lire()).logo, imageJpeg());
    });

    test('supprimer le logo', () async {
      await etablissements.enregistrer(Etablissement(nom: 'X', logo: imagePng()));
      final avec = await etablissements.lire();
      expect(avec.logo, isNotNull);
      await etablissements.enregistrer(avec.copyWith(supprimerLogo: true));
      final sans = await etablissements.lire();
      expect(sans.logo, isNull);
      expect(sans.nom, 'X');
    });

    test('un fichier qui n\'est pas une image est refusé, rien n\'est modifié',
        () async {
      await expectLater(
        etablissements.enregistrer(
          Etablissement(nom: 'Nouveau', logo: Uint8List.fromList([1, 2, 3, 4])),
        ),
        erreurContenant('PNG ou JPEG'),
      );
      expect((await etablissements.lire()).nom, '');
    });

    test('logo vide refusé', () async {
      await expectLater(
        etablissements.enregistrer(Etablissement(logo: Uint8List(0))),
        uneErreur,
      );
    });

    test('limite de taille : exactement 2 Mo accepté, 1 octet de plus refusé',
        () async {
      await etablissements.enregistrer(
        Etablissement(nom: 'Limite', logo: imagePng(tailleMaxLogo)),
      );
      expect((await etablissements.lire()).logo!.length, tailleMaxLogo);
      await expectLater(
        etablissements.enregistrer(
          Etablissement(nom: 'Trop gros', logo: imagePng(tailleMaxLogo + 1)),
        ),
        erreurContenant('trop volumineux'),
      );
      expect((await etablissements.lire()).nom, 'Limite');
    });
  });

  group('années scolaires', () {
    test('la première année créée devient active', () async {
      final a = await annees.creer('2025-2026');
      expect(a.active, isTrue);
      expect((await annees.active())!.libelle, '2025-2026');
    });

    test('une année suivante n\'est pas active par défaut', () async {
      await annees.creer('2025-2026');
      final b = await annees.creer('2026-2027');
      expect(b.active, isFalse);
      expect((await annees.active())!.libelle, '2025-2026');
    });

    test('créer avec « activer » bascule l\'année active', () async {
      await annees.creer('2025-2026');
      await annees.creer('2026-2027', activer: true);
      expect((await annees.active())!.libelle, '2026-2027');
      final actives = (await annees.lister()).where((a) => a.active);
      expect(actives.length, 1);
    });

    test('activer une année existante', () async {
      final a = await annees.creer('2025-2026');
      final b = await annees.creer('2026-2027');
      await annees.activer(b.id);
      expect((await annees.active())!.id, b.id);
      await annees.activer(a.id);
      expect((await annees.active())!.id, a.id);
      expect((await annees.lister()).where((x) => x.active).length, 1);
    });

    test('activer une année inconnue est refusé', () async {
      await annees.creer('2025-2026');
      await expectLater(annees.activer(999), uneErreur);
      expect((await annees.active())!.libelle, '2025-2026');
    });

    test('libellé vide, trop long ou en double refusé', () async {
      await annees.creer('2025-2026');
      await expectLater(annees.creer(''), erreurContenant('obligatoire'));
      await expectLater(annees.creer('   '), erreurContenant('obligatoire'));
      await expectLater(annees.creer('x' * 31), erreurContenant('trop long'));
      await expectLater(annees.creer('2025-2026'), erreurContenant('existe déjà'));
      await expectLater(annees.creer(' 2025-2026 '), erreurContenant('existe déjà'));
      expect((await annees.lister()).length, 1);
    });

    test('le libellé est nettoyé et la date de création est enregistrée',
        () async {
      final a = await annees.creer('  2026-2027 ');
      expect(a.libelle, '2026-2027');
      expect(a.creeLe, '2026-10-01T08:00:00.000Z');
    });

    test('lister : la plus récente d\'abord', () async {
      await annees.creer('2025-2026');
      await annees.creer('2027-2028');
      await annees.creer('2026-2027');
      final libelles = (await annees.lister()).map((a) => a.libelle);
      expect(libelles, ['2027-2028', '2026-2027', '2025-2026']);
    });

    test('chaque année reçoit des seuils par défaut', () async {
      final a = await annees.creer('2025-2026');
      final c = await configs.lire(a.id);
      expect(c.toJson(), ConfigResultats.defaut.toJson());
    });

    test(
        'créer une année en copiant la précédente : classes, matières et '
        'seuils recopiés, jamais les élèves ni les notes', () async {
      final a1 = await annees.creer('2025-2026');
      final classe = await classes.creer(
        anneeId: a1.id,
        nom: '10e A',
        niveau: '10e année',
      );
      final maths = await matieres.ajouter(
        classeId: classe.id,
        nom: 'Mathématiques',
        coefficient: 400,
      );
      await matieres.ajouter(
        classeId: classe.id,
        nom: 'Français',
        coefficient: 250,
      );
      final inscription = await inscrireEleve(classe.id, a1.id, 'M001');
      await ajouterNote(inscription, maths.id, 10, 1500);
      const perso = ConfigResultats(
        seuilAdmission: 900,
        seuilBon: 1400,
        mentions: [Palier(1400, 'Bien')],
        decisionsPeriode: [Palier(0, 'Non'), Palier(900, 'Oui')],
        decisionsAnnee: [Palier(0, 'Redouble'), Palier(900, 'Passe')],
      );
      await configs.enregistrer(a1.id, perso);

      final a2 = await annees.creer('2026-2027', copierDepuisAnneeId: a1.id);

      final classes2 = await classes.lister(a2.id);
      expect(classes2.length, 1);
      expect(classes2.first.classe.nom, '10e A');
      expect(classes2.first.classe.niveau, '10e année');
      expect(classes2.first.classe.id, isNot(classe.id));
      expect(classes2.first.nbMatieres, 2);
      expect(classes2.first.nbEleves, 0);
      final m2 = await matieres.lister(classes2.first.classe.id);
      expect(m2.map((m) => m.nom), ['Mathématiques', 'Français']);
      expect(m2.map((m) => m.coefficient), [400, 250]);
      expect((await configs.lire(a2.id)).toJson(), perso.toJson());

      // L'année source est restée intacte.
      final classes1 = await classes.lister(a1.id);
      expect(classes1.first.nbEleves, 1);
      expect(classes1.first.nbMatieres, 2);
      expect((await db.query('note')).length, 1);
      expect((await db.query('inscription')).length, 1);
    });

    test('copier une année inconnue : refusé, rien n\'est créé', () async {
      await annees.creer('2025-2026');
      await expectLater(
        annees.creer('2026-2027', copierDepuisAnneeId: 999),
        erreurContenant('introuvable'),
      );
      expect((await annees.lister()).length, 1);
      expect(await db.query('config_resultats'), hasLength(1));
    });

    test('supprimer : année active refusée', () async {
      final a = await annees.creer('2025-2026');
      await expectLater(annees.supprimer(a.id), erreurContenant('année active'));
      expect((await annees.lister()).length, 1);
    });

    test('supprimer : année qui contient des classes refusée', () async {
      await annees.creer('2025-2026');
      final b = await annees.creer('2026-2027');
      await classes.creer(anneeId: b.id, nom: '10e A');
      await expectLater(annees.supprimer(b.id), erreurContenant('1 classe'));
      expect((await annees.lister()).length, 2);
    });

    test('supprimer : année vide et inactive supprimée avec ses seuils',
        () async {
      await annees.creer('2025-2026');
      final b = await annees.creer('2026-2027');
      await annees.supprimer(b.id);
      expect((await annees.lister()).map((a) => a.libelle), ['2025-2026']);
      expect(
        await db.query('config_resultats', where: 'annee_id = ?', whereArgs: [b.id]),
        isEmpty,
      );
    });

    test('supprimer une année inconnue est refusé', () async {
      await expectLater(annees.supprimer(999), uneErreur);
    });
  });

  group('seuils de mentions et de décisions', () {
    const perso = ConfigResultats(
      seuilAdmission: 950,
      seuilBon: 1300,
      mentions: [Palier(1300, 'Satisfaisant'), Palier(1700, 'Brillant')],
      decisionsPeriode: [Palier(0, 'Insuffisant'), Palier(950, 'Suffisant')],
      decisionsAnnee: [Palier(0, 'Redouble'), Palier(950, 'Passe')],
    );

    test('année sans configuration enregistrée : valeurs par défaut', () async {
      final id = await db.insert('annee_scolaire', {
        'libelle': '2020-2021',
        'active': 0,
        'cree_le': '2020-10-01',
      });
      expect((await configs.lire(id)).toJson(), ConfigResultats.defaut.toJson());
    });

    test('enregistrer puis relire sans perte', () async {
      final a = await annees.creer('2025-2026');
      await configs.enregistrer(a.id, perso);
      final relue = await configs.lire(a.id);
      expect(relue.toJson(), perso.toJson());
      expect(relue.mention(1750), 'Brillant');
      expect(relue.decisionAnnee(949), 'Redouble');
    });

    test('chaque année a sa propre configuration', () async {
      final a1 = await annees.creer('2025-2026');
      final a2 = await annees.creer('2026-2027');
      await configs.enregistrer(a2.id, perso);
      expect((await configs.lire(a1.id)).toJson(), ConfigResultats.defaut.toJson());
      expect((await configs.lire(a2.id)).toJson(), perso.toJson());
    });

    test('configuration invalide refusée, ancienne valeur conservée', () async {
      final a = await annees.creer('2025-2026');
      await configs.enregistrer(a.id, perso);
      const mauvaise = ConfigResultats(
        seuilAdmission: 1000,
        seuilBon: 900,
        mentions: [],
        decisionsPeriode: [Palier(1000, 'Admis')],
        decisionsAnnee: [Palier(0, 'Redouble')],
      );
      await expectLater(
        configs.enregistrer(a.id, mauvaise),
        erreurContenant('seuil « bon »'),
      );
      expect((await configs.lire(a.id)).toJson(), perso.toJson());
    });

    test('configuration illisible : message clair', () async {
      final a = await annees.creer('2025-2026');
      await db.update(
        'config_resultats',
        {'json': 'pas du json'},
        where: 'annee_id = ?',
        whereArgs: [a.id],
      );
      await expectLater(configs.lire(a.id), erreurContenant('illisible'));
    });
  });

  group('classes', () {
    late int anneeId;

    setUp(() async {
      anneeId = (await annees.creer('2025-2026')).id;
    });

    test('créer et lister (tri par niveau puis nom)', () async {
      await classes.creer(anneeId: anneeId, nom: '10e B', niveau: '10e année');
      await classes.creer(anneeId: anneeId, nom: '2nde', niveau: '9e');
      await classes.creer(anneeId: anneeId, nom: '10e A', niveau: '10e année');
      final noms = (await classes.lister(anneeId)).map((r) => r.classe.nom);
      expect(noms, ['10e A', '10e B', '2nde']);
    });

    test('effectifs : matières et élèves', () async {
      final c = await classes.creer(anneeId: anneeId, nom: '10e A');
      await matieres.ajouter(classeId: c.id, nom: 'Maths', coefficient: 400);
      await matieres.ajouter(classeId: c.id, nom: 'Français', coefficient: 300);
      await inscrireEleve(c.id, anneeId, 'M001');
      await inscrireEleve(c.id, anneeId, 'M002');
      final r = (await classes.lister(anneeId)).single;
      expect(r.nbMatieres, 2);
      expect(r.nbEleves, 2);
    });

    test('nom vide ou trop long refusé ; niveau trop long refusé', () async {
      await expectLater(
        classes.creer(anneeId: anneeId, nom: '  '),
        erreurContenant('obligatoire'),
      );
      await expectLater(
        classes.creer(anneeId: anneeId, nom: 'x' * 61),
        erreurContenant('trop long'),
      );
      await expectLater(
        classes.creer(anneeId: anneeId, nom: 'OK', niveau: 'n' * 61),
        erreurContenant('trop long'),
      );
      expect(await classes.lister(anneeId), isEmpty);
    });

    test('doublon refusé sans tenir compte de la casse, permis dans une autre année',
        () async {
      await classes.creer(anneeId: anneeId, nom: '10e A');
      await expectLater(
        classes.creer(anneeId: anneeId, nom: '10E a'),
        erreurContenant('existe déjà'),
      );
      final autre = await annees.creer('2026-2027');
      await classes.creer(anneeId: autre.id, nom: '10e A');
      expect((await classes.lister(autre.id)).length, 1);
    });

    test('doublon détecté aussi avec des lettres accentuées majuscules', () async {
      await classes.creer(anneeId: anneeId, nom: 'Étude A');
      await expectLater(
        classes.creer(anneeId: anneeId, nom: 'étude a'),
        erreurContenant('existe déjà'),
      );
      expect((await classes.lister(anneeId)).length, 1);
    });

    test('année inconnue refusée', () async {
      await expectLater(
        classes.creer(anneeId: 999, nom: '10e A'),
        erreurContenant('introuvable'),
      );
    });

    test('aucune limite artificielle au nombre de classes', () async {
      for (var i = 1; i <= 40; i++) {
        await classes.creer(anneeId: anneeId, nom: 'Classe $i');
      }
      expect((await classes.lister(anneeId)).length, 40);
    });

    test('modifier le nom et le niveau', () async {
      final c = await classes.creer(anneeId: anneeId, nom: '10e A');
      await classes.modifier(c.id, nom: '10e Alpha', niveau: '10e année');
      final r = (await classes.lister(anneeId)).single;
      expect(r.classe.nom, '10e Alpha');
      expect(r.classe.niveau, '10e année');
    });

    test('modifier : garder le même nom est permis, un doublon est refusé',
        () async {
      final a = await classes.creer(anneeId: anneeId, nom: '10e A');
      await classes.creer(anneeId: anneeId, nom: '10e B');
      await classes.modifier(a.id, nom: '10e A', niveau: 'Nouveau niveau');
      await expectLater(
        classes.modifier(a.id, nom: '10e B', niveau: ''),
        erreurContenant('existe déjà'),
      );
      expect((await classes.obtenir(a.id))!.nom, '10e A');
    });

    test('modifier une classe inconnue est refusé', () async {
      await expectLater(
        classes.modifier(999, nom: 'X', niveau: ''),
        erreurContenant('introuvable'),
      );
    });

    test('supprimer une classe vide supprime aussi ses matières', () async {
      final c = await classes.creer(anneeId: anneeId, nom: '10e A');
      await matieres.ajouter(classeId: c.id, nom: 'Maths', coefficient: 400);
      await classes.supprimer(c.id);
      expect(await classes.lister(anneeId), isEmpty);
      expect(await db.query('matiere_classe'), isEmpty);
    });

    test('supprimer une classe qui a des élèves est refusé', () async {
      final c = await classes.creer(anneeId: anneeId, nom: '10e A');
      await inscrireEleve(c.id, anneeId, 'M001');
      await expectLater(classes.supprimer(c.id), erreurContenant('1 élève'));
      expect((await classes.lister(anneeId)).length, 1);
    });

    test('supprimer une classe inconnue est refusé', () async {
      await expectLater(classes.supprimer(999), erreurContenant('introuvable'));
    });
  });

  group('matières et coefficients', () {
    late int anneeId;
    late Classe classe;

    setUp(() async {
      anneeId = (await annees.creer('2025-2026')).id;
      classe = await classes.creer(anneeId: anneeId, nom: '10e A');
    });

    Future<List<String>> noms([Classe? c]) async =>
        [for (final m in await matieres.lister((c ?? classe).id)) m.nom];

    test('ajouter : ordre d\'affichage croissant', () async {
      final m1 = await matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
      final m2 = await matieres.ajouter(classeId: classe.id, nom: 'Français', coefficient: 300);
      expect(m1.ordre, 0);
      expect(m2.ordre, 1);
      expect(await noms(), ['Maths', 'Français']);
    });

    test('chaque classe a ses propres matières, en nombre différent', () async {
      final autre = await classes.creer(anneeId: anneeId, nom: '11e B');
      await matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
      await matieres.ajouter(classeId: autre.id, nom: 'Maths', coefficient: 250);
      await matieres.ajouter(classeId: autre.id, nom: 'Physique', coefficient: 200);
      expect((await matieres.lister(classe.id)).length, 1);
      expect((await matieres.lister(autre.id)).length, 2);
      expect((await matieres.lister(classe.id)).single.coefficient, 400);
      expect((await matieres.lister(autre.id)).first.coefficient, 250);
    });

    test('aucune limite artificielle au nombre de matières', () async {
      for (var i = 1; i <= 60; i++) {
        await matieres.ajouter(
          classeId: classe.id,
          nom: 'Matière $i',
          coefficient: 100 + i,
        );
      }
      expect((await matieres.lister(classe.id)).length, 60);
    });

    test('coefficient invalide refusé (0, négatif, 100 ou plus)', () async {
      for (final coef in [0, -100, 10000]) {
        await expectLater(
          matieres.ajouter(classeId: classe.id, nom: 'M$coef', coefficient: coef),
          erreurContenant('coefficient'),
          reason: 'coefficient $coef',
        );
      }
      // Limites acceptées : 0,01 et 99,99.
      await matieres.ajouter(classeId: classe.id, nom: 'Min', coefficient: 1);
      await matieres.ajouter(classeId: classe.id, nom: 'Max', coefficient: 9999);
      expect(await noms(), ['Min', 'Max']);
    });

    test('nom vide, trop long ou en double (casse ignorée) refusé', () async {
      await matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
      await expectLater(
        matieres.ajouter(classeId: classe.id, nom: ' ', coefficient: 100),
        erreurContenant('obligatoire'),
      );
      await expectLater(
        matieres.ajouter(classeId: classe.id, nom: 'x' * 81, coefficient: 100),
        erreurContenant('trop long'),
      );
      await expectLater(
        matieres.ajouter(classeId: classe.id, nom: 'MATHS', coefficient: 100),
        erreurContenant('existe déjà'),
      );
      expect(await noms(), ['Maths']);
    });

    test('doublon détecté aussi avec des lettres accentuées majuscules', () async {
      await matieres.ajouter(
        classeId: classe.id,
        nom: 'Éducation civique',
        coefficient: 100,
      );
      await expectLater(
        matieres.ajouter(
          classeId: classe.id,
          nom: 'éducation civique',
          coefficient: 100,
        ),
        erreurContenant('existe déjà'),
      );
      expect(await noms(), ['Éducation civique']);
    });

    test('classe inconnue refusée', () async {
      await expectLater(
        matieres.ajouter(classeId: 999, nom: 'Maths', coefficient: 100),
        erreurContenant('introuvable'),
      );
    });

    test('modifier le coefficient ne touche pas aux notes brutes', () async {
      final m = await matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
      final inscription = await inscrireEleve(classe.id, anneeId, 'M001');
      await ajouterNote(inscription, m.id, 10, 1475);

      await matieres.modifier(m.id, coefficient: 150);

      expect((await matieres.lister(classe.id)).single.coefficient, 150);
      final notes = await db.query('note');
      expect(notes.single['valeur'], 1475);
    });

    test('modifier le nom, avec contrôle des doublons', () async {
      final m1 = await matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
      await matieres.ajouter(classeId: classe.id, nom: 'Français', coefficient: 300);
      await matieres.modifier(m1.id, nom: 'Mathématiques');
      expect(await noms(), ['Mathématiques', 'Français']);
      await matieres.modifier(m1.id, nom: 'Mathématiques'); // inchangé : permis
      await expectLater(
        matieres.modifier(m1.id, nom: 'français'),
        erreurContenant('existe déjà'),
      );
      expect(await noms(), ['Mathématiques', 'Français']);
    });

    test('modifier sans rien changer ne fait rien', () async {
      final m = await matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
      await matieres.modifier(m.id);
      expect((await matieres.lister(classe.id)).single.coefficient, 400);
    });

    test('modifier : coefficient invalide ou matière inconnue refusés', () async {
      final m = await matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
      await expectLater(matieres.modifier(m.id, coefficient: 0), erreurContenant('coefficient'));
      await expectLater(matieres.modifier(999, coefficient: 100), erreurContenant('introuvable'));
      expect((await matieres.lister(classe.id)).single.coefficient, 400);
    });

    test('supprimer une matière sans notes', () async {
      final m = await matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
      await matieres.supprimer(m.id);
      expect(await noms(), isEmpty);
    });

    test('supprimer une matière qui a des notes est refusé', () async {
      final m = await matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
      final inscription = await inscrireEleve(classe.id, anneeId, 'M001');
      await ajouterNote(inscription, m.id, 10, 1200);
      expect(await matieres.nbNotes(m.id), 1);
      await expectLater(matieres.supprimer(m.id), erreurContenant('1 note'));
      expect(await noms(), ['Maths']);
      expect((await db.query('note')).length, 1);
    });

    test('supprimer une matière inconnue est refusé', () async {
      await expectLater(matieres.supprimer(999), erreurContenant('introuvable'));
    });

    test('réordonner', () async {
      final a = await matieres.ajouter(classeId: classe.id, nom: 'A', coefficient: 100);
      final b = await matieres.ajouter(classeId: classe.id, nom: 'B', coefficient: 100);
      final c = await matieres.ajouter(classeId: classe.id, nom: 'C', coefficient: 100);
      await matieres.reordonner(classe.id, [c.id, a.id, b.id]);
      expect(await noms(), ['C', 'A', 'B']);
    });

    test('réordonner avec une liste incorrecte est refusé', () async {
      final a = await matieres.ajouter(classeId: classe.id, nom: 'A', coefficient: 100);
      final b = await matieres.ajouter(classeId: classe.id, nom: 'B', coefficient: 100);
      final autre = await classes.creer(anneeId: anneeId, nom: '11e B');
      final x = await matieres.ajouter(classeId: autre.id, nom: 'X', coefficient: 100);

      await expectLater(matieres.reordonner(classe.id, [a.id]), uneErreur); // incomplète
      await expectLater(matieres.reordonner(classe.id, [a.id, a.id]), uneErreur); // doublon
      await expectLater(matieres.reordonner(classe.id, [a.id, x.id]), uneErreur); // étrangère
      await expectLater(matieres.reordonner(classe.id, [a.id, b.id, x.id]), uneErreur); // en trop
      expect(await noms(), ['A', 'B']);
    });

    test('copier les matières d\'une autre classe', () async {
      await matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 400);
      await matieres.ajouter(classeId: classe.id, nom: 'Français', coefficient: 300);
      await matieres.ajouter(classeId: classe.id, nom: 'Anglais', coefficient: 200);
      final cible = await classes.creer(anneeId: anneeId, nom: '10e B');
      await matieres.ajouter(classeId: cible.id, nom: 'maths', coefficient: 100);

      final ajoutees = await matieres.copier(
        depuisClasseId: classe.id,
        versClasseId: cible.id,
      );

      expect(ajoutees, 2); // « Maths » existe déjà (casse ignorée)
      final resultat = await matieres.lister(cible.id);
      expect(resultat.map((m) => m.nom), ['maths', 'Français', 'Anglais']);
      expect(resultat.map((m) => m.coefficient), [100, 300, 200]);
      expect(resultat.map((m) => m.ordre), [0, 1, 2]);

      // Une seconde copie n'ajoute rien.
      expect(
        await matieres.copier(depuisClasseId: classe.id, versClasseId: cible.id),
        0,
      );
      // La classe source n'a pas changé.
      expect(await noms(), ['Maths', 'Français', 'Anglais']);
    });

    test('copier vers la même classe ou une classe inconnue est refusé', () async {
      await expectLater(
        matieres.copier(depuisClasseId: classe.id, versClasseId: classe.id),
        uneErreur,
      );
      await expectLater(
        matieres.copier(depuisClasseId: classe.id, versClasseId: 999),
        erreurContenant('introuvable'),
      );
    });

    test('versCoef : conversion pour le moteur de calcul', () async {
      final m = await matieres.ajouter(classeId: classe.id, nom: 'Maths', coefficient: 250);
      final coef = m.versCoef();
      expect(coef.id, m.id);
      expect(coef.nom, 'Maths');
      expect(coef.coefficient, 250);
    });
  });
}
