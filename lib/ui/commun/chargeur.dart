import 'package:flutter/material.dart';

/// Charge des données de façon asynchrone et les affiche.
///
/// Quand [cle] change, les données sont rechargées ; pendant le rechargement,
/// les dernières données restent affichées (pas de clignotement).
class Chargeur<T> extends StatefulWidget {
  const Chargeur({
    super.key,
    required this.cle,
    required this.charger,
    required this.builder,
  });

  final Object? cle;
  final Future<T> Function() charger;
  final Widget Function(BuildContext context, T donnees) builder;

  @override
  State<Chargeur<T>> createState() => _ChargeurState<T>();
}

class _ChargeurState<T> extends State<Chargeur<T>> {
  late Future<T> _futur;
  T? _dernier;
  bool _aUnResultat = false;

  @override
  void initState() {
    super.initState();
    _futur = widget.charger();
  }

  @override
  void didUpdateWidget(Chargeur<T> ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cle != widget.cle) {
      _futur = widget.charger();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _futur,
      builder: (context, instantane) {
        if (instantane.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                'Erreur de chargement : ${instantane.error}',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }
        if (instantane.connectionState == ConnectionState.done) {
          _dernier = instantane.data;
          _aUnResultat = true;
        }
        if (_aUnResultat) {
          return widget.builder(context, _dernier as T);
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}
