/// Import des élèves depuis un tableau Excel : champs de GESCO, association
/// des colonnes, puis vérification ligne par ligne **avant** toute écriture.
///
/// Rien n'est lu dans la base ici : le contexte (classes, matricules déjà
/// pris...) est fourni par [ContexteImportEleves], ce qui permet de tout tester
/// sans fichier ni base. L'écriture se fait ensuite en une seule transaction
/// (`EleveDepot.importerLot`).
library;

import '../data/modeles_donnees.dart';
import '../data/validation_eleve.dart';
import '../domain/dates.dart';
import '../domain/matricule.dart';
import '../tableur/classeur.dart';
import 'lecture_tableur.dart';

/// Une information de la fiche élève que l'on peut importer.
enum ChampEleve {
  matricule(
    'Matricule',
    ['matricule', 'n matricule', 'no matricule', 'numero matricule', 'identifiant', 'id'],
  ),
  nom(
    'Nom',
    ['nom', 'noms', 'nom de famille', 'nom eleve', 'nom de l eleve', 'patronyme'],
    obligatoire: true,
  ),
  prenom('Prénom', ['prenom', 'prenoms', 'prenom eleve', 'prenom de l eleve'], obligatoire: true),
  sexe('Sexe', ['sexe', 'genre', 's'], obligatoire: true),
  dateNaissance(
    'Date de naissance',
    ['date de naissance', 'date naissance', 'naissance', 'ne le', 'nee le', 'date de naiss'],
  ),
  lieuNaissance(
    'Lieu de naissance',
    ['lieu de naissance', 'lieu naissance', 'ne a', 'nee a', 'lieu de naiss'],
  ),
  adresse('Adresse', ['adresse', 'domicile', 'residence', 'adresse de l eleve']),
  telephone(
    'Téléphone',
    ['telephone', 'tel', 'numero de telephone', 'telephone eleve', 'contact eleve', 'phone'],
  ),
  nomPere('Nom du père', ['nom du pere', 'nom pere', 'pere']),
  nomMere('Nom de la mère', ['nom de la mere', 'nom mere', 'mere']),
  contactParent(
    'Contact des parents',
    [
      'contact des parents',
      'contact parents',
      'contact parent',
      'contact du parent',
      'telephone des parents',
      'telephone parents',
      'telephone parent',
      'tel parents',
      'tel parent',
    ],
  ),
  nomTuteur(
    'Nom du tuteur',
    [
      'nom du tuteur',
      'nom tuteur',
      'tuteur',
      'parent tuteur',
      'parent ou tuteur',
      'nom du parent tuteur',
      'nom du parent ou tuteur',
      'responsable',
      'nom du responsable',
    ],
  ),
  contactTuteur(
    'Contact du tuteur',
    [
      'contact du tuteur',
      'contact tuteur',
      'telephone du tuteur',
      'telephone tuteur',
      'tel du tuteur',
      'tel tuteur',
      'contact du responsable',
    ],
  ),
  classe('Classe', ['classe', 'classe actuelle', 'classe de l eleve']),
  anneeScolaire('Année scolaire', ['annee scolaire', 'annee', 'annee scolaire en cours']);

  const ChampEleve(this.libelle, this.synonymes, {this.obligatoire = false});

  final String libelle;

  /// Titres de colonne reconnus automatiquement (sous la forme de [cleColonne]).
  final List<String> synonymes;

  /// Champ sans lequel l'élève ne peut pas être créé.
  final bool obligatoire;
}

/// Titres de colonnes connus, pour repérer la ligne d'en-tête d'un fichier.
final Set<String> titresConnusEleves = {
  for (final c in ChampEleve.values) ...c.synonymes,
  // Colonnes des exports de GESCO, ignorées à l'import.
  'n',
  'situation',
};

