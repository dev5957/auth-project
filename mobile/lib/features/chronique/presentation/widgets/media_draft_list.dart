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
  if (byteSize == null || byteSize < 1) {
    return null;
  }
  const mo = 1024 * 1024;
  const ko = 1024;
  if (byteSize >= mo) {
    return '${(byteSize / mo).toStringAsFixed(1)} Mo';
  }
  if (byteSize >= ko) {
    return '${(byteSize / ko).floor()} Ko';
  }
  return '$byteSize o';
}

IconData mediaDraftKindIcon(MediaDraftKind kind) {
  return switch (kind) {
    MediaDraftKind.image => Icons.image_outlined,
    MediaDraftKind.video => Icons.videocam_outlined,
    MediaDraftKind.audio => Icons.audiotrack_outlined,
    MediaDraftKind.document => Icons.description_outlined,
  };
}

/// Liste locale des médias du brouillon. Aucun appel réseau.
class MediaDraftList extends StatelessWidget {
  const MediaDraftList({
    super.key,
    required this.medias,
    this.onRemove,
  });

  final List<MediaDraft> medias;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < medias.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _MediaDraftTile(
            media: medias[i],
            onRemove: onRemove == null ? null : () => onRemove!(medias[i].id),
          ),
        ],
      ],
    );
  }
}

class _MediaDraftTile extends StatelessWidget {
  const _MediaDraftTile({
    required this.media,
    this.onRemove,
  });

  final MediaDraft media;
  final VoidCallback? onRemove;

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
          Icon(mediaDraftKindIcon(media.kind), color: colors.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (name == null || name.isEmpty) ? 'Sans nom' : name,
                  style: AppTextTheme.titleSmall.copyWith(color: colors.textPrimary),
                ),
                if (size != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    size,
                    style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                  ),
                ],
                if (_statusLabel(media) != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _statusLabel(media)!,
                    style: AppTextTheme.labelSmall.copyWith(
                      color: media.status == MediaDraftStatus.failed
                          ? colors.danger
                          : colors.textSecondary,
                    ),
                  ),
                ],
                if (media.status == MediaDraftStatus.uploading) ...[
                  const SizedBox(height: AppSpacing.sm),
                  LinearProgressIndicator(
                    value: media.uploadProgress.clamp(0, 100) / 100,
                  ),
                ],
              ],
            ),
          ),
          if (onRemove != null &&
              media.status != MediaDraftStatus.uploading &&
              media.status != MediaDraftStatus.uploaded)
            IconButton(
              key: ValueKey('remove-media-${media.id}'),
              tooltip: 'Supprimer',
              onPressed: onRemove,
              icon: Icon(Icons.close, color: colors.textSecondary),
            ),
        ],
      ),
    );
  }
}

String? _statusLabel(MediaDraft media) {
  return switch (media.status) {
    MediaDraftStatus.selected => null,
    MediaDraftStatus.uploading => 'Envoi… ${media.uploadProgress.clamp(0, 100)} %',
    MediaDraftStatus.uploaded => 'Terminé',
    MediaDraftStatus.failed => media.errorMessage?.trim().isNotEmpty == true
        ? media.errorMessage
        : 'Échec',
  };
}
