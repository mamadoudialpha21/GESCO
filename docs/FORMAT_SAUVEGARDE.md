# Sauvegardes GESCO : fonctionnement et format du fichier

Ce document décrit ce que GESCO sauvegarde, comment il vérifie ses sauvegardes,
comment il les restaure, et le format exact du fichier. Ce format est volontairement
simple : une sauvegarde peut être copiée sur une clé USB, installée sur un autre
ordinateur, ou ouverte avec n'importe quel outil de compression pour récupérer la
base de données sans GESCO.

## 1. Ce que contient une sauvegarde

Une sauvegarde est une **copie complète de la base de données** de GESCO :

- établissement, années scolaires, classes, matières, élèves, inscriptions ;
- évaluations, notes, appréciations, absences, périodes (calendriers) et règles de
  calcul des résultats ;
- enseignants et leurs classes ;
- **comptes utilisateurs et leurs permissions** (rôle, permissions personnalisées,
  compte limité à un enseignant). Les mots de passe sont enregistrés sous forme
  hachée (PBKDF2), jamais en clair ;
- paramètres du logiciel (délai de verrouillage, sauvegarde automatique…) ;
- journaux (opérations, connexions, historique des notes).

Les documents déjà générés (bulletins PDF, fichiers Excel) ne sont pas dans la
sauvegarde : ils se régénèrent à partir des données.

## 2. Le fichier

Nom : `GESCO_sauvegarde_AAAA-MM-JJ_HHMMSS_<type>.zip`, par exemple
`GESCO_sauvegarde_2026-11-25_190000_automatique.zip`.

`<type>` vaut `manuelle`, `automatique` ou `securite` (copie faite automatiquement
juste avant une restauration).

C'est une archive **.zip standard** (méthodes « stockée » et « deflate », noms en
UTF-8, pas de mot de passe). Elle contient trois fichiers :

| Fichier          | Rôle                                                              |
|------------------|-------------------------------------------------------------------|
| `manifeste.json` | Descriptif de la sauvegarde (voir ci-dessous).                    |
| `LISEZ-MOI.txt`  | Notice lisible : contenu, et comment restaurer.                   |
| `gesco.db`       | La base de données SQLite (copie cohérente faite par `VACUUM INTO`). |

### 2.1 `manifeste.json`

```json
{
  "format": "GESCO-SAUVEGARDE",
  "version_format": 1,
  "version_schema": 4,
  "version_application": "0.4.0",
  "cree_le": "2026-11-25T19:00:00",
  "type": "automatique",
  "utilisateur": "Système",
  "etablissement": "Groupe Scolaire Test",
  "annee": "2026-2027",
  "contenu": {
    "eleves": 2, "inscriptions": 2, "classes": 1, "matieres": 0,
    "evaluations": 0, "notes": 0, "notes_evaluations": 0,
    "enseignants": 0, "comptes": 1
  },
  "base": { "fichier": "gesco.db", "sha256": "…64 caractères hexadécimaux…", "taille": 417792 }
}
```

- `format` et `version_format` : GESCO refuse un fichier d'un autre format, et un
  fichier d'une version de format plus récente que celle qu'il connaît.
- `version_schema` : version du schéma de la base (`PRAGMA user_version`). Une
  sauvegarde plus ancienne que l'application est restaurée puis mise à jour
  automatiquement ; une sauvegarde plus récente est refusée.
- `cree_le` : date et heure locales de la copie.
- `contenu` : nombre de lignes de quelques tables, pour comparer avant de restaurer.
- `base.sha256` et `base.taille` : empreinte SHA-256 et taille exactes de `gesco.db`.

### 2.2 Récupérer les données sans GESCO

1. Ouvrir le fichier `.zip` avec l'explorateur Windows ou n'importe quel logiciel de
   compression, et extraire `gesco.db`.
2. L'ouvrir avec n'importe quel outil SQLite (DB Browser for SQLite, `sqlite3`…).

## 3. Sauvegarde

### 3.1 Sauvegarde manuelle

Sécurité > Sauvegardes > « Sauvegarder maintenant » (dans le dossier de GESCO) ou
« Sauvegarder sur une clé USB ou un dossier… ». Il faut la permission « Créer et
consulter les sauvegardes ».

### 3.2 Sauvegarde automatique

