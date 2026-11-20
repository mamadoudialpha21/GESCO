/// Éléments de mise en page communs à tous les documents PDF : en-tête de
/// l'établissement, styles de texte, cadres, images.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'polices_pdf.dart';
import 'styles_bulletin.dart';

/// Un document PDF produit.
class DocumentPdf {
  const DocumentPdf({required this.octets, required this.pages});

  final Uint8List octets;
  final int pages;
}

/// Ce que l'en-tête d'un document affiche de l'établissement.
class EnteteEtablissement {
  const EnteteEtablissement({
    required this.nom,
    this.adresse = '',
    this.telephone = '',
    this.email = '',
    this.devise = '',
    this.infosAdmin = '',
    this.logo,
  });

  final String nom;
  final String adresse;
  final String telephone;
  final String email;
  final String devise;

  /// Informations libres (agrément, BP...), une par ligne.
  final String infosAdmin;
  final Uint8List? logo;
}

/// Date au format « 05/03/2026 ».
String dateFrancaise(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Outils de mise en page d'un document, liés à un style et à des polices.
class OutilsPdf {
  OutilsPdf({required this.style, required this.polices});

  final StyleBulletin style;
  final PolicesPdf polices;

  // Un même fichier d'image n'est décodé et incorporé qu'une fois par document
  // (le logo et le cachet figurent sur chaque bulletin).
  final Map<Uint8List, pw.ImageProvider?> _images = Map.identity();

  pw.ThemeData get theme => polices.theme(serif: style.serif);

  /// Image prête à placer, ou null si les octets sont vides ou illisibles.
  pw.ImageProvider? image(Uint8List? octets) {
    if (octets == null || octets.isEmpty) return null;
    return _images.putIfAbsent(octets, () {
      try {
        return pw.MemoryImage(octets);
      } catch (_) {
        return null;
      }
    });
  }

  pw.TextStyle st(
    double taille, {
    PdfColor? couleur,
    bool gras = false,
    bool italique = false,
  }) =>
      pw.TextStyle(
        fontSize: taille,
        color: couleur ?? style.texte,
        fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
        fontStyle: italique ? pw.FontStyle.italic : pw.FontStyle.normal,
      );

  /// Trait horizontal plein.
  pw.Widget filet(PdfColor couleur, double epaisseur) =>
      pw.Container(height: epaisseur, color: couleur);

  /// Cadre aux coins arrondis, fond clair facultatif.
  pw.Widget cadre({
    required pw.Widget child,
    bool rempli = false,
    pw.EdgeInsets padding = const pw.EdgeInsets.all(6),
    PdfColor? bordure,
    double epaisseur = 0.7,
    double? hauteurMin,
  }) {
    return pw.Container(
      constraints: hauteurMin == null ? null : pw.BoxConstraints(minHeight: hauteurMin),
      padding: padding,
      decoration: pw.BoxDecoration(
        color: rempli ? style.claire : null,
        border: pw.Border.all(color: bordure ?? style.bordure, width: epaisseur),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: child,
    );
  }

  /// En-tête : logo, nom de l'établissement, devise, coordonnées, décor du style.
  pw.Widget entete(EnteteEtablissement e) {
    final s = style;
    final sombre = s.ornement == OrnementEntete.bandeau;
    final couleurNom = sombre ? s.surPrincipale : s.principale;
    final couleurInfo = sombre ? s.surPrincipale : s.discret;
    final logo = image(e.logo);

    final contact = [
      if (e.telephone.trim().isNotEmpty) 'Tél. ${e.telephone.trim()}',
      if (e.email.trim().isNotEmpty) e.email.trim(),
    ].join('  ·  ');
    final infos = <String>[
      if (e.adresse.trim().isNotEmpty) e.adresse.trim(),
      if (contact.isNotEmpty) contact,
      for (final l in e.infosAdmin.split('\n'))
        if (l.trim().isNotEmpty) l.trim(),
    ];

    final contenu = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logo != null)
          pw.Container(
            width: 58,
            height: 58,
            margin: const pw.EdgeInsets.only(right: 12),
            padding: sombre ? const pw.EdgeInsets.all(3) : null,
            decoration: sombre
                ? pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(4),
                  )
                : null,
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (e.nom.trim().isNotEmpty)
                pw.Text(
                  e.nom.trim().toUpperCase(),
                  style: st(15, couleur: couleurNom, gras: true),
                ),
              if (e.devise.trim().isNotEmpty)
                pw.Text(
                  '« ${e.devise.trim()} »',
                  style: st(8.5, couleur: couleurInfo, italique: true),
                ),
              for (final l in infos) pw.Text(l, style: st(8, couleur: couleurInfo)),
            ],
          ),
        ),
      ],
    );

    switch (s.ornement) {
      case OrnementEntete.tricolore:
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              children: [
                for (final c in [rougeGuinee, jauneGuinee, vertGuinee])
                  pw.Expanded(child: pw.Container(height: 5, color: c)),
              ],
            ),
            pw.SizedBox(height: 8),
            contenu,
            pw.SizedBox(height: 6),
            filet(s.principale, 1.2),
          ],
        );
      case OrnementEntete.bandeau:
        return pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: s.principale,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: contenu,
        );
      case OrnementEntete.doubleFilet:
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            contenu,
            pw.SizedBox(height: 6),
            filet(s.principale, 2.4),
            pw.SizedBox(height: 2),
            filet(s.accent, 0.7),
          ],
        );
      case OrnementEntete.filet:
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [contenu, pw.SizedBox(height: 6), filet(s.principale, 2)],
        );
      case OrnementEntete.sobre:
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [contenu, pw.SizedBox(height: 6), filet(s.texte, 0.8)],
        );
    }
  }

  /// Encadré du titre du document, centré.
  pw.Widget titre(String texte, {String sousTitre = ''}) {
    final s = style;
    return pw.Container(
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: pw.BoxDecoration(
        color: s.enteteTableauPlein ? s.claire : null,
        border: pw.Border.all(color: s.principale, width: 0.9),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(texte, style: st(13.5, couleur: s.principale, gras: true)),
          if (sousTitre.isNotEmpty)
            pw.Text(sousTitre, style: st(9, couleur: s.discret)),
        ],
      ),
    );
  }

  /// Cellule d'un tableau.
  pw.Widget cellule(
    String texte, {
    required pw.TextStyle style,
    pw.Alignment alignement = pw.Alignment.center,
    pw.TextAlign alignementTexte = pw.TextAlign.center,
    double rembourrage = 3,
  }) {
    return pw.Container(
      alignment: alignement,
      padding: pw.EdgeInsets.symmetric(horizontal: 4, vertical: rembourrage),
      child: pw.Text(texte, style: style, textAlign: alignementTexte),
    );
  }

  /// Ligne d'en-tête d'un tableau, répétée à chaque page.
  pw.TableRow enteteTableau(
    List<String> titres, {
    required double taille,
    double rembourrage = 4,
    Set<int> aGauche = const {0},
  }) {
    final s = style;
    final plein = s.enteteTableauPlein;
    final styleTitre = st(taille, couleur: plein ? s.surPrincipale : s.principale, gras: true);
    return pw.TableRow(
      repeat: true,
      decoration: plein
          ? pw.BoxDecoration(color: s.principale)
          : pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: s.texte, width: 0.8),
                bottom: pw.BorderSide(color: s.texte, width: 0.8),
              ),
            ),
      children: [
        for (var i = 0; i < titres.length; i++)
          cellule(
            titres[i],
            style: styleTitre,
            alignement: aGauche.contains(i) ? pw.Alignment.centerLeft : pw.Alignment.center,
            alignementTexte: aGauche.contains(i) ? pw.TextAlign.left : pw.TextAlign.center,
            rembourrage: rembourrage,
          ),
      ],
    );
  }

  /// Bordure légère d'un tableau de données.
  pw.TableBorder get bordureTableau {
    final fin = pw.BorderSide(color: style.bordure, width: 0.4);
    final trait = pw.BorderSide(color: style.principale, width: 0.8);
    return pw.TableBorder(
      top: trait,
      bottom: trait,
      left: fin,
      right: fin,
      horizontalInside: fin,
      verticalInside: fin,
    );
  }

  /// Pied de page commun : texte à gauche, texte à droite.
  pw.Widget pied(String gauche, String droite) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: style.bordure, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(gauche, style: st(7.5, couleur: style.discret)),
          pw.Text(droite, style: st(7.5, couleur: style.discret)),
        ],
      ),
    );
  }
}
