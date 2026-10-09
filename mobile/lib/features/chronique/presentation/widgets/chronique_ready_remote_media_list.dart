import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../models/chronique.dart';
import 'chronique_ready_audio_list.dart';
import 'chronique_ready_document_list.dart';
import 'chronique_ready_image_list.dart';
import 'chronique_ready_video_list.dart';

int _mediaSort(ChroniqueMedia a, ChroniqueMedia b) {
  final order = (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0);
  if (order != 0) {
    return order;
  }
  return (a.id ?? 0).compareTo(b.id ?? 0);
}

List<ChroniqueMedia> displayableChroniqueRemoteMedia(Iterable<ChroniqueMedia> medias) {
  final items = [
    for (final media in medias)
      if (chroniqueMediaIsDisplayableImage(media) ||
          chroniqueMediaIsDisplayableVideo(media) ||
          chroniqueMediaIsDisplayableAudio(media) ||
          chroniqueMediaIsDisplayableDocument(media))
        media,
  ];
  items.sort(_mediaSort);
  return items;
}

/// Médias `ready` avec id, ordre API (`sort_order`, puis `id`).
List<ChroniqueMedia> readyChroniqueMedia(Iterable<ChroniqueMedia> medias) {
  final items = [
    for (final media in medias)
      if (media.status == 'ready' && media.id != null) media,
  ];
  items.sort(_mediaSort);
  return items;
}

/// Compteur quota UX : `pending_upload` + `ready` (plafond 5 inchangé).
int chroniqueQuotaMediaCount(Iterable<ChroniqueMedia> medias) {
  var count = 0;
  for (final media in medias) {
    if (media.status == 'ready' || media.status == 'pending_upload') {
      count += 1;
    }
  }
  return count;
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
