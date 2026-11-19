import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/modeles_donnees.dart';
import '../../data/modeles_notation.dart';
import '../../domain/dates.dart';
import '../../domain/periodes.dart';
import '../commun/chargeur.dart';
import '../commun/choix.dart';
import '../commun/composants.dart';
import '../theme.dart';
import 'choix_classe.dart';

const int _taillePage = 50;

class _PageHistorique {
  const _PageHistorique({
    this.classes = const [],
    this.classe,
    this.matieres = const [],
    this.lignes = const [],
    this.total = 0,
  });

  final List<ClasseResume> classes;
  final ClasseResume? classe;
  final List<MatiereClasse> matieres;
  final List<EntreeHistoriqueNote> lignes;
  final int total;
}

/// Historique des notes d'une classe : qui a saisi, modifié ou supprimé
/// quelle note, quand, avec l'ancienne et la nouvelle valeur.
class VueHistorique extends StatefulWidget {
  const VueHistorique({
    super.key,
    required this.etat,
    required this.classeId,
    required this.surClasse,
  });

  final EtatApp etat;
  final int? classeId;
  final ValueChanged<int> surClasse;

  @override
  State<VueHistorique> createState() => _VueHistoriqueState();
}

class _VueHistoriqueState extends State<VueHistorique> {
  int? _matiereId;
  int? _mois;
  String? _source;
  int _page = 0;

  EtatApp get _etat => widget.etat;

  Future<_PageHistorique> _charger() async {
    final anneeId = _etat.anneeId;
    if (anneeId == null) return const _PageHistorique();
    final services = _etat.services;
    final classes = await services.classes.lister(anneeId);
    if (classes.isEmpty) return _PageHistorique(classes: classes);
    final choisie = classes.firstWhere(
      (c) => c.classe.id == widget.classeId,
      orElse: () => classes.first,
    );
    final id = choisie.classe.id;
    final matieres = await services.matieres.lister(id);
    final matiereId = matieres.any((m) => m.id == _matiereId) ? _matiereId : null;
    final total = await services.notes.compterHistorique(
      classeId: id,
      matiereId: matiereId,
      mois: _mois,
      source: _source,
    );
    final derniere = total == 0 ? 0 : (total - 1) ~/ _taillePage;
    final page = _page > derniere ? derniere : _page;
    final lignes = await services.notes.historique(
      classeId: id,
      matiereId: matiereId,
      mois: _mois,
      source: _source,
      limite: _taillePage,
      decalage: page * _taillePage,
    );
    return _PageHistorique(
      classes: classes,
      classe: choisie,
      matieres: matieres,
      lignes: lignes,
      total: total,
    );
  }

  void _filtrer(void Function() changement) => setState(() {
        changement();
        _page = 0;
      });

  @override
  Widget build(BuildContext context) {
    return Chargeur<_PageHistorique>(
      cle: (_etat.anneeId, widget.classeId, _matiereId, _mois, _source, _page, _etat.version),
      charger: _charger,
      builder: _contenu,
    );
  }

