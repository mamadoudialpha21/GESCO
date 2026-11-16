/// Schéma SQL de GESCO, version 1.
///
/// Règles de conception :
/// - notes et coefficients sont des ENTIERS en centièmes (14,75 -> 1475,
///   coefficient 2,5 -> 250) : aucun nombre flottant n'est stocké ;
/// - une note non saisie = aucune ligne dans `note` (jamais zéro par défaut) ;
/// - les classes, matières et inscriptions appartiennent à une année
///   scolaire : les années ne se mélangent jamais ;
/// - les clés étrangères RESTRICT empêchent de supprimer une classe, une
///   matière ou une inscription qui possède des notes.
const List<String> schemaV1 = [
  """
  CREATE TABLE etablissement (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    nom TEXT NOT NULL DEFAULT '',
    adresse TEXT NOT NULL DEFAULT '',
    telephone TEXT NOT NULL DEFAULT '',
    email TEXT NOT NULL DEFAULT '',
    logo BLOB
  )
  """,
  """
  CREATE TABLE parametre (
    cle TEXT PRIMARY KEY,
    valeur TEXT NOT NULL
  )
  """,
  """
  CREATE TABLE annee_scolaire (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    libelle TEXT NOT NULL UNIQUE CHECK (length(trim(libelle)) > 0),
    active INTEGER NOT NULL DEFAULT 0 CHECK (active IN (0, 1)),
    cree_le TEXT NOT NULL
  )
  """,
  // Une seule année active à la fois.
  """
  CREATE UNIQUE INDEX idx_annee_active ON annee_scolaire(active) WHERE active = 1
  """,
  // Seuils de mentions et de décisions, propres à chaque année (JSON).
  """
  CREATE TABLE config_resultats (
    annee_id INTEGER PRIMARY KEY REFERENCES annee_scolaire(id) ON DELETE CASCADE,
    json TEXT NOT NULL
  )
  """,
  """
  CREATE TABLE classe (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    annee_id INTEGER NOT NULL REFERENCES annee_scolaire(id) ON DELETE RESTRICT,
    niveau TEXT NOT NULL DEFAULT '',
    nom TEXT NOT NULL CHECK (length(trim(nom)) > 0),
    UNIQUE (annee_id, nom),
    UNIQUE (id, annee_id)
  )
  """,
  """
  CREATE TABLE matiere_classe (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    classe_id INTEGER NOT NULL REFERENCES classe(id) ON DELETE CASCADE,
    nom TEXT NOT NULL CHECK (length(trim(nom)) > 0),
    coefficient INTEGER NOT NULL CHECK (coefficient > 0),
    ordre INTEGER NOT NULL DEFAULT 0,
    UNIQUE (classe_id, nom)
  )
  """,
  """
  CREATE TABLE eleve (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    matricule TEXT NOT NULL UNIQUE CHECK (length(trim(matricule)) > 0),
    nom TEXT NOT NULL CHECK (length(trim(nom)) > 0),
    prenom TEXT NOT NULL CHECK (length(trim(prenom)) > 0),
    sexe TEXT NOT NULL CHECK (sexe IN ('M', 'F')),
    date_naissance TEXT,
    lieu_naissance TEXT,
    nom_pere TEXT,
    nom_mere TEXT,
    contact_parent TEXT,
    adresse TEXT,
    photo BLOB
  )
  """,
  // Un élève a au plus une inscription par année ; la classe doit appartenir
  // à la même année (clé étrangère composite).
  """
  CREATE TABLE inscription (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    eleve_id INTEGER NOT NULL REFERENCES eleve(id) ON DELETE RESTRICT,
    classe_id INTEGER NOT NULL,
    annee_id INTEGER NOT NULL,
    date_inscription TEXT NOT NULL,
    UNIQUE (eleve_id, annee_id),
    FOREIGN KEY (classe_id, annee_id) REFERENCES classe (id, annee_id) ON DELETE RESTRICT
  )
  """,
  // etat 'saisie'  : valeur obligatoire (0 à 2000 centièmes = 0,00 à 20,00)
  // etat 'absent' / 'dispense' : pas de valeur.
  """
  CREATE TABLE note (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    inscription_id INTEGER NOT NULL REFERENCES inscription(id) ON DELETE RESTRICT,
    matiere_id INTEGER NOT NULL REFERENCES matiere_classe(id) ON DELETE RESTRICT,
    mois INTEGER NOT NULL CHECK (mois IN (1, 2, 3, 4, 5, 6, 10, 11, 12)),
    etat TEXT NOT NULL CHECK (etat IN ('saisie', 'absent', 'dispense')),
    valeur INTEGER CHECK (valeur IS NULL OR (valeur >= 0 AND valeur <= 2000)),
    modifie_le TEXT NOT NULL,
    UNIQUE (inscription_id, matiere_id, mois),
    CHECK (
      (etat = 'saisie' AND valeur IS NOT NULL)
      OR (etat <> 'saisie' AND valeur IS NULL)
    )
  )
  """,
  // La matière d'une note doit appartenir à la classe de l'inscription.
  """
  CREATE TRIGGER note_coherence_insert BEFORE INSERT ON note
  BEGIN
    SELECT RAISE(ABORT, 'Matiere hors classe')
    WHERE (SELECT classe_id FROM inscription WHERE id = NEW.inscription_id)
      IS NOT (SELECT classe_id FROM matiere_classe WHERE id = NEW.matiere_id);
  END
  """,
  """
  CREATE TRIGGER note_coherence_update BEFORE UPDATE OF inscription_id, matiere_id ON note
  BEGIN
    SELECT RAISE(ABORT, 'Matiere hors classe')
    WHERE (SELECT classe_id FROM inscription WHERE id = NEW.inscription_id)
      IS NOT (SELECT classe_id FROM matiere_classe WHERE id = NEW.matiere_id);
  END
  """,
  // Symétrique des deux triggers ci-dessus : on ne peut pas changer la classe
  // d'une inscription qui a déjà des notes (elles porteraient sur les matières
  // de l'ancienne classe). L'application affiche un message clair avant ; ce
  // trigger est le filet de sécurité de la base.
  """
  CREATE TRIGGER inscription_classe_verrouillee BEFORE UPDATE OF classe_id ON inscription
  WHEN NEW.classe_id IS NOT OLD.classe_id
    AND EXISTS (SELECT 1 FROM note WHERE inscription_id = OLD.id)
  BEGIN
    SELECT RAISE(ABORT, 'Classe verrouillee: des notes existent');
  END
  """,
  'CREATE INDEX idx_matiere_classe ON matiere_classe(classe_id)',
  'CREATE INDEX idx_eleve_nom ON eleve(nom, prenom)',
  'CREATE INDEX idx_inscription_classe ON inscription(classe_id)',
  'CREATE INDEX idx_note_inscription ON note(inscription_id, mois)',
  'CREATE INDEX idx_note_matiere ON note(matiere_id)',
];
