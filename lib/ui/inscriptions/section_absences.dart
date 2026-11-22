import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/modeles_absences.dart';
import '../../domain/dates.dart';
import '../../domain/permissions.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../theme.dart';

/// Absences et retards d'un élève inscrit : totaux, liste, ajout, correction
/// et suppression (réservés à qui gère les élèves).
class SectionAbsences extends StatefulWidget {
  const SectionAbsences({
    super.key,
    required this.etat,
    required this.inscriptionId,
    this.maintenant,
  });

  final EtatApp etat;
  final int inscriptionId;

  /// Horloge de la date proposée par défaut (tests).
  final DateTime Function()? maintenant;

  @override
  State<SectionAbsences> createState() => _SectionAbsencesState();
}

class _SectionAbsencesState extends State<SectionAbsences> {
  /// Nombre d'absences affichées ; les plus anciennes restent dans les exports.
  static const int _maxAffichees = 12;

  late Future<List<Absence>> _futur;

  bool get _peutGerer => widget.etat.peut(Permission.elevesGerer);

  @override
  void initState() {
    super.initState();
    _futur = widget.etat.services.absences.lister(widget.inscriptionId);
  }

  void _recharger() {
    setState(() {
      _futur = widget.etat.services.absences.lister(widget.inscriptionId);
    });
  }

  Future<void> _saisir([Absence? existante]) async {
    final saisie = await showDialog<Absence>(
      context: context,
      builder: (_) => DialogueAbsence(
        inscriptionId: widget.inscriptionId,
        existante: existante,
        aujourdhui: (widget.maintenant ?? DateTime.now)(),
      ),
    );
    if (saisie == null || !mounted) return;
    final depot = widget.etat.services.absences;
    final ok = await executer(
      context,
      () => existante == null ? depot.ajouter(saisie) : depot.modifier(saisie),
      succes: existante == null ? 'Enregistré.' : 'Modifié.',
    );
    if (ok) _recharger();
  }

  Future<void> _supprimer(Absence a) async {
    final ok = await confirmer(
      context,
      titre: 'Supprimer cette ligne ?',
      message: '${a.type.libelle} du ${formaterDateFr(a.date)}.',
      libelleConfirmer: 'Supprimer',
      danger: true,
    );
    if (!ok || !mounted) return;
    final fait = await executer(
      context,
      () => widget.etat.services.absences.supprimer(a.id),
      succes: 'Supprimé.',
    );
    if (fait) _recharger();
  }

