import '../../domain/periodes.dart';

enum GenrePeriode { mois, trimestre, annee }

/// Période affichée dans la page Notes : un mois (saisie), un trimestre ou
/// l'année (lecture seule, calculés automatiquement).
class Periode {
  const Periode.mois(this.numero) : genre = GenrePeriode.mois;
  const Periode.trimestre(this.numero) : genre = GenrePeriode.trimestre;
  const Periode.annee()
      : genre = GenrePeriode.annee,
        numero = 0;

  /// Mois de la date, s'il est dans l'année scolaire ; sinon octobre.
  factory Periode.moisDe(DateTime date) => moisScolaires.contains(date.month)
      ? Periode.mois(date.month)
      : const Periode.mois(10);

  final GenrePeriode genre;

  /// Numéro du mois (1 à 12) ou du trimestre (1 à 3) ; 0 pour l'année.
  final int numero;

  bool get saisissable => genre == GenrePeriode.mois;

  /// Identifiant stable (pour les clés de test).
  String get cle => switch (genre) {
        GenrePeriode.mois => 'm$numero',
        GenrePeriode.trimestre => 't$numero',
        GenrePeriode.annee => 'annee',
      };

  String get libelle => switch (genre) {
        GenrePeriode.mois => libelleMois(numero),
        GenrePeriode.trimestre => libelleTrimestre(numero),
        GenrePeriode.annee => 'Année',
      };

  @override
  bool operator ==(Object other) =>
      other is Periode && other.genre == genre && other.numero == numero;

  @override
  int get hashCode => Object.hash(genre, numero);
}

/// Périodes dans l'ordre d'affichage : chaque trimestre suit ses trois mois.
const List<Periode> periodesAffichees = [
  Periode.mois(10),
  Periode.mois(11),
  Periode.mois(12),
  Periode.trimestre(1),
  Periode.mois(1),
  Periode.mois(2),
  Periode.mois(3),
  Periode.trimestre(2),
  Periode.mois(4),
  Periode.mois(5),
  Periode.mois(6),
  Periode.trimestre(3),
  Periode.annee(),
];
