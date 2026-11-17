# GESCO — état réel des 24 modules du cahier des charges

Dernière mise à jour : 17 novembre 2026 (audit initial, version 0.4.0).

Légende : ✅ existe et couvert par des tests automatiques · 🟡 partiel · ⬜ à faire.
Ce tableau est mis à jour à chaque étape : une ligne ne passe à ✅ que lorsque la
fonction est écrite **et** testée.

Un récapitulatif chiffré sera ajouté à la fin, une fois toutes les étapes faites.

## 1. Tableau de bord général

| Fonction | Statut | Remarque |
|---|---|---|
| Vue d'ensemble de l'établissement | 🟡 | bandeau, tuiles, liste de démarrage |
| Nombre total d'élèves | 🟡 | seuls les inscrits de l'année affichée sont comptés |
| Nombre de classes | ✅ | |
| Nombre d'enseignants | ⬜ | module 15 |
| Nombre de matières | ✅ | |
| Nombre d'utilisateurs | ⬜ | module 16 |
| Nombre d'élèves inscrits | ✅ | avec garçons / filles |
| Moyenne générale de l'établissement | ⬜ | |
| Taux de réussite / d'échec | ⬜ | calculés seulement par classe, dans la grille |
| Meilleurs élèves / élèves en difficulté | ⬜ | |
| Dernières opérations effectuées | ⬜ | demande le journal (module 22) |
| Graphiques statistiques | ⬜ | |
| Répartition des élèves par classe | ✅ | barres |
| Évolution des résultats scolaires | ⬜ | |
| Alertes et notifications internes | 🟡 | seule l'alerte d'intégrité de la base existe |

## 2. Gestion de l'établissement

| Fonction | Statut | Remarque |
|---|---|---|
| Nom, logo, adresse, téléphone, e-mail | ✅ | |
| Nom du directeur | ⬜ | |
| Informations administratives | ⬜ | |
| Devise ou slogan | ⬜ | |
| Année scolaire en cours | ✅ | |
| Personnalisation des documents | ⬜ | |
| Signatures et cachets | ⬜ | |
| Paramètres généraux du logiciel | 🟡 | seuils de résultats seulement |

## 3. Gestion des années scolaires

| Fonction | Statut | Remarque |
|---|---|---|
| Création, définition de l'année active | ✅ | avec copie des classes et matières |
| Modification d'une année | ⬜ | le libellé ne peut pas être changé |
| Archivage des anciennes années | ⬜ | |
| Consultation des années précédentes | ✅ | sélecteur d'année |
| Passage d'une année à l'autre, historique des élèves | ✅ | réinscription, historique par inscription |
| Comparaison des résultats entre années | ⬜ | |

## 4. Gestion des classes

| Fonction | Statut | Remarque |
|---|---|---|
| Création, modification, suppression contrôlée | ✅ | |
| Nom et niveau, affectation des élèves et des matières, coefficients | ✅ | |
| Capacité | ⬜ | |
| Barèmes | ⬜ | module 8 |
| Professeur principal | ⬜ | module 15 |
| Liste des élèves | ✅ | |
| Statistiques, moyenne, classement de la classe | 🟡 | dans la grille de notes, pas de page dédiée |
| Effectif filles / garçons par classe | 🟡 | global seulement |

## 5. Gestion des élèves

| Fonction | Statut | Remarque |
|---|---|---|
| Ajouter, modifier, consulter, supprimer | ✅ | |
| Archiver un dossier, selon les permissions | ⬜ | |
| Matricule unique, photo, identité, naissance, sexe, adresse | ✅ | |
| Téléphone, parent ou tuteur | 🟡 | père, mère et contact ; pas de tuteur ni de téléphone de l'élève |
| Classe actuelle | ✅ | |
| Historique des inscriptions | ⬜ | non affiché dans la fiche |
| Historique des notes, moyennes par trimestre, moyenne annuelle, classement, décision | ⬜ | pas dans la fiche |
| Impression de la fiche individuelle | ⬜ | |
| Recherche (nom, prénom, matricule), filtrage classe et année | ✅ | |

## 6. Inscriptions et réinscriptions

| Fonction | Statut | Remarque |
|---|---|---|
| Inscrire, réinscrire, affecter à une classe et à une année, date | ✅ | |
| Transférer dans une autre classe | 🟡 | refusé si l'élève a déjà des notes |
| Enregistrer les changements de classe | ⬜ | |
| Départs et abandons | ⬜ | |
| Conserver l'historique | ⬜ | |
| Effectifs par année | ⬜ | |
| Imprimer les listes d'inscrits | ⬜ | |

## 7. Gestion des matières

| Fonction | Statut | Remarque |
|---|---|---|
| Ajouter, modifier, supprimer, coefficient | ✅ | |
| Affecter à une classe et à une année | ✅ | |
| Note maximale, barème | ⬜ | module 8 |
| Affecter un enseignant | ⬜ | module 15 |
| Résultats par matière | 🟡 | moyenne de classe en pied de grille |
| Obligatoire / facultative | ⬜ | |

## 8. Système de notation configurable

