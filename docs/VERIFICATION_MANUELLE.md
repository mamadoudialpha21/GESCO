# Vérification manuelle — étapes 3 (Paramètres) et 4 (Inscriptions)

À faire une fois l'application lancée sur Windows (`flutter run -d windows`, ou
l'installateur produit par GitHub / le script PowerShell).

Les tests automatiques vérifient la logique et la base de données. **Cette liste
vérifie ce qu'ils ne voient pas : l'interface.** Cochez chaque ligne ; pour
toute ligne qui ne se passe pas comme décrit, notez le numéro et ce que vous
voyez (une capture d'écran aide beaucoup).

## A. Premier lancement

| # | Action | Résultat attendu |
|---|---|---|
| A1 | Lancer GESCO sur une machine neuve | La fenêtre s'ouvre sur le **Tableau de bord** : « Établissement non renseigné », « Aucune année scolaire » |
| A2 | Regarder la barre du haut | Bouton « Créer l'année scolaire » à droite |
| A3 | Lire le cadre bleu en bas | Il indique le chemin du fichier de données (dossier `AppData`) |

## B. Années scolaires

| # | Action | Résultat attendu |
|---|---|---|
| B1 | Paramètres → Années scolaires → **Nouvelle année** | Le champ propose l'année en cours (ex. `2026-2027`) |
| B2 | Valider | L'année apparaît avec les étiquettes **Active** et **Affichée** ; le sélecteur du haut la montre |
| B3 | Créer `2026-2027` une seconde fois | Message rouge « existe déjà » |
| B4 | Créer un libellé vide | Message « obligatoire » |

## C. Établissement et logo

| # | Action | Résultat attendu |
|---|---|---|
| C1 | Établissement : saisir nom, adresse, téléphone, e-mail → **Enregistrer** | Message vert ; le nom apparaît sur le Tableau de bord |
| C2 | **Choisir un logo…** → un fichier PNG ou JPEG | Aperçu du logo dans le carré ; après **Enregistrer**, le logo s'affiche sur le Tableau de bord |
| C3 | Choisir une image de plus de 2 Mo | Message rouge « trop volumineux » ; le logo précédent est conservé |
| C4 | Renommer un fichier texte en `.png` et le choisir | Message rouge « doit être une image PNG ou JPEG » |
| C5 | **Retirer le logo** → Enregistrer | Le logo disparaît du Tableau de bord |

## D. Classes et matières

| # | Action | Résultat attendu |
|---|---|---|
| D1 | Classes et matières → **Ajouter** une classe `10e A`, niveau `10e année` | La classe apparaît à gauche et est sélectionnée |
| D2 | Ajouter une classe `10E a` | Message rouge « existe déjà » (la casse est ignorée) |
| D3 | Ajouter les matières : Mathématiques `4`, Français `3`, Anglais `2` | Les 3 matières s'affichent ; **Total des coefficients : 9** |
| D4 | Ajouter une matière avec le coefficient `2,5` puis `2.5` | Les deux saisies sont acceptées ; l'affichage est « 2,5 » |
| D5 | Ajouter une matière avec le coefficient `0`, puis `abc`, puis `100` | Message « Coefficient invalide » à chaque fois |
| D6 | Ajouter une matière `mathématiques` (minuscule) | Message rouge « existe déjà » |
| D7 | Flèches ↑ ↓ à gauche d'une matière | L'ordre change et reste après rechargement |
| D8 | Modifier le coefficient d'une matière | Le total se met à jour |
| D9 | Créer une classe `10e B`, **Copier depuis une autre classe…** → `10e A` | Les matières de `10e A` sont copiées avec leurs coefficients |
| D10 | Supprimer une matière (confirmation demandée) | Elle disparaît |
| D11 | Supprimer la classe `10e B` (confirmation demandée) | Elle disparaît avec ses matières |
| D12 | Créer 15 matières dans une classe | Aucune limite n'apparaît |

## E. Plusieurs années

| # | Action | Résultat attendu |
|---|---|---|
| E1 | Années scolaires → **Nouvelle année** `2027-2028`, cocher « Reprendre les classes… » depuis `2026-2027` | L'année est créée (non active) |
| E2 | Sélecteur du haut → `2027-2028` | Une étiquette orange « Année non active » apparaît ; les classes et matières de `2026-2027` sont présentes |
| E3 | Dans `2027-2028`, changer un coefficient | Dans `2026-2027`, ce coefficient n'a **pas** changé |
| E4 | **Rendre active** `2027-2028` | L'étiquette Active passe à cette année |
| E5 | Supprimer `2027-2028` (active) | Le bouton n'existe pas pour l'année active |
| E6 | Supprimer `2026-2027` (contient des classes) | Message rouge « contient 1 classe » |

## F. Mentions et décisions

| # | Action | Résultat attendu |
|---|---|---|
| F1 | Ouvrir l'onglet | Admission `10,00`, bon `12,00`, mentions Passable → Excellent |
| F2 | Mettre l'admission à `9,5` → **Enregistrer** | Message vert ; en changeant d'onglet puis en revenant, `9,50` est conservé |
| F3 | Saisir `abc` comme seuil → Enregistrer | Message rouge, rien n'est enregistré |
| F4 | Deux mentions avec le même seuil → Enregistrer | Message rouge « seuil en double » |
| F5 | Retirer le palier à `0,00` des décisions → Enregistrer | Message rouge « prévoir un palier à 0,00 » |
| F6 | **Valeurs par défaut** | Les champs reprennent les valeurs d'origine ; rien n'est enregistré avant d'avoir cliqué sur Enregistrer |
| F7 | Changer d'année dans le sélecteur | Les seuils affichés sont ceux de cette année (indépendants) |

## G. Inscriptions

Prérequis : l'année `2026-2027` avec les classes `10e A` et `10e B` (section D).
Règles détaillées : `docs/REGLES_INSCRIPTIONS.md`.

| # | Action | Résultat attendu |
|---|---|---|
| G1 | Menu **Inscriptions** | Liste vide, « Aucun élève inscrit pour cette année scolaire », compteur `0 élève` |
| G2 | **Inscrire un élève** | Formulaire ; matricule proposé `2026-0001` ; la première classe est présélectionnée ; le nom a le curseur |
| G3 | Cliquer **Enregistrer** sans rien saisir | Encadré rouge sous le formulaire : nom, prénom et sexe obligatoires ; le formulaire reste ouvert |
| G4 | Saisir `Diallo`, `Aminata`, sexe **Féminin**, date `05/03/2011` → **Enregistrer** | Le formulaire se ferme, message vert, l'élève apparaît : `DIALLO Aminata`, avec matricule, classe et date de naissance |
| G5 | **Inscrire un élève** en remplaçant le matricule proposé par celui d'un élève déjà inscrit (par exemple `2026-0001`) → Enregistrer | Message rouge « déjà utilisé » ; le formulaire **reste ouvert avec toute la saisie** (rien à retaper) |
| G6 | Date `31/02/2011` | Message rouge sous le champ date ; rien n'est enregistré |
| G7 | Icône calendrier du champ date, choisir une date | Le champ se remplit au format `JJ/MM/AAAA` |
| G8 | Date de naissance dans le futur | Message rouge « ne peut pas être dans le futur » |
| G9 | **Ajouter une photo…**, choisir un PNG ou JPEG de moins de 1 Mo | Aperçu rond ; bouton « Retirer » disponible |
| G10 | Choisir une image de plus de 1 Mo, ou un fichier texte renommé en `.png` | Message rouge dans le formulaire (« trop volumineux » / « doit être une image PNG ou JPEG ») ; l'ancienne photo est conservée |
| G11 | **Enregistrer et ajouter un autre** (avec nom, prénom, sexe saisis) | Message vert « 1 élève enregistré pendant cette saisie » ; formulaire vidé (classe conservée) ; matricule suivant proposé ; le bouton Annuler devient **Fermer** |
| G12 | Inscrire ainsi une dizaine d'élèves, répartis dans `10e A` et `10e B` | Tous apparaissent dans la liste, triés par nom puis prénom |
| G13 | Recherche : `diallo`, `AMINATA`, `aminata diallo`, `diallo aminata`, un matricule | Mêmes résultats quelle que soit la casse ou l'ordre des mots ; compteur `x élèves sur y` |
| G14 | Recherche avec accent : saisir `zoe` (si un élève s'appelle `Zoé`), ou `eloi` pour `Éloi` | L'élève est trouvé |
| G15 | Croix dans le champ de recherche | La recherche est effacée, toute la liste revient |
| G16 | Filtre **Classe** : choisir `10e A` | Seuls ses élèves ; les nombres entre parenthèses correspondent aux effectifs |
| G17 | Cliquer sur une ligne | Fiche complète : photo, matricule, classe, sexe, date et **âge**, lieu, parents, contact, adresse |
| G18 | Depuis la fiche : **Modifier**, changer l'adresse → **Enregistrer** | Message vert ; la fiche rouverte montre la nouvelle adresse |
| G19 | Modifier, **Retirer** la photo et vider la date de naissance → Enregistrer | Photo et date disparaissent de la fiche |
| G20 | Modifier : changer la classe (l'élève n'a pas de note) | Il apparaît dans la nouvelle classe |
| G21 | Menu `⋮` d'une ligne → **Supprimer** | Confirmation rouge ; après validation, message vert et l'élève disparaît |
| G22 | Paramètres → Classes : supprimer une classe qui contient des élèves | Message rouge « n élèves y sont inscrits » ; après avoir retiré les élèves, la suppression réussit |
| G23 | Années scolaires → créer `2027-2028` ; la sélectionner ; **Inscriptions → Réinscrire…** | Liste des élèves de `2026-2027` ; la classe de destination est à choisir |
| G24 | **Tout sélectionner**, retirer un élève, **Réinscrire (n)** | Message vert « n élèves réinscrits » ; ils apparaissent dans `2027-2028` **et** toujours dans `2026-2027` |
| G25 | **Réinscrire…** de nouveau dans `2027-2028` quand tous le sont | Message « Aucun élève à réinscrire… » |
| G26 | Sans année scolaire, ou dans une année sans classe : menu Inscriptions | Message explicatif et bouton **Ouvrir les paramètres** |
| G27 | Tableau de bord | La tuile « Élèves inscrits » est exacte ; l'étape « Inscrire les élèves » est cochée ; avant la première inscription, un bouton « Inscrire les élèves » y mène |
| G28 | Redimensionner la fenêtre en dessous de 760 px | Le menu du bas contient 4 entrées (Accueil, Inscriptions, Notes, Paramètres) ; le formulaire reste utilisable (sous environ 570 px de large, ses champs passent sur une seule colonne) |

Le changement de classe refusé quand l'élève a des notes, et la suppression d'un
élève qui a des notes (double confirmation), se vérifient après la section I
(lignes I16 et I17).

## H. Persistance et fonctionnement hors ligne

| # | Action | Résultat attendu |
|---|---|---|
| H1 | **Fermer complètement GESCO**, puis le relancer | Établissement, logo, années, classes, matières, seuils, **élèves et leurs photos** et **notes** sont tous conservés |
| H2 | Couper le Wi-Fi / débrancher le câble réseau, refaire quelques actions (B, C, D, G) | Tout fonctionne, aucune erreur réseau |
| H3 | Redimensionner la fenêtre en dessous de 760 px de large | Le menu passe en bas de l'écran |
| H4 | Ouvrir le dossier indiqué sur le Tableau de bord | Le fichier `gesco.db` existe |

## I. Saisie des notes

À faire avec les classes, matières et élèves des sections précédentes. Prévoir au
moins une classe avec 3 élèves et 2 matières (coefficients différents).

| # | Action | Résultat attendu |
|---|---|---|
| I1 | Menu **Notes** | Choix de la classe, puces Octobre → Juin, Trimestre 1/2/3 et Année ; tableau avec un élève par ligne et une matière par colonne (coefficient sous le nom) |
| I2 | Cliquer sur une case, taper `14,5`, **Entrée** | La note s'affiche `14,50` ; la case de l'élève suivant s'ouvre ; « Enregistré automatiquement » apparaît en haut |
| I3 | Saisir une note pour chaque matière d'un même élève | Sa **moyenne** apparaît tout de suite, en vert / orange / rouge ; elle est pondérée par les coefficients (ex. 12,5 × coef 4 et 9 × coef 3 → 11,00) |
| I4 | Saisir des notes pour plusieurs élèves | Les **rangs** (1er, 2e…) se mettent à jour ; deux moyennes égales donnent « ex æquo » ; la ligne grisée du bas donne la moyenne de la classe par matière |
| I5 | Taper `A` dans une case | Elle affiche `ABS`, en gris ; la moyenne de l'élève ne baisse pas ; une étoile orange `*` apparaît à côté de sa moyenne |
| I6 | Taper `D` dans une case | Elle affiche `DISP` |
| I7 | Taper `0` | La case affiche `0,00` et **compte** dans la moyenne |
| I8 | Vider une case déjà remplie, puis Entrée | La case redevient vide (pas de 0) et la moyenne est recalculée |
| I9 | Taper `25`, puis Entrée | Case encadrée en rouge, message « dépasse 20 », rien n'est enregistré ; corriger en `15` puis Entrée enregistre |
| I10 | Taper `abc`, puis Entrée | Message « n'est pas une note valide… » |
| I11 | Taper `14` et attendre une seconde **sans rien valider** | « Enregistré automatiquement » apparaît quand même |
| I12 | Taper une note puis cliquer directement sur une autre case | La première note est enregistrée, la seconde case s'ouvre |
| I13 | **Tab**, **Maj+Tab**, flèches haut / bas, **Échap** | Déplacements décrits dans `REGLES_NOTES.md` ; Échap abandonne la frappe non enregistrée |
| I14 | Changer de mois (Novembre) puis revenir à Octobre | Les notes d'octobre sont intactes ; novembre est vide ; l'avancement « x / y cases » est juste |
| I15 | **Fermer complètement GESCO**, relancer, rouvrir Notes | Toutes les notes sont là, y compris la dernière tapée juste avant la fermeture |
| I16 | Inscriptions → modifier un élève qui a des notes : changer sa classe | Refusé avec un message clair ; la classe reste inchangée |
| I17 | Inscriptions → supprimer un élève qui a des notes | Double confirmation ; après validation, il disparaît avec ses notes |
| I18 | Puces **Trimestre 1** puis **Année** | Moyennes calculées, rang, mention, décision ; aucune case modifiable ; trimestre 1 = moyenne des mois d'octobre à décembre saisis |
| I19 | Paramètres → modifier le coefficient d'une matière, revenir à Notes | Les notes sont inchangées ; les moyennes sont recalculées avec le nouveau coefficient |
| I20 | Classe sans matière / sans élève : menu Notes | Message explicatif et bouton vers Paramètres / Inscriptions |
| I21 | Tableau de bord | Tuile « Notes saisies » exacte ; étape « Saisir les notes » cochée ; bouton « Saisir les notes » dans le bandeau |
| I22 | Fenêtre étroite (moins de 760 px) | Le tableau défile horizontalement (glisser avec la souris ou le doigt, ou Maj + molette) ; la colonne des noms reste visible |

## Si quelque chose ne va pas

Envoyez-moi : le numéro de la ligne, ce que vous attendiez, ce que vous voyez, et
si possible une capture d'écran. Pour une erreur au démarrage, le texte de
l'écran d'erreur suffit.
