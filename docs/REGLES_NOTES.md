# Règles de la saisie des notes

Ce document décrit ce que fait GESCO (étape 5). Chaque règle est appliquée par le
code **et** vérifiée par un test automatique ; la base de données ajoute un
second filet pour les plus importantes. Le calcul des moyennes, rangs et
mentions est décrit dans `REGLES_DE_CALCUL.md` : la page Notes n'a pas de calcul
à elle, elle affiche ce que fournit le moteur.

## Où et comment saisir

Menu **Notes** → choisir la **classe** puis le **mois** (octobre à juin). Le
tableau montre un élève par ligne et une matière par colonne, avec le
coefficient sous le nom de la matière. Les matières et coefficients viennent des
paramètres de la classe.

- Cliquer sur une case, taper la note, **Entrée** : la note est enregistrée et
  la case de l'élève suivant (même matière) s'ouvre. Idéal pour saisir toute une
  colonne.
- **Tab** / **Maj+Tab** : matière suivante / précédente ; **flèches haut et
  bas** : élève précédent / suivant ; **Échap** : abandonner la frappe en cours.
- Cliquer directement sur une autre case valide la saisie en cours.

## Ce qu'on peut taper

| Saisie | Effet |
|---|---|
| `14`, `14,5`, `14.75`, `7,05` | Note chiffrée de 0 à 20, **2 décimales au plus**, virgule ou point |
| `0` | Un **vrai zéro** : il compte dans la moyenne |
| `A`, `ABS`, `absent` | Élève **absent** (affiché `ABS`) |
| `D`, `DISP`, `dispensé` | Élève **dispensé** (affiché `DISP`) |
| case vidée | Note **non saisie** : la note est supprimée |
| `25`, `14,555`, `abc`, `-3` | **Refusé** avec un message précis ; rien n'est enregistré |

**Une case vide, un absent et un dispensé ne sont jamais comptés comme zéro** :
ils sont ignorés dans la moyenne de l'élève. Le résultat est alors marqué d'une
étoile orange (`*`) : « des notes manquent, moyenne calculée sur les notes
saisies ».

## Enregistrement automatique

- La note est enregistrée **dès Entrée, Tab, flèche ou clic ailleurs**, et aussi
  **0,7 seconde après la dernière touche** si l'on ne fait rien : fermer le
  logiciel juste après avoir tapé ne perd pas la note.
- Le bandeau indique l'état : « Enregistrement… » puis « Enregistré
  automatiquement ». Il n'y a pas de bouton Enregistrer.
- Si l'enregistrement échoue (disque plein, base verrouillée…), la case **revient
  à sa valeur d'avant** et un message rouge « Note non enregistrée : … » reste
  affiché. L'écran ne montre jamais une note qui n'est pas dans la base.
- Les notes sont conservées **brutes** (en centièmes, `14,75` = `1475`) avec la
  date de modification. Les moyennes ne sont **jamais stockées** : elles sont
  recalculées à chaque affichage, donc toujours cohérentes.

## Recalcul en direct (mois)

À chaque changement, pour le mois affiché, le tableau met à jour : la **moyenne**
de chaque élève (pondérée par les coefficients, colorée vert / orange / rouge
d'après les seuils des paramètres), le **rang** (avec « ex æquo »), la
**mention**, la **moyenne de la classe pour chaque matière** (ligne grisée en
bas), et les statistiques de la classe (moyenne, admis, taux de réussite,
meilleure et plus faible moyenne). Le bandeau indique aussi l'avancement :
« Octobre : 37 / 42 cases renseignées ».

## Trimestres et année (lecture seule)

Les puces **Trimestre 1, 2, 3** et **Année** affichent les résultats calculés à
partir des moyennes mensuelles (T1 = octobre à décembre, T2 = janvier à mars,
T3 = avril à juin). On n'y saisit rien : les notes se saisissent mois par mois.
La vue Année montre les trois moyennes de trimestre, la moyenne annuelle, le
rang, la mention et la décision (admis en classe supérieure, redouble…).

## Protections

| Situation | Comportement |
|---|---|
| Mois hors octobre à juin | Refusé par le code |
| Matière qui n'appartient pas à la classe de l'élève | Refusé par le code **et** par un déclencheur de la base |
| Élève ou matière supprimés entre-temps | Message « n'existe plus : rechargez la page » |
| Élève qui a des notes : changement de classe | Refusé par la base (une note est rattachée à la classe) |
| Matière qui a des notes : suppression | Refusée (les notes ne disparaissent jamais en silence) |
| Suppression d'un élève qui a des notes | Double confirmation, puis ses notes sont supprimées avec lui |

## Limites actuelles

- Pas encore de classement imprimable, d'export PDF / Excel ni de bulletins
  (étapes suivantes).
- Pas de saisie par trimestre : la saisie est mensuelle, comme demandé.
