/// Mise en page A4 des bulletins scolaires en PDF.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/arrondi.dart';
import 'elements_pdf.dart';
import 'modele_bulletin.dart';
import 'polices_pdf.dart';
import 'styles_bulletin.dart';

export 'elements_pdf.dart' show DocumentPdf;

/// Produit un PDF A4 : une page par bulletin (davantage si la classe compte
/// un très grand nombre de matières).
Future<DocumentPdf> genererBulletinsPdf(
  List<Bulletin> bulletins, {
  required StyleBulletin style,
  required PolicesPdf polices,
}) async {
  if (bulletins.isEmpty) {
    throw ArgumentError('Aucun bulletin à imprimer.');
  }
  final premier = bulletins.first;
  final outils = OutilsPdf(style: style, polices: polices);
  final doc = pw.Document(
    title: bulletins.length == 1
        ? '${premier.titre} - ${premier.nomComplet}'
        : '${premier.titre} - ${premier.classeNom}',
    author: premier.etablissementNom,
    creator: 'GESCO',
    subject: 'Année scolaire ${premier.anneeLibelle}',
  );
  for (final b in bulletins) {
    doc.addPage(_PageBulletin(b, outils).construire());
  }
  final octets = await doc.save();
  return DocumentPdf(octets: octets, pages: doc.document.pdfPageList.pages.length);
}

/// Taille du texte et espacement des lignes selon le nombre de matières, pour
/// que le bulletin tienne sur une page.
class _Densite {
  const _Densite(this.police, this.rembourrage);

  factory _Densite.pour(int nbLignes) {
    if (nbLignes <= 12) return const _Densite(9.5, 4.2);
    if (nbLignes <= 16) return const _Densite(9, 3.4);
    if (nbLignes <= 21) return const _Densite(8.5, 2.6);
    if (nbLignes <= 26) return const _Densite(8, 2.0);
    return const _Densite(7.5, 1.6);
  }

  final double police;
  final double rembourrage;
}

class _PageBulletin {
  _PageBulletin(this.b, this.o) : d = _Densite.pour(b.lignes.length);