  Widget _contenu(BuildContext context, _PageHistorique d) {
    final classe = d.classe;
    if (_etat.anneeCourante == null || classe == null) {
      return const MessageVide(
        'Aucune classe pour cette année scolaire : l\'historique des notes est vide.',
        icone: Icons.history,
      );
    }
    final pages = d.total == 0 ? 1 : ((d.total - 1) ~/ _taillePage) + 1;
    final page = _page >= pages ? pages - 1 : _page;
    final matiereFiltre = d.matieres.any((m) => m.id == _matiereId) ? _matiereId : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: CouleursGesco.bordure)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: Wrap(
            spacing: 16,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoixClasse(
                classes: d.classes,
                classeId: classe.classe.id,
                surClasse: (id) {
                  _filtrer(() {
                    _matiereId = null;
                    _mois = null;
                    _source = null;
                  });
                  widget.surClasse(id);
                },
              ),
              SizedBox(
                width: 210,
                child: ChoixListe<int?>(
                  cleChamp: const Key('histo_filtre_matiere'),
                  libelle: 'Matière',
                  valeur: matiereFiltre,
                  options: [
                    (null, 'Toutes les matières'),
                    for (final m in d.matieres) (m.id, m.nom),
                  ],
                  onChanged: (id) => _filtrer(() => _matiereId = id),
                ),
              ),
              SizedBox(
                width: 170,
                child: ChoixListe<int?>(
                  cleChamp: const Key('histo_filtre_mois'),
                  libelle: 'Mois',
                  valeur: _mois,
                  options: [
                    (null, 'Tous les mois'),
                    for (final m in moisScolaires) (m, libelleMois(m)),
                  ],
                  onChanged: (m) => _filtrer(() => _mois = m),
                ),
              ),
              SizedBox(
                width: 200,
                child: ChoixListe<String?>(
                  cleChamp: const Key('histo_filtre_source'),
                  libelle: 'Type de note',
                  valeur: _source,
                  options: const [
                    (null, 'Toutes les notes'),
                    ('mensuelle', 'Notes du mois'),
                    ('evaluation', 'Évaluations'),
                  ],
                  onChanged: (s) => _filtrer(() => _source = s),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: d.lignes.isEmpty
              ? MessageVide(
                  _matiereId != null || _mois != null || _source != null
                      ? 'Aucune modification de note ne correspond à ces filtres.'
                      : 'Aucune note n\'a encore été saisie dans la classe '
                          '${classe.classe.nom}.',
                  icone: Icons.history,
                )
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      '${d.total} ${d.total > 1 ? 'modifications' : 'modification'} · '
                      'les plus récentes d\'abord',
                      key: const Key('histo_total'),
                      style: const TextStyle(color: CouleursGesco.gris),
                    ),
                    const SizedBox(height: 10),
                    Carte(
                      child: Column(
                        children: [
                          for (var i = 0; i < d.lignes.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            _LigneHistorique(entree: d.lignes[i]),
                          ],
                        ],
                      ),
                    ),
                    if (pages > 1) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            key: const Key('histo_precedent'),
                            onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
                            icon: const Icon(Icons.chevron_left),
                            label: const Text('Plus récentes'),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Page ${page + 1} / $pages',
                              key: const Key('histo_page'),
                            ),
                          ),
                          OutlinedButton.icon(
                            key: const Key('histo_suivant'),
                            onPressed:
                                page + 1 < pages ? () => setState(() => _page = page + 1) : null,
                            icon: const Icon(Icons.chevron_right),
                            label: const Text('Plus anciennes'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _LigneHistorique extends StatelessWidget {
  const _LigneHistorique({required this.entree});

  final EntreeHistoriqueNote entree;

  static String _dateHeure(String iso) {
    if (iso.length < 16) return iso;
    return '${formaterDateFr(iso.substring(0, 10))} ${iso.substring(11, 16)}';
  }

  @override
  Widget build(BuildContext context) {
    final e = entree;
    final couleur = switch (e.operation) {
      'suppression' => CouleursGesco.rouge,
      'creation' => CouleursGesco.vert,
      _ => CouleursGesco.bleu,
    };
    final qui = e.utilisateurNom.isEmpty ? 'Utilisateur inconnu' : e.utilisateurNom;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 40,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    e.eleveNom,
                    e.matiereNom,
                    e.nomMois,
                  ].where((t) => t.isNotEmpty).join(' · '),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${e.libelleOperation} (${e.libelleSource}) : '
                  '${e.ancienTexte} → ${e.nouveauTexte}',
                  style: TextStyle(color: couleur, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_dateHeure(e.dateHeure), style: const TextStyle(fontSize: 13)),
              Text(qui, style: const TextStyle(color: CouleursGesco.gris, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
