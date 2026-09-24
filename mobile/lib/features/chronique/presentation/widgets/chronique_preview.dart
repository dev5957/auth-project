import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../models/chronique_date.dart';
import '../../models/chronique_schedule_draft.dart';
import '../../models/media_draft.dart';
import 'media_draft_list.dart';

/// Prévisualisation locale, proche d’une future ChroniqueCard.
class ChroniquePreview extends StatelessWidget {
  const ChroniquePreview({
    super.key,
    required this.title,
    required this.body,
    required this.medias,
    required this.schedule,
  });

  final String title;
  final String body;
  final List<MediaDraft> medias;
  final ChroniqueScheduleDraft schedule;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final trimmedTitle = title.trim();
    final publishLabel = schedule.publishMode == ChroniquePublishMode.schedule &&
            schedule.scheduledAt != null
        ? ChroniqueDateHelper.formatLocal(schedule.scheduledAt!)
        : 'Maintenant';
    final expires = schedule.resolvedExpiresLocal();
    final expirationLabel =
        expires == null ? 'Pas d\'expiration' : ChroniqueDateHelper.formatLocal(expires);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Publication',
            style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            publishLabel,
            key: const ValueKey('preview-publication'),
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Expiration',
            style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            expirationLabel,
            key: const ValueKey('preview-expiration'),
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (trimmedTitle.isNotEmpty) ...[
            Text(
              trimmedTitle,
              style: AppTextTheme.titleSmall.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(
            body,
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
          ),
          if (medias.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            MediaDraftList(medias: medias),
          ],
        ],
      ),
    );
  }
}
