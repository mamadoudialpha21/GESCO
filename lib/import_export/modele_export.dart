/// Données communes aux fichiers Excel produits par GESCO.
library;

import '../data/modeles_donnees.dart';

/// Établissement, année et date d'édition inscrits en tête de chaque fichier.
class ContexteExport {
  const ContexteExport({
    required this.etablissement,
    required this.annee,
    required this.date,
  });

  final String etablissement;
  final String annee;
  final DateTime date;
}

/// Un élève inscrit avec sa fiche complète, pour la liste des élèves.
class EleveExport {
  const EleveExport({required this.eleve, required this.inscription});

  final Eleve eleve;
  final EleveInscrit inscription;
}

/// Date au format « JJ/MM/AAAA ».
String dateFr(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
