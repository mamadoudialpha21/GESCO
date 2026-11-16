# Règles des inscriptions et des fiches élèves

Ce document décrit ce que fait GESCO (étape 4). Chaque règle est appliquée par le
code **et** vérifiée par un test automatique ; la base de données ajoute un
second filet pour les plus importantes.

## Fiche élève et inscription : deux notions distinctes

- La **fiche** contient l'identité de l'élève : matricule, nom, prénom, sexe,
  date et lieu de naissance, père, mère, contact du parent ou tuteur, adresse,
  photo. Elle est enregistrée **une seule fois**.
- L'**inscription** relie la fiche à **une classe** pour **une année scolaire**.
  Les notes, classements et bulletins s'appuient sur l'inscription.

Conséquence : un élève réinscrit l'année suivante garde sa fiche et son
matricule ; ses notes d'une année ne se mélangent jamais avec celles d'une autre.

## Champs

| Champ | Règle |
|---|---|
| Nom, prénom | Obligatoires, 60 caractères maximum, espaces autour retirés |
| Matricule | Obligatoire, 40 caractères maximum, **unique** (majuscules et minuscules considérées identiques, accents compris : `É` = `é`) |
| Sexe | Obligatoire : masculin ou féminin |
| Date de naissance | Facultative. Saisie `JJ/MM/AAAA` (séparateurs `/`, `-` ou `.`, jour et mois sur 1 ou 2 chiffres) ou calendrier. Une date inexistante (`31/02`) ou antérieure à 1900 est refusée. **Jamais dans le futur** (aujourd'hui est accepté). Stockée au format `AAAA-MM-JJ` |
| Lieu, père, mère, contact, adresse | Facultatifs, 120 caractères maximum |
| Photo | Facultative, PNG ou JPEG (reconnu d'après le contenu du fichier, pas d'après son extension), **1 Mo maximum** (exactement 1 Mo est accepté) |
| Classe | Obligatoire à l'inscription ; doit appartenir à l'année scolaire concernée |

Aucune limite sur le nombre d'élèves, de classes ou d'années.

## Matricule proposé

Le bouton « baguette » et le premier formulaire proposent `AAAA-NNNN` :
`AAAA` est l'année de début de l'année scolaire (`2026-2027` → `2026`) et `NNNN`
le plus grand numéro déjà utilisé avec ce préfixe, plus 1, sur 4 chiffres
(`2026-0001`, `2026-0002`…). Les matricules d'un autre format sont ignorés pour
ce calcul. Si l'année ne contient aucun nombre de 4 chiffres, la proposition est
simplement `0001`, `0002`… La proposition peut toujours être modifiée à la main.

## Liste, tri et recherche

- La liste montre les élèves **de l'année sélectionnée**, éventuellement d'une
  seule classe.
- Tri par nom puis prénom, **sans tenir compte des accents ni des majuscules**
  (`Camara` avant `Éloi`).
- Recherche en direct sur le nom, le prénom et le matricule : minuscules,
  accents ignorés (`zoe` trouve `Zoé`), **chaque mot saisi doit se retrouver**
  (`aminata diallo` et `diallo aminata` donnent le même résultat). Une recherche
  vide affiche tout. Le compteur indique `x élèves sur y` quand une recherche
  est active.

## Modifier

- La fiche peut être modifiée à tout moment ; le matricule aussi (il doit rester
  unique).
- La **classe** peut être changée tant que l'élève n'a **aucune note** dans
  l'année. Dès qu'une note existe, la classe est verrouillée : les notes
  portent sur les matières de la classe d'origine, les déplacer fausserait les
  moyennes. Le formulaire le dit, le dépôt de données le refuse, et la base le
  refuse aussi en dernier recours (`inscription_classe_verrouillee`).
- Une modification est **tout ou rien** : si le changement de classe est refusé,
  les autres changements de la fiche ne sont pas enregistrés non plus.

## Réinscrire un élève déjà connu

« Réinscrire… » liste les élèves enregistrés qui ne sont **pas encore inscrits**
dans l'année sélectionnée. On choisit la classe de destination, on coche les
élèves (ou « Tout sélectionner » : seulement ceux qui sont affichés après
recherche), puis on valide.

- Un élève ne peut être inscrit **qu'une fois par année**.
- Chaque réinscription est enregistrée séparément. Si une erreur survient au
  milieu, GESCO indique combien d'élèves ont été réinscrits avant l'arrêt ; ceux
  qui l'ont été sont conservés.
- La fiche et les notes des années précédentes ne sont pas modifiées.

## Supprimer

La suppression retire l'**inscription** de l'année sélectionnée :

1. **Sans note** : une confirmation. Si c'était la seule inscription de l'élève,
   sa fiche est supprimée aussi ; sinon la fiche est conservée (il reste inscrit
   dans une autre année).
2. **Avec des notes** : une première alerte indique le nombre de notes qui seront
   supprimées, puis une **dernière confirmation** est demandée. Les notes de cet
   élève pour cette année disparaissent avec lui, et **seulement les siennes**.
3. Tout se fait en une seule opération : en cas de problème, rien n'est supprimé.

La suppression est définitive ; seule la restauration d'une sauvegarde permet de
revenir en arrière (sauvegardes : étape 9, pas encore réalisée).

Une **classe** qui contient des élèves ne peut pas être supprimée (message
« 1 élève y est inscrit ») tant qu'ils n'ont pas été retirés ou changés de classe.

## Formulaire

- Les erreurs sont listées dans un encadré rouge **sous** le formulaire (toujours
  visible, même si on a fait défiler le formulaire).
- Si l'enregistrement est refusé (par exemple matricule déjà utilisé), le
  formulaire **reste ouvert avec toute la saisie** : rien n'est à retaper.
- « Enregistrer et ajouter un autre » enregistre, vide le formulaire (la classe
  est conservée), propose le matricule suivant et compte les élèves saisis. Les
  informations des parents ne sont volontairement pas reprises, pour éviter de
  les copier par erreur sur un élève sans lien.

## Ce qui n'est pas encore vérifiable

La saisie des notes n'existe qu'à l'étape 5. Les règles « changement de classe
refusé avec notes » et « suppression avec notes » sont donc couvertes par les
tests automatiques et les contrôles SQLite, mais **ne pourront être essayées à
la main dans l'interface qu'après l'étape 5**.
