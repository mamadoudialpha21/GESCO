/// Génération automatique des bulletins individuels.
///
/// Chaque fois que des notes sont enregistrées (note du mois, évaluation,
/// composition), les bulletins de la classe concernée sont régénérés :
/// - le bulletin du mois ;
/// - le bulletin du trimestre, quand la saisie est une composition ou un
///   examen, ou quand le mois est le dernier du trimestre ;
/// - le bulletin annuel, quand ce trimestre est le dernier de l'année.
///
/// Chaque élève a son fichier PDF, rangé dans
/// `Documents\GESCO\Bulletins\<année>\<classe>\<période>\`, avec en plus un
/// fichier `00_Classe_entiere.pdf` qui regroupe toute la classe pour
/// l'impression. Les fichiers déjà présents sont remplacés par la version à
/// jour. La génération attend quelques secondes après la dernière saisie pour
/// ne pas recommencer à chaque case remplie.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/changements_notes.dart';
import '../data/erreurs.dart';
import '../data/modeles_donnees.dart';
import '../documents/modele_bulletin.dart';
import '../documents/ouvrir_document.dart';
import '../documents/pdf_bulletin.dart';
import '../documents/polices_pdf.dart';
import '../documents/styles_bulletin.dart';
import '../domain/calendrier.dart';
import '../domain/modeles.dart';
import '../domain/periodes.dart';
import 'calcul_classe.dart';
import 'construire_bulletins.dart';
import 'services.dart';

/// Libellé d'une portée dans le calendrier d'une classe : « Novembre »,
/// « Trimestre 1 », « Année entière ».
String libellePortee(Portee portee) {
  if (portee.annuelle) return 'Année entière';
  final periode = portee.periodeChoisie;
  if (periode != null) return periode.libelle;
  return libelleMois(portee.moisChoisi!);
}

/// Type de bulletin correspondant à une portée.
TypeBulletin typeDeBulletin(Portee portee) {
  if (portee.annuelle) return TypeBulletin.annuel;
  if (portee.estMois) return TypeBulletin.mensuel;
  return TypeBulletin.periodique;
}

/// Nom du dossier d'une portée : `Mensuel_Novembre`, `Trimestre_1`, `Annuel`.
String nomDossierPortee(Portee portee) {
  if (portee.annuelle) return 'Annuel';
  if (portee.estMois) return 'Mensuel_${nomDeFichierSur(libellePortee(portee))}';
  return nomDeFichierSur(libellePortee(portee));
}

/// Dernier mois d'une période, dans l'ordre de l'année scolaire.
int dernierMoisDe(PeriodeScolaire periode) => periode.mois.reduce(
      (a, b) => moisScolaires.indexOf(a) >= moisScolaires.indexOf(b) ? a : b,
    );

/// Bulletins à produire quand les notes d'un mois changent.
///
/// Toujours le bulletin du mois. Le bulletin du trimestre s'y ajoute pour une
/// composition ou un examen, ou quand c'est le dernier mois du trimestre ; le
/// bulletin annuel s'y ajoute quand ce trimestre est le dernier de l'année.
List<Portee> porteesPourChangement(Calendrier calendrier, ChangementNotes changement) {
  final portees = <Portee>[Portee.mois(changement.mois)];
  final periode = calendrier.periodeDuMois(changement.mois);
  if (periode == null) return portees;
  final finDePeriode = dernierMoisDe(periode) == changement.mois;
  if (changement.composition || finDePeriode) {
    portees.add(Portee.periode(periode));
    if (calendrier.periodes.isNotEmpty && calendrier.periodes.last.cle == periode.cle) {
      portees.add(const Portee.annee());
    }
  }
  return portees;
}

/// Résultat d'une génération de bulletins.
class RapportBulletins {
  RapportBulletins({DateTime? date, this.automatique = false}) : date = date ?? DateTime.now();

  final DateTime date;

