import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/erreurs.dart';
import '../../sauvegarde/service_sauvegarde.dart';
import '../theme.dart';
import 'libelles.dart';

/// Ouvre l'assistant de restauration de la sauvegarde [chemin]. Retourne
/// quand l'assistant est fermé.
Future<void> ouvrirRestauration(
  BuildContext context,
  EtatApp etat,
  String chemin, {
  required void Function() quitter,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DialogueRestauration(etat: etat, chemin: chemin, quitter: quitter),
  );
}

enum _Phase { analyse, refuse, apercu, execution, fini }

enum _Statut { fait, enCours, aVenir, echec }

/// Restauration en neuf étapes : choix du fichier, contrôle, comparaison avec
/// les données actuelles, confirmation, sauvegarde de sécurité, remplacement,
/// réouverture, contrôle des données restaurées, fin.
class DialogueRestauration extends StatefulWidget {
  const DialogueRestauration({
    super.key,
    required this.etat,
    required this.chemin,
    required this.quitter,
  });

  final EtatApp etat;
  final String chemin;
  final void Function() quitter;

  @override
  State<DialogueRestauration> createState() => _DialogueRestaurationState();
}

class _DialogueRestaurationState extends State<DialogueRestauration> {
  _Phase _phase = _Phase.analyse;
  EtapeRestauration _etape = EtapeRestauration.verification;
  EtapeRestauration? _echec;
  ApercuRestauration? _apercu;
  ResultatRestauration? _resultat;
  String? _erreur;
  bool _confirme = false;
  bool _redemarrage = false;

  EtatApp get _etat => widget.etat;

  @override
  void initState() {
    super.initState();
    _analyser();
  }

