import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/erreurs.dart';
import '../../documents/ouvrir_document.dart';
import '../../domain/periodes.dart';
import '../../import_export/liste_vierge.dart';
import '../../import_export/service_export.dart';
import '../commun/choix.dart';
import '../commun/composants.dart';
import '../theme.dart';
import 'donnees_excel.dart';
import 'resultat_fichiers.dart';

/// Listes de notes vierges pour les enseignants : un fichier Excel par classe
/// et par enseignant, avec les élèves et des cases à remplir. L'enseignant
/// rend le fichier rempli, qui sera importé dans GESCO.
class VueListesVierges extends StatefulWidget {
  const VueListesVierges({
    super.key,
    required this.etat,
    required this.donnees,
    required this.ouvreur,
    this.dossier,
    this.maintenant,
  });

  final EtatApp etat;
  final DonneesExcel donnees;
  final Ouvreur ouvreur;
  final Directory? dossier;
  final DateTime Function()? maintenant;

  @override
  State<VueListesVierges> createState() => _VueListesViergesState();
}

class _VueListesViergesState extends State<VueListesVierges> {
  int? _classeId;
  int? _enseignantId;
  late int _mois = moisParDefaut((widget.maintenant ?? DateTime.now)());
  int _interrogations = 2;
  int _devoirs = 0;
  bool _composition = false;
  bool _observations = true;
  bool _enCours = false;
  ProduitExcel? _produit;
  String _dossierProduit = '';

  Future<void> _generer(int? classeId, int? enseignantId) async {
    final anneeId = widget.etat.anneeId;
    if (_enCours || anneeId == null) return;
    setState(() => _enCours = true);
    ProduitExcel? produit;
    String? erreur;
    try {
      final service = ServiceExport(widget.etat.services, maintenant: widget.maintenant);
      final fichiers = await service.listesVierges(
        anneeId: anneeId,
        classeId: classeId,
        enseignantId: enseignantId,
        options: OptionsListeVierge(
          mois: _mois,
          nbInterrogations: _interrogations,
          nbDevoirs: _devoirs,
          avecComposition: _composition,
          avecObservations: _observations,
        ),
      );
      final dossier = widget.dossier ?? await dossierDocuments();
      final chemins = <String>[];
      for (final f in fichiers) {
        final enregistre = await service.enregistrer(f, dossier: dossier);
        chemins.add(enregistre.fichier.path);
      }
      _dossierProduit = dossier.path;
      produit = ProduitExcel(
        titre: chemins.length == 1
            ? 'Liste créée pour ${libelleMois(_mois)}.'
            : '${chemins.length} listes créées pour ${libelleMois(_mois)}.',
        chemins: chemins,
        avertissements: fichiers.first.avertissements,
      );
    } on ErreurGesco catch (e) {
      erreur = e.message;
    } catch (e) {
      erreur = 'Erreur inattendue : $e';
    }
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _produit = produit ?? _produit;
    });
    if (erreur != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erreur), backgroundColor: CouleursGesco.rouge),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.donnees;
    final int? classeId = d.classes.any((c) => c.classe.id == _classeId) ? _classeId : null;
    final int? enseignantId =
        d.enseignants.any((e) => e.enseignant.id == _enseignantId) ? _enseignantId : null;

    return Column(
      key: const Key('vue_listes'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Carte(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Un fichier Excel est créé pour chaque classe et chaque enseignant, avec '
                'une feuille par matière : établissement, année, classe, matière, '
                'enseignant, puis matricule, nom et prénom de chaque élève et des cases '
                'jaunes à remplir. Envoyez-le à l\'enseignant ; une fois rempli, '
                'il pourra être importé dans GESCO.',
                key: Key('listes_intro'),
                style: TextStyle(color: CouleursGesco.gris),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 240,
                    child: ChoixListe<int?>(
                      cleChamp: const Key('liste_classe'),
                      libelle: 'Classe',
                      valeur: classeId,
                      options: [
                        (null, 'Toutes les classes'),
                        for (final c in d.classes) (c.classe.id, c.classe.nom),
                      ],
                      onChanged: (v) => setState(() => _classeId = v),
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: ChoixListe<int?>(
                      cleChamp: const Key('liste_enseignant'),
                      libelle: 'Enseignant',
                      valeur: enseignantId,
                      options: [
                        (null, 'Tous les enseignants'),
                        for (final e in d.enseignants)
                          (e.enseignant.id, e.enseignant.nomComplet),
                      ],
                      onChanged: (v) => setState(() => _enseignantId = v),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: ChoixListe<int>(
                      cleChamp: const Key('liste_mois'),
                      libelle: 'Mois des notes',
                      valeur: _mois,
                      options: [for (final m in moisScolaires) (m, libelleMois(m))],
                      onChanged: (v) => setState(() => _mois = v ?? _mois),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Colonnes à remplir',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Si une matière a déjà des évaluations ce mois-ci, ce sont elles qui '
                'servent de colonnes (avec leur barème). Sinon, GESCO propose :',
                key: Key('listes_aide_colonnes'),
                style: TextStyle(color: CouleursGesco.gris),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 200,
                    child: ChoixListe<int>(
                      cleChamp: const Key('liste_interros'),
                      libelle: 'Interrogations',
                      valeur: _interrogations,
                      options: [for (var i = 0; i <= interrogationsMax; i++) (i, '$i')],
                      onChanged: (v) => setState(() => _interrogations = v ?? _interrogations),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: ChoixListe<int>(
                      cleChamp: const Key('liste_devoirs'),
                      libelle: 'Devoirs',
                      valeur: _devoirs,
                      options: [for (var i = 0; i <= devoirsMax; i++) (i, '$i')],
                      onChanged: (v) => setState(() => _devoirs = v ?? _devoirs),
                    ),
                  ),
                ],
              ),
              CheckboxListTile(
                key: const Key('liste_composition'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Ajouter une colonne « Composition »'),
                value: _composition,
                onChanged: (v) => setState(() => _composition = v ?? false),
              ),
              CheckboxListTile(
                key: const Key('liste_observations'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Ajouter une colonne « Observations »'),
                value: _observations,
                onChanged: (v) => setState(() => _observations = v ?? false),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const Key('liste_creer'),
                  onPressed: _enCours ? null : () => _generer(classeId, enseignantId),
                  icon: _enCours
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.assignment_outlined),
                  label: Text(_enCours ? 'Création en cours...' : 'Créer les listes'),
                ),
              ),
            ],
          ),
        ),
        if (_produit != null) ...[
          const SizedBox(height: 16),
          CarteProduit(produit: _produit!, ouvrir: widget.ouvreur, dossier: _dossierProduit),
        ],
      ],
    );
  }
}