  /// Vrai quand la génération a été déclenchée par une saisie de notes, faux
  /// quand l'utilisateur l'a demandée (« Tout générer »).
  final bool automatique;

  /// Une ligne par classe et période produite : « Tle SM · Trimestre 1 : 32 bulletins ».
  final List<String> descriptions = [];

  /// Problèmes rencontrés (fichier ouvert ailleurs, disque plein...).
  final List<String> erreurs = [];

  /// Classes sans rien à produire (aucun élève actif, période absente).
  final List<String> ignorees = [];

  int bulletins = 0;
  int fichiers = 0;

  /// Dossier du dernier groupe de bulletins produit.
  String? dossier;

  bool get ok => erreurs.isEmpty;
  bool get vide => descriptions.isEmpty && erreurs.isEmpty;

  void ajouter(RapportBulletins autre) {
    descriptions.addAll(autre.descriptions);
    erreurs.addAll(autre.erreurs);
    ignorees.addAll(autre.ignorees);
    bulletins += autre.bulletins;
    fichiers += autre.fichiers;
    dossier = autre.dossier ?? dossier;
  }

  String get resume {
    final b = bulletins;
    final base = '$b bulletin${b > 1 ? 's' : ''} individuel${b > 1 ? 's' : ''} '
        '(${descriptions.length} classe${descriptions.length > 1 ? 's' : ''}/période${descriptions.length > 1 ? 's' : ''})';
    if (erreurs.isEmpty) return base;
    return '$base, ${erreurs.length} erreur${erreurs.length > 1 ? 's' : ''}';
  }
}

/// Écoute les saisies de notes et régénère les bulletins.
class BulletinsAuto extends ChangeNotifier {
  BulletinsAuto({
    required this.services,
    required this.dossierRacine,
    required this.chargerPolices,
    this.delai = const Duration(seconds: 3),
    DateTime Function()? maintenant,
  }) : _maintenant = maintenant ?? DateTime.now;

  final Services services;

  /// Dossier de travail de GESCO (`Documents\GESCO`) ; les bulletins sont
  /// rangés dans son sous-dossier `Bulletins`.
  final Future<Directory> Function() dossierRacine;
  final Future<PolicesPdf> Function() chargerPolices;

  /// Attente après la dernière saisie avant de générer.
  final Duration delai;
  final DateTime Function() _maintenant;

  StreamSubscription<ChangementNotes>? _abonnement;
  Timer? _minuterie;
  final Map<(int, int), bool> _enAttente = {};
  Future<void>? _traitement;
  PolicesPdf? _polices;
  bool _fermee = false;

  /// Résultat de la dernière génération (automatique ou manuelle).
  RapportBulletins? dernierRapport;

  /// Vrai pendant qu'une génération est en cours.
  bool enCours = false;

  /// Dossier racine des bulletins : `Documents\GESCO\Bulletins`.
  Future<Directory> dossierBulletins() async =>
      Directory(p.join((await dossierRacine()).path, 'Bulletins'));

  /// Commence à écouter les saisies de notes.
  void demarrer() {
    _abonnement ??= services.notifications.flux.listen(_recevoir);
  }

  Future<bool> estActif() => services.parametres.bulletinsAutomatiques();

  Future<void> definirActif(bool actif) =>
      services.parametres.definirBulletinsAutomatiques(actif);

  void _recevoir(ChangementNotes c) {
    final cle = (c.classeId, c.mois);
    _enAttente[cle] = (_enAttente[cle] ?? false) || c.composition;
    _minuterie?.cancel();
    _minuterie = Timer(delai, _declencher);
  }

  void _declencher() {
    _minuterie = null;
    if (_fermee) return;
    if (_traitement != null) {
      // Une génération est en cours : on repart quand elle sera finie.
      _minuterie = Timer(delai, _declencher);
      return;
    }
    _traitement = _traiterEnAttente().whenComplete(() => _traitement = null);
  }

