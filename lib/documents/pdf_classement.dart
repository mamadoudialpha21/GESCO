/// Mise en page A4 des classements et des résultats annuels en PDF.
library;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/arrondi.dart';
import '../domain/statistiques.dart';
import 'elements_pdf.dart';
import 'modele_classement.dart';
import 'polices_pdf.dart';
import 'styles_bulletin.dart';

export 'elements_pdf.dart' show DocumentPdf;

/// Produit le PDF d'un classement (une classe, plusieurs pages si nécessaire).
Future<DocumentPdf> genererClassementPdf(
  DocumentClassement document, {
  required StyleBulletin style,
  required PolicesPdf polices,
}) async {
  final outils = OutilsPdf(style: style, polices: polices);
  final doc = pw.Document(
    title: '${document.titre} - ${document.classeNom}',
    author: document.entete.nom,
    creator: 'GESCO',
    subject: 'Année scolaire ${document.anneeLibelle}',
  );
  doc.addPage(_PageClassement(document, outils).construire());
  final octets = await doc.save();
  return DocumentPdf(octets: octets, pages: doc.document.pdfPageList.pages.length);
}

class _PageClassement {
  _PageClassement(this.d, this.o) : _pad = _rembourragePour(d.lignes.length);

  final DocumentClassement d;
  final OutilsPdf o;

  /// Espace vertical dans chaque ligne : réduit quand la classe est nombreuse,
  /// pour qu'une classe d'une trentaine d'élèves tienne sur une page.
  final double _pad;

  static double _rembourragePour(int nbLignes) {
    if (nbLignes <= 24) return 3.2;
    if (nbLignes <= 30) return 2.4;
    return 2.0;
  }

  StyleBulletin get s => o.style;

