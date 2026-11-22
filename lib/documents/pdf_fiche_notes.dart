/// Mise en page A4 des fiches de notes et des listes de classe en PDF.
library;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'elements_pdf.dart';
import 'modele_fiche_notes.dart';
import 'polices_pdf.dart';
import 'styles_bulletin.dart';

export 'elements_pdf.dart' show DocumentPdf;

/// Au-delà de ce nombre de colonnes (notes + observations), la page passe en
/// paysage pour que chaque case reste assez large pour écrire.
const int colonnesMaxPortrait = 7;

/// La fiche s'imprime en paysage quand elle a trop de colonnes pour le portrait.
bool ficheEnPaysage(FicheNotes f) =>
    f.intitules.length + (f.avecObservations ? 1 : 0) > colonnesMaxPortrait;

/// Produit le PDF des [fiches] : chacune commence sur une nouvelle page et
/// occupe autant de pages que nécessaire.
Future<DocumentPdf> genererFichesNotesPdf(
  List<FicheNotes> fiches, {
  required StyleBulletin style,
  required PolicesPdf polices,
}) async {
  if (fiches.isEmpty) {
    throw ArgumentError('Aucune fiche à imprimer.');
  }
  final outils = OutilsPdf(style: style, polices: polices);
  final premiere = fiches.first;
  final doc = pw.Document(
    title: fiches.length == 1
        ? '${premiere.titre} - ${premiere.classeNom}'
            '${premiere.matiereNom == null ? '' : ' - ${premiere.matiereNom}'}'
        : 'Fiches de notes - ${premiere.classeNom}',
    author: premiere.entete.nom,
    creator: 'GESCO',
    subject: premiere.anneeLibelle.isEmpty
        ? ''
        : 'Année scolaire ${premiere.anneeLibelle}',
  );
  for (final fiche in fiches) {
    doc.addPage(_PageFicheNotes(fiche, outils).construire());
  }
  final octets = await doc.save();
  return DocumentPdf(octets: octets, pages: doc.document.pdfPageList.pages.length);
}

class _PageFicheNotes {
  _PageFicheNotes(this.f, this.o);

  final FicheNotes f;
  final OutilsPdf o;

  StyleBulletin get s => o.style;

  bool get _paysage => ficheEnPaysage(f);

  /// Hauteur d'une ligne : assez grande pour écrire à la main, réduite quand
  /// la classe est nombreuse.
  double get _hauteurLigne => f.lignes.length <= 25 ? 22 : 19;

