import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../models/media_draft.dart';

String mediaDraftKindLabel(MediaDraftKind kind) {
  return switch (kind) {
    MediaDraftKind.image => 'Image',
    MediaDraftKind.video => 'Vidéo',
    MediaDraftKind.audio => 'Audio',
    MediaDraftKind.document => 'Document',
  };
}

String? mediaDraftSizeLabel(int? byteSize) {
  if (byteSize == null) {
    return null;
  }
  if (byteSize < 1024) {
    return '$byteSize o';
  }
  final ko = (byteSize / 1024).floor();
  return '$ko Ko';
}

/// Liste locale des médias du brouillon. Aucun appel réseau.
class MediaDraftList extends StatelessWidget {
  const MediaDraftList({
    super.key,
    required this.medias,
    required this.onRemove,
  });

  final List<MediaDraft> medias;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < medias.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _MediaDraftTile(
            media: medias[i],
            onRemove: () => onRemove(medias[i].id),
          ),
        ],
      ],
    );
  }
}

class _MediaDraftTile extends StatelessWidget {
  const _MediaDraftTile({
    required this.media,
    required this.onRemove,
  });

  final MediaDraft media;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final name = media.fileName?.trim();
    final size = mediaDraftSizeLabel(media.byteSize);
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mediaDraftKindLabel(media.kind),
                  style: AppTextTheme.titleSmall.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  (name == null || name.isEmpty) ? 'Sans nom' : name,
                  style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                ),
                if (size != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    size,
                    style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Supprimer',
            onPressed: onRemove,
            icon: Icon(Icons.close, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
