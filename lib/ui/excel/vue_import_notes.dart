import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/erreurs.dart';
import '../../data/modeles_donnees.dart';
import '../../data/modeles_notation.dart';
import '../../documents/ouvrir_document.dart';
import '../../domain/bareme.dart';
import '../../domain/calendrier.dart';
import '../../domain/permissions.dart';
import '../../domain/periodes.dart';
import '../../domain/saisie_note.dart';
import '../../import_export/import_notes.dart';
import '../../import_export/lecture_tableur.dart';
import '../../import_export/service_export.dart';
import '../../import_export/service_import_eleves.dart';
import '../../import_export/service_import_notes.dart';
import '../../tableur/classeur.dart';
import '../commun/choix.dart';
import '../commun/composants.dart';
import '../theme.dart';
import 'donnees_excel.dart';
import 'resultat_fichiers.dart';
import 'vue_import_eleves.dart';

enum _Filtre {
  tout('Toutes'),
  aImporter('À importer'),
  remarques('Avec remarque'),
  sansNote('Sans note'),
  erreurs('En erreur');

  const _Filtre(this.libelle);

  final String libelle;
}

/// Nombre de lignes affichées à l'écran (le rapport Excel les contient toutes).
const int _lignesAffichees = 200;

/// Valeur de la liste « évaluation visée » pour une évaluation à créer.
const int _nouvelleEvaluation = -1;

/// Coefficients proposés pour une évaluation créée par l'import (centièmes).
const List<int> _coefficientsUsuels = [50, 100, 150, 200, 300];

String _n(int n, String un, String plusieurs) => '$n ${n > 1 ? plusieurs : un}';

String _notes(int n) => _n(n, 'note', 'notes');

String _coefTexte(int centiemes) => centiemes % 100 == 0
    ? '${centiemes ~/ 100}'
    : (centiemes / 100).toString().replaceAll('.', ',');

/// Import des notes depuis un fichier Excel : on choisit la classe, la
/// matière et le trimestre, puis le fichier ; il est vérifié case par case
/// avec un aperçu, et rien n'est enregistré avant la confirmation.
class VueImportNotes extends StatefulWidget {
  const VueImportNotes({
    super.key,
    required this.etat,
    required this.donnees,
    required this.ouvreur,
    this.dossier,
    this.maintenant,
    this.selecteur = choisirFichierExcel,
  });

  final EtatApp etat;
  final DonneesExcel donnees;
  final Ouvreur ouvreur;
  final Directory? dossier;
  final DateTime Function()? maintenant;
  final SelecteurFichier selecteur;

  @override
  State<VueImportNotes> createState() => _VueImportNotesState();
}

class _VueImportNotesState extends State<VueImportNotes> {
  late final ServiceImportNotes _service =
      ServiceImportNotes(widget.etat.services, maintenant: widget.maintenant);

  // Choix de l'utilisateur
  int? _classeId;
  int? _matiereId;
  String? _periodeCle;
  bool _remplacer = false;
  bool _ignorer = false;

  // Fichier choisi et association
  String? _nomFichier;
  ClasseurLu? _classeur;
  List<FeuilleImport> _feuilles = const [];
  int _feuille = 0;
  int _indexEntete = 0;
  bool _listeGesco = false;
  List<String> _problemesGesco = const [];
  List<String> _remarquesGesco = const [];
  TableLue? _table;
  int? _colMatricule;
  int? _colNom;
  int? _colPrenom;
  Map<int, CibleColonne> _cibles = const {};
  Map<int, int?> _annonces = const {};
  ContexteImportNotes? _ctx;

  // Résultats
  RapportImportNotes? _rapport;
  BilanImportNotes? _resultat;
  ProduitExcel? _produit;
  String _dossierProduit = '';
  _Filtre _filtre = _Filtre.tout;
  bool _occupe = false;

  // ---------------------------------------------------------- Sélection

  DateTime _maintenant() => (widget.maintenant ?? DateTime.now)();

  Classe? get _classe {
    for (final c in widget.donnees.classes) {
      if (c.classe.id == _classeId) return c.classe;
    }
    return null;
  }

  List<MatiereClasse> get _matieres => widget.donnees.matieres[_classeId] ?? const [];

  MatiereClasse? get _matiere {
    for (final m in _matieres) {
      if (m.id == _matiereId) return m;
    }
    return null;
  }

  List<PeriodeScolaire> get _periodes => widget.donnees.periodesClasse[_classeId] ?? const [];

  PeriodeScolaire? get _periode {
    for (final p in _periodes) {
      if (p.cle == _periodeCle) return p;
    }
    return null;
  }

  /// Période qui contient le mois en cours, à défaut la première.
  String? _periodeParDefaut(int? classeId) {
    final liste = widget.donnees.periodesClasse[classeId] ?? const <PeriodeScolaire>[];
    if (liste.isEmpty) return null;
    final mois = moisParDefaut(_maintenant());
    for (final p in liste) {
      if (p.mois.contains(mois)) return p.cle;
    }
    return liste.first.cle;
  }