  Future<void> _traiterEnAttente() async {
    final lot = Map<(int, int), bool>.of(_enAttente);
    _enAttente.clear();
    if (lot.isEmpty) return;
    try {
      if (!await estActif()) return;
    } catch (_) {
      return;
    }
    final rapport = RapportBulletins(date: _maintenant(), automatique: true);
    enCours = true;
    notifyListeners();
    try {
      for (final entree in lot.entries) {
        try {
          rapport.ajouter(await genererPourChangement(
            ChangementNotes(entree.key.$1, entree.key.$2, composition: entree.value),
          ));
        } catch (e) {
          rapport.erreurs.add(_texteErreur(e));
        }
      }
    } finally {
      enCours = false;
      if (!rapport.vide) dernierRapport = rapport;
      if (!_fermee) notifyListeners();
    }
  }

  /// Termine tout ce qui est en attente sans attendre le délai (tests, arrêt
  /// de l'application).
  Future<void> vider() async {
    await Future<void>.delayed(Duration.zero);
    _minuterie?.cancel();
    _minuterie = null;
    while (_traitement != null || _enAttente.isNotEmpty) {
      final en = _traitement;
      if (en != null) {
        await en;
        continue;
      }
      _traitement = _traiterEnAttente().whenComplete(() => _traitement = null);
    }
  }

  /// Génère les bulletins prévus pour un changement de notes (voir
  /// [porteesPourChangement]) : un PDF par élève actif, plus le fichier de
  /// la classe entière.
  Future<RapportBulletins> genererPourChangement(ChangementNotes changement) async {
    final rapport = RapportBulletins(date: _maintenant());
    final classe = await services.classes.obtenir(changement.classeId);
    if (classe == null) return rapport; // classe supprimée entre-temps
    final contexte = await _Contexte.charger(this, classe.anneeId);
    final resume = contexte.classes.where((c) => c.classe.id == classe.id).firstOrNull;
    if (resume == null) return rapport;
    final calendrier = contexte.calendriers.pour(classe.cycle);
    final calcul = await chargerCalculClasse(
      services,
      resume,
      config: contexte.config,
      calendrier: calendrier,
    );
    for (final portee in porteesPourChangement(calendrier, changement)) {
      await _produire(calcul, portee, contexte, rapport);
    }
    return rapport;
  }

  /// Génère, pour toutes les classes de l'année, les bulletins d'une période
  /// choisie par sa clé (`m11`, `t1`, `annee`...). Une classe dont le
  /// calendrier n'a pas cette période est signalée et ignorée : le primaire a
  /// trois trimestres, le collège et le lycée deux.
  Future<RapportBulletins> genererTout(int anneeId, String cle) async {
    final rapport = RapportBulletins(date: _maintenant());
    enCours = true;
    notifyListeners();
    try {
      final contexte = await _Contexte.charger(this, anneeId);
      for (final resume in contexte.classes) {
        final calendrier = contexte.calendriers.pour(resume.classe.cycle);
        final portee = calendrier.portee(cle);
        if (portee == null) {
          rapport.ignorees.add('${resume.classe.nom} : pas de période « $cle » dans son calendrier');
          continue;
        }
        final calcul = await chargerCalculClasse(
          services,
          resume,
          config: contexte.config,
          calendrier: calendrier,
        );
        await _produire(calcul, portee, contexte, rapport);
      }
    } catch (e) {
      rapport.erreurs.add(_texteErreur(e));
    } finally {
      enCours = false;
      dernierRapport = rapport;
      if (!_fermee) notifyListeners();
    }
    return rapport;
  }

