import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../models/chronique.dart';

bool chroniqueMediaIsDisplayableImage(ChroniqueMedia media) {
  if (media.kind != 'image') {
    return false;
  }
  if (media.status != 'ready') {
    return false;
  }
  final url = media.readUrl;
  return url != null && url.isNotEmpty;
}

List<ChroniqueMedia> displayableChroniqueImages(Iterable<ChroniqueMedia> medias) {
  final images = [
    for (final media in medias)
      if (chroniqueMediaIsDisplayableImage(media)) media,
  ];
  images.sort((a, b) {
    final order = (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0);
    if (order != 0) {
      return order;
    }
    return (a.id ?? 0).compareTo(b.id ?? 0);
  });
  return images;
}

/// Images `ready` avec `read_url`. Pas de GET Dio, pas de JWT vers R2.
class ChroniqueReadyImageList extends StatelessWidget {
  const ChroniqueReadyImageList({
    super.key,
    required this.medias,
  });

  final List<ChroniqueMedia> medias;

  @override
  Widget build(BuildContext context) {
    final images = displayableChroniqueImages(medias);
    if (images.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < images.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.lg),
          _ChroniqueNetworkImage(
            key: ValueKey('chronique-ready-image-${images[i].id ?? i}'),
            url: images[i].readUrl!,
          ),
        ],
      ],
    );
  }
}

class _ChroniqueNetworkImage extends StatelessWidget {
  const _ChroniqueNetworkImage({
    super.key,
    required this.url,
  });

  final String url;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.lg),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            return child;
          }
          return SizedBox(
            height: 180,
            child: Center(
              child: CircularProgressIndicator(
                color: colors.primary,
                strokeWidth: 2,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return SizedBox(
            height: 72,
            child: Center(
              child: Text(
                'Image indisponible',
                textAlign: TextAlign.center,
                style: AppTextTheme.labelSmall.copyWith(color: colors.danger),
              ),
            ),
          );
        },
      ),
    );
  }
}