  pw.MultiPage construire() {
    return pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: _paysage ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 26),
        theme: o.theme,
      ),
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      footer: _pied,
      build: (context) => [
        o.entete(f.entete),
        pw.SizedBox(height: 8),
        o.titre(
          f.titre,
          sousTitre: [
            'Classe ${f.classeNom}',
            if (f.matiereNom != null) f.matiereNom!,
            if (f.anneeLibelle.isNotEmpty) 'Année scolaire ${f.anneeLibelle}',
          ].join('  ·  '),
        ),
        pw.SizedBox(height: 8),
        _informations(),
        pw.SizedBox(height: 8),
        _tableau(),
        pw.SizedBox(height: 4),
        _legende(),
        pw.SizedBox(height: 14),
        _signatures(),
      ],
    );
  }

  // ---------------------------------------------------------- Informations

  /// Une information : étiquette suivie de sa valeur, ou d'un
  /// trait à remplir à la main quand la valeur est inconnue.
  pw.Widget _champ(String etiquette, String valeur, {double largeurLigne = 110}) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text('$etiquette : ', style: o.st(9, couleur: s.discret)),
        if (valeur.trim().isNotEmpty)
          pw.Text(valeur.trim(), style: o.st(9.5, gras: true))
        else
          pw.Container(
            width: largeurLigne,
            height: 11,
            decoration: pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: s.discret, width: 0.5)),
            ),
          ),
      ],
    );
  }

  pw.Widget _informations() {
    final effectif = f.lignes.length;
    final repartition = effectif > 0 && f.nbFilles + f.nbGarcons == effectif
        ? ' (${f.nbFilles} fille${f.nbFilles > 1 ? 's' : ''}, '
            '${f.nbGarcons} garçon${f.nbGarcons > 1 ? 's' : ''})'
        : '';
    return o.cadre(
      rempli: true,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: pw.Wrap(
        spacing: 22,
        runSpacing: 6,
        children: [
          if (!f.estListe) _champ('Enseignant', f.enseignant, largeurLigne: 130),
          if (!f.estListe) _champ('Notes sur', '${f.bareme}'),
          if (!f.estListe && f.evaluation.isNotEmpty) _champ('Évaluation', f.evaluation),
          if (!f.estListe) _champ('Période', f.periode, largeurLigne: 90),
          if (!f.estListe && f.evaluation.isEmpty && f.intitules.isNotEmpty)
            _champ('Date', '', largeurLigne: 70),
          _champ('Effectif', '$effectif élève${effectif > 1 ? 's' : ''}$repartition'),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- Tableau

  pw.Widget _tableau() {
    if (f.lignes.isEmpty) {
      return pw.Text(
        'Aucun élève dans cette classe.',
        style: o.st(9.5, couleur: s.discret, italique: true),
      );
    }
    final titres = [
      'N°',
      'Nom et prénoms',
      if (f.avecMatricule) 'Matricule',
      if (f.avecSexe) 'Sexe',
      ...f.intitules,
      if (f.avecObservations) 'Observations',
    ];
    var colonne = 0;
    final colonnes = <int, pw.TableColumnWidth>{
      colonne++: const pw.FixedColumnWidth(26),
      colonne++: const pw.FlexColumnWidth(3.6),
      if (f.avecMatricule) colonne++: const pw.FixedColumnWidth(62),
      if (f.avecSexe) colonne++: const pw.FixedColumnWidth(30),
      for (var i = 0; i < f.intitules.length; i++)
        colonne++: const pw.FlexColumnWidth(1.15),
      if (f.avecObservations) colonne++: const pw.FlexColumnWidth(1.8),
    };

    final corps = o.st(9.5);
    final gras = o.st(9.5, gras: true);
    final discret = o.st(8.5, couleur: s.discret);

    return pw.Table(
      border: o.bordureTableau,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: colonnes,
      children: [
        o.enteteTableau(titres, taille: 8.5, aGauche: const {1}),
        for (var i = 0; i < f.lignes.length; i++) _ligne(f.lignes[i], i, corps, gras, discret),
      ],
    );
  }

  pw.TableRow _ligne(
    LigneFicheNotes l,
    int index,
    pw.TextStyle corps,
    pw.TextStyle gras,
    pw.TextStyle discret,
  ) {
    final h = _hauteurLigne;
    pw.Widget vide() => pw.SizedBox(height: h);
    return pw.TableRow(
      decoration: index.isOdd ? pw.BoxDecoration(color: s.claire) : null,
      children: [
        pw.Container(
          height: h,
          alignment: pw.Alignment.center,
          child: pw.Text('${l.numero}', style: discret),
        ),
        pw.Container(
          height: h,
          alignment: pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          child: pw.Text(l.nom, style: gras),
        ),
        if (f.avecMatricule)
          pw.Container(
            height: h,
            alignment: pw.Alignment.center,
            child: pw.Text(l.matricule, style: corps),
          ),
        if (f.avecSexe)
          pw.Container(
            height: h,
            alignment: pw.Alignment.center,
            child: pw.Text(l.sexe, style: corps),
          ),
        for (var i = 0; i < f.intitules.length; i++) vide(),
        if (f.avecObservations) vide(),
      ],
    );
  }

  // --------------------------------------------------------------- Légende

  pw.Widget _legende() {
    if (f.estListe || f.intitules.isEmpty) return pw.SizedBox();
    final bareme = f.bareme;
    return pw.Text(
      'Notes de 0 à $bareme (virgule permise : ${bareme * 7 ~/ 10},5).  '
      'Élève absent : écrire ABS.  Élève dispensé : écrire DISP.  '
      'Case vide : note non remise.',
      style: o.st(8, couleur: s.discret, italique: true),
    );
  }

  // ------------------------------------------------------------ Signatures

  pw.Widget _zone(String titre, {String detail = ''}) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(titre, style: o.st(8.5, couleur: s.discret, gras: true)),
          if (detail.isNotEmpty) pw.Text(detail, style: o.st(8, couleur: s.discret)),
          pw.SizedBox(height: 34),
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 14),
            height: 0.5,
            color: s.discret,
          ),
        ],
      ),
    );
  }

  pw.Widget _signatures() {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _zone('Date de remise de la fiche'),
        _zone(
          f.estListe ? 'Le titulaire de la classe' : 'Le professeur',
          detail: 'nom et signature',
        ),
        _zone('Visa de la direction'),
      ],
    );
  }

  // ---------------------------------------------------------------- Pied

  pw.Widget _pied(pw.Context context) => o.pied(
        '${f.estListe ? 'Liste de classe' : 'Fiche de notes'}'
        '  ·  ${f.classeNom}'
        '${f.matiereNom == null ? '' : '  ·  ${f.matiereNom}'}'
        '  ·  Édité le ${dateFrancaise(f.dateEdition ?? DateTime.now())}',
        'Page ${context.pageNumber} / ${context.pagesCount}',
      );
}
