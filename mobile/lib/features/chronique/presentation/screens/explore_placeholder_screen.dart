import 'package:flutter/material.dart';

import '../../../../core/router/placeholder_screen.dart';

/// Entrée future du fil Chronique. Aucun métier Chronique dans ce lot.
class ExplorePlaceholderScreen extends StatelessWidget {
  const ExplorePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RouterPlaceholderScreen(title: 'EXPLORE');
  }
}
