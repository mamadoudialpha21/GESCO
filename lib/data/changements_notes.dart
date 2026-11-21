import 'dart:async';

/// Signal émis quand des notes d'une classe ont changé pour un mois.
class ChangementNotes {
  const ChangementNotes(this.classeId, this.mois, {this.composition = false});

  final int classeId;

  /// Mois scolaire concerné (1 à 12).
  final int mois;

  /// Vrai si le changement vient d'une composition ou d'un examen : la fin
  /// d'un trimestre.
  final bool composition;

  @override
  String toString() =>
      'ChangementNotes(classe $classeId, mois $mois${composition ? ', composition' : ''})';
}

/// Diffuse les changements de notes aux parties de l'application qui
/// réagissent à une saisie (génération automatique des bulletins...).
///
/// Les dépôts de données signalent un changement une fois l'écriture
/// réussie ; aucun écouteur n'est requis.
class NotificationsNotes {
  final StreamController<ChangementNotes> _flux = StreamController.broadcast();

  Stream<ChangementNotes> get flux => _flux.stream;

  void signaler(ChangementNotes changement) {
    if (!_flux.isClosed) _flux.add(changement);
  }

  Future<void> fermer() => _flux.close();
}
