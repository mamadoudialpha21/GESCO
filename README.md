# GESCO — gestion des notes scolaires

Application 100 % hors ligne (Flutter + SQLite local). Aucune connexion
Internet, aucun serveur : toutes les données sont dans un fichier sur l'appareil.

Priorité actuelle : version **Windows** complète avec installateur `.exe`.

## Où en est le projet

| Étape | Contenu | État |
|---|---|---|
| 1 | Socle : projet, schéma SQLite, migrations, contrôle d'intégrité | Écrit, **non exécuté** |
| 2 | Moteur de calcul : moyennes, rangs, mentions, décisions, statistiques | Écrit, **non exécuté** |
| 3 | Paramètres : établissement et logo, années, classes, matières, coefficients, seuils | Écrit, **non exécuté** |
| 4 | Inscriptions et fiches élèves : ajout, modification, fiche, suppression, recherche, réinscription, photo | Écrit, **non exécuté** |
| 5 | Saisie des notes avec enregistrement automatique | À faire |
| 6 | Classements, exports PDF / Excel, impression | À faire |
| 7 | Bulletins trimestriels et annuel (PDF A4) | À faire |
| 8 | Notes finales | À faire |
| 9 | Connexion, rôles, sauvegarde et restauration | À faire |
| 10 | Finitions, documentation, installateur final | À faire |
| 11 | Android, macOS, iOS | À faire |

## Ce que « vérifié » veut dire ici

Le code a été rédigé dans un environnement qui **ne peut pas installer Flutter
ni Dart** (les sites nécessaires y sont bloqués). **Aucun test Dart n'a donc été
exécuté et l'application n'a jamais été lancée.** Rien n'est considéré comme
fonctionnel tant que les tests n'ont pas réussi chez vous (ou sur GitHub) et que
la liste de `docs/VERIFICATION_MANUELLE.md` n'a pas été parcourue.

Ce qui a pu être contrôlé sans Flutter, avec de vrais outils :

| Contrôle | Portée | Limite |
|---|---|---|
| Analyseur de grammaire Dart (tree-sitter) | Syntaxe de tous les fichiers `.dart` | Ne vérifie pas les types |
| SQLite réel sur le schéma | 58 scénarios (bornes, doublons, clés étrangères, suppressions refusées), lancés à l'étape 1 ; le trigger ajouté à l'étape 4 est couvert par les contrôles « inscriptions » ci-dessous | Teste le SQL, pas le code Dart |
| Requêtes SQL extraites du code Dart | 92 requêtes et noms de colonnes des dépôts valides contre le schéma | Contrôle statique |
| Comportements SQLite utilisés par les dépôts | 15 (activation d'année, `REPLACE`, cascades, copie d'année, tri) | Idem |
| Comportements SQLite des inscriptions | 29 (listes, élèves à réinscrire, doublons, clé étrangère composite, suppression avec et sans notes, trigger de verrouillage de classe, tri accents/casse) | Idem |
| Contrôle croisé interface ↔ dépôts | Méthodes, paramètres nommés requis/inconnus, imports inutilisés ou manquants (54 fichiers) | Heuristique : n'est pas le compilateur ; 7 faux positifs connus (listes locales nommées `classes`/`matieres`) |
| Valeurs attendues des tests du moteur | Recalculées avec un programme indépendant | Ne remplace pas l'exécution |

Ces contrôles ont déjà permis de corriger des défauts (syntaxe Dart trop
récente, comparaison de noms accentués), mais **une erreur de compilation ou de
type reste possible**. Le premier passage sur GitHub ou sur votre PC le dira ;
envoyez-moi alors le message d'erreur.

## Vérifier et compiler

### Option A — GitHub (recommandé, rien à installer)

1. Créez un dépôt GitHub (privé si vous voulez) et envoyez-y tout le contenu de
   ce dossier, y compris le dossier caché `.github`.
2. Ouvrez l'onglet **Actions** : le workflow « GESCO - tests et installateur
   Windows » se lance seul (ou bouton *Run workflow*).
3. Le premier job (`Analyse et tests`) lance les tests. L'analyse statique y est
   informative : un avertissement de style n'arrête rien, c'est l'échec d'un
   test ou de la compilation qui est bloquant. Le second job (`Compilation et
   installateur .exe`) compile l'application et produit `GESCO-Setup-0.1.0.exe`,
   téléchargeable en bas de la page de l'exécution (*Artifacts*).
4. Si une étape devient rouge, copiez-moi son message d'erreur : je corrige.

### Option B — sur votre PC Windows

1. Installez Flutter (https://docs.flutter.dev/get-started/install/windows),
   **Visual Studio Build Tools** avec la charge de travail « Développement
   Desktop en C++ », et **Inno Setup 6** (https://jrsoftware.org/isdl.php).
2. Dans PowerShell, à la racine du projet :

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\scripts\build_windows.ps1
   ```

   Le script lance les tests du moteur de calcul, compile et crée
   l'installateur dans `installer\Output`.
3. Les tests de la base de données ont besoin de `sqlite3.dll` sous Windows : ils
   sont exécutés automatiquement par GitHub (option A). Pour les lancer sur
   votre PC, placez `sqlite3.dll` à la racine du projet puis
   `.\scripts\build_windows.ps1 -ToutesLesTests`.

### Premier essai de l'application

Après compilation, lancez `gesco.exe` et suivez `docs/VERIFICATION_MANUELLE.md`.

## Où sont les données ?

Sous Windows : `%APPDATA%\gn.gesco\gesco\gesco.db`. Ce dossier est conservé
lors des mises à jour et de la désinstallation. Le chemin exact est rappelé sur
le Tableau de bord. La sauvegarde et la restauration intégrées seront ajoutées
à l'étape 9 ; en attendant, copier ce fichier (application fermée) est une
sauvegarde complète.

## Structure

```
lib/domain/   Moteur de calcul (Dart pur) : arrondi, périodes, modèles,
              configuration des seuils, moteur de résultats, statistiques,
              dates, recherche sans accents, matricules
lib/data/     Schéma SQLite, ouverture de la base, migrations, images,
              validation des fiches, dépôts (établissement, années, classes,
              matières, seuils, élèves et inscriptions)
lib/app/      État partagé de l'application, accès aux dépôts
lib/ui/       Écrans : coquille de navigation, tableau de bord, paramètres,
              inscriptions (liste, formulaire, fiche, réinscription)
test/         Tests du moteur, de la base, des dépôts, des composants et des
              formulaires d'inscription
docs/         Règles de calcul (à valider), règles des inscriptions, liste de vérification manuelle
installer/    Script Inno Setup de l'installateur Windows
scripts/      Script de construction pour votre PC
.github/      Workflow de vérification et de compilation automatiques
```

Les dossiers `windows/`, `android/`... sont générés par `flutter create` (le
workflow et le script le font automatiquement) ; il n'est pas nécessaire de les
envoyer sur GitHub.

## Choix techniques

- **SQL direct (sqflite_common_ffi)** plutôt que Drift : Drift demande une
  génération de code impossible à contrôler dans l'environnement de rédaction.
  Les données restent dans un fichier SQLite local.
- **État de l'application par `ChangeNotifier`** (inclus dans Flutter) plutôt
  que Riverpod : une dépendance de moins à résoudre.
- **Pas de mode WAL** : le journal SQLite par défaut garde un seul fichier, ce
  qui simplifie la sauvegarde sur clé USB.
- Interface de l'étape 3 pensée pour l'ordinateur ; l'adaptation tablettes et
  téléphones est prévue à l'étape 11.
