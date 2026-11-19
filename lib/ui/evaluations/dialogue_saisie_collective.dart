import 'package:flutter/material.dart';

import '../../data/modeles_donnees.dart';
import '../../data/modeles_notation.dart';
import '../../domain/arrondi.dart';
import '../../domain/modeles.dart';
import '../../domain/periodes.dart';
import '../../domain/saisie_note.dart';
import '../commun/composants.dart';
import '../theme.dart';

/// Saisie collective : les notes de toute la classe pour une évaluation.
///
/// Retourne les seules notes modifiées (inscription -> note, null pour
/// effacer), ou null si l'utilisateur annule ou ne change rien.
class DialogueSaisieCollective extends StatefulWidget {
  const DialogueSaisieCollective({
    super.key,
    required this.evaluation,
    required this.matiereNom,
    required this.eleves,
    required this.notes,
    this.motifLecture,
  });

  final Evaluation evaluation;
  final String matiereNom;

  /// Élèves qui suivent la classe, dans l'ordre d'affichage.
  final List<EleveInscrit> eleves;

  /// Notes déjà enregistrées (inscription -> note), sur le barème de l'évaluation.
  final Map<int, Saisie> notes;

  /// Si non nul, les notes ne sont pas modifiables : explication affichée.
  final String? motifLecture;

  @override
  State<DialogueSaisieCollective> createState() => _DialogueSaisieCollectiveState();
}

class _DialogueSaisieCollectiveState extends State<DialogueSaisieCollective> {
  late final List<TextEditingController> _controleurs;
  late final List<FocusNode> _focus;
  final Map<int, String> _erreurs = {};
  String? _resume;

  int get _bareme => widget.evaluation.bareme;
  bool get _lecture => widget.motifLecture != null;

  @override
  void initState() {
    super.initState();
    _controleurs = [
      for (final e in widget.eleves)
        TextEditingController(text: _texte(widget.notes[e.inscriptionId])),
    ];
    _focus = [for (final _ in widget.eleves) FocusNode()];
  }

  @override
  void dispose() {
    for (final c in _controleurs) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    super.dispose();
  }

  String _texte(Saisie? s) => texteSaisie(s);

  void _suivant(int i) {
    if (i + 1 < _focus.length) {
      _focus[i + 1].requestFocus();
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  void _enregistrer() {
    final modifiees = <int, Saisie?>{};
    final erreurs = <int, String>{};
    for (var i = 0; i < widget.eleves.length; i++) {
      final id = widget.eleves[i].inscriptionId;
      final lecture = lireNoteSaisie(_controleurs[i].text, bareme: _bareme);
      if (lecture.estInvalide) {
        erreurs[id] = lecture.erreur!;
        continue;
      }
      final avant = widget.notes[id];
      final apres = lecture.saisie;
      if (apres != avant) modifiees[id] = apres;
    }
    setState(() {
      _erreurs
        ..clear()
        ..addAll(erreurs);
      _resume = erreurs.isEmpty
          ? null
          : '${erreurs.length > 1 ? '${erreurs.length} notes sont' : '1 note est'} '
              'invalide${erreurs.length > 1 ? 's' : ''} : corrigez-${erreurs.length > 1 ? 'les' : 'la'} '
              'avant d\'enregistrer.';
    });
    if (erreurs.isNotEmpty) return;
    if (modifiees.isEmpty) {
      setState(() => _resume = 'Aucune note n\'a changé.');
      return;
    }
    Navigator.of(context).pop(modifiees);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.evaluation;
    final remplies = _controleurs.where((c) => c.text.trim().isNotEmpty).length;
    return AlertDialog(
      title: Text(e.titre),
      content: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.matiereNom} · ${libelleMois(e.mois)} · notes sur ${e.bareme}'
              ' · coef ${formaterCoefficient(e.coefficient)}',
              style: const TextStyle(color: CouleursGesco.gris),
            ),
            const SizedBox(height: 4),
            Text(
              _lecture
                  ? widget.motifLecture!
                  : 'Note de 0 à ${e.bareme} (virgule ou point), A = absent, '
                      'D = dispensé, vide = pas encore saisie. Entrée passe à '
                      'l\'élève suivant.',
              key: const Key('aide_saisie_collective'),
              style: TextStyle(
                color: _lecture ? CouleursGesco.orange : CouleursGesco.gris,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: widget.eleves.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final el = widget.eleves[i];
                  final erreur = _erreurs[el.inscriptionId];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 30,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(color: CouleursGesco.gris),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              el.nomComplet,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: erreur == null ? 110 : 250,
                          child: TextField(
                            key: Key('note_${el.inscriptionId}'),
                            controller: _controleurs[i],
                            focusNode: _focus[i],
                            enabled: !_lecture,
                            textAlign: TextAlign.center,
                            decoration: champ('/ ${e.bareme}', erreur: erreur),
                            onChanged: (_) => setState(() {
                              _erreurs.remove(el.inscriptionId);
                            }),
                            onSubmitted: (_) => _suivant(i),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _resume ??
                  '$remplies / ${widget.eleves.length} élèves ont une note ou un état.',
              key: const Key('resume_saisie_collective'),
              style: TextStyle(
                color: _erreurs.isEmpty ? CouleursGesco.gris : CouleursGesco.rouge,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_lecture ? 'Fermer' : 'Annuler'),
        ),
        if (!_lecture)
          FilledButton(
            key: const Key('enregistrer_notes'),
            onPressed: _enregistrer,
            child: const Text('Enregistrer les notes'),
          ),
      ],
    );
  }
}
