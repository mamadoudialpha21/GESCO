import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/bulletins_auto.dart';
import '../../app/etat_app.dart';
import '../../documents/ouvrir_document.dart';
import '../../domain/permissions.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../theme.dart';

/// Réglage et suivi de la génération automatique des bulletins individuels :
/// interrupteur, dernier résultat, dossier de destination et génération
/// manuelle pour toutes les classes de l'année.
class CarteBulletinsAuto extends StatefulWidget {
  const CarteBulletinsAuto({
    super.key,
    required this.etat,
    required this.auto,
    required this.cle,
    required this.periodeLibelle,
    this.ouvreur = ouvrirFichier,
  });

  final EtatApp etat;
  final BulletinsAuto auto;

  /// Clé de la période affichée (`m11`, `t1`, `annee`...) : celle que
  /// « Tout générer » produit pour chaque classe.
  final String cle;
  final String periodeLibelle;
  final Ouvreur ouvreur;

  @override
  State<CarteBulletinsAuto> createState() => _CarteBulletinsAutoState();
}

class _CarteBulletinsAutoState extends State<CarteBulletinsAuto> {
  /// Null tant que le réglage n'est pas lu.
  bool? _actif;
  String? _dossier;

  bool get _peut => widget.etat.peut(Permission.documentsGenerer);

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final actif = await widget.auto.estActif();
      final dossier = (await widget.auto.dossierBulletins()).path;
      if (!mounted) return;
      setState(() {
        _actif = actif;
        _dossier = dossier;
      });
    } catch (_) {
      if (mounted) setState(() => _actif = true); // valeur par défaut
    }
  }

  Future<void> _basculer(bool actif) async {
    final avant = _actif;
    setState(() => _actif = actif);
    final ok = await executer(context, () => widget.auto.definirActif(actif));
    if (!ok && mounted) setState(() => _actif = avant);
  }

  Future<void> _toutGenerer() async {
    final anneeId = widget.etat.anneeId;
    if (anneeId == null) return;
    final rapport = await widget.auto.genererTout(anneeId, widget.cle);
    if (!mounted) return;
    afficherMessage(
      context,
      rapport.erreurs.isEmpty
          ? (rapport.bulletins == 0
              ? 'Aucun bulletin à produire pour « ${widget.periodeLibelle} ».'
              : 'Terminé : ${rapport.resume}.')
          : 'Génération terminée avec ${rapport.erreurs.length} erreur'
              '${rapport.erreurs.length > 1 ? 's' : ''} : voir le détail.',
      erreur: rapport.erreurs.isNotEmpty,
    );
  }

  Future<void> _ouvrirDossier() async {
    final chemin = _dossier;
    if (chemin == null) return;
    var ok = false;
    try {
      await Directory(chemin).create(recursive: true);
      ok = await widget.ouvreur(chemin);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) {
      afficherMessage(context, 'Impossible d\'ouvrir le dossier : $chemin', erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.auto,
      builder: (context, _) {
        final auto = widget.auto;
        final rapport = auto.dernierRapport;
        final actif = _actif ?? true;
        return Carte(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_outlined, color: CouleursGesco.bleu),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bulletins automatiques',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Switch(
                    key: const Key('auto_bulletins_actif'),
                    value: actif,
                    onChanged: (_actif == null || !_peut) ? null : _basculer,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                actif
                    ? 'À chaque saisie de notes, d\'évaluation ou de composition, GESCO produit '
                        'le bulletin individuel de chaque élève de la classe concernée : '
                        'mensuel, puis de période (maternelle et primaire : 3 compositions ; '
                        'collège et lycée : 2 semestres), puis annuel après la dernière période. '
                        'Les fichiers précédents sont remplacés par la version à jour.'
                    : 'Génération automatique désactivée : les bulletins ne sont produits que '
                        'par les boutons ci-dessous.',
                key: const Key('auto_bulletins_texte'),
                style: const TextStyle(color: CouleursGesco.gris),
              ),
              if (_dossier != null) ...[
                const SizedBox(height: 8),
                SelectableText(
                  _dossier!,
                  key: const Key('auto_bulletins_dossier'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    key: const Key('auto_bulletins_tout'),
                    onPressed: (_peut && !auto.enCours && widget.etat.anneeId != null)
                        ? _toutGenerer
                        : null,
                    icon: const Icon(Icons.play_circle_outline),
                    label: Text('Tout générer : ${widget.periodeLibelle}'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('auto_bulletins_ouvrir'),
                    onPressed: _dossier == null ? null : _ouvrirDossier,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Ouvrir le dossier'),
                  ),
                  if (auto.enCours)
                    const Row(
                      key: Key('auto_bulletins_en_cours'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        SizedBox(width: 8),
                        Text('Génération en cours…'),
                      ],
                    ),
                ],
              ),
              if (!_peut) ...[
                const SizedBox(height: 8),
                const Text(
                  'Votre compte n\'a pas l\'autorisation de générer les documents.',
                  style: TextStyle(color: CouleursGesco.rouge),
                ),
              ],
              if (rapport != null) ...[
                const Divider(height: 28),
                _Rapport(rapport: rapport),
              ],
            ],
          ),
        );
      },
    );
  }
}

String _heure(DateTime d) {
  String deux(int n) => n.toString().padLeft(2, '0');
  return '${deux(d.day)}/${deux(d.month)}/${d.year} à ${deux(d.hour)}:${deux(d.minute)}';
}

class _Rapport extends StatelessWidget {
  const _Rapport({required this.rapport});

  final RapportBulletins rapport;

  static const int _maxLignes = 8;

  @override
  Widget build(BuildContext context) {
    final lignes = rapport.descriptions;
    final visibles = lignes.take(_maxLignes).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${rapport.automatique ? 'Dernière génération automatique' : 'Dernière génération manuelle'}'
          ' · ${_heure(rapport.date)}',
          key: const Key('auto_bulletins_quand'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(rapport.resume, key: const Key('auto_bulletins_resume')),
        for (final l in visibles)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('• $l', style: const TextStyle(color: CouleursGesco.gris)),
          ),
        if (lignes.length > visibles.length)
          Text(
            '… et ${lignes.length - visibles.length} autre${lignes.length - visibles.length > 1 ? 's' : ''}',
            style: const TextStyle(color: CouleursGesco.gris),
          ),
        if (rapport.ignorees.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final (i, l) in rapport.ignorees.take(_maxLignes).indexed)
            Text('Ignoré : $l',
                key: Key('auto_bulletins_ignoree_$i'),
                style: const TextStyle(color: CouleursGesco.orange)),
        ],
        if (rapport.erreurs.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final (i, e) in rapport.erreurs.take(_maxLignes).indexed)
            Text(e,
                key: Key('auto_bulletins_erreur_$i'),
                style: const TextStyle(color: CouleursGesco.rouge)),
        ],
      ],
    );
  }
}
