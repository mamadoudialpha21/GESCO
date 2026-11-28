import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/erreurs.dart';
import '../../data/modeles_donnees.dart';
import '../../documents/ouvrir_document.dart';
import '../../domain/calendrier.dart';
import '../../import_export/service_export.dart';
import '../commun/choix.dart';
import '../commun/composants.dart';
import '../theme.dart';
import 'donnees_excel.dart';
import 'resultat_fichiers.dart';

/// Les dix exports Excel : on choisit le contenu, la classe et la période, puis
/// le fichier est créé dans « Documents\GESCO », relu pour vérification et
/// ouvert dans Excel.
class VueExports extends StatefulWidget {
  const VueExports({
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
  State<VueExports> createState() => _VueExportsState();
}

class _VueExportsState extends State<VueExports> {
  TypeExport _type = TypeExport.eleves;
  int? _classeId;
  int? _matiereId;
  String _cle = cleAnnee;
  bool _enCours = false;
  ProduitExcel? _produit;
  String _dossierProduit = '';

  Future<void> _exporter(OptionsExport options) async {
    final anneeId = widget.etat.anneeId;
    if (_enCours || anneeId == null) return;
    setState(() => _enCours = true);
    ProduitExcel? produit;
    String? erreur;
    try {
      final service = ServiceExport(widget.etat.services, maintenant: widget.maintenant);
      final fichier = await service.construire(_type, anneeId: anneeId, options: options);
      final dossier = widget.dossier ?? await dossierDocuments();
      final enregistre = await service.enregistrer(fichier, dossier: dossier);
      final ouvert = await widget.ouvreur(enregistre.fichier.path);
      _dossierProduit = dossier.path;
      produit = ProduitExcel(
        titre: 'Fichier créé : ${_type.libelle} '
            '(${enregistre.nbFeuilles} feuille${enregistre.nbFeuilles > 1 ? 's' : ''}).',
        chemins: [enregistre.fichier.path],
        avertissements: fichier.avertissements,
        ouvert: ouvert,
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
    final type = _type;

    // Choix valides : on revient à une valeur permise si la précédente ne
    // s'applique plus au type d'export (ou si la classe a disparu).
    int? classeId = type.accepteClasse ? _classeId : null;
    if (classeId != null && !d.classes.any((c) => c.classe.id == classeId)) classeId = null;
    if (type.classeObligatoire && classeId == null) classeId = d.classes.first.classe.id;
    final List<MatiereClasse> matieres =
        classeId == null ? const [] : (d.matieres[classeId] ?? const []);
    final int? matiereId = type.accepteMatiere && matieres.any((m) => m.id == _matiereId)
        ? _matiereId
        : null;
    final etendues = type.periodeSeulement ? d.periodes : d.etendues;
    final cle = etendues.any((o) => o.$1 == _cle) ? _cle : etendues.first.$1;

    return Column(
      key: const Key('vue_exports'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Carte(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChoixListe<TypeExport>(
                cleChamp: const Key('excel_type'),
                libelle: 'Que voulez-vous exporter ?',
                valeur: type,
                options: [for (final t in TypeExport.values) (t, t.libelle)],
                onChanged: (v) {
                  if (v != null) setState(() => _type = v);
                },
              ),
              const SizedBox(height: 8),
              Text(
                type.description,
                key: const Key('excel_description'),
                style: const TextStyle(color: CouleursGesco.gris),
              ),
              if (type.accepteClasse) ...[
                const SizedBox(height: 14),
                ChoixListe<int?>(
                  cleChamp: const Key('excel_classe'),
                  libelle: 'Classe',
                  valeur: classeId,
                  options: [
                    if (!type.classeObligatoire) (null, 'Toutes les classes'),
                    for (final c in d.classes) (c.classe.id, c.classe.nom),
                  ],
                  onChanged: (v) => setState(() {
                    _classeId = v;
                    _matiereId = null;
                  }),
                ),
              ],
              if (type.accepteMatiere && classeId != null) ...[
                const SizedBox(height: 12),
                ChoixListe<int?>(
                  cleChamp: const Key('excel_matiere'),
                  libelle: 'Matière',
                  valeur: matiereId,
                  options: [
                    (null, type == TypeExport.classements ? 'Moyenne générale' : 'Toutes les matières'),
                    for (final m in matieres) (m.id, m.nom),
                  ],
                  onChanged: (v) => setState(() => _matiereId = v),
                ),
              ],
              if (type.demandePeriode) ...[
                const SizedBox(height: 12),
                ChoixListe<String>(
                  cleChamp: const Key('excel_periode'),
                  libelle: type.periodeSeulement ? 'Période (trimestre, semestre, composition)' : 'Période',
                  valeur: cle,
                  options: etendues,
                  onChanged: (v) {
                    if (v != null) setState(() => _cle = v);
                  },
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const Key('excel_creer'),
                  onPressed: _enCours
                      ? null
                      : () => _exporter(
                            OptionsExport(classeId: classeId, matiereId: matiereId, cle: cle),
                          ),
                  icon: _enCours
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_download_outlined),
                  label: Text(_enCours ? 'Création en cours...' : 'Créer le fichier Excel'),
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
