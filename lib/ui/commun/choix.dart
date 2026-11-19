import 'package:flutter/material.dart';

import 'composants.dart';

/// Liste déroulante au style des champs de saisie.
///
/// [options] associe chaque valeur à son libellé. [cleChamp] est posée sur la
/// liste elle-même (pour les tests). [onChanged] à null désactive la liste.
class ChoixListe<T> extends StatelessWidget {
  const ChoixListe({
    super.key,
    this.cleChamp,
    required this.libelle,
    required this.valeur,
    required this.options,
    required this.onChanged,
    this.aide,
    this.erreur,
  });

  final Key? cleChamp;
  final String libelle;
  final T? valeur;
  final List<(T, String)> options;
  final ValueChanged<T?>? onChanged;
  final String? aide;
  final String? erreur;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: champ(libelle, aide: aide, erreur: erreur),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          key: cleChamp,
          isExpanded: true,
          isDense: true,
          value: valeur,
          items: [
            for (final o in options)
              DropdownMenuItem<T>(
                value: o.$1,
                child: Text(o.$2, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
