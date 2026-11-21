import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/calcul_classe.dart';
import '../../app/construire_bulletins.dart';
import '../../app/construire_classement.dart';
import '../../app/etat_app.dart';
import '../../data/erreurs.dart';
import '../../data/modeles_donnees.dart';
import '../../documents/elements_pdf.dart';
import '../../documents/modele_bulletin.dart';
import '../../documents/ouvrir_document.dart';
import '../../documents/pdf_bulletin.dart';
import '../../documents/pdf_classement.dart';
import '../../documents/polices_pdf.dart';
import '../../documents/styles_bulletin.dart';
import '../../domain/calendrier.dart';
import '../../domain/permissions.dart';
import '../commun/choix.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../theme.dart';

/// Dernier document produit, rappelé sous les boutons.
class _Document {
  const _Document({
    required this.description,
    required this.chemin,
    required this.pages,
    required this.ouvert,
  });

  final String description;
  final String chemin;
  final int pages;

  /// Le lecteur PDF a-t-il accepté d'ouvrir le fichier ?
  final bool ouvert;
}

/// Édition des bulletins, du classement et des résultats annuels en PDF pour
/// une classe et une période.
///
/// Le PDF est enregistré dans le dossier « Documents\GESCO » puis ouvert dans
/// le lecteur PDF par défaut du système : c'est cet affichage qui sert
/// d'aperçu, et c'est depuis le lecteur que l'on imprime.
class VueBulletins extends StatefulWidget {
  const VueBulletins({
    super.key,
    required this.etat,
    required this.calcul,
    required this.portee,
    required this.periodeLibelle,
    this.ouvreur = ouvrirFichier,
    this.dossier,
    this.chargerPolices = PolicesPdf.charger,
  });

  final EtatApp etat;
  final CalculClasse calcul;
  final Portee portee;
  final String periodeLibelle;

  /// Ouvre un fichier dans le programme par défaut (remplaçable dans les tests).
  final Ouvreur ouvreur;

  /// Dossier d'enregistrement ; « Documents\GESCO » si absent.
  final Directory? dossier;
  final Future<PolicesPdf> Function() chargerPolices;

  @override
  State<VueBulletins> createState() => _VueBulletinsState();
}

class _VueBulletinsState extends State<VueBulletins> {
  StyleBulletin _style = StyleBulletin.classiqueBleu;
  bool _styleChoisi = false;

  /// 0 : toute la classe ; sinon, identifiant d'inscription d'un élève.
  int _eleveId = 0;
  bool _enCours = false;
  _Document? _dernier;

  bool get _peutGenerer => widget.etat.peut(Permission.documentsGenerer);

  @override
  void initState() {
    super.initState();
    _chargerStyle();
  }

  Future<void> _chargerStyle() async {
    try {
      final id = await widget.etat.services.parametres.styleDocuments();
      if (mounted && !_styleChoisi && id != null) {
        setState(() => _style = StyleBulletin.parId(id));
      }
    } catch (_) {
      // Le style par défaut convient.
    }
  }

  Future<void> _choisirStyle(StyleBulletin s) async {
    setState(() {
      _style = s;
      _styleChoisi = true;
    });
    try {
      await widget.etat.services.parametres.definirStyleDocuments(s.id);
    } catch (_) {
      // Le choix reste valable pour cette session même s'il n'est pas mémorisé.
    }
  }

  TypeBulletin get _type {
    if (widget.portee.annuelle) return TypeBulletin.annuel;
    if (widget.portee.estMois) return TypeBulletin.mensuel;
    return TypeBulletin.periodique;
  }