  Future<void> _analyser() async {
    final service = _etat.sauvegarde;
    if (service == null) {
      setState(() {
        _phase = _Phase.refuse;
        _echec = EtapeRestauration.verification;
        _erreur = 'Les sauvegardes ne sont pas disponibles dans ce mode.';
      });
      return;
    }
    try {
      final apercu = await service.preparerRestauration(widget.chemin);
      if (!mounted) return;
      setState(() {
        _apercu = apercu;
        if (apercu.possible) {
          _phase = _Phase.apercu;
          _etape = EtapeRestauration.confirmation;
        } else {
          _phase = _Phase.refuse;
          _echec = EtapeRestauration.verification;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.refuse;
        _echec = EtapeRestauration.verification;
        _erreur = e is ErreurGesco ? e.message : '$e';
      });
    }
  }

  Future<void> _lancer() async {
    final gestion = _etat.gestionBase;
    if (gestion == null) return;
    setState(() {
      _phase = _Phase.execution;
      _etape = EtapeRestauration.securite;
    });
    try {
      final r = await gestion.restaurer(
        widget.chemin,
        progression: (e) {
          if (mounted) setState(() => _etape = e);
        },
      );
      if (!mounted) return;
      setState(() {
        _resultat = r;
        _phase = _Phase.fini;
        if (r.reussie) {
          _etape = EtapeRestauration.termine;
        } else {
          _echec = _etape;
        }
      });
    } catch (e) {
      // Fichier refusé ou sauvegarde de sécurité impossible : rien n'a été modifié.
      if (!mounted) return;
      setState(() {
        _phase = _Phase.refuse;
        _echec = _etape;
        _erreur = e is ErreurGesco ? e.message : '$e';
      });
    }
  }

  Future<void> _redemarrer() async {
    final gestion = _etat.gestionBase;
    if (gestion == null) return;
    setState(() => _redemarrage = true);
    try {
      await gestion.redemarrer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _redemarrage = false;
          _erreur = 'GESCO n\'a pas pu redémarrer ($e). Fermez GESCO puis relancez-le.';
        });
      }
      return;
    }
    // Dans l'application, l'interface entière est reconstruite : ce dialogue
    // n'existe plus. Dans un autre cadre, on le ferme.
    if (mounted) Navigator.of(context).pop();
  }

  _Statut _statut(EtapeRestauration e) {
    if (_echec == e) return _Statut.echec;
    final fini = _phase == _Phase.fini && (_resultat?.reussie ?? false);
    if (fini) return _Statut.fait;
    if (e.numero < _etape.numero) return _Statut.fait;
    if (e == _etape) return _Statut.enCours;
    return _Statut.aVenir;
  }

  bool get _occupe => _phase == _Phase.analyse || _phase == _Phase.execution || _redemarrage;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_occupe && _phase != _Phase.fini,
      child: AlertDialog(
        key: const Key('sauv_restauration'),
        title: const Text('Restaurer une sauvegarde'),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _etapes(),
                const SizedBox(height: 16),
                _corps(),
              ],
            ),
          ),
        ),
        actions: _actions(),
      ),
    );
  }

  Widget _etapes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in EtapeRestauration.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              key: Key('sauv_etape_${e.numero}'),
              children: [
                _iconeStatut(_statut(e)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${e.numero}. ${e.libelle}',
                    style: TextStyle(
                      fontWeight: _statut(e) == _Statut.enCours ? FontWeight.w700 : FontWeight.w400,
                      color: _statut(e) == _Statut.aVenir ? CouleursGesco.gris : CouleursGesco.texte,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _iconeStatut(_Statut s) => switch (s) {
        _Statut.fait => const Icon(Icons.check_circle, size: 18, color: CouleursGesco.vert),
        _Statut.echec => const Icon(Icons.cancel, size: 18, color: CouleursGesco.rouge),
        _Statut.enCours => const Icon(Icons.arrow_circle_right, size: 18, color: CouleursGesco.bleu),
        _Statut.aVenir => const Icon(Icons.circle_outlined, size: 18, color: CouleursGesco.gris),
      };

  Widget _corps() {
    switch (_phase) {
      case _Phase.analyse:
        return const Row(
          key: Key('sauv_analyse'),
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Contrôle du fichier de sauvegarde...'),
          ],
        );
      case _Phase.refuse:
        return _refus();
      case _Phase.apercu:
        return _apercuEtConfirmation();
      case _Phase.execution:
        return Column(
          key: const Key('sauv_execution'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text('${_etape.numero}. ${_etape.libelle}...'),
            const SizedBox(height: 4),
            const Text(
              'Ne fermez pas GESCO et ne débranchez pas l\'ordinateur.',
              style: TextStyle(color: CouleursGesco.orange),
            ),
          ],
        );
      case _Phase.fini:
        return _fin();
    }
  }

  Widget _refus() {
    final problemes = _apercu?.verification.problemes ?? const <String>[];
    return Container(
      key: const Key('sauv_refus'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CouleursGesco.rougeClair,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cette sauvegarde ne sera pas restaurée. Vos données actuelles n\'ont pas été modifiées.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_erreur != null) SelectableText(_erreur!, key: const Key('sauv_refus_message')),
          for (final (i, p) in problemes.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SelectableText(p, key: Key('sauv_refus_probleme_$i')),
            ),
        ],
      ),
    );
  }

  String _nombre(Map<String, int> contenu, List<String> cles) =>
      '${cles.fold<int>(0, (somme, c) => somme + (contenu[c] ?? 0))}';

  Widget _apercuEtConfirmation() {
    final a = _apercu!;
    final m = a.verification.manifeste!;
    final b = a.verification.base!;
    final lignes = <(String, String, String, String)>[
      ('creee', 'Créée le', dateHeureFr(m.creeLe), 'maintenant'),
      ('etablissement', 'Établissement', m.etablissement.isEmpty ? '—' : m.etablissement,
          a.actuelle.etablissement.isEmpty ? '—' : a.actuelle.etablissement),
      ('annee', 'Année scolaire active', m.annee.isEmpty ? '—' : m.annee,
          a.actuelle.annee.isEmpty ? '—' : a.actuelle.annee),
      ('eleves', 'Élèves', _nombre(b.contenu, ['eleves']), _nombre(a.actuelle.contenu, ['eleves'])),
      ('classes', 'Classes', _nombre(b.contenu, ['classes']), _nombre(a.actuelle.contenu, ['classes'])),
      ('enseignants', 'Enseignants', _nombre(b.contenu, ['enseignants']),
          _nombre(a.actuelle.contenu, ['enseignants'])),
      ('evaluations', 'Évaluations', _nombre(b.contenu, ['evaluations']),
          _nombre(a.actuelle.contenu, ['evaluations'])),
      ('notes', 'Notes saisies', _nombre(b.contenu, ['notes', 'notes_evaluations']),
          _nombre(a.actuelle.contenu, ['notes', 'notes_evaluations'])),
      ('comptes', 'Comptes utilisateurs', _nombre(b.contenu, ['comptes']),
          _nombre(a.actuelle.contenu, ['comptes'])),
    ];
    return Column(
      key: const Key('sauv_apercu'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Le fichier est valide : archive complète, empreinte SHA-256 exacte, base saine. '
          'Voici ce qui va changer :',
        ),
        const SizedBox(height: 8),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(2),
          },
          children: [
            const TableRow(
              children: [
                Padding(padding: EdgeInsets.all(4), child: Text('')),
                Padding(
                  padding: EdgeInsets.all(4),
                  child: Text('Cette sauvegarde', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: EdgeInsets.all(4),
                  child: Text('Données actuelles', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            for (final l in lignes)
              TableRow(
                children: [
                  Padding(padding: const EdgeInsets.all(4), child: Text(l.$2)),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(l.$3, key: Key('sauv_cmp_${l.$1}_sauvegarde')),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(l.$4, key: Key('sauv_cmp_${l.$1}_actuelle')),
                  ),
                ],
              ),
          ],
        ),
        if (a.avertissements.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            key: const Key('sauv_avertissements'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CouleursGesco.orangeClair,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, t) in a.avertissements.indexed)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
                    child: Text(t, key: Key('sauv_avertissement_$i')),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Avant de remplacer les données, GESCO en fait une sauvegarde de sécurité : '
          'elle restera dans l\'historique et pourra être restaurée à son tour. '
          'Les comptes et les permissions seront ceux de la sauvegarde : vous devrez vous reconnecter.',
          style: TextStyle(color: CouleursGesco.gris),
        ),
        CheckboxListTile(
          key: const Key('sauv_confirmer_case'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _confirme,
          onChanged: (v) => setState(() => _confirme = v ?? false),
          title: const Text(
            'Je comprends que les données actuelles seront remplacées par celles de cette sauvegarde.',
          ),
        ),
      ],
    );
  }

  Widget _fin() {
    final r = _resultat!;
    final couleur = r.reussie ? CouleursGesco.vertClair : CouleursGesco.rougeClair;
    return Container(
      key: const Key('sauv_fin'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(r.message, key: const Key('sauv_fin_message')),
          if (r.securite != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              'Sauvegarde de sécurité des données d\'avant : ${r.securite!.chemin}',
              key: const Key('sauv_fin_securite'),
              style: const TextStyle(color: CouleursGesco.gris),
            ),
          ],
          if (_erreur != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              _erreur!,
              key: const Key('sauv_fin_erreur'),
              style: const TextStyle(color: CouleursGesco.rouge),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _actions() {
    switch (_phase) {
      case _Phase.analyse:
      case _Phase.execution:
        return const [];
      case _Phase.refuse:
        return [
          TextButton(
            key: const Key('sauv_restaurer_fermer'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ];
      case _Phase.apercu:
        return [
          TextButton(
            key: const Key('sauv_restaurer_annuler'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('sauv_restaurer_lancer'),
            style: FilledButton.styleFrom(backgroundColor: CouleursGesco.rouge),
            onPressed: _confirme && _etat.gestionBase != null ? _lancer : null,
            child: const Text('Restaurer'),
          ),
        ];
      case _Phase.fini:
        final r = _resultat!;
        // Réussie ou annulée avec retour arrière : la base a été rouverte, on
        // repart dessus. Sinon, GESCO doit être relancé.
        final rouverte = r.reussie || r.retourArriere;
        if (rouverte) {
          return [
            FilledButton(
              key: const Key('sauv_restaurer_termine'),
              onPressed: _redemarrage ? null : _redemarrer,
              child: Text(r.reussie ? 'Redémarrer GESCO' : 'Continuer'),
            ),
          ];
        }
        return [
          FilledButton(
            key: const Key('sauv_restaurer_quitter'),
            onPressed: widget.quitter,
            child: const Text('Quitter GESCO'),
          ),
        ];
    }
  }
}
