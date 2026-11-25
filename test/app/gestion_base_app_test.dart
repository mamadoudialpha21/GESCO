import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/etat_app.dart';
import 'package:gesco/app/gestion_base_app.dart';
import 'package:gesco/data/erreurs.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/data/modeles_securite.dart';
import 'package:gesco/domain/permissions.dart';
import 'package:gesco/sauvegarde/service_sauvegarde.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const administrateur = Utilisateur(
  id: 1,
  identifiant: 'admin',
  nomComplet: 'Administrateur',
  role: RoleUtilisateur.administrateur,
  actif: true,
  creeLe: '2026-01-01',
);

void main() {
  sqfliteFfiInit();

  late Directory tmp;
  late String chemin;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gesco_gestion_base_');
    chemin = p.join(tmp.path, 'gesco.db');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<GestionBaseApp> demarrer({bool planificateur = false}) => GestionBaseApp.demarrer(
        fabrique: databaseFactoryFfi,
        chemin: chemin,
        demarrerPlanificateur: planificateur,
      );

  Future<void> inscrire(EtatApp e, int annee, int classe, String matricule, String nom, String prenom) async {
    await e.services.eleves.inscrire(
      Eleve(matricule: matricule, nom: nom, prenom: prenom, sexe: 'M'),
      anneeId: annee,
      classeId: classe,
    );
  }

  /// Une année, une classe et deux élèves, saisis avec le compte administrateur.
  Future<(int, int)> peupler(EtatApp e) async {
    e.services.session.ouvrir(administrateur);
    final s = e.services;
    await s.etablissements.enregistrer(const Etablissement(nom: 'Groupe Scolaire Test'));
    final annee = (await s.annees.creer('2026-2027', activer: true)).id;
    final classe = (await s.classes.creer(anneeId: annee, nom: '10e A', niveauCode: 10)).id;
    await inscrire(e, annee, classe, '2026-0001', 'BARRY', 'Mamadou');
    await inscrire(e, annee, classe, '2026-0002', 'DIALLO', 'Aminata');
    return (annee, classe);
  }

  Future<int> nbEleves(EtatApp e, int annee, int classe) async =>
      (await e.services.eleves.lister(annee, classeId: classe)).length;

  test('démarrage : base ouverte, état chargé, sauvegardes et restauration branchées', () async {
    final g = await demarrer();
    final e = g.etat.value;
    expect(e.chemin, chemin);
    expect(File(chemin).existsSync(), isTrue);
    expect(e.sauvegarde, isNotNull);
    expect(e.gestionBase, same(g));
    expect(e.planificateurSauvegarde, isNotNull);
    expect(e.planificateurSauvegarde!.actif, isFalse);
    expect(e.acces.aucunCompte, isTrue);
    expect(e.acces.charge, isTrue);
    expect(e.problemesIntegrite, isEmpty);
    await g.fermer();
  });

  test('avec planification : la sauvegarde automatique est démarrée, puis arrêtée à la fermeture', () async {
    final g = await demarrer(planificateur: true);
    final pl = g.etat.value.planificateurSauvegarde!;
    expect(pl.actif, isTrue);
    await g.fermer();
    expect(pl.actif, isFalse);
  });

  test('restauration puis redémarrage : base remplacée, session fermée, nouvel état de l\'application',
      () async {
    final g = await demarrer(planificateur: true);
    final avant = g.etat.value;
    final (annee, classe) = await peupler(avant);
    final sauvegarde = (await avant.sauvegarde!.creerManuelle()).sauvegarde; // 2 élèves
    await inscrire(avant, annee, classe, '2026-0003', 'CAMARA', 'Fatou');
    expect(await nbEleves(avant, annee, classe), 3);

    final etapes = <EtapeRestauration>[];
    final r = await g.restaurer(sauvegarde.chemin, progression: etapes.add);
    expect(r.reussie, isTrue, reason: r.message);
    expect(etapes.last, EtapeRestauration.termine);
    // La sauvegarde automatique de l'ancienne base est arrêtée dès la fermeture.
    expect(avant.planificateurSauvegarde!.actif, isFalse);
    // L'application n'a pas encore été reconstruite.
    expect(identical(g.etat.value, avant), isTrue);

    await g.redemarrer();
    final apres = g.etat.value;
    expect(identical(apres, avant), isFalse);
    expect(apres.gestionBase, same(g));
    expect(apres.sauvegarde, isNot(same(avant.sauvegarde)));
    expect(apres.services.session.utilisateur, isNull, reason: 'il faut se reconnecter');
    expect(apres.planificateurSauvegarde!.actif, isTrue);
    expect(apres.annees.map((a) => a.libelle), ['2026-2027']);
    expect(apres.etablissement.nom, 'Groupe Scolaire Test');
    expect(apres.problemesIntegrite, isEmpty);

    apres.services.session.ouvrir(administrateur);
    expect(await nbEleves(apres, annee, classe), 2);
    // Les données d'avant la restauration sont dans la sauvegarde de sécurité.
    final securite = (await apres.sauvegarde!.historique())
        .where((s) => s.type == TypeSauvegarde.securite)
        .toList();
    expect(securite, hasLength(1));
    final v = await apres.sauvegarde!.verifierFichier(securite.single.chemin);
    expect(v.valide, isTrue);
    expect(v.manifeste!.contenu['eleves'], 3);

    await g.fermer();
    expect(apres.planificateurSauvegarde!.actif, isFalse);
  });

  test('on peut revenir en arrière en restaurant la sauvegarde de sécurité', () async {
    final g = await demarrer();
    final (annee, classe) = await peupler(g.etat.value);
    final a = (await g.etat.value.sauvegarde!.creerManuelle()).sauvegarde;
    await inscrire(g.etat.value, annee, classe, '2026-0003', 'CAMARA', 'Fatou');

    expect((await g.restaurer(a.chemin)).reussie, isTrue);
    await g.redemarrer();
    g.etat.value.services.session.ouvrir(administrateur);
    expect(await nbEleves(g.etat.value, annee, classe), 2);
    final securite = (await g.etat.value.sauvegarde!.historique())
        .firstWhere((s) => s.type == TypeSauvegarde.securite);

    final retour = await g.restaurer(securite.chemin);
    expect(retour.reussie, isTrue, reason: retour.message);
    await g.redemarrer();
    g.etat.value.services.session.ouvrir(administrateur);
    expect(await nbEleves(g.etat.value, annee, classe), 3);
    await g.fermer();
  });

  test('fichier refusé : rien ne change et l\'application reste utilisable sans redémarrer', () async {
    final g = await demarrer(planificateur: true);
    final avant = g.etat.value;
    final (annee, classe) = await peupler(avant);
    final texte = File(p.join(tmp.path, 'faux.zip'))..writeAsStringSync('ceci n\'est pas une sauvegarde');

    await expectLater(g.restaurer(texte.path), throwsA(isA<ErreurGesco>()));
    // Le refus a lieu avant toute fermeture : la base et la planification continuent.
    expect(avant.planificateurSauvegarde!.actif, isTrue);
    expect(identical(g.etat.value, avant), isTrue);
    expect(await nbEleves(avant, annee, classe), 2);
    await inscrire(avant, annee, classe, '2026-0003', 'CAMARA', 'Fatou');
    expect(await nbEleves(avant, annee, classe), 3);
    await g.fermer();
  });

  test('sans le droit de restaurer, la restauration est refusée', () async {
    final g = await demarrer();
    final e = g.etat.value;
    await peupler(e);
    final a = (await e.sauvegarde!.creerManuelle()).sauvegarde;
    e.services.session.ouvrir(const Utilisateur(
      id: 2,
      identifiant: 'direction',
      nomComplet: 'Direction',
      role: RoleUtilisateur.direction,
      actif: true,
      creeLe: '2026-01-01',
    ));
    await expectLater(g.restaurer(a.chemin), throwsA(isA<ErreurGesco>()));
    expect(identical(g.etat.value, e), isTrue);
    await g.fermer();
  });
}
