import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../models/chronique_assistant_copy.dart';
import '../../models/chronique_date.dart';
import '../../models/chronique_schedule_draft.dart';
import '../../models/media_draft.dart';
import 'media_draft_list.dart';

/// Prévisualisation locale. Les options en pause ne sont pas présentées comme enregistrées.
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
    final scheduled = schedule.publishMode == ChroniquePublishMode.schedule &&
        schedule.scheduledAt != null;
    final expires = schedule.resolvedExpiresLocal();
    final expirationLabel = expires == null
        ? kChroniqueNoExpirationLabel
        : '${ChroniqueDateHelper.expirationLabel(schedule.effectivePreset)} · ${ChroniqueDateHelper.formatLocal(expires)}';

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
            scheduled ? kChroniquePublishScheduleLabel : kChroniquePublishNowLabel,
            key: const ValueKey('preview-publication'),
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
          ),
          if (scheduled) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              ChroniqueDateHelper.formatLocal(schedule.scheduledAt!),
              key: const ValueKey('preview-scheduled-at'),
              style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            kChroniqueEphemeralSectionLabel,
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
          const SizedBox(height: AppSpacing.lg),
          Text(
            kChroniquePausedOptionsPreviewTitle,
            key: const ValueKey('preview-paused-options'),
            style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Thème : $kChroniqueThemePausedMessage',
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Commentaires : $kChroniqueCommentsUnavailableMessage',
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Visibilité : $kChroniqueVisibilityUnavailableMessage',
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
