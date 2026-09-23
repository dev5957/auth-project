import 'package:flutter/material.dart';

import '../../../../core/router/placeholder_screen.dart';

/// Entrée future de l'assistant de création. Aucun métier Chronique dans ce lot.
class CreatePlaceholderScreen extends StatelessWidget {
  const CreatePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RouterPlaceholderScreen(title: 'CREATE');
  }
}