/// Propose le champ de chaque colonne d'après son titre (null = colonne
/// ignorée). Un champ n'est proposé que pour une seule colonne.
List<ChampEleve?> associerColonnes(List<String> entetes) {
  final res = List<ChampEleve?>.filled(entetes.length, null);
  final pris = <ChampEleve>{};
  for (var i = 0; i < entetes.length; i++) {
    final cle = cleColonne(entetes[i]);
    if (cle.isEmpty) continue;
    for (final c in ChampEleve.values) {
      if (!pris.contains(c) && c.synonymes.contains(cle)) {
        res[i] = c;
        pris.add(c);
        break;
      }
    }
  }
  return res;
}

// ----------------------------------------------------------------- Contexte

/// Une classe de l'année, telle que l'import la connaît.
class ClasseImport {
  const ClasseImport({required this.id, required this.nom, this.capacite, this.nbActifs = 0});

  final int id;
  final String nom;

  /// Nombre maximal d'élèves, ou null si non limité.
  final int? capacite;

  /// Élèves qui suivent déjà la classe.
  final int nbActifs;
}

/// Ce que l'import doit savoir de la base pour vérifier le fichier.
class ContexteImportEleves {
  const ContexteImportEleves({
    required this.anneeLibelle,
    required this.maintenant,
    required this.classes,
    this.existants = const [],
    this.classeParDefautId,
    this.autoriserDepassement = false,
  });

  /// Année scolaire dans laquelle les élèves seront inscrits.
  final String anneeLibelle;

  /// Date du jour (refus d'une naissance dans le futur).
  final DateTime maintenant;
  final List<ClasseImport> classes;

  /// Élèves déjà enregistrés (toutes années, dossiers archivés compris).
  final List<IdentiteEleve> existants;

  /// Classe de tous les élèves dont la colonne « Classe » est absente ou vide.
  final int? classeParDefautId;

  /// Accepte qu'une classe dépasse sa capacité (signalé en avertissement).
  final bool autoriserDepassement;
}

// ------------------------------------------------------------------ Rapport

/// Résultat de la vérification d'une ligne du fichier.
class LigneImportEleve {
  const LigneImportEleve({
    required this.numero,
    required this.nom,
    required this.prenom,
    required this.matricule,
    required this.classe,
    this.eleve,
    this.classeId,
    this.erreurs = const [],
    this.avertissements = const [],
    this.dejaPresent = false,
    this.matriculeGenere = false,
  });

  /// Numéro de la ligne dans le fichier Excel.
  final int numero;

  /// Valeurs lues (affichées même si la ligne est en erreur).
  final String nom;
  final String prenom;
  final String matricule;
  final String classe;

  /// Fiche prête à être enregistrée ; null si la ligne est en erreur.
  final Eleve? eleve;
  final int? classeId;

  /// Raisons pour lesquelles la ligne ne peut pas être importée.
  final List<String> erreurs;

  /// Remarques qui n'empêchent pas l'import.
  final List<String> avertissements;

  /// Cet élève (même matricule, même identité) est déjà dans GESCO : la ligne
  /// est ignorée sans erreur et rien n'est écrasé.
  final bool dejaPresent;

  /// Le matricule du fichier était vide : GESCO en a attribué un.
  final bool matriculeGenere;

  bool get enErreur => erreurs.isNotEmpty;
  bool get aImporter => !enErreur && !dejaPresent && eleve != null && classeId != null;
}

/// Résultat de la vérification d'un fichier entier.
class RapportImportEleves {
  const RapportImportEleves({
    this.problemesFichier = const [],
    this.remarquesFichier = const [],
    this.lignes = const [],
    this.nbLignesVides = 0,
  });

  /// Problèmes qui empêchent toute vérification (colonne obligatoire non
  /// associée, tableau vide...).
  final List<String> problemesFichier;

  /// Informations générales (matricules générés...).
  final List<String> remarquesFichier;
  final List<LigneImportEleve> lignes;

  /// Lignes entièrement vides, ignorées.
  final int nbLignesVides;

  List<LigneImportEleve> get aImporter => [
        for (final l in lignes)
          if (l.aImporter) l,
      ];
  int get nbAImporter => aImporter.length;
  int get nbDejaPresents => lignes.where((l) => l.dejaPresent && !l.enErreur).length;
  int get nbErreurs => lignes.where((l) => l.enErreur).length;
  int get nbAvertissements =>
      lignes.where((l) => !l.enErreur && l.avertissements.isNotEmpty).length;

