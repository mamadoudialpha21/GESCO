import 'package:flutter/material.dart';

import '../../data/modeles_donnees.dart';
import '../../data/modeles_notation.dart';
import '../../domain/arrondi.dart';
import '../../domain/dates.dart';
import '../../domain/periodes.dart';
import '../commun/choix.dart';
import '../commun/composants.dart';

/// Ce que l'utilisateur a rempli dans la fiche d'une évaluation.
class SaisieEvaluation {
  const SaisieEvaluation({
    required this.titre,
    required this.type,
    required this.matiereId,
    required this.mois,
    required this.date,
    required this.coefficient,
    required this.bareme,
  });

  final String titre;
  final TypeEvaluation type;
  final int matiereId;
  final int mois;

  /// Date au format ISO (2026-11-17), ou null.
  final String? date;

  /// Centièmes (2 -> 200).
  final int coefficient;
  final int bareme;
}

/// Fiche d'une évaluation : création ([existante] null) ou modification.
///
/// Quand l'évaluation a déjà des notes ([verrouillerMoisEtBareme]), son mois,
/// son barème et sa matière ne peuvent plus changer.
class DialogueEvaluation extends StatefulWidget {
  const DialogueEvaluation({
    super.key,
    required this.matieres,
    required this.moisInitial,
    this.existante,
    this.matiereInitialeId,
    this.verrouillerMoisEtBareme = false,
  });

  final List<MatiereClasse> matieres;
  final int moisInitial;
  final Evaluation? existante;
  final int? matiereInitialeId;
  final bool verrouillerMoisEtBareme;

  @override
  State<DialogueEvaluation> createState() => _DialogueEvaluationState();
}

class _DialogueEvaluationState extends State<DialogueEvaluation> {
  late final TextEditingController _titre;
  late final TextEditingController _date;
  late final TextEditingController _coefficient;
  late final TextEditingController _bareme;
  late TypeEvaluation _type;
  late int _matiereId;
  late int _mois;
  bool _baremeModifie = false;
  String? _erreurTitre;
  String? _erreurDate;
  String? _erreurCoefficient;
  String? _erreurBareme;

  Evaluation? get _e => widget.existante;

  @override
  void initState() {
    super.initState();
    final e = _e;
    _titre = TextEditingController(text: e?.titre ?? '');
    _date = TextEditingController(text: e == null ? '' : formaterDateFr(e.date));
    _coefficient = TextEditingController(
      text: e == null ? '1' : formaterCoefficient(e.coefficient),
    );
    _type = e?.type ?? TypeEvaluation.evaluation;
    _matiereId = e?.matiereId ??
        (widget.matieres.any((m) => m.id == widget.matiereInitialeId)
            ? widget.matiereInitialeId!
            : widget.matieres.first.id);
    _mois = e?.mois ?? widget.moisInitial;
    _bareme = TextEditingController(
      text: '${e?.bareme ?? _matiere(_matiereId).bareme}',
    );
  }

  @override
  void dispose() {
    _titre.dispose();
    _date.dispose();
    _coefficient.dispose();
    _bareme.dispose();
    super.dispose();
  }

  MatiereClasse _matiere(int id) => widget.matieres.firstWhere((m) => m.id == id);

  Future<void> _choisirDate() async {
    final aujourdHui = DateTime.now();
    final initiale = analyserDateFr(_date.text.trim()) ?? aujourdHui;
    final choix = await showDatePicker(
      context: context,
      initialDate: initiale,
      firstDate: DateTime(2000),
      lastDate: DateTime(aujourdHui.year + 2, 12, 31),
      helpText: 'Date de l\'évaluation',
    );
    if (choix == null || !mounted) return;
    setState(() {
      _date.text = dateVersFr(choix);
      _erreurDate = null;
    });
  }

