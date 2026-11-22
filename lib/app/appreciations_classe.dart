/// Appréciations automatiques d'une classe entière, d'après ses résultats.
library;

import '../domain/appreciations_auto.dart';
import '../domain/calendrier.dart';
import 'calcul_classe.dart';

/// Appréciations générées pour une classe et une étendue.
class AppreciationsGenerees {
  const AppreciationsGenerees({this.generales = const {}, this.matieres = const {}});

  /// Appréciation générale par inscription (absente si pas de moyenne).
  final Map<int, String> generales;

  /// Appréciation de chaque matière : inscription -> matière -> texte.
  final Map<int, Map<int, String>> matieres;
}

/// Étendue précédant [portee] dans l'année, pour mesurer l'évolution :
/// le mois d'avant, la période d'avant (trimestre, semestre ou séquence).
/// Null pour le premier mois, la première période et le bilan annuel.
Portee? porteePrecedente(Calendrier calendrier, Portee portee) {
  if (portee.estMois) {
    final i = moisScolaires.indexOf(portee.moisChoisi!);
    return i > 0 ? Portee.mois(moisScolaires[i - 1]) : null;
  }
  final p = portee.periodeChoisie;
  if (p == null) return null;
  for (final liste in [calendrier.periodes, calendrier.sequences]) {
    final i = liste.indexWhere((x) => x.cle == p.cle);
    if (i >= 0) return i > 0 ? Portee.periode(liste[i - 1]) : null;
  }
  return null;
}

/// Matières fortes et faibles retenues dans l'appréciation générale.
const int _maxMatieresCitees = 2;

/// Rédige l'appréciation générale et celle de chaque matière de tous les
/// élèves actifs de la classe qui ont une moyenne (ou une note).
AppreciationsGenerees genererAppreciations(CalculClasse calcul, Portee portee) {
  final config = calcul.config;
  final resultats = {for (final r in calcul.resultats(portee)) r.inscriptionId: r};
  final precedente = porteePrecedente(calcul.calendrier, portee);
  final resultatsPrecedents = precedente == null
      ? const <int, int?>{}
      : {for (final r in calcul.resultats(precedente)) r.inscriptionId: r.moyenne};

  // Rang partagé : plusieurs élèves à la même place.
  final classes = [
    for (final e in calcul.eleves)
      if (e.actif && resultats[e.inscriptionId]?.rang != null) resultats[e.inscriptionId]!,
  ];
  final partages = <int, int>{};
  for (final r in classes) {
    partages[r.rang!] = (partages[r.rang!] ?? 0) + 1;
  }

  // Note de chaque élève dans chaque matière (facultatives exclues des
  // « points forts » et « à renforcer », qui n'entrent pas dans la moyenne).
  final notes = <int, Map<int, int>>{};
  for (final m in calcul.matieres) {
    for (final r in calcul.moteur.classementMatiere(m.id, portee)) {
      if (r.note != null) (notes[r.inscriptionId] ??= {})[m.id] = r.note!;
    }
  }
  final nomsMatieres = {for (final m in calcul.matieres) m.id: m.nom};
  final comptees = {
    for (final m in calcul.matieres)
      if (!m.facultative) m.id,
  };

  final generales = <int, String>{};
  final parMatiere = <int, Map<int, String>>{};
  for (final e in calcul.eleves) {
    if (!e.actif) continue;
    final r = resultats[e.inscriptionId];
    final rangEleve = r?.rang;
    final notesEleve = notes[e.inscriptionId] ?? const {};

    // Points forts : au moins « bon » ; à renforcer : sous le seuil d'admission.
    final classees = [
      for (final entree in notesEleve.entries)
        if (comptees.contains(entree.key)) entree,
    ]..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
    final fortes = [
      for (final n in classees)
        if (n.value >= 1400) nomsMatieres[n.key]!,
    ].take(_maxMatieresCitees).toList();
    final faibles = [
      for (final n in classees.reversed)
        if (n.value < config.seuilAdmission) nomsMatieres[n.key]!,
    ].take(_maxMatieresCitees).toList();

    final texte = appreciationGenerale(
      EntreeAppreciation(
        moyenne: r?.moyenne,
        rang: rangEleve,
        exAequo: rangEleve != null && (partages[rangEleve] ?? 0) > 1,
        effectif: classes.length,
        moyennePrecedente: resultatsPrecedents[e.inscriptionId],
        sexe: e.sexe,
        matieresFortes: fortes,
        matieresFaibles: faibles,
        seuilAdmission: config.seuilAdmission,
        seuilBon: config.seuilBon,
      ),
    );
    if (texte.isNotEmpty) generales[e.inscriptionId] = texte;

    final avisMatieres = <int, String>{};
    for (final entree in notesEleve.entries) {
      final avis = appreciationMatiere(
        entree.value,
        seuilAdmission: config.seuilAdmission,
        seuilBon: config.seuilBon,
      );
      if (avis.isNotEmpty) avisMatieres[entree.key] = avis;
    }
    if (avisMatieres.isNotEmpty) parMatiere[e.inscriptionId] = avisMatieres;
  }
  return AppreciationsGenerees(generales: generales, matieres: parMatiere);
}