  pw.MultiPage construire() {
    return pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 26),
        theme: o.theme,
      ),
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      footer: _pied,
      build: (context) => [
        o.entete(d.entete),
        pw.SizedBox(height: 8),
        o.titre(
          d.titre,
          sousTitre: [
            if (d.sousTitre.isNotEmpty) d.sousTitre,
            'Classe ${d.classeNom}',
            if (d.anneeLibelle.isNotEmpty) 'Année scolaire ${d.anneeLibelle}',
          ].join('  ·  '),
        ),
        pw.SizedBox(height: 8),
        _tableau(),
        if (d.lignes.any((l) => l.exAequo)) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            'ex : ex æquo (rang partagé avec un autre élève).',
            style: o.st(8, couleur: s.discret, italique: true),
          ),
        ],
        if (d.stats != null) ...[
          pw.SizedBox(height: 10),
          _statistiques(d.stats!),
        ],
        pw.SizedBox(height: 14),
        _directeur(),
      ],
    );
  }

  // --------------------------------------------------------------- Tableau

  pw.Widget _tableau() {
    if (d.lignes.isEmpty) {
      return pw.Text(
        'Aucun élève dans cette classe.',
        style: o.st(9.5, couleur: s.discret, italique: true),
      );
    }
    final nbPeriodes = d.periodes.length;
    final corps = o.st(9);
    final gras = o.st(9, gras: true);
    final discret = o.st(9, couleur: s.discret, italique: true);

    final titres = [
      'Rang',
      'Nom et prénoms',
      'Matricule',
      ...d.periodes,
      d.libelleMoyenne,
      'Mention',
      if (d.avecDecision) 'Décision',
    ];
    final colonnes = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(44),
      1: const pw.FlexColumnWidth(3.4),
      2: const pw.FixedColumnWidth(58),
      for (var i = 0; i < nbPeriodes; i++) 3 + i: const pw.FixedColumnWidth(44),
      3 + nbPeriodes: const pw.FixedColumnWidth(54),
      4 + nbPeriodes: const pw.FlexColumnWidth(1.5),
      if (d.avecDecision) 5 + nbPeriodes: const pw.FlexColumnWidth(1.8),
    };

    return pw.Table(
      border: o.bordureTableau,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: colonnes,
      children: [
        o.enteteTableau(
          titres,
          taille: 8.5,
          aGauche: const {1},
        ),
        for (var i = 0; i < d.lignes.length; i++) _ligne(d.lignes[i], i, corps, gras, discret),
      ],
    );
  }

  pw.TableRow _ligne(
    LigneDocClassement l,
    int index,
    pw.TextStyle corps,
    pw.TextStyle gras,
    pw.TextStyle discret,
  ) {
    final classe = l.rang != null;
    final podium = classe && l.rang! <= 3;
    final style = classe ? corps : discret;
    final rang = l.rang == null ? '—' : '${formaterRang(l.rang!)}${l.exAequo ? ' ex' : ''}';
    final decision = l.decision.isNotEmpty ? l.decision : l.observation;
    return pw.TableRow(
      decoration: index.isOdd ? pw.BoxDecoration(color: s.claire) : null,
      children: [
        o.cellule(rang,
            style: podium ? o.st(9, couleur: s.accent, gras: true) : style, rembourrage: _pad),
        o.cellule(
          l.nom,
          style: classe ? gras : discret,
          alignement: pw.Alignment.centerLeft,
          alignementTexte: pw.TextAlign.left,
          rembourrage: _pad,
        ),
        o.cellule(l.matricule, style: style, rembourrage: _pad),
        for (var i = 0; i < d.periodes.length; i++)
          o.cellule(
            formaterCentiemes(i < l.moyennesPeriodes.length ? l.moyennesPeriodes[i] : null),
            style: style,
            rembourrage: _pad,
          ),
        o.cellule(
          '${formaterCentiemes(l.moyenne)}${l.incomplet && l.moyenne != null ? ' *' : ''}',
          style: classe ? gras : style,
          rembourrage: _pad,
        ),
        o.cellule(l.mention.isEmpty ? '—' : l.mention, style: style, rembourrage: _pad),
        if (d.avecDecision)
          o.cellule(decision.isEmpty ? '—' : decision, style: style, rembourrage: _pad),
      ],
    );
  }

  // ----------------------------------------------------------- Statistiques

  pw.Widget _tuile(String etiquette, String valeur) {
    return pw.Expanded(
      child: o.cadre(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(
              etiquette,
              style: o.st(7.5, couleur: s.discret),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 2),
            pw.Text(valeur, style: o.st(10.5, gras: true), textAlign: pw.TextAlign.center),
          ],
        ),
      ),
    );
  }

  pw.Widget _statistiques(StatsClasse st) {
    final taux = st.tauxReussiteCentiemes;
    final mentions = [
      for (final e in st.repartitionMentions.entries)
        if (e.key != sansMention && e.value > 0) '${e.key} : ${e.value}',
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _tuile('Effectif', '${st.effectif}'),
            pw.SizedBox(width: 5),
            _tuile('Évalués', '${st.evalues}'),
            pw.SizedBox(width: 5),
            _tuile('Admis', '${st.admis}'),
            pw.SizedBox(width: 5),
            _tuile('Taux de réussite', taux == null ? '—' : '${formaterCentiemes(taux)} %'),
            pw.SizedBox(width: 5),
            _tuile('Moyenne de la classe', formaterCentiemes(st.moyenneClasse)),
            pw.SizedBox(width: 5),
            _tuile('Meilleure', formaterCentiemes(st.meilleureMoyenne)),
            pw.SizedBox(width: 5),
            _tuile('Plus faible', formaterCentiemes(st.plusFaibleMoyenne)),
          ],
        ),
        if (mentions.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            'Mentions : ${mentions.join('  ·  ')}',
            style: o.st(8.5, couleur: s.discret),
          ),
        ],
        if (d.lignes.any((l) => l.incomplet && l.moyenne != null)) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            '* Résultat provisoire : certaines notes ne sont pas encore saisies.',
            style: o.st(8, couleur: s.discret, italique: true),
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------ Directeur

  pw.Widget _directeur() {
    final signature = o.image(d.signature);
    final cachet = o.image(d.cachet);
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.SizedBox(
          width: 190,
          child: pw.Column(
            children: [
              pw.Text('Le directeur', style: o.st(8.5, couleur: s.discret, gras: true)),
              pw.SizedBox(
                height: 50,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (signature != null) pw.Image(signature, height: 38),
                    if (signature != null && cachet != null) pw.SizedBox(width: 8),
                    if (cachet != null) pw.Image(cachet, height: 48),
                  ],
                ),
              ),
              if (d.directeur.trim().isNotEmpty)
                pw.Text(
                  d.directeur.trim(),
                  style: o.st(9, gras: true),
                  textAlign: pw.TextAlign.center,
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- Pied

  pw.Widget _pied(pw.Context context) => o.pied(
        '${d.titre}  ·  ${d.classeNom}  ·  Édité le '
        '${dateFrancaise(d.dateEdition ?? DateTime.now())}',
        'Page ${context.pageNumber} / ${context.pagesCount}',
      );
}