- Activée par défaut, **chaque jour à l'heure choisie** (18 h 00 par défaut).
- Si l'ordinateur était éteint à l'heure prévue, la sauvegarde manquée est **faite au
  démarrage de GESCO** (une seule, même après plusieurs jours d'arrêt).
- GESCO garde les **N dernières sauvegardes automatiques valides** (7 par défaut,
  réglable). Seules les sauvegardes automatiques sont supprimées par cette rotation :
  les sauvegardes manuelles et les sauvegardes de sécurité ne le sont jamais.
- Option : copie de chaque sauvegarde automatique sur une clé USB ou un disque
  externe. Si la clé est absente, la sauvegarde interne est faite quand même et un
  avertissement est affiché.
- Un échec n'est jamais silencieux : l'écran Sauvegardes affiche le motif. Après un
  échec, GESCO ne retente qu'après 15 minutes.

### 3.3 Vérification

Une sauvegarde n'est enregistrée dans l'historique **qu'après avoir été relue** :

1. l'archive se lit entièrement (structure et sommes de contrôle CRC-32) ;
2. `manifeste.json` est reconnu et complet ;
3. la taille et l'empreinte SHA-256 de `gesco.db` sont celles du descriptif ;
4. la base s'ouvre, `PRAGMA integrity_check` et `PRAGMA foreign_key_check` ne
   signalent aucun problème, et les tables indispensables sont présentes ;
5. la version du schéma est connue de cette version de GESCO.

Si un contrôle échoue, le fichier est supprimé et une erreur est affichée.
Le fichier est d'abord écrit sous le nom `….zip.partiel`, puis renommé : une coupure
d'électricité ne laisse jamais une archive incomplète sous un nom de sauvegarde.

Le bouton « Contrôler » de l'historique refait ces contrôles à tout moment.

## 4. Restauration

Sécurité > Sauvegardes > « Restaurer » (sur une ligne de l'historique, ou « Restaurer
depuis un fichier… » pour un fichier copié depuis une clé USB, y compris venant d'un
autre ordinateur). Il faut la permission « Restaurer une sauvegarde »
(administrateur par défaut).

Les neuf étapes affichées à l'écran :

1. Choisir la sauvegarde.
2. Vérifier le fichier (contrôles du § 3.3). **Si un contrôle échoue, rien n'est
   modifié.**
3. Comparer avec les données actuelles (élèves, classes, notes, comptes… et
   avertissements : sauvegarde ancienne, notes qui seraient perdues, base plus
   ancienne qui sera mise à jour).
4. Confirmer (case à cocher obligatoire).
5. **Sauvegarde de sécurité** des données actuelles. Si elle échoue, la
   restauration est annulée avant tout changement.
6. Remplacement des données : la base actuelle est mise de côté
   (`gesco.db.avant-restauration`) puis remplacée.
7. Réouverture de la base (les mises à jour de schéma éventuelles s'appliquent).
8. Contrôle des données restaurées (intégrité et clés étrangères).
9. Terminé : la restauration est inscrite au journal, la sauvegarde de sécurité reste
   dans l'historique, et GESCO redémarre sur les nouvelles données.

**Retour arrière** : si une erreur survient après l'étape 6, les données précédentes
sont remises en place et rouvertes automatiquement ; l'écran l'indique. Si même cela
échoue (disque indisponible…), le message donne l'emplacement exact des données
conservées et de la sauvegarde de sécurité.

Après une restauration, **les comptes et les permissions sont ceux de la
sauvegarde** : il faut se reconnecter avec un compte qui existait au moment de la
sauvegarde.

### Transfert vers un autre ordinateur

1. Sur l'ordinateur d'origine : « Sauvegarder sur une clé USB ou un dossier… ».
2. Installer GESCO (même version ou plus récente) sur l'autre ordinateur.
3. Brancher la clé, ouvrir GESCO, créer le premier compte administrateur si GESCO le
   demande, puis Sécurité > Sauvegardes > « Restaurer depuis un fichier… ».

## 5. Mises à jour de GESCO

Avant d'ouvrir une base dont le schéma est plus ancien que celui de l'application
(donc avant de la mettre à jour), GESCO copie le fichier tel quel dans le dossier
`sauvegardes`, sous le nom `avant-mise-a-jour_vX-vers-vY_AAAA-MM-JJ_HHMMSS.db`.
Ces copies apparaissent dans l'historique (type « Avant une mise à jour »). Elles
sont des fichiers SQLite bruts, pas des archives : pour y revenir, les ouvrir avec un
outil SQLite ou remplacer `gesco.db` après avoir fermé GESCO.

## 6. Emplacements (Windows)

- Base : `%APPDATA%\<organisation>\gesco\gesco.db`
- Sauvegardes : `%APPDATA%\<organisation>\gesco\sauvegardes\`

## 7. Limites connues

- La sauvegarde automatique ne se fait que quand GESCO est ouvert (ou démarre) ;
  GESCO n'installe pas de service Windows.
- Les sauvegardes ne sont pas chiffrées : elles contiennent des données d'élèves et
  des comptes (mots de passe hachés). Gardez la clé USB en lieu sûr.
- Une sauvegarde interne reste sur le même disque que la base : pour se protéger d'une
  panne de disque, utilisez aussi la copie sur clé USB ou disque externe.