  Future<void> _produire(
    CalculClasse calcul,
    Portee portee,
    _Contexte ctx,
    RapportBulletins rapport,
  ) async {
    final classe = calcul.classe.classe;
    final libelle = libellePortee(portee);
    final actifs = [for (final e in calcul.eleves) if (e.actif) e];
    if (actifs.isEmpty) {
      rapport.ignorees.add('${classe.nom} : aucun élève actif');
      return;
    }
    final cle = portee.cle;
    final avis = await services.appreciations.eleves(classe.id, cle);
    final avisMatieres = await services.appreciations.matieres(classe.id, cle);
    final appreciationsAuto = await services.parametres.appreciationsAutomatiques();
    final fiches = <int, Eleve>{};
    for (final e in actifs) {
      final fiche = await services.eleves.obtenir(e.eleveId);
      if (fiche != null) fiches[e.eleveId] = fiche;
    }
    final bulletins = construireBulletins(
      calcul: calcul,
      portee: portee,
      periodeLibelle: libelle,
      type: typeDeBulletin(portee),
      etablissement: ctx.etablissement,
      anneeLibelle: ctx.anneeLibelle,
      appreciations: avis,
      appreciationsMatieres: avisMatieres,
      appreciationsAuto: appreciationsAuto,
      fiches: fiches,
      dateEdition: _maintenant(),
    );
    final dossier = Directory(p.join(
      ctx.racine.path,
      nomDeFichierSur(ctx.anneeLibelle),
      nomDeFichierSur(classe.nom),
      nomDossierPortee(portee),
    ));
    final polices = _polices ??= await chargerPolices();
    final avant = rapport.erreurs.length;

    Future<void> ecrire(String nomFichier, List<Bulletin> liste, String sujet) async {
      try {
        final doc = await genererBulletinsPdf(liste, style: ctx.style, polices: polices);
        await ecrireEnRemplacant(File(p.join(dossier.path, nomFichier)), doc.octets);
        rapport.fichiers++;
      } catch (e) {
        rapport.erreurs.add('${classe.nom} · $libelle · $sujet : ${_texteErreur(e)}');
      }
      // Laisse l'interface respirer entre deux PDF.
      await Future<void>.delayed(Duration.zero);
    }

    for (final b in bulletins) {
      await ecrire(
        '${nomDeFichierSur('${b.nomComplet} ${b.matricule}')}.pdf',
        [b],
        b.nomComplet,
      );
    }
    await ecrire('00_Classe_entiere.pdf', bulletins, 'classe entière');

    if (rapport.erreurs.length == avant) {
      rapport.bulletins += bulletins.length;
      rapport.descriptions.add(
        '${classe.nom} · $libelle : ${bulletins.length} bulletin${bulletins.length > 1 ? 's' : ''}',
      );
      rapport.dossier = dossier.path;
    }
  }

  static String _texteErreur(Object e) => e is ErreurGesco ? e.message : '$e';

  /// Arrête l'écoute sans libérer l'objet (avant de fermer la base, par
  /// exemple pendant une restauration).
  void arreter() {
    _fermee = true;
    _minuterie?.cancel();
    _abonnement?.cancel();
    _abonnement = null;
  }

  /// Arrête l'écoute (fermeture de l'application, tests).
  @override
  void dispose() {
    arreter();
    super.dispose();
  }
}

/// Données communes à toutes les classes d'une génération, lues une fois.
class _Contexte {
  _Contexte({
    required this.anneeLibelle,
    required this.etablissement,
    required this.config,
    required this.calendriers,
    required this.classes,
    required this.style,
    required this.racine,
  });

  final String anneeLibelle;
  final Etablissement etablissement;
  final ConfigResultats config;
  final CalendriersAnnee calendriers;
  final List<ClasseResume> classes;
  final StyleBulletin style;
  final Directory racine;

  static Future<_Contexte> charger(BulletinsAuto auto, int anneeId) async {
    final s = auto.services;
    final annee = await s.annees.obtenir(anneeId);
    return _Contexte(
      anneeLibelle: annee?.libelle ?? '',
      etablissement: await s.etablissements.lire(),
      config: await s.configs.lire(anneeId),
      calendriers: await s.calendriers.lireTous(anneeId),
      classes: await s.classes.lister(anneeId),
      style: StyleBulletin.parId(await s.parametres.styleDocuments()),
      racine: await auto.dossierBulletins(),
    );
  }
}
