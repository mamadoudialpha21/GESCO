import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/erreurs.dart';
import '../../data/images.dart';
import '../../data/modeles_donnees.dart';
import '../../data/validation_eleve.dart';
import '../../domain/dates.dart';
import '../../domain/matricule.dart';
import '../commun/composants.dart';
import '../theme.dart';

/// Enregistre la fiche. Doit lever une [ErreurGesco] si l'enregistrement est
/// refusé (le formulaire reste alors ouvert avec le message).
typedef EnregistrerEleve = Future<void> Function(Eleve eleve, int classeId);

/// Formulaire d'inscription (création) ou de modification d'un élève.
///
/// Le formulaire ne se ferme qu'après un enregistrement réussi : en cas de
/// refus (matricule déjà utilisé, par exemple), la saisie n'est pas perdue.
class DialogueEleve extends StatefulWidget {
  const DialogueEleve({
    super.key,
    required this.classes,
    required this.matricules,
    required this.prefixeMatricule,
    required this.enregistrer,
    this.classeInitiale,
    this.eleve,
    this.nbNotes = 0,
  });

  /// Classes de l'année scolaire (au moins une).
  final List<Classe> classes;

  /// Matricules déjà utilisés (pour proposer le suivant).
  final List<String> matricules;

  /// Début du matricule proposé (par exemple « 2026 » -> « 2026-0001 »).
  final String prefixeMatricule;

  final EnregistrerEleve enregistrer;

  /// Classe présélectionnée (celle du filtre, ou celle de l'élève modifié).
  final int? classeInitiale;

  /// Élève à modifier ; null pour une nouvelle inscription.
  final Eleve? eleve;

  /// Nombre de notes déjà saisies pour cette inscription (modification) :
  /// si elles existent, la classe ne peut plus être changée.
  final int nbNotes;

  @override
  State<DialogueEleve> createState() => _DialogueEleveState();
}

class _DialogueEleveState extends State<DialogueEleve> {
  final TextEditingController _matricule = TextEditingController();
  final TextEditingController _nom = TextEditingController();
  final TextEditingController _prenom = TextEditingController();
  final TextEditingController _date = TextEditingController();
  final TextEditingController _lieu = TextEditingController();
  final TextEditingController _pere = TextEditingController();
  final TextEditingController _mere = TextEditingController();
  final TextEditingController _contact = TextEditingController();
  final TextEditingController _adresse = TextEditingController();
  final TextEditingController _telephone = TextEditingController();
  final TextEditingController _tuteur = TextEditingController();
  final TextEditingController _contactTuteur = TextEditingController();
  final FocusNode _focusNom = FocusNode();

  late final List<String> _matricules = List<String>.of(widget.matricules);

  String? _sexe;
  int? _classeId;
  Uint8List? _photo;

  String? _erreurDate;
  List<String> _erreurs = const [];
  bool _enCours = false;
  int _ajoutes = 0;

  bool get _creation => widget.eleve == null;
  bool get _classeVerrouillee => !_creation && widget.nbNotes > 0;

  @override
  void initState() {
    super.initState();
    final e = widget.eleve;
    if (e != null) {
      _matricule.text = e.matricule;
      _nom.text = e.nom;
      _prenom.text = e.prenom;
      _date.text = formaterDateFr(e.dateNaissance);
      _lieu.text = e.lieuNaissance;
      _pere.text = e.nomPere;
      _mere.text = e.nomMere;
      _contact.text = e.contactParent;
      _adresse.text = e.adresse;
      _telephone.text = e.telephone;
      _tuteur.text = e.nomTuteur;
      _contactTuteur.text = e.contactTuteur;
      _sexe = e.sexe;
      _photo = e.photo;
    } else {
      _matricule.text = _matriculeSuivant();
    }
    final initiale = widget.classeInitiale;
    final existe = widget.classes.any((c) => c.id == initiale);
    _classeId = existe
        ? initiale
        : (widget.classes.isEmpty ? null : widget.classes.first.id);
  }

  @override
  void dispose() {
    _matricule.dispose();
    _nom.dispose();
    _prenom.dispose();
    _date.dispose();
    _lieu.dispose();
    _pere.dispose();
    _mere.dispose();
    _contact.dispose();
    _adresse.dispose();
    _telephone.dispose();
    _tuteur.dispose();
    _contactTuteur.dispose();
    _focusNom.dispose();
    super.dispose();
  }

  String _matriculeSuivant() =>
      proposerMatricule(widget.prefixeMatricule, _matricules);

  Future<void> _choisirPhoto() async {
    final resultat = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (resultat == null || resultat.files.isEmpty) return;

    final fichier = resultat.files.single;
    Uint8List? octets = fichier.bytes;
    final chemin = fichier.path;
    if (octets == null && chemin != null) {
      octets = await File(chemin).readAsBytes();
    }
    if (!mounted) return;
    if (octets == null) {
      setState(() => _erreurs = const ['Impossible de lire le fichier choisi.']);
      return;
    }
    try {
      verifierImage(octets, tailleMax: tailleMaxPhoto, nom: 'La photo');
    } on ErreurGesco catch (e) {
      setState(() => _erreurs = [e.message]);
      return;
    }
    setState(() {
      _photo = octets;
      _erreurs = const [];
    });
  }

