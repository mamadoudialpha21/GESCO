/// Note d'un mois calculée à partir des évaluations de la matière.
///
/// Dart pur : aucun accès à la base de données.
library;

import 'arrondi.dart';
import 'modeles.dart';

/// Note d'une évaluation (déjà ramenée sur 20) avec son coefficient
/// (centièmes : 2 -> 200).
class NoteEvaluee {
  const NoteEvaluee(this.saisie, this.coefficient) : assert(coefficient > 0);

  final Saisie saisie;
  final int coefficient;
}

/// Note du mois d'un élève dans une matière, d'après ses évaluations :
/// moyenne des notes sur 20 pondérée par les coefficients des évaluations,
/// arrondie au centième, demi vers le haut.
///
/// - un absent ou un dispensé n'est pas compté comme zéro : l'évaluation est
///   simplement ignorée, sauf si [absenceEgaleZero] est vrai (un absent compte
///   alors pour 0) ;
/// - sans aucune note chiffrée : absent s'il a été absent à au moins une
///   évaluation, sinon dispensé s'il l'a été, sinon null (« non saisie »).
Saisie? noteDuMois(
  Iterable<NoteEvaluee> notes, {
  bool absenceEgaleZero = false,
}) {
  var somme = 0;
  var poids = 0;
  var absent = false;
  var dispense = false;
  for (final n in notes) {
    switch (n.saisie.etat) {
      case EtatNote.saisie:
        somme += n.saisie.centiemes! * n.coefficient;
        poids += n.coefficient;
      case EtatNote.absent:
        absent = true;
        if (absenceEgaleZero) poids += n.coefficient;
      case EtatNote.dispense:
        dispense = true;
    }
  }
  if (poids > 0) return Saisie.valeur(divisionArrondie(somme, poids));
  if (absent) return const Saisie.absent();
  if (dispense) return const Saisie.dispense();
  return null;
}
