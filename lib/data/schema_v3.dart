/// Migration du schéma de la version 2 vers la version 3 : cycles d'études.
///
/// - `classe.niveau_code` : niveau d'études (1 à 13, 13 = Terminale), ou NULL
///   pour une classe dont le niveau n'est pas dans le catalogue ;
/// - `classe.serie` : option du lycée (SS, SE, SM) ou chaîne vide ;
/// - `config_calendrier_cycle` : calendrier des périodes propre à chaque cycle
///   (primaire, collège, lycée) d'une année. Les calendriers déjà enregistrés
///   par année sont recopiés pour les trois cycles : les résultats des années
///   existantes ne changent pas.
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/niveaux.dart';

final List<String> migrationV3 = [
  'ALTER TABLE classe ADD COLUMN niveau_code INTEGER '
      'CHECK (niveau_code IS NULL OR (niveau_code >= 1 AND niveau_code <= 13))',
  "ALTER TABLE classe ADD COLUMN serie TEXT NOT NULL DEFAULT '' "
      "CHECK (serie IN ('', 'SS', 'SE', 'SM'))",
  """
  CREATE TABLE config_calendrier_cycle (
    annee_id INTEGER NOT NULL REFERENCES annee_scolaire(id) ON DELETE CASCADE,
    cycle TEXT NOT NULL CHECK (cycle IN ('primaire', 'college', 'lycee')),
    json TEXT NOT NULL,
    PRIMARY KEY (annee_id, cycle)
  )
  """,
  """
  INSERT INTO config_calendrier_cycle (annee_id, cycle, json)
  SELECT c.annee_id, k.cycle, c.json
  FROM config_calendrier c
  CROSS JOIN (
    SELECT 'primaire' AS cycle UNION ALL SELECT 'college' UNION ALL SELECT 'lycee'
  ) k
  """,
  'CREATE INDEX idx_classe_niveau ON classe(annee_id, niveau_code)',
];

/// Rattache les classes existantes au catalogue d'après leur niveau saisi à
/// la main (« 10e », « 7ème année »...). Un niveau non reconnu reste sans
/// cycle : la classe garde alors le calendrier général de l'année. Le texte
/// du niveau n'est pas modifié.
Future<void> rattraperNiveaux(Database db) async {
  final classes = await db.query('classe', columns: ['id', 'niveau', 'nom']);
  for (final c in classes) {
    final texte = (c['niveau'] as String?) ?? '';
    final niveau = devinerNiveau(texte);
    if (niveau == null) continue;
    final serie =
        niveau.aDesOptions ? devinerSerie('$texte ${c['nom']}') : null;
    await db.update(
      'classe',
      {'niveau_code': niveau.code, 'serie': serie?.code ?? ''},
      where: 'id = ?',
      whereArgs: [c['id']],
    );
  }
}