  Future<void> _choisirDate() async {
    final maintenant = DateTime.now();
    final aujourdHui = DateTime(maintenant.year, maintenant.month, maintenant.day);
    var initiale = analyserDateFr(_date.text.trim()) ??
        DateTime(aujourdHui.year - 12, 1, 1);
    if (initiale.isAfter(aujourdHui)) initiale = aujourdHui;
    final choix = await showDatePicker(
      context: context,
      initialDate: initiale,
      firstDate: DateTime(1900),
      lastDate: aujourdHui,
      helpText: 'Date de naissance',
    );
    if (choix == null || !mounted) return;
    setState(() {
      _date.text = dateVersFr(choix);
      _erreurDate = null;
    });
  }

  /// Construit la fiche à partir des champs. Retourne null (et affiche les
  /// erreurs) si elle n'est pas valide.
  Eleve? _construire() {
    final texteDate = _date.text.trim();
    String? iso;
    String? erreurDate;
    if (texteDate.isNotEmpty) {
      final date = analyserDateFr(texteDate);
      if (date == null) {
        erreurDate = 'Date invalide : utilisez JJ/MM/AAAA (ex. 05/03/2011).';
      } else {
        iso = dateVersIso(date);
      }
    }

    final eleve = Eleve(
      id: widget.eleve?.id ?? 0,
      matricule: _matricule.text.trim(),
      nom: _nom.text.trim(),
      prenom: _prenom.text.trim(),
      sexe: _sexe ?? '',
      dateNaissance: iso,
      lieuNaissance: _lieu.text.trim(),
      nomPere: _pere.text.trim(),
      nomMere: _mere.text.trim(),
      contactParent: _contact.text.trim(),
      adresse: _adresse.text.trim(),
      photo: _photo,
      telephone: _telephone.text.trim(),
      nomTuteur: _tuteur.text.trim(),
      contactTuteur: _contactTuteur.text.trim(),
      archive: widget.eleve?.archive ?? false,
    );
    final erreurs = erreursEleve(eleve, maintenant: DateTime.now());
    setState(() {
      _erreurDate = erreurDate;
      _erreurs = erreurs;
    });
    if (erreurDate != null || erreurs.isNotEmpty) return null;
    return eleve;
  }

  void _vider() {
    _nom.clear();
    _prenom.clear();
    _date.clear();
    _lieu.clear();
    _pere.clear();
    _mere.clear();
    _contact.clear();
    _adresse.clear();
    _telephone.clear();
    _tuteur.clear();
    _contactTuteur.clear();
    _sexe = null;
    _photo = null;
    _erreurDate = null;
    _erreurs = const [];
    _matricule.text = _matriculeSuivant();
  }

