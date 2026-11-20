import '../../domain/calendrier.dart';
import '../../domain/periodes.dart';

/// Nature d'une période affichée : un mois (saisie), une période du
/// calendrier (trimestre, semestre...), une séquence ou l'année entière.
enum GenrePeriode { mois, trimestre, sequence, annee }

/// Période affichée dans la page Notes : un mois (saisie), ou une période,
/// une séquence ou l'année (lecture seule, calculées automatiquement).
///
/// Une période est repérée par son numéro dans le calendrier de l'année
/// (1 = première période) ; [etiquette] est le nom que lui donne ce calendrier
/// (« Semestre 1 »...) et ne compte pas dans l'égalité.
class Periode {
  const Periode.mois(this.numero)
      : genre = GenrePeriode.mois,
        etiquette = null;
  const Periode.trimestre(this.numero, {this.etiquette}) : genre = GenrePeriode.trimestre;
  const Periode.sequence(this.numero, {this.etiquette}) : genre = GenrePeriode.sequence;
  const Periode.annee()
      : genre = GenrePeriode.annee,
        numero = 0,
        etiquette = null;

  /// Mois de la date, s'il est dans l'année scolaire ; sinon octobre.
  factory Periode.moisDe(DateTime date) => moisScolaires.contains(date.month)
      ? Periode.mois(date.month)
      : const Periode.mois(10);

  final GenrePeriode genre;

  /// Numéro du mois (1 à 12), de la période ou de la séquence (à partir de 1) ;
  /// 0 pour l'année.
  final int numero;

  /// Nom donné par le calendrier, s'il diffère du nom par défaut.
  final String? etiquette;

  bool get saisissable => genre == GenrePeriode.mois;

  /// Identifiant stable (pour les clés de test).
  String get cle => switch (genre) {
        GenrePeriode.mois => 'm$numero',
        GenrePeriode.trimestre => 't$numero',
        GenrePeriode.sequence => 'q$numero',
        GenrePeriode.annee => 'annee',
      };

  String get libelle =>
      etiquette ??
      switch (genre) {
        GenrePeriode.mois => libelleMois(numero),
        GenrePeriode.trimestre => libelleTrimestre(numero),
        GenrePeriode.sequence => 'Séquence $numero',
        GenrePeriode.annee => 'Année',
      };

  /// Étendue de calcul correspondante dans [calendrier].
  Portee portee(Calendrier calendrier) => switch (genre) {
        GenrePeriode.mois => Portee.mois(numero),
        GenrePeriode.trimestre => Portee.periode(calendrier.periodes[numero - 1]),
        GenrePeriode.sequence => Portee.periode(calendrier.sequences[numero - 1]),
        GenrePeriode.annee => const Portee.annee(),
      };

  @override
  bool operator ==(Object other) =>
      other is Periode && other.genre == genre && other.numero == numero;

  @override
  int get hashCode => Object.hash(genre, numero);
}

/// Dernier mois de [groupe] dans l'ordre de l'année scolaire.
int _dernierMois(PeriodeScolaire groupe) =>
    moisScolaires.lastWhere(groupe.mois.contains, orElse: () => groupe.mois.last);

/// Périodes dans l'ordre d'affichage : après ses derniers mois viennent la
/// séquence, puis la période qui les regroupe ; l'année est en dernier.
List<Periode> periodesDuCalendrier(Calendrier calendrier) {
  final resultat = <Periode>[];
  for (final mois in moisScolaires) {
    resultat.add(Periode.mois(mois));
    for (var i = 0; i < calendrier.sequences.length; i++) {
      final s = calendrier.sequences[i];
      if (s.mois.isNotEmpty && _dernierMois(s) == mois) {
        resultat.add(Periode.sequence(i + 1, etiquette: s.libelle));
      }
    }
    for (var i = 0; i < calendrier.periodes.length; i++) {
      final p = calendrier.periodes[i];
      if (p.mois.isNotEmpty && _dernierMois(p) == mois) {
        resultat.add(Periode.trimestre(i + 1, etiquette: p.libelle));
      }
    }
  }
  resultat.add(const Periode.annee());
  return resultat;
}

/// Périodes du calendrier par défaut (trois trimestres).
final List<Periode> periodesAffichees = periodesDuCalendrier(Calendrier.defaut);
