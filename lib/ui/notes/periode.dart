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
  const Periode.mois(this.numero, {this.etiquette}) : genre = GenrePeriode.mois;
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
///
/// Seuls les mois où l'on saisit des notes sont proposés ([Calendrier.moisDeSaisie]) :
/// pour les compositions, décembre, mars et juin. Un mois de composition porte
/// son numéro (« Janvier (Compo 1) »).
List<Periode> periodesDuCalendrier(Calendrier calendrier) {
  final resultat = <Periode>[];
  for (final mois in calendrier.moisDeSaisie) {
    resultat.add(Periode.mois(mois, etiquette: calendrier.libelleDuMois(mois)));
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

/// Mois à proposer par défaut à la [date] : le mois courant s'il fait partie des
/// mois de saisie du calendrier, sinon le prochain mois de saisie de l'année (le
/// dernier s'il n'en reste plus). Hors de l'année scolaire : le premier. Sans
/// aucun mois de saisie : l'année.
Periode moisParDefaut(Calendrier calendrier, DateTime date) {
  final mois = calendrier.moisDeSaisie;
  if (mois.isEmpty) return const Periode.annee();
  final rang = moisScolaires.indexOf(date.month);
  var choisi = mois.first;
  if (rang >= 0) {
    choisi = mois.last;
    for (final m in mois) {
      if (moisScolaires.indexOf(m) >= rang) {
        choisi = m;
        break;
      }
    }
  }
  return periodesDuCalendrier(calendrier).firstWhere((p) => p == Periode.mois(choisi));
}
