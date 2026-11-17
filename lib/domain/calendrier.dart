/// Calendrier scolaire configurable : périodes (trimestres, semestres ou
/// découpage personnalisé) et séquences facultatives.
///
/// Le mois reste l'unité de base : une période est un groupe de mois de
/// l'année scolaire (octobre à juin). Chaque mois appartient à une seule
/// période. Les séquences, si elles sont activées, découpent à leur tour
/// chaque période en groupes de mois (par exemple deux séquences par
/// trimestre).
library;

import 'dart:convert';

import 'periodes.dart';

/// Une période (trimestre, semestre...) ou une séquence.
class PeriodeScolaire {
  const PeriodeScolaire({
    required this.cle,
    required this.libelle,
    required this.mois,
  });

  /// Identifiant stable (t1, s2, q3...). Utilisé pour les appréciations.
  final String cle;
  final String libelle;

  /// Mois civils (10, 11, 12, 1...), dans l'ordre de l'année scolaire.
  final List<int> mois;

  Map<String, Object?> toJson() => {'cle': cle, 'libelle': libelle, 'mois': mois};

  factory PeriodeScolaire.fromJson(Map<String, dynamic> json) => PeriodeScolaire(
        cle: json['cle'] as String,
        libelle: json['libelle'] as String,
        mois: [for (final m in json['mois'] as List) m as int],
      );

  @override
  bool operator ==(Object other) =>
      other is PeriodeScolaire &&
      other.cle == cle &&
      other.libelle == libelle &&
      _memesMois(other.mois, mois);

  @override
  int get hashCode => Object.hash(cle, libelle, Object.hashAll(mois));

