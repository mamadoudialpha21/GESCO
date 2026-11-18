/// Erreur « métier » : son message, en français, peut être affiché tel quel
/// à l'utilisateur (règle non respectée, doublon, suppression refusée...).
class ErreurGesco implements Exception {
  const ErreurGesco(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Opération refusée tant que l'utilisateur n'a pas confirmé une conséquence
/// (classe pleine, notes perdues lors d'un transfert...). Les écrans affichent
/// [message], puis relancent l'opération avec la confirmation.
class ErreurAConfirmer extends ErreurGesco {
  const ErreurAConfirmer(super.message, this.sujet);

  /// 'capacite' ou 'pertes'.
  final String sujet;
}