  /// Vrai si le fichier a un problème qui bloque tout.
  bool get bloque => problemesFichier.isNotEmpty;

  /// Peut-on lancer l'import ? Il faut au moins une ligne valide, et soit
  /// aucune ligne en erreur, soit l'accord pour les ignorer.
  bool peutImporter({required bool ignorerErreurs}) =>
      !bloque && nbAImporter > 0 && (nbErreurs == 0 || ignorerErreurs);

  /// Nombre d'élèves à importer dans chaque classe (nom -> effectif).
  Map<String, int> get effectifParClasse {
    final res = <String, int>{};
    for (final l in aImporter) {
      res[l.classe] = (res[l.classe] ?? 0) + 1;
    }
    return res;
  }
}

// ------------------------------------------------------------- Vérification

String _texte(Cellule c) => c.texte.replaceAll(RegExp(r'\s+'), ' ').trim();

/// « M », « masculin », « garçon »... -> « M » ; « F », « féminin »... -> « F » ;
/// null si le texte n'est pas reconnu.
String? sexeDepuisTexte(String texte) {
  switch (cleColonne(texte)) {
    case 'm' || 'masculin' || 'garcon' || 'g' || 'h' || 'homme':
      return 'M';
    case 'f' || 'feminin' || 'fille' || 'femme':
      return 'F';
  }
  return null;
}

/// Lit une date de naissance : vraie date Excel, texte « JJ/MM/AAAA » ou
/// « AAAA-MM-JJ », ou numéro de série Excel. [illisible] est vrai si la
/// cellule n'est pas vide mais ne contient pas de date valide.
({DateTime? date, bool illisible}) lireDate(Cellule c) {
  if (c.vide) return (date: null, illisible: false);
  final d = c.date;
  if (d != null) return (date: DateTime(d.year, d.month, d.day), illisible: false);
  final t = c.texte.trim();
  final lue = analyserDateFr(t) ?? analyserDateIso(t);
  if (lue != null) return (date: lue, illisible: false);
  final n = c.nombre;
  if (n != null && n == n.roundToDouble() && n >= 10000 && n <= 60000) {
    // Numéro de série Excel : jours écoulés depuis le 30/12/1899.
    final serie = DateTime.utc(1899, 12, 30).add(Duration(days: n.toInt()));
    return (date: DateTime(serie.year, serie.month, serie.day), illisible: false);
  }
  return (date: null, illisible: true);
}

String _cleAnnee(String s) => RegExp(r'\d+').allMatches(s).map((m) => m.group(0)).join('-');

String _cleClasse(String s) => cleColonne(s).replaceAll(' ', '');

String _cleIdentite(String nom, String prenom) => '${cleColonne(nom)}|${cleColonne(prenom)}';

String _cleIdentiteDate(String nom, String prenom, String? iso) =>
    '${_cleIdentite(nom, prenom)}|${iso ?? ''}';

String _nomComplet(IdentiteEleve e) => '${e.nom.toUpperCase()} ${e.prenom}';

class _Brouillon {
  _Brouillon(this.numero);

  final int numero;
  String nom = '', prenom = '', matricule = '', classe = '';
  String sexe = '';
  String? dateIso;
  String lieu = '', adresse = '', telephone = '';
  String pere = '', mere = '', contactParent = '', tuteur = '', contactTuteur = '';
  ClasseImport? classeTrouvee;
  bool matriculeGenere = false;
  bool dejaPresent = false;
  final erreurs = <String>[];
  final avertissements = <String>[];
}

