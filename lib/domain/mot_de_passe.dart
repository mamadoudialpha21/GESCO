/// Règles sur les identifiants et les mots de passe.
library;

const int longueurMiniMotDePasse = 6;

const Set<String> _tropFaciles = {
  '123456',
  '1234567',
  '12345678',
  '000000',
  '111111',
  'azerty',
  'azerty123',
  'qwerty',
  'password',
  'motdepasse',
  'admin123',
  'gesco',
  'gesco123',
};

/// Message d'erreur si [identifiant] n'est pas acceptable, sinon null.
String? validerIdentifiant(String identifiant) {
  final i = identifiant.trim();
  if (i.length < 3) {
    return 'L\'identifiant doit avoir au moins 3 caractères.';
  }
  if (i.length > 30) {
    return 'L\'identifiant est trop long (30 caractères au maximum).';
  }
  if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(i)) {
    return 'L\'identifiant ne peut contenir que des lettres sans accent, '
        'des chiffres, le point, le tiret et le tiret bas.';
  }
  return null;
}

/// Message d'erreur si [motDePasse] est trop faible, sinon null.
String? validerMotDePasse(String motDePasse, {String? identifiant}) {
  if (motDePasse.length < longueurMiniMotDePasse) {
    return 'Le mot de passe doit avoir au moins $longueurMiniMotDePasse caractères.';
  }
  if (motDePasse.length > 128) {
    return 'Le mot de passe est trop long (128 caractères au maximum).';
  }
  if (motDePasse.trim().isEmpty) {
    return 'Le mot de passe ne peut pas être fait uniquement d\'espaces.';
  }
  if (_tropFaciles.contains(motDePasse.toLowerCase())) {
    return 'Ce mot de passe est trop courant : choisissez-en un moins facile à deviner.';
  }
  if (identifiant != null &&
      motDePasse.toLowerCase() == identifiant.trim().toLowerCase()) {
    return 'Le mot de passe ne doit pas être identique à l\'identifiant.';
  }
  if (motDePasse.split('').toSet().length == 1) {
    return 'Le mot de passe ne peut pas répéter toujours le même caractère.';
  }
  return null;
}
