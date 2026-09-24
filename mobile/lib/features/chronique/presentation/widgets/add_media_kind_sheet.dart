import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../models/media_draft.dart';
import 'media_draft_list.dart';

/// Choix de type média. La galerie / le sélecteur système s’ouvrent ensuite.
Future<MediaDraftKind?> showAddMediaKindSheet(BuildContext context) {
  return showModalBottomSheet<MediaDraftKind>(
    context: context,
    builder: (context) {
      final colors = context.luminaColors;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final kind in MediaDraftKind.values)
                ListTile(
                  title: Text(
                    mediaDraftKindLabel(kind),
                    style: AppTextTheme.bodyLarge.copyWith(color: colors.textPrimary),
                  ),
                  onTap: () => Navigator.of(context).pop(kind),
                ),
            ],
          ),
        ),
      );
    },
  );
}