  /// Exécute [fabriquer], enregistre le PDF obtenu puis l'ouvre.
  Future<void> _produire(
    Future<(DocumentPdf, String, String)> Function() fabriquer,
  ) async {
    if (_enCours) return;
    setState(() => _enCours = true);
    _Document? produit;
    try {
      final ok = await executer(context, () async {
        final (pdf, nom, description) = await fabriquer();
        final fichier = await enregistrerPdf(pdf, nom, dossier: widget.dossier);
        final ouvert = await widget.ouvreur(fichier.path);
        produit = _Document(
          description: description,
          chemin: fichier.path,
          pages: pdf.pages,
          ouvert: ouvert,
        );
      });
      if (ok && produit != null && mounted) {
        setState(() => _dernier = produit);
        afficherMessage(
          context,
          produit!.ouvert
              ? '${produit!.description} : PDF enregistré et ouvert.'
              : '${produit!.description} : PDF enregistré. Ouvrez-le depuis le dossier indiqué.',
        );
      }
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  String get _anneeLibelle => widget.etat.anneeCourante?.libelle ?? '';

  Future<(DocumentPdf, String, String)> _fabriquerBulletins() async {
    final s = widget.etat.services;
    final calcul = widget.calcul;
    final classeId = calcul.classe.classe.id;
    final cle = widget.portee.cle;

    final retenus = [
      for (final e in calcul.eleves)
        if (_eleveId == 0 ? e.actif : e.inscriptionId == _eleveId) e,
    ];
    if (retenus.isEmpty) {
      throw const ErreurGesco('Aucun élève actif dans cette classe : il n\'y a rien à imprimer.');
    }

    final etablissement = await s.etablissements.lire();
    final avis = await s.appreciations.eleves(classeId, cle);
    final avisMatieres = await s.appreciations.matieres(classeId, cle);
    final fiches = <int, Eleve>{};
    for (final e in retenus) {
      final fiche = await s.eleves.obtenir(e.eleveId);
      if (fiche != null) fiches[e.eleveId] = fiche;
    }

    final bulletins = construireBulletins(
      calcul: calcul,
      portee: widget.portee,
      periodeLibelle: widget.periodeLibelle,
      type: _type,
      etablissement: etablissement,
      anneeLibelle: _anneeLibelle,
      appreciations: avis,
      appreciationsMatieres: avisMatieres,
      fiches: fiches,
      inscriptions: _eleveId == 0 ? null : {_eleveId},
    );
    final polices = await widget.chargerPolices();
    final pdf = await genererBulletinsPdf(bulletins, style: _style, polices: polices);

    final classe = calcul.classe.classe.nom;
    if (bulletins.length == 1) {
      final b = bulletins.first;
      return (
        pdf,
        'Bulletin ${b.nomComplet} ${widget.periodeLibelle}',
        'Bulletin de ${b.nomComplet}',
      );
    }
    return (
      pdf,
      'Bulletins $classe ${widget.periodeLibelle}',
      '${bulletins.length} bulletins de la classe $classe',
    );
  }

  Future<(DocumentPdf, String, String)> _fabriquerClassement({required bool annuel}) async {
    final calcul = widget.calcul;
    final etablissement = await widget.etat.services.etablissements.lire();
    final document = construireClassement(
      calcul: calcul,
      portee: widget.portee,
      periodeLibelle: widget.periodeLibelle,
      etablissement: etablissement,
      anneeLibelle: _anneeLibelle,
      detaillerPeriodes: annuel,
    );
    final polices = await widget.chargerPolices();
    final pdf = await genererClassementPdf(document, style: _style, polices: polices);
    final classe = calcul.classe.classe.nom;
    return annuel
        ? (pdf, 'Resultats annuels $classe', 'Résultats annuels de la classe $classe')
        : (
            pdf,
            'Classement $classe ${widget.periodeLibelle}',
            'Classement de la classe $classe',
          );
  }

  @override
  Widget build(BuildContext context) {
    final calcul = widget.calcul;
    final actifs = calcul.eleves.where((e) => e.actif).length;
    final optionsEleves = <(int, String)>[
      (0, 'Toute la classe ($actifs élève${actifs > 1 ? 's' : ''})'),
      for (final e in calcul.eleves)
        (e.inscriptionId, e.actif ? e.nomComplet : '${e.nomComplet} (${e.statut.libelle})'),
    ];
    final eleveValide = optionsEleves.any((o) => o.$1 == _eleveId) ? _eleveId : 0;
    final type = _type;
    final peut = _peutGenerer && !_enCours;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Carte(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                switch (type) {
                  TypeBulletin.mensuel => 'Bulletin mensuel · ${widget.periodeLibelle}',
                  TypeBulletin.periodique => 'Bulletin de période · ${widget.periodeLibelle}',
                  TypeBulletin.annuel => 'Bulletin annuel · ${widget.periodeLibelle}',
                },
                key: const Key('bulletin_type'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Format A4. Le PDF s\'ouvre dans votre lecteur PDF : vous y voyez l\'aperçu '
                'et vous pouvez l\'imprimer.',
                style: TextStyle(color: CouleursGesco.gris),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  SizedBox(
                    width: 300,
                    child: ChoixListe<String>(
                      cleChamp: const Key('choix_style'),
                      libelle: 'Style du document',
                      valeur: _style.id,
                      options: [for (final s in StyleBulletin.tous) (s.id, s.nom)],
                      aide: _style.description,
                      onChanged: (id) {
                        if (id != null) _choisirStyle(StyleBulletin.parId(id));
                      },
                    ),
                  ),
                  SizedBox(
                    width: 340,
                    child: ChoixListe<int>(
                      cleChamp: const Key('choix_eleve_bulletin'),
                      libelle: 'Élèves',
                      valeur: eleveValide,
                      options: optionsEleves,
                      onChanged: (v) => setState(() => _eleveId = v ?? 0),
                    ),
                  ),
                  _Apercu(style: _style),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    key: const Key('generer_bulletins'),
                    onPressed: peut ? () => _produire(_fabriquerBulletins) : null,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(eleveValide == 0 ? 'Bulletins de la classe (PDF)' : 'Bulletin (PDF)'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('generer_classement'),
                    onPressed: peut ? () => _produire(() => _fabriquerClassement(annuel: false)) : null,
                    icon: const Icon(Icons.format_list_numbered),
                    label: const Text('Classement (PDF)'),
                  ),
                  if (widget.portee.annuelle)
                    OutlinedButton.icon(
                      key: const Key('generer_resultats_annuels'),
                      onPressed: peut ? () => _produire(() => _fabriquerClassement(annuel: true)) : null,
                      icon: const Icon(Icons.assessment_outlined),
                      label: const Text('Résultats annuels (PDF)'),
                    ),
                  if (_enCours)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        key: Key('bulletins_en_cours'),
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                ],
              ),
              if (!_peutGenerer) ...[
                const SizedBox(height: 12),
                const Text(
                  'Votre compte n\'a pas l\'autorisation de générer les documents.',
                  key: Key('bulletins_interdits'),
                  style: TextStyle(color: CouleursGesco.rouge),
                ),
              ],
            ],
          ),
        ),
        if (_dernier != null) ...[
          const SizedBox(height: 16),
          _CarteDernier(
            document: _dernier!,
            ouvreur: widget.ouvreur,
          ),
        ],
      ],
    );
  }
}

