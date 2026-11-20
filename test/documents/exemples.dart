/// Données d'exemple partagées par les tests des documents PDF et par l'outil
/// qui produit les PDF d'exemple.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:gesco/documents/elements_pdf.dart';
import 'package:gesco/documents/modele_bulletin.dart';
import 'package:gesco/documents/modele_classement.dart';
import 'package:gesco/documents/polices_pdf.dart';
import 'package:gesco/domain/statistiques.dart';

/// Les polices lues dans le dépôt (le test s'exécute depuis la racine).
PolicesPdf polices() {
  Uint8List lire(String nom) => File('assets/fonts/$nom').readAsBytesSync();
  return PolicesPdf.depuisOctets(
    sans: lire('DejaVuSans.ttf'),
    sansGras: lire('DejaVuSans-Bold.ttf'),
    sansItalique: lire('DejaVuSans-Oblique.ttf'),
    serif: lire('DejaVuSerif.ttf'),
    serifGras: lire('DejaVuSerif-Bold.ttf'),
    serifItalique: lire('DejaVuSerif-Italic.ttf'),
  );
}

Uint8List image(String nom) => File('test/assets/$nom').readAsBytesSync();

const nomsMatieres = <String>[
  'Mathématiques',
  'Physique-Chimie',
  'Sciences de la vie et de la Terre',
  'Français',
  'Anglais',
  'Histoire-Géographie',
  'Éducation civique et morale',
  'Éducation physique et sportive',
  'Informatique',
  'Dessin',
  'Musique',
  'Philosophie',
  'Espagnol',
  'Arabe',
  'Économie familiale',
  'Travaux manuels',
  'Lecture',
  'Dictée',
  'Rédaction',
  'Grammaire',
  'Conjugaison',
  'Vocabulaire',
  'Calcul mental',
  'Géométrie',
  'Éveil scientifique',
  'Éducation religieuse',
  'Poésie',
  'Récitation',
  'Écriture',
  'Chant',
];

const appreciationsMatieres = <String>[
  'Très bon travail, continuez ainsi.',
  'Des efforts à poursuivre.',
  'Participation active en classe.',
  'Peut mieux faire : revoir les leçons.',
  'Résultats satisfaisants.',
  'Élève sérieux et appliqué.',
];

/// Bulletin d'exemple vraisemblable. Les notes sont déterministes.
Bulletin bulletinExemple({
  int nbMatieres = 12,
  TypeBulletin type = TypeBulletin.periodique,
  String periodeLibelle = 'Trimestre 1',
  bool avecImages = true,
  bool avecAppreciationsMatieres = true,
  bool avecAppreciationGenerale = true,
  bool avecMoyenne = true,
  bool incomplet = false,
  String nom = 'DIALLO',
  String prenom = 'Aminata',
  String sexe = 'F',
  String matricule = '2026-0012',
}) {
  final lignes = [
    for (var i = 0; i < nbMatieres; i++)
      LigneBulletin(
        matiere: nomsMatieres[i % nomsMatieres.length],
        coefficient: const [100, 200, 300, 400, 150][i % 5],
        note: avecMoyenne ? 700 + (i * 437) % 1200 : null,
        rang: avecMoyenne ? 1 + (i * 7) % 28 : null,
        moyenneClasse: 1050 + (i * 131) % 400,
        minClasse: 300 + (i * 53) % 300,
        maxClasse: 1600 + (i * 71) % 400,
        appreciation:
            avecAppreciationsMatieres ? appreciationsMatieres[i % appreciationsMatieres.length] : '',
        facultative: i == nbMatieres - 1 && nbMatieres > 6,
      ),
  ];
  return Bulletin(
    type: type,
    periodeLibelle: periodeLibelle,
    anneeLibelle: '2026-2027',
    etablissementNom: 'Groupe Scolaire Nialy International',
    adresse: 'Tombolia, Commune de Matoto, Conakry',
    telephone: '+224 622 00 00 00',
    email: 'contact@nialy.example',
    devise: 'Travail - Justice - Solidarité',
    infosAdmin: 'Agrément n° 0123/MEPU-A/2020\nBP 1234 Conakry',
    directeur: 'M. Mamadou Camara',
    logo: avecImages ? image('logo_exemple.png') : null,
    signature: avecImages ? image('signature_exemple.png') : null,
    cachet: avecImages ? image('cachet_exemple.png') : null,
    classeNom: '10e A',
    niveau: '10e année',
    eleveNom: nom,
    elevePrenom: prenom,
    matricule: matricule,
    sexe: sexe,
    dateNaissance: '2011-03-05',
    lieuNaissance: 'Conakry',
    photo: avecImages ? image('photo_exemple.png') : null,
    lignes: lignes,
    moyenne: avecMoyenne ? 1342 : null,
    rang: avecMoyenne ? 3 : null,
    exAequo: avecMoyenne,
    effectif: 42,
    moyenneClasse: 1105,
    meilleureMoyenne: 1688,
    plusFaibleMoyenne: 547,
    mention: avecMoyenne ? 'Assez bien' : '',
    decision: avecMoyenne ? 'Admis(e)' : '',
    incomplet: incomplet,
    appreciation: avecAppreciationGenerale
        ? 'Élève sérieuse, dont les résultats sont encourageants. '
            'Elle doit poursuivre ses efforts en mathématiques et en sciences.'
        : '',
    decisionConseil: avecAppreciationGenerale ? 'Félicitations du conseil de classe' : '',
    periodes: type == TypeBulletin.annuel
        ? const [
            ResumePeriode(libelle: 'Trimestre 1', moyenne: 1342, rang: 3),
            ResumePeriode(libelle: 'Trimestre 2', moyenne: 1415, rang: 2),
            ResumePeriode(libelle: 'Trimestre 3', moyenne: null, rang: null),
          ]
        : const [],
    dateEdition: DateTime(2026, 11, 20),
  );
}