/// Vérifie tout le fichier : aucune écriture, seulement un rapport détaillé.
RapportImportEleves analyserImportEleves({
  required TableLue table,
  required List<ChampEleve?> association,
  required ContexteImportEleves ctx,
}) {
  // ---- Association des colonnes
  final colonneDe = <ChampEleve, int>{};
  final problemes = <String>[];
  for (var i = 0; i < association.length; i++) {
    final champ = association[i];
    if (champ == null) continue;
    final deja = colonneDe[champ];
    if (deja != null) {
      problemes.add(
        'Le champ « ${champ.libelle} » est associé à deux colonnes '
        '(« ${_titre(table, deja)} » et « ${_titre(table, i)} »).',
      );
    } else {
      colonneDe[champ] = i;
    }
  }
  for (final c in ChampEleve.values) {
    if (c.obligatoire && !colonneDe.containsKey(c)) {
      problemes.add('Aucune colonne n\'est associée au champ obligatoire « ${c.libelle} ».');
    }
  }
  ClasseImport? parDefaut;
  for (final c in ctx.classes) {
    if (c.id == ctx.classeParDefautId) parDefaut = c;
  }
  if (!colonneDe.containsKey(ChampEleve.classe) && parDefaut == null) {
    problemes.add(
      'Aucune colonne « Classe » n\'est associée : choisissez la classe de tous les élèves '
      'du fichier.',
    );
  }
  if (table.lignes.isEmpty) {
    problemes.add('Le tableau ne contient aucune ligne d\'élève sous la ligne d\'en-tête.');
  }
  if (problemes.isNotEmpty) return RapportImportEleves(problemesFichier: problemes);

  String lire(LigneTable l, ChampEleve c) {
    final i = colonneDe[c];
    return i == null ? '' : _texte(l.cellule(i));
  }

  final classesParCle = {for (final c in ctx.classes) _cleClasse(c.nom): c};
  final anneeCle = _cleAnnee(ctx.anneeLibelle);
  final maintenant = ctx.maintenant;

  final parMatricule = {for (final e in ctx.existants) e.matricule.trim().toLowerCase(): e};
  final parIdentite = <String, IdentiteEleve>{};
  for (final e in ctx.existants) {
    parIdentite.putIfAbsent(_cleIdentiteDate(e.nom, e.prenom, e.dateNaissance), () => e);
  }

  // ---- Lecture des lignes
  final brouillons = <_Brouillon>[];
  var nbVides = 0;
  for (final l in table.lignes) {
    final utiles = [
      for (final i in colonneDe.values)
        if (!l.cellule(i).vide) i,
    ];
    if (utiles.isEmpty) {
      nbVides++;
      continue;
    }
    final b = _Brouillon(l.numero);
    brouillons.add(b);

    for (final i in utiles) {
      if (l.cellule(i).formule) {
        b.erreurs.add(
          'La cellule « ${_titre(table, i)} » contient une formule : remplacez-la par sa '
          'valeur (Copier, puis Collage spécial > Valeurs).',
        );
        break;
      }
    }

    b.nom = lire(l, ChampEleve.nom);
    b.prenom = lire(l, ChampEleve.prenom);
    b.matricule = lire(l, ChampEleve.matricule);
    b.lieu = lire(l, ChampEleve.lieuNaissance);
    b.adresse = lire(l, ChampEleve.adresse);
    b.telephone = lire(l, ChampEleve.telephone);
    b.pere = lire(l, ChampEleve.nomPere);
    b.mere = lire(l, ChampEleve.nomMere);
    b.contactParent = lire(l, ChampEleve.contactParent);
    b.tuteur = lire(l, ChampEleve.nomTuteur);
    b.contactTuteur = lire(l, ChampEleve.contactTuteur);
    b.classe = lire(l, ChampEleve.classe);

    // Sexe
    final sexeBrut = lire(l, ChampEleve.sexe);
    if (sexeBrut.isNotEmpty) {
      final s = sexeDepuisTexte(sexeBrut);
      if (s == null) {
        b.erreurs.add('Sexe « $sexeBrut » non reconnu (attendu : M ou F).');
      } else {
        b.sexe = s;
      }
    }

    // Date de naissance
    final iDate = colonneDe[ChampEleve.dateNaissance];
    if (iDate != null) {
      final r = lireDate(l.cellule(iDate));
      if (r.illisible) {
        b.erreurs.add(
          'Date de naissance « ${_texte(l.cellule(iDate))} » illisible (attendu : JJ/MM/AAAA).',
        );
      } else if (r.date != null) {
        b.dateIso = dateVersIso(r.date!);
      }
    }

    // Année scolaire
    final annee = lire(l, ChampEleve.anneeScolaire);
    if (annee.isNotEmpty && _cleAnnee(annee) != anneeCle) {
      b.erreurs.add(
        'Année scolaire « $annee » différente de l\'année en cours (${ctx.anneeLibelle}).',
      );
    }

    // Classe
    if (b.classe.isEmpty) {
      if (parDefaut == null) {
        b.erreurs.add('Classe manquante.');
      } else {
        b.classeTrouvee = parDefaut;
        b.classe = parDefaut.nom;
      }
    } else {
      final c = classesParCle[_cleClasse(b.classe)];
      if (c == null) {
        final noms = [for (final c in ctx.classes.take(8)) c.nom].join(', ');
        b.erreurs.add(
          'Classe « ${b.classe} » inconnue pour ${ctx.anneeLibelle}'
          '${noms.isEmpty ? '' : ' (classes : $noms${ctx.classes.length > 8 ? '…' : ''})'}.',
        );
      } else {
        b.classeTrouvee = c;
        b.classe = c.nom;
      }
    }
  }

  // ---- Matricules : doublons, élèves déjà présents, génération
  final vus = <String, int>{};
  for (final b in brouillons) {
    if (b.matricule.isEmpty) continue;
    final cle = b.matricule.toLowerCase();
    final avant = vus[cle];
    if (avant != null) {
      b.erreurs.add(
        'Doublon dans le fichier : le matricule « ${b.matricule} » est déjà utilisé ligne $avant.',
      );
      continue;
    }
    vus[cle] = b.numero;
    final connu = parMatricule[cle];
    if (connu == null) continue;
    if (_cleIdentite(connu.nom, connu.prenom) == _cleIdentite(b.nom, b.prenom)) {
      b.dejaPresent = true;
    } else {
      b.erreurs.add(
        'Le matricule « ${b.matricule} » appartient déjà à ${_nomComplet(connu)} dans GESCO'
        '${connu.archive ? ' (dossier archivé)' : ''}.',
      );
    }
  }

  final pool = <String>[
    for (final e in ctx.existants) e.matricule,
    for (final b in brouillons)
      if (b.matricule.isNotEmpty) b.matricule,
  ];
  final prefixe = RegExp(r'\d{4}').firstMatch(ctx.anneeLibelle)?.group(0) ?? '';
  var nbGeneres = 0;
  for (final b in brouillons) {
    if (b.matricule.isNotEmpty || b.erreurs.isNotEmpty) continue;
    final m = proposerMatricule(prefixe, pool);
    pool.add(m);
    b.matricule = m;
    b.matriculeGenere = true;
    nbGeneres++;
  }

  // ---- Personnes déjà connues (même nom, prénom et date de naissance)
  final dansFichier = <String, int>{};
  for (final b in brouillons) {
    if (b.nom.isEmpty || b.prenom.isEmpty) continue;
    final cle = _cleIdentiteDate(b.nom, b.prenom, b.dateIso);
    if (!b.dejaPresent) {
      final connu = parIdentite[cle];
      if (connu != null && connu.matricule.trim().toLowerCase() != b.matricule.toLowerCase()) {
        b.avertissements.add(
          'Un élève de même nom, prénom et date de naissance existe déjà dans GESCO '
          '(matricule ${connu.matricule}) : vérifiez qu\'il ne s\'agit pas d\'un doublon.',
        );
      }
      final avant = dansFichier[cle];
      if (avant != null) {
        b.avertissements.add(
          'Même nom, prénom et date de naissance que la ligne $avant du fichier.',
        );
      }
    }
    dansFichier.putIfAbsent(cle, () => b.numero);
  }

  // ---- Fiches et règles communes avec la saisie manuelle
  final fiches = <_Brouillon, Eleve>{};
  for (final b in brouillons) {
    final eleve = Eleve(
      matricule: b.matricule,
      nom: b.nom,
      prenom: b.prenom,
      sexe: b.sexe,
      dateNaissance: b.dateIso,
      lieuNaissance: b.lieu,
      adresse: b.adresse,
      telephone: b.telephone,
      nomPere: b.pere,
      nomMere: b.mere,
      contactParent: b.contactParent,
      nomTuteur: b.tuteur,
      contactTuteur: b.contactTuteur,
    );
    fiches[b] = eleve;
    final sexeDejaSignale = b.erreurs.any((e) => e.startsWith('Sexe '));
    for (final e in erreursEleve(eleve, maintenant: maintenant)) {
      if (sexeDejaSignale && e.startsWith('Le sexe')) continue;
      // Un matricule vide est déjà expliqué par une autre erreur de la ligne.
      if (b.matricule.isEmpty && e.startsWith('Le matricule')) continue;
      b.erreurs.add(e);
    }
    final naissance = analyserDateIso(b.dateIso);
    if (naissance != null && !naissance.isAfter(maintenant)) {
      final age = ageEn(naissance, maintenant);
      if (age < 3 || age > 30) {
        b.avertissements.add('Âge inhabituel pour un élève : $age ans.');
      }
    }
  }

  // ---- Capacité des classes
  final ajoutes = <int, int>{};
  for (final b in brouillons) {
    final c = b.classeTrouvee;
    if (c == null || b.erreurs.isNotEmpty || b.dejaPresent) continue;
    final n = (ajoutes[c.id] ?? 0) + 1;
    ajoutes[c.id] = n;
    final cap = c.capacite;
    if (cap != null && c.nbActifs + n > cap) {
      final msg = 'La classe « ${c.nom} » est pleine (capacité $cap, ${c.nbActifs} élève'
          '${c.nbActifs > 1 ? 's' : ''} déjà inscrit${c.nbActifs > 1 ? 's' : ''}).';
      if (ctx.autoriserDepassement) {
        b.avertissements.add('$msg Dépassement autorisé.');
      } else {
        b.erreurs.add(msg);
      }
    }
  }

  final remarques = <String>[
    if (!colonneDe.containsKey(ChampEleve.matricule))
      'Aucune colonne « Matricule » : GESCO attribuera un matricule à chaque élève.'
    else if (nbGeneres > 0)
      '$nbGeneres matricule${nbGeneres > 1 ? 's' : ''} vide${nbGeneres > 1 ? 's' : ''} : '
          'GESCO attribuera automatiquement ${nbGeneres > 1 ? 'un matricule à chacun' : 'un matricule'}.',
    if (nbVides > 0) '$nbVides ligne${nbVides > 1 ? 's' : ''} vide${nbVides > 1 ? 's' : ''} ignorée${nbVides > 1 ? 's' : ''}.',
  ];

  return RapportImportEleves(
    remarquesFichier: remarques,
    nbLignesVides: nbVides,
    lignes: [
      for (final b in brouillons)
        LigneImportEleve(
          numero: b.numero,
          nom: b.nom,
          prenom: b.prenom,
          matricule: b.matricule,
          classe: b.classe,
          eleve: b.erreurs.isEmpty ? fiches[b] : null,
          classeId: b.classeTrouvee?.id,
          erreurs: List.unmodifiable(b.erreurs),
          avertissements: List.unmodifiable(b.avertissements),
          dejaPresent: b.dejaPresent,
          matriculeGenere: b.matriculeGenere,
        ),
    ],
  );
}

