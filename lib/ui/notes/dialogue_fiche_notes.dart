import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/construire_fiches_notes.dart';
import '../../app/etat_app.dart';
import '../../data/erreurs.dart';
import '../../data/modeles_donnees.dart';
import '../../data/modeles_notation.dart';
import '../../documents/modele_fiche_notes.dart';
import '../../documents/ouvrir_document.dart';
import '../../documents/pdf_fiche_notes.dart';
import '../../documents/polices_pdf.dart';
import '../../documents/styles_bulletin.dart';
import '../../domain/permissions.dart';
import '../commun/choix.dart';
import '../commun/composants.dart';
import '../theme.dart';

/// Données lues à l'ouverture de la fenêtre.
class _Donnees {
  const _Donnees({
    required this.matieres,
    required this.eleves,
    required this.enseignants,
    required this.etablissement,
    required this.style,
  });

  final List<MatiereClasse> matieres;
  final List<EleveInscrit> eleves;

  /// Identifiant d'enseignant -> nom complet.
  final Map<int, String> enseignants;
  final Etablissement etablissement;
  final StyleBulletin style;

  int get nbActifs => eleves.where((e) => e.actif).length;
}

/// Ce que la dernière impression a produit.
class _Produit {
  const _Produit({
    required this.description,
    required this.chemin,
    required this.pages,
    required this.ouvert,
  });

  final String description;
  final String chemin;
  final int pages;
  final bool ouvert;
}

const String _toutes = 'toutes';
const String _liste = 'liste';
String _cleMatiere(int id) => 'mat:$id';
String _cleEnseignant(int id) => 'ens:$id';

/// Fenêtre d'impression des fiches de notes remises aux professeurs.
///
/// Le professeur écrit ses notes sur la fiche ; la personne qui utilise GESCO
/// les saisit ensuite dans « Notes » : la fiche reprend l'ordre des élèves de
/// l'écran de saisie. Le PDF est enregistré dans « Documents\GESCO » puis
/// ouvert dans le lecteur par défaut, d'où l'on imprime.
///
/// Avec [evaluation], la fiche est celle de cette évaluation (une colonne, son
/// barème, son mois) ; sans elle, on choisit les matières et les colonnes.
class DialogueFicheNotes extends StatefulWidget {
  const DialogueFicheNotes({
    super.key,
    required this.etat,
    required this.classe,
    this.evaluation,
    this.periodeInitiale = '',
    this.ouvreur = ouvrirFichier,
    this.dossier,
    this.chargerPolices = PolicesPdf.charger,
    this.maintenant,
  });

  final EtatApp etat;
  final ClasseResume classe;
  final Evaluation? evaluation;

  /// Période proposée au départ (« Novembre »), modifiable.
  final String periodeInitiale;

  /// Ouvre un fichier dans le programme par défaut (remplaçable dans les tests).
  final Ouvreur ouvreur;

  /// Dossier d'enregistrement ; « Documents\GESCO » si absent.
  final Directory? dossier;
  final Future<PolicesPdf> Function() chargerPolices;

  /// Horloge de la date d'édition imprimée en pied de page (tests).
  final DateTime Function()? maintenant;

  @override
  State<DialogueFicheNotes> createState() => _DialogueFicheNotesState();
}

class _DialogueFicheNotesState extends State<DialogueFicheNotes> {
  late final Future<_Donnees> _futur;
  late final TextEditingController _periode;
  final TextEditingController _intitules = TextEditingController();

  String? _contenu;
  int _nombre = 3;
  bool _matricule = true;
  bool _sexe = false;
  bool _observations = true;
  bool _enCours = false;
  _Produit? _produit;

  bool get _peut => widget.etat.peut(Permission.documentsGenerer);

  @override
  void initState() {
    super.initState();
    _periode = TextEditingController(text: widget.periodeInitiale);
    _futur = _charger();
  }

  @override
  void dispose() {
    _periode.dispose();
    _intitules.dispose();
    super.dispose();
  }

  Future<_Donnees> _charger() async {
    final etat = widget.etat;
    final s = etat.services;
    final classeId = widget.classe.classe.id;
    final anneeId = widget.classe.classe.anneeId;
    final enseignants = await s.enseignants.lister(anneeId: anneeId);
    String? styleId;
    try {
      styleId = await s.parametres.styleDocuments();
    } catch (_) {
      // Le style par défaut convient.
    }
    return _Donnees(
      matieres: await s.matieres.lister(classeId),
      eleves: await s.eleves.lister(anneeId, classeId: classeId),
      enseignants: {for (final e in enseignants) e.enseignant.id: e.enseignant.nomComplet},
      etablissement: await s.etablissements.lire(),
      style: StyleBulletin.parId(styleId),
    );
  }

