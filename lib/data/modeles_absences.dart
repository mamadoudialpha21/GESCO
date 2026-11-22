/// Absences et retards des élèves.
library;

/// Nature d'un manquement à la présence.
enum TypeAbsence {
  absence('absence', 'Absence'),
  retard('retard', 'Retard');

  const TypeAbsence(this.code, this.libelle);

  /// Valeur enregistrée dans la base.
  final String code;
  final String libelle;

  static TypeAbsence parCode(String code) =>
      values.firstWhere((t) => t.code == code, orElse: () => TypeAbsence.absence);
}

/// Une absence (journée) ou un retard d'un élève inscrit.
class Absence {
  const Absence({
    this.id = 0,
    required this.inscriptionId,
    required this.date,
    this.type = TypeAbsence.absence,
    this.justifiee = false,
    this.dureeMinutes,
    this.motif = '',
    this.eleveNom = '',
    this.matricule = '',
    this.classeNom = '',
  });

  final int id;
  final int inscriptionId;

  /// Jour concerné, au format « AAAA-MM-JJ ».
  final String date;
  final TypeAbsence type;
  final bool justifiee;

  /// Durée du retard en minutes ; toujours null pour une absence.
  final int? dureeMinutes;
  final String motif;

  /// Renseignés par les listes de classe (exports) : élève et classe.
  final String eleveNom;
  final String matricule;
  final String classeNom;
}

/// Total des absences et retards d'un élève.
class TotauxAbsences {
  const TotauxAbsences({
    this.absences = 0,
    this.absencesJustifiees = 0,
    this.retards = 0,
    this.retardsJustifies = 0,
    this.minutesRetard = 0,
  });

  /// Totaux d'une liste d'absences et de retards.
  factory TotauxAbsences.depuis(Iterable<Absence> liste) {
    var abs = 0, absJ = 0, ret = 0, retJ = 0, minutes = 0;
    for (final a in liste) {
      if (a.type == TypeAbsence.absence) {
        abs++;
        if (a.justifiee) absJ++;
      } else {
        ret++;
        if (a.justifiee) retJ++;
        minutes += a.dureeMinutes ?? 0;
      }
    }
    return TotauxAbsences(
      absences: abs,
      absencesJustifiees: absJ,
      retards: ret,
      retardsJustifies: retJ,
      minutesRetard: minutes,
    );
  }

  /// Nombre de journées d'absence (justifiées ou non).
  final int absences;
  final int absencesJustifiees;
  final int retards;
  final int retardsJustifies;

  /// Somme des durées de retard renseignées.
  final int minutesRetard;

  int get absencesInjustifiees => absences - absencesJustifiees;
  int get retardsInjustifies => retards - retardsJustifies;
  bool get vide => absences == 0 && retards == 0;
}
