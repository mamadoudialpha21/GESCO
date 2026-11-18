import 'package:flutter/material.dart';

import '../../app/etat_app.dart';
import '../../data/modeles_securite.dart';
import '../../domain/permissions.dart';
import '../commun/chargeur.dart';
import '../commun/composants.dart';
import '../commun/dialogues.dart';
import '../theme.dart';
import 'libelles.dart';

/// Gestion des comptes : création, rôle, permissions, mot de passe,
/// activation. Réservée aux administrateurs.
class OngletComptes extends StatefulWidget {
  const OngletComptes({super.key, required this.etat});

  final EtatApp etat;

  @override
  State<OngletComptes> createState() => _OngletComptesState();
}

class _OngletComptesState extends State<OngletComptes> {
  int _rafraichir = 0;

  EtatApp get etat => widget.etat;

  Future<void> _recharger() async {
    if (mounted) setState(() => _rafraichir++);
  }

  Future<void> _creer() async {
    final demande = await showDialog<_DemandeCompte>(
      context: context,
      builder: (ctx) => const _DialogueCompte(),
    );
    if (demande == null || !mounted) return;
    final ok = await executer(
      context,
      () async {
        await etat.services.utilisateurs.creer(
          identifiant: demande.identifiant,
          nomComplet: demande.nomComplet,
          role: demande.role,
          motDePasse: demande.motDePasse!,
          permissions: demande.permissions,
        );
      },
      succes: 'Compte « ${demande.identifiant.trim()} » créé. Il devra choisir '
          'son mot de passe à la première connexion.',
    );
    if (ok) await _recharger();
  }

  Future<void> _modifier(Utilisateur u) async {
    final demande = await showDialog<_DemandeCompte>(
      context: context,
      builder: (ctx) => _DialogueCompte(utilisateur: u),
    );
    if (demande == null || !mounted) return;
    final ok = await executer(
      context,
      () async {
        await etat.services.utilisateurs.modifierProfil(
          u.id,
          nomComplet: demande.nomComplet,
          role: demande.role,
          enseignantId: u.enseignantId,
          permissions: demande.permissions,
        );
        // Si c'est son propre compte, la session reprend les nouveaux droits.
        final moi = etat.services.session.utilisateur;
        if (moi != null && moi.id == u.id) {
          final frais = await etat.services.utilisateurs.obtenir(u.id);
          if (frais != null) etat.services.session.actualiser(frais);
        }
      },
      succes: 'Compte « ${u.identifiant} » modifié.',
    );
    if (ok) await _recharger();
  }

  Future<void> _reinitialiser(Utilisateur u) async {
    final mdp = await showDialog<String>(
      context: context,
      builder: (ctx) => _DialogueMotDePasseProvisoire(identifiant: u.identifiant),
    );
    if (mdp == null || !mounted) return;
    final ok = await executer(
      context,
      () => etat.services.utilisateurs.reinitialiserMotDePasse(u.id, mdp),
      succes: 'Mot de passe de « ${u.identifiant} » réinitialisé : '
          'il devra en choisir un nouveau à la prochaine connexion.',
    );
    if (ok) await _recharger();
  }

  Future<void> _basculerActif(Utilisateur u) async {
    if (u.actif) {
      final oui = await confirmer(
        context,
        titre: 'Désactiver le compte',
        message: '« ${u.identifiant} » ne pourra plus se connecter. Ses '
            'données et son historique sont conservés.',
        libelleConfirmer: 'Désactiver',
        danger: true,
      );
      if (!oui || !mounted) return;
    }
    final ok = await executer(
      context,
      () => etat.services.utilisateurs.definirActif(u.id, !u.actif),
      succes: u.actif ? 'Compte désactivé.' : 'Compte réactivé.',
    );
    if (ok) await _recharger();
  }

  Future<void> _supprimer(Utilisateur u) async {
    final oui = await confirmer(
      context,
      titre: 'Supprimer le compte',
      message: 'Supprimer définitivement le compte « ${u.identifiant} » ? '
          'Son nom reste inscrit dans le journal et l\'historique.',
      libelleConfirmer: 'Supprimer',
      danger: true,
    );
    if (!oui || !mounted) return;
    final ok = await executer(
      context,
      () => etat.services.utilisateurs.supprimer(
        u.id,
        parId: etat.services.session.utilisateur?.id,
      ),
      succes: 'Compte supprimé.',
    );
    if (ok) await _recharger();
  }

