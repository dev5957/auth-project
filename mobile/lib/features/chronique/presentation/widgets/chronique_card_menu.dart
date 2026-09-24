import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/chronique.dart';

enum ChroniqueCardMenuAction { edit, archive, delete }

/// Menu ⋮ d’une carte : active → Modifier/Archiver ; scheduled → Modifier/Supprimer.
class ChroniqueCardMenu extends StatelessWidget {
  const ChroniqueCardMenu({
    super.key,
    required this.chronique,
    required this.onSelected,
  });

  final Chronique chronique;
  final ValueChanged<ChroniqueCardMenuAction> onSelected;

  static bool isAvailable(Chronique chronique) {
    return chronique.status == 'active' || chronique.status == 'scheduled';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return PopupMenuButton<ChroniqueCardMenuAction>(
      key: ValueKey('chronique-card-menu-${chronique.id}'),
      tooltip: 'Actions',
      icon: Icon(Icons.more_vert, color: colors.textSecondary),
      onSelected: onSelected,
      itemBuilder: (context) {
        if (chronique.status == 'scheduled') {
          return const [
            PopupMenuItem(
              value: ChroniqueCardMenuAction.edit,
              child: Text('Modifier'),
            ),
            PopupMenuItem(
              value: ChroniqueCardMenuAction.delete,
              child: Text('Supprimer'),
            ),
          ];
        }
        return const [
          PopupMenuItem(
            value: ChroniqueCardMenuAction.edit,
            child: Text('Modifier'),
          ),
          PopupMenuItem(
            value: ChroniqueCardMenuAction.archive,
            child: Text('Archiver'),
          ),
        ];
      },
    );
  }
}