  final Bulletin b;
  final OutilsPdf o;
  final _Densite d;

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
        o.entete(EnteteEtablissement(
          nom: b.etablissementNom,
          adresse: b.adresse,
          telephone: b.telephone,
          email: b.email,
          devise: b.devise,
          infosAdmin: b.infosAdmin,
          logo: b.logo,
        )),
        pw.SizedBox(height: 8),
        o.titre(
          b.titre,
          sousTitre: b.anneeLibelle.isEmpty ? '' : 'Année scolaire ${b.anneeLibelle}',
        ),
        pw.SizedBox(height: 8),
        _eleve(),
        pw.SizedBox(height: 8),
        _tableau(),
        pw.SizedBox(height: 8),
        _synthese(),
        if (b.periodes.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          _recapitulatifPeriodes(),
        ],
        pw.SizedBox(height: 8),
        _avis(),
        pw.SizedBox(height: 10),
        _signatures(),
      ],
    );
  }

  // ------------------------------------------------------------ Bloc élève

  pw.Widget _info(String etiquette, String valeur, {bool gras = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2.5),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(text: '$etiquette : ', style: o.st(9, couleur: s.discret)),
            pw.TextSpan(text: valeur, style: o.st(9.5, gras: gras)),
          ],
        ),
      ),
    );
  }

  pw.Widget _eleve() {
    final photo = o.image(b.photo);
    return o.cadre(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (photo != null)
            pw.Container(
              width: 56,
              height: 70,
              margin: const pw.EdgeInsets.only(right: 10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: s.bordure, width: 0.5),
              ),
              child: pw.Image(photo, fit: pw.BoxFit.contain),
            ),
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _info('Élève', b.nomComplet, gras: true),
                _info('Matricule', b.matricule),
                if (b.naissance.isNotEmpty)
                  pw.Text(b.naissance, style: o.st(9.5)),
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            flex: 2,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _info('Classe', b.classeNom, gras: true),
                if (b.niveau.trim().isNotEmpty) _info('Niveau', b.niveau.trim()),
                _info('Sexe', b.sexe == 'F' ? 'Féminin' : 'Masculin'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------ Tableau des notes

  pw.Widget _tableau() {
    if (b.lignes.isEmpty) {
      return pw.Text(
        'Aucune matière n\'est enregistrée pour cette classe.',
        style: o.st(9.5, couleur: s.discret, italique: true),
      );
    }
    final corps = o.st(d.police);
    final gras = o.st(d.police, gras: true);
    const gaucheTexte = pw.TextAlign.left;
    const gauche = pw.Alignment.centerLeft;

    return pw.Table(
      border: o.bordureTableau,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: pw.FlexColumnWidth(3.4),
        1: pw.FixedColumnWidth(30),
        2: pw.FixedColumnWidth(38),
        3: pw.FixedColumnWidth(40),
        4: pw.FixedColumnWidth(34),
        5: pw.FixedColumnWidth(34),
        6: pw.FixedColumnWidth(38),
        7: pw.FlexColumnWidth(3.2),
      },
      children: [
        o.enteteTableau(
          const ['Matière', 'Coef.', 'Note\n/20', 'Moy.\nclasse', 'Min.', 'Max.', 'Rang', 'Appréciation'],
          taille: d.police - 0.5,
          rembourrage: d.rembourrage + 0.5,
          aGauche: const {0, 7},
        ),
        for (var i = 0; i < b.lignes.length; i++)
          pw.TableRow(
            decoration: i.isOdd ? pw.BoxDecoration(color: s.claire) : null,
            children: [
              o.cellule(
                b.lignes[i].facultative ? '${b.lignes[i].matiere} (facultative)' : b.lignes[i].matiere,
                style: b.lignes[i].facultative ? o.st(d.police, italique: true) : corps,
                alignement: gauche,
                alignementTexte: gaucheTexte,
                rembourrage: d.rembourrage,
              ),
              o.cellule(
                b.lignes[i].facultative ? '—' : formaterCoefficient(b.lignes[i].coefficient),
                style: corps,
                rembourrage: d.rembourrage,
              ),
              o.cellule(formaterCentiemes(b.lignes[i].note),
                  style: gras, rembourrage: d.rembourrage),
              o.cellule(formaterCentiemes(b.lignes[i].moyenneClasse),
                  style: corps, rembourrage: d.rembourrage),
              o.cellule(formaterCentiemes(b.lignes[i].minClasse),
                  style: corps, rembourrage: d.rembourrage),
              o.cellule(formaterCentiemes(b.lignes[i].maxClasse),
                  style: corps, rembourrage: d.rembourrage),
              o.cellule(b.lignes[i].rang == null ? '—' : formaterRang(b.lignes[i].rang!),
                  style: corps, rembourrage: d.rembourrage),
              o.cellule(
                b.lignes[i].appreciation,
                style: o.st(d.police - 0.5),
                alignement: gauche,
                alignementTexte: gaucheTexte,
                rembourrage: d.rembourrage,
              ),
            ],
          ),
      ],
    );
  }

  // ------------------------------------------------------------ Synthèse

  pw.Widget _tuile(
    String etiquette,
    String valeur, {
    bool vedette = false,
    int flex = 1,
    double taille = 11.5,
  }) {
    final plein = s.enteteTableauPlein;
    final surFond = vedette && plein;
    final couleurTexte = surFond ? s.surPrincipale : s.texte;
    return pw.Expanded(
      flex: flex,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        decoration: pw.BoxDecoration(
          color: surFond ? s.principale : null,
          border: pw.Border.all(
            color: vedette ? s.principale : s.bordure,
            width: vedette ? 1.2 : 0.7,
          ),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(
              etiquette,
              style: o.st(7.5, couleur: surFond ? s.surPrincipale : s.discret),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              valeur,
              style: o.st(taille, couleur: couleurTexte, gras: true),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String get _texteRang {
    final r = b.rang;
    if (r == null) return '—';
    return b.exAequo ? '${formaterRang(r)} ex æquo' : formaterRang(r);
  }

  pw.Widget _synthese() {
    final aDesStats =
        b.moyenneClasse != null || b.meilleureMoyenne != null || b.plusFaibleMoyenne != null;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _tuile(
              'Moyenne générale',
              b.moyenne == null ? '—' : '${formaterCentiemes(b.moyenne)} / 20',
              vedette: true,
              taille: 13,
            ),
            pw.SizedBox(width: 6),
            _tuile(b.rang == null ? 'Rang' : 'Rang sur ${b.effectif}', _texteRang),
            pw.SizedBox(width: 6),
            _tuile('Mention', b.mention.isEmpty ? '—' : b.mention),
            pw.SizedBox(width: 6),
            _tuile('Décision', b.decision.isEmpty ? '—' : b.decision),
          ],
        ),
        if (aDesStats) ...[
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Moyenne de la classe : ${formaterCentiemes(b.moyenneClasse)}',
                  style: o.st(8.5, couleur: s.discret)),
              pw.Text('Plus forte moyenne : ${formaterCentiemes(b.meilleureMoyenne)}',
                  style: o.st(8.5, couleur: s.discret)),
              pw.Text('Plus faible moyenne : ${formaterCentiemes(b.plusFaibleMoyenne)}',
                  style: o.st(8.5, couleur: s.discret)),
            ],
          ),
        ],
        if (b.incomplet && b.moyenne != null) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            'Résultat provisoire : certaines notes ne sont pas saisies, '
            'la moyenne porte sur les notes disponibles.',
            style: o.st(8, couleur: s.discret, italique: true),
          ),
        ],
        if (b.moyenne == null) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            'Aucune note chiffrée : la moyenne et le rang ne peuvent pas être calculés.',
            style: o.st(8, couleur: s.discret, italique: true),
          ),
        ],
      ],
    );
  }

  // ------------------------------------------- Récapitulatif (bulletin annuel)

  pw.Widget _recapitulatifPeriodes() {
    final titres = ['', for (final p in b.periodes) p.libelle, b.recapitulatifFinal];
    final moyennes = [
      'Moyenne',
      for (final p in b.periodes) formaterCentiemes(p.moyenne),
      formaterCentiemes(b.moyenne),
    ];
    final rangs = [
      'Rang',
      for (final p in b.periodes) p.rang == null ? '—' : formaterRang(p.rang!),
      b.rang == null ? '—' : formaterRang(b.rang!),
    ];
    pw.TableRow ligne(List<String> valeurs, {required bool gras}) => pw.TableRow(
          children: [
            for (var i = 0; i < valeurs.length; i++)
              o.cellule(
                valeurs[i],
                style: o.st(8.5, gras: gras || i == 0 || i == valeurs.length - 1),
                alignement: i == 0 ? pw.Alignment.centerLeft : pw.Alignment.center,
                alignementTexte: i == 0 ? pw.TextAlign.left : pw.TextAlign.center,
                rembourrage: 2.5,
              ),
          ],
        );
    return pw.Table(
      border: o.bordureTableau,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: {
        0: const pw.FixedColumnWidth(70),
        for (var i = 1; i < titres.length; i++) i: const pw.FlexColumnWidth(1),
      },
      children: [
        o.enteteTableau(titres, taille: 8.5, rembourrage: 3),
        ligne(moyennes, gras: false),
        ligne(rangs, gras: false),
      ],
    );
  }

  // ----------------------------------------------------- Avis et décision

  pw.Widget _encadre(String titre, String texte) {
    return o.cadre(
      hauteurMin: 48,
      padding: const pw.EdgeInsets.all(6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(titre, style: o.st(8, couleur: s.principale, gras: true)),
          if (texte.trim().isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text(texte.trim(), style: o.st(9)),
          ],
        ],
      ),
    );
  }

  pw.Widget _avis() {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 3,
          child: _encadre('Appréciation du conseil de classe', b.appreciation),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          flex: 2,
          child: _encadre('Décision du conseil de classe', b.decisionConseil),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ Signatures

  pw.Widget _signature(String role, {Uint8List? signature, Uint8List? cachet, String nom = ''}) {
    final imageSignature = o.image(signature);
    final imageCachet = o.image(cachet);
    return pw.Expanded(
      child: pw.Column(
        children: [
          pw.Text(role, style: o.st(8.5, couleur: s.discret, gras: true)),
          pw.SizedBox(
            height: 58,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (imageSignature != null) pw.Image(imageSignature, height: 44),
                if (imageSignature != null && imageCachet != null) pw.SizedBox(width: 8),
                if (imageCachet != null) pw.Image(imageCachet, height: 54),
              ],
            ),
          ),
          if (nom.trim().isNotEmpty)
            pw.Text(nom.trim(), style: o.st(9, gras: true), textAlign: pw.TextAlign.center),
        ],
      ),
    );
  }

  pw.Widget _signatures() {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _signature('Le professeur principal'),
        _signature('Les parents ou le tuteur'),
        _signature('Le directeur', signature: b.signature, cachet: b.cachet, nom: b.directeur),
      ],
    );
  }

  // ---------------------------------------------------------------- Pied

  pw.Widget _pied(pw.Context context) => o.pied(
        '${b.nomComplet}  ·  ${b.classeNom}',
        'Édité le ${dateFrancaise(b.dateEdition ?? DateTime.now())}',
      );
}