  Future<void> _nouveauCode() async {
    final oui = await confirmer(
      context,
      titre: 'Nouveau code de récupération',
      message: 'L\'ancien code ne fonctionnera plus. Le nouveau ne sera '
          'affiché qu\'une seule fois.',
      libelleConfirmer: 'Générer',
    );
    if (!oui || !mounted) return;
    String? code;
    final ok = await executer(
      context,
      () async => code = await etat.services.utilisateurs.nouveauCodeRecuperation(),
    );
    if (!ok || code == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Code de récupération'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notez ce code et gardez-le en lieu sûr. Il ne sera plus affiché.'),
            const SizedBox(height: 12),
            SelectableText(
              code!,
              key: const Key('code_recuperation_genere'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('J\'ai noté le code'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final moi = etat.services.session.utilisateur;
    return Chargeur<List<Utilisateur>>(
      cle: (_rafraichir, etat.version),
      charger: () => etat.services.utilisateurs.lister(),
      builder: (context, comptes) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: TitreSection(
                    'Comptes et permissions',
                    sousTitre: 'Chaque personne a son propre compte. Le rôle '
                        'fixe ce qu\'elle peut faire ; les permissions peuvent '
                        'être ajustées compte par compte.',
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  key: const Key('bouton_nouveau_compte'),
                  onPressed: _creer,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Nouveau compte'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final u in comptes)
              Carte(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: CouleursGesco.bleuClair,
                        child: Icon(
                          u.role == RoleUtilisateur.administrateur
                              ? Icons.admin_panel_settings_outlined
                              : Icons.person_outline,
                          color: CouleursGesco.bleu,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  u.nomAffiche,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                Etiquette(
                                  u.role.libelle,
                                  couleur: CouleursGesco.bleu,
                                  fond: CouleursGesco.bleuClair,
                                ),
                                if (!u.actif)
                                  const Etiquette(
                                    'Désactivé',
                                    couleur: CouleursGesco.rouge,
                                    fond: CouleursGesco.rougeClair,
                                  ),
                                if (u.permissionsPersonnalisees != null)
                                  const Etiquette(
                                    'Permissions personnalisées',
                                    couleur: CouleursGesco.orange,
                                    fond: CouleursGesco.orangeClair,
                                  ),
                                if (moi != null && moi.id == u.id)
                                  const Etiquette(
                                    'Vous',
                                    couleur: CouleursGesco.vert,
                                    fond: CouleursGesco.vertClair,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Identifiant : ${u.identifiant} · '
                              '${u.derniereConnexion == null ? 'jamais connecté' : 'dernière connexion le ${dateHeureFr(u.derniereConnexion!)}'}',
                              style: const TextStyle(color: CouleursGesco.gris),
                            ),
                            if (u.doitChangerMotDePasse)
                              const Text(
                                'Doit choisir son mot de passe à la prochaine connexion.',
                                style: TextStyle(color: CouleursGesco.orange, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        key: Key('menu_compte_${u.identifiant}'),
                        tooltip: 'Actions',
                        onSelected: (a) {
                          switch (a) {
                            case 'modifier':
                              _modifier(u);
                            case 'mdp':
                              _reinitialiser(u);
                            case 'actif':
                              _basculerActif(u);
                            case 'supprimer':
                              _supprimer(u);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'modifier', child: Text('Modifier')),
                          const PopupMenuItem(
                            value: 'mdp',
                            child: Text('Réinitialiser le mot de passe'),
                          ),
                          PopupMenuItem(
                            value: 'actif',
                            child: Text(u.actif ? 'Désactiver' : 'Réactiver'),
                          ),
                          if (moi == null || moi.id != u.id)
                            const PopupMenuItem(value: 'supprimer', child: Text('Supprimer')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Carte(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.key_outlined, color: CouleursGesco.bleu),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Code de récupération : permet à un administrateur qui a '
                      'perdu son mot de passe de retrouver l\'accès.',
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    key: const Key('bouton_nouveau_code'),
                    onPressed: _nouveauCode,
                    child: const Text('Générer un nouveau code'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DemandeCompte {
  const _DemandeCompte({
    required this.identifiant,
    required this.nomComplet,
    required this.role,
    required this.permissions,
    this.motDePasse,
  });

  final String identifiant;
  final String nomComplet;
  final RoleUtilisateur role;
  final Set<Permission>? permissions;
  final String? motDePasse;
}

/// Création ou modification d'un compte.
class _DialogueCompte extends StatefulWidget {
  const _DialogueCompte({this.utilisateur});

  final Utilisateur? utilisateur;

  @override
  State<_DialogueCompte> createState() => _DialogueCompteState();
}

class _DialogueCompteState extends State<_DialogueCompte> {
  late final TextEditingController _identifiant;
  late final TextEditingController _nom;
  final _motDePasse = TextEditingController();
  late RoleUtilisateur _role;
  late bool _personnaliser;
  late Set<Permission> _permissions;
  String? _erreur;

  bool get _creation => widget.utilisateur == null;

  @override
  void initState() {
    super.initState();
    final u = widget.utilisateur;
    _identifiant = TextEditingController(text: u?.identifiant ?? '');
    _nom = TextEditingController(text: u?.nomComplet ?? '');
    _role = u?.role ?? RoleUtilisateur.consultation;
    _personnaliser = u?.permissionsPersonnalisees != null;
    _permissions = {...?u?.permissionsPersonnalisees};
    if (!_personnaliser) _permissions = {...permissionsDuRole(_role)};
  }

  @override
  void dispose() {
    _identifiant.dispose();
    _nom.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  void _changerRole(RoleUtilisateur r) {
    setState(() {
      _role = r;
      if (!_personnaliser) _permissions = {...permissionsDuRole(r)};
      if (r == RoleUtilisateur.administrateur) _personnaliser = false;
    });
  }

  void _valider() {
    if (_creation && _identifiant.text.trim().isEmpty) {
      setState(() => _erreur = 'L\'identifiant est obligatoire.');
      return;
    }
    if (_creation && _motDePasse.text.isEmpty) {
      setState(() => _erreur = 'Choisissez un mot de passe provisoire.');
      return;
    }
    Navigator.of(context).pop(
      _DemandeCompte(
        identifiant: _identifiant.text,
        nomComplet: _nom.text,
        role: _role,
        motDePasse: _creation ? _motDePasse.text : null,
        permissions: _personnaliser && _role != RoleUtilisateur.administrateur
            ? _permissions
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final admin = _role == RoleUtilisateur.administrateur;
    return AlertDialog(
      title: Text(_creation ? 'Nouveau compte' : 'Modifier le compte'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('compte_identifiant'),
                controller: _identifiant,
                enabled: _creation,
                autocorrect: false,
                decoration: champ(
                  'Identifiant',
                  aide: _creation
                      ? 'Lettres, chiffres, point, tiret (3 caractères minimum)'
                      : 'L\'identifiant ne peut pas être modifié',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('compte_nom'),
                controller: _nom,
                decoration: champ('Nom complet'),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: champ('Rôle', aide: _role.description),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<RoleUtilisateur>(
                    key: const Key('compte_role'),
                    isExpanded: true,
                    isDense: true,
                    value: _role,
                    items: [
                      for (final r in RoleUtilisateur.values)
                        DropdownMenuItem(value: r, child: Text(r.libelle)),
                    ],
                    onChanged: (r) {
                      if (r != null) _changerRole(r);
                    },
                  ),
                ),
              ),
              if (_creation) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('compte_mot_de_passe'),
                  controller: _motDePasse,
                  autocorrect: false,
                  decoration: champ(
                    'Mot de passe provisoire',
                    aide: 'La personne devra le remplacer à sa première connexion.',
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (admin)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Un administrateur a toujours toutes les permissions.',
                    style: TextStyle(color: CouleursGesco.gris),
                  ),
                )
              else ...[
                SwitchListTile(
                  key: const Key('compte_personnaliser'),
                  contentPadding: EdgeInsets.zero,
                  value: _personnaliser,
                  onChanged: (v) => setState(() {
                    _personnaliser = v;
                    if (!v) _permissions = {...permissionsDuRole(_role)};
                  }),
                  title: const Text('Personnaliser les permissions'),
                  subtitle: const Text('Sinon, celles du rôle s\'appliquent.'),
                ),
                if (_personnaliser)
                  for (final groupe in permissionsParGroupe().entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 2),
                      child: Text(
                        groupe.key,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: CouleursGesco.bleu,
                        ),
                      ),
                    ),
                    for (final p in groupe.value)
                      CheckboxListTile(
                        key: Key('permission_${p.cle}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _permissions.contains(p),
                        onChanged: (v) => setState(() {
                          if (v ?? false) {
                            _permissions.add(p);
                          } else {
                            _permissions.remove(p);
                          }
                        }),
                        title: Text(p.libelle, style: const TextStyle(fontSize: 13.5)),
                      ),
                  ],
              ],
              if (_erreur != null) ...[
                const SizedBox(height: 8),
                Text(_erreur!, style: const TextStyle(color: CouleursGesco.rouge)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('bouton_valider_compte'),
          onPressed: _valider,
          child: Text(_creation ? 'Créer' : 'Enregistrer'),
        ),
      ],
    );
  }
}

class _DialogueMotDePasseProvisoire extends StatefulWidget {
  const _DialogueMotDePasseProvisoire({required this.identifiant});

  final String identifiant;

  @override
  State<_DialogueMotDePasseProvisoire> createState() =>
      _DialogueMotDePasseProvisoireState();
}

class _DialogueMotDePasseProvisoireState extends State<_DialogueMotDePasseProvisoire> {
  final _mdp = TextEditingController();

  @override
  void dispose() {
    _mdp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Réinitialiser « ${widget.identifiant} »'),
      content: SizedBox(
        width: 380,
        child: TextField(
          key: const Key('mdp_provisoire'),
          controller: _mdp,
          autofocus: true,
          autocorrect: false,
          decoration: champ(
            'Nouveau mot de passe provisoire',
            aide: 'La personne devra en choisir un nouveau à sa prochaine connexion.',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('bouton_valider_mdp'),
          onPressed: () => Navigator.of(context).pop(_mdp.text),
          child: const Text('Réinitialiser'),
        ),
      ],
    );
  }
}
