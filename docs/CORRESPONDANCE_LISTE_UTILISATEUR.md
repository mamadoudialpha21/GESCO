# Correspondance avec la liste de fonctionnalités du 19 novembre 2026

Cette liste (14 rubriques) a été comparée au **code réel du dépôt** (application
Flutter/Dart + SQLite ; il n'existe aucun code Python/PySide6 dans ce dépôt, les
lignes « Interface développée avec Python et PySide6 » ne s'appliquent donc pas).
La branche `feature/evaluations-guinee-v1` est identique à `main`.

Légende : ✅ implémenté **et** couvert par des tests automatiques passés en CI ·
🟡 partiel ou écrit mais pas encore validé en CI · ⬜ à faire (étape prévue indiquée).
Rien n'est marqué ✅ sans test automatique ; l'aspect visuel des écrans reste à
vérifier manuellement sur Windows (voir `VERIFICATION_MANUELLE.md`).

Étapes du plan : 8 = enseignants/établissement/années/classes/matières/inscriptions ·
9 = notation configurable, évaluations, saisie · 10 = moteur complet, classements,
statistiques, tableau de bord · 11 = appréciations, décisions, bulletins PDF,
documents · 12 = Excel · 13 = sauvegarde · 14 = interface (sombre, recherche,
raccourcis) · 15 = vérification finale, documentation, installateur.

## 1. Tableau de bord
| Point | État | Étape |
|---|---|---|
| Totaux élèves, classes, matières, filles, garçons, année consultée | ✅ | — |
| Effectif par classe | ✅ | — |
| Moyennes générales par classe, taux de réussite par classe | ⬜ (seulement dans la grille de notes) | 10 |
| Moyennes des trois trimestres, moyennes annuelles | ⬜ | 10 |
| Graphique de progression des moyennes | ⬜ | 10 |
| Classement des cinq meilleurs élèves | ⬜ | 10 |
| Raccourcis vers les pages | 🟡 | 10 |

## 2. Établissement
| Point | État | Étape |
|---|---|---|
| Enregistrement de l'établissement (nom, logo, adresse, contacts) | ✅ | — |
| Directeur, devise, informations administratives, signature, cachet | 🟡 données testées en CI ; écran écrit, en attente de CI | 8 |
| Années : création, activation, consultation | ✅ | — |
| Années : renommer, archiver / rouvrir, effectifs, comparaison des effectifs | 🟡 données testées ; écran en attente de CI | 8 |
| Classes : création, modification, suppression contrôlée | ✅ | — |
| Classes : capacité, professeur principal, effectifs filles/garçons | 🟡 données testées ; écran en attente de CI | 8 |
| Gestion des niveaux (liste de niveaux réutilisable) | ⬜ (le niveau est aujourd'hui un champ libre) | 8 |
| Matières, affectation aux classes, coefficients | ✅ | — |
| Matières : note maximale, facultative, enseignant | 🟡 données testées ; écran en attente de CI | 8 |

## 3. Élèves
| Point | État | Étape |
|---|---|---|
| Inscription, informations personnelles, matricule, photo, validations | ✅ | — |
| Association à une classe, inscriptions par année, historique par inscription | ✅ | — |
| Changement de classe et transfert **avec reprise des notes** | 🟡 données testées ; écran à faire | 8 |
| Départ, abandon, reprise, archivage, tuteur, téléphone | 🟡 données testées ; écran à faire | 8 |
| Historique des mouvements d'inscription | 🟡 données testées ; écran à faire | 8 |

## 4. Notes
| Point | État | Étape |
|---|---|---|
| Saisie, modification, notes par matière et par mois, notes manquantes, absents | ✅ | — |
| Barème maximal configurable (20 par défaut), conversion, historique des modifications | ⬜ (les tables existent depuis la version 2 de la base) | 9 |
| Évaluations, saisie individuelle, verrouillage | ⬜ | 9 |

## 5. Calculs et résultats
| Point | État | Étape |
|---|---|---|
| Moyennes pondérées mensuelles, trimestrielles, annuelles ; mentions ; décisions configurables ; ex æquo ; sans moyenne | ✅ | — |
| Périodes configurables (trimestres, semestres, séquences) dans le moteur | ✅ (étape 6) | — |
| Moyenne par évaluation / pondération des évaluations | ⬜ | 9–10 |
| Option « compter une absence comme zéro » | ⬜ | 10 |
| Option « exiger les trois mois pour calculer un trimestre » | ⬜ | 10 |
| Statistiques de réussite / d'échec par classe et établissement | 🟡 par classe dans la grille | 10 |
| Exclusion des élèves partis/abandons/archivés des classements | ⬜ (données prêtes) | 10 |

## 6. Classements
| Point | État | Étape |
|---|---|---|
| Rangs avec ex æquo (1, 1, 3), élèves non classés | ✅ (dans la grille) | — |
| Page « Classements » (classe, période, matière, comparaison de périodes) | ⬜ | 10 |
| Export des classements en PDF | ⬜ | 11 |

## 7. Bulletins
| Point | État | Étape |
|---|---|---|
| Bulletins mensuel / trimestriel / annuel en PDF, aperçu, A4, matières nombreuses | ⬜ | 11 |
| Notes, coefficients, moyennes, rang, mention, décision | ⬜ | 11 |
| Appréciations par matière et générale, décision du conseil | ⬜ | 11 |
| Styles : classique bleu, couleurs guinéennes, élégant rose, moderne anthracite, minimaliste noir et blanc, bleu et or, vert sauge, violet (8 styles) | ⬜ | 11 |

## 8. Résultats annuels
| Point | État | Étape |
|---|---|---|
| Moyennes et décisions annuelles dans la grille | ✅ | — |
| Page de résultats annuels, classement annuel, PDF | ⬜ | 10–11 |

## 9. Import / export Excel
Tout ⬜ — étape 12 : modèles préformatés, import des élèves et des notes avec numéro de
ligne pour chaque erreur, refus d'écraser un matricule existant, cellules vides = note
manquante (jamais zéro), barème configurable, export des données.

## 10. Sauvegarde et restauration
Contrôle d'intégrité au démarrage ✅. Sauvegarde, restauration, vérification SHA-256 de
l'archive : ⬜ — étape 13.

## 11. Utilisateurs
| Point | État |
|---|---|
| Comptes locaux, rôles (Administrateur, Direction, Saisie, Consultation), permissions par utilisateur, PBKDF2-SHA256, limitation des tentatives, verrouillage par inactivité, code de récupération, journaux | ✅ (étape 7, 530 tests, installateur compilé) |

## 12. Paramètres et personnalisation
Seuils, mentions, décisions ✅. Période/calendrier configurable (données) ✅ ; écran
de configuration, barème, sauvegardes : étapes 9 et 13. Thème clair/sombre : ⬜ étape 14.
Logo ✅, photos ✅.

## 13. Interface et fonctionnement
| Point | État | Étape |
|---|---|---|
| Application de bureau Windows (Flutter), navigation, notifications, erreurs lisibles, SQLite local, hors ligne | ✅ | — |
| Journalisation des erreurs dans un fichier | ⬜ | 14 |
| Protection contre les arrêts inattendus (capture globale des erreurs, écriture atomique) | ⬜ | 14 |
| Recherche globale, tri, pagination, raccourcis clavier, mode sombre | ⬜ | 14 |

## 14. Documents et impression
Bulletins, classements, résultats annuels en PDF, ouverture dans le lecteur PDF de
Windows pour imprimer, polices embarquées, exemples de documents dans le dépôt :
⬜ — étape 11. L'impression directe depuis l'application n'est pas garantie ; le PDF
s'ouvre dans le lecteur par défaut.
