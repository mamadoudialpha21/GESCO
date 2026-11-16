# Règles de calcul de GESCO

Ces règles pilotent **tous** les résultats (moyennes, rangs, mentions,
bulletins). Elles sont implémentées dans `lib/domain/` et vérifiées par les
tests de `test/domain/`. **Relisez-les : si une règle ne correspond pas à la
pratique de votre établissement, dites-le avant que l'interface ne soit bâtie
dessus.**

Les règles marquées ⚠ sont des choix par défaut proposés, à valider.

## Représentation des nombres

1. Notes, coefficients et moyennes sont stockés en **centièmes entiers**
   (14,75 → 1475 ; coefficient 2,5 → 250). Aucun nombre à virgule flottante :
   pas d'erreur d'arrondi cachée.
2. Une note est comprise entre 0,00 et 20,00. Un coefficient est > 0.
3. Les notes brutes ne sont jamais modifiées par un changement de
   coefficient : les moyennes sont recalculées à chaque fois.

## Cellules de notes (élève × matière × mois)

4. Quatre états : **note saisie**, **absent**, **dispensé**, **non saisie**.
5. Seule une note saisie compte dans les calculs. Absent, dispensé et non
   saisie sont **exclus** (au numérateur *et* au total des coefficients) :
   une note manquante n'est **jamais** un zéro. ⚠
6. Un vrai zéro saisi (0,00) est compté normalement.
7. Un mois est dit **incomplet** s'il manque une matière (non saisie ou
   absent). « Dispensé » n'est pas un manque.

## Moyennes

8. **Moyenne d'un mois** = Σ(note × coefficient) ÷ Σ(coefficients), sur les
   matières ayant une note saisie.
9. **Moyenne d'un trimestre** = moyenne des moyennes mensuelles disponibles
   (T1 = octobre, novembre, décembre ; T2 = janvier, février, mars ;
   T3 = avril, mai, juin).
10. **Moyenne annuelle** = moyenne des moyennes trimestrielles disponibles.
11. **Arrondi** : chaque moyenne affichée est arrondie à 2 décimales, demi vers
    le haut (10,005 → 10,01). Les moyennes de niveau supérieur sont calculées
    **à partir des moyennes affichées** du niveau inférieur, pour que vous
    puissiez refaire le calcul à la main sur les documents. ⚠
    Exemple : 12,89 ; 13,89 ; 13,56 → T1 = 13,45 (sans arrondi intermédiaire,
    on obtiendrait 13,44).
12. Si un mois ou un trimestre n'a aucune note, il est ignoré dans la moyenne
    supérieure et le résultat est marqué **incomplet** (jamais traité comme 0). ⚠
13. Note d'une matière au trimestre (bulletin) = moyenne de ses notes
    mensuelles saisies. Quand toutes les notes sont saisies, la moyenne
    générale du bulletin est exactement Σ(note × coef) ÷ Σ(coef). Si
    des matières manquent sur des mois différents, le bulletin est marqué
    incomplet car les deux façons de calculer peuvent différer de quelques
    centièmes. ⚠

## Rangs

14. Classement par moyenne décroissante (sur la moyenne arrondie).
15. **Ex æquo** : même rang, le suivant saute (1, 1, 3, 4).
16. Un élève sans moyenne n'a pas de rang. Un élève dont le résultat est
    incomplet est classé, avec l'indicateur « incomplet ». ⚠

## Mentions, décisions, admission (valeurs par défaut modifiables)

17. Admis si moyenne ≥ **10,00** (seuil d'admission).
18. Mentions : Passable ≥ 10 ; Assez bien ≥ 12 ; Bien ≥ 14 ; Très bien ≥ 16 ;
    Excellent ≥ 18 ; en dessous de 10 : aucune mention. ⚠
19. Décision d'un mois ou trimestre : « Admis(e) » ≥ 10, sinon
    « Non admis(e) ». Décision annuelle : « Admis(e) en classe supérieure »
    ≥ 10, sinon « Redouble ». ⚠
20. Couleurs : rouge < 10 ; orange de 10 à 11,99 ; vert ≥ 12 (seuil « bon »
    modifiable).
21. Tous ces seuils et libellés sont enregistrés **par année scolaire** dans
    la base (table `config_resultats`) : les modifier ne change pas les
    résultats des années passées.

## Statistiques de classe

22. Effectif = tous les inscrits. Filles / garçons = selon le sexe enregistré.
23. « Évalués » = élèves ayant une moyenne pour la période. Admis, non admis,
    moyenne de la classe, meilleure et plus faible moyenne, taux de réussite
    et répartition par mention sont calculés sur les **évalués**.
24. Taux de réussite = admis ÷ évalués, en pourcentage à 2 décimales.
