import 'package:flutter/material.dart';

import '../../data/depots/appreciation_depot.dart';
import '../../data/modeles_donnees.dart';
import '../commun/composants.dart';
import '../theme.dart';

/// Appréciations d'un élève dans chaque matière pour une période.
///
/// Retourne les seuls textes modifiés (matière -> texte, vide pour effacer),
/// ou null si l'utilisateur annule ou ne change rien.
class DialogueAppreciationsMatieres extends StatefulWidget {
  const DialogueAppreciationsMatieres({
    super.key,
    required this.eleveNom,
    required this.periodeLibelle,
    required this.matieres,
    required this.textes,
    this.propositions = const {},
    this.lectureSeule = false,
  });

  final String eleveNom;
  final String periodeLibelle;
  final List<MatiereClasse> matieres;

  /// Appréciations déjà enregistrées (matière -> texte).
  final Map<int, String> textes;

  /// Appréciations rédigées automatiquement (matière -> texte), affichées en
  /// grisé dans les champs vides : elles figurent sur le bulletin tant que le
  /// champ reste vide.
  final Map<int, String> propositions;
  final bool lectureSeule;

  @override
  State<DialogueAppreciationsMatieres> createState() =>
      _DialogueAppreciationsMatieresState();
}

class _DialogueAppreciationsMatieresState extends State<DialogueAppreciationsMatieres> {
  late final Map<int, TextEditingController> _controleurs;

  @override
  void initState() {
    super.initState();
    _controleurs = {
      for (final m in widget.matieres)
        m.id: TextEditingController(text: widget.textes[m.id] ?? ''),
    };
  }

  @override
  void dispose() {
    for (final c in _controleurs.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Recopie les propositions dans les champs vides, pour les modifier.
  void _utiliserPropositions() {
    for (final m in widget.matieres) {
      final c = _controleurs[m.id]!;
      final proposition = widget.propositions[m.id];
      if (c.text.trim().isEmpty && proposition != null) c.text = proposition;
    }
    setState(() {});
  }

  bool get _propositionsUtilisables =>
      !widget.lectureSeule &&
      widget.matieres.any((m) =>
          widget.propositions[m.id] != null && _controleurs[m.id]!.text.trim().isEmpty);

  void _valider() {
    final modifies = <int, String>{};
    for (final m in widget.matieres) {
      final nouveau = _controleurs[m.id]!.text.trim();
      if (nouveau != (widget.textes[m.id] ?? '').trim()) modifies[m.id] = nouveau;
    }
    Navigator.of(context).pop(modifies.isEmpty ? null : modifies);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Appréciations par matière'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.eleveNom} · ${widget.periodeLibelle}'),
            if (widget.propositions.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Text(
                'Texte grisé : appréciation automatique, utilisée sur le bulletin '
                'tant que le champ reste vide.',
                style: TextStyle(color: CouleursGesco.gris),
              ),
              if (_propositionsUtilisables)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('appr_matieres_utiliser'),
                    onPressed: _utiliserPropositions,
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('Utiliser les propositions'),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final m in widget.matieres)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          key: Key('appr_matiere_${m.id}'),
                          controller: _controleurs[m.id],
                          readOnly: widget.lectureSeule,
                          maxLines: 2,
                          minLines: 1,
                          maxLength: AppreciationDepot.longueurMaxMatiere,
                          onChanged: (_) => setState(() {}),
                          decoration: champ(m.nom).copyWith(
                            counterText: '',
                            hintText: widget.propositions[m.id],
                            // Sans cela, le texte grisé n'apparaît qu'au clic.
                            floatingLabelBehavior: widget.propositions[m.id] == null
                                ? null
                                : FloatingLabelBehavior.always,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.lectureSeule ? 'Fermer' : 'Annuler'),
        ),
        if (!widget.lectureSeule)
          FilledButton(
            key: const Key('enregistrer_appr_matieres'),
            onPressed: _valider,
            child: const Text('Enregistrer'),
          ),
      ],
    );
  }
}
