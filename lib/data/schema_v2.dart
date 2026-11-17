/// Migration du schéma de la version 1 vers la version 2.
///
/// Ajoute, sans toucher aux données existantes :
/// - enseignants, comptes utilisateurs, journaux (connexions, opérations) ;
/// - évaluations (interrogation, devoir, composition, examen) et leurs notes,
///   avec un barème propre (sur 10, 20, 40, 100...) ;
/// - historique automatique des notes (anciennes valeurs, auteur) ;
/// - verrouillage des mois et archivage des années ;
/// - mouvements d'inscription (changement de classe, départ, abandon) ;
/// - appréciations et décisions du conseil de classe ;
/// - historique des sauvegardes, calendrier des périodes par année ;
/// - colonnes complémentaires (directeur, devise, capacité, barème...).
///
/// Les mêmes instructions servent à créer une base neuve et à mettre à jour une
/// base existante : les deux chemins donnent exactement le même schéma.
library;

/// Enregistre une ligne d'historique de note. [ref] vaut `NEW` ou `OLD` et
/// désigne la ligne qui porte l'identifiant de l'élève.
String _historique({
  required String source,
  required String operation,
  required String ref,
  required String matiere,
  required String mois,
  required String evaluation,
  required String bareme,
  required String ancienEtat,
  required String ancienneValeur,
  required String nouvelEtat,
  required String nouvelleValeur,
}) =>
    '''
INSERT INTO historique_note (
  date_heure, utilisateur_id, utilisateur_nom, source, operation,
  inscription_id, matiere_id, mois, evaluation_id, bareme,
  eleve_nom, matiere_nom, classe_nom,
  ancien_etat, ancienne_valeur, nouvel_etat, nouvelle_valeur
)
SELECT
  strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'), c.utilisateur_id, c.utilisateur_nom,
  '$source', '$operation',
  $ref.inscription_id, $matiere, $mois, $evaluation, $bareme,
  (SELECT e.nom || ' ' || e.prenom FROM inscription i JOIN eleve e ON e.id = i.eleve_id
    WHERE i.id = $ref.inscription_id),
  (SELECT nom FROM matiere_classe WHERE id = $matiere),
  (SELECT cl.nom FROM inscription i JOIN classe cl ON cl.id = i.classe_id
    WHERE i.id = $ref.inscription_id),
  $ancienEtat, $ancienneValeur, $nouvelEtat, $nouvelleValeur
FROM contexte c WHERE c.id = 1;
''';

/// Les trois déclencheurs d'historique d'une table de notes.
List<String> _declencheursHistorique({
  required String table,
  required String source,
  required String matiere,
  required String Function(String ref) mois,
  required String Function(String ref) evaluation,
  required String Function(String ref) bareme,
  required String valeur,
  required String prefixe,
}) {
  String corps(String operation, String ref, bool ancien, bool nouveau) =>
      _historique(
        source: source,
        operation: operation,
        ref: ref,
        matiere: matiere.replaceAll('REF', ref),
        mois: mois(ref),
        evaluation: evaluation(ref),
        bareme: bareme(ref),
        ancienEtat: ancien ? 'OLD.etat' : 'NULL',
        ancienneValeur: ancien ? 'OLD.$valeur' : 'NULL',
        nouvelEtat: nouveau ? 'NEW.etat' : 'NULL',
        nouvelleValeur: nouveau ? 'NEW.$valeur' : 'NULL',
      );
  return [
    '''
CREATE TRIGGER ${prefixe}_historique_creation AFTER INSERT ON $table
BEGIN
${corps('creation', 'NEW', false, true)}
END
''',
    '''
CREATE TRIGGER ${prefixe}_historique_modif AFTER UPDATE ON $table
WHEN OLD.etat IS NOT NEW.etat OR OLD.$valeur IS NOT NEW.$valeur
BEGIN
${corps('modification', 'NEW', true, true)}
END
''',
    '''
CREATE TRIGGER ${prefixe}_historique_suppression AFTER DELETE ON $table
BEGIN
${corps('suppression', 'OLD', true, false)}
END
''',
  ];
}

