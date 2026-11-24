import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/erreurs.dart';
import '../../documents/ouvrir_document.dart';
import '../../domain/permissions.dart';
import '../../import_export/import_eleves.dart';
import '../../import_export/lecture_tableur.dart';
import '../../import_export/service_import_eleves.dart';
import '../../tableur/classeur.dart';
import '../commun/choix.dart';
import '../commun/composants.dart';
import '../theme.dart';
import 'donnees_excel.dart';
import 'resultat_fichiers.dart';

/// Choisit un classeur Excel : boîte de dialogue du système (remplaçable dans
/// les tests).
typedef SelecteurFichier = Future<FichierChoisi?> Function();

Future<FichierChoisi?> choisirFichierExcel() async {
  final resultat = await FilePicker.platform.pickFiles(
    dialogTitle: 'Choisir le fichier Excel',
    type: FileType.custom,
    allowedExtensions: const ['xlsx'],
    withData: true,
  );
  if (resultat == null || resultat.files.isEmpty) return null;
  final fichier = resultat.files.single;
  var octets = fichier.bytes;
  final chemin = fichier.path;
  if (octets == null && chemin != null) octets = await File(chemin).readAsBytes();
  if (octets == null) throw const ErreurGesco('Impossible de lire le fichier choisi.');
  return FichierChoisi(nom: fichier.name, octets: octets);
}

enum _Filtre {
  tout('Toutes'),
  aImporter('À importer'),
  remarques('Avec remarque'),
  dejaPresents('Déjà présents'),
  erreurs('En erreur');

  const _Filtre(this.libelle);

  final String libelle;
}

/// Nombre de lignes affichées à l'écran (le rapport Excel les contient toutes).
const int _lignesAffichees = 200;

String _eleves(int n) => n == 1 ? '1 élève' : '$n élèves';

