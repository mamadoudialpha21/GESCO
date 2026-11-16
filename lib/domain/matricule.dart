/// Aide à la numérotation des matricules.
library;

/// Propose le prochain matricule : [prefixe]-NNNN, numéroté après le plus
/// grand numéro existant de ce préfixe (jamais un numéro déjà utilisé, même
/// si un élève a été supprimé entre-temps).
///
/// `proposerMatricule('2026', ['2026-0001', '2026-0007'])` -> « 2026-0008 ».
/// Sans préfixe : « 0001 », « 0002 »...
String proposerMatricule(String prefixe, Iterable<String> existants) {
  final p = prefixe.trim();
  final debut = p.isEmpty ? '' : '$p-';
  final motif = RegExp('^${RegExp.escape(debut)}(\\d+)\$', caseSensitive: false);
  var maximum = 0;
  for (final existant in existants) {
    final m = motif.firstMatch(existant.trim());
    if (m == null) continue;
    final numero = int.tryParse(m.group(1)!);
    if (numero != null && numero > maximum) maximum = numero;
  }
  return '$debut${(maximum + 1).toString().padLeft(4, '0')}';
}