  Future<void> _enregistrer({required bool continuer}) async {
    if (_enCours) return;
    final eleve = _construire();
    final classeId = _classeId;
    if (eleve == null) return;
    if (classeId == null) {
      setState(() => _erreurs = const ['Choisissez une classe.']);
      return;
    }

    setState(() => _enCours = true);
    try {
      await widget.enregistrer(eleve, classeId);
    } on ErreurGesco catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreurs = [e.message];
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreurs = ['Erreur inattendue : $e'];
      });
      return;
    }
    if (!mounted) return;

    if (continuer) {
      _matricules.add(eleve.matricule);
      setState(() {
        _enCours = false;
        _ajoutes++;
        _vider();
      });
      _focusNom.requestFocus();
    } else {
      Navigator.of(context).pop();
    }
  }

  Widget _paire(Widget gauche, Widget droite) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        if (contraintes.maxWidth < 480) {
          return Column(children: [gauche, const SizedBox(height: 12), droite]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: gauche),
            const SizedBox(width: 12),
            Expanded(child: droite),
          ],
        );
      },
    );
  }

  Widget _blocPhoto() {
    return Row(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: CouleursGesco.grisClair,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black12),
          ),
          child: _photo == null
              ? const Icon(Icons.person_outline, size: 44, color: CouleursGesco.gris)
              : ClipOval(
                  child: Image.memory(
                    _photo!,
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                    errorBuilder: (context, erreur, trace) =>
                        const Icon(Icons.broken_image_outlined),
                  ),
                ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('bouton_photo'),
                    onPressed: _enCours ? null : _choisirPhoto,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(_photo == null ? 'Ajouter une photo…' : 'Changer la photo…'),
                  ),
                  if (_photo != null)
                    TextButton.icon(
                      onPressed: _enCours ? null : () => setState(() => _photo = null),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Retirer'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Facultative. PNG ou JPEG, 1 Mo maximum.',
                style: TextStyle(color: CouleursGesco.gris),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _champClasse() {
    final verrouillee = _classeVerrouillee;
    return InputDecorator(
      decoration: champ(
        'Classe *',
        aide: verrouillee
            ? 'Classe verrouillée : ${widget.nbNotes} '
                '${widget.nbNotes > 1 ? 'notes sont déjà enregistrées' : 'note est déjà enregistrée'}.'
            : null,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          key: const Key('liste_classe'),
          isExpanded: true,
          isDense: true,
          value: _classeId,
          items: [
            for (final c in widget.classes)
              DropdownMenuItem<int>(value: c.id, child: Text(c.nom)),
          ],
          onChanged: (verrouillee || _enCours)
              ? null
              : (id) => setState(() => _classeId = id),
        ),
      ),
    );
  }

  Widget _blocSexe() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Sexe *', style: TextStyle(color: CouleursGesco.gris, fontSize: 12)),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          emptySelectionAllowed: true,
          segments: const [
            ButtonSegment<String>(
              value: 'M',
              label: Text('Masculin'),
              icon: Icon(Icons.male),
            ),
            ButtonSegment<String>(
              value: 'F',
              label: Text('Féminin'),
              icon: Icon(Icons.female),
            ),
          ],
          selected: _sexe == null ? <String>{} : <String>{_sexe!},
          onSelectionChanged: _enCours
              ? null
              : (choix) => setState(() => _sexe = choix.isEmpty ? null : choix.first),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final titre = _creation ? 'Inscrire un élève' : 'Modifier l\'élève';

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text(titre, style: Theme.of(context).textTheme.titleLarge),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _blocPhoto(),
                    const SizedBox(height: 20),
                    _paire(
                      TextField(
                        key: const Key('champ_matricule'),
                        controller: _matricule,
                        decoration: champ('Matricule *').copyWith(
                          suffixIcon: IconButton(
                            tooltip: 'Proposer le prochain matricule',
                            icon: const Icon(Icons.auto_fix_high),
                            onPressed: _enCours
                                ? null
                                : () => setState(() => _matricule.text = _matriculeSuivant()),
                          ),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      _champClasse(),
                    ),
                    const SizedBox(height: 12),
                    _paire(
                      TextField(
                        key: const Key('champ_nom'),
                        controller: _nom,
                        focusNode: _focusNom,
                        autofocus: true,
                        decoration: champ('Nom *'),
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                      ),
                      TextField(
                        key: const Key('champ_prenom'),
                        controller: _prenom,
                        decoration: champ('Prénom *'),
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _paire(
                      _blocSexe(),
                      TextField(
                        key: const Key('champ_date'),
                        controller: _date,
                        decoration: champ(
                          'Date de naissance',
                          aide: 'JJ/MM/AAAA',
                          erreur: _erreurDate,
                        ).copyWith(
                          suffixIcon: IconButton(
                            tooltip: 'Choisir dans le calendrier',
                            icon: const Icon(Icons.calendar_month),
                            onPressed: _enCours ? null : _choisirDate,
                          ),
                        ),
                        keyboardType: TextInputType.datetime,
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('champ_lieu'),
                      controller: _lieu,
                      decoration: champ('Lieu de naissance'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    _paire(
                      TextField(
                        key: const Key('champ_pere'),
                        controller: _pere,
                        decoration: champ('Nom du père'),
                        textInputAction: TextInputAction.next,
                      ),
                      TextField(
                        key: const Key('champ_mere'),
                        controller: _mere,
                        decoration: champ('Nom de la mère'),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _paire(
                      TextField(
                        key: const Key('champ_contact'),
                        controller: _contact,
                        decoration: champ('Contact du parent ou tuteur'),
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                      ),
                      TextField(
                        key: const Key('champ_adresse'),
                        controller: _adresse,
                        decoration: champ('Adresse'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _paire(
                      TextField(
                        key: const Key('champ_telephone'),
                        controller: _telephone,
                        decoration: champ('Téléphone de l\'élève'),
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                      ),
                      TextField(
                        key: const Key('champ_tuteur'),
                        controller: _tuteur,
                        decoration: champ('Nom du tuteur (si différent des parents)'),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _paire(
                      TextField(
                        key: const Key('champ_contact_tuteur'),
                        controller: _contactTuteur,
                        decoration: champ('Contact du tuteur'),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '* champs obligatoires',
                      style: TextStyle(color: CouleursGesco.gris, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            if (_erreurs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Container(
                  key: const Key('erreurs_formulaire'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CouleursGesco.rougeClair,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final message in _erreurs)
                        Text(
                          message,
                          style: const TextStyle(color: CouleursGesco.rouge),
                        ),
                    ],
                  ),
                ),
              ),
            if (_ajoutes > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Text(
                  _ajoutes > 1
                      ? '$_ajoutes élèves enregistrés pendant cette saisie.'
                      : '1 élève enregistré pendant cette saisie.',
                  style: const TextStyle(color: CouleursGesco.vert),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _enCours ? null : () => Navigator.of(context).pop(),
                    child: Text(_ajoutes > 0 ? 'Fermer' : 'Annuler'),
                  ),
                  if (_creation)
                    OutlinedButton(
                      onPressed: _enCours ? null : () => _enregistrer(continuer: true),
                      child: const Text('Enregistrer et ajouter un autre'),
                    ),
                  FilledButton(
                    onPressed: _enCours ? null : () => _enregistrer(continuer: false),
                    child: const Text('Enregistrer'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
