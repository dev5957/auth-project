import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../models/chronique.dart';
import 'chronique_ready_remote_media_list.dart';

/// Médias du détail auteur : consultation + ajout / suppression / ↑↓.
class ChroniqueDetailMediaSection extends StatelessWidget {
  const ChroniqueDetailMediaSection({
    super.key,
    required this.medias,
    required this.canAdd,
    required this.canDelete,
    required this.canReorder,
    required this.busy,
    this.onAdd,
    this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
  });

  final List<ChroniqueMedia> medias;
  final bool canAdd;
  final bool canDelete;
  final bool canReorder;
  final bool busy;
  final VoidCallback? onAdd;
  final ValueChanged<int>? onDelete;
  final ValueChanged<int>? onMoveUp;
  final ValueChanged<int>? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final displayable = displayableChroniqueRemoteMedia(medias);
    final ready = readyChroniqueMedia(medias);
    if (displayable.isEmpty && ready.isEmpty && !canAdd) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (displayable.isNotEmpty) ChroniqueReadyRemoteMediaList(medias: medias),
        if (canDelete || canReorder)
          for (var i = 0; i < ready.length; i++) ...[
            const SizedBox(height: AppSpacing.sm),
            _MediaMutationRow(
              media: ready[i],
              colors: colors,
              canDelete: canDelete,
              showUp: canReorder && i > 0,
              showDown: canReorder && i < ready.length - 1,
              busy: busy,
              onDelete: onDelete,
              onMoveUp: onMoveUp,
              onMoveDown: onMoveDown,
            ),
          ],
        if (canAdd) ...[
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            key: const ValueKey('chronique-detail-add-media'),
            label: '+ Ajouter un média',
            variant: AppButtonVariant.secondary,
            onPressed: busy ? null : onAdd,
          ),
        ],
      ],
    );
  }
}

class _MediaMutationRow extends StatelessWidget {
  const _MediaMutationRow({
    required this.media,
    required this.colors,
    required this.canDelete,
    required this.showUp,
    required this.showDown,
    required this.busy,
    this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
  });

  final ChroniqueMedia media;
  final LuminaColors colors;
  final bool canDelete;
  final bool showUp;
  final bool showDown;
  final bool busy;
  final ValueChanged<int>? onDelete;
  final ValueChanged<int>? onMoveUp;
  final ValueChanged<int>? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final id = media.id!;
    return Row(
      children: [
        Expanded(
          child: Text(
            media.originalFilename?.trim().isNotEmpty == true
                ? media.originalFilename!.trim()
                : media.kind,
            style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showUp)
          IconButton(
            key: ValueKey('chronique-media-up-$id'),
            tooltip: 'Monter',
            onPressed: busy ? null : () => onMoveUp?.call(id),
            icon: const Icon(Icons.arrow_upward),
          ),
        if (showDown)
          IconButton(
            key: ValueKey('chronique-media-down-$id'),
            tooltip: 'Descendre',
            onPressed: busy ? null : () => onMoveDown?.call(id),
            icon: const Icon(Icons.arrow_downward),
          ),
        if (canDelete)
          TextButton(
            key: ValueKey('chronique-media-delete-$id'),
            onPressed: busy ? null : () => onDelete?.call(id),
            child: const Text('Supprimer'),
          ),
      ],
    );
  }
}
