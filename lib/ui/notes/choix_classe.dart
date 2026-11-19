import 'package:flutter/material.dart';

import '../../data/modeles_donnees.dart';
import '../commun/composants.dart';

/// Liste déroulante de choix de la classe (commune aux vues de la page Notes).
class ChoixClasse extends StatelessWidget {
  const ChoixClasse({
    super.key,
    required this.classes,
    required this.classeId,
    required this.surClasse,
  });

  final List<ClasseResume> classes;
  final int classeId;
  final ValueChanged<int> surClasse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: InputDecorator(
        decoration: champ('Classe'),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            key: const Key('choix_classe'),
            isExpanded: true,
            isDense: true,
            value: classeId,
            items: [
              for (final c in classes)
                DropdownMenuItem<int>(
                  value: c.classe.id,
                  child: Text(c.classe.nom),
                ),
            ],
            onChanged: (id) {
              if (id != null) surClasse(id);
            },
          ),
        ),
      ),
    );
  }
}
