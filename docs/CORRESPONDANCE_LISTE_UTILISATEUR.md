# Correspondance avec la liste de fonctionnalités du 19 novembre 2026

Cette liste (14 rubriques) a été comparée au **code réel du dépôt** (application
Flutter/Dart + SQLite ; il n'existe aucun code Python/PySide6 dans ce dépôt, les
lignes « Interface développée avec Python et PySide6 » ne s'appliquent donc pas).

**Dernier état vérifié** : 20 novembre 2026, intégration continue verte, plus de
840 tests automatiques, installateur Windows compilé par la CI.

Légende :
- ✅ implémenté **et** couvert par des tests automatiques passés en CI ;
- 🟡 implémenté mais **partiellement testé** (la colonne « Remarque » dit ce qui
  manque : en général un test d'écran, la base de données étant déjà testée) ;
- ⬜ pas encore fait (étape prévue indiquée).

Rien n'est marqué ✅ sans test automatique. **Aucun écran n'a encore été vérifié à
l'œil sur un vrai Windows** : les tests d'écran contrôlent le contenu et les
actions, pas l'esthétique (voir `VERIFICATION_MANUELLE.md`).

Étapes du plan : 8 = enseignants/établissement/années/classes/matières/inscriptions ·
9 = notation configurable, évaluations, saisie · 10 = moteur complet, résultats,
classements, tableau de bord · 11 = appréciations, décisions, bulletins PDF,
documents · 12 = Excel · 13 = sauvegarde · 14 = interface (sombre, recherche,
raccourcis, journal d'erreurs) · 15 = vérification finale, documentation,
installateur.

## 1. Tableau de bord
| Point | État | Remarque |
|---|---|---|
| Totaux élèves, classes, matières, notes, filles, garçons, année consultée | ✅ | « Élèves inscrits » compte aussi les élèves partis |
| Effectif et nombre de matières par classe | ✅ | |
| Moyennes générales par classe, moyennes de chaque période (trois trimestres en mode trimestres), moyenne annuelle, taux de réussite par classe | ✅ | |
| Moyenne générale et taux de réussite de l'établissement | ✅ | élèves évalués et actifs seulement |
| Graphique de progression des moyennes (une courbe par classe, mois par mois) | 🟡 | séries de données, légende et présence du graphique testées ; le dessin lui-même doit être regardé sur un vrai écran |
| Classement des cinq meilleurs élèves (ex æquo compris, élèves partis exclus) | ✅ | |
| Raccourcis : saisir les notes, inscrire un élève, paramètres, résultats | ✅ | |

## 2. Établissement
| Point | État | Remarque |
|---|---|---|
| Établissement : nom, adresse, contacts, logo, directeur, devise, informations, signature, cachet | 🟡 | base de données testée (enregistrement, relecture, limites de taille) ; l'écran n'a pas de test d'écran |
| Années : création, activation, renommer, archiver / rouvrir, effectifs, comparaison des années | 🟡 | base de données testée ; écran sans test d'écran |
| Consultation d'une ancienne année | 🟡 | les pages suivent l'année choisie ; pas de test d'écran dédié |
| Classes : création, modification, suppression contrôlée, capacité, professeur principal | 🟡 | base de données testée ; écran sans test d'écran |
| Niveaux (liste réutilisable) | ⬜ | le niveau est un champ libre (étape 8, reste à faire) |
| Matières : affectation aux classes, coefficients, note maximale, facultative, enseignant | 🟡 | base de données testée ; écran sans test d'écran |
| Enseignants : création, désactivation, recherche, affectations | ✅ | |

## 3. Élèves
| Point | État | Remarque |
|---|---|---|
| Inscription, informations, matricule proposé, validations (dates, champs obligatoires) | ✅ | fenêtre d'élève testée |
| Photo de l'élève | 🟡 | stockage et limites testés en base ; sélection de l'image non testée à l'écran |
| Inscription par année, ré-inscription en lot | ✅ | |
| Changement de classe et transfert avec reprise des notes | 🟡 | base de données et fenêtre de transfert testées ; l'enchaînement dans la page Inscriptions n'a pas de test d'écran |
| Départ, abandon, reprise, archivage | 🟡 | idem ; les élèves partis sont exclus des classements (testé) |
| Historique des mouvements d'inscription | 🟡 | base de données testée ; écran non testé |

## 4. Notes
| Point | État | Remarque |
|---|---|---|
| Saisie, modification, notes par matière et par mois, notes manquantes, absents (ABS), dispensés | ✅ | |
| Option « compter une absence comme zéro » | ✅ | désactivée par défaut |
| Option « exiger tous les mois d'une période pour calculer sa moyenne » | ✅ | désactivée par défaut |
| Barème par matière (10, 20, 40, 100…), barème par défaut, conversion sur 20 | ✅ | |
| Convertisseur de barème (écran Paramètres) | ✅ | |
| Évaluations (création, modification, validation, suppression confirmée, statistiques) | ✅ | |
| Saisie individuelle dans la grille, saisie collective d'une évaluation | ✅ | |
| Verrouillage d'un mois par classe | ✅ | |
| Historique des modifications de notes | 🟡 | affichage et total testés ; filtres et pagination non testés à l'écran |

## 5. Calculs et résultats
| Point | État | Remarque |
|---|---|---|
| Moyennes pondérées (matière, mois, période, année), mentions, décisions, ex æquo, élèves sans moyenne | ✅ | |
| Périodes configurables : trimestres, semestres, personnalisé, séquences, moyennes mensuelles masquables | ✅ | moteur, base et écran testés |
| Résultats incomplets signalés | 🟡 | calcul testé ; l'étiquette « Incomplet » de la page Résultats n'est pas testée à l'écran |
| Statistiques de réussite / d'échec par classe et pour l'établissement | ✅ | |
| Élèves partis / abandons exclus du classement et des statistiques | ✅ | |
| Mentions et décisions modifiables | 🟡 | calcul testé ; l'éditeur des paliers n'a pas de test d'écran |

## 6. Classements
| Point | État | Remarque |
|---|---|---|
| Page « Résultats » : classement d'une classe pour un mois, une période, une séquence ou l'année, avec ex æquo (1, 1, 3), mention et décision | ✅ | |
| Classement dans une matière | ✅ | |
| Élèves non classés (sans note, partis) listés à part | ✅ | |
| Comparaison et rang des classes | ✅ | à interpréter avec prudence entre niveaux différents |
| Export des classements en PDF | ⬜ | étape 11 |

## 7. Bulletins
Tout ⬜ — étape 11 : bulletins mensuel / trimestriel / annuel en PDF, aperçu, format
A4, matières nombreuses, notes, coefficients, moyennes, rang, mention, décision,
appréciations par matière et générale, décision du conseil, 8 styles (classique
bleu, couleurs guinéennes, élégant rose, moderne anthracite, minimaliste noir et
blanc, bleu et or, vert sauge, violet).

## 8. Résultats annuels
| Point | État | Remarque |
|---|---|---|
| Moyenne annuelle, rang annuel, décision annuelle (grille et page Résultats, portée « Année entière ») | ✅ | |
| Export PDF des résultats annuels | ⬜ | étape 11 |

## 9. Import / export Excel
Tout ⬜ — étape 12 : modèles préformatés, import des élèves et des notes avec numéro de
ligne pour chaque erreur, refus d'écraser un matricule existant, cellules vides = note
manquante (jamais zéro), barème configurable, export des données.

## 10. Sauvegarde et restauration
Contrôle d'intégrité au démarrage ✅. Sauvegarde, restauration, vérification SHA-256 de
l'archive : ⬜ — étape 13.

## 11. Utilisateurs
| Point | État | Remarque |
|---|---|---|
| Comptes locaux, rôles (Administrateur, Direction, Saisie, Consultation), permissions par utilisateur, PBKDF2-SHA256, limitation des tentatives, verrouillage par inactivité, code de récupération, journaux | ✅ | écrans de gestion des comptes sans test d'écran (🟡 pour ces écrans) ; la page Résultats refuse l'accès sans permission (testé) |

## 12. Paramètres et personnalisation
| Point | État | Remarque |
|---|---|---|
| Règles de calcul, périodes, barème par défaut | ✅ | |
| Seuils, mentions, décisions | 🟡 | voir rubrique 5 |
| Logo, photos | 🟡 | voir rubriques 2 et 3 |
| Thème clair / sombre | ⬜ | étape 14 |
| Paramètres de sauvegarde | ⬜ | étape 13 |

## 13. Interface et fonctionnement
| Point | État | Remarque |
|---|---|---|
| Application de bureau Windows (Flutter), navigation, messages d'erreur lisibles, SQLite local, fonctionnement hors ligne | ✅ | compilation de l'installateur par la CI ; non essayé à la main sur Windows |
| Journalisation des erreurs dans un fichier | ⬜ | étape 14 |
| Protection contre les arrêts inattendus (capture globale des erreurs, écriture atomique) | ⬜ | étape 14 |
| Recherche globale, tri, pagination, raccourcis clavier, mode sombre | ⬜ | étape 14 (des recherches et paginations locales existent déjà dans certaines listes) |

## 14. Documents et impression
Bulletins, classements, résultats annuels en PDF, ouverture dans le lecteur PDF de
Windows pour imprimer, polices embarquées, exemples de documents dans le dépôt :
⬜ — étape 11. L'impression directe depuis l'application n'est pas garantie ; le PDF
s'ouvrira dans le lecteur par défaut.

## Reste à faire avant la livraison finale
1. Étape 11 : appréciations, décisions du conseil, bulletins et classements en PDF.
2. Étape 12 : import / export Excel.
3. Étape 13 : sauvegarde et restauration.
4. Étape 14 : thème sombre, recherche globale, raccourcis, journal d'erreurs.
5. Étape 15 : tests d'écran manquants (Établissement, Années, Classes et matières,
   page Inscriptions, éditeur de mentions, écrans de gestion des comptes), liste de
   niveaux, mise à jour du README, du cahier des charges et de l'installateur,
   vérification à la main sur Windows.