  static bool _memesMois(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

enum TypePeriodes { trimestres, semestres, personnalise }

/// Clé réservée à la période « année entière ».
const String cleAnnee = 'annee';

/// Étendue d'un calcul : un mois, une période (ou séquence), ou l'année.
class Portee {
  const Portee.mois(int numero)
      : moisChoisi = numero,
        periodeChoisie = null,
        annuelle = false;
  const Portee.periode(PeriodeScolaire periode)
      : moisChoisi = null,
        periodeChoisie = periode,
        annuelle = false;
  const Portee.annee()
      : moisChoisi = null,
        periodeChoisie = null,
        annuelle = true;

  final int? moisChoisi;
  final PeriodeScolaire? periodeChoisie;
  final bool annuelle;

  bool get estMois => moisChoisi != null;
  bool get estPeriode => periodeChoisie != null;

  /// Clé utilisée pour ranger les appréciations (m10, t1, annee...).
  String get cle {
    if (annuelle) return cleAnnee;
    if (periodeChoisie != null) return periodeChoisie!.cle;
    return 'm$moisChoisi';
  }
}

class Calendrier {
  const Calendrier({
    required this.type,
    required this.periodes,
    this.sequences = const [],
    this.moyenneMensuelle = true,
  });

  final TypePeriodes type;
  final List<PeriodeScolaire> periodes;

  /// Vide si les moyennes séquentielles ne sont pas activées.
  final List<PeriodeScolaire> sequences;

  /// Affichage des moyennes mensuelles (grille par mois).
  final bool moyenneMensuelle;

  static const Calendrier trimestres = Calendrier(
    type: TypePeriodes.trimestres,
    periodes: [
      PeriodeScolaire(cle: 't1', libelle: 'Trimestre 1', mois: [10, 11, 12]),
      PeriodeScolaire(cle: 't2', libelle: 'Trimestre 2', mois: [1, 2, 3]),
      PeriodeScolaire(cle: 't3', libelle: 'Trimestre 3', mois: [4, 5, 6]),
    ],
  );

  static const Calendrier semestres = Calendrier(
    type: TypePeriodes.semestres,
    periodes: [
      PeriodeScolaire(cle: 's1', libelle: 'Semestre 1', mois: [10, 11, 12, 1]),
      PeriodeScolaire(cle: 's2', libelle: 'Semestre 2', mois: [2, 3, 4, 5, 6]),
    ],
  );

  /// Calendrier appliqué tant que rien n'a été configuré.
  static const Calendrier defaut = trimestres;

  /// Séquences d'un trimestre sur deux mois (Oct-Nov, Déc-Jan...) : proposées
  /// quand on active les séquences sur un calendrier en trimestres.
  static const List<PeriodeScolaire> sequencesProposees = [
    PeriodeScolaire(cle: 'q1', libelle: 'Séquence 1', mois: [10, 11]),
    PeriodeScolaire(cle: 'q2', libelle: 'Séquence 2', mois: [12]),
    PeriodeScolaire(cle: 'q3', libelle: 'Séquence 3', mois: [1, 2]),
    PeriodeScolaire(cle: 'q4', libelle: 'Séquence 4', mois: [3]),
    PeriodeScolaire(cle: 'q5', libelle: 'Séquence 5', mois: [4, 5]),
    PeriodeScolaire(cle: 'q6', libelle: 'Séquence 6', mois: [6]),
  ];

  Calendrier copyWith({
    TypePeriodes? type,
    List<PeriodeScolaire>? periodes,
    List<PeriodeScolaire>? sequences,
    bool? moyenneMensuelle,
  }) =>
      Calendrier(
        type: type ?? this.type,
        periodes: periodes ?? this.periodes,
        sequences: sequences ?? this.sequences,
        moyenneMensuelle: moyenneMensuelle ?? this.moyenneMensuelle,
      );

  bool get sequencesActives => sequences.isNotEmpty;

  PeriodeScolaire? periode(String cle) {
    for (final p in periodes) {
      if (p.cle == cle) return p;
    }
    return null;
  }

  PeriodeScolaire? sequence(String cle) {
    for (final s in sequences) {
      if (s.cle == cle) return s;
    }
    return null;
  }

  PeriodeScolaire? periodeDuMois(int mois) {
    for (final p in periodes) {
      if (p.mois.contains(mois)) return p;
    }
    return null;
  }

  PeriodeScolaire? sequenceDuMois(int mois) {
    for (final s in sequences) {
      if (s.mois.contains(mois)) return s;
    }
    return null;
  }

  /// Étendue correspondant à une clé (m10, t1, q2, annee), ou null.
  Portee? portee(String cle) {
    if (cle == cleAnnee) return const Portee.annee();
    if (cle.length > 1 && cle.startsWith('m')) {
      final m = int.tryParse(cle.substring(1));
      if (m != null && moisScolaires.contains(m)) return Portee.mois(m);
    }
    final p = periode(cle) ?? sequence(cle);
    return p == null ? null : Portee.periode(p);
  }

  /// Problèmes de configuration (liste vide si le calendrier est valide).
  List<String> erreurs() {
    final e = <String>[];
    if (periodes.isEmpty) {
      e.add('Il faut au moins une période.');
    }
    if (periodes.length > 6) {
      e.add('Six périodes au maximum.');
    }
    _verifierGroupes('période', periodes, e, toutCouvrir: true);
    if (sequences.isNotEmpty) {
      if (sequences.length > 9) e.add('Neuf séquences au maximum.');
      _verifierGroupes('séquence', sequences, e, toutCouvrir: true);
      for (final s in sequences) {
        final parents = {
          for (final m in s.mois)
            if (periodeDuMois(m) != null) periodeDuMois(m)!.cle,
        };
        if (parents.length > 1) {
          e.add(
            'La séquence « ${s.libelle} » chevauche plusieurs périodes : '
            'une séquence doit rester à l\'intérieur d\'une période.',
          );
        }
      }
    }
    return e;
  }

  void _verifierGroupes(
    String nom,
    List<PeriodeScolaire> groupes,
    List<String> e, {
    required bool toutCouvrir,
  }) {
    final cles = <String>{};
    final vus = <int, String>{};
    for (final g in groupes) {
      final libelle = g.libelle.trim();
      if (libelle.isEmpty) {
        e.add('Une $nom n\'a pas de nom.');
      } else if (libelle.length > 30) {
        e.add('Le nom « $libelle » est trop long (30 caractères au maximum).');
      }
      if (g.cle.trim().isEmpty || g.cle == cleAnnee || g.cle.startsWith('m')) {
        e.add('Identifiant « ${g.cle} » non autorisé pour une $nom.');
      } else if (!cles.add(g.cle)) {
        e.add('Deux ${nom}s ont le même identifiant (${g.cle}).');
      }
      if (g.mois.isEmpty) {
        e.add('La $nom « $libelle » ne contient aucun mois.');
      }
      for (final m in g.mois) {
        if (!moisScolaires.contains(m)) {
          e.add('Le mois $m n\'existe pas dans l\'année scolaire (octobre à juin).');
        } else if (vus.containsKey(m)) {
          e.add(
            '${libelleMois(m)} est dans deux ${nom}s : « ${vus[m]} » et « $libelle ».',
          );
        } else {
          vus[m] = libelle;
        }
      }
    }
    if (toutCouvrir) {
      for (final m in moisScolaires) {
        if (!vus.containsKey(m) && groupes.isNotEmpty) {
          e.add('${libelleMois(m)} n\'appartient à aucune $nom.');
        }
      }
    }
  }

  Map<String, Object?> toJson() => {
        'type': type.name,
        'periodes': [for (final p in periodes) p.toJson()],
        'sequences': [for (final s in sequences) s.toJson()],
        'moyenneMensuelle': moyenneMensuelle,
      };

  String toJsonString() => jsonEncode(toJson());

  /// Relit un calendrier enregistré. Tolère l'absence des clés ajoutées plus
  /// tard ; lève une [FormatException] si le contenu est illisible.
  factory Calendrier.fromJson(Map<String, dynamic> json) {
    final nomType = json['type'] as String? ?? 'trimestres';
    return Calendrier(
      type: TypePeriodes.values.firstWhere(
        (t) => t.name == nomType,
        orElse: () => TypePeriodes.personnalise,
      ),
      periodes: [
        for (final p in json['periodes'] as List)
          PeriodeScolaire.fromJson(p as Map<String, dynamic>),
      ],
      sequences: [
        for (final s in (json['sequences'] as List? ?? const []))
          PeriodeScolaire.fromJson(s as Map<String, dynamic>),
      ],
      moyenneMensuelle: json['moyenneMensuelle'] as bool? ?? true,
    );
  }

  factory Calendrier.fromJsonString(String texte) =>
      Calendrier.fromJson(jsonDecode(texte) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      other is Calendrier &&
      other.type == type &&
      other.moyenneMensuelle == moyenneMensuelle &&
      _memesGroupes(other.periodes, periodes) &&
      _memesGroupes(other.sequences, sequences);

  @override
  int get hashCode => Object.hash(
        type,
        moyenneMensuelle,
        Object.hashAll(periodes),
        Object.hashAll(sequences),
      );

  static bool _memesGroupes(List<PeriodeScolaire> a, List<PeriodeScolaire> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