String _titre(TableLue t, int colonne) {
  final titre = colonne < t.entetes.length ? t.entetes[colonne] : '';
  return titre.isEmpty ? 'colonne ${TableLue.lettre(colonne)}' : titre;
}

// --------------------------------------------------------- Fichiers produits

CelluleEcrite _t(String s, [StyleCellule style = StyleCellule.normal]) => CelluleEcrite(s, style);

CelluleEcrite _h(String s) => CelluleEcrite(s, StyleCellule.entete);

/// Rapport de vérification, à ouvrir dans Excel : une ligne par ligne du
/// fichier ayant une erreur, un avertissement ou ignorée.
FeuilleEcrite feuilleRapportImportEleves({
  required String etablissement,
  required String anneeLibelle,
  required String nomFichier,
  required DateTime date,
  required RapportImportEleves rapport,
}) {
  String d2(int n) => n.toString().padLeft(2, '0');
  final quand = '${d2(date.day)}/${d2(date.month)}/${date.year}';
  final lignes = <List<CelluleEcrite?>>[
    [_t(etablissement.isEmpty ? 'Établissement' : etablissement, StyleCellule.titre)],
    [_t('Rapport de vérification de l\'import des élèves', StyleCellule.etiquette)],
    [
      _t(
        'Fichier « $nomFichier »  ·  Année scolaire $anneeLibelle  ·  Vérifié le $quand',
        StyleCellule.discret,
      ),
    ],
    [
      _t(
        '${rapport.nbAImporter} à importer  ·  ${rapport.nbDejaPresents} déjà présents  ·  '
        '${rapport.nbErreurs} en erreur  ·  ${rapport.nbAvertissements} avec remarque',
        StyleCellule.discret,
      ),
    ],
    <CelluleEcrite?>[],
  ];
  for (final p in rapport.problemesFichier) {
    lignes.add([_t('Problème : $p', StyleCellule.etiquette)]);
  }
  for (final r in rapport.remarquesFichier) {
    lignes.add([_t(r, StyleCellule.discret)]);
  }
  if (rapport.problemesFichier.isNotEmpty || rapport.remarquesFichier.isNotEmpty) {
    lignes.add(<CelluleEcrite?>[]);
  }
  lignes.add([_h('Ligne'), _h('Matricule'), _h('Nom'), _h('Prénom'), _h('Classe'), _h('Résultat'), _h('Détail')]);
  for (final l in rapport.lignes) {
    final resultat = l.enErreur
        ? 'Erreur'
        : l.dejaPresent
            ? 'Déjà présent (ignoré)'
            : l.avertissements.isNotEmpty
                ? 'À importer (remarque)'
                : 'À importer';
    if (resultat == 'À importer') continue;
    lignes.add([
      CelluleEcrite(l.numero, StyleCellule.entier),
      _t(l.matricule),
      _t(l.nom),
      _t(l.prenom),
      _t(l.classe),
      _t(resultat),
      _t([...l.erreurs, ...l.avertissements].join('\n')),
    ]);
  }
  return FeuilleEcrite('Rapport', lignes, largeurs: const [8, 14, 22, 22, 12, 22, 80]);
}

