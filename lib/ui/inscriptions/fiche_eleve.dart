import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/erreurs.dart';
import '../../data/modeles_donnees.dart';
import '../../domain/dates.dart';
import '../commun/chargeur.dart';
import '../theme.dart';

/// Action demandée depuis la fiche (exécutée ensuite par la page).
enum ActionFiche { modifier, supprimer }

class _Fiche {
  const _Fiche({required this.eleve, required this.nbNotes});

  final Eleve eleve;
  final int nbNotes;
}

/// Fiche complète d'un élève inscrit, en lecture seule.
/// Se ferme avec une [ActionFiche] si l'utilisateur choisit d'agir.
class DialogueFiche extends StatelessWidget {
  const DialogueFiche({
    super.key,
    required this.etat,
    required this.inscrit,
    required this.anneeLibelle,
  });

  final EtatApp etat;
  final EleveInscrit inscrit;
  final String anneeLibelle;

  Future<_Fiche> _charger() async {
    final eleve = await etat.services.eleves.obtenir(inscrit.eleveId);
    if (eleve == null) throw const ErreurGesco('Fiche élève introuvable.');
    final nbNotes = await etat.services.eleves.compterNotes(inscrit.inscriptionId);
    return _Fiche(eleve: eleve, nbNotes: nbNotes);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 200),
                  child: Chargeur<_Fiche>(
                    cle: inscrit.inscriptionId,
                    charger: _charger,
                    builder: (context, fiche) => _contenu(context, fiche),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(ActionFiche.supprimer),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Supprimer'),
                    style: TextButton.styleFrom(foregroundColor: CouleursGesco.rouge),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(ActionFiche.modifier),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Fermer'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contenu(BuildContext context, _Fiche fiche) {
    final e = fiche.eleve;
    final naissance = analyserDateIso(e.dateNaissance);
    final dateTexte = naissance == null
        ? 'Non renseignée'
        : '${dateVersFr(naissance)} (${_age(ageEn(naissance, DateTime.now()))})';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: CouleursGesco.grisClair,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black12),
              ),
              child: e.photo == null
                  ? const Icon(Icons.person_outline, size: 52, color: CouleursGesco.gris)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        e.photo!,
                        width: 104,
                        height: 104,
                        fit: BoxFit.cover,
                        errorBuilder: (context, erreur, trace) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
                    ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.nomComplet,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Matricule : ${e.matricule}',
                    style: const TextStyle(color: CouleursGesco.gris),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${inscrit.classeNom} — année scolaire $anneeLibelle',
                    style: const TextStyle(
                      color: CouleursGesco.bleu,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _Ligne('Sexe', e.sexe == 'F' ? 'Féminin' : 'Masculin'),
        _Ligne('Date de naissance', dateTexte),
        _Ligne('Lieu de naissance', e.lieuNaissance),
        _Ligne('Père', e.nomPere),
        _Ligne('Mère', e.nomMere),
        _Ligne('Contact du parent ou tuteur', e.contactParent),
        _Ligne('Adresse', e.adresse),
        _Ligne(
          'Notes enregistrées cette année',
          fiche.nbNotes == 0
              ? 'Aucune'
              : '${fiche.nbNotes}',
        ),
      ],
    );
  }

  static String _age(int ans) => ans > 1 ? '$ans ans' : '$ans an';
}

class _Ligne extends StatelessWidget {
  const _Ligne(this.libelle, this.valeur);

  final String libelle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 190,
            child: Text(libelle, style: const TextStyle(color: CouleursGesco.gris)),
          ),
          Expanded(
            child: SelectableText(valeur.trim().isEmpty ? '—' : valeur),
          ),
        ],
      ),
    );
  }
}
