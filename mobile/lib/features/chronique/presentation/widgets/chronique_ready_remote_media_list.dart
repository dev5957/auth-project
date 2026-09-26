import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../models/chronique.dart';
import 'chronique_ready_audio_list.dart';
import 'chronique_ready_document_list.dart';
import 'chronique_ready_image_list.dart';
import 'chronique_ready_video_list.dart';

List<ChroniqueMedia> displayableChroniqueRemoteMedia(Iterable<ChroniqueMedia> medias) {
  final items = [
    for (final media in medias)
      if (chroniqueMediaIsDisplayableImage(media) ||
          chroniqueMediaIsDisplayableVideo(media) ||
          chroniqueMediaIsDisplayableAudio(media) ||
          chroniqueMediaIsDisplayableDocument(media))
        media,
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

Widget _tileFor(ChroniqueMedia media, ChroniqueDocumentOpenHandler? openHandler) {
  if (chroniqueMediaIsDisplayableImage(media)) {
    return ChroniqueReadyImageList(medias: [media]);
  }
  if (chroniqueMediaIsDisplayableVideo(media)) {
    return ChroniqueReadyVideoList(medias: [media]);
  }
  if (chroniqueMediaIsDisplayableAudio(media)) {
    return ChroniqueReadyAudioList(medias: [media]);
  }
  if (chroniqueMediaIsDisplayableDocument(media)) {
    return ChroniqueReadyDocumentList(medias: [media], openHandler: openHandler);
  }
  return const SizedBox.shrink();
}

/// Médias distants `ready` (image + vidéo + audio + document) dans l’ordre `sort_order` global.
class ChroniqueReadyRemoteMediaList extends StatelessWidget {
  const ChroniqueReadyRemoteMediaList({
    super.key,
    required this.medias,
    this.openHandler,
  });

  final List<ChroniqueMedia> medias;
  final ChroniqueDocumentOpenHandler? openHandler;

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
          _tileFor(items[i], openHandler),
        ],
      ],
    );
  }
}
