import 'package:flutter/material.dart';

import '../app/etat_app.dart';
import '../data/modeles_donnees.dart';
import 'commun/chargeur.dart';
import 'commun/composants.dart';
import 'theme.dart';

class _Resume {
  const _Resume({required this.classes, required this.eleves});

  final List<ClasseResume> classes;
  final List<EleveInscrit> eleves;

  int get nbClasses => classes.length;
  int get nbMatieres => classes.fold(0, (somme, c) => somme + c.nbMatieres);
  int get nbEleves => classes.fold(0, (somme, c) => somme + c.nbEleves);
  int get nbGarcons => eleves.where((e) => e.sexe == 'M').length;
  int get nbFilles => eleves.where((e) => e.sexe == 'F').length;

  List<String> get classesSansMatiere => [
        for (final c in classes)
          if (c.nbMatieres == 0) c.classe.nom,
      ];
}

/// Largeur à partir de laquelle le tableau de bord passe sur deux colonnes.
const double _largeurDeuxColonnes = 900;

/// Page d'accueil : situation de l'établissement, répartition des élèves et
/// étapes de démarrage.
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
        if (anneeId == null) return const _Resume(classes: [], eleves: []);
        return _Resume(
          classes: await etat.services.classes.lister(anneeId),
          eleves: await etat.services.eleves.lister(anneeId),
        );
      },
      builder: (context, resume) => _contenu(context, resume),
    );
  }

  Widget _contenu(BuildContext context, _Resume resume) {
    final nom = etat.etablissement.nom;

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

    return LayoutBuilder(
      builder: (context, contraintes) {
        final large = contraintes.maxWidth >= _largeurDeuxColonnes;
        final marge = large ? 28.0 : 16.0;

        final repartition = _CarteRepartition(
          resume: resume,
          onInscrire: allerAuxInscriptions,
        );
        final demarrage = _CarteDemarrage(
          etapes: etapes,
          tout: tout,
          parametrageFait: parametrageFait,
          allerAuxParametres: allerAuxParametres,
          allerAuxInscriptions: allerAuxInscriptions,
        );
        final donnees = _CarteDonnees(chemin: etat.chemin);

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: ListView(
              padding: EdgeInsets.all(marge),
              children: [
                _Bandeau(
                  etat: etat,
                  parametrageFait: parametrageFait,
                  allerAuxParametres: allerAuxParametres,
                  allerAuxInscriptions: allerAuxInscriptions,
                ),
                const SizedBox(height: 16),
                if (etat.problemesIntegrite.isNotEmpty) ...[
                  _AlerteIntegrite(problemes: etat.problemesIntegrite),
                  const SizedBox(height: 16),
                ],
                _RangeeTuiles(
                  large: large,
                  tuiles: [
                    _Tuile(
                      libelle: 'Classes',
                      valeur: '${resume.nbClasses}',
                      icone: Icons.class_outlined,
                      detail: resume.nbClasses == 0
                          ? 'Aucune classe créée'
                          : 'cette année scolaire',
                    ),
                    _Tuile(
                      libelle: 'Matières (toutes classes)',
                      valeur: '${resume.nbMatieres}',
                      icone: Icons.menu_book_outlined,
                      detail: 'avec leurs coefficients',
                    ),
                    _Tuile(
                      libelle: 'Élèves inscrits',
                      valeur: '${resume.nbEleves}',
                      icone: Icons.people_outline,
                      detail: resume.nbEleves == 0
                          ? 'Aucun élève inscrit'
                          : '${resume.nbGarcons} garçon${resume.nbGarcons > 1 ? 's' : ''}'
                              '  ·  ${resume.nbFilles} fille${resume.nbFilles > 1 ? 's' : ''}',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (large)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: repartition),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: Column(
                          children: [
                            demarrage,
                            const SizedBox(height: 16),
                            donnees,
                          ],
                        ),
                      ),
                    ],
                  )
                else ...[
                  demarrage,
                  const SizedBox(height: 16),
                  repartition,
                  const SizedBox(height: 16),
                  donnees,
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Etape {
  const _Etape(this.texte, this.faite);

  final String texte;
  final bool faite;
}

/// Bandeau bleu : établissement, année scolaire et actions rapides.
class _Bandeau extends StatelessWidget {
  const _Bandeau({
    required this.etat,
    required this.parametrageFait,
    required this.allerAuxParametres,
    required this.allerAuxInscriptions,
  });

  final EtatApp etat;
  final bool parametrageFait;
  final VoidCallback allerAuxParametres;
  final VoidCallback allerAuxInscriptions;

  @override
  Widget build(BuildContext context) {
    final annee = etat.anneeCourante;
    final nom = etat.etablissement.nom;
    final logo = etat.etablissement.logo;

    final identite = Row(
      children: [
        Container(
          width: 64,
          height: 64,
          padding: logo == null ? EdgeInsets.zero : const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: logo == null ? const Color(0x26FFFFFF) : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: logo == null
              ? const Icon(Icons.school, color: Colors.white, size: 34)
              : Image.memory(
                  logo,
                  fit: BoxFit.contain,
                  errorBuilder: (context, erreur, trace) =>
                      const Icon(Icons.school, color: CouleursGesco.bleu),
                ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nom.isEmpty ? 'Établissement non renseigné' : nom,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                annee == null
                    ? 'Aucune année scolaire'
                    : 'Année scolaire ${annee.libelle}'
                        '${annee.active ? '  ·  en cours' : '  ·  consultation'}',
                style: const TextStyle(color: Color(0xFFD3E1F5), fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );

    final styleBouton = FilledButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: CouleursGesco.bleuFonce,
    );
    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (parametrageFait)
          FilledButton.icon(
            key: const Key('action_inscrire'),
            style: styleBouton,
            onPressed: allerAuxInscriptions,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Inscrire un élève'),
          ),
        FilledButton.icon(
          key: const Key('action_parametres'),
          style: styleBouton,
          onPressed: allerAuxParametres,
          icon: const Icon(Icons.settings),
          label: const Text('Paramètres'),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [CouleursGesco.bleuFonce, CouleursGesco.bleu],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth < 640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [identite, const SizedBox(height: 16), actions],
            );
          }
          return Row(
            children: [
              Expanded(child: identite),
              const SizedBox(width: 16),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _AlerteIntegrite extends StatelessWidget {
  const _AlerteIntegrite({required this.problemes});

  final List<String> problemes;

  @override
  Widget build(BuildContext context) {
    return Carte(
      couleur: CouleursGesco.rougeClair,
      bordure: CouleursGesco.rouge,
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
          for (final p in problemes) SelectableText(p),
        ],
      ),
    );
  }
}

/// Les tuiles de chiffres : trois côte à côte (même hauteur) ou empilées.
class _RangeeTuiles extends StatelessWidget {
  const _RangeeTuiles({required this.large, required this.tuiles});

  final bool large;
  final List<Widget> tuiles;

  @override
  Widget build(BuildContext context) {
    if (!large) {
      return Column(
        children: [
          for (var i = 0; i < tuiles.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            tuiles[i],
          ],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tuiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(child: tuiles[i]),
          ],
        ],
      ),
    );
  }
}

class _Tuile extends StatelessWidget {
  const _Tuile({
    required this.libelle,
    required this.valeur,
    required this.icone,
    required this.detail,
  });

  final String libelle;
  final String valeur;
  final IconData icone;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Carte(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: CouleursGesco.bleuClair,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icone, size: 28, color: CouleursGesco.bleu),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  valeur,
                  style: const TextStyle(
                    color: CouleursGesco.texte,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  libelle,
                  style: const TextStyle(
                    color: CouleursGesco.texte,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(color: CouleursGesco.gris, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Nombre d'élèves et de matières de chaque classe, avec une barre
/// proportionnelle à l'effectif.
class _CarteRepartition extends StatelessWidget {
  const _CarteRepartition({required this.resume, required this.onInscrire});

  final _Resume resume;
  final VoidCallback onInscrire;

  @override
  Widget build(BuildContext context) {
    final plusGrand = resume.classes.fold<int>(
      0,
      (m, c) => c.nbEleves > m ? c.nbEleves : m,
    );
    return Carte(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Répartition par classe',
            style: TextStyle(
              color: CouleursGesco.texte,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Effectif et nombre de matières de chaque classe.',
            style: TextStyle(color: CouleursGesco.gris),
          ),
          const SizedBox(height: 16),
          if (resume.classes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Aucune classe pour cette année scolaire.',
                  style: TextStyle(color: CouleursGesco.gris),
                ),
              ),
            )
          else
            for (var i = 0; i < resume.classes.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _LigneClasse(classe: resume.classes[i], plusGrand: plusGrand),
            ],
        ],
      ),
    );
  }
}

class _LigneClasse extends StatelessWidget {
  const _LigneClasse({required this.classe, required this.plusGrand});

  final ClasseResume classe;
  final int plusGrand;

  @override
  Widget build(BuildContext context) {
    final proportion = plusGrand == 0 ? 0.0 : classe.nbEleves / plusGrand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                classe.classe.nom,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CouleursGesco.texte,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (classe.nbMatieres == 0)
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Etiquette(
                  'Sans matière',
                  couleur: CouleursGesco.orange,
                  fond: CouleursGesco.orangeClair,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  '${classe.nbMatieres} matière${classe.nbMatieres > 1 ? 's' : ''}',
                  style: const TextStyle(color: CouleursGesco.gris, fontSize: 12.5),
                ),
              ),
            Text(
              '${classe.nbEleves} élève${classe.nbEleves > 1 ? 's' : ''}',
              style: const TextStyle(
                color: CouleursGesco.bleu,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: proportion,
            minHeight: 8,
            color: CouleursGesco.bleu,
            backgroundColor: CouleursGesco.bleuClair,
          ),
        ),
      ],
    );
  }
}

/// Étapes pour démarrer, ou confirmation que tout est prêt.
class _CarteDemarrage extends StatelessWidget {
  const _CarteDemarrage({
    required this.etapes,
    required this.tout,
    required this.parametrageFait,
    required this.allerAuxParametres,
    required this.allerAuxInscriptions,
  });

  final List<_Etape> etapes;
  final bool tout;
  final bool parametrageFait;
  final VoidCallback allerAuxParametres;
  final VoidCallback allerAuxInscriptions;

  @override
  Widget build(BuildContext context) {
    return Carte(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tout ? 'Configuration complète' : 'Pour démarrer',
                  style: const TextStyle(
                    color: CouleursGesco.texte,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (tout)
                const Etiquette(
                  'Prêt',
                  couleur: CouleursGesco.vert,
                  fond: CouleursGesco.vertClair,
                ),
            ],
          ),
          const SizedBox(height: 10),
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
    );
  }
}

/// Rappel : les données restent sur l'ordinateur, avec l'emplacement du fichier.
class _CarteDonnees extends StatelessWidget {
  const _CarteDonnees({required this.chemin});

  final String chemin;

  @override
  Widget build(BuildContext context) {
    return Carte(
      couleur: CouleursGesco.bleuClair,
      bordure: CouleursGesco.bleuClair,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, color: CouleursGesco.bleu),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vos données restent sur cet ordinateur, sans Internet ni serveur.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  'Fichier : $chemin',
                  style: const TextStyle(color: CouleursGesco.gris, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
