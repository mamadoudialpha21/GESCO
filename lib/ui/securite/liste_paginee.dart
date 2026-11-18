import 'package:flutter/material.dart';

import '../commun/chargeur.dart';
import '../commun/composants.dart';
import '../theme.dart';

/// Une page de résultats et le nombre total de lignes.
typedef PageResultats<T> = ({List<T> lignes, int total});

/// Liste avec recherche et pagination (50 lignes par page) pour les
/// journaux, qui peuvent compter des milliers d'entrées.
class ListePaginee<T> extends StatefulWidget {
  const ListePaginee({
    super.key,
    required this.titre,
    required this.sousTitre,
    required this.charger,
    required this.ligne,
    this.rechargerSur,
    this.vide = 'Aucune entrée.',
    this.taillePage = 50,
  });

  final String titre;
  final String sousTitre;

  /// Charge une page : [decalage] lignes ignorées, au plus [limite] lignes,
  /// filtrées par [recherche] (vide = tout).
  final Future<PageResultats<T>> Function(int limite, int decalage, String recherche)
      charger;
  final Widget Function(BuildContext context, T entree) ligne;

  /// Quand cette valeur change, la liste est rechargée.
  final Object? rechargerSur;
  final String vide;
  final int taillePage;

  @override
  State<ListePaginee<T>> createState() => _ListePagineeState<T>();
}

class _ListePagineeState<T> extends State<ListePaginee<T>> {
  final _recherche = TextEditingController();
  String _filtre = '';
  int _page = 0;
  int _rafraichir = 0;

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Chargeur<PageResultats<T>>(
      cle: (_filtre, _page, _rafraichir, widget.rechargerSur),
      charger: () => widget.charger(
        widget.taillePage,
        _page * widget.taillePage,
        _filtre,
      ),
      builder: (context, resultat) {
        final total = resultat.total;
        final pages = total == 0 ? 1 : ((total - 1) ~/ widget.taillePage) + 1;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TitreSection(widget.titre, sousTitre: widget.sousTitre),
                ),
                IconButton(
                  tooltip: 'Actualiser',
                  onPressed: () => setState(() => _rafraichir++),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('recherche_liste'),
              controller: _recherche,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => setState(() {
                _filtre = v.trim();
                _page = 0;
              }),
              decoration: champ('Rechercher').copyWith(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _filtre.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer la recherche',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _recherche.clear();
                          _filtre = '';
                          _page = 0;
                        }),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            if (resultat.lignes.isEmpty)
              SizedBox(
                height: 200,
                child: MessageVide(
                  _filtre.isEmpty ? widget.vide : 'Aucun résultat pour « $_filtre ».',
                  icone: Icons.history,
                ),
              )
            else
              Carte(
                child: Column(
                  children: [
                    for (var i = 0; i < resultat.lignes.length; i++) ...[
                      if (i > 0) const Divider(),
                      widget.ligne(context, resultat.lignes[i]),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '$total entrée${total > 1 ? 's' : ''} · page ${_page + 1}/$pages',
                  style: const TextStyle(color: CouleursGesco.gris),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('page_precedente'),
                  tooltip: 'Page précédente',
                  onPressed: _page > 0 ? () => setState(() => _page--) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  key: const Key('page_suivante'),
                  tooltip: 'Page suivante',
                  onPressed: _page + 1 < pages ? () => setState(() => _page++) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
