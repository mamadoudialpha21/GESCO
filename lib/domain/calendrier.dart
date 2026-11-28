/// Calendrier scolaire configurable : périodes (trimestres, semestres ou
/// découpage personnalisé), séquences facultatives et méthode de calcul.
///
/// Trois méthodes de calcul existent (voir [MethodeCalcul]) : l'ancienne
/// (moyenne des moyennes mensuelles), les compositions de la maternelle et du
/// primaire (décembre, mars, juin) et les semestres du collège et du lycée
/// (mois + composition, janvier et juin faisant office de compositions).
///
/// Le mois reste l'unité de base : une période est un groupe de mois de
/// l'année scolaire (octobre à juin). Chaque mois appartient à une seule
/// période. Les séquences, si elles sont activées, découpent à leur tour
/// chaque période en groupes de mois (par exemple deux séquences par
/// trimestre).
library;

import 'dart:convert';

import 'niveaux.dart';
import 'periodes.dart';

/// Une période (trimestre, semestre...) ou une séquence.
class PeriodeScolaire {
  const PeriodeScolaire({
    required this.cle,
    required this.libelle,
    required this.mois,
    this.moisCompo,
    this.poidsCompo = 2,
  });

  /// Identifiant stable (t1, s2, q3...). Utilisé pour les appréciations.
  final String cle;
  final String libelle;

  /// Mois civils (10, 11, 12, 1...), dans l'ordre de l'année scolaire.
  final List<int> mois;

  /// Mois dont la moyenne est la **composition** de la période (janvier pour
  /// le premier semestre, juin pour le second). Null : toutes les moyennes
  /// mensuelles pèsent pareil (ancienne méthode).
  final int? moisCompo;

  /// Poids de la composition face à la moyenne des autres mois : avec 2, la
  /// moyenne de la période est (2 × composition + moyenne des mois) ÷ 3.
  final int poidsCompo;

  Map<String, Object?> toJson() => {
        'cle': cle,
        'libelle': libelle,
        'mois': mois,
        if (moisCompo != null) 'moisCompo': moisCompo,
        if (moisCompo != null) 'poidsCompo': poidsCompo,
      };

  factory PeriodeScolaire.fromJson(Map<String, dynamic> json) => PeriodeScolaire(
        cle: json['cle'] as String,
        libelle: json['libelle'] as String,
        mois: [for (final m in json['mois'] as List) m as int],
        moisCompo: json['moisCompo'] as int?,
        poidsCompo: json['poidsCompo'] as int? ?? 2,
      );

  @override
  bool operator ==(Object other) =>
      other is PeriodeScolaire &&
      other.cle == cle &&
      other.libelle == libelle &&
      other.moisCompo == moisCompo &&
      other.poidsCompo == poidsCompo &&
      _memesMois(other.mois, mois);

  @override
  int get hashCode =>
      Object.hash(cle, libelle, moisCompo, poidsCompo, Object.hashAll(mois));

