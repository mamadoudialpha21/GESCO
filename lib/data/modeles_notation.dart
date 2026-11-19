/// Modèles de la notation : évaluations, statistiques d'une évaluation et
/// historique des modifications de notes.
library;

import '../domain/arrondi.dart';
import '../domain/bareme.dart';
import '../domain/periodes.dart';

/// Nature d'une évaluation.
enum TypeEvaluation {
  evaluation('evaluation', 'Évaluation'),
  interrogation('interrogation', 'Interrogation'),
  devoir('devoir', 'Devoir'),
  composition('composition', 'Composition'),
  examen('examen', 'Examen');

  const TypeEvaluation(this.cle, this.libelle);

  /// Valeur enregistrée dans la base.
  final String cle;
  final String libelle;

  static TypeEvaluation depuisCle(String cle) => values.firstWhere(
        (t) => t.cle == cle,
        orElse: () => TypeEvaluation.evaluation,
      );
}

/// Évaluation d'une matière dans un mois : interrogation, devoir, composition...
class Evaluation {
  const Evaluation({
    required this.id,
    required this.classeId,
    required this.matiereId,
    required this.mois,
    required this.type,
    required this.titre,
    this.date,
    this.coefficient = 100,
    this.bareme = 20,
    this.valide = false,
  });

  final int id;
  final int classeId;
  final int matiereId;

  /// Mois civil (10, 11, 12, 1 à 6).
  final int mois;
  final TypeEvaluation type;
  final String titre;

  /// Date de l'évaluation au format `2026-11-17`, ou null.
  final String? date;

  /// Poids dans la note du mois (centièmes : 2 -> 200).
  final int coefficient;

  /// Note maximale (10, 20, 40, 100...).
  final int bareme;

  /// Évaluation validée : plus aucune note ne peut être modifiée.
  final bool valide;

  String get libelleBareme => 'sur $bareme';
}

/// Évaluation avec ce qu'il faut pour l'afficher dans une liste.
class EvaluationResume {
  const EvaluationResume({
    required this.evaluation,
    required this.matiereNom,
    required this.nbEleves,
    required this.nbNotes,
  });

  final Evaluation evaluation;
  final String matiereNom;

  /// Élèves qui suivent encore la classe (ni départ ni abandon).
  final int nbEleves;

  /// Notes enregistrées (y compris absences et dispenses) de ces élèves.
  final int nbNotes;

  bool get complete => nbEleves > 0 && nbNotes >= nbEleves;
}

/// Statistiques d'une évaluation, sur les élèves qui suivent la classe.
class StatsEvaluation {
  const StatsEvaluation({
    required this.bareme,
    required this.nbEleves,
    required this.nbSaisies,
    required this.nbAbsents,
    required this.nbDispenses,
    required this.nbReussites,
    this.moyenne,
    this.moyenneSur20,
    this.minimum,
    this.maximum,
  });

  final int bareme;
  final int nbEleves;

  /// Élèves ayant une note chiffrée.
  final int nbSaisies;
  final int nbAbsents;
  final int nbDispenses;

  /// Élèves dont la note, ramenée sur 20, atteint le seuil d'admission.
  final int nbReussites;

  /// Moyenne de la classe sur le barème (centièmes), null sans note.
  final int? moyenne;

  /// La même moyenne ramenée sur 20 (centièmes).
  final int? moyenneSur20;
  final int? minimum;
  final int? maximum;

  int get nbNonSaisis {
    final reste = nbEleves - nbSaisies - nbAbsents - nbDispenses;
    return reste < 0 ? 0 : reste;
  }

  /// Part des élèves notés qui réussissent (0 à 100), null sans note.
  double? get tauxReussite =>
      nbSaisies == 0 ? null : nbReussites * 100 / nbSaisies;
}

/// Une ligne de l'historique des notes (création, modification, suppression).
class EntreeHistoriqueNote {
  const EntreeHistoriqueNote({
    required this.id,
    required this.dateHeure,
    required this.utilisateurNom,
    required this.source,
    required this.operation,
    required this.inscriptionId,
    this.matiereId,
    this.mois,
    this.evaluationId,
    this.bareme,
    this.eleveNom = '',
    this.matiereNom = '',
    this.classeNom = '',
    this.ancienEtat,
    this.ancienneValeur,
    this.nouvelEtat,
    this.nouvelleValeur,
  });

  final int id;

  /// `2026-11-17T08:05:09` (heure locale).
  final String dateHeure;
  final String utilisateurNom;

  /// 'mensuelle' ou 'evaluation'.
  final String source;

  /// 'creation', 'modification' ou 'suppression'.
  final String operation;
  final int inscriptionId;
  final int? matiereId;
  final int? mois;
  final int? evaluationId;

  /// Barème de l'évaluation (null pour une note mensuelle : toujours sur 20).
  final int? bareme;
  final String eleveNom;
  final String matiereNom;
  final String classeNom;
  final String? ancienEtat;
  final int? ancienneValeur;
  final String? nouvelEtat;
  final int? nouvelleValeur;

  String get libelleOperation => switch (operation) {
        'creation' => 'Saisie',
        'modification' => 'Modification',
        'suppression' => 'Suppression',
        _ => operation,
      };

  String get libelleSource => source == 'evaluation' ? 'Évaluation' : 'Note du mois';

  String get nomMois => mois == null ? '' : libelleMois(mois!);

  /// Ancienne note, lisible : « 14,50 / 20 », « Absent », « — ».
  String get ancienTexte => _texte(ancienEtat, ancienneValeur);

  /// Nouvelle note, lisible.
  String get nouveauTexte => _texte(nouvelEtat, nouvelleValeur);

  String _texte(String? etat, int? valeur) {
    switch (etat) {
      case 'saisie':
        return '${formaterCentiemes(valeur)} / ${bareme ?? baremeParDefaut}';
      case 'absent':
        return 'Absent';
      case 'dispense':
        return 'Dispensé';
      default:
        return '—';
    }
  }
}

/// Verrouillage d'un mois pour une classe.
class VerrouMois {
  const VerrouMois({
    required this.mois,
    required this.verrouilleLe,
    this.utilisateurNom = '',
  });

  final int mois;
  final String verrouilleLe;
  final String utilisateurNom;
}
