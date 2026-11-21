import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/bareme.dart';
import '../../domain/permissions.dart';
import '../controle.dart';
import '../erreurs.dart';

/// Clés des paramètres du logiciel.
class CleParametre {
  const CleParametre._();

  static const delaiInactiviteMinutes = 'session.delai_inactivite_minutes';
  static const recuperationHash = 'securite.recuperation_hash';
  static const recuperationSel = 'securite.recuperation_sel';
  static const recuperationIterations = 'securite.recuperation_iterations';
  static const recuperationEchecs = 'securite.recuperation_echecs';
  static const recuperationVerrouJusqua = 'securite.recuperation_verrou_jusqua';
  static const theme = 'interface.theme';
  static const lignesParPage = 'interface.lignes_par_page';
  static const baremeDefaut = 'notation.bareme_defaut';
  static const styleDocuments = 'documents.style';
}

/// Paramètres du logiciel enregistrés sous forme clé / valeur.
class ParametreDepot {
  ParametreDepot(this._db, {this.controle = Controle.aucun});

  final Database _db;
  final Controle controle;

  /// Barème proposé pour les nouvelles matières et évaluations (20 par
  /// défaut). Les matières et évaluations existantes gardent le leur.
  Future<int> baremeDefaut() async {
    final v = await lireEntier(CleParametre.baremeDefaut, baremeParDefaut);
    return baremeValide(v) ? v : baremeParDefaut;
  }

  Future<void> definirBaremeDefaut(int bareme) async {
    controle.exiger(Permission.parametresGerer, 'modifier le barème par défaut');
    if (!baremeValide(bareme)) {
      throw const ErreurGesco('Le barème doit être compris entre 1 et 1000.');
    }
    await ecrire(CleParametre.baremeDefaut, '$bareme');
    await controle.noter('modification', 'parametre', details: 'barème par défaut : $bareme');
  }

  /// Identifiant du style des documents PDF choisi en dernier (null si aucun).
  Future<String?> styleDocuments() => lire(CleParametre.styleDocuments);

  Future<void> definirStyleDocuments(String id) => ecrire(CleParametre.styleDocuments, id);

  Future<String?> lire(String cle) async {
    final l = await _db.query('parametre', where: 'cle = ?', whereArgs: [cle]);
    return l.isEmpty ? null : l.first['valeur'] as String;
  }

  Future<void> ecrire(String cle, String valeur) async {
    await _db.insert(
      'parametre',
      {'cle': cle, 'valeur': valeur},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> supprimer(String cle) async {
    await _db.delete('parametre', where: 'cle = ?', whereArgs: [cle]);
  }

  Future<int> lireEntier(String cle, int defaut) async =>
      int.tryParse(await lire(cle) ?? '') ?? defaut;

  Future<bool> lireBool(String cle, bool defaut) async {
    final v = await lire(cle);
    if (v == null) return defaut;
    return v == '1' || v == 'true';
  }

  Future<void> ecrireBool(String cle, bool valeur) =>
      ecrire(cle, valeur ? '1' : '0');

  /// Tous les paramètres (pour les sauvegardes et le diagnostic).
  Future<Map<String, String>> tous() async {
    final l = await _db.query('parametre', orderBy: 'cle');
    return {for (final r in l) r['cle'] as String: r['valeur'] as String};
  }
}
