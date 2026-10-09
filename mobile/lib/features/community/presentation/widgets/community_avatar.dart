import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_theme.dart';

class CommunityAvatar extends StatelessWidget {
  const CommunityAvatar({
    super.key,
    this.readUrl,
    this.size = 40,
    this.onEdit,
    this.heroTag,
  });

  final String? readUrl;
  final double size;
  final VoidCallback? onEdit;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final image = readUrl;
    final circle = Container(
      key: const ValueKey('community-identity-avatar'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.bgSurface,
        border: Border.all(color: colors.bgBase, width: size >= 72 ? 3 : 2),
        boxShadow: [
          BoxShadow(
            color: colors.textPrimary.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: image == null
          ? Center(
              child: Text(
                'Avatar',
                key: const ValueKey('community-placeholder-Avatar'),
                style: AppTextTheme.bodyMedium.copyWith(
                  color: colors.textSecondary,
                  fontSize: size >= 72 ? 12 : 10,
                ),
              ),
            )
          : Image.network(
              image,
              key: const ValueKey('community-identity-avatar-image'),
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, __, ___) => Icon(
                Icons.groups_outlined,
                color: colors.textSecondary,
                size: size * 0.42,
              ),
            ),
    );

    final content = onEdit == null
        ? circle
        : GestureDetector(
            key: const ValueKey('community-identity-avatar-edit'),
            behavior: HitTestBehavior.opaque,
            onTap: onEdit,
            child: circle,
          );

    if (heroTag == null) {
      return content;
    }
    return Hero(tag: heroTag!, child: content);
  }
}