  static String _resume(TotauxAbsences t) {
    if (t.vide) return 'Aucune absence ni retard enregistré.';
    final parties = <String>[];
    if (t.absences > 0) {
      parties.add(
        '${t.absences} absence${t.absences > 1 ? 's' : ''}'
        '${t.absencesJustifiees > 0 ? ' (dont ${t.absencesJustifiees} justifiée${t.absencesJustifiees > 1 ? 's' : ''})' : ''}',
      );
    }
    if (t.retards > 0) {
      parties.add(
        '${t.retards} retard${t.retards > 1 ? 's' : ''}'
        '${t.minutesRetard > 0 ? ' (${t.minutesRetard} min au total)' : ''}',
      );
    }
    return parties.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Absence>>(
      future: _futur,
      builder: (context, instantane) {
        final liste = instantane.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Absences et retards',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_peutGerer)
                  OutlinedButton.icon(
                    key: const Key('absence_ajouter'),
                    onPressed: () => _saisir(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Ajouter'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (instantane.hasError)
              Text(
                'Impossible de lire les absences : ${instantane.error}',
                style: const TextStyle(color: CouleursGesco.rouge),
              )
            else if (liste == null)
              const LinearProgressIndicator()
            else ...[
              Text(
                _resume(TotauxAbsences.depuis(liste)),
                key: const Key('absences_resume'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final a in liste.take(_maxAffichees))
                ListTile(
                  key: Key('absence_${a.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${formaterDateFr(a.date)} — ${a.type.libelle}'
                    '${a.dureeMinutes == null ? '' : ' de ${a.dureeMinutes} min'}'
                    '${a.justifiee ? ' (justifiée)' : ' (non justifiée)'}',
                  ),
                  subtitle: a.motif.isEmpty ? null : Text(a.motif),
                  trailing: !_peutGerer
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: Key('absence_modifier_${a.id}'),
                              tooltip: 'Modifier',
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => _saisir(a),
                            ),
                            IconButton(
                              key: Key('absence_supprimer_${a.id}'),
                              tooltip: 'Supprimer',
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () => _supprimer(a),
                            ),
                          ],
                        ),
                ),
              if (liste.length > _maxAffichees)
                Text(
                  '… et ${liste.length - _maxAffichees} plus ancienne'
                  '${liste.length - _maxAffichees > 1 ? 's' : ''} '
                  '(toutes figurent dans l\'export Excel).',
                  style: const TextStyle(color: CouleursGesco.gris),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// Saisie ou correction d'une absence ou d'un retard.
class DialogueAbsence extends StatefulWidget {
  const DialogueAbsence({
    super.key,
    required this.inscriptionId,
    required this.aujourdhui,
    this.existante,
  });

  final int inscriptionId;
  final Absence? existante;

  /// Date proposée pour une nouvelle ligne.
  final DateTime aujourdhui;

  @override
  State<DialogueAbsence> createState() => _DialogueAbsenceState();
}

class _DialogueAbsenceState extends State<DialogueAbsence> {
  late TypeAbsence _type = widget.existante?.type ?? TypeAbsence.absence;
  late bool _justifiee = widget.existante?.justifiee ?? false;
  late final TextEditingController _date = TextEditingController(
    text: widget.existante == null
        ? dateVersFr(widget.aujourdhui)
        : formaterDateFr(widget.existante!.date),
  );
  late final TextEditingController _duree =
      TextEditingController(text: widget.existante?.dureeMinutes?.toString() ?? '');
  late final TextEditingController _motif =
      TextEditingController(text: widget.existante?.motif ?? '');
  String? _erreurDate;
  String? _erreurDuree;

  @override
  void dispose() {
    _date.dispose();
    _duree.dispose();
    _motif.dispose();
    super.dispose();
  }

  void _valider() {
    final date = analyserDateFr(_date.text);
    final texteDuree = _duree.text.trim();
    final duree = int.tryParse(texteDuree);
    final erreurDate = date == null ? 'Date invalide (format jj/mm/aaaa).' : null;
    final erreurDuree = _type == TypeAbsence.retard &&
            texteDuree.isNotEmpty &&
            (duree == null || duree < 1 || duree > 600)
        ? 'Entre 1 et 600 minutes.'
        : null;
    if (erreurDate != null || erreurDuree != null) {
      setState(() {
        _erreurDate = erreurDate;
        _erreurDuree = erreurDuree;
      });
      return;
    }
    Navigator.of(context).pop(
      Absence(
        id: widget.existante?.id ?? 0,
        inscriptionId: widget.inscriptionId,
        date: dateVersIso(date!),
        type: _type,
        justifiee: _justifiee,
        dureeMinutes: _type == TypeAbsence.retard ? duree : null,
        motif: _motif.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existante == null ? 'Absence ou retard' : 'Modifier'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<TypeAbsence>(
                key: const Key('absence_type'),
                segments: [
                  for (final t in TypeAbsence.values)
                    ButtonSegment(
                      value: t,
                      label: Text(t.libelle, key: Key('absence_type_${t.code}')),
                    ),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('absence_date'),
                controller: _date,
                decoration: champ('Date', aide: 'Format jj/mm/aaaa', erreur: _erreurDate),
                onChanged: (_) => setState(() => _erreurDate = null),
              ),
              if (_type == TypeAbsence.retard) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('absence_duree'),
                  controller: _duree,
                  keyboardType: TextInputType.number,
                  decoration:
                      champ('Durée du retard en minutes (facultatif)', erreur: _erreurDuree),
                  onChanged: (_) => setState(() => _erreurDuree = null),
                ),
              ],
              const SizedBox(height: 4),
              CheckboxListTile(
                key: const Key('absence_justifiee'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Justifiée (certificat, mot des parents...)'),
                value: _justifiee,
                onChanged: (v) => setState(() => _justifiee = v ?? false),
              ),
              TextField(
                key: const Key('absence_motif'),
                controller: _motif,
                maxLength: 200,
                decoration: champ('Motif (facultatif)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('absence_annuler'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('absence_valider'),
          onPressed: _valider,
          child: Text(widget.existante == null ? 'Enregistrer' : 'Modifier'),
        ),
      ],
    );
  }
}
