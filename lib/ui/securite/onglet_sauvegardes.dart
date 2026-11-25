import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/depots/aides.dart' show horodatage;
import '../../data/erreurs.dart';
import '../../domain/permissions.dart';
import '../../sauvegarde/service_sauvegarde.dart';
import '../commun/choix.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../theme.dart';
import 'dialogue_restauration.dart';
import 'libelles.dart';

/// Choisit un dossier (clé USB, disque externe) : boîte de dialogue du
/// système, remplaçable dans les tests.
typedef SelecteurDossier = Future<String?> Function();

/// Choisit un fichier de sauvegarde (.zip) : boîte de dialogue du système,
/// remplaçable dans les tests.
typedef SelecteurSauvegarde = Future<String?> Function();

Future<String?> choisirDossierSauvegarde() => FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choisir le dossier (clé USB, disque externe...)',
    );

Future<String?> choisirFichierSauvegarde() async {
  final resultat = await FilePicker.platform.pickFiles(
    dialogTitle: 'Choisir la sauvegarde GESCO',
    type: FileType.custom,
    allowedExtensions: const ['zip'],
  );
  if (resultat == null || resultat.files.isEmpty) return null;
  return resultat.files.single.path;
}

/// Taille d'un fichier en français : « 850 Ko », « 2,4 Mo ».
String tailleLisible(int octets) {
  if (octets < 1024) return '$octets o';
  if (octets < 1024 * 1024) return '${(octets / 1024).round()} Ko';
  final mo = octets / (1024 * 1024);
  return '${mo.toStringAsFixed(mo < 10 ? 1 : 0).replaceAll('.', ',')} Mo';
}

/// Date et heure d'une sauvegarde : « 25/11/2026 19:00 ».
String dateSauvegarde(DateTime d) => dateHeureFr(horodatage(d));

/// Sécurité > Sauvegardes : réglages de la sauvegarde automatique, sauvegarde
/// manuelle (dossier, clé USB), historique avec contrôle, et restauration.
class OngletSauvegardes extends StatefulWidget {
  const OngletSauvegardes({
    super.key,
    required this.etat,
    this.selecteurDossier = choisirDossierSauvegarde,
    this.selecteurFichier = choisirFichierSauvegarde,
    this.quitter = _quitterGesco,
  });

  final EtatApp etat;
  final SelecteurDossier selecteurDossier;
  final SelecteurSauvegarde selecteurFichier;

  /// Ferme GESCO (si la base n'a pas pu être rouverte après une restauration).
  final void Function() quitter;

  @override
  State<OngletSauvegardes> createState() => _OngletSauvegardesState();
}

void _quitterGesco() => exit(0);

class _OngletSauvegardesState extends State<OngletSauvegardes> {
  static const List<int> _nombres = [3, 5, 7, 10, 14, 20, 30];

  EtatApp get _etat => widget.etat;
  ServiceSauvegarde? get _service => _etat.sauvegarde;

  ConfigSauvegarde? _enregistree;
  ConfigSauvegarde? _edition;
  List<Sauvegarde> _historique = const [];
  String? _erreurChargement;
  bool _occupe = false;
  ResultatSauvegarde? _derniereCreee;

  @override
  void initState() {
    super.initState();
    _etat.planificateurSauvegarde?.addListener(_surPlanificateur);
    _charger();
  }

  @override
  void dispose() {
    _etat.planificateurSauvegarde?.removeListener(_surPlanificateur);
    super.dispose();
  }

  void _surPlanificateur() {
    if (mounted) _charger();
  }

