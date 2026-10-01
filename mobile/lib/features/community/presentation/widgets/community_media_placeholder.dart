import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';

/// Placeholder visuel Lot 1 : aucun upload, aucune URL média.
class CommunityMediaPlaceholder extends StatelessWidget {
  const CommunityMediaPlaceholder({
    super.key,
    required this.label,
    this.height = 88,
  });

  final String label;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Semantics(
      label: label,
      child: Container(
        key: ValueKey('community-placeholder-$label'),
        height: height,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: BorderRadius.circular(AppSpacing.lg),
          border: Border.all(color: colors.border),
        ),
        child: Text(
          label,
          style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}
