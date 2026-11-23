import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../documents/ouvrir_document.dart';
import '../../domain/permissions.dart';
import '../commun/chargeur.dart';
import '../commun/composants.dart';
import 'donnees_excel.dart';
import 'vue_exports.dart';
import 'vue_listes_vierges.dart';

enum _Vue { exporter, listes }

/// Fichiers Excel : exports des données et listes de notes vierges pour les
/// enseignants. (Les imports s'ajoutent ici : élèves, puis notes.)
class PageExcel extends StatefulWidget {
  const PageExcel({
    super.key,
    required this.etat,
    required this.allerAuxParametres,
    this.ouvreur = ouvrirFichier,
    this.dossier,
    this.maintenant,
  });

  final EtatApp etat;
  final VoidCallback allerAuxParametres;

  /// Ouvre un fichier ou un dossier dans le programme du système.
  final Ouvreur ouvreur;

  /// Dossier d'enregistrement ; « Documents\GESCO » si absent (tests).
  final Directory? dossier;

  /// Horloge (remplaçable dans les tests).
  final DateTime Function()? maintenant;

  @override
  State<PageExcel> createState() => _PageExcelState();
}

class _PageExcelState extends State<PageExcel> {
  _Vue _vue = _Vue.exporter;

  @override
  Widget build(BuildContext context) {
    final etat = widget.etat;
    if (!etat.peut(Permission.importExport)) {
      return const MessageVide(
        'Votre compte n\'a pas le droit d\'importer ou d\'exporter des fichiers Excel.',
        icone: Icons.lock_outline,
      );
    }
    return Chargeur<DonneesExcel>(
      cle: (etat.anneeId, etat.version),
      charger: () => DonneesExcel.charger(etat),
      builder: _contenu,
    );
  }

  Widget _sansDonnees(String message, IconData icone) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MessageVide(message, icone: icone),
          FilledButton.icon(
            onPressed: widget.allerAuxParametres,
            icon: const Icon(Icons.settings),
            label: const Text('Ouvrir les paramètres'),
          ),
        ],
      ),
    );
  }

  Widget _contenu(BuildContext context, DonneesExcel d) {
    final annee = widget.etat.anneeCourante;
    if (annee == null) {
      return _sansDonnees(
        'Aucune année scolaire. Créez-en une dans les paramètres.',
        Icons.event_outlined,
      );
    }
    if (d.classes.isEmpty) {
      return _sansDonnees(
        'Aucune classe pour cette année scolaire. Créez des classes et leurs matières '
        'dans les paramètres.',
        Icons.school_outlined,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TitreSection(
          'Fichiers Excel',
          sousTitre: 'Année ${annee.libelle} · exporter les données et préparer les '
              'listes de notes des enseignants.',
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<_Vue>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: _Vue.exporter,
                label: Text('Exporter', key: Key('excel_vue_exporter')),
              ),
              ButtonSegment(
                value: _Vue.listes,
                label: Text('Listes pour les enseignants', key: Key('excel_vue_listes')),
              ),
            ],
            selected: {_vue},
            onSelectionChanged: (s) => setState(() => _vue = s.first),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: _vue == _Vue.exporter
                ? VueExports(
                    etat: widget.etat,
                    donnees: d,
                    ouvreur: widget.ouvreur,
                    dossier: widget.dossier,
                    maintenant: widget.maintenant,
                  )
                : VueListesVierges(
                    etat: widget.etat,
                    donnees: d,
                    ouvreur: widget.ouvreur,
                    dossier: widget.dossier,
                    maintenant: widget.maintenant,
                  ),
          ),
        ),
      ],
    );
  }
}
