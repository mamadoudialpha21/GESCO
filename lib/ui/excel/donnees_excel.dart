import '../../app/etat_app.dart';
import '../../data/modeles_donnees.dart';
import '../../domain/calendrier.dart';
import '../../domain/periodes.dart';

/// Ce que les écrans Excel lisent une fois : classes, matières, enseignants et
/// périodes proposées (celles des calendriers des cycles présents).
class DonneesExcel {
  const DonneesExcel({
    this.classes = const [],
    this.matieres = const {},
    this.enseignants = const [],
    this.periodes = const [],
    this.etendues = const [],
    this.periodesClasse = const {},
  });

  final List<ClasseResume> classes;

  /// Matières de chaque classe (identifiant de la classe -> matières).
  final Map<int, List<MatiereClasse>> matieres;

  /// Enseignants qui ont au moins une matière cette année.
  final List<EnseignantResume> enseignants;

  /// (clé, libellé) des trimestres ou périodes, sans doublon entre les cycles.
  final List<(String, String)> periodes;

  /// Périodes, année entière, séquences puis mois : toutes les étendues.
  final List<(String, String)> etendues;

  /// Périodes (avec leurs mois) du calendrier de chaque classe : celles qui
  /// servent à l'import des notes.
  final Map<int, List<PeriodeScolaire>> periodesClasse;

  static Future<DonneesExcel> charger(EtatApp etat) async {
    final anneeId = etat.anneeId;
    if (anneeId == null) return const DonneesExcel();
    final s = etat.services;
    final classes = await s.classes.lister(anneeId);
    final calendriers = await s.calendriers.lireTous(anneeId);
    final periodes = <String, String>{};
    final sequences = <String, String>{};
    for (final c in classes) {
      final cal = calendriers.pour(c.classe.cycle);
      for (final p in cal.periodes) {
        periodes.putIfAbsent(p.cle, () => p.libelle);
      }
      for (final q in cal.sequences) {
        sequences.putIfAbsent(q.cle, () => q.libelle);
      }
    }
    if (periodes.isEmpty) {
      for (final p in calendriers.general.periodes) {
        periodes[p.cle] = p.libelle;
      }
    }
    final listePeriodes = [for (final e in periodes.entries) (e.key, e.value)];
    final enseignants = await s.enseignants.lister(anneeId: anneeId);
    return DonneesExcel(
      periodesClasse: {
        for (final c in classes) c.classe.id: calendriers.pour(c.classe.cycle).periodes,
      },
      classes: classes,
      matieres: {for (final c in classes) c.classe.id: await s.matieres.lister(c.classe.id)},
      enseignants: [
        for (final e in enseignants)
          if (e.nbMatieres > 0) e,
      ],
      periodes: listePeriodes,
      etendues: [
        ...listePeriodes,
        (cleAnnee, 'Année entière'),
        for (final e in sequences.entries) (e.key, e.value),
        for (final m in moisScolaires) ('m$m', libelleMois(m)),
      ],
    );
  }
}
