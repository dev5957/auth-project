import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../models/chronique.dart';
import '../../models/chronique_date.dart';
import 'chronique_card_menu.dart';
import 'chronique_feed_media.dart';

/// Carte d’une chronique (fil, archives, à venir).
class ChroniqueCard extends StatefulWidget {
  const ChroniqueCard({
    super.key,
    required this.chronique,
    this.onTap,
    this.onMenuSelected,
    this.excerpt,
    this.showFeedMedia = false,
    this.showInactiveSocialActions = false,
    this.onMediaSelected,
    this.localMediaPaths = const {},
    this.localThumbnailPaths = const {},
  });

  final Chronique chronique;
  final VoidCallback? onTap;
  final ValueChanged<ChroniqueCardMenuAction>? onMenuSelected;
  final String? excerpt;
  final bool showFeedMedia;
  final bool showInactiveSocialActions;
  final ValueChanged<ChroniqueMedia>? onMediaSelected;
  final Map<int, String> localMediaPaths;
  final Map<int, String> localThumbnailPaths;

  @override
  State<ChroniqueCard> createState() => _ChroniqueCardState();
}

class _ChroniqueCardState extends State<ChroniqueCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final title = widget.chronique.title?.trim();
    final body = widget.excerpt ?? widget.chronique.body;
    final showMenu =
        widget.onMenuSelected != null && ChroniqueCardMenu.isAvailable(widget.chronique);
    final feedMedias =
        widget.showFeedMedia ? chroniqueFeedMediaItems(widget.chronique.media) : const <ChroniqueMedia>[];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: widget.onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _temporalLines(colors),
                  ),
                ),
              ),
              if (showMenu)
                ChroniqueCardMenu(
                  chronique: widget.chronique,
                  onSelected: widget.onMenuSelected!,
                ),
            ],
          ),
          GestureDetector(
            key: const ValueKey('chronique-card-copy'),
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null && title.isNotEmpty) ...[
                  Text(
                    title,
                    key: const ValueKey('chronique-card-title'),
                    style: AppTextTheme.titleSmall.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                _bodyBlock(colors, body),
              ],
            ),
          ),
          if (feedMedias.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ChroniqueFeedMediaBand(
              medias: feedMedias,
              localPaths: widget.localMediaPaths,
              localThumbnailPaths: widget.localThumbnailPaths,
              onSelect: widget.onMediaSelected,
            ),
          ],
          if (widget.showInactiveSocialActions) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                IconButton(
                  key: const ValueKey('chronique-share'),
                  tooltip: 'Partager',
                  onPressed: null,
                  icon: Icon(Icons.ios_share, color: colors.textSecondary),
                ),
                IconButton(
                  key: const ValueKey('chronique-like'),
                  tooltip: 'Aimer',
                  onPressed: null,
                  icon: Icon(Icons.favorite_border, color: colors.textSecondary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _bodyBlock(LuminaColors colors, String body) {
    final style = AppTextTheme.bodyLarge.copyWith(color: colors.textPrimary);
    if (widget.excerpt != null) {
      return Text(body, style: style);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final overflows = _exceedsSixLines(body, style, constraints.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              body,
              key: const ValueKey('chronique-card-body'),
              maxLines: _expanded ? null : 6,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: style,
            ),
            if (overflows) ...[
              const SizedBox(height: AppSpacing.xs),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                behavior: HitTestBehavior.opaque,
                child: Text(
                  _expanded ? 'Voir moins' : 'Voir plus',
                  key: const ValueKey('chronique-see-more'),
                  style: AppTextTheme.labelLarge.copyWith(color: colors.primary),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  bool _exceedsSixLines(String text, TextStyle style, double maxWidth) {
    if (maxWidth <= 0) {
      return false;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 6,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
  }

  List<Widget> _temporalLines(LuminaColors colors) {
    final style = AppTextTheme.labelSmall.copyWith(color: colors.textSecondary);
    if (widget.chronique.status == 'scheduled') {
      final when = formatOptionalChroniqueDate(widget.chronique.scheduledAt) ??
          chroniqueDateLabel(widget.chronique);
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
    final dateLabel = chroniqueDateLabel(widget.chronique);
    if (dateLabel.isNotEmpty) {
      lines.add(Text(dateLabel, style: style));
    }
    if (widget.chronique.status == 'active' &&
        widget.chronique.isTimeLimited &&
        widget.chronique.expiresAt != null) {
      if (lines.isNotEmpty) {
        lines.add(const SizedBox(height: AppSpacing.xs));
      }
      lines.add(Text('Expire le', style: style));
      lines.add(const SizedBox(height: AppSpacing.xs));
      lines.add(Text(ChroniqueDateHelper.formatLocal(widget.chronique.expiresAt!), style: style));
    }
    if (widget.chronique.status == 'expired') {
      if (lines.isNotEmpty) {
        lines.add(const SizedBox(height: AppSpacing.xs));
      }
      lines.add(Text('Expirée', style: style));
    }
    if (lines.isEmpty &&
        (widget.chronique.title == null || widget.chronique.title!.trim().isEmpty)) {
      lines.add(const SizedBox(height: AppSpacing.sm));
    } else if (lines.isNotEmpty) {
      lines.add(const SizedBox(height: AppSpacing.sm));
    }
    return lines;
  }
}