| Fonction | Statut | Remarque |
|---|---|---|
| Barème par matière, échelles 10 / 20 / 40 / 100 | ⬜ | tout est sur 20 |
| Coefficients personnalisables, notes décimales | ✅ | 2 décimales |
| Évaluations, interrogations, devoirs, compositions, examens | ⬜ | module 9 |
| Notes absentes, non saisies, invalides | ✅ | jamais comptées comme zéro |
| Conversion vers une échelle commune | ⬜ | |
| Validation selon le barème | 🟡 | validée de 0 à 20 |
| Historique des modifications | ⬜ | |
| Protection contre les saisies incorrectes | ✅ | |

## 9. Gestion des évaluations

Tout est à faire : créer, titre, classe, matière, période, date, coefficient,
note maximale, saisie de la classe, modification, enregistrement, consultation,
suppression, filtres.

## 10. Saisie des notes

| Fonction | Statut | Remarque |
|---|---|---|
| Tableau de saisie rapide, liste des élèves, saisie collective | ✅ | grille par classe et par mois |
| Modification, enregistrement automatique, validation | ✅ | |
| Calcul automatique des moyennes, moyenne de classe | ✅ | |
| Détection des notes manquantes | ✅ | compteur et astérisque |
| Notes les plus élevées / faibles | 🟡 | meilleure et plus faible moyenne ; pas par matière |
| Saisie individuelle | ⬜ | |
| Enregistrement manuel | ⬜ | |
| Historique des saisies | ⬜ | |
| Verrouillage après validation | ⬜ | |

## 11. Calcul automatique des moyennes

| Fonction | Statut | Remarque |
|---|---|---|
| Moyenne mensuelle, trimestrielle, annuelle | ✅ | |
| Moyenne d'une matière | 🟡 | par mois et par trimestre |
| Moyenne générale élève et classe, pondération par coefficient | ✅ | |
| Moyenne d'une évaluation | ⬜ | |
| Moyenne séquentielle, semestrielle | ⬜ | |
| Pondération par poids des évaluations | ⬜ | |
| Périodes configurables | ⬜ | trimestres fixes (octobre à juin) |

## 12. Classements scolaires

| Fonction | Statut | Remarque |
|---|---|---|
| Classement général, trimestriel, annuel | ✅ | dans la grille |
| Gestion des ex æquo | ✅ | 1, 1, 3 |
| Meilleure, plus faible moyenne, moyenne de classe | ✅ | |
| Premier / dernier de classe, nombre de classés | 🟡 | chiffres sans les noms |
| Classement par matière | ⬜ | |
| Comparaison entre périodes | ⬜ | |
| Page « Classements » dédiée | ⬜ | |

## 13. Bulletins scolaires

Tout est à faire (aucun document PDF n'existe encore).

## 14. Appréciations et décisions scolaires

| Fonction | Statut | Remarque |
|---|---|---|
| Mentions automatiques, personnalisation des mentions | ✅ | |
| Décisions automatiques (passage, redoublement), seuils de réussite | ✅ | |
| Appréciation par matière, appréciation générale, personnalisation | ⬜ | |
| Décision du conseil de classe saisie à la main, exclusion | ⬜ | |

## 15. Gestion des enseignants — ⬜ tout est à faire
## 16. Utilisateurs et permissions — ⬜ tout est à faire (pas de connexion actuellement)
## 17. Statistiques et rapports — 🟡 statistiques de classe dans la grille ; le reste est à faire
## 18. Importation et exportation Excel — ⬜ tout est à faire
## 19. Documents et impressions — ⬜ tout est à faire

## 20. Sauvegarde et restauration

Seul le contrôle d'intégrité de la base existe (au démarrage) 🟡. Sauvegarde
manuelle et automatique, choix du dossier, clé USB, historique, restauration
protégée : ⬜.

## 21. Sécurité et confidentialité

| Fonction | Statut | Remarque |
|---|---|---|
| Stockage local, aucun serveur, aucune connexion Internet | ✅ | |
| Validation des entrées | ✅ | |
| Protection contre les suppressions accidentelles | ✅ | confirmations et clés étrangères RESTRICT |
| Mots de passe hachés, permissions, journaux, sessions, verrouillage | ⬜ | modules 16 et 22 |

## 22. Historique et traçabilité

Date de dernière modification d'une note 🟡. Historique des notes, des
modifications, des inscriptions, des changements de classe, des utilisateurs,
identité de l'auteur, anciennes valeurs, journal administratif : ⬜.

## 23. Paramètres avancés

Mentions, décisions, seuils ✅. Système de notation, périodes, coefficients
globaux, bulletins, documents, sauvegardes, interface : ⬜.

## 24. Interface et expérience utilisateur

| Fonction | Statut | Remarque |
|---|---|---|
| Interface professionnelle en français, menu latéral, tableau de bord moderne | ✅ | |
| Fenêtres de confirmation, messages d'erreur compréhensibles | ✅ | |
| Interface cohérente | ✅ | |
| Navigation rapide, filtres, tableaux interactifs | 🟡 | |
| Adaptation aux résolutions | 🟡 | menu du bas sous 760 px |
| Raccourcis clavier | 🟡 | seulement dans la grille de notes |
| Recherche globale | ⬜ | |
| Tri des colonnes, pagination | ⬜ | |
| Mode clair et mode sombre | ⬜ | clair seulement |
