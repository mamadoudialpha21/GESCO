import 'package:flutter/material.dart';

import '../../data/depots/appreciation_depot.dart';
import '../../data/modeles_donnees.dart';
import '../commun/composants.dart';

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
    this.lectureSeule = false,
  });

  final String eleveNom;
  final String periodeLibelle;
  final List<MatiereClasse> matieres;

  /// Appréciations déjà enregistrées (matière -> texte).
  final Map<int, String> textes;
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
                          decoration: champ(m.nom).copyWith(counterText: ''),
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
