import '../data/depots/annee_depot.dart';
import '../data/depots/classe_depot.dart';
import '../data/depots/config_resultats_depot.dart';
import '../data/depots/eleve_depot.dart';
import '../data/depots/etablissement_depot.dart';
import '../data/depots/matiere_depot.dart';
import '../data/depots/note_depot.dart';
import '../data/gesco_database.dart';

/// Regroupe l'accès à la base et tous les dépôts de données.
class Services {
  Services(this.gdb)
      : etablissements = EtablissementDepot(gdb.db),
        annees = AnneeDepot(gdb.db),
        configs = ConfigResultatsDepot(gdb.db),
        classes = ClasseDepot(gdb.db),
        matieres = MatiereDepot(gdb.db),
        eleves = EleveDepot(gdb.db),
        notes = NoteDepot(gdb.db);

  final GescoDatabase gdb;
  final EtablissementDepot etablissements;
  final AnneeDepot annees;
  final ConfigResultatsDepot configs;
  final ClasseDepot classes;
  final MatiereDepot matieres;
  final EleveDepot eleves;
  final NoteDepot notes;
}
