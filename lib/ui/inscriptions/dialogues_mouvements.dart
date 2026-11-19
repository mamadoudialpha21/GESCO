import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/modeles_donnees.dart';
import '../../domain/dates.dart';
import '../commun/chargeur.dart';
import '../commun/composants.dart';
import '../theme.dart';

/// Départ ou abandon d'un élève.
class ChoixSortie {
  const ChoixSortie({required this.statut, required this.motif, required this.date});

  final StatutInscription statut;
  final String motif;
  final DateTime date;
}

/// Demande le type de sortie (départ ou abandon), la date et le motif.
class DialogueSortie extends StatefulWidget {
  const DialogueSortie({super.key, required this.nomEleve});

  final String nomEleve;

  @override
  State<DialogueSortie> createState() => _DialogueSortieState();
}

class _DialogueSortieState extends State<DialogueSortie> {
  StatutInscription _statut = StatutInscription.depart;
  final TextEditingController _motif = TextEditingController();
  late final TextEditingController _date =
      TextEditingController(text: dateVersFr(DateTime.now()));
  String? _erreurDate;

  @override
  void dispose() {
    _motif.dispose();
    _date.dispose();
    super.dispose();
  }

  void _valider() {
    final date = analyserDateFr(_date.text);
    if (date == null) {
      setState(() => _erreurDate = 'Date invalide (format jj/mm/aaaa).');
      return;
    }
    Navigator.of(context).pop(
      ChoixSortie(statut: _statut, motif: _motif.text.trim(), date: date),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Départ ou abandon'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.nomEleve} ne sera plus compté dans les effectifs, les '
                'classements ni les statistiques. Ses notes sont conservées et '
                'il pourra être repris à tout moment.',
              ),
              const SizedBox(height: 12),
              RadioListTile<StatutInscription>(
                contentPadding: EdgeInsets.zero,
                value: StatutInscription.depart,
                groupValue: _statut,
                onChanged: (v) => setState(() => _statut = v ?? _statut),
                title: const Text('Départ (transfert vers un autre établissement, déménagement...)'),
              ),
              RadioListTile<StatutInscription>(
                contentPadding: EdgeInsets.zero,
                value: StatutInscription.abandon,
                groupValue: _statut,
                onChanged: (v) => setState(() => _statut = v ?? _statut),
                title: const Text('Abandon des études'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('champ_date_sortie'),
                controller: _date,
                decoration: champ('Date de sortie', aide: 'jj/mm/aaaa', erreur: _erreurDate),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('champ_motif_sortie'),
                controller: _motif,
                decoration: champ('Motif (facultatif)'),
                maxLength: 200,
                onSubmitted: (_) => _valider(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('bouton_valider_sortie'),
          onPressed: _valider,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

/// Classe d'arrivée et motif d'un transfert.
class ChoixTransfert {
  const ChoixTransfert({required this.classeId, required this.motif});

  final int classeId;
  final String motif;
}

/// Demande la classe d'arrivée d'un transfert. Les notes mensuelles suivent
/// l'élève quand la matière existe dans la nouvelle classe.
class DialogueTransfert extends StatefulWidget {
  const DialogueTransfert({
    super.key,
    required this.nomEleve,
    required this.classeActuelleId,
    required this.classes,
    required this.nbNotes,
  });

  final String nomEleve;
  final int classeActuelleId;
  final List<ClasseResume> classes;
  final int nbNotes;

  @override
  State<DialogueTransfert> createState() => _DialogueTransfertState();
}

class _DialogueTransfertState extends State<DialogueTransfert> {
  late final List<ClasseResume> _autres = [
    for (final c in widget.classes)
      if (c.classe.id != widget.classeActuelleId) c,
  ];
  late int? _classeId = _autres.isEmpty ? null : _autres.first.classe.id;
  final TextEditingController _motif = TextEditingController();

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Transférer dans une autre classe'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_autres.isEmpty)
                const Text('Il n\'y a pas d\'autre classe dans cette année scolaire.')
              else ...[
                Text(
                  widget.nbNotes == 0
                      ? '${widget.nomEleve} n\'a pas encore de notes : le changement est immédiat.'
                      : '${widget.nomEleve} a ${widget.nbNotes} '
                          '${widget.nbNotes > 1 ? 'notes' : 'note'}. Les notes mensuelles '
                          'sont reportées sur la matière de même nom de la nouvelle '
                          'classe ; celles qui n\'ont pas d\'équivalent (et les notes '
                          'd\'évaluation) ne peuvent pas suivre : une confirmation '
                          'sera demandée avant de les supprimer.',
                ),
                const SizedBox(height: 16),
                InputDecorator(
                  decoration: champ('Nouvelle classe'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      key: const Key('choix_classe_transfert'),
                      isExpanded: true,
                      isDense: true,
                      value: _classeId,
                      items: [
                        for (final c in _autres)
                          DropdownMenuItem<int>(
                            value: c.classe.id,
                            child: Text(
                              '${c.classe.nom} (${c.nbActifs}'
                              '${c.classe.capacite == null ? '' : ' / ${c.classe.capacite}'})',
                            ),
                          ),
                      ],
                      onChanged: (id) => setState(() => _classeId = id),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _motif,
                  decoration: champ('Motif (facultatif)'),
                  maxLength: 200,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('bouton_valider_transfert'),
          onPressed: _classeId == null
              ? null
              : () => Navigator.of(context).pop(
                    ChoixTransfert(classeId: _classeId!, motif: _motif.text.trim()),
                  ),
          child: const Text('Transférer'),
        ),
      ],
    );
  }
}

/// Historique des mouvements d'inscription de l'année affichée (ou d'un seul
/// élève si [eleveId] est donné).
class DialogueMouvements extends StatelessWidget {
  const DialogueMouvements({super.key, required this.etat, this.eleveId, this.titre});

  final EtatApp etat;
  final int? eleveId;
  final String? titre;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text(
                titre ?? 'Mouvements d\'inscription',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: Chargeur<List<MouvementInscription>>(
                cle: (etat.anneeId, etat.version, eleveId),
                charger: () => etat.services.eleves.mouvements(
                  eleveId: eleveId,
                  anneeId: eleveId == null ? etat.anneeId : null,
                  limite: 500,
                ),
                builder: (context, liste) {
                  if (liste.isEmpty) {
                    return const MessageVide(
                      'Aucun mouvement enregistré.',
                      icone: Icons.swap_horiz,
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: liste.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, i) => _LigneMouvement(
                      mouvement: liste[i],
                      avecEleve: eleveId == null,
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fermer'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LigneMouvement extends StatelessWidget {
  const _LigneMouvement({required this.mouvement, required this.avecEleve});

  final MouvementInscription mouvement;
  final bool avecEleve;

  String get _detail {
    final m = mouvement;
    final morceaux = <String>[
      if (avecEleve && m.eleveNom.isNotEmpty) m.eleveNom,
      if (!avecEleve && m.anneeLibelle.isNotEmpty) m.anneeLibelle,
      if (m.classeOrigineNom.isNotEmpty && m.classeDestinationNom.isNotEmpty)
        '${m.classeOrigineNom} → ${m.classeDestinationNom}'
      else if (m.classeDestinationNom.isNotEmpty)
        m.classeDestinationNom
      else if (m.classeOrigineNom.isNotEmpty)
        m.classeOrigineNom,
      if (m.motif.isNotEmpty) m.motif,
      if (m.utilisateur.isNotEmpty) 'par ${m.utilisateur}',
    ];
    return morceaux.join(' · ');
  }

  static String _date(String iso) {
    final partie = iso.length >= 10 ? iso.substring(0, 10) : iso;
    return formaterDateFr(partie);
  }

  Color get _couleur => switch (mouvement.type) {
        'depart' || 'abandon' => CouleursGesco.orange,
        'reprise' => CouleursGesco.vert,
        _ => CouleursGesco.bleu,
      };

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 150,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Etiquette(
            mouvement.libelleType,
            couleur: _couleur,
            fond: CouleursGesco.grisClair,
          ),
        ),
      ),
      title: Text(_detail),
      trailing: Text(_date(mouvement.date)),
    );
  }
}
