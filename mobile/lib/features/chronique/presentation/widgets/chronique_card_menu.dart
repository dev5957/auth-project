import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/chronique.dart';
import '../../models/chronique_correction_window.dart';

enum ChroniqueCardMenuAction { edit, archive, delete }

/// Menu ⋮ : active → Modifier/Archiver/Supprimer ; scheduled → Modifier/Supprimer ;
/// archived → Supprimer.
class ChroniqueCardMenu extends StatelessWidget {
  const ChroniqueCardMenu({
    super.key,
    required this.chronique,
    required this.onSelected,
    this.enabled = true,
  });

  final Chronique chronique;
  final ValueChanged<ChroniqueCardMenuAction> onSelected;
  final bool enabled;

  static bool isAvailable(Chronique chronique) {
    return chronique.status == 'active' ||
        chronique.status == 'scheduled' ||
        chronique.status == 'archived';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return PopupMenuButton<ChroniqueCardMenuAction>(
      key: ValueKey('chronique-card-menu-${chronique.id}'),
      tooltip: 'Actions',
      enabled: enabled,
      icon: Icon(Icons.more_vert, color: colors.textSecondary),
      onSelected: onSelected,
      itemBuilder: (context) {
        if (chronique.status == 'archived') {
          return const [
            PopupMenuItem(
              value: ChroniqueCardMenuAction.delete,
              child: Text('Supprimer'),
            ),
          ];
        }
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
        return [
          if (isChroniqueTextCorrectionOpen(chronique))
            const PopupMenuItem(
              value: ChroniqueCardMenuAction.edit,
              child: Text('Modifier'),
            ),
          const PopupMenuItem(
            value: ChroniqueCardMenuAction.archive,
            child: Text('Archiver'),
          ),
          const PopupMenuItem(
            value: ChroniqueCardMenuAction.delete,
            child: Text('Supprimer'),
          ),
        ];
      },
    );
  }
}
