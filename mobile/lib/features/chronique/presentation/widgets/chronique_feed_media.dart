import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../models/chronique.dart';

const List<double> kChroniqueFeedAudioDecorHeights = [8, 14, 10, 16, 9, 12, 7, 11, 15, 8];

const double kChroniqueFeedReferenceWidth = 390;
const double kChroniqueFeedMediaGap = 2;

const Map<int, double> kChroniqueFeedMediaReferenceHeights = {
  2: 219,
  3: 260,
  4: 310,
  5: 360,
};

List<ChroniqueMedia> chroniqueFeedMediaItems(Iterable<ChroniqueMedia> medias) {
  final items = [
    for (final media in medias)
      if (media.status == null || media.status == 'ready') media,
  ];
  items.sort((a, b) {
    final order = (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0);
    if (order != 0) {
      return order;
    }
    return (a.id ?? 0).compareTo(b.id ?? 0);
  });
  if (items.length <= 5) {
    return items;
  }
  return items.sublist(0, 5);
}

double chroniqueFeedMediaBandHeight({
  required int count,
  required double width,
}) {
  if (count <= 0 || width <= 0) {
    return 0;
  }
  if (count == 1) {
    return width * 9 / 16;
  }
  final capped = count > 5 ? 5 : count;
  final reference = kChroniqueFeedMediaReferenceHeights[capped] ?? 360;
  return width * reference / kChroniqueFeedReferenceWidth;
}

bool chroniqueFeedReadUrlExpired(ChroniqueMedia media, [DateTime? now]) {
  final expires = media.readExpiresAt;
  if (expires == null) {
    return false;
  }
  return !expires.isAfter(now ?? DateTime.now());
}

bool chroniqueFeedHasUsableReadUrl(ChroniqueMedia media, [DateTime? now]) {
  final url = media.readUrl?.trim();
  if (url == null || url.isEmpty) {
    return false;
  }
  return !chroniqueFeedReadUrlExpired(media, now);
}

String? chroniqueFeedSizeLabel(int? byteSize) {
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

/// Mosaïque du fil. Ordre API conservé. Pas de scroll interne.
class ChroniqueFeedMediaBand extends StatelessWidget {
  const ChroniqueFeedMediaBand({
    super.key,
    required this.medias,
    this.onSelect,
    this.localPaths = const {},
  });

  final List<ChroniqueMedia> medias;
  final ValueChanged<ChroniqueMedia>? onSelect;
  final Map<int, String> localPaths;

  @override
  Widget build(BuildContext context) {
    final items = chroniqueFeedMediaItems(medias);
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = chroniqueFeedMediaBandHeight(count: items.length, width: width);
        return SizedBox(
          key: const ValueKey('chronique-feed-media-band'),
          width: width,
          height: height,
          child: _layout(context, items, width, height),
        );
      },
    );
  }

  Widget _layout(
    BuildContext context,
    List<ChroniqueMedia> items,
    double width,
    double height,
  ) {
    if (items.length == 1) {
      return _tile(context, items[0], 0);
    }
    if (items.length == 2) {
      return Row(
        children: [
          Expanded(child: _tile(context, items[0], 0)),
          const SizedBox(width: kChroniqueFeedMediaGap),
          Expanded(child: _tile(context, items[1], 1)),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: _tile(context, items[0], 0)),
        const SizedBox(width: kChroniqueFeedMediaGap),
        Expanded(
          child: Column(
            children: [
              for (var i = 1; i < items.length; i++) ...[
                if (i > 1) const SizedBox(height: kChroniqueFeedMediaGap),
                Expanded(child: _tile(context, items[i], i)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, ChroniqueMedia media, int index) {
    final id = media.id;
    return ChroniqueFeedMediaTile(
      media: media,
      index: index,
      localPath: id == null ? null : localPaths[id],
      onTap: onSelect == null ? null : () => onSelect!(media),
    );
  }
}

class ChroniqueFeedMediaTile extends StatelessWidget {
  const ChroniqueFeedMediaTile({
    super.key,
    required this.media,
    required this.index,
    this.onTap,
    this.localPath,
  });

  final ChroniqueMedia media;
  final int index;
  final VoidCallback? onTap;
  final String? localPath;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Material(
      color: colors.bgRaised,
      child: InkWell(
        key: ValueKey('chronique-feed-media-${media.id ?? index}'),
        onTap: onTap,
        child: ClipRect(
          child: _content(context, colors),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, LuminaColors colors) {
    switch (media.kind) {
      case 'image':
        return _image(colors);
      case 'video':
        return _video(colors);
      case 'audio':
        return _audio(colors);
      case 'document':
        return _document(colors);
      default:
        return _fallback(colors, label: 'Média');
    }
  }

  Widget _image(LuminaColors colors) {
    final path = localPath?.trim();
    if (path != null && path.isNotEmpty) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) {
          return _fallback(colors, label: 'Média indisponible');
        },
      );
    }
    if (!chroniqueFeedHasUsableReadUrl(media)) {
      return _fallback(
        colors,
        label: chroniqueFeedReadUrlExpired(media)
            ? 'Lien expiré'
            : 'Média indisponible',
      );
    }
    return Image.network(
      media.readUrl!.trim(),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) {
        return _fallback(colors, label: 'Média indisponible');
      },
    );
  }

  bool get _hasLocalFile {
    final path = localPath?.trim();
    return path != null && path.isNotEmpty;
  }

  Widget _video(LuminaColors colors) {
    if (!_hasLocalFile && !chroniqueFeedHasUsableReadUrl(media)) {
      return _fallback(
        colors,
        label: chroniqueFeedReadUrlExpired(media)
            ? 'Lien expiré'
            : 'Média indisponible',
      );
    }
    final name = media.originalFilename?.trim();
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: colors.bgRaised),
        const ColoredBox(color: Color(0x59000000)),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_circle,
                color: colors.textOnPrimary,
                size: 40,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Vidéo',
                key: const ValueKey('chronique-feed-video-label'),
                style: AppTextTheme.labelSmall.copyWith(color: colors.textOnPrimary),
              ),
              if (name != null && name.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 2, AppSpacing.sm, 0),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTextTheme.labelSmall.copyWith(color: colors.textOnPrimary),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _audio(LuminaColors colors) {
    final name = media.originalFilename?.trim();
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq, color: colors.primary, size: 28),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  (name == null || name.isEmpty) ? 'Audio' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextTheme.labelSmall.copyWith(color: colors.textPrimary),
                ),
              ),
              Icon(
                Icons.play_circle,
                color: colors.primary,
                size: 36,
              ),
            ],
          ),
          const Spacer(),
          ExcludeSemantics(
            child: SizedBox(
              height: 22,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final height in kChroniqueFeedAudioDecorHeights) ...[
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: SizedBox(height: height, width: double.infinity),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _document(LuminaColors colors) {
    final name = media.originalFilename?.trim();
    final size = chroniqueFeedSizeLabel(media.byteSize);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description_outlined, color: colors.primary),
          const SizedBox(height: AppSpacing.xs),
          Text(
            (name == null || name.isEmpty) ? 'Document' : name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTextTheme.labelSmall.copyWith(color: colors.textPrimary),
          ),
          if (size != null) ...[
            const SizedBox(height: 2),
            Text(
              size,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fallback(LuminaColors colors, {required String label}) {
    return ColoredBox(
      color: colors.bgRaised,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Text(
            label,
            key: const ValueKey('chronique-media-fallback'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}