/// Vérifications de verrouillage pour une case de note mensuelle.
String _verrouNote(String ref) => '''
  SELECT RAISE(ABORT, 'Annee archivee') WHERE EXISTS (
    SELECT 1 FROM inscription i JOIN annee_scolaire a ON a.id = i.annee_id
    WHERE i.id = $ref.inscription_id AND a.archivee = 1);
  SELECT RAISE(ABORT, 'Mois verrouille') WHERE EXISTS (
    SELECT 1 FROM inscription i JOIN verrou_notes v
      ON v.classe_id = i.classe_id AND v.mois = $ref.mois
    WHERE i.id = $ref.inscription_id);
''';

/// Vérifications de verrouillage pour une note d'évaluation.
String _verrouEvaluationNote(String ref) => '''
  SELECT RAISE(ABORT, 'Evaluation validee') WHERE EXISTS (
    SELECT 1 FROM evaluation WHERE id = $ref.evaluation_id AND valide = 1);
  SELECT RAISE(ABORT, 'Mois verrouille') WHERE EXISTS (
    SELECT 1 FROM evaluation e JOIN verrou_notes v
      ON v.classe_id = e.classe_id AND v.mois = e.mois
    WHERE e.id = $ref.evaluation_id);
  SELECT RAISE(ABORT, 'Annee archivee') WHERE EXISTS (
    SELECT 1 FROM evaluation e JOIN classe cl ON cl.id = e.classe_id
      JOIN annee_scolaire a ON a.id = cl.annee_id
    WHERE e.id = $ref.evaluation_id AND a.archivee = 1);
''';

const String _sansTransfert =
    '(SELECT transfert FROM contexte WHERE id = 1) = 0';

