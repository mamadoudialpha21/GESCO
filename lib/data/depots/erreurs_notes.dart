import '../erreurs.dart';

/// Message lisible pour une erreur levée par un déclencheur de la base de
/// données (verrouillage, cohérence), ou null si l'erreur est autre.
///
/// Les déclencheurs sont le dernier garde-fou : même si un écran oublie une
/// vérification, une note ne peut pas être modifiée dans une année archivée,
/// un mois verrouillé ou une évaluation validée.
ErreurGesco? erreurDeDeclencheur(Object erreur) {
  final texte = erreur.toString();
  if (texte.contains('Annee archivee')) {
    return const ErreurGesco(
      'Cette année scolaire est archivée : les notes ne peuvent plus être '
      'modifiées. Rouvrez l\'année dans les paramètres pour continuer.',
    );
  }
  if (texte.contains('Mois verrouille')) {
    return const ErreurGesco(
      'Ce mois est verrouillé pour cette classe : déverrouillez-le pour '
      'modifier les notes.',
    );
  }
  if (texte.contains('Evaluation validee')) {
    return const ErreurGesco(
      'Cette évaluation est validée : annulez sa validation pour la modifier.',
    );
  }
  if (texte.contains('Evaluation avec notes')) {
    return const ErreurGesco(
      'Cette évaluation a déjà des notes : la matière, le mois et le barème '
      'ne peuvent plus changer.',
    );
  }
  if (texte.contains('Note hors bareme')) {
    return const ErreurGesco('La note dépasse le barème de l\'évaluation.');
  }
  if (texte.contains('Eleve hors classe')) {
    return const ErreurGesco(
      'Cet élève n\'est pas inscrit dans la classe de cette évaluation.',
    );
  }
  if (texte.contains('Matiere hors classe')) {
    return const ErreurGesco('Cette matière n\'appartient pas à la classe.');
  }
  return null;
}
