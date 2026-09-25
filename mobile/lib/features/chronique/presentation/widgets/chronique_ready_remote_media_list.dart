import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../models/chronique.dart';
import 'chronique_ready_image_list.dart';
import 'chronique_ready_video_list.dart';

List<ChroniqueMedia> displayableChroniqueRemoteMedia(Iterable<ChroniqueMedia> medias) {
  final items = [
    for (final media in medias)
      if (chroniqueMediaIsDisplayableImage(media) || chroniqueMediaIsDisplayableVideo(media)) media,
  ];
  items.sort((a, b) {
    final order = (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0);
    if (order != 0) {
      return order;
    }
    return (a.id ?? 0).compareTo(b.id ?? 0);
  });
  return items;
}

/// Médias distants `ready` (image + vidéo) dans l’ordre `sort_order` global.
class ChroniqueReadyRemoteMediaList extends StatelessWidget {
  const ChroniqueReadyRemoteMediaList({
    super.key,
    required this.medias,
  });

  final List<ChroniqueMedia> medias;

  @override
  Widget build(BuildContext context) {
    final items = displayableChroniqueRemoteMedia(medias);
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.lg),
          if (chroniqueMediaIsDisplayableImage(items[i]))
            ChroniqueReadyImageList(medias: [items[i]])
          else
            ChroniqueReadyVideoList(medias: [items[i]]),
        ],
      ],
    );
  }
}