  static bool _memesMois(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

enum TypePeriodes {
  /// Trois trimestres (octobre-décembre, janvier-mars, avril-juin).
  trimestres,

  /// Deux périodes appelées « semestres ».
  semestres,

  /// Deux trimestres (octobre-janvier, février-juin) : modèle du collège et
  /// du lycée.
  deuxTrimestres,

  /// Compositions de la maternelle et du primaire : décembre, mars et juin.
  compositions,

  /// Semestres du collège et du lycée : mois + composition (janvier, juin).
  semestresCompo,
  personnalise,
}

/// Façon de calculer les moyennes d'une période.
enum MethodeCalcul {
  /// Ancienne méthode : une période est la moyenne de ses moyennes mensuelles.
  moyenneDesMois,

  /// Maternelle et primaire : trois compositions (décembre, mars, juin).
  /// Moyenne d'une composition = moyenne des notes de la composition ; note
  /// finale = moyenne des moyennes des compositions.
  compositions,

  /// Collège et lycée : une note par matière et par mois (octobre à juin).
  /// Janvier est la composition 1, juin la composition 2. Moyenne d'un
  /// semestre = (2 × composition + moyenne des autres mois) ÷ 3 ; moyenne de
  /// l'année = (semestre 1 + semestre 2) ÷ 2.
  semestresCompo,
}

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
    this.ponderee = true,
  });

  final TypePeriodes type;
  final List<PeriodeScolaire> periodes;

  /// Vide si les moyennes séquentielles ne sont pas activées.
  final List<PeriodeScolaire> sequences;

  /// Affichage des moyennes mensuelles (grille par mois).
  final bool moyenneMensuelle;

  /// Vrai (par défaut) : la moyenne d'un mois est pondérée par les coefficients
  /// des matières, ce qui donne « somme des notes ÷ nombre de matières » quand
  /// tous les coefficients valent 1. Faux : moyenne simple, coefficients ignorés
  /// (somme des notes ÷ nombre de matières notées).
  final bool ponderee;

  /// Méthode de calcul de ce calendrier.
  MethodeCalcul get methode => switch (type) {
        TypePeriodes.compositions => MethodeCalcul.compositions,
        TypePeriodes.semestresCompo => MethodeCalcul.semestresCompo,
        _ => MethodeCalcul.moyenneDesMois,
      };

  /// Mois où des notes sont saisies pour ce calendrier, dans l'ordre de
  /// l'année : les neuf mois, sauf pour les compositions (décembre, mars, juin).
  List<int> get moisDeSaisie => [
        for (final m in moisScolaires)
          if (periodes.any((p) => p.mois.contains(m))) m,
      ];

  /// Numéro de composition d'un mois (1, 2, 3), ou null si ce mois n'est pas
  /// une composition : décembre, mars et juin pour les compositions ; janvier
  /// et juin pour les semestres du collège et du lycée.
  int? numeroCompo(int mois) {
    for (var i = 0; i < periodes.length; i++) {
      final p = periodes[i];
      switch (methode) {
        case MethodeCalcul.compositions:
          if (p.mois.contains(mois)) return i + 1;
        case MethodeCalcul.semestresCompo:
          if (p.moisCompo == mois) return i + 1;
        case MethodeCalcul.moyenneDesMois:
          break;
      }
    }
    return null;
  }

  /// Description courte de la méthode : « 3 compositions », « 2 semestres avec
  /// compositions », « 3 périodes »...
  String get descriptionCourte {
    final n = periodes.length;
    return switch (methode) {
      MethodeCalcul.compositions => '$n compositions',
      MethodeCalcul.semestresCompo => '$n semestres avec compositions',
      MethodeCalcul.moyenneDesMois => n > 1 ? '$n périodes' : '$n période',
    };
  }

  /// Nom d'un mois dans ce calendrier : « Janvier », ou « Janvier (Compo 1) »
  /// quand ce mois est une composition.
  String libelleDuMois(int mois) {
    final n = numeroCompo(mois);
    return n == null ? libelleMois(mois) : '${libelleMois(mois)} (Compo $n)';
  }

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

  /// Deux trimestres : octobre à janvier, puis février à juin. Les mois de
  /// chaque trimestre restent modifiables dans les paramètres.
  static const Calendrier deuxTrimestres = Calendrier(
    type: TypePeriodes.deuxTrimestres,
    periodes: [
      PeriodeScolaire(cle: 't1', libelle: 'Trimestre 1', mois: [10, 11, 12, 1]),
      PeriodeScolaire(cle: 't2', libelle: 'Trimestre 2', mois: [2, 3, 4, 5, 6]),
    ],
  );

  /// Maternelle et primaire : trois compositions, en décembre, en mars et en
  /// juin. La note finale est la moyenne des moyennes des compositions. Les
  /// identifiants (t1, t2, t3) sont ceux des anciens trimestres : les
  /// appréciations déjà saisies restent rattachées à la période correspondante.
  static const Calendrier compositions = Calendrier(
    type: TypePeriodes.compositions,
    periodes: [
      PeriodeScolaire(cle: 't1', libelle: 'Compo 1 (décembre)', mois: [12]),
      PeriodeScolaire(cle: 't2', libelle: 'Compo 2 (mars)', mois: [3]),
      PeriodeScolaire(cle: 't3', libelle: 'Compo 3 (juin)', mois: [6]),
    ],
  );

  /// Collège et lycée : deux semestres (mêmes identifiants et mêmes mois que
  /// les anciens « deux trimestres »). Janvier est la composition 1 du
  /// semestre 1, juin la composition 2 du semestre 2. Moyenne d'un semestre =
  /// (2 × composition + moyenne des autres mois) ÷ 3.
  static const Calendrier semestresCompo = Calendrier(
    type: TypePeriodes.semestresCompo,
    periodes: [
      PeriodeScolaire(cle: 't1', libelle: 'Semestre 1', mois: [10, 11, 12, 1], moisCompo: 1),
      PeriodeScolaire(cle: 't2', libelle: 'Semestre 2', mois: [2, 3, 4, 5, 6], moisCompo: 6),
    ],
  );

  /// Calendrier appliqué tant que rien n'a été configuré.
  static const Calendrier defaut = trimestres;

  /// Calendrier d'un cycle tant que rien n'a été configuré pour lui : les
  /// compositions à la maternelle et au primaire, les semestres avec
  /// composition au collège et au lycée. Sans cycle connu : [defaut].
  static Calendrier pourCycle(Cycle? cycle) => switch (cycle) {
        Cycle.maternelle || Cycle.primaire => compositions,
        Cycle.college || Cycle.lycee => semestresCompo,
        null => defaut,
      };

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
    bool? ponderee,
  }) =>
      Calendrier(
        type: type ?? this.type,
        periodes: periodes ?? this.periodes,
        sequences: sequences ?? this.sequences,
        moyenneMensuelle: moyenneMensuelle ?? this.moyenneMensuelle,
        ponderee: ponderee ?? this.ponderee,
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

  /// Période en cours au [mois] : celle qui le contient ; sinon, pour un mois
  /// scolaire qui n'appartient à aucune période (novembre avec des
  /// compositions, par exemple), la prochaine période de l'année, ou la
  /// dernière s'il n'en reste plus. Null hors de l'année scolaire.
  PeriodeScolaire? periodeEnCours(int mois) {
    if (!moisScolaires.contains(mois)) return null;
    final contenue = periodeDuMois(mois);
    if (contenue != null) return contenue;
    final rang = moisScolaires.indexOf(mois);
    PeriodeScolaire? derniere;
    for (final p in periodes) {
      var fin = -1;
      for (final m in p.mois) {
        final r = moisScolaires.indexOf(m);
        if (r > fin) fin = r;
      }
      if (fin < 0) continue;
      derniere = p;
      if (fin >= rang) return p;
    }
    return derniere;
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
    _verifierGroupes(
      'période',
      periodes,
      e,
      toutCouvrir: methode != MethodeCalcul.compositions,
    );
    _verifierMethode(e);
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

  /// Contrôles propres aux compositions et aux semestres avec composition.
  void _verifierMethode(List<String> e) {
    switch (methode) {
      case MethodeCalcul.compositions:
        for (final p in periodes) {
          if (p.mois.length != 1) {
            e.add(
              'La composition « ${p.libelle} » doit correspondre à un seul mois.',
            );
          }
        }
        if (sequences.isNotEmpty) {
          e.add('Les séquences ne sont pas prévues avec les compositions.');
        }
      case MethodeCalcul.semestresCompo:
        for (final p in periodes) {
          final compo = p.moisCompo;
          if (compo == null || !p.mois.contains(compo)) {
            e.add(
              'La période « ${p.libelle} » doit avoir un mois de composition '
              'parmi ses mois.',
            );
          }
          if (p.poidsCompo < 1 || p.poidsCompo > 10) {
            e.add('Le poids de la composition de « ${p.libelle} » doit être de 1 à 10.');
          }
        }
        if (sequences.isNotEmpty) {
          e.add('Les séquences ne sont pas prévues avec les semestres.');
        }
      case MethodeCalcul.moyenneDesMois:
        break;
    }
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
        if (!ponderee) 'ponderee': false,
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
      ponderee: json['ponderee'] as bool? ?? true,
    );
  }

  factory Calendrier.fromJsonString(String texte) =>
      Calendrier.fromJson(jsonDecode(texte) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      other is Calendrier &&
      other.type == type &&
      other.moyenneMensuelle == moyenneMensuelle &&
      other.ponderee == ponderee &&
      _memesGroupes(other.periodes, periodes) &&
      _memesGroupes(other.sequences, sequences);

  @override
  int get hashCode => Object.hash(
        type,
        moyenneMensuelle,
        ponderee,
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

/// Calendriers d'une année scolaire : un par cycle (maternelle, primaire,
/// collège, lycée), et un calendrier général pour les classes qui ne sont rattachées à
/// aucun cycle.
class CalendriersAnnee {
  const CalendriersAnnee({
    this.general = Calendrier.defaut,
    this.parCycle = const {},
  });

  final Calendrier general;

  /// Calendriers enregistrés pour un cycle. Un cycle absent suit le modèle
  /// de son cycle ([Calendrier.pourCycle]).
  final Map<Cycle, Calendrier> parCycle;

  /// Calendrier d'une classe selon son [cycle] (null : calendrier général).
  Calendrier pour(Cycle? cycle) =>
      cycle == null ? general : (parCycle[cycle] ?? Calendrier.pourCycle(cycle));
}
