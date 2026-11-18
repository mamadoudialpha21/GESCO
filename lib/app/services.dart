import '../data/controle.dart';
import '../data/depots/annee_depot.dart';
import '../data/depots/calendrier_depot.dart';
import '../data/depots/classe_depot.dart';
import '../data/depots/config_resultats_depot.dart';
import '../data/depots/eleve_depot.dart';
import '../data/depots/etablissement_depot.dart';
import '../data/depots/journal_depot.dart';
import '../data/depots/matiere_depot.dart';
import '../data/depots/note_depot.dart';
import '../data/depots/parametre_depot.dart';
import '../data/depots/utilisateur_depot.dart';
import '../data/gesco_database.dart';
import '../data/securite.dart';
import 'session.dart';

/// Regroupe l'accès à la base et tous les dépôts de données.
///
/// Sans [session], aucun contrôle d'accès n'est appliqué (tests, outils) ;
/// l'application réelle fournit une [Session] et demande donc une connexion.
class Services {
  factory Services(
    GescoDatabase gdb, {
    Session? session,
    int iterations = Hachage.iterationsParDefaut,
  }) {
    final s = session ?? Session.sansControle();
    final journal = JournalDepot(gdb.db);
    final controle = Controle(autorisations: s, journal: journal);
    return Services._(gdb, s, journal, controle, iterations);
  }

  Services._(
    this.gdb,
    this.session,
    this.journal,
    this.controle,
    int iterations,
  )   : etablissements = EtablissementDepot(gdb.db, controle: controle),
        annees = AnneeDepot(gdb.db, controle: controle),
        configs = ConfigResultatsDepot(gdb.db, controle: controle),
        calendriers = CalendrierDepot(gdb.db, controle: controle),
        classes = ClasseDepot(gdb.db, controle: controle),
        matieres = MatiereDepot(gdb.db, controle: controle),
        eleves = EleveDepot(gdb.db, controle: controle),
        notes = NoteDepot(gdb.db, controle: controle),
        parametres = ParametreDepot(gdb.db),
        utilisateurs = UtilisateurDepot(
          gdb.db,
          iterations: iterations,
          controle: controle,
        );

  final GescoDatabase gdb;
  final Session session;
  final JournalDepot journal;
  final Controle controle;
  final EtablissementDepot etablissements;
  final AnneeDepot annees;
  final ConfigResultatsDepot configs;
  final CalendrierDepot calendriers;
  final ClasseDepot classes;
  final MatiereDepot matieres;
  final EleveDepot eleves;
  final NoteDepot notes;
  final ParametreDepot parametres;
  final UtilisateurDepot utilisateurs;
}
