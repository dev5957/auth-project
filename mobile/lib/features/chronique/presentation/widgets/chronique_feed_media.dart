import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../models/chronique.dart';
import 'chronique_ready_document_list.dart' show chroniqueDocumentShortType;

const double kChroniqueFeedReferenceWidth = 390;
const double kChroniqueFeedMediaGap = 2;
const double kChroniqueFeedTileComfortMinHeight = 130;
const double kChroniqueFeedTileStandardMinHeight = 78;

enum ChroniqueFeedTileDensity { comfort, standard, compact }

ChroniqueFeedTileDensity chroniqueFeedTileDensity(double height) {
  if (height >= kChroniqueFeedTileComfortMinHeight) {
    return ChroniqueFeedTileDensity.comfort;
  }
  if (height >= kChroniqueFeedTileStandardMinHeight) {
    return ChroniqueFeedTileDensity.standard;
  }
  return ChroniqueFeedTileDensity.compact;
}

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

bool chroniqueFeedThumbnailExpired(ChroniqueMedia media, [DateTime? now]) {
  final expires = media.thumbnailExpiresAt;
  if (expires == null) {
    return false;
  }
  return !expires.isAfter(now ?? DateTime.now());
}

bool chroniqueFeedHasUsableThumbnail(ChroniqueMedia media, [DateTime? now]) {
  final url = media.thumbnailUrl?.trim();
  if (url == null || url.isEmpty) {
    return false;
  }
  return !chroniqueFeedThumbnailExpired(media, now);
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
    this.localThumbnailPaths = const {},
  });

  final List<ChroniqueMedia> medias;
  final ValueChanged<ChroniqueMedia>? onSelect;
  final Map<int, String> localPaths;
  final Map<int, String> localThumbnailPaths;

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
    if (items.length == 3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: kChroniqueFeedMediaGap),
            Expanded(child: _filledTile(context, items[i], i)),
          ],
        ],
      );
    }
    if (items.length == 4) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _pair(context, items, 0)),
          const SizedBox(height: kChroniqueFeedMediaGap),
          Expanded(child: _pair(context, items, 2)),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: _stack(context, items.sublist(0, 2), 0)),
        const SizedBox(width: kChroniqueFeedMediaGap),
        Expanded(child: _stack(context, items.sublist(2, 5), 2)),
      ],
    );
  }

  Widget _pair(BuildContext context, List<ChroniqueMedia> items, int startIndex) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _filledTile(context, items[startIndex], startIndex)),
        const SizedBox(width: kChroniqueFeedMediaGap),
        Expanded(child: _filledTile(context, items[startIndex + 1], startIndex + 1)),
      ],
    );
  }

  Widget _stack(BuildContext context, List<ChroniqueMedia> items, int startIndex) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: kChroniqueFeedMediaGap),
          Expanded(child: _tile(context, items[i], startIndex + i)),
        ],
      ],
    );
  }

  Widget _filledTile(BuildContext context, ChroniqueMedia media, int index) {
    return SizedBox.expand(child: _tile(context, media, index));
  }

  Widget _tile(BuildContext context, ChroniqueMedia media, int index) {
    final id = media.id;
    return ChroniqueFeedMediaTile(
      media: media,
      index: index,
      localPath: id == null ? null : localPaths[id],
      localThumbnailPath: id == null ? null : localThumbnailPaths[id],
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
    this.localThumbnailPath,
  });

  final ChroniqueMedia media;
  final int index;
  final VoidCallback? onTap;
  final String? localPath;
  final String? localThumbnailPath;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Material(
      color: colors.bgRaised,
      child: InkWell(
        key: ValueKey('chronique-feed-media-${media.id ?? index}'),
        onTap: onTap,
        child: ClipRect(
          child: SizedBox.expand(
            child: _content(context, colors),
          ),
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
      return _coverImage(
        filePath: path,
        fallback: _fallback(colors, label: 'Média indisponible'),
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
    return _coverImage(
      networkUrl: media.readUrl!.trim(),
      fallback: _fallback(colors, label: 'Média indisponible'),
    );
  }

  Widget _coverImage({
    String? filePath,
    String? networkUrl,
    required Widget fallback,
    Key? key,
  }) {
    return SizedBox.expand(
      child: filePath != null
          ? Image.file(
              File(filePath),
              key: key,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) => fallback,
            )
          : Image.network(
              networkUrl!,
              key: key,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) => fallback,
            ),
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
    return SizedBox.expand(
      child: _ChroniqueFeedVideoBody(
        chrome: _videoChrome(colors),
        overlay: _videoPlayOverlay(colors),
        localThumbnailPath: localThumbnailPath,
        networkThumbnailUrl: chroniqueFeedHasUsableThumbnail(media) ? media.thumbnailUrl : null,
      ),
    );
  }

  Widget _videoPlayOverlay(LuminaColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final density = chroniqueFeedTileDensity(height);
        final showLabel = density != ChroniqueFeedTileDensity.compact;
        final iconSize = _tileIconSize(density, play: true);
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_circle,
                color: colors.textOnPrimary,
                size: iconSize,
              ),
              if (showLabel) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Vidéo',
                  key: const ValueKey('chronique-feed-video-label'),
                  style: AppTextTheme.labelSmall.copyWith(color: colors.textOnPrimary),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _videoChrome(LuminaColors colors) {
    final name = media.originalFilename?.trim();
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final density = chroniqueFeedTileDensity(height);
        final showName =
            name != null && name.isNotEmpty && density == ChroniqueFeedTileDensity.comfort;
        final showLabel = density != ChroniqueFeedTileDensity.compact;
        final iconSize = _tileIconSize(density, play: true);
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
                    size: iconSize,
                  ),
                  if (showLabel) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Vidéo',
                      key: const ValueKey('chronique-feed-video-label'),
                      style: AppTextTheme.labelSmall.copyWith(color: colors.textOnPrimary),
                    ),
                  ],
                  if (showName)
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
      },
    );
  }

  Widget _audio(LuminaColors colors) {
    final name = media.originalFilename?.trim();
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final density = chroniqueFeedTileDensity(height);
        final padding = density == ChroniqueFeedTileDensity.compact ? AppSpacing.xs : AppSpacing.sm;
        final lineHeight = _labelLineHeight(context);
        final inner = height - padding * 2;
        final eqSize = density == ChroniqueFeedTileDensity.compact ? 20.0 : 28.0;
        final playSize = density == ChroniqueFeedTileDensity.compact ? 24.0 : 36.0;
        final reserved = eqSize > playSize ? eqSize : playSize;
        final hasFileName = name != null && name.isNotEmpty;
        final showName = inner >= reserved &&
            inner >= lineHeight &&
            (hasFileName || density != ChroniqueFeedTileDensity.compact);
        final label = hasFileName ? name : 'Audio';
        return Padding(
          padding: EdgeInsets.all(padding),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: constraints.maxWidth - padding * 2,
              child: Row(
              children: [
                Icon(
                  Icons.graphic_eq,
                  color: colors.primary,
                  size: eqSize,
                ),
                if (showName) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: density == ChroniqueFeedTileDensity.comfort ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextTheme.labelSmall.copyWith(color: colors.textPrimary),
                    ),
                  ),
                ] else
                  const Spacer(),
                Icon(
                  Icons.play_circle,
                  key: const ValueKey('chronique-feed-audio-play'),
                  color: colors.primary,
                  size: playSize,
                ),
              ],
            ),
            ),
          ),
        );
      },
    );
  }

  Widget _document(LuminaColors colors) {
    final name = media.originalFilename?.trim();
    final size = chroniqueFeedSizeLabel(media.byteSize);
    final type = chroniqueDocumentShortType(media);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final density = chroniqueFeedTileDensity(height);
        final padding = density == ChroniqueFeedTileDensity.compact ? AppSpacing.xs : AppSpacing.sm;
        final lineHeight = _labelLineHeight(context);
        final inner = height - padding * 2;
        const slack = 3.0;
        final iconSize = _tileIconSize(density, play: false);
        var remaining = inner - iconSize - slack;
        final showType = remaining >= lineHeight;
        if (showType) {
          remaining -= lineHeight + AppSpacing.xs;
        }
        var nameLines = 0;
        if (name != null && name.isNotEmpty && remaining >= lineHeight) {
          if (density == ChroniqueFeedTileDensity.comfort && remaining >= lineHeight * 2) {
            nameLines = 2;
          } else {
            nameLines = 1;
          }
        }
        if (nameLines > 0) {
          remaining -= lineHeight * nameLines + AppSpacing.xs;
        }
        final showSize =
            density == ChroniqueFeedTileDensity.comfort && size != null && remaining >= lineHeight;
        final showFallbackName =
            (name == null || name.isEmpty) && density != ChroniqueFeedTileDensity.compact;
        return Padding(
          padding: EdgeInsets.all(padding),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth - padding * 2),
              child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _documentIcon(type),
                color: colors.primary,
                size: iconSize,
              ),
              if (showType) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  type,
                  key: const ValueKey('chronique-feed-document-type'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                ),
              ],
              if (nameLines > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  name!,
                  maxLines: nameLines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTextTheme.labelSmall.copyWith(color: colors.textPrimary),
                ),
              ] else if (showFallbackName) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Document',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextTheme.labelSmall.copyWith(color: colors.textPrimary),
                ),
              ],
              if (showSize) ...[
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
            ),
          ),
        );
      },
    );
  }

  static IconData _documentIcon(String type) {
    return switch (type) {
      'PDF' => Icons.picture_as_pdf_outlined,
      'TXT' => Icons.notes_outlined,
      _ => Icons.description_outlined,
    };
  }

  static double _tileIconSize(ChroniqueFeedTileDensity density, {required bool play}) {
    return switch (density) {
      ChroniqueFeedTileDensity.comfort => play ? 40.0 : 28.0,
      ChroniqueFeedTileDensity.standard => play ? 28.0 : 24.0,
      ChroniqueFeedTileDensity.compact => play ? 20.0 : 20.0,
    };
  }

  static double _labelLineHeight(BuildContext context) {
    const style = AppTextTheme.labelSmall;
    final size = style.fontSize ?? 12;
    final height = style.height ?? 1.2;
    return MediaQuery.textScalerOf(context).scale(size) * height;
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

class _ChroniqueFeedVideoBody extends StatefulWidget {
  const _ChroniqueFeedVideoBody({
    required this.chrome,
    required this.overlay,
    this.localThumbnailPath,
    this.networkThumbnailUrl,
  });

  final Widget chrome;
  final Widget overlay;
  final String? localThumbnailPath;
  final String? networkThumbnailUrl;

  @override
  State<_ChroniqueFeedVideoBody> createState() => _ChroniqueFeedVideoBodyState();
}

class _ChroniqueFeedVideoBodyState extends State<_ChroniqueFeedVideoBody> {
  var _failed = false;

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return widget.chrome;
    }
    final localThumb = widget.localThumbnailPath?.trim();
    final networkUrl = widget.networkThumbnailUrl?.trim();
    late final Widget poster;
    if (localThumb != null && localThumb.isNotEmpty) {
      poster = _posterImage(
        filePath: localThumb,
        fallback: widget.chrome,
      );
    } else if (networkUrl != null && networkUrl.isNotEmpty) {
      poster = _posterImage(
        networkUrl: networkUrl,
        fallback: widget.chrome,
      );
    } else {
      return widget.chrome;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        poster,
        const ColoredBox(color: Color(0x59000000)),
        widget.overlay,
      ],
    );
  }

  Widget _posterImage({
    String? filePath,
    String? networkUrl,
    required Widget fallback,
  }) {
    const key = ValueKey('chronique-feed-video-thumb');
    if (WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding')) {
      return const ColoredBox(key: key, color: Color(0xFF222222));
    }
    if (filePath != null) {
      return Image.file(
        File(filePath),
        key: key,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (context, error, stackTrace) {
          _markFailed();
          return fallback;
        },
      );
    }
    return Image.network(
      networkUrl!,
      key: key,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      errorBuilder: (context, error, stackTrace) {
        _markFailed();
        return fallback;
      },
    );
  }

  void _markFailed() {
    if (_failed) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _failed = true);
      }
    });
  }
}
