// Produit des PDF d'exemple (bulletins) dans `captures/`.
//
// Sert à relire la mise en page sans lancer l'application : la CI convertit
// ces PDF en images et les publie sur la branche « captures ».
//
// Lancer :  flutter test tool/exemples_pdf_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesco/documents/modele_bulletin.dart';
import 'package:gesco/documents/pdf_bulletin.dart';
import 'package:gesco/documents/styles_bulletin.dart';

import '../test/documents/exemples.dart';

void main() {
  test('PDF d\'exemple', () async {
    final dossier = Directory('captures')..createSync(recursive: true);
    final p = polices();

    Future<void> ecrire(String nom, List<Bulletin> bulletins, StyleBulletin style) async {
      final pdf = await genererBulletinsPdf(bulletins, style: style, polices: p);
      File('${dossier.path}/$nom.pdf').writeAsBytesSync(pdf.octets);
      // ignore: avoid_print
      print('PDF $nom : ${pdf.pages} page(s), ${pdf.octets.length} octets');
    }

    for (final style in StyleBulletin.tous) {
      await ecrire('bulletin_${style.id}', [bulletinExemple()], style);
    }
    const classique = StyleBulletin.classiqueBleu;
    await ecrire('bulletin_20_matieres',
        [bulletinExemple(nbMatieres: 20, avecAppreciationsMatieres: false)], classique);
    await ecrire('bulletin_30_matieres', [bulletinExemple(nbMatieres: 30)], classique);
    await ecrire(
        'bulletin_annuel',
        [bulletinExemple(type: TypeBulletin.annuel, periodeLibelle: 'Année scolaire')],
        StyleBulletin.bleuEtOr);
    await ecrire(
        'bulletin_mensuel',
        [bulletinExemple(type: TypeBulletin.mensuel, periodeLibelle: 'Novembre', nbMatieres: 8)],
        StyleBulletin.vertSauge);
    await ecrire(
        'bulletin_sans_notes',
        [bulletinExemple(avecMoyenne: false, avecImages: false, avecAppreciationsMatieres: false)],
        StyleBulletin.minimalisteNoirBlanc);
    await ecrire(
        'classe_complete',
        [
          for (var i = 0; i < 5; i++)
            bulletinExemple(nom: 'ELEVE$i', prenom: 'Prénom$i', matricule: '2026-001$i'),
        ],
        StyleBulletin.couleursGuineennes);
  });
}