/// Aperçu des couleurs du style choisi.
class _Apercu extends StatelessWidget {
  const _Apercu({required this.style});

  final StyleBulletin style;

  @override
  Widget build(BuildContext context) {
    Widget pastille(Color c) => Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: CouleursGesco.bordure),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        key: const Key('apercu_style'),
        mainAxisSize: MainAxisSize.min,
        children: [
          pastille(Color(style.principale.toInt())),
          pastille(Color(style.accent.toInt())),
          pastille(Color(style.claire.toInt())),
        ],
      ),
    );
  }
}

class _CarteDernier extends StatelessWidget {
  const _CarteDernier({required this.document, required this.ouvreur});

  final _Document document;
  final Ouvreur ouvreur;

  @override
  Widget build(BuildContext context) {
    final dossier = File(document.chemin).parent.path;
    return Carte(
      padding: const EdgeInsets.all(16),
      couleur: CouleursGesco.vertClair,
      bordure: CouleursGesco.vert,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${document.description} · ${document.pages} page${document.pages > 1 ? 's' : ''}',
            key: const Key('dernier_description'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          SelectableText(document.chemin, key: const Key('dernier_chemin')),
          if (!document.ouvert) ...[
            const SizedBox(height: 4),
            const Text(
              'Le fichier n\'a pas pu s\'ouvrir automatiquement : utilisez les boutons ci-dessous.',
              key: Key('dernier_non_ouvert'),
              style: TextStyle(color: CouleursGesco.orange),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('ouvrir_dernier'),
                onPressed: () async {
                  final ok = await ouvreur(document.chemin);
                  if (!ok && context.mounted) {
                    afficherMessage(
                      context,
                      'Impossible d\'ouvrir le fichier. Ouvrez-le depuis le dossier.',
                      erreur: true,
                    );
                  }
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Ouvrir le PDF'),
              ),
              OutlinedButton.icon(
                key: const Key('ouvrir_dossier'),
                onPressed: () async {
                  final ok = await ouvreur(dossier);
                  if (!ok && context.mounted) {
                    afficherMessage(context, 'Impossible d\'ouvrir le dossier.', erreur: true);
                  }
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('Ouvrir le dossier'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
