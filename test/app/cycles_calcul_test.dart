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

  /// Une classe par cycle, un élève par classe, une note en janvier (mois 1)
  /// et une en novembre (mois 11).
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
        mois: 11,
        saisie: const Saisie.valeur(1200),
      );
      await s.notes.enregistrer(
        inscriptionId: insc,
        matiereId: m.id,
        mois: 1,
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
    expect(c['3e A']!.calendrier, Calendrier.trimestres);
    expect(c['8e A']!.calendrier, Calendrier.deuxTrimestres);
  });

  test('janvier : trimestre 2 au primaire, trimestre 1 au collège et au lycée',
      () async {
    final c = await charger();
    int? moyenne(String nom, String cle) {
      final calcul = c[nom]!;
      final portee = calcul.calendrier.portee(cle)!;
      return calcul.resultats(portee).single.moyenne;
    }

    // Primaire : T1 = oct-déc (novembre : 12,00) ; T2 = janv-mars (janvier : 16,00).
    expect(moyenne('3e A', 't1'), 1200);
    expect(moyenne('3e A', 't2'), 1600);
    expect(moyenne('3e A', 't3'), isNull);
    // Collège / lycée : T1 = oct-janv (moyenne de 12 et 16 = 14,00) ; T2 vide.
    expect(moyenne('8e A', 't1'), 1400);
    expect(moyenne('8e A', 't2'), isNull);
    expect(c['8e A']!.calendrier.portee('t3'), isNull, reason: 'pas de trimestre 3');
    expect(moyenne('Tle SM', 't1'), 1400);
    expect(moyenne('Tle SM', 't2'), isNull);
  });

  test('moyenne annuelle : moyenne des trimestres de la classe', () async {
    final c = await charger();
    // Primaire : (12,00 + 16,00) / 2 trimestres notés = 14,00.
    expect(c['3e A']!.resultats(const Portee.annee()).single.moyenne, 1400);
    // Collège : un seul trimestre noté (14,00).
    expect(c['8e A']!.resultats(const Portee.annee()).single.moyenne, 1400);
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
    expect(c['3e A']!.calendrier, Calendrier.trimestres);
  });

  test('synthèse de l\'établissement : périodes de chaque classe', () async {
    final calculs = await chargerToutesLesClasses(s, annee);
    final synthese = synthetiserEtablissement(
      calculs,
      config: ConfigResultats.defaut,
    );
    final parNom = {for (final c in synthese.classes) c.classe.classe.nom: c};
    expect(parNom['3e A']!.moyennesPeriodes, [1200, 1600, null]);
    expect(parNom['8e A']!.moyennesPeriodes, [1400, null]);
    expect(parNom['Tle SM']!.moyennesPeriodes, [1400, null]);
    expect(parNom['8e A']!.calendrier, Calendrier.deuxTrimestres);
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
    expect([for (final p in tle.single.periodes) p.libelle], ['Trimestre 1', 'Trimestre 2']);

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
        ['Trimestre 1', 'Trimestre 2', 'Trimestre 3']);
  });
}
