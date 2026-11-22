/// Migration du schéma de la version 3 vers la version 4 : absences et retards.
///
/// `absence` : une ligne par absence (journée) ou par retard d'un élève inscrit.
/// Un élève ne peut avoir qu'une absence et qu'un retard par jour. Les absences
/// disparaissent avec l'inscription qu'elles concernent.
library;

final List<String> migrationV4 = [
  """
  CREATE TABLE absence (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    inscription_id INTEGER NOT NULL REFERENCES inscription(id) ON DELETE CASCADE,
    date TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('absence', 'retard')),
    justifiee INTEGER NOT NULL DEFAULT 0 CHECK (justifiee IN (0, 1)),
    duree_minutes INTEGER CHECK (duree_minutes IS NULL OR (duree_minutes >= 1 AND duree_minutes <= 600)),
    motif TEXT NOT NULL DEFAULT '',
    cree_le TEXT NOT NULL,
    UNIQUE (inscription_id, date, type)
  )
  """,
  'CREATE INDEX idx_absence_inscription ON absence(inscription_id, date)',
];
