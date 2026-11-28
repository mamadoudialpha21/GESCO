import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/app/calcul_classe.dart';
import 'package:gesco/app/construire_bulletins.dart';
import 'package:gesco/app/services.dart';
import 'package:gesco/app/session.dart';
import 'package:gesco/data/gesco_database.dart';
import 'package:gesco/data/modeles_donnees.dart';
import 'package:gesco/documents/modele_bulletin.dart';
import 'package:gesco/domain/calendrier.dart';
import 'package:gesco/domain/modeles.dart';
import 'package:gesco/domain/niveaux.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late GescoDatabase gdb;
  late Services s;
  late int annee;
  late Map<String, int> classe;
  late Map<String, int> inscription;

  /// Une classe par cycle, un élève par classe. Primaire : une note en décembre
  /// (12,00) et une en mars (16,00), les compositions. Collège et lycée : une
  /// note en novembre (12,00) et une en janvier (16,00), la composition 1.
  setUp(() async {
    gdb = await GescoDatabase.ouvrir(
      fabrique: databaseFactoryFfi,
      chemin: inMemoryDatabasePath,
    );
    s = Services(gdb, session: Session.sansControle(), iterations: 2);
    annee = (await s.annees.creer('2026-2027', activer: true)).id;
    classe = {};
    inscription = {};
    final specs = <(String, int, SerieLycee?)>[
      ('3e A', 3, null),
      ('8e A', 8, null),
      ('Tle SM', 13, SerieLycee.sciencesMathematiques),
    ];
    var n = 0;
    for (final (nom, code, serie) in specs) {
      final c = await s.classes.creer(anneeId: annee, nom: nom, niveauCode: code, serie: serie);
      classe[nom] = c.id;
      final m = await s.matieres.ajouter(classeId: c.id, nom: 'Maths', coefficient: 200);
      n++;
      final insc = await s.eleves.inscrire(
        Eleve(matricule: '2026-000$n', nom: 'ELEVE$n', prenom: 'Test', sexe: n.isEven ? 'F' : 'M'),
        anneeId: annee,
        classeId: c.id,
      );
      inscription[nom] = insc;
      await s.notes.enregistrer(
        inscriptionId: insc,
        matiereId: m.id,
        mois: code <= 6 ? 12 : 11,
        saisie: const Saisie.valeur(1200),
      );
      await s.notes.enregistrer(
        inscriptionId: insc,
        matiereId: m.id,
        mois: code <= 6 ? 3 : 1,
        saisie: const Saisie.valeur(1600),
      );
    }
  });

  tearDown(() async => gdb.fermer());

  Future<Map<String, CalculClasse>> charger() async {
    final calculs = await chargerToutesLesClasses(s, annee);
    return {for (final c in calculs) c.classe.classe.nom: c};
  }

  test('chaque classe reçoit le calendrier de son cycle', () async {
    final c = await charger();
    expect(c['3e A']!.calendrier.periodes.length, 3);
    expect(c['8e A']!.calendrier.periodes.length, 2);
    expect(c['Tle SM']!.calendrier.periodes.length, 2);
    expect(c['3e A']!.calendrier, Calendrier.compositions);
    expect(c['8e A']!.calendrier, Calendrier.semestresCompo);
    expect(c['Tle SM']!.calendrier, Calendrier.semestresCompo);
  });

  test('primaire : une période par composition ; collège et lycée : janvier est la composition 1',
      () async {
    final c = await charger();
    int? moyenne(String nom, String cle) {
      final calcul = c[nom]!;
      final portee = calcul.calendrier.portee(cle)!;
      return calcul.resultats(portee).single.moyenne;
    }

    // Primaire : compo 1 (décembre) 12,00 ; compo 2 (mars) 16,00 ; compo 3 vide.
    expect(moyenne('3e A', 't1'), 1200);
    expect(moyenne('3e A', 't2'), 1600);
    expect(moyenne('3e A', 't3'), isNull);
    // Collège / lycée : semestre 1 = (composition de janvier 16,00 x 2 + moyenne
    // des autres mois, ici novembre 12,00) / 3 = 44 / 3 = 14,67 ; semestre 2 vide.
    expect(moyenne('8e A', 't1'), 1467);
    expect(moyenne('8e A', 't2'), isNull);
    expect(c['8e A']!.calendrier.portee('t3'), isNull, reason: 'pas de période 3');
    expect(moyenne('Tle SM', 't1'), 1467);
    expect(moyenne('Tle SM', 't2'), isNull);
  });

  test('moyenne annuelle : moyenne des périodes notées de la classe', () async {
    final c = await charger();
    // Primaire : (12,00 + 16,00) / 2 compositions notées = 14,00.
    expect(c['3e A']!.resultats(const Portee.annee()).single.moyenne, 1400);
    // Collège : un seul semestre noté (14,67).
    expect(c['8e A']!.resultats(const Portee.annee()).single.moyenne, 1467);
  });

  test('un calendrier personnalisé pour un cycle ne change que ses classes', () async {
    await s.calendriers.enregistrer(annee, Calendrier.trimestres, cycle: Cycle.college);
    final c = await charger();
    expect(c['8e A']!.calendrier.periodes.length, 3);
    expect(c['Tle SM']!.calendrier.periodes.length, 2);
    expect(c['3e A']!.calendrier.periodes.length, 3);
    expect(c['8e A']!.resultats(c['8e A']!.calendrier.portee('t2')!).single.moyenne, 1600);
  });

  test('classe sans cycle : calendrier général de l\'année', () async {
    final libre = await s.classes.creer(anneeId: annee, nom: 'Autre', niveau: 'Crèche');
    await s.calendriers.enregistrer(annee, Calendrier.semestres);
    final c = await charger();
    expect(c[libre.nom]!.calendrier, Calendrier.semestres);
    expect(c['3e A']!.calendrier, Calendrier.compositions);
  });

  test('synthèse de l\'établissement : périodes de chaque classe', () async {
    final calculs = await chargerToutesLesClasses(s, annee);
    final synthese = synthetiserEtablissement(
      calculs,
      config: ConfigResultats.defaut,
    );
    final parNom = {for (final c in synthese.classes) c.classe.classe.nom: c};
    expect(parNom['3e A']!.moyennesPeriodes, [1200, 1600, null]);
    expect(parNom['8e A']!.moyennesPeriodes, [1467, null]);
    expect(parNom['Tle SM']!.moyennesPeriodes, [1467, null]);
    expect(parNom['8e A']!.calendrier, Calendrier.semestresCompo);
  });

  test('bulletin : niveau, option et périodes du cycle', () async {
    final calculs = await chargerToutesLesClasses(s, annee);
    final c = {for (final x in calculs) x.classe.classe.nom: x};

    final tle = construireBulletins(
      calcul: c['Tle SM']!,
      portee: const Portee.annee(),
      periodeLibelle: 'Année entière',
      type: TypeBulletin.annuel,
      etablissement: const Etablissement(nom: 'École'),
      anneeLibelle: '2026-2027',
    );
    expect(tle.single.niveau, 'Terminale · Sciences mathématiques');
    expect([for (final p in tle.single.periodes) p.libelle], ['Semestre 1', 'Semestre 2']);

    final primaire = construireBulletins(
      calcul: c['3e A']!,
      portee: const Portee.annee(),
      periodeLibelle: 'Année entière',
      type: TypeBulletin.annuel,
      etablissement: const Etablissement(nom: 'École'),
      anneeLibelle: '2026-2027',
    );
    expect(primaire.single.niveau, '3ème année');
    expect([for (final p in primaire.single.periodes) p.libelle],
        ['Compo 1 (décembre)', 'Compo 2 (mars)', 'Compo 3 (juin)']);
  });
}