  Future<void> _charger() async {
    final service = _service;
    if (service == null) return;
    try {
      final c = await service.config();
      final h = await service.historique();
      if (!mounted) return;
      setState(() {
        _enregistree = c;
        _edition ??= c;
        _historique = h;
        _erreurChargement = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreurChargement = e is ErreurGesco ? e.message : '$e');
    }
  }

  bool get _modifiee {
    final a = _enregistree;
    final b = _edition;
    if (a == null || b == null) return false;
    return a.auto != b.auto ||
        a.heure != b.heure ||
        a.minute != b.minute ||
        a.conserver != b.conserver ||
        a.dossierExterne != b.dossierExterne;
  }

  void _modifier(ConfigSauvegarde Function(ConfigSauvegarde c) f) {
    final c = _edition;
    if (c == null) return;
    setState(() => _edition = f(c));
  }

  Future<void> _enregistrer() async {
    final service = _service;
    final c = _edition;
    if (service == null || c == null) return;
    final ok = await executer(
      context,
      () => service.enregistrerConfig(c),
      succes: 'Réglages de sauvegarde enregistrés.',
    );
    if (ok) {
      await _charger();
      if (mounted) setState(() => _edition = _enregistree);
    }
  }

  Future<void> _choisirDossierExterne() async {
    final dossier = await widget.selecteurDossier();
    if (dossier == null || dossier.trim().isEmpty) return;
    _modifier((c) => c.copie(dossierExterne: dossier));
  }

  Future<void> _creer({String? dossier}) async {
    final service = _service;
    if (service == null || _occupe) return;
    setState(() {
      _occupe = true;
      _derniereCreee = null;
    });
    ResultatSauvegarde? resultat;
    await executer(context, () async {
      resultat = await service.creerManuelle(
        destination: dossier == null ? null : Directory(dossier),
      );
    });
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _derniereCreee = resultat;
    });
    await _charger();
  }

  Future<void> _creerSurDossier() async {
    final dossier = await widget.selecteurDossier();
    if (dossier == null || dossier.trim().isEmpty) return;
    await _creer(dossier: dossier);
  }

  Future<void> _verifier(Sauvegarde s) async {
    final service = _service;
    if (service == null) return;
    ResultatVerification? resultat;
    final ok = await executer(context, () async {
      resultat = await service.verifier(s);
    });
    if (!ok || resultat == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _DialogueVerification(s: s, resultat: resultat!),
    );
    await _charger();
  }

  Future<void> _supprimer(Sauvegarde s) async {
    final service = _service;
    if (service == null) return;
    final oui = await confirmer(
      context,
      titre: 'Supprimer cette sauvegarde ?',
      message: 'Le fichier « ${s.nom} » sera supprimé. Cette opération est définitive.',
      libelleConfirmer: 'Supprimer',
      danger: true,
    );
    if (!oui || !mounted) return;
    final ok = await executer(
      context,
      () => service.supprimer(s),
      succes: 'Sauvegarde supprimée.',
    );
    if (ok) await _charger();
  }

  Future<void> _restaurer(String chemin) async {
    if (_etat.gestionBase == null) return;
    await ouvrirRestauration(context, _etat, chemin, quitter: widget.quitter);
    if (mounted) await _charger();
  }

  Future<void> _restaurerDepuisFichier() async {
    final chemin = await widget.selecteurFichier();
    if (chemin == null || chemin.trim().isEmpty || !mounted) return;
    await _restaurer(chemin);
  }

  @override
  Widget build(BuildContext context) {
    if (_service == null) {
      return const MessageVide(
        'Les sauvegardes ne sont pas disponibles dans ce mode.',
        icone: Icons.backup_outlined,
      );
    }
    final c = _edition;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const TitreSection(
          'Sauvegardes',
          sousTitre: 'GESCO copie la base chaque jour, relit et contrôle chaque copie, '
              'et garde les plus récentes. Une sauvegarde contient tout : élèves, notes, '
              'comptes et permissions.',
        ),
        const SizedBox(height: 16),
        if (_erreurChargement != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SelectableText(
              'Impossible de lire l\'état des sauvegardes : $_erreurChargement',
              key: const Key('sauv_erreur_chargement'),
              style: const TextStyle(color: CouleursGesco.rouge),
            ),
          ),
        if (c != null) _carteAutomatique(c),
        const SizedBox(height: 16),
        _carteManuelle(),
        const SizedBox(height: 16),
        _carteHistorique(),
        const SizedBox(height: 16),
        _carteRestauration(),
      ],
    );
  }

  // ------------------------------------------------------------ Automatique

  Widget _carteAutomatique(ConfigSauvegarde c) {
    final erreurAuto = _etat.planificateurSauvegarde?.derniereErreur;
    final avertissementAuto = _etat.planificateurSauvegarde?.dernierAvertissement;
    final derniere = _historique
        .where((s) => s.type == TypeSauvegarde.automatique && s.existe)
        .firstOrNull;
    final minutes = <int>{for (var m = 0; m < 60; m += 5) m, c.minute}.toList()..sort();
    final nombres = <int>{..._nombres, c.conserver}.toList()..sort();
    return Carte(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sauvegarde automatique',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const Key('sauv_auto'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Sauvegarder automatiquement chaque jour'),
            subtitle: const Text(
              'Si l\'ordinateur était éteint à l\'heure prévue, la sauvegarde manquée '
              'est faite au démarrage de GESCO.',
            ),
            value: c.auto,
            onChanged: (v) => _modifier((x) => x.copie(auto: v)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 130,
                child: ChoixListe<int>(
                  cleChamp: const Key('sauv_heure'),
                  libelle: 'Heure',
                  valeur: c.heure,
                  options: [for (var h = 0; h < 24; h++) (h, '${h.toString().padLeft(2, '0')} h')],
                  onChanged: c.auto ? (v) => _modifier((x) => x.copie(heure: v)) : null,
                ),
              ),
              SizedBox(
                width: 130,
                child: ChoixListe<int>(
                  cleChamp: const Key('sauv_minute'),
                  libelle: 'Minute',
                  valeur: c.minute,
                  options: [for (final m in minutes) (m, m.toString().padLeft(2, '0'))],
                  onChanged: c.auto ? (v) => _modifier((x) => x.copie(minute: v)) : null,
                ),
              ),
              SizedBox(
                width: 260,
                child: ChoixListe<int>(
                  cleChamp: const Key('sauv_conserver'),
                  libelle: 'Sauvegardes automatiques à conserver',
                  valeur: c.conserver,
                  options: [for (final n in nombres) (n, '$n dernières')],
                  onChanged: (v) => _modifier((x) => x.copie(conserver: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.usb, size: 20, color: CouleursGesco.gris),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.dossierExterne.isEmpty
                      ? 'Copie sur clé USB ou disque externe : aucune'
                      : 'Copie sur clé USB ou disque externe : ${c.dossierExterne}',
                  key: const Key('sauv_externe_texte'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('sauv_externe_choisir'),
                onPressed: _choisirDossierExterne,
                icon: const Icon(Icons.folder_open),
                label: const Text('Choisir une clé USB ou un dossier...'),
              ),
              if (c.dossierExterne.isNotEmpty)
                TextButton(
                  key: const Key('sauv_externe_retirer'),
                  onPressed: () => _modifier((x) => x.copie(dossierExterne: '')),
                  child: const Text('Ne plus copier'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('sauv_config_enregistrer'),
            onPressed: _modifiee ? _enregistrer : null,
            child: const Text('Enregistrer les réglages'),
          ),
          const Divider(height: 28),
          Text(
            derniere == null
                ? 'Aucune sauvegarde automatique pour le moment.'
                : 'Dernière sauvegarde automatique : ${dateSauvegarde(derniere.creeLe)}'
                    '${derniere.verifiee ? ' (contrôlée)' : ''}',
            key: const Key('sauv_derniere_auto'),
          ),
          if (erreurAuto != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              'La dernière sauvegarde automatique a échoué : $erreurAuto',
              key: const Key('sauv_erreur_auto'),
              style: const TextStyle(color: CouleursGesco.rouge),
            ),
          ],
          if (avertissementAuto != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              avertissementAuto,
              key: const Key('sauv_avertissement_auto'),
              style: const TextStyle(color: CouleursGesco.orange),
            ),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------------------- Manuelle

  Widget _carteManuelle() {
    final r = _derniereCreee;
    return Carte(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sauvegarde manuelle',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Faites une sauvegarde avant une opération importante, ou copiez-la sur une '
            'clé USB pour la garder hors de cet ordinateur.',
            style: TextStyle(color: CouleursGesco.gris),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('sauv_creer'),
                onPressed: _occupe ? null : () => _creer(),
                icon: const Icon(Icons.backup_outlined),
                label: const Text('Sauvegarder maintenant'),
              ),
              OutlinedButton.icon(
                key: const Key('sauv_creer_externe'),
                onPressed: _occupe ? null : _creerSurDossier,
                icon: const Icon(Icons.usb),
                label: const Text('Sauvegarder sur une clé USB ou un dossier...'),
              ),
            ],
          ),
          if (_occupe) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(key: Key('sauv_en_cours')),
          ],
          if (r != null) ...[
            const SizedBox(height: 12),
            Container(
              key: const Key('sauv_resultat'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CouleursGesco.vertClair,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                'Sauvegarde créée et contrôlée : ${r.sauvegarde.nom} '
                '(${tailleLisible(r.sauvegarde.taille)}).\n'
                'Emplacement : ${r.sauvegarde.chemin}',
                key: const Key('sauv_resultat_texte'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------- Historique

  Widget _carteHistorique() {
    final peutRestaurer = _etat.peut(Permission.sauvegardeRestaurer) && _etat.gestionBase != null;
    return Carte(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Historique des sauvegardes',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_historique.isEmpty)
            const Text(
              'Aucune sauvegarde pour le moment.',
              key: Key('sauv_historique_vide'),
              style: TextStyle(color: CouleursGesco.gris),
            ),
          for (final (i, s) in _historique.indexed)
            ListTile(
              key: Key('sauv_ligne_$i'),
              contentPadding: EdgeInsets.zero,
              leading: _iconeEtat(s),
              title: Text('${s.type.libelle} · ${dateSauvegarde(s.creeLe)}'),
              subtitle: Text(
                '${s.nom} · ${tailleLisible(s.taille)}'
                '${s.utilisateur.isEmpty ? '' : ' · ${s.utilisateur}'}'
                '${s.existe ? '' : ' · fichier introuvable (clé USB retirée ou fichier déplacé ?)'}'
                '${s.existe && !s.verifiee ? ' · contrôle en échec' : ''}',
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  if (s.existe)
                    IconButton(
                      key: Key('sauv_verifier_$i'),
                      tooltip: 'Contrôler cette sauvegarde',
                      onPressed: () => _verifier(s),
                      icon: const Icon(Icons.verified_outlined),
                    ),
                  if (s.existe && peutRestaurer)
                    IconButton(
                      key: Key('sauv_restaurer_$i'),
                      tooltip: 'Restaurer cette sauvegarde',
                      onPressed: () => _restaurer(s.chemin),
                      icon: const Icon(Icons.settings_backup_restore),
                    ),
                  IconButton(
                    key: Key('sauv_supprimer_$i'),
                    tooltip: 'Supprimer cette sauvegarde',
                    onPressed: () => _supprimer(s),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _iconeEtat(Sauvegarde s) {
    if (!s.existe) return const Icon(Icons.link_off, color: CouleursGesco.orange);
    if (!s.verifiee) return const Icon(Icons.error_outline, color: CouleursGesco.rouge);
    return const Icon(Icons.check_circle_outline, color: CouleursGesco.vert);
  }

  // ---------------------------------------------------------- Restauration

  Widget _carteRestauration() {
    final peut = _etat.peut(Permission.sauvegardeRestaurer);
    return Carte(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Restaurer une sauvegarde',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pour reprendre des données après un problème, ou les installer sur un autre '
            'ordinateur : installez GESCO, puis choisissez ici le fichier de sauvegarde '
            '(copié depuis une clé USB, par exemple). GESCO contrôle le fichier, sauvegarde '
            'les données actuelles, remplace les données et revient en arrière si '
            'quelque chose se passe mal.',
            style: TextStyle(color: CouleursGesco.gris),
          ),
          const SizedBox(height: 12),
          if (peut && _etat.gestionBase != null)
            OutlinedButton.icon(
              key: const Key('sauv_restaurer_fichier'),
              onPressed: _restaurerDepuisFichier,
              icon: const Icon(Icons.upload_file),
              label: const Text('Restaurer depuis un fichier...'),
            )
          else
            const Text(
              'Seul un compte autorisé à restaurer les sauvegardes (administrateur) '
              'peut le faire.',
              key: Key('sauv_restaurer_refuse'),
              style: TextStyle(color: CouleursGesco.orange),
            ),
        ],
      ),
    );
  }
}

/// Résultat du contrôle d'une sauvegarde de l'historique.
class _DialogueVerification extends StatelessWidget {
  const _DialogueVerification({required this.s, required this.resultat});

  final Sauvegarde s;
  final ResultatVerification resultat;

  @override
  Widget build(BuildContext context) {
    final m = resultat.manifeste;
    final valide = resultat.valide;
    return AlertDialog(
      key: const Key('sauv_verif_dialogue'),
      title: Text(valide ? 'Sauvegarde valide' : 'Sauvegarde non valide'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (valide && m != null) ...[
                const Text(
                  'Le fichier a été relu : l\'archive est complète, son empreinte '
                  'SHA-256 est exacte et la base de données est saine.',
                  key: Key('sauv_verif_ok'),
                ),
                const SizedBox(height: 8),
                Text('Créée le ${dateHeureFr(m.creeLe)} par ${m.utilisateur}.'),
                if (m.etablissement.isNotEmpty) Text('Établissement : ${m.etablissement}'),
                if (m.annee.isNotEmpty) Text('Année scolaire : ${m.annee}'),
                Text(
                  '${m.contenu['eleves'] ?? 0} élève(s), ${m.contenu['classes'] ?? 0} classe(s), '
                  '${m.contenu['comptes'] ?? 0} compte(s).',
                ),
              ] else
                for (final (i, p) in resultat.problemes.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: SelectableText(
                      p,
                      key: Key('sauv_verif_probleme_$i'),
                      style: const TextStyle(color: CouleursGesco.rouge),
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('sauv_verif_fermer'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
