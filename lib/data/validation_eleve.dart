import '../domain/dates.dart';
import 'erreurs.dart';
import 'images.dart';
import 'modeles_donnees.dart';

/// Longueurs maximales des champs d'une fiche élève.
const int longueurMaxNom = 60;
const int longueurMaxMatricule = 40;
const int longueurMaxTexte = 120;

/// Liste des erreurs d'une fiche élève (vide si elle est valide).
/// [maintenant] sert à refuser une date de naissance dans le futur.
List<String> erreursEleve(Eleve eleve, {required DateTime maintenant}) {
  final erreurs = <String>[];

  void obligatoire(String valeur, String nom, int max) {
    final v = valeur.trim();
    if (v.isEmpty) {
      erreurs.add('$nom est obligatoire.');
    } else if (v.length > max) {
      erreurs.add('$nom est trop long ($max caractères maximum).');
    }
  }

  void facultatif(String valeur, String nom) {
    if (valeur.trim().length > longueurMaxTexte) {
      erreurs.add('$nom est trop long ($longueurMaxTexte caractères maximum).');
    }
  }

  obligatoire(eleve.nom, 'Le nom', longueurMaxNom);
  obligatoire(eleve.prenom, 'Le prénom', longueurMaxNom);
  obligatoire(eleve.matricule, 'Le matricule', longueurMaxMatricule);

  if (eleve.sexe != 'M' && eleve.sexe != 'F') {
    erreurs.add('Le sexe doit être renseigné (masculin ou féminin).');
  }

  final naissance = eleve.dateNaissance;
  if (naissance != null) {
    final date = analyserDateIso(naissance);
    if (date == null) {
      erreurs.add('La date de naissance est invalide.');
    } else if (date.isAfter(maintenant)) {
      erreurs.add('La date de naissance ne peut pas être dans le futur.');
    }
  }

  facultatif(eleve.lieuNaissance, 'Le lieu de naissance');
  facultatif(eleve.nomPere, 'Le nom du père');
  facultatif(eleve.nomMere, 'Le nom de la mère');
  facultatif(eleve.contactParent, 'Le contact du parent ou tuteur');
  facultatif(eleve.adresse, 'L\'adresse');

  final photo = eleve.photo;
  if (photo != null) {
    try {
      verifierImage(photo, tailleMax: tailleMaxPhoto, nom: 'La photo');
    } on ErreurGesco catch (e) {
      erreurs.add(e.message);
    }
  }

  return erreurs;
}
