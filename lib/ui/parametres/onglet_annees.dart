import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/modeles_donnees.dart';
import '../../domain/periodes.dart';
import '../commun/chargeur.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../theme.dart';

/// Gestion des années scolaires : chaque année possède ses propres données.
class OngletAnnees extends StatelessWidget {
  const OngletAnnees({super.key, required this.etat});

  final EtatApp etat;

  Future<void> _creer(BuildContext context, List<AnneeScolaire> annees) async {
    final demande = await showDialog<_DemandeAnnee>(
      context: context,
      builder: (ctx) => _DialogueNouvelleAnnee(annees: annees),
    );
    if (demande == null || !context.mounted) return;
    final ok = await executer(
      context,
      () async {
        await etat.services.annees.creer(
          demande.libelle,
          copierDepuisAnneeId: demande.copierDepuis,
          activer: demande.activer,
        );
      },
      succes: 'Année scolaire « ${demande.libelle.trim()} » créée.',
    );
    if (ok) await etat.charger();
  }

  Future<void> _activer(BuildContext context, AnneeScolaire annee) async {
    final ok = await executer(
      context,
      () => etat.services.annees.activer(annee.id),
      succes: 'L\'année « ${annee.libelle} » est maintenant active.',
    );
    if (ok) await etat.charger();
  }

  Future<void> _supprimer(BuildContext context, AnneeScolaire annee) async {
    final oui = await confirmer(
      context,
      titre: 'Supprimer l\'année scolaire',
      message:
          'Supprimer l\'année « ${annee.libelle} » ? Seules les années vides '
          '(sans classe) peuvent être supprimées.',
      libelleConfirmer: 'Supprimer',
      danger: true,
    );
    if (!oui || !context.mounted) return;
    final ok = await executer(
      context,
      () => etat.services.annees.supprimer(annee.id),
      succes: 'Année « ${annee.libelle} » supprimée.',
    );
    if (ok) await etat.charger();
  }

  @override
  Widget build(BuildContext context) {
    return Chargeur<List<AnneeScolaire>>(
      cle: etat.version,
      charger: () => etat.services.annees.lister(),
      builder: (context, annees) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: TitreSection(
                    'Années scolaires',
                    sousTitre:
                        'Chaque année a ses propres classes, élèves et notes. '
                        'Les anciennes années sont toujours conservées et '
                        'consultables avec le sélecteur en haut de l\'écran.',
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: () => _creer(context, annees),
                  icon: const Icon(Icons.add),
                  label: const Text('Nouvelle année'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (annees.isEmpty)
              const SizedBox(
                height: 240,
                child: MessageVide(
                  'Aucune année scolaire. Créez la première année pour commencer.',
                  icone: Icons.event_outlined,
                ),
              ),
            for (final annee in annees)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event, color: CouleursGesco.bleu),
                  title: Row(
                    children: [
                      Text(
                        annee.libelle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (annee.active)
                        const Etiquette(
                          'Active',
                          couleur: CouleursGesco.vert,
                          fond: CouleursGesco.vertClair,
                        )
                      else
                        const Etiquette(
                          'Consultation',
                          couleur: CouleursGesco.gris,
                          fond: CouleursGesco.grisClair,
                        ),
                      if (annee.id == etat.anneeId) ...[
                        const SizedBox(width: 8),
                        const Etiquette(
                          'Affichée',
                          couleur: CouleursGesco.bleu,
                          fond: CouleursGesco.bleuClair,
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text('Créée le ${_dateCourte(annee.creeLe)}'),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      if (annee.id != etat.anneeId)
                        TextButton(
                          onPressed: () => etat.choisirAnnee(annee.id),
                          child: const Text('Afficher'),
                        ),
                      if (!annee.active)
                        OutlinedButton(
                          onPressed: () => _activer(context, annee),
                          child: const Text('Rendre active'),
                        ),
                      if (!annee.active)
                        IconButton(
                          tooltip: 'Supprimer (année vide uniquement)',
                          onPressed: () => _supprimer(context, annee),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: CouleursGesco.rouge,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// « 2026-10-01T08:00:00.000Z » -> « 01/10/2026 ».
  static String _dateCourte(String iso) {
    final partie = iso.length >= 10 ? iso.substring(0, 10) : iso;
    final morceaux = partie.split('-');
    if (morceaux.length != 3) return iso;
    return '${morceaux[2]}/${morceaux[1]}/${morceaux[0]}';
  }
}

class _DemandeAnnee {
  const _DemandeAnnee({
    required this.libelle,
    required this.copierDepuis,
    required this.activer,
  });

  final String libelle;
  final int? copierDepuis;
  final bool activer;
}

class _DialogueNouvelleAnnee extends StatefulWidget {
  const _DialogueNouvelleAnnee({required this.annees});

  final List<AnneeScolaire> annees;

  @override
  State<_DialogueNouvelleAnnee> createState() => _DialogueNouvelleAnneeState();
}

class _DialogueNouvelleAnneeState extends State<_DialogueNouvelleAnnee> {
  late final TextEditingController _libelle;
  bool _copier = false;
  int? _source;
  bool _activer = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    final derniere = widget.annees.isEmpty ? null : widget.annees.first.libelle;
    _libelle = TextEditingController(
      text: proposerAnneeSuivante(derniere, DateTime.now()),
    );
    if (widget.annees.isNotEmpty) {
      _source = widget.annees.first.id;
      _copier = true;
    }
  }

  @override
  void dispose() {
    _libelle.dispose();
    super.dispose();
  }

  void _valider() {
    final libelle = _libelle.text.trim();
    if (libelle.isEmpty) {
      setState(() => _erreur = 'Le libellé est obligatoire (ex. 2026-2027).');
      return;
    }
    Navigator.of(context).pop(
      _DemandeAnnee(
        libelle: libelle,
        copierDepuis: _copier ? _source : null,
        activer: _activer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aDesAnnees = widget.annees.isNotEmpty;
    return AlertDialog(
      title: const Text('Nouvelle année scolaire'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _libelle,
              autofocus: true,
              decoration: champ('Année scolaire', aide: 'Exemple : 2026-2027', erreur: _erreur),
              onSubmitted: (_) => _valider(),
            ),
            if (aDesAnnees) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _copier,
                onChanged: (v) => setState(() => _copier = v ?? false),
                title: const Text(
                  'Reprendre les classes, matières, coefficients et seuils d\'une année existante',
                ),
                subtitle: const Text(
                  'Les élèves et les notes ne sont jamais copiés.',
                ),
              ),
              if (_copier)
                Padding(
                  padding: const EdgeInsets.only(left: 40),
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _source,
                    items: [
                      for (final a in widget.annees)
                        DropdownMenuItem<int>(value: a.id, child: Text(a.libelle)),
                    ],
                    onChanged: (id) => setState(() => _source = id),
                  ),
                ),
            ],
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _activer,
              onChanged: (v) => setState(() => _activer = v ?? false),
              title: const Text('Rendre cette année active'),
              subtitle: aDesAnnees
                  ? const Text('Elle s\'ouvrira par défaut au démarrage.')
                  : const Text('La première année est toujours active.'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _valider, child: const Text('Créer')),
      ],
    );
  }
}
