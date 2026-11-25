import '../sauvegarde/service_sauvegarde.dart';

/// Ce que l'application sait faire de la base ouverte et qui la remplace :
/// restaurer une sauvegarde, puis repartir sur la base rouverte.
///
/// Les écrans n'ont besoin que de cette interface ; `GestionBaseApp` en est la
/// réalisation (elle ferme, remplace et rouvre le fichier de la base).
abstract class GestionBase {
  /// Restaure la sauvegarde [chemin] : sauvegarde de sécurité, remplacement de
  /// la base, réouverture et contrôle (voir `ServiceSauvegarde.restaurer`).
  ///
  /// Une `ErreurGesco` est levée, sans que rien ne soit modifié, si le fichier
  /// est refusé. Après tout autre résultat (réussite ou retour arrière), la base
  /// a été rouverte : l'appelant doit alors appeler [redemarrer].
  Future<ResultatRestauration> restaurer(
    String chemin, {
    void Function(EtapeRestauration etape)? progression,
  });

  /// Reconstruit toute l'application sur la base rouverte : nouvelle session
  /// (les comptes sont ceux de la base restaurée), écrans rechargés.
  Future<void> redemarrer();
}
