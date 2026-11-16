import 'package:flutter/material.dart';

import '../../data/modeles_donnees.dart';
import '../../domain/recherche.dart';
import '../commun/composants.dart';
import '../theme.dart';

/// Résultat du dialogue : les élèves à réinscrire et leur classe.
class ChoixReinscription {
  const ChoixReinscription(this.eleveIds, this.classeId);

  final List<int> eleveIds;
  final int classeId;
}

/// Réinscrit dans l'année courante des élèves déjà enregistrés (par exemple
/// ceux de l'année précédente), sans ressaisir leur fiche.
class DialogueReinscription extends StatefulWidget {
  const DialogueReinscription({
    super.key,
    required this.candidats,
    required this.classes,
    this.classeInitiale,
  });

  /// Élèves connus, pas encore inscrits pour l'année.
  final List<Eleve> candidats;

  /// Classes de l'année courante (au moins une).
  final List<Classe> classes;

  final int? classeInitiale;

  @override
  State<DialogueReinscription> createState() => _DialogueReinscriptionState();
}

class _DialogueReinscriptionState extends State<DialogueReinscription> {
  final TextEditingController _recherche = TextEditingController();
  final Set<int> _choisis = <int>{};
  late int _classeId;

  @override
  void initState() {
    super.initState();
    final initiale = widget.classeInitiale;
    final existe = widget.classes.any((c) => c.id == initiale);
    _classeId = (existe && initiale != null) ? initiale : widget.classes.first.id;
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  List<Eleve> get _visibles => [
        for (final e in widget.candidats)
          if (correspondRecherche(_recherche.text, [e.nom, e.prenom, e.matricule])) e,
      ];

  void _toutBasculer(List<Eleve> visibles) {
    final tousChoisis = visibles.isNotEmpty && visibles.every((e) => _choisis.contains(e.id));
    setState(() {
      for (final e in visibles) {
        if (tousChoisis) {
          _choisis.remove(e.id);
        } else {
          _choisis.add(e.id);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _visibles;
    final tousChoisis = visibles.isNotEmpty && visibles.every((e) => _choisis.contains(e.id));
    final n = _choisis.length;

    return AlertDialog(
      title: const Text('Réinscrire des élèves déjà enregistrés'),
      content: SizedBox(
        width: 560,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choisissez la classe de cette année, puis cochez les élèves à '
              'réinscrire. Leur fiche est conservée ; les notes des années '
              'précédentes ne sont pas modifiées.',
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: champ('Classe de destination'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  key: const Key('liste_classe_reinscription'),
                  isExpanded: true,
                  isDense: true,
                  value: _classeId,
                  items: [
                    for (final c in widget.classes)
                      DropdownMenuItem<int>(value: c.id, child: Text(c.nom)),
                  ],
                  onChanged: (id) {
                    if (id != null) setState(() => _classeId = id);
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('recherche_reinscription'),
              controller: _recherche,
              decoration: champ('Rechercher par nom, prénom ou matricule').copyWith(
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton(
                  onPressed: visibles.isEmpty ? null : () => _toutBasculer(visibles),
                  child: Text(
                    tousChoisis ? 'Tout désélectionner' : 'Tout sélectionner',
                  ),
                ),
                const Spacer(),
                Text(
                  '${visibles.length} affiché${visibles.length > 1 ? 's' : ''} · '
                  '$n sélectionné${n > 1 ? 's' : ''}',
                  style: const TextStyle(color: CouleursGesco.gris),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: visibles.isEmpty
                  ? const MessageVide('Aucun élève ne correspond à la recherche.')
                  : ListView.builder(
                      itemCount: visibles.length,
                      itemBuilder: (context, index) {
                        final e = visibles[index];
                        return CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _choisis.contains(e.id),
                          onChanged: (coche) => setState(() {
                            if (coche == true) {
                              _choisis.add(e.id);
                            } else {
                              _choisis.remove(e.id);
                            }
                          }),
                          title: Text(e.nomComplet),
                          subtitle: Text('Matricule ${e.matricule}'),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: n == 0
              ? null
              : () => Navigator.of(context).pop(
                    ChoixReinscription(_choisis.toList(), _classeId),
                  ),
          child: Text(n == 0 ? 'Réinscrire' : 'Réinscrire ($n)'),
        ),
      ],
    );
  }
}
