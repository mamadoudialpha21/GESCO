import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../domain/arrondi.dart';
import '../../domain/bareme.dart';
import '../../domain/permissions.dart';
import '../commun/chargeur.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../theme.dart';

/// Notation : barème proposé par défaut (20) et convertisseur de notes.
///
/// Chaque matière et chaque évaluation a son propre barème (10, 20, 40, 100…) ;
/// celui d'ici n'est que la valeur proposée à la création.
class OngletNotation extends StatelessWidget {
  const OngletNotation({super.key, required this.etat});

  final EtatApp etat;

  @override
  Widget build(BuildContext context) {
    return Chargeur<int>(
      cle: (etat.version,),
      charger: () => etat.services.parametres.baremeDefaut(),
      builder: (context, bareme) => _ContenuNotation(
        key: ValueKey('notation-${etat.version}-$bareme'),
        etat: etat,
        baremeDefaut: bareme,
      ),
    );
  }
}

class _ContenuNotation extends StatefulWidget {
  const _ContenuNotation({super.key, required this.etat, required this.baremeDefaut});

  final EtatApp etat;
  final int baremeDefaut;

  @override
  State<_ContenuNotation> createState() => _ContenuNotationState();
}

class _ContenuNotationState extends State<_ContenuNotation> {
  late final TextEditingController _bareme;
  final TextEditingController _note = TextEditingController();
  final TextEditingController _de = TextEditingController(text: '10');
  final TextEditingController _vers = TextEditingController(text: '20');
  String? _erreurBareme;

  EtatApp get _etat => widget.etat;

  @override
  void initState() {
    super.initState();
    _bareme = TextEditingController(text: '${widget.baremeDefaut}');
  }

  @override
  void dispose() {
    _bareme.dispose();
    _note.dispose();
    _de.dispose();
    _vers.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final valeur = int.tryParse(_bareme.text.trim());
    if (valeur == null || !baremeValide(valeur)) {
      setState(() => _erreurBareme = 'Barème invalide (entier de 1 à 1000 ; ex. 10, 20, 40, 100).');
      return;
    }
    setState(() => _erreurBareme = null);
    final ok = await executer(
      context,
      () => _etat.services.parametres.definirBaremeDefaut(valeur),
      succes: 'Barème par défaut : sur $valeur.',
    );
    if (ok) _etat.donneesModifiees();
  }

  /// Résultat de la conversion en cours, ou le message à afficher.
  String _conversion() {
    final de = int.tryParse(_de.text.trim());
    final vers = int.tryParse(_vers.text.trim());
    if (de == null || !baremeValide(de) || vers == null || !baremeValide(vers)) {
      return 'Entrez deux barèmes entre 1 et 1000.';
    }
    if (_note.text.trim().isEmpty) return 'Entrez une note à convertir.';
    final centiemes = analyserNoteSurBareme(_note.text, de);
    if (centiemes == null) {
      return 'La note doit être un nombre de 0 à $de (2 décimales au plus).';
    }
    final resultat = convertirEntreBaremes(centiemes, de: de, vers: vers);
    return '${formaterCentiemes(centiemes)} sur $de = ${formaterCentiemes(resultat)} sur $vers';
  }

  @override
  Widget build(BuildContext context) {
    final modifiable = _etat.peut(Permission.parametresGerer);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const TitreSection(
          'Notation',
          sousTitre: 'Barème des notes : 20 par défaut, configurable par matière et par évaluation.',
        ),
        const SizedBox(height: 16),
        Carte(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Barème proposé par défaut',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Il est proposé à la création d\'une matière. Les matières et '
                'évaluations existantes gardent leur barème : les moyennes sont '
                'toujours calculées sur 20.',
                style: TextStyle(color: CouleursGesco.gris),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  SizedBox(
                    width: 160,
                    child: TextField(
                      key: const Key('champ_bareme_defaut'),
                      controller: _bareme,
                      enabled: modifiable,
                      keyboardType: TextInputType.number,
                      decoration: champ('Note maximale', erreur: _erreurBareme),
                      onSubmitted: (_) => _enregistrer(),
                    ),
                  ),
                  for (final b in baremesUsuels)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: ActionChip(
                        key: Key('bareme_usuel_$b'),
                        label: Text('sur $b'),
                        onPressed: modifiable
                            ? () => setState(() {
                                  _bareme.text = '$b';
                                  _erreurBareme = null;
                                })
                            : null,
                      ),
                    ),
                  if (modifiable)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: FilledButton(
                        key: const Key('enregistrer_bareme_defaut'),
                        onPressed: _enregistrer,
                        child: const Text('Enregistrer'),
                      ),
                    ),
                ],
              ),
              if (!modifiable)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Vous n\'avez pas l\'autorisation de modifier les paramètres.',
                    style: TextStyle(color: CouleursGesco.orange),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Carte(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Convertisseur de notes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Convertit une note d\'un barème à un autre (arrondi au centième).',
                style: TextStyle(color: CouleursGesco.gris),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 130,
                    child: TextField(
                      key: const Key('conv_note'),
                      controller: _note,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: champ('Note'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      key: const Key('conv_de'),
                      controller: _de,
                      keyboardType: TextInputType.number,
                      decoration: champ('Sur (barème)'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      key: const Key('conv_vers'),
                      controller: _vers,
                      keyboardType: TextInputType.number,
                      decoration: champ('Vers (barème)'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _conversion(),
                key: const Key('conv_resultat'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