  /// Mois proposé aux évaluations créées par l'import.
  int _moisNouvelles() {
    final p = _periode;
    if (p == null || p.mois.isEmpty) return moisScolaires.first;
    final m = moisParDefaut(_maintenant());
    return p.mois.contains(m) ? m : p.mois.first;
  }

  bool get _selectionComplete => _classe != null && _matiere != null && _periode != null;

  // ------------------------------------------------------------- Actions

  /// Exécute [action] en bloquant les boutons ; toute erreur est expliquée.
  Future<void> _executer(Future<void> Function() action) async {
    if (_occupe) return;
    setState(() => _occupe = true);
    String? erreur;
    try {
      await action();
    } on ErreurGesco catch (e) {
      erreur = e.message;
    } catch (e) {
      erreur = 'Erreur inattendue : $e';
    }
    if (!mounted) return;
    setState(() => _occupe = false);
    if (erreur != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erreur), backgroundColor: CouleursGesco.rouge),
      );
    }
  }

  /// Oublie le fichier, l'association et le rapport. Le bilan du dernier
  /// import est gardé si [garderResultat].
  void _reinitialiser({bool garderResultat = false}) {
    _nomFichier = null;
    _classeur = null;
    _feuilles = const [];
    _feuille = 0;
    _indexEntete = 0;
    _listeGesco = false;
    _problemesGesco = const [];
    _remarquesGesco = const [];
    _table = null;
    _colMatricule = null;
    _colNom = null;
    _colPrenom = null;
    _cibles = const {};
    _annonces = const {};
    _ctx = null;
    _rapport = null;
    if (!garderResultat) _resultat = null;
  }

  void _appliquerAssociation(MappingNotes m) {
    _colMatricule = m.colonneMatricule;
    _colNom = m.colonneNom;
    _colPrenom = m.colonnePrenom;
    _cibles = {...m.colonnes};
    _annonces = {for (final e in m.colonnes.entries) e.key: e.value.baremeAnnonce};
  }

  /// Relit le tableau de la feuille choisie (autre fichier qu'une liste GESCO).
  void _chargerTable() {
    final f = _classeur!.feuilles[_feuille];
    final t = lireTable(f, indexEntete: _indexEntete);
    _table = t;
    _appliquerAssociation(
      proposerAssociationNotes(table: t, ctx: _ctx!, moisParDefaut: _moisNouvelles()),
    );
    _rapport = null;
    _resultat = null;
  }

  MappingNotes get _mapping => MappingNotes(
        colonneMatricule: _colMatricule,
        colonneNom: _colNom,
        colonnePrenom: _colPrenom,
        colonnes: _cibles,
      );

  Future<ContexteImportNotes> _lireContexte() async {
    final anneeId = widget.etat.anneeId;
    final classe = _classe;
    final matiere = _matiere;
    final periode = _periode;
    if (anneeId == null || classe == null || matiere == null || periode == null) {
      throw const ErreurGesco('Choisissez la classe, la matière et la période.');
    }
    return _service.contexte(
      anneeId: anneeId,
      classe: classe,
      matiere: matiere,
      periode: periode,
      remplacerExistantes: _remplacer,
    );
  }

  Future<void> _choisir() => _executer(() async {
        if (!_selectionComplete) return;
        final choisi = await widget.selecteur();
        if (choisi == null) return;
        final classeur = _service.ouvrir(choisi.octets);
        if (classeur.feuilles.isEmpty) {
          throw const ErreurGesco('Le classeur ne contient aucune feuille.');
        }
        final ctx = await _lireContexte();
        final feuilles = _service.feuilles(classeur);
        final proposition = _service.reconnaitreListeGesco(classeur, ctx);
        if (!mounted) return;
        setState(() {
          _reinitialiser();
          _nomFichier = choisi.nom;
          _classeur = classeur;
          _feuilles = feuilles;
          _ctx = ctx;
          if (proposition != null && proposition.utilisable) {
            _listeGesco = true;
            _remarquesGesco = proposition.remarques;
            _table = proposition.table;
            _appliquerAssociation(proposition.mapping!);
          } else {
            if (proposition != null) _problemesGesco = proposition.problemes;
            final proposee = _service.feuilleProposee(classeur);
            _feuille = proposee;
            _indexEntete = feuilles[proposee].indexEntete ?? 0;
            _chargerTable();
          }
        });
      });

  Future<void> _verifier() => _executer(() async {
        final table = _table;
        if (table == null) return;
        final ctx = await _lireContexte();
        final rapport = analyserImportNotes(table: table, mapping: _mapping, ctx: ctx);
        if (!mounted) return;
        setState(() {
          _ctx = ctx;
          _rapport = rapport;
          _resultat = null;
          _filtre = _Filtre.tout;
        });
      });

  Future<void> _confirmer(RapportImportNotes rapport) async {
    final classe = _classe;
    final matiere = _matiere;
    final periode = _periode;
    if (classe == null || matiere == null || periode == null) return;
    final creees = [for (final c in rapport.plan) if (c.creer) c.titre];
    final remplacees = rapport.nbNotesRemplacees;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Importer ${_notes(rapport.nbNotesAEcrire)} ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${classe.nom} · ${matiere.nom} · ${periode.libelle}'),
            if (creees.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_n(creees.length, 'évaluation sera créée', 'évaluations seront créées')} : '
                '${creees.join(', ')}.',
                key: const Key('notes_import_confirmer_creees'),
              ),
            ],
            if (remplacees > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${_n(remplacees, 'note déjà enregistrée sera remplacée', 'notes déjà enregistrées seront remplacées')} '
                'par la valeur du fichier. Les anciennes valeurs restent consultables dans '
                'l\'historique des notes.',
                key: const Key('notes_import_confirmer_remplace'),
                style: const TextStyle(color: CouleursGesco.orange, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'L\'import est fait en une seule fois : si une note pose problème, rien n\'est '
              'enregistré.',
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('notes_import_confirmer_non'),
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('notes_import_confirmer_oui'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Importer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _executer(() async {
      final bilan = await _service.importer(
        rapport,
        classe: classe,
        matiere: matiere,
        ignorerErreurs: _ignorer,
      );
      widget.etat.donneesModifiees();
      if (!mounted) return;
      // Le fichier est oublié : le réimporter par erreur ne doit pas être
      // l'affaire d'un simple clic sur « Importer ».
      setState(() {
        _reinitialiser(garderResultat: true);
        _resultat = bilan;
      });
    });
  }

  Future<void> _enregistrerRapport(RapportImportNotes rapport) => _executer(() async {
        final ctx = _ctx;
        if (ctx == null) return;
        final dossier = widget.dossier ?? await dossierDocuments();
        final f = await _service.enregistrerRapport(
          rapport,
          ctx: ctx,
          nomFichier: _nomFichier ?? '',
          dossier: dossier,
        );
        final ouvert = await widget.ouvreur(f.fichier.path);
        if (!mounted) return;
        setState(() {
          _dossierProduit = dossier.path;
          _produit = ProduitExcel(
            titre: 'Rapport créé.',
            chemins: [f.fichier.path],
            ouvert: ouvert,
          );
        });
      });

  /// Une modification de l'association rend le rapport périmé.
  void _modifie(VoidCallback f) => setState(() {
        f();
        _rapport = null;
        _resultat = null;
      });

  // --------------------------------------------------------------- Écran

  @override
  Widget build(BuildContext context) {
    final etat = widget.etat;
    final annee = etat.anneeCourante;
    final peutNotes = etat.peut(Permission.notesSaisir);
    final archivee = annee?.archivee ?? false;
    final peutChoisir = peutNotes && !archivee && !_occupe && _selectionComplete;
    final rapport = _rapport;

    return Column(
      key: const Key('vue_import_notes'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Carte(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Importez les notes d\'une matière depuis un fichier Excel : la liste remplie '
                'par l\'enseignant (créée dans « Listes pour les enseignants ») ou un autre '
                'tableau avec le matricule ou le nom des élèves. Chaque case est vérifiée '
                'avant tout enregistrement : vous voyez le résultat, puis vous confirmez. '
                'Une note déjà enregistrée n\'est jamais écrasée sans votre accord.',
                key: Key('notes_import_intro'),
                style: TextStyle(color: CouleursGesco.gris),
              ),
              if (!peutNotes || archivee) ...[
                const SizedBox(height: 10),
                Text(
                  !peutNotes
                      ? 'Votre compte n\'a pas le droit de saisir des notes : l\'import est désactivé.'
                      : 'L\'année scolaire ${annee?.libelle ?? ''} est archivée : elle n\'est plus modifiable.',
                  key: const Key('notes_import_refus'),
                  style: const TextStyle(color: CouleursGesco.rouge),
                ),
              ],
              const SizedBox(height: 14),
              _selection(),
              SwitchListTile(
                key: const Key('notes_import_remplacer'),
                contentPadding: EdgeInsets.zero,
                value: _remplacer,
                title: const Text('Remplacer les notes déjà enregistrées'),
                subtitle: const Text(
                  'Si le fichier donne une autre note pour un élève, elle remplace l\'ancienne. '
                  'Sinon, l\'ancienne note est conservée.',
                ),
                onChanged: (v) => _modifie(() => _remplacer = v),
              ),
              SwitchListTile(
                key: const Key('notes_import_ignorer'),
                contentPadding: EdgeInsets.zero,
                value: _ignorer,
                title: const Text('Ignorer les lignes en erreur et importer les autres'),
                subtitle: const Text(
                  'Une ligne en erreur n\'est jamais importée à moitié. Sinon, l\'import est '
                  'refusé tant qu\'une ligne est en erreur.',
                ),
                onChanged: (v) => setState(() => _ignorer = v),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('notes_import_choisir'),
                onPressed: peutChoisir ? _choisir : null,
                icon: const Icon(Icons.upload_file, size: 18),
                label: Text(_classeur == null ? 'Choisir un fichier Excel' : 'Choisir un autre fichier'),
              ),
              if (_occupe) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(key: Key('notes_import_occupe')),
              ],
            ],
          ),
        ),
        if (_produit != null) ...[
          const SizedBox(height: 12),
          CarteProduit(produit: _produit!, ouvrir: widget.ouvreur, dossier: _dossierProduit),
        ],
        if (_resultat != null) ...[
          const SizedBox(height: 12),
          _carteResultat(_resultat!),
        ],
        if (_table != null) ...[
          const SizedBox(height: 12),
          _carteAssociation(_table!),
        ],
        if (rapport != null) ...[
          const SizedBox(height: 12),
          _carteRapport(rapport),
        ],
      ],
    );
  }

  Widget _selection() {
    final d = widget.donnees;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 230,
          child: ChoixListe<int?>(
            cleChamp: const Key('notes_import_classe'),
            libelle: 'Classe',
            valeur: _classe?.id,
            options: [
              (null, 'Choisir la classe'),
              for (final c in d.classes) (c.classe.id, c.classe.nom),
            ],
            onChanged: _occupe
                ? null
                : (v) => setState(() {
                      _reinitialiser();
                      _classeId = v;
                      _matiereId = null;
                      _periodeCle = _periodeParDefaut(v);
                    }),
          ),
        ),
        SizedBox(
          width: 230,
          child: ChoixListe<int?>(
            cleChamp: const Key('notes_import_matiere'),
            libelle: 'Matière',
            valeur: _matiere?.id,
            options: [
              (null, 'Choisir la matière'),
              for (final m in _matieres) (m.id, m.nom),
            ],
            onChanged: (_occupe || _classe == null)
                ? null
                : (v) => setState(() {
                      _reinitialiser();
                      _matiereId = v;
                    }),
          ),
        ),
        SizedBox(
          width: 230,
          child: ChoixListe<String?>(
            cleChamp: const Key('notes_import_periode'),
            libelle: 'Période',
            valeur: _periode?.cle,
            options: [
              if (_periode == null) (null, 'Choisir la période'),
              for (final p in _periodes) (p.cle, p.libelle),
            ],
            onChanged: (_occupe || _classe == null)
                ? null
                : (v) => setState(() {
                      _reinitialiser();
                      _periodeCle = v;
                    }),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ Résultat

  Widget _carteResultat(BilanImportNotes b) {
    const gris = TextStyle(color: CouleursGesco.gris);
    return Carte(
      key: const Key('notes_import_resultat'),
      padding: const EdgeInsets.all(16),
      couleur: CouleursGesco.vertClair,
      bordure: CouleursGesco.vert,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: CouleursGesco.vert),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_notes(b.nbNotes)} importée${b.nbNotes > 1 ? 's' : ''} et '
                  'retrouvée${b.nbVerifiees > 1 ? 's' : ''} dans la base.',
                  key: const Key('notes_import_resultat_titre'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (b.nbEvaluationsCreees > 0) ...[
            const SizedBox(height: 6),
            Text(
              _n(b.nbEvaluationsCreees, 'évaluation créée', 'évaluations créées'),
              style: gris,
            ),
          ],
          if (b.nbRemplacees > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${_n(b.nbRemplacees, 'note a remplacé', 'notes ont remplacé')} une note '
              'enregistrée avant (l\'historique des notes garde l\'ancienne valeur).',
              style: gris,
            ),
          ],
          if (b.nbIdentiques > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${_n(b.nbIdentiques, 'note du fichier était', 'notes du fichier étaient')} '
              'déjà identique${b.nbIdentiques > 1 ? 's' : ''} à GESCO : rien n\'a été modifié.',
              style: gris,
            ),
          ],
          if (b.nbConservees > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${_n(b.nbConservees, 'note du fichier différait', 'notes du fichier différaient')} '
              'de celle de GESCO : l\'ancienne a été conservée.',
              style: gris,
            ),
          ],
          if (b.nbLignesEnErreur > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${_n(b.nbLignesEnErreur, 'ligne en erreur ignorée', 'lignes en erreur ignorées')} : '
              'à corriger dans le fichier puis à importer de nouveau.',
              style: gris,
            ),
          ],
          if (b.nbLignesSansNote > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${_n(b.nbLignesSansNote, 'élève du fichier n\'a', 'élèves du fichier n\'ont')} '
              'aucune note remise.',
              style: gris,
            ),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------------- Association

  Widget _choixFeuilleEtEntete() {
    final nbLignesFeuille = _classeur!.feuilles[_feuille].nbLignes;
    final maxEntete = nbLignesFeuille < 15 ? nbLignesFeuille : 15;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_feuilles.length > 1)
          SizedBox(
            width: 240,
            child: ChoixListe<int>(
              cleChamp: const Key('notes_import_feuille'),
              libelle: 'Feuille du classeur',
              valeur: _feuille,
              options: [for (final f in _feuilles) (f.indice, f.nom)],
              onChanged: (v) => setState(() {
                if (v == null) return;
                _feuille = v;
                _indexEntete = _feuilles[v].indexEntete ?? 0;
                _chargerTable();
              }),
            ),
          ),
        if (maxEntete > 1)
          SizedBox(
            width: 200,
            child: ChoixListe<int>(
              cleChamp: const Key('notes_import_ligne_entete'),
              libelle: 'Ligne des titres',
              valeur: _indexEntete < maxEntete ? _indexEntete : 0,
              options: [for (var i = 0; i < maxEntete; i++) (i, 'Ligne ${i + 1}')],
              onChanged: (v) => setState(() {
                if (v == null) return;
                _indexEntete = v;
                _chargerTable();
              }),
            ),
          ),
      ],
    );
  }

  /// Colonnes proposées pour une liste : celles qui ont un titre ou des
  /// valeurs, et celle qui est déjà choisie.
  List<(int?, String)> _optionsColonnes(TableLue t, int? courante) => [
        (null, 'Aucune'),
        for (var i = 0; i < t.nbColonnes; i++)
          if (t.entetes[i].isNotEmpty || t.exemples(i).isNotEmpty || i == courante)
            (i, '${TableLue.lettre(i)}  ·  ${t.titreColonne(i)}'),
      ];

  /// Choisit une colonne d'identité : elle ne peut plus être une colonne de notes.
  void _choisirIdentite(void Function(int?) affecter, int? v) => _modifie(() {
        affecter(v);
        if (v != null && _cibles.containsKey(v)) {
          _cibles = {..._cibles}..remove(v);
        }
      });

  Widget _carteAssociation(TableLue t) {
    final colMatricule = _colMatricule;
    final colNom = _colNom;
    final colPrenom = _colPrenom;
    final identite = <int>{
      if (colMatricule != null) colMatricule,
      if (colNom != null) colNom,
      if (colPrenom != null) colPrenom,
    };
    final colonnes = [
      for (var i = 0; i < t.nbColonnes; i++)
        if (!identite.contains(i) &&
            (t.entetes[i].isNotEmpty || t.exemples(i).isNotEmpty || _cibles.containsKey(i)))
          i,
    ];
    final ctx = _ctx;
    return Carte(
      key: const Key('notes_import_association'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fichier « ${_nomFichier ?? ''} »  ·  ${_n(t.lignes.length, 'ligne', 'lignes')} '
            'sous les titres',
            key: const Key('notes_import_fichier'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final (k, m) in _remarquesGesco.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                m,
                key: Key('notes_import_gesco_reconnue_$k'),
                style: const TextStyle(color: CouleursGesco.vert, fontWeight: FontWeight.w600),
              ),
            ),
          for (final (k, p) in _problemesGesco.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                p,
                key: Key('notes_import_gesco_probleme_$k'),
                style: const TextStyle(color: CouleursGesco.rouge),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            _listeGesco
                ? 'Les colonnes ont été associées d\'après la liste GESCO. Vous pouvez les '
                    'corriger ci-dessous avant la vérification.'
                : 'Indiquez les colonnes du matricule et du nom des élèves, puis, pour chaque '
                    'colonne de notes, l\'évaluation à laquelle elle correspond. Les colonnes '
                    'reconnues sont déjà associées.',
            style: const TextStyle(color: CouleursGesco.gris),
          ),
          if (!_listeGesco) ...[
            const SizedBox(height: 12),
            _choixFeuilleEtEntete(),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 240,
                child: ChoixListe<int?>(
                  cleChamp: const Key('notes_import_col_matricule'),
                  libelle: 'Colonne du matricule',
                  valeur: _colMatricule,
                  options: _optionsColonnes(t, _colMatricule),
                  onChanged: (v) => _choisirIdentite((x) => _colMatricule = x, v),
                ),
              ),
              SizedBox(
                width: 240,
                child: ChoixListe<int?>(
                  cleChamp: const Key('notes_import_col_nom'),
                  libelle: 'Colonne du nom (ou nom et prénom)',
                  valeur: _colNom,
                  options: _optionsColonnes(t, _colNom),
                  onChanged: (v) => _choisirIdentite((x) => _colNom = x, v),
                ),
              ),
              SizedBox(
                width: 240,
                child: ChoixListe<int?>(
                  cleChamp: const Key('notes_import_col_prenom'),
                  libelle: 'Colonne du prénom (si séparé)',
                  valeur: _colPrenom,
                  options: _optionsColonnes(t, _colPrenom),
                  onChanged: (v) => _choisirIdentite((x) => _colPrenom = x, v),
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          Text(
            colonnes.isEmpty
                ? 'Aucune autre colonne dans ce fichier.'
                : 'Colonnes du fichier',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (ctx != null)
            for (final i in colonnes) _ligneColonne(t, i, ctx),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('notes_import_verifier'),
            onPressed: _occupe ? null : _verifier,
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Vérifier le fichier'),
          ),
        ],
      ),
    );
  }

  String _libelleEvaluation(Evaluation e) =>
      '${e.titre} · ${libelleMois(e.mois)} · sur ${e.bareme}${e.valide ? ' · validée' : ''}';

  List<(int?, String)> _optionsCible(ContexteImportNotes ctx, CibleColonne? cible) {
    final evaluations = [
      for (final e in ctx.evaluations)
        if (e.matiereId == ctx.matiereId && e.classeId == ctx.classeId) e,
    ];
    final options = <(int?, String)>[
      (null, 'Ne pas importer'),
      (_nouvelleEvaluation, 'Nouvelle évaluation'),
      for (final e in evaluations) (e.id, _libelleEvaluation(e)),
    ];
    final id = cible?.evaluationId;
    if (id != null && !evaluations.any((e) => e.id == id)) {
      options.add((id, 'Évaluation n° $id (introuvable)'));
    }
    return options;
  }

  /// Change l'évaluation visée par la colonne [i].
  void _viser(int i, int? v, ContexteImportNotes ctx, TableLue t) => _modifie(() {
        if (v == null) {
          _cibles = {..._cibles}..remove(i);
          return;
        }
        if (v == _nouvelleEvaluation) {
          final separe = separerBaremeDuTitre(t.titreColonne(i));
          final titre = separe.titre.startsWith('Colonne ') ? '' : separe.titre;
          _cibles = {
            ..._cibles,
            i: CibleColonne(
              titre: titre,
              type: typeDepuisTitre(titre),
              mois: _moisNouvelles(),
              bareme: separe.bareme ?? ctx.matiereBareme,
              baremeAnnonce: _annonces[i] ?? separe.bareme,
            ),
          };
          return;
        }
        final e = ctx.evaluations.firstWhere((e) => e.id == v);
        _cibles = {
          ..._cibles,
          i: CibleColonne(
            evaluationId: e.id,
            titre: e.titre,
            type: e.type,
            mois: e.mois,
            bareme: e.bareme,
            coefficient: e.coefficient,
            baremeAnnonce: _annonces[i] ?? separerBaremeDuTitre(t.titreColonne(i)).bareme,
          ),
        };
      });

  List<(int, String)> _optionsMois(int courant) {
    final mois = _periode?.mois ?? const <int>[];
    return [
      for (final m in mois) (m, libelleMois(m)),
      if (!mois.contains(courant)) (courant, '${libelleMois(courant)} (hors de la période)'),
    ];
  }

  List<(int, String)> _optionsBareme(int courant) => [
        for (final b in baremesUsuels) (b, 'Sur $b'),
        if (!baremesUsuels.contains(courant)) (courant, 'Sur $courant'),
      ];

  List<(int, String)> _optionsCoefficient(int courant) => [
        for (final c in _coefficientsUsuels) (c, 'Coefficient ${_coefTexte(c)}'),
        if (!_coefficientsUsuels.contains(courant)) (courant, 'Coefficient ${_coefTexte(courant)}'),
      ];

  Widget _champsNouvelle(int i, CibleColonne c) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: 230,
            child: TextFormField(
              key: Key('notes_import_titre_$i'),
              initialValue: c.titre,
              decoration: champ('Titre de l\'évaluation'),
              onChanged: (v) => _modifie(() => _cibles = {..._cibles, i: c.copie(titre: v)}),
            ),
          ),
          SizedBox(
            width: 170,
            child: ChoixListe<TypeEvaluation>(
              cleChamp: Key('notes_import_type_$i'),
              libelle: 'Type',
              valeur: c.type,
              options: [for (final t in TypeEvaluation.values) (t, t.libelle)],
              onChanged: (v) {
                if (v == null) return;
                _modifie(() => _cibles = {..._cibles, i: c.copie(type: v)});
              },
            ),
          ),
          SizedBox(
            width: 170,
            child: ChoixListe<int>(
              cleChamp: Key('notes_import_mois_$i'),
              libelle: 'Mois',
              valeur: c.mois,
              options: _optionsMois(c.mois),
              onChanged: (v) {
                if (v == null) return;
                _modifie(() => _cibles = {..._cibles, i: c.copie(mois: v)});
              },
            ),
          ),
          SizedBox(
            width: 130,
            child: ChoixListe<int>(
              cleChamp: Key('notes_import_bareme_$i'),
              libelle: 'Barème',
              valeur: c.bareme,
              options: _optionsBareme(c.bareme),
              onChanged: (v) {
                if (v == null) return;
                _modifie(() => _cibles = {..._cibles, i: c.copie(bareme: v)});
              },
            ),
          ),
          SizedBox(
            width: 170,
            child: ChoixListe<int>(
              cleChamp: Key('notes_import_coef_$i'),
              libelle: 'Coefficient',
              valeur: c.coefficient,
              options: _optionsCoefficient(c.coefficient),
              onChanged: (v) {
                if (v == null) return;
                _modifie(() => _cibles = {..._cibles, i: c.copie(coefficient: v)});
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _ligneColonne(TableLue t, int i, ContexteImportNotes ctx) {
    final exemples = t.exemples(i);
    final cible = _cibles[i];
    final valeur = cible == null
        ? null
        : cible.nouvelle
            ? _nouvelleEvaluation
            : cible.evaluationId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${TableLue.lettre(i)}  ·  ${t.titreColonne(i)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (exemples.isNotEmpty)
                      Text(
                        'Ex. : ${exemples.join('  ·  ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: CouleursGesco.gris, fontSize: 12),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 300,
                child: ChoixListe<int?>(
                  cleChamp: Key('notes_import_cible_$i'),
                  libelle: 'Évaluation visée',
                  valeur: valeur,
                  options: _optionsCible(ctx, cible),
                  onChanged: (v) => _viser(i, v, ctx, t),
                ),
              ),
            ],
          ),
          if (cible != null && cible.nouvelle) _champsNouvelle(i, cible),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- Rapport

  bool _garde(LigneImportNotes l, _Filtre f) => switch (f) {
        _Filtre.tout => true,
        _Filtre.aImporter => !l.enErreur && l.nbAEcrire > 0,
        _Filtre.remarques => !l.enErreur && l.avertissements.isNotEmpty,
        _Filtre.sansNote => !l.enErreur && l.sansNote,
        _Filtre.erreurs => l.enErreur,
      };

  Widget _carteRapport(RapportImportNotes r) {
    final compte = {
      for (final f in _Filtre.values) f: r.lignes.where((l) => _garde(l, f)).length,
    };
    final visibles = [for (final l in r.lignes) if (_garde(l, _filtre)) l];
    final affichees = visibles.take(_lignesAffichees).toList();
    final peut = r.peutImporter(ignorerErreurs: _ignorer);
    final manqueDroitEvaluations =
        r.nbEvaluationsACreer > 0 && !widget.etat.peut(Permission.evaluationsGerer);
    final titres = {for (final c in r.colonnes) c.colonne: c.titre};
    final noms = [
      for (final e in r.absentsDuFichier.take(12)) '${e.nom.toUpperCase()} ${e.prenom}'.trim(),
    ];
    final autres = r.absentsDuFichier.length - noms.length;
    final texteAbsents =
        'Absents du fichier : ${noms.join(', ')}${autres > 0 ? ' et $autres autre(s)' : ''}.';

    String? explication;
    if (r.bloque) {
      explication = 'Corrigez l\'association des colonnes ci-dessus, puis vérifiez de nouveau.';
    } else if (r.nbNotesAEcrire == 0) {
      explication = 'Aucune note à importer : toutes les cases sont vides, identiques à GESCO '
          'ou conservées.';
    } else if (r.nbLignesErreur > 0 && !_ignorer) {
      explication = 'Corrigez le fichier Excel puis choisissez-le de nouveau, ou activez '
          '« Ignorer les lignes en erreur » ci-dessus.';
    } else if (manqueDroitEvaluations) {
      explication = 'Cet import crée des évaluations : votre compte n\'a pas le droit d\'en '
          'créer. Associez ces colonnes à des évaluations existantes.';
    }

    return Carte(
      key: const Key('notes_import_rapport_carte'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Résultat de la vérification', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Rien n\'a encore été enregistré.',
            style: TextStyle(color: CouleursGesco.gris),
          ),
          const SizedBox(height: 10),
          for (final (k, p) in r.problemesFichier.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $p',
                key: Key('notes_import_probleme_$k'),
                style: const TextStyle(color: CouleursGesco.rouge),
              ),
            ),
          for (final m in r.remarquesFichier)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $m', style: const TextStyle(color: CouleursGesco.gris)),
            ),
          if (!r.bloque) ...[
            const SizedBox(height: 6),
            for (final c in r.colonnes) _resumeColonne(c),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in _Filtre.values)
                  ChoiceChip(
                    key: Key('notes_import_filtre_${f.name}'),
                    label: Text('${f.libelle} (${compte[f]})'),
                    selected: _filtre == f,
                    onSelected: (_) => setState(() => _filtre = f),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (affichees.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Aucune ligne dans cette catégorie.'),
              ),
            for (final l in affichees) _ligneRapport(l, titres),
            if (visibles.length > affichees.length)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Les $_lignesAffichees premières lignes sur ${visibles.length} sont affichées ; '
                  'le rapport Excel contient toutes les lignes à signaler.',
                  key: const Key('notes_import_tronque'),
                  style: const TextStyle(color: CouleursGesco.gris),
                ),
              ),
            if (r.absentsDuFichier.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  texteAbsents,
                  key: const Key('notes_import_absents'),
                  style: const TextStyle(color: CouleursGesco.gris),
                ),
              ),
          ],
          const SizedBox(height: 14),
          if (explication != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                explication,
                key: const Key('notes_import_explication'),
                style: const TextStyle(color: CouleursGesco.orange),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('notes_import_lancer'),
                onPressed: (_occupe || !peut || manqueDroitEvaluations) ? null : () => _confirmer(r),
                icon: const Icon(Icons.download_done, size: 18),
                label: Text(
                  r.nbNotesAEcrire == 0 ? 'Importer' : 'Importer ${_notes(r.nbNotesAEcrire)}',
                ),
              ),
              OutlinedButton.icon(
                key: const Key('notes_import_rapport'),
                onPressed: _occupe ? null : () => _enregistrerRapport(r),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Enregistrer le rapport (Excel)'),
              ),
              TextButton(
                key: const Key('notes_import_annuler'),
                onPressed: _occupe ? null : () => setState(_reinitialiser),
                child: const Text('Annuler l\'import'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resumeColonne(ResumeColonneNotes c) {
    final statut = c.creer
        ? 'évaluation à créer'
        : c.reprise
            ? 'évaluation existante reprise'
            : 'évaluation existante';
    final details = [
      if (c.nbNouvelles > 0) _n(c.nbNouvelles, 'nouvelle', 'nouvelles'),
      if (c.nbRemplacees > 0) _n(c.nbRemplacees, 'remplacée', 'remplacées'),
      if (c.nbIdentiques > 0) _n(c.nbIdentiques, 'identique', 'identiques'),
      if (c.nbConservees > 0) _n(c.nbConservees, 'ancienne gardée', 'anciennes gardées'),
      if (c.nbVides > 0) _n(c.nbVides, 'case vide', 'cases vides'),
      if (c.nbErreurs > 0) _n(c.nbErreurs, 'erreur', 'erreurs'),
      if (c.nbSansNote > 0) _n(c.nbSansNote, 'élève sans note', 'élèves sans note'),
    ];
    return Padding(
      key: Key('notes_import_colonne_${c.colonne}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${c.titre}  ·  ${libelleMois(c.mois)}  ·  sur ${c.bareme}  ·  '
            'coefficient ${_coefTexte(c.coefficient)}  ·  $statut',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            details.isEmpty ? 'Aucune note.' : details.join('  ·  '),
            style: const TextStyle(color: CouleursGesco.gris, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _puceCase(String titre, CaseNote c) {
    final (texte, couleur, fond) = switch (c.etat) {
      EtatCaseNote.nouvelle => (c.texte, CouleursGesco.vert, CouleursGesco.vertClair),
      EtatCaseNote.identique => (
          '${c.texte} (déjà enregistrée)',
          CouleursGesco.gris,
          CouleursGesco.grisClair,
        ),
      EtatCaseNote.remplacee => (
          '${c.texte} remplace ${texteSaisie(c.ancienne)}',
          CouleursGesco.orange,
          CouleursGesco.orangeClair,
        ),
      EtatCaseNote.conflit => (
          '${c.texte} ≠ ${texteSaisie(c.ancienne)} : ancienne gardée',
          CouleursGesco.orange,
          CouleursGesco.orangeClair,
        ),
      EtatCaseNote.vide => ('', CouleursGesco.gris, CouleursGesco.grisClair),
      EtatCaseNote.erreur => (
          '${c.texte.isEmpty ? '' : '${c.texte} : '}${c.message ?? 'erreur'}',
          CouleursGesco.rouge,
          CouleursGesco.rougeClair,
        ),
    };
    return Etiquette('$titre : $texte', couleur: couleur, fond: fond);
  }

  Widget _ligneRapport(LigneImportNotes l, Map<int, String> titres) {
    final (texte, couleur, fond) = l.enErreur
        ? ('Erreur', CouleursGesco.rouge, CouleursGesco.rougeClair)
        : l.nbAEcrire > 0
            ? ('À importer', CouleursGesco.vert, CouleursGesco.vertClair)
            : l.sansNote
                ? ('Sans note', CouleursGesco.gris, CouleursGesco.grisClair)
                : l.avertissements.isNotEmpty
                    ? ('Remarque', CouleursGesco.orange, CouleursGesco.orangeClair)
                    : ('Rien à modifier', CouleursGesco.gris, CouleursGesco.grisClair);
    final e = l.eleve;
    final identite = e != null ? '${e.nom.toUpperCase()} ${e.prenom}'.trim() : l.nom;
    final colonnes = l.cases.keys.toList()..sort();
    return Container(
      key: Key('notes_import_ligne_${l.numero}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CouleursGesco.bordure)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text('L${l.numero}', style: const TextStyle(color: CouleursGesco.gris)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    identite.isEmpty ? '(sans nom)' : identite,
                    if (l.matricule.isNotEmpty) l.matricule,
                  ].join('  ·  '),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                for (final m in l.erreurs)
                  Text('• $m', style: const TextStyle(color: CouleursGesco.rouge, fontSize: 13)),
                for (final m in l.avertissements)
                  Text('• $m', style: const TextStyle(color: CouleursGesco.orange, fontSize: 13)),
                if (!l.enErreur && colonnes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final i in colonnes)
                          if (l.cases[i]!.etat != EtatCaseNote.vide)
                            _puceCase(titres[i] ?? 'Colonne ${TableLue.lettre(i)}', l.cases[i]!),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Etiquette(texte, couleur: couleur, fond: fond),
        ],
      ),
    );
  }
}
