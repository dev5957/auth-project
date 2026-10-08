import 'package:flutter/material.dart';

import '../../models/chronique.dart';
import '../../models/chronique_fields.dart';
import '../../models/chronique_schedule_draft.dart';
import '../../models/media_draft.dart';
import 'chronique_card.dart';
import 'chronique_media_viewer.dart';

List<ChroniqueMedia> chroniquePreviewMediaFromDrafts(List<MediaDraft> drafts) {
  final capped = drafts.length > 5 ? drafts.sublist(0, 5) : drafts;
  return [
    for (var i = 0; i < capped.length; i++)
      ChroniqueMedia(
        id: capped[i].id,
        kind: capped[i].kind.name,
        status: 'ready',
        originalFilename: capped[i].fileName,
        byteSize: capped[i].byteSize,
        contentType: capped[i].contentType,
        sortOrder: i,
      ),
  ];
}

Map<int, String> chroniquePreviewLocalPaths(List<MediaDraft> drafts) {
  return {
    for (final draft in drafts)
      if (draft.localPath != null && draft.localPath!.trim().isNotEmpty)
        draft.id: draft.localPath!.trim(),
  };
}

Map<int, String> chroniquePreviewLocalThumbnails(List<MediaDraft> drafts) {
  return {
    for (final draft in drafts)
      if (draft.localThumbnailPath != null && draft.localThumbnailPath!.trim().isNotEmpty)
        draft.id: draft.localThumbnailPath!.trim(),
  };
}

/// Prévisualisation identique à une carte du fil. Aucun GET.
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
    final trimmedTitle = ChroniqueFields.trimmedTitle(title);
    final trimmedBody = ChroniqueFields.trimmedBody(body);
    final previewMedias = chroniquePreviewMediaFromDrafts(medias);
    final localPaths = chroniquePreviewLocalPaths(medias);
    final localThumbnails = chroniquePreviewLocalThumbnails(medias);
    final scheduled = schedule.publishMode == ChroniquePublishMode.schedule;
    final expires = schedule.resolvedExpiresLocal();
    return ChroniqueCard(
      key: const ValueKey('chronique-preview-card'),
      chronique: Chronique(
        id: 0,
        title: trimmedTitle,
        body: trimmedBody,
        status: scheduled ? 'scheduled' : 'active',
        scheduledAt: scheduled ? schedule.scheduledAt : null,
        isTimeLimited: schedule.apiIsTimeLimited,
        expiresAt: expires,
        media: previewMedias,
      ),
      showFeedMedia: true,
      showInactiveSocialActions: false,
      localMediaPaths: localPaths,
      localThumbnailPaths: localThumbnails,
      onMediaSelected: (media) => openChroniqueFeedMedia(
        context,
        media,
        localPath: media.id == null ? null : localPaths[media.id],
      ),
    );
  }
}