final List<String> migrationV2 = [
  // ------------------------------------------------ Colonnes complémentaires
  "ALTER TABLE etablissement ADD COLUMN directeur TEXT NOT NULL DEFAULT ''",
  "ALTER TABLE etablissement ADD COLUMN devise TEXT NOT NULL DEFAULT ''",
  "ALTER TABLE etablissement ADD COLUMN infos_admin TEXT NOT NULL DEFAULT ''",
  'ALTER TABLE etablissement ADD COLUMN signature_directeur BLOB',
  'ALTER TABLE etablissement ADD COLUMN cachet BLOB',
  'ALTER TABLE annee_scolaire ADD COLUMN archivee INTEGER NOT NULL DEFAULT 0 '
      'CHECK (archivee IN (0, 1))',
  'ALTER TABLE classe ADD COLUMN capacite INTEGER '
      'CHECK (capacite IS NULL OR capacite > 0)',
  'ALTER TABLE classe ADD COLUMN prof_principal_id INTEGER '
      'REFERENCES enseignant(id) ON DELETE SET NULL',
  'ALTER TABLE matiere_classe ADD COLUMN bareme INTEGER NOT NULL DEFAULT 20 '
      'CHECK (bareme > 0 AND bareme <= 1000)',
  'ALTER TABLE matiere_classe ADD COLUMN facultative INTEGER NOT NULL DEFAULT 0 '
      'CHECK (facultative IN (0, 1))',
  'ALTER TABLE matiere_classe ADD COLUMN enseignant_id INTEGER '
      'REFERENCES enseignant(id) ON DELETE SET NULL',
  'ALTER TABLE eleve ADD COLUMN telephone TEXT',
  'ALTER TABLE eleve ADD COLUMN nom_tuteur TEXT',
  'ALTER TABLE eleve ADD COLUMN contact_tuteur TEXT',
  'ALTER TABLE eleve ADD COLUMN archive INTEGER NOT NULL DEFAULT 0 '
      'CHECK (archive IN (0, 1))',
  "ALTER TABLE inscription ADD COLUMN statut TEXT NOT NULL DEFAULT 'inscrit' "
      "CHECK (statut IN ('inscrit', 'depart', 'abandon'))",
  'ALTER TABLE inscription ADD COLUMN date_sortie TEXT',
  'ALTER TABLE inscription ADD COLUMN motif_sortie TEXT',
  // Note mensuelle saisie sur un barème différent de 20 : `valeur` reste la
  // note ramenée sur 20 ; `brut` et `bareme` gardent la saisie d'origine.
  'ALTER TABLE note ADD COLUMN brut INTEGER',
  'ALTER TABLE note ADD COLUMN bareme INTEGER',

  // ------------------------------------------------------------- Enseignants
  """
  CREATE TABLE enseignant (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    matricule TEXT UNIQUE,
    nom TEXT NOT NULL CHECK (length(trim(nom)) > 0),
    prenom TEXT NOT NULL CHECK (length(trim(prenom)) > 0),
    sexe TEXT CHECK (sexe IS NULL OR sexe IN ('M', 'F')),
    telephone TEXT,
    email TEXT,
    specialite TEXT,
    actif INTEGER NOT NULL DEFAULT 1 CHECK (actif IN (0, 1)),
    peut_saisir INTEGER NOT NULL DEFAULT 1 CHECK (peut_saisir IN (0, 1)),
    signature BLOB,
    cree_le TEXT NOT NULL
  )
  """,
  // Classes confiées à un enseignant (en plus de celles où il enseigne une
  // matière).
  """
  CREATE TABLE enseignant_classe (
    enseignant_id INTEGER NOT NULL REFERENCES enseignant(id) ON DELETE CASCADE,
    classe_id INTEGER NOT NULL REFERENCES classe(id) ON DELETE CASCADE,
    PRIMARY KEY (enseignant_id, classe_id)
  )
  """,

  // ------------------------------------------------------------ Utilisateurs
  """
  CREATE TABLE utilisateur (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    identifiant TEXT NOT NULL UNIQUE COLLATE NOCASE
      CHECK (length(trim(identifiant)) >= 3),
    nom_complet TEXT NOT NULL DEFAULT '',
    role TEXT NOT NULL
      CHECK (role IN ('administrateur', 'direction', 'saisie', 'consultation')),
    mot_de_passe_hash TEXT NOT NULL,
    sel TEXT NOT NULL,
    iterations INTEGER NOT NULL CHECK (iterations > 0),
    actif INTEGER NOT NULL DEFAULT 1 CHECK (actif IN (0, 1)),
    permissions TEXT,
    enseignant_id INTEGER REFERENCES enseignant(id) ON DELETE SET NULL,
    doit_changer_mdp INTEGER NOT NULL DEFAULT 0 CHECK (doit_changer_mdp IN (0, 1)),
    echecs_connexion INTEGER NOT NULL DEFAULT 0,
    verrouille_jusqua TEXT,
    cree_le TEXT NOT NULL,
    derniere_connexion TEXT
  )
  """,
  // Ligne unique : utilisateur connecté (pour signer l'historique) et
  // indicateur de transfert d'élève en cours.
  """
  CREATE TABLE contexte (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    utilisateur_id INTEGER,
    utilisateur_nom TEXT NOT NULL DEFAULT '',
    transfert INTEGER NOT NULL DEFAULT 0 CHECK (transfert IN (0, 1))
  )
  """,
  'INSERT INTO contexte (id) VALUES (1)',
  """
  CREATE TABLE journal_connexion (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date_heure TEXT NOT NULL,
    utilisateur_id INTEGER REFERENCES utilisateur(id) ON DELETE SET NULL,
    identifiant TEXT NOT NULL DEFAULT '',
    evenement TEXT NOT NULL,
    detail TEXT NOT NULL DEFAULT ''
  )
  """,
  """
  CREATE TABLE journal (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date_heure TEXT NOT NULL,
    utilisateur_id INTEGER REFERENCES utilisateur(id) ON DELETE SET NULL,
    utilisateur_nom TEXT NOT NULL DEFAULT '',
    action TEXT NOT NULL,
    entite TEXT NOT NULL DEFAULT '',
    entite_id INTEGER,
    details TEXT NOT NULL DEFAULT ''
  )
  """,
  'CREATE INDEX idx_journal_date ON journal(date_heure)',
  'CREATE INDEX idx_journal_connexion_date ON journal_connexion(date_heure)',

  // --------------------------------------------------- Calendrier par année
  """
  CREATE TABLE config_calendrier (
    annee_id INTEGER PRIMARY KEY REFERENCES annee_scolaire(id) ON DELETE CASCADE,
    json TEXT NOT NULL
  )
  """,

  // ------------------------------------------------------------- Évaluations
  // `coefficient` (centièmes) : poids de l'évaluation dans la note du mois.
  // `bareme` : note maximale (sur 10, 20, 40, 100...).
  """
  CREATE TABLE evaluation (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    classe_id INTEGER NOT NULL REFERENCES classe(id) ON DELETE RESTRICT,
    matiere_id INTEGER NOT NULL REFERENCES matiere_classe(id) ON DELETE RESTRICT,
    mois INTEGER NOT NULL CHECK (mois IN (1, 2, 3, 4, 5, 6, 10, 11, 12)),
    type TEXT NOT NULL CHECK (type IN
      ('evaluation', 'interrogation', 'devoir', 'composition', 'examen')),
    titre TEXT NOT NULL CHECK (length(trim(titre)) > 0),
    date_evaluation TEXT,
    coefficient INTEGER NOT NULL DEFAULT 100 CHECK (coefficient > 0),
    bareme INTEGER NOT NULL DEFAULT 20 CHECK (bareme > 0 AND bareme <= 1000),
    valide INTEGER NOT NULL DEFAULT 0 CHECK (valide IN (0, 1)),
    cree_le TEXT NOT NULL
  )
  """,
  // `brut` : note en centièmes sur le barème de l'évaluation (14,5 sur 20 ->
  // 1450 ; 7 sur 10 -> 700). La note ramenée sur 20 est calculée, jamais
  // stockée.
  """
  CREATE TABLE evaluation_note (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    evaluation_id INTEGER NOT NULL REFERENCES evaluation(id) ON DELETE CASCADE,
    inscription_id INTEGER NOT NULL REFERENCES inscription(id) ON DELETE RESTRICT,
    etat TEXT NOT NULL CHECK (etat IN ('saisie', 'absent', 'dispense')),
    brut INTEGER CHECK (brut IS NULL OR brut >= 0),
    modifie_le TEXT NOT NULL,
    UNIQUE (evaluation_id, inscription_id),
    CHECK (
      (etat = 'saisie' AND brut IS NOT NULL)
      OR (etat <> 'saisie' AND brut IS NULL)
    )
  )
  """,
  'CREATE INDEX idx_evaluation_classe ON evaluation(classe_id, matiere_id, mois)',
  'CREATE INDEX idx_evaluation_matiere ON evaluation(matiere_id)',
  'CREATE INDEX idx_evaluation_note_inscription ON evaluation_note(inscription_id)',

  // ------------------------------------------------ Verrouillage des résultats
  """
  CREATE TABLE verrou_notes (
    classe_id INTEGER NOT NULL REFERENCES classe(id) ON DELETE CASCADE,
    mois INTEGER NOT NULL CHECK (mois IN (1, 2, 3, 4, 5, 6, 10, 11, 12)),
    verrouille_le TEXT NOT NULL,
    utilisateur_nom TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (classe_id, mois)
  )
  """,

  // ------------------------------------------------------ Historique des notes
  // Pas de clés étrangères : l'historique survit à la suppression d'un élève ;
  // les noms sont recopiés au moment de l'opération.
  """
  CREATE TABLE historique_note (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date_heure TEXT NOT NULL,
    utilisateur_id INTEGER,
    utilisateur_nom TEXT NOT NULL DEFAULT '',
    source TEXT NOT NULL CHECK (source IN ('mensuelle', 'evaluation')),
    operation TEXT NOT NULL CHECK (operation IN ('creation', 'modification', 'suppression')),
    inscription_id INTEGER NOT NULL,
    matiere_id INTEGER,
    mois INTEGER,
    evaluation_id INTEGER,
    bareme INTEGER,
    eleve_nom TEXT,
    matiere_nom TEXT,
    classe_nom TEXT,
    ancien_etat TEXT,
    ancienne_valeur INTEGER,
    nouvel_etat TEXT,
    nouvelle_valeur INTEGER
  )
  """,
  'CREATE INDEX idx_historique_note_date ON historique_note(date_heure)',
  'CREATE INDEX idx_historique_note_inscription ON historique_note(inscription_id)',

  // ------------------------------------------- Mouvements d'inscription
  """
  CREATE TABLE mouvement_inscription (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    inscription_id INTEGER NOT NULL REFERENCES inscription(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN
      ('inscription', 'reinscription', 'changement_classe', 'depart', 'abandon', 'reprise')),
    date_mouvement TEXT NOT NULL,
    classe_origine_id INTEGER REFERENCES classe(id) ON DELETE SET NULL,
    classe_destination_id INTEGER REFERENCES classe(id) ON DELETE SET NULL,
    motif TEXT NOT NULL DEFAULT '',
    utilisateur_nom TEXT NOT NULL DEFAULT ''
  )
  """,
  'CREATE INDEX idx_mouvement_inscription ON mouvement_inscription(inscription_id)',
  // Les inscriptions déjà enregistrées reçoivent leur mouvement d'origine.
  """
  INSERT INTO mouvement_inscription (inscription_id, type, date_mouvement)
  SELECT id, 'inscription', date_inscription FROM inscription
  """,

  // --------------------------------------- Appréciations et décisions du conseil
  // `periode` : clé de période du calendrier (t1, s2...) ou 'annee'.
  """
  CREATE TABLE appreciation_matiere (
    inscription_id INTEGER NOT NULL REFERENCES inscription(id) ON DELETE CASCADE,
    matiere_id INTEGER NOT NULL REFERENCES matiere_classe(id) ON DELETE CASCADE,
    periode TEXT NOT NULL,
    texte TEXT NOT NULL,
    PRIMARY KEY (inscription_id, matiere_id, periode)
  )
  """,
  """
  CREATE TABLE appreciation_eleve (
    inscription_id INTEGER NOT NULL REFERENCES inscription(id) ON DELETE CASCADE,
    periode TEXT NOT NULL,
    appreciation TEXT NOT NULL DEFAULT '',
    decision_conseil TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (inscription_id, periode)
  )
  """,

  // ----------------------------------------------------------- Sauvegardes
  """
  CREATE TABLE sauvegarde (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    chemin TEXT NOT NULL,
    taille INTEGER NOT NULL DEFAULT 0,
    cree_le TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('manuelle', 'automatique', 'securite')),
    verifiee INTEGER NOT NULL DEFAULT 0 CHECK (verifiee IN (0, 1)),
    utilisateur_nom TEXT NOT NULL DEFAULT ''
  )
  """,

  // ------------------------------------- Déclencheurs : verrouillage et cohérence
  // Les anciens déclencheurs sont remplacés par des versions qui acceptent un
  // transfert d'élève en cours (contexte.transfert = 1).
  'DROP TRIGGER note_coherence_update',
  """
  CREATE TRIGGER note_coherence_update BEFORE UPDATE OF inscription_id, matiere_id ON note
  WHEN $_sansTransfert
  BEGIN
    SELECT RAISE(ABORT, 'Matiere hors classe')
    WHERE (SELECT classe_id FROM inscription WHERE id = NEW.inscription_id)
      IS NOT (SELECT classe_id FROM matiere_classe WHERE id = NEW.matiere_id);
  END
  """,
  'DROP TRIGGER inscription_classe_verrouillee',
  """
  CREATE TRIGGER inscription_classe_verrouillee BEFORE UPDATE OF classe_id ON inscription
  WHEN NEW.classe_id IS NOT OLD.classe_id
    AND $_sansTransfert
    AND EXISTS (SELECT 1 FROM note WHERE inscription_id = OLD.id)
  BEGIN
    SELECT RAISE(ABORT, 'Classe verrouillee: des notes existent');
  END
  """,
  // Un élève ayant des notes d'évaluation ne change pas de classe non plus.
  """
  CREATE TRIGGER inscription_classe_verrouillee_eval BEFORE UPDATE OF classe_id ON inscription
  WHEN NEW.classe_id IS NOT OLD.classe_id
    AND EXISTS (SELECT 1 FROM evaluation_note WHERE inscription_id = OLD.id)
  BEGIN
    SELECT RAISE(ABORT, 'Classe verrouillee: des notes existent');
  END
  """,
  """
  CREATE TRIGGER note_verrou_insert BEFORE INSERT ON note
  BEGIN
  ${_verrouNote('NEW')}
  END
  """,
  """
  CREATE TRIGGER note_verrou_update BEFORE UPDATE ON note
  WHEN $_sansTransfert
  BEGIN
  ${_verrouNote('OLD')}
  END
  """,
  """
  CREATE TRIGGER note_verrou_delete BEFORE DELETE ON note
  BEGIN
  ${_verrouNote('OLD')}
  END
  """,
  """
  CREATE TRIGGER evaluation_coherence_insert BEFORE INSERT ON evaluation
  BEGIN
    SELECT RAISE(ABORT, 'Matiere hors classe')
    WHERE (SELECT classe_id FROM matiere_classe WHERE id = NEW.matiere_id)
      IS NOT NEW.classe_id;
    SELECT RAISE(ABORT, 'Annee archivee') WHERE EXISTS (
      SELECT 1 FROM classe cl JOIN annee_scolaire a ON a.id = cl.annee_id
      WHERE cl.id = NEW.classe_id AND a.archivee = 1);
  END
  """,
  """
  CREATE TRIGGER evaluation_coherence_update BEFORE UPDATE OF classe_id, matiere_id ON evaluation
  BEGIN
    SELECT RAISE(ABORT, 'Matiere hors classe')
    WHERE (SELECT classe_id FROM matiere_classe WHERE id = NEW.matiere_id)
      IS NOT NEW.classe_id;
    SELECT RAISE(ABORT, 'Evaluation avec notes')
    WHERE EXISTS (SELECT 1 FROM evaluation_note WHERE evaluation_id = OLD.id);
  END
  """,
  """
  CREATE TRIGGER evaluation_bareme_verrouille BEFORE UPDATE OF bareme, mois ON evaluation
  WHEN NEW.bareme IS NOT OLD.bareme OR NEW.mois IS NOT OLD.mois
  BEGIN
    SELECT RAISE(ABORT, 'Evaluation avec notes')
    WHERE EXISTS (SELECT 1 FROM evaluation_note WHERE evaluation_id = OLD.id);
  END
  """,
  """
  CREATE TRIGGER evaluation_suppression BEFORE DELETE ON evaluation
  BEGIN
    SELECT RAISE(ABORT, 'Evaluation avec notes')
    WHERE EXISTS (SELECT 1 FROM evaluation_note WHERE evaluation_id = OLD.id);
    SELECT RAISE(ABORT, 'Evaluation validee') WHERE OLD.valide = 1;
    SELECT RAISE(ABORT, 'Mois verrouille') WHERE EXISTS (
      SELECT 1 FROM verrou_notes WHERE classe_id = OLD.classe_id AND mois = OLD.mois);
  END
  """,
  """
  CREATE TRIGGER evaluation_note_coherence_insert BEFORE INSERT ON evaluation_note
  BEGIN
  ${_verrouEvaluationNote('NEW')}
    SELECT RAISE(ABORT, 'Eleve hors classe')
    WHERE (SELECT classe_id FROM inscription WHERE id = NEW.inscription_id)
      IS NOT (SELECT classe_id FROM evaluation WHERE id = NEW.evaluation_id);
    SELECT RAISE(ABORT, 'Note hors bareme')
    WHERE NEW.brut IS NOT NULL
      AND NEW.brut > (SELECT bareme FROM evaluation WHERE id = NEW.evaluation_id) * 100;
  END
  """,
  """
  CREATE TRIGGER evaluation_note_coherence_update BEFORE UPDATE ON evaluation_note
  BEGIN
  ${_verrouEvaluationNote('OLD')}
    SELECT RAISE(ABORT, 'Eleve hors classe')
    WHERE (SELECT classe_id FROM inscription WHERE id = NEW.inscription_id)
      IS NOT (SELECT classe_id FROM evaluation WHERE id = NEW.evaluation_id);
    SELECT RAISE(ABORT, 'Note hors bareme')
    WHERE NEW.brut IS NOT NULL
      AND NEW.brut > (SELECT bareme FROM evaluation WHERE id = NEW.evaluation_id) * 100;
  END
  """,
  """
  CREATE TRIGGER evaluation_note_verrou_delete BEFORE DELETE ON evaluation_note
  BEGIN
  ${_verrouEvaluationNote('OLD')}
  END
  """,

  // ----------------------------------------------- Déclencheurs : historique
  ..._declencheursHistorique(
    table: 'note',
    source: 'mensuelle',
    matiere: 'REF.matiere_id',
    mois: (ref) => '$ref.mois',
    evaluation: (ref) => 'NULL',
    bareme: (ref) => 'NULL',
    valeur: 'valeur',
    prefixe: 'note',
  ),
  ..._declencheursHistorique(
    table: 'evaluation_note',
    source: 'evaluation',
    matiere: '(SELECT matiere_id FROM evaluation WHERE id = REF.evaluation_id)',
    mois: (ref) => '(SELECT mois FROM evaluation WHERE id = $ref.evaluation_id)',
    evaluation: (ref) => '$ref.evaluation_id',
    bareme: (ref) => '(SELECT bareme FROM evaluation WHERE id = $ref.evaluation_id)',
    valeur: 'brut',
    prefixe: 'evaluation_note',
  ),

  // ------------------------------------------------------------ Index divers
  'CREATE INDEX idx_inscription_statut ON inscription(annee_id, statut)',
  'CREATE INDEX idx_matiere_enseignant ON matiere_classe(enseignant_id)',
];