  /// Choix proposés : une matière, toutes celles d'un enseignant, toutes, ou la
  /// liste de classe seule.
  List<(String, String)> _options(_Donnees d) {
    String nomEns(MatiereClasse m) => d.enseignants[m.enseignantId] ?? '';
    final parEnseignant = <int, List<MatiereClasse>>{};
    for (final m in d.matieres) {
      final id = m.enseignantId;
      if (id != null && d.enseignants.containsKey(id)) {
        (parEnseignant[id] ??= []).add(m);
      }
    }
    return [
      for (final m in d.matieres)
        (_cleMatiere(m.id), nomEns(m).isEmpty ? m.nom : '${m.nom}  ·  ${nomEns(m)}'),
      if (d.matieres.length > 1) (_toutes, 'Toutes les matières (${d.matieres.length} fiches)'),
      for (final e in parEnseignant.entries)
        if (e.value.length > 1)
          (
            _cleEnseignant(e.key),
            'Toutes les matières de ${d.enseignants[e.key]} (${e.value.length} fiches)',
          ),
      (_liste, 'Liste de classe seule (sans matière)'),
    ];
  }

  String _choixValide(_Donnees d, List<(String, String)> options) {
    final actuel = _contenu;
    if (actuel != null && options.any((o) => o.$1 == actuel)) return actuel;
    return options.first.$1;
  }

