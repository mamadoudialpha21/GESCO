/// Migration du schéma de la version 4 vers la version 5 : maternelle et
/// programmes par cycle.
///
/// - `classe.niveau_code` accepte 14 à 16 (petite, moyenne et grande section de
///   la maternelle) en plus de 1 à 13 ;
/// - `config_calendrier_cycle` accepte le cycle `maternelle` ;
/// - `programme_matiere` : matières et coefficients d'un cycle (et, pour le
///   lycée, d'une option SM, SE ou SS) pour une année scolaire. Ils sont ajoutés
///   automatiquement aux classes du cycle ;
/// - les calendriers de cycle que personne n'a modifiés (trimestres, semestres
///   ou deux trimestres d'origine) sont retirés pour les années non archivées :
///   ces cycles suivent désormais la méthode de calcul de leur cycle
///   (compositions, ou mois + compositions + semestres). Un calendrier
///   personnalisé, et toute année archivée, restent tels quels.
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/calendrier.dart';

final List<String> migrationV5 = [
  // Le CHECK de niveau_code ne se modifie pas : on crée la colonne corrigée,
  // on y recopie les valeurs, puis on remplace l'ancienne. Aucune table n'est
  // recréée, donc aucune clé étrangère n'est touchée.
  'DROP INDEX idx_classe_niveau',
  'ALTER TABLE classe ADD COLUMN niveau_code_v5 INTEGER '
      'CHECK (niveau_code_v5 IS NULL OR (niveau_code_v5 >= 1 AND niveau_code_v5 <= 16))',
  'UPDATE classe SET niveau_code_v5 = niveau_code',
  'ALTER TABLE classe DROP COLUMN niveau_code',
  'ALTER TABLE classe RENAME COLUMN niveau_code_v5 TO niveau_code',
  'CREATE INDEX idx_classe_niveau ON classe(annee_id, niveau_code)',
  // Même chose pour config_calendrier_cycle, que rien ne référence.
  """
  CREATE TABLE config_calendrier_cycle_v5 (
    annee_id INTEGER NOT NULL REFERENCES annee_scolaire(id) ON DELETE CASCADE,
    cycle TEXT NOT NULL CHECK (cycle IN ('maternelle', 'primaire', 'college', 'lycee')),
    json TEXT NOT NULL,
    PRIMARY KEY (annee_id, cycle)
  )
  """,
  'INSERT INTO config_calendrier_cycle_v5 (annee_id, cycle, json) '
      'SELECT annee_id, cycle, json FROM config_calendrier_cycle',
  'DROP TABLE config_calendrier_cycle',
  'ALTER TABLE config_calendrier_cycle_v5 RENAME TO config_calendrier_cycle',
  """
  CREATE TABLE programme_matiere (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    annee_id INTEGER NOT NULL REFERENCES annee_scolaire(id) ON DELETE CASCADE,
    cycle TEXT NOT NULL CHECK (cycle IN ('maternelle', 'primaire', 'college', 'lycee')),
    serie TEXT NOT NULL DEFAULT '' CHECK (serie IN ('', 'SS', 'SE', 'SM')),
    nom TEXT NOT NULL CHECK (length(trim(nom)) > 0),
    coefficient INTEGER NOT NULL CHECK (coefficient > 0),
    bareme INTEGER NOT NULL DEFAULT 20 CHECK (bareme >= 1 AND bareme <= 1000),
    facultative INTEGER NOT NULL DEFAULT 0 CHECK (facultative IN (0, 1)),
    ordre INTEGER NOT NULL DEFAULT 0,
    UNIQUE (annee_id, cycle, serie, nom),
    CHECK (cycle = 'lycee' OR serie = '')
  )
  """,
  'CREATE INDEX idx_programme_annee ON programme_matiere(annee_id, cycle, serie)',
];

/// Retire les calendriers de cycle d'origine (jamais personnalisés) des années
/// non archivées, pour que ces cycles passent à la méthode de leur cycle.
/// Retourne le nombre de calendriers retirés.
Future<int> basculerCalendriersDOrigine(Database db) async {
  final lignes = await db.rawQuery('''
    SELECT c.annee_id, c.cycle, c.json
    FROM config_calendrier_cycle c
    JOIN annee_scolaire a ON a.id = c.annee_id
    WHERE a.archivee = 0
  ''');
  const origines = [Calendrier.trimestres, Calendrier.semestres, Calendrier.deuxTrimestres];
  var retires = 0;
  for (final l in lignes) {
    final Calendrier calendrier;
    try {
      calendrier = Calendrier.fromJsonString(l['json'] as String);
    } catch (_) {
      continue; // illisible : on n'y touche pas
    }
    if (!origines.contains(calendrier)) continue;
    await db.delete(
      'config_calendrier_cycle',
      where: 'annee_id = ? AND cycle = ?',
      whereArgs: [l['annee_id'], l['cycle']],
    );
    retires++;
  }
  return retires;
}
