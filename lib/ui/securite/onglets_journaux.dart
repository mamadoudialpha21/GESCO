import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/modeles_securite.dart';
import '../theme.dart';
import 'libelles.dart';
import 'liste_paginee.dart';

/// Qui a fait quoi : créations, modifications et suppressions.
class OngletJournal extends StatelessWidget {
  const OngletJournal({super.key, required this.etat});

  final EtatApp etat;

  @override
  Widget build(BuildContext context) {
    return ListePaginee<EntreeJournal>(
      titre: 'Journal des opérations',
      sousTitre: 'Chaque modification importante est enregistrée avec son auteur, '
          'la date et l\'heure. Le journal ne peut pas être modifié.',
      rechargerSur: etat.version,
      vide: 'Aucune opération enregistrée pour le moment.',
      charger: (limite, decalage, recherche) async {
        final j = etat.services.journal;
        final lignes = await j.lister(
          limite: limite,
          decalage: decalage,
          recherche: recherche,
        );
        final total = await j.compter(recherche: recherche);
        return (lignes: lignes, total: total);
      },
      ligne: (context, e) => ListTile(
        dense: true,
        leading: const Icon(Icons.edit_note, color: CouleursGesco.bleu),
        title: Text(
          '${libelleAction(e.action)} · ${libelleEntite(e.entite)}'
          '${e.details.isEmpty ? '' : ' — ${e.details}'}',
        ),
        subtitle: Text(
          '${dateHeureFr(e.dateHeure)} · '
          '${e.utilisateurNom.isEmpty ? 'Utilisateur inconnu' : e.utilisateurNom}',
        ),
      ),
    );
  }
}

/// Connexions, déconnexions, échecs et verrouillages de comptes.
class OngletConnexions extends StatelessWidget {
  const OngletConnexions({super.key, required this.etat});

  final EtatApp etat;

  @override
  Widget build(BuildContext context) {
    return ListePaginee<EntreeConnexion>(
      titre: 'Journal des connexions',
      sousTitre: 'Les échecs de connexion et les verrouillages sont signalés en rouge.',
      rechargerSur: etat.version,
      vide: 'Aucune connexion enregistrée.',
      charger: (limite, decalage, recherche) async {
        final j = etat.services.journal;
        final lignes = await j.listerConnexions(
          limite: limite,
          decalage: decalage,
          recherche: recherche,
        );
        final total = await j.compterConnexions(recherche: recherche);
        return (lignes: lignes, total: total);
      },
      ligne: (context, e) {
        final suspect = evenementSuspect(e.evenement);
        return ListTile(
          dense: true,
          leading: Icon(
            suspect ? Icons.warning_amber_rounded : Icons.login,
            color: suspect ? CouleursGesco.rouge : CouleursGesco.bleu,
          ),
          title: Text(
            '${libelleEvenement(e.evenement)}'
            '${e.identifiant.isEmpty ? '' : ' · ${e.identifiant}'}',
            style: TextStyle(color: suspect ? CouleursGesco.rouge : null),
          ),
          subtitle: Text(
            '${dateHeureFr(e.dateHeure)}${e.detail.isEmpty ? '' : ' · ${e.detail}'}',
          ),
        );
      },
    );
  }
}

/// Anciennes et nouvelles valeurs de chaque note modifiée.
class OngletHistoriqueNotes extends StatelessWidget {
  const OngletHistoriqueNotes({super.key, required this.etat});

  final EtatApp etat;

  @override
  Widget build(BuildContext context) {
    return ListePaginee<EntreeHistoriqueNote>(
      titre: 'Historique des notes',
      sousTitre: 'Toute création, modification ou suppression de note est '
          'conservée avec l\'ancienne valeur et son auteur.',
      rechargerSur: etat.version,
      vide: 'Aucune note n\'a encore été saisie.',
      charger: (limite, decalage, recherche) async {
        final j = etat.services.journal;
        final lignes = await j.historiqueNotes(
          limite: limite,
          decalage: decalage,
          recherche: recherche,
        );
        final total = await j.compterHistoriqueNotes(recherche: recherche);
        return (lignes: lignes, total: total);
      },
      ligne: (context, e) {
        final periode = e.source == 'evaluation'
            ? 'évaluation'
            : nomMois(e.mois);
        return ListTile(
          dense: true,
          leading: Icon(
            switch (e.operation) {
              'creation' => Icons.add_circle_outline,
              'suppression' => Icons.remove_circle_outline,
              _ => Icons.edit_outlined,
            },
            color: e.operation == 'suppression'
                ? CouleursGesco.rouge
                : CouleursGesco.bleu,
          ),
          title: Text(
            '${e.eleveNom} · ${e.matiereNom} · ${changementNote(e)}',
          ),
          subtitle: Text(
            '${dateHeureFr(e.dateHeure)} · '
            '${e.utilisateurNom.isEmpty ? 'Utilisateur inconnu' : e.utilisateurNom}'
            '${e.classeNom.isEmpty ? '' : ' · ${e.classeNom}'}'
            '${periode.isEmpty ? '' : ' · $periode'}',
          ),
        );
      },
    );
  }
}