/// Import des élèves depuis un fichier Excel : choix du fichier, association
/// des colonnes, vérification complète avec aperçu, puis import en une seule
/// fois. Rien n'est écrit tant que l'utilisateur n'a pas confirmé.
class VueImportEleves extends StatefulWidget {
  const VueImportEleves({
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
  State<VueImportEleves> createState() => _VueImportElevesState();
}

class _VueImportElevesState extends State<VueImportEleves> {
  late final ServiceImportEleves _service =
      ServiceImportEleves(widget.etat.services, maintenant: widget.maintenant);

  String? _nomFichier;
  ClasseurLu? _classeur;
  List<FeuilleImport> _feuilles = const [];
  int _feuille = 0;
  int _indexEntete = 0;
  TableLue? _table;
  List<ChampEleve?> _association = const [];
  int? _classeDefaut;
  bool _ignorer = false;
  bool _depassement = false;
  RapportImportEleves? _rapport;
  ResultatImportEleves? _resultat;
  ProduitExcel? _produit;
  String _dossierProduit = '';
  _Filtre _filtre = _Filtre.tout;
  bool _occupe = false;

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

  /// Oublie le fichier, l'association et le rapport. Le résultat du dernier
  /// import est gardé si [garderResultat].
  void _reinitialiser({bool garderResultat = false}) {
    _nomFichier = null;
    _classeur = null;
    _feuilles = const [];
    _feuille = 0;
    _indexEntete = 0;
    _table = null;
    _association = const [];
    _classeDefaut = null;
    _rapport = null;
    if (!garderResultat) _resultat = null;
  }

  /// Relit le tableau de la feuille choisie avec la ligne d'en-tête courante.
  void _chargerTable() {
    final f = _classeur!.feuilles[_feuille];
    final t = lireTable(f, indexEntete: _indexEntete);
    _table = t;
    _association = associerColonnes(t.entetes);
    _rapport = null;
    _resultat = null;
  }

  Future<void> _choisir() => _executer(() async {
        final choisi = await widget.selecteur();
        if (choisi == null) return;
        final classeur = _service.ouvrir(choisi.octets);
        final feuilles = _service.feuilles(classeur);
        final proposee = _service.feuilleProposee(classeur);
        if (!mounted) return;
        setState(() {
          _reinitialiser();
          _nomFichier = choisi.nom;
          _classeur = classeur;
          _feuilles = feuilles;
          _feuille = proposee;
          _indexEntete = feuilles[proposee].indexEntete ?? 0;
          _chargerTable();
        });
      });

  Future<void> _verifier() => _executer(() async {
        final anneeId = widget.etat.anneeId;
        final table = _table;
        if (anneeId == null || table == null) return;
        final ctx = await _service.contexte(
          anneeId,
          classeParDefautId: _classeDefautValide,
          autoriserDepassement: _depassement,
        );
        final rapport = analyserImportEleves(table: table, association: _association, ctx: ctx);
        if (!mounted) return;
        setState(() {
          _rapport = rapport;
          _resultat = null;
          _filtre = _Filtre.tout;
        });
      });

  Future<void> _confirmer(RapportImportEleves rapport) async {
    final annee = widget.etat.anneeCourante;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Importer ${_eleves(rapport.nbAImporter)} ?'),
        content: Text(
          'Les élèves seront inscrits dans l\'année scolaire ${annee?.libelle ?? ''}. '
          'L\'import est fait en une seule fois : si une ligne pose problème, rien '
          'n\'est enregistré.',
        ),
        actions: [
          TextButton(
            key: const Key('import_confirmer_non'),
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('import_confirmer_oui'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Importer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _executer(() async {
      final anneeId = widget.etat.anneeId;
      if (anneeId == null) return;
      final resultat = await _service.importer(
        rapport,
        anneeId: anneeId,
        nomFichier: _nomFichier ?? '',
        ignorerErreurs: _ignorer,
        autoriserDepassement: _depassement,
      );
      widget.etat.donneesModifiees();
      if (!mounted) return;
      // Le fichier est oublié : le réimporter par erreur créerait des doublons.
      setState(() {
        _reinitialiser(garderResultat: true);
        _resultat = resultat;
      });
    });
  }

  Future<void> _enregistrerRapport(RapportImportEleves rapport) => _executer(() async {
        final anneeId = widget.etat.anneeId;
        if (anneeId == null) return;
        final dossier = widget.dossier ?? await dossierDocuments();
        final f = await _service.enregistrerRapport(
          rapport,
          anneeId: anneeId,
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

  Future<void> _creerModele() => _executer(() async {
        final anneeId = widget.etat.anneeId;
        if (anneeId == null) return;
        final dossier = widget.dossier ?? await dossierDocuments();
        final f = await _service.enregistrerModele(anneeId: anneeId, dossier: dossier);
        final ouvert = await widget.ouvreur(f.fichier.path);
        if (!mounted) return;
        setState(() {
          _dossierProduit = dossier.path;
          _produit = ProduitExcel(
            titre: 'Modèle créé : remplissez-le, puis importez-le ici.',
            chemins: [f.fichier.path],
            ouvert: ouvert,
          );
        });
      });

  int? get _classeDefautValide =>
      widget.donnees.classes.any((c) => c.classe.id == _classeDefaut) ? _classeDefaut : null;

  // --------------------------------------------------------------- Écran

  @override
  Widget build(BuildContext context) {
    final etat = widget.etat;
    final annee = etat.anneeCourante;
    final peutGerer = etat.peut(Permission.elevesGerer);
    final archivee = annee?.archivee ?? false;
    final peutChoisir = peutGerer && !archivee && !_occupe;
    final rapport = _rapport;

    return Column(
      key: const Key('vue_import_eleves'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Carte(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Importez une liste d\'élèves depuis un fichier Excel (.xlsx). Le fichier est '
                'd\'abord vérifié en entier : vous voyez le résultat avant que quoi que ce soit '
                'ne soit enregistré. La liste des élèves exportée par GESCO peut être corrigée '
                'puis réimportée.',
                key: Key('import_intro'),
                style: TextStyle(color: CouleursGesco.gris),
              ),
              if (!peutGerer || archivee) ...[
                const SizedBox(height: 10),
                Text(
                  !peutGerer
                      ? 'Votre compte n\'a pas le droit de gérer les élèves : l\'import est désactivé.'
                      : 'L\'année scolaire ${annee?.libelle ?? ''} est archivée : elle n\'est plus modifiable.',
                  key: const Key('import_refus'),
                  style: const TextStyle(color: CouleursGesco.rouge),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const Key('import_choisir'),
                    onPressed: peutChoisir ? _choisir : null,
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: Text(_classeur == null ? 'Choisir un fichier Excel' : 'Choisir un autre fichier'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('import_modele'),
                    onPressed: _occupe ? null : _creerModele,
                    icon: const Icon(Icons.table_chart_outlined, size: 18),
                    label: const Text('Créer un modèle à remplir'),
                  ),
                ],
              ),
              if (_occupe) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(key: Key('import_occupe')),
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

  Widget _carteResultat(ResultatImportEleves r) {
    return Carte(
      key: const Key('import_resultat'),
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
                  '${_eleves(r.nbImportes)} importé${r.nbImportes > 1 ? 's' : ''} et '
                  'retrouvé${r.nbVerifies > 1 ? 's' : ''} dans la base.',
                  key: const Key('import_resultat_titre'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (r.nbDejaPresents > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${r.nbDejaPresents} ligne${r.nbDejaPresents > 1 ? 's' : ''} ignorée'
              '${r.nbDejaPresents > 1 ? 's' : ''} : élève déjà présent (rien n\'a été modifié).',
              style: const TextStyle(color: CouleursGesco.gris),
            ),
          ],
          if (r.nbLignesEnErreur > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${r.nbLignesEnErreur} ligne${r.nbLignesEnErreur > 1 ? 's' : ''} en erreur '
              'ignorée${r.nbLignesEnErreur > 1 ? 's' : ''} : à corriger dans le fichier puis '
              'à importer de nouveau.',
              style: const TextStyle(color: CouleursGesco.gris),
            ),
          ],
        ],
      ),
    );
  }

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
              cleChamp: const Key('import_feuille'),
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
              cleChamp: const Key('import_ligne_entete'),
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

  Widget _carteAssociation(TableLue t) {
    final colonnes = [
      for (var i = 0; i < t.nbColonnes; i++)
        if (t.entetes[i].isNotEmpty || t.exemples(i).isNotEmpty) i,
    ];
    return Carte(
      key: const Key('import_association'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fichier « ${_nomFichier ?? ''} »  ·  ${t.lignes.length} ligne'
            '${t.lignes.length > 1 ? 's' : ''} sous les titres',
            key: const Key('import_fichier'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Indiquez pour chaque colonne du fichier le champ de GESCO qui lui correspond '
            '(les champs marqués * sont obligatoires). Les colonnes reconnues sont déjà associées.',
            style: TextStyle(color: CouleursGesco.gris),
          ),
          const SizedBox(height: 12),
          _choixFeuilleEtEntete(),
          const SizedBox(height: 8),
          for (final i in colonnes) _ligneColonne(t, i),
          const Divider(height: 24),
          SizedBox(
            width: 460,
            child: ChoixListe<int?>(
              cleChamp: const Key('import_classe_defaut'),
              libelle: 'Classe de tous les élèves',
              aide: 'Utilisée si la colonne « Classe » est absente ou vide.',
              valeur: _classeDefautValide,
              options: [
                (null, 'Aucune'),
                for (final c in widget.donnees.classes) (c.classe.id, c.classe.nom),
              ],
              onChanged: (v) => setState(() {
                _classeDefaut = v;
                _rapport = null;
                _resultat = null;
              }),
            ),
          ),
          SwitchListTile(
            key: const Key('import_ignorer'),
            contentPadding: EdgeInsets.zero,
            value: _ignorer,
            title: const Text('Ignorer les lignes en erreur et importer les autres'),
            subtitle: const Text(
              'Sinon, l\'import est refusé tant qu\'une ligne est en erreur.',
            ),
            onChanged: (v) => setState(() => _ignorer = v),
          ),
          SwitchListTile(
            key: const Key('import_depassement'),
            contentPadding: EdgeInsets.zero,
            value: _depassement,
            title: const Text('Autoriser le dépassement de la capacité des classes'),
            onChanged: (v) => setState(() {
              _depassement = v;
              _rapport = null;
              _resultat = null;
            }),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('import_verifier'),
            onPressed: _occupe ? null : _verifier,
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Vérifier le fichier'),
          ),
        ],
      ),
    );
  }

  Widget _ligneColonne(TableLue t, int i) {
    final exemples = t.exemples(i);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${TableLue.lettre(i)}  ·  ${t.entetes[i].isEmpty ? '(sans titre)' : t.entetes[i]}',
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
            width: 240,
            child: ChoixListe<ChampEleve?>(
              cleChamp: Key('import_col_$i'),
              libelle: 'Champ de GESCO',
              valeur: _association[i],
              options: [
                (null, 'Ne pas importer'),
                for (final c in ChampEleve.values) (c, c.obligatoire ? '${c.libelle} *' : c.libelle),
              ],
              onChanged: (v) => setState(() {
                _association = [..._association]..[i] = v;
                _rapport = null;
                _resultat = null;
              }),
            ),
          ),
        ],
      ),
    );
  }

  bool _garde(LigneImportEleve l, _Filtre f) => switch (f) {
        _Filtre.tout => true,
        _Filtre.aImporter => l.aImporter,
        _Filtre.remarques => !l.enErreur && l.avertissements.isNotEmpty,
        _Filtre.dejaPresents => l.dejaPresent && !l.enErreur,
        _Filtre.erreurs => l.enErreur,
      };

  Widget _carteRapport(RapportImportEleves r) {
    final compte = {
      _Filtre.tout: r.lignes.length,
      _Filtre.aImporter: r.nbAImporter,
      _Filtre.remarques: r.nbAvertissements,
      _Filtre.dejaPresents: r.nbDejaPresents,
      _Filtre.erreurs: r.nbErreurs,
    };
    final visibles = [for (final l in r.lignes) if (_garde(l, _filtre)) l];
    final affichees = visibles.take(_lignesAffichees).toList();
    final peut = r.peutImporter(ignorerErreurs: _ignorer);

    String? explication;
    if (r.bloque) {
      explication = 'Corrigez l\'association des colonnes ci-dessus, puis vérifiez de nouveau.';
    } else if (r.nbAImporter == 0) {
      explication = 'Aucun nouvel élève à importer.';
    } else if (r.nbErreurs > 0 && !_ignorer) {
      explication = 'Corrigez le fichier Excel puis choisissez-le de nouveau, ou activez '
          '« Ignorer les lignes en erreur » ci-dessus.';
    }

    return Carte(
      key: const Key('import_rapport_carte'),
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
          for (final p in r.problemesFichier)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $p', style: const TextStyle(color: CouleursGesco.rouge)),
            ),
          for (final m in r.remarquesFichier)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $m', style: const TextStyle(color: CouleursGesco.gris)),
            ),
          if (!r.bloque) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in _Filtre.values)
                  ChoiceChip(
                    key: Key('import_filtre_${f.name}'),
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
            for (final l in affichees) _ligneRapport(l),
            if (visibles.length > affichees.length)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Les $_lignesAffichees premières lignes sur ${visibles.length} sont affichées ; '
                  'le rapport Excel contient toutes les lignes à signaler.',
                  key: const Key('import_tronque'),
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
                key: const Key('import_explication'),
                style: const TextStyle(color: CouleursGesco.orange),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('import_lancer'),
                onPressed: (_occupe || !peut) ? null : () => _confirmer(r),
                icon: const Icon(Icons.download_done, size: 18),
                label: Text(
                  r.nbAImporter == 0 ? 'Importer' : 'Importer ${_eleves(r.nbAImporter)}',
                ),
              ),
              OutlinedButton.icon(
                key: const Key('import_rapport'),
                onPressed: _occupe ? null : () => _enregistrerRapport(r),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Enregistrer le rapport (Excel)'),
              ),
              TextButton(
                key: const Key('import_annuler'),
                onPressed: _occupe ? null : () => setState(_reinitialiser),
                child: const Text('Annuler l\'import'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ligneRapport(LigneImportEleve l) {
    final (texte, couleur, fond) = l.enErreur
        ? ('Erreur', CouleursGesco.rouge, CouleursGesco.rougeClair)
        : l.dejaPresent
            ? ('Déjà présent', CouleursGesco.gris, CouleursGesco.grisClair)
            : l.avertissements.isNotEmpty
                ? ('Remarque', CouleursGesco.orange, CouleursGesco.orangeClair)
                : ('À importer', CouleursGesco.vert, CouleursGesco.vertClair);
    final identite = '${l.nom.toUpperCase()} ${l.prenom}'.trim();
    return Container(
      key: Key('import_ligne_${l.numero}'),
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
                    if (l.classe.isNotEmpty) l.classe,
                  ].join('  ·  '),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                for (final m in l.erreurs)
                  Text('• $m', style: const TextStyle(color: CouleursGesco.rouge, fontSize: 13)),
                for (final m in l.avertissements)
                  Text('• $m', style: const TextStyle(color: CouleursGesco.orange, fontSize: 13)),
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