const _prenoms = ['Aminata', 'Mamadou', 'Fatoumata', 'Ibrahima', 'Mariama', 'Alpha', 'Kadiatou', 'Sékou'];
const _noms = ['DIALLO', 'BARRY', 'CAMARA', 'SOW', 'BAH', 'TOURÉ', 'KEÏTA', 'SYLLA', 'CONDÉ', 'BANGOURA'];

/// Classement d'exemple de [nbEleves] élèves ; les élèves classés d'abord (avec
/// quelques ex æquo), puis un élève parti et un élève sans note.
DocumentClassement classementExemple({
  int nbEleves = 25,
  bool annuel = false,
  bool avecStats = true,
  bool parMatiere = false,
  bool avecImages = true,
}) {
  final lignes = <LigneDocClassement>[];
  for (var i = 0; i < nbEleves; i++) {
    final moyenne = 1800 - (i * 41) % 1500;
    final rang = i < 2 ? 1 : i;
    lignes.add(LigneDocClassement(
      nom: '${_noms[i % _noms.length]} ${_prenoms[i % _prenoms.length]}',
      matricule: '2026-${(i + 1).toString().padLeft(4, '0')}',
      rang: rang,
      exAequo: i < 2,
      moyenne: moyenne,
      mention: moyenne >= 1600 ? 'Très bien' : moyenne >= 1400 ? 'Bien' : moyenne >= 1200 ? 'Assez bien' : moyenne >= 1000 ? 'Passable' : '',
      decision: parMatiere ? '' : (moyenne >= 1000 ? 'Admis(e)' : 'Redouble'),
      incomplet: i == 3,
      moyennesPeriodes: annuel ? [moyenne + 30, moyenne - 25, null] : const [],
    ));
  }
  lignes.add(const LigneDocClassement(
    nom: 'SYLLA Moussa',
    matricule: '2026-0098',
    moyenne: 1500,
    observation: 'Parti',
  ));
  lignes.add(const LigneDocClassement(
    nom: 'CONDÉ Aïcha',
    matricule: '2026-0099',
    observation: 'Sans note',
  ));
  return DocumentClassement(
    entete: enteteExemple(avecImages: avecImages),
    titre: annuel ? 'RÉSULTATS ANNUELS' : (parMatiere ? 'CLASSEMENT EN MATHÉMATIQUES' : 'CLASSEMENT GÉNÉRAL'),
    sousTitre: annuel ? 'Année entière' : 'Trimestre 1',
    classeNom: '10e A',
    anneeLibelle: '2026-2027',
    libelleMoyenne: parMatiere ? 'Note /20' : 'Moyenne',
    periodes: annuel ? const ['Trimestre 1', 'Trimestre 2', 'Trimestre 3'] : const [],
    avecDecision: !parMatiere,
    lignes: lignes,
    stats: avecStats
        ? StatsClasse(
            effectif: nbEleves + 2,
            filles: 14,
            garcons: nbEleves - 12,
            evalues: nbEleves,
            admis: nbEleves - 4,
            nonAdmis: 4,
            moyenneClasse: 1350,
            meilleureMoyenne: 1800,
            plusFaibleMoyenne: 800,
            tauxReussiteCentiemes: 8400,
            repartitionMentions: const {'Très bien': 3, 'Bien': 6, 'Assez bien': 7, 'Passable': 5, '': 4},
          )
        : null,
    directeur: 'M. Mamadou Camara',
    signature: avecImages ? image('signature_exemple.png') : null,
    cachet: avecImages ? image('cachet_exemple.png') : null,
    dateEdition: DateTime(2026, 11, 20),
  );
}

/// En-tête d'exemple de l'établissement.
EnteteEtablissement enteteExemple({bool avecImages = true}) => EnteteEtablissement(
      nom: 'Groupe Scolaire Nialy International',
      adresse: 'Tombolia, Commune de Matoto, Conakry',
      telephone: '+224 622 00 00 00',
      email: 'contact@nialy.example',
      devise: 'Travail - Justice - Solidarité',
      infosAdmin: 'Agrément n° 0123/MEPU-A/2020\nBP 1234 Conakry',
      logo: avecImages ? image('logo_exemple.png') : null,
    );