  Future<void> _generer(_Donnees d, String contenu) async {
    if (_enCours) return;
    setState(() => _enCours = true);
    _Produit? produit;
    String? erreur;
    try {
      final nomClasse = widget.classe.classe.nom;
      if (d.nbActifs == 0) {
        throw ErreurGesco(
          'Aucun élève ne suit la classe $nomClasse : il n\'y a rien à imprimer.',
        );
      }
      final anneeLibelle = widget.etat.anneeCourante?.libelle ?? '';
      final date = widget.maintenant?.call();
      final options = OptionsFicheNotes(
        periode: _periode.text,
        intitules: intitulesFiche(_intitules.text, _nombre),
        avecMatricule: _matricule,
        avecSexe: _sexe,
        avecObservations: _observations,
      );

      final List<FicheNotes> fiches;
      final String nomFichier;
      final String description;
      final evaluation = widget.evaluation;
      if (evaluation != null) {
        final matiere = d.matieres.firstWhere(
          (m) => m.id == evaluation.matiereId,
          orElse: () => throw const ErreurGesco('La matière de cette évaluation n\'existe plus.'),
        );
        fiches = [
          construireFicheEvaluation(
            etablissement: d.etablissement,
            anneeLibelle: anneeLibelle,
            classeNom: nomClasse,
            eleves: d.eleves,
            evaluation: evaluation,
            matiere: matiere,
            enseignant: d.enseignants[matiere.enseignantId] ?? '',
            options: options,
            dateEdition: date,
          ),
        ];
        nomFichier = 'Fiche de notes $nomClasse ${matiere.nom} ${evaluation.titre}';
        description = 'Fiche de notes « ${evaluation.titre} » (${matiere.nom}, $nomClasse)';
      } else if (contenu == _liste) {
        fiches = [
          construireListeClasse(
            etablissement: d.etablissement,
            anneeLibelle: anneeLibelle,
            classeNom: nomClasse,
            eleves: d.eleves,
            options: options,
            dateEdition: date,
          ),
        ];
        nomFichier = 'Liste de classe $nomClasse';
        description = 'Liste de la classe $nomClasse';
      } else {
        final List<MatiereClasse> retenues;
        String complement = '';
        if (contenu == _toutes) {
          retenues = d.matieres;
        } else if (contenu.startsWith('ens:')) {
          final id = int.parse(contenu.substring(4));
          retenues = [
            for (final m in d.matieres)
              if (m.enseignantId == id) m,
          ];
          complement = ' ${d.enseignants[id] ?? ''}';
        } else {
          final id = int.parse(contenu.substring(4));
          retenues = [
            for (final m in d.matieres)
              if (m.id == id) m,
          ];
        }
        if (retenues.isEmpty) {
          throw const ErreurGesco('Aucune matière à imprimer : choisissez-en une autre.');
        }
        fiches = construireFichesNotes(
          etablissement: d.etablissement,
          anneeLibelle: anneeLibelle,
          classeNom: nomClasse,
          eleves: d.eleves,
          matieres: retenues,
          enseignants: d.enseignants,
          options: options,
          dateEdition: date,
        );
        if (retenues.length == 1) {
          nomFichier = 'Fiche de notes $nomClasse ${retenues.first.nom}';
          description = 'Fiche de notes de ${retenues.first.nom} ($nomClasse)';
        } else {
          nomFichier = 'Fiches de notes $nomClasse$complement';
          description = '${retenues.length} fiches de notes de la classe $nomClasse';
        }
      }

      final polices = await widget.chargerPolices();
      final pdf = await genererFichesNotesPdf(fiches, style: d.style, polices: polices);
      final fichier = await enregistrerPdf(pdf, nomFichier, dossier: widget.dossier);
      final ouvert = await widget.ouvreur(fichier.path);
      produit = _Produit(
        description: description,
        chemin: fichier.path,
        pages: pdf.pages,
        ouvert: ouvert,
      );
    } on ErreurGesco catch (e) {
      erreur = e.message;
    } catch (e) {
      erreur = 'Erreur inattendue : $e';
    }
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _produit = produit ?? _produit;
    });
    if (erreur != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erreur), backgroundColor: CouleursGesco.rouge),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nomClasse = widget.classe.classe.nom;
    return FutureBuilder<_Donnees>(
      future: _futur,
      builder: (context, instantane) {
        final d = instantane.data;
        final options = d == null ? const <(String, String)>[] : _options(d);
        final contenu = d == null ? _liste : _choixValide(d, options);
        final liste = widget.evaluation == null && contenu == _liste;
        final evaluation = widget.evaluation;

        Widget corps;
        if (instantane.hasError) {
          corps = Text(
            'Impossible de préparer la fiche : ${instantane.error}',
            key: const Key('fiche_erreur'),
            style: const TextStyle(color: CouleursGesco.rouge),
          );
        } else if (d == null) {
          corps = const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        } else {
          corps = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Imprimez la liste des ${d.nbActifs} élève${d.nbActifs > 1 ? 's' : ''} de '
                '$nomClasse avec des colonnes vides : le professeur y écrit les notes, '
                'puis vous les saisissez dans GESCO, dans le même ordre.',
                key: const Key('fiche_intro'),
                style: const TextStyle(color: CouleursGesco.gris),
              ),
              const SizedBox(height: 14),
              if (evaluation != null)
                Text(
                  'Évaluation : ${evaluation.titre} (${evaluation.libelleBareme})',
                  key: const Key('fiche_evaluation'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                )
              else
                ChoixListe<String>(
                  cleChamp: const Key('fiche_contenu'),
                  libelle: 'Contenu de la fiche',
                  valeur: contenu,
                  options: options,
                  onChanged: (v) => setState(() => _contenu = v),
                ),
              if (!liste) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('fiche_periode'),
                  controller: _periode,
                  enabled: evaluation == null,
                  decoration: champ(
                    'Période ou mois (facultatif)',
                    aide: evaluation == null
                        ? 'Laissez vide pour l\'écrire à la main.'
                        : 'Mois de l\'évaluation.',
                  ),
                ),
              ],
              if (!liste && evaluation == null) ...[
                const SizedBox(height: 12),
                ChoixListe<int>(
                  cleChamp: const Key('fiche_nombre'),
                  libelle: 'Colonnes de notes à remplir',
                  valeur: _nombre,
                  options: [
                    for (var i = 1; i <= colonnesNotesMax; i++) (i, i == 1 ? '1 colonne' : '$i colonnes'),
                  ],
                  onChanged: (v) => setState(() => _nombre = v ?? _nombre),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('fiche_intitules'),
                  controller: _intitules,
                  decoration: champ(
                    'Titres des colonnes (facultatif)',
                    aide: 'Séparés par des virgules. Vide : « Note 1, Note 2... ».',
                  ),
                ),
              ],
              const SizedBox(height: 6),
              CheckboxListTile(
                key: const Key('fiche_matricule'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Afficher le matricule'),
                value: _matricule,
                onChanged: (v) => setState(() => _matricule = v ?? false),
              ),
              CheckboxListTile(
                key: const Key('fiche_sexe'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Afficher le sexe'),
                value: _sexe,
                onChanged: (v) => setState(() => _sexe = v ?? false),
              ),
              CheckboxListTile(
                key: const Key('fiche_observations'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Colonne « Observations »'),
                value: _observations,
                onChanged: (v) => setState(() => _observations = v ?? false),
              ),
              if (!_peut) ...[
                const SizedBox(height: 8),
                const Text(
                  'Votre compte n\'a pas l\'autorisation de générer les documents.',
                  key: Key('fiche_refus'),
                  style: TextStyle(color: CouleursGesco.rouge),
                ),
              ],
              if (_produit != null) ...[
                const Divider(height: 24),
                Text(
                  _produit!.ouvert
                      ? '${_produit!.description} : PDF enregistré et ouvert '
                          '(${_produit!.pages} page${_produit!.pages > 1 ? 's' : ''}).'
                      : '${_produit!.description} : PDF enregistré '
                          '(${_produit!.pages} page${_produit!.pages > 1 ? 's' : ''}). '
                          'Ouvrez-le depuis le dossier indiqué.',
                  key: const Key('fiche_resultat'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                SelectableText(_produit!.chemin, key: const Key('fiche_chemin')),
              ],
            ],
          );
        }

        return AlertDialog(
          backgroundColor: Colors.white,
          title: Row(
            children: [
              const Icon(Icons.print_outlined, color: CouleursGesco.bleu),
              const SizedBox(width: 8),
              Expanded(child: Text('Fiche de notes · $nomClasse')),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(child: corps),
          ),
          actions: [
            TextButton(
              key: const Key('fiche_fermer'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
            FilledButton.icon(
              key: const Key('fiche_generer'),
              onPressed: (d == null || !_peut || _enCours) ? null : () => _generer(d, contenu),
              icon: _enCours
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Générer le PDF'),
            ),
          ],
        );
      },
    );
  }
}
