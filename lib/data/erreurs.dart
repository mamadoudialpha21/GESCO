/// Erreur « métier » : son message, en français, peut être affiché tel quel
/// à l'utilisateur (règle non respectée, doublon, suppression refusée...).
class ErreurGesco implements Exception {
  const ErreurGesco(this.message);

  final String message;

  @override
  String toString() => message;
}
