import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/depots/note_depot.dart';
import '../../data/modeles_donnees.dart';
import '../../domain/modeles.dart';
import '../commun/chargeur.dart';
import '../commun/composants.dart';
import '../theme.dart';
import 'grille_notes.dart';
import 'periode.dart';

class _DonneesNotes {
  const _DonneesNotes({
    this.classes = const [],
    this.classe,
    this.matieres = const [],
    this.eleves = const [],
    this.saisies = const {},
    this.config = ConfigResultats.defaut,
  });

  final List<ClasseResume> classes;
  final ClasseResume? classe;
  final List<MatiereClasse> matieres;
  final List<EleveInscrit> eleves;
  final SaisiesClasse saisies;
  final ConfigResultats config;
}

/// Saisie des notes : choix de la classe et de la période, puis tableau
/// élèves × matières avec enregistrement automatique.
class PageNotes extends StatefulWidget {
  const PageNotes({
    super.key,
    required this.etat,
    required this.allerAuxParametres,
    required this.allerAuxInscriptions,
    this.maintenant,
  });

  final EtatApp etat;
  final VoidCallback allerAuxParametres;
  final VoidCallback allerAuxInscriptions;

  /// Horloge (pour les tests) : détermine le mois proposé au départ.
  final DateTime Function()? maintenant;

  @override
  State<PageNotes> createState() => _PageNotesState();
}

class _PageNotesState extends State<PageNotes> {
  int? _classeId;
  late Periode _periode;

  EtatApp get _etat => widget.etat;

  @override
  void initState() {
    super.initState();
    _periode = Periode.moisDe((widget.maintenant ?? DateTime.now)());
  }

  Future<_DonneesNotes> _charger() async {
    final anneeId = _etat.anneeId;
    if (anneeId == null) return const _DonneesNotes();
    final services = _etat.services;
    final classes = await services.classes.lister(anneeId);
    if (classes.isEmpty) return _DonneesNotes(classes: classes);

    final choisie = classes.firstWhere(
      (c) => c.classe.id == _classeId,
      orElse: () => classes.first,
    );
    final id = choisie.classe.id;
    return _DonneesNotes(
      classes: classes,
      classe: choisie,
      matieres: await services.matieres.lister(id),
      eleves: await services.eleves.lister(anneeId, classeId: id),
      saisies: await services.notes.lireClasse(id),
      config: await services.configs.lire(anneeId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Chargeur<_DonneesNotes>(
      cle: (_etat.anneeId, _classeId, _etat.version),
      charger: _charger,
      builder: _contenu,
    );
  }

  Widget _contenu(BuildContext context, _DonneesNotes d) {
    if (_etat.anneeCourante == null) {
      return _Vide(
        message: 'Aucune année scolaire. Créez-en une dans les paramètres '
            'avant de saisir des notes.',
        libelleBouton: 'Ouvrir les paramètres',
        icone: Icons.settings,
        onPressed: widget.allerAuxParametres,
      );
    }
    final classe = d.classe;
    if (classe == null) {
      return _Vide(
        message: 'Aucune classe pour cette année scolaire. Créez une classe, '
            'ses matières et ses coefficients dans les paramètres.',
        libelleBouton: 'Ouvrir les paramètres',
        icone: Icons.settings,
        onPressed: widget.allerAuxParametres,
      );
    }

    final haut = _Selection(
      classes: d.classes,
      classeId: classe.classe.id,
      nbEleves: d.eleves.length,
      nbMatieres: d.matieres.length,
      periode: _periode,
      surClasse: (id) => setState(() => _classeId = id),
      surPeriode: (p) => setState(() => _periode = p),
    );

    Widget corps;
    if (d.matieres.isEmpty) {
      corps = _Vide(
        message: 'La classe ${classe.classe.nom} n\'a aucune matière. Ajoutez '
            'ses matières et leurs coefficients dans les paramètres.',
        libelleBouton: 'Ouvrir les paramètres',
        icone: Icons.settings,
        onPressed: widget.allerAuxParametres,
      );
    } else if (d.eleves.isEmpty) {
      corps = _Vide(
        message: 'Aucun élève n\'est inscrit dans la classe '
            '${classe.classe.nom} pour cette année scolaire.',
        libelleBouton: 'Inscrire des élèves',
        icone: Icons.person_add_alt_1,
        onPressed: widget.allerAuxInscriptions,
      );
    } else {
      corps = GrilleNotes(
        // Nouvelle grille à chaque rechargement des données.
        key: ObjectKey(d),
        enregistrer: _etat.services.notes.enregistrer,
        matieres: d.matieres,
        eleves: d.eleves,
        saisies: d.saisies,
        config: d.config,
        periode: _periode,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [haut, Expanded(child: corps)],
    );
  }
}

/// Choix de la classe et de la période.
class _Selection extends StatelessWidget {
  const _Selection({
    required this.classes,
    required this.classeId,
    required this.nbEleves,
    required this.nbMatieres,
    required this.periode,
    required this.surClasse,
    required this.surPeriode,
  });

  final List<ClasseResume> classes;
  final int classeId;
  final int nbEleves;
  final int nbMatieres;
  final Periode periode;
  final ValueChanged<int> surClasse;
  final ValueChanged<Periode> surPeriode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: CouleursGesco.bordure)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: InputDecorator(
                  decoration: champ('Classe'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      key: const Key('choix_classe'),
                      isExpanded: true,
                      isDense: true,
                      value: classeId,
                      items: [
                        for (final c in classes)
                          DropdownMenuItem<int>(
                            value: c.classe.id,
                            child: Text(c.classe.nom),
                          ),
                      ],
                      onChanged: (id) {
                        if (id != null) surClasse(id);
                      },
                    ),
                  ),
                ),
              ),
              Text(
                '${nbEleves > 1 ? '$nbEleves élèves' : '$nbEleves élève'}'
                '  ·  ${nbMatieres > 1 ? '$nbMatieres matières' : '$nbMatieres matière'}',
                style: const TextStyle(color: CouleursGesco.gris),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in periodesAffichees)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      key: Key('periode_${p.cle}'),
                      label: Text(p.libelle),
                      selected: p == periode,
                      showCheckmark: false,
                      selectedColor: CouleursGesco.bleu,
                      backgroundColor: p.saisissable
                          ? Colors.white
                          : CouleursGesco.bleuClair,
                      labelStyle: TextStyle(
                        color: p == periode ? Colors.white : CouleursGesco.texte,
                        fontWeight: p.saisissable ? FontWeight.w500 : FontWeight.w700,
                      ),
                      onSelected: (_) => surPeriode(p),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Vide extends StatelessWidget {
  const _Vide({
    required this.message,
    required this.libelleBouton,
    required this.icone,
    required this.onPressed,
  });

  final String message;
  final String libelleBouton;
  final IconData icone;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MessageVide(message, icone: Icons.edit_note),
          FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icone),
            label: Text(libelleBouton),
          ),
        ],
      ),
    );
  }
}