/// Modèle vierge à remplir puis importer : mêmes titres que la liste des
/// élèves exportée par GESCO (sans « N° » ni « Situation »).
FeuilleEcrite feuilleModeleImportEleves({required String etablissement, required String anneeLibelle}) {
  const titres = [
    'Matricule',
    'Nom',
    'Prénom',
    'Sexe',
    'Date de naissance',
    'Lieu de naissance',
    'Adresse',
    'Téléphone',
    'Nom du père',
    'Nom de la mère',
    'Contact des parents',
    'Nom du tuteur',
    'Contact du tuteur',
    'Classe',
  ];
  final lignes = <List<CelluleEcrite?>>[
    [_t(etablissement.isEmpty ? 'Établissement' : etablissement, StyleCellule.titre)],
    [_t('Liste des élèves à importer dans GESCO', StyleCellule.etiquette)],
    [
      _t(
        'Année scolaire $anneeLibelle. Une ligne par élève. Obligatoires : Nom, Prénom, Sexe '
        '(M ou F) et Classe.',
        StyleCellule.discret,
      ),
    ],
    [
      _t(
        'Date de naissance : JJ/MM/AAAA. Matricule vide : GESCO en attribue un. '
        'La classe doit exister dans GESCO.',
        StyleCellule.discret,
      ),
    ],
    <CelluleEcrite?>[],
    [for (final t in titres) _h(t)],
    for (var i = 0; i < 30; i++)
      [for (final _ in titres) const CelluleEcrite(null, StyleCellule.saisie)],
  ];
  return FeuilleEcrite(
    'Élèves',
    lignes,
    largeurs: const [14, 22, 22, 8, 16, 20, 24, 14, 22, 22, 18, 22, 18, 12],
  );
}
