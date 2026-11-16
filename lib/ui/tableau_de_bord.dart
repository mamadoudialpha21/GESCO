import 'package:flutter/material.dart';

import '../app/etat_app.dart';
import '../data/modeles_donnees.dart';
import 'commun/chargeur.dart';
import 'theme.dart';

class _Resume {
  const _Resume({required this.classes});

  final List<ClasseResume> classes;

  int get nbClasses => classes.length;
  int get nbMatieres => classes.fold(0, (somme, c) => somme + c.nbMatieres);
  int get nbEleves => classes.fold(0, (somme, c) => somme + c.nbEleves);

  List<String> get classesSansMatiere => [
        for (final c in classes)
          if (c.nbMatieres == 0) c.classe.nom,
      ];
}

/// Page d'accueil : situation de l'établissement et étapes de démarrage.
class PageTableauDeBord extends StatelessWidget {
  const PageTableauDeBord({
    super.key,
    required this.etat,
    required this.allerAuxParametres,
    required this.allerAuxInscriptions,
  });

  final EtatApp etat;
  final VoidCallback allerAuxParametres;
  final VoidCallback allerAuxInscriptions;

  @override
  Widget build(BuildContext context) {
    return Chargeur<_Resume>(
      cle: (etat.anneeId, etat.version),
      charger: () async {
        final anneeId = etat.anneeId;
        if (anneeId == null) return const _Resume(classes: []);
        return _Resume(classes: await etat.services.classes.lister(anneeId));
      },
      builder: (context, resume) => _contenu(context, resume),
    );
  }

  Widget _contenu(BuildContext context, _Resume resume) {
    final annee = etat.anneeCourante;
    final nom = etat.etablissement.nom;
    final logo = etat.etablissement.logo;

    final sansMatiere = resume.classesSansMatiere;
    final etapes = <_Etape>[
      _Etape('Renseigner l\'établissement (nom, logo, adresse)', nom.isNotEmpty),
      _Etape('Créer l\'année scolaire', etat.annees.isNotEmpty),
      _Etape('Créer au moins une classe', resume.nbClasses > 0),
      _Etape(
        sansMatiere.isEmpty
            ? 'Définir les matières et coefficients de chaque classe'
            : 'Définir les matières de : ${sansMatiere.join(', ')}',
        resume.nbClasses > 0 && sansMatiere.isEmpty,
      ),
    ];
    // Les étapes de paramétrage doivent être faites avant d'inscrire.
    final parametrageFait = etapes.every((e) => e.faite);
    etapes.add(_Etape('Inscrire les élèves', resume.nbEleves > 0));
    final tout = etapes.every((e) => e.faite);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            if (logo != null)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Image.memory(
                  logo,
                  height: 64,
                  fit: BoxFit.contain,
                  errorBuilder: (context, erreur, trace) =>
                      const Icon(Icons.school, size: 48),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nom.isEmpty ? 'Établissement non renseigné' : nom,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    annee == null
                        ? 'Aucune année scolaire'
                        : 'Année scolaire ${annee.libelle}',
                    style: const TextStyle(color: CouleursGesco.gris),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (etat.problemesIntegrite.isNotEmpty) ...[
          Card(
            color: CouleursGesco.rougeClair,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Le contrôle d\'intégrité de la base a signalé des problèmes',
                    style: TextStyle(
                      color: CouleursGesco.rouge,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final p in etat.problemesIntegrite) SelectableText(p),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _Tuile(
              libelle: 'Classes',
              valeur: '${resume.nbClasses}',
              icone: Icons.class_outlined,
            ),
            _Tuile(
              libelle: 'Matières (toutes classes)',
              valeur: '${resume.nbMatieres}',
              icone: Icons.menu_book_outlined,
            ),
            _Tuile(
              libelle: 'Élèves inscrits',
              valeur: '${resume.nbEleves}',
              icone: Icons.people_outline,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tout ? 'Configuration complète' : 'Pour démarrer',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final e in etapes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          e.faite ? Icons.check_circle : Icons.radio_button_unchecked,
                          size: 20,
                          color: e.faite ? CouleursGesco.vert : CouleursGesco.gris,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(e.texte)),
                      ],
                    ),
                  ),
                if (!tout) ...[
                  const SizedBox(height: 12),
                  if (parametrageFait)
                    FilledButton.icon(
                      onPressed: allerAuxInscriptions,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Inscrire les élèves'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: allerAuxParametres,
                      icon: const Icon(Icons.settings),
                      label: const Text('Ouvrir les paramètres'),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: CouleursGesco.bleuClair,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline, color: CouleursGesco.bleu),
                const SizedBox(width: 12),
                Expanded(
                  child: SelectableText(
                    'Vos données sont enregistrées uniquement sur cet ordinateur, '
                    'sans Internet ni serveur.\nFichier : ${etat.chemin}',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Etape {
  const _Etape(this.texte, this.faite);

  final String texte;
  final bool faite;
}

class _Tuile extends StatelessWidget {
  const _Tuile({
    required this.libelle,
    required this.valeur,
    required this.icone,
  });

  final String libelle;
  final String valeur;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icone, size: 32, color: CouleursGesco.bleu),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valeur,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      libelle,
                      style: const TextStyle(color: CouleursGesco.gris),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