  void _valider() {
    final titre = _titre.text.trim();
    final texteDate = _date.text.trim();
    final date = texteDate.isEmpty ? null : analyserDateFr(texteDate);
    final coefficient = analyserCoefficient(_coefficient.text);
    final bareme = int.tryParse(_bareme.text.trim());
    final baremeValide = bareme != null && bareme >= 1 && bareme <= 1000;
    setState(() {
      _erreurTitre = titre.isEmpty ? 'Le titre est obligatoire.' : null;
      _erreurDate = texteDate.isNotEmpty && date == null
          ? 'Date invalide : utilisez JJ/MM/AAAA (ex. 17/11/2026).'
          : null;
      _erreurCoefficient = coefficient == null
          ? 'Coefficient invalide (de 0,01 à 99,99 ; ex. 1 ou 2,5).'
          : null;
      _erreurBareme =
          baremeValide ? null : 'Barème invalide (entier de 1 à 1000 ; ex. 10, 20, 40, 100).';
    });
    if (titre.isEmpty ||
        (texteDate.isNotEmpty && date == null) ||
        coefficient == null ||
        !baremeValide) {
      return;
    }
    Navigator.of(context).pop(
      SaisieEvaluation(
        titre: titre,
        type: _type,
        matiereId: _matiereId,
        mois: _mois,
        date: date == null ? null : dateVersIso(date),
        coefficient: coefficient,
        bareme: bareme,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final creation = _e == null;
    final fige = widget.verrouillerMoisEtBareme;
    return AlertDialog(
      title: Text(creation ? 'Nouvelle évaluation' : 'Modifier l\'évaluation'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('champ_titre'),
                controller: _titre,
                autofocus: true,
                decoration: champ('Titre', erreur: _erreurTitre),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ChoixListe<TypeEvaluation>(
                      cleChamp: const Key('choix_type'),
                      libelle: 'Type',
                      valeur: _type,
                      options: [for (final t in TypeEvaluation.values) (t, t.libelle)],
                      onChanged: (t) => setState(() => _type = t ?? _type),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChoixListe<int>(
                      cleChamp: const Key('choix_mois'),
                      libelle: 'Mois',
                      valeur: _mois,
                      options: [for (final m in moisScolaires) (m, libelleMois(m))],
                      onChanged: fige ? null : (m) => setState(() => _mois = m ?? _mois),
                      aide: fige ? 'Des notes existent déjà.' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (creation)
                ChoixListe<int>(
                  cleChamp: const Key('choix_matiere'),
                  libelle: 'Matière',
                  valeur: _matiereId,
                  options: [for (final m in widget.matieres) (m.id, m.nom)],
                  onChanged: (id) {
                    if (id == null) return;
                    setState(() {
                      _matiereId = id;
                      // Le barème de la matière est proposé tant qu'on n'a pas
                      // choisi le sien.
                      if (!_baremeModifie) _bareme.text = '${_matiere(id).bareme}';
                    });
                  },
                )
              else
                InputDecorator(
                  decoration: champ('Matière'),
                  child: Text(_matiere(_matiereId).nom),
                ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('champ_coefficient'),
                      controller: _coefficient,
                      decoration: champ(
                        'Coefficient',
                        aide: 'Poids dans la note du mois',
                        erreur: _erreurCoefficient,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const Key('champ_bareme'),
                      controller: _bareme,
                      enabled: !fige,
                      decoration: champ(
                        'Note maximale',
                        aide: fige ? 'Des notes existent déjà.' : 'Barème : 10, 20, 40, 100...',
                        erreur: _erreurBareme,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _baremeModifie = true,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('champ_date'),
                controller: _date,
                decoration: champ(
                  'Date (facultative)',
                  aide: 'JJ/MM/AAAA',
                  erreur: _erreurDate,
                ).copyWith(
                  suffixIcon: IconButton(
                    tooltip: 'Choisir la date',
                    icon: const Icon(Icons.calendar_month_outlined),
                    onPressed: _choisirDate,
                  ),
                ),
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
          key: const Key('enregistrer_evaluation'),
          onPressed: _valider,
          child: Text(creation ? 'Créer' : 'Enregistrer'),
        ),
      ],
    );
  }
}
