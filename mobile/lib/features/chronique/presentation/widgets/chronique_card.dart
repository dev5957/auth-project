import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../models/chronique.dart';
import '../../models/chronique_date.dart';
import 'chronique_card_menu.dart';

/// Carte V1 d’une chronique du fil (date, titre optionnel, texte).
class ChroniqueCard extends StatelessWidget {
  const ChroniqueCard({
    super.key,
    required this.chronique,
    this.onTap,
    this.onMenuSelected,
    this.excerpt,
  });

  final Chronique chronique;
  final VoidCallback? onTap;
  final ValueChanged<ChroniqueCardMenuAction>? onMenuSelected;
  final String? excerpt;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final title = chronique.title?.trim();
    final body = excerpt ?? chronique.body;
    final showMenu = onMenuSelected != null && ChroniqueCardMenu.isAvailable(chronique);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _temporalLines(colors),
                  ),
                ),
              ),
              if (showMenu)
                ChroniqueCardMenu(
                  chronique: chronique,
                  onSelected: onMenuSelected!,
                ),
            ],
          ),
          GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null && title.isNotEmpty) ...[
                  Text(
                    title,
                    style: AppTextTheme.titleSmall.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Text(
                  body,
                  style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _temporalLines(LuminaColors colors) {
    final style = AppTextTheme.labelSmall.copyWith(color: colors.textSecondary);
    if (chronique.status == 'scheduled') {
      final when = formatOptionalChroniqueDate(chronique.scheduledAt) ??
          chroniqueDateLabel(chronique);
      return [
        Text('Programmée', style: style),
        if (when.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(when, style: style),
        ],
        const SizedBox(height: AppSpacing.sm),
      ];
    }

    final lines = <Widget>[];
    final dateLabel = chroniqueDateLabel(chronique);
    if (dateLabel.isNotEmpty) {
      lines.add(Text(dateLabel, style: style));
    }
    if (chronique.status == 'active' &&
        chronique.isTimeLimited &&
        chronique.expiresAt != null) {
      if (lines.isNotEmpty) {
        lines.add(const SizedBox(height: AppSpacing.xs));
      }
      lines.add(Text('Expire le', style: style));
      lines.add(const SizedBox(height: AppSpacing.xs));
      lines.add(Text(ChroniqueDateHelper.formatLocal(chronique.expiresAt!), style: style));
    }
    if (chronique.status == 'expired') {
      if (lines.isNotEmpty) {
        lines.add(const SizedBox(height: AppSpacing.xs));
      }
      lines.add(Text('Expirée', style: style));
    }
    if (lines.isNotEmpty) {
      lines.add(const SizedBox(height: AppSpacing.sm));
    }
    return lines;
  }
}
