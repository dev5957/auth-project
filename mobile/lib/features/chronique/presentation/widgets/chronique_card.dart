import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../models/chronique.dart';

/// Carte V1 d’une chronique du fil (date, titre optionnel, texte).
class ChroniqueCard extends StatelessWidget {
  const ChroniqueCard({
    super.key,
    required this.chronique,
    this.onTap,
  });

  final Chronique chronique;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final dateLabel = chroniqueDateLabel(chronique);
    final title = chronique.title?.trim();
    return GestureDetector(
      onTap: onTap,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (dateLabel.isNotEmpty) ...[
              Text(
                dateLabel,
                style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (title != null && title.isNotEmpty) ...[
              Text(
                title,
                style: AppTextTheme.titleSmall.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Text(
              chronique.body,
              style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

String chroniqueDateLabel(Chronique chronique) {
  final raw = chronique.publishedAt ?? chronique.createdAt;
  if (raw == null || raw.isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  final utc = parsed.toUtc();
  final day = utc.day.toString().padLeft(2, '0');
  final month = utc.month.toString().padLeft(2, '0');
  return '$day/$month/${utc.year}';
}
