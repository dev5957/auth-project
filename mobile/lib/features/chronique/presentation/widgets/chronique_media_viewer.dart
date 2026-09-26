import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../models/chronique.dart';
import 'chronique_feed_media.dart';
import 'chronique_ready_audio_list.dart';
import 'chronique_ready_document_list.dart';
import 'chronique_ready_video_list.dart';

Future<void> openChroniqueFeedMedia(BuildContext context, ChroniqueMedia media) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => ChroniqueMediaViewerPage(media: media),
    ),
  );
}

/// Lecture directe d’un média du fil. Réutilise les lecteurs ready existants.
class ChroniqueMediaViewerPage extends StatelessWidget {
  const ChroniqueMediaViewerPage({
    super.key,
    required this.media,
  });

  final ChroniqueMedia media;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        title: Text(
          _title,
          style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: _body(colors),
        ),
      ),
    );
  }

  String get _title {
    return switch (media.kind) {
      'image' => 'Image',
      'video' => 'Vidéo',
      'audio' => 'Audio',
      'document' => 'Document',
      _ => 'Média',
    };
  }

  Widget _body(LuminaColors colors) {
    if (!chroniqueFeedHasUsableReadUrl(media) && media.kind != 'document') {
      return Center(
        child: Text(
          chroniqueFeedReadUrlExpired(media) ? 'Lien expiré' : 'Média indisponible',
          key: const ValueKey('chronique-media-viewer-unavailable'),
          textAlign: TextAlign.center,
          style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
        ),
      );
    }
    final url = media.readUrl?.trim() ?? '';
    return switch (media.kind) {
      'image' => Center(
          child: InteractiveViewer(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Text(
                  'Média indisponible',
                  key: const ValueKey('chronique-media-viewer-unavailable'),
                  textAlign: TextAlign.center,
                  style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                );
              },
            ),
          ),
        ),
      'video' => Center(
          child: KeyedSubtree(
            key: const ValueKey('chronique-media-viewer-video'),
            child: ChroniqueReadyVideoPlayer(url: url),
          ),
        ),
      'audio' => ChroniqueReadyAudioPlayer(
          key: const ValueKey('chronique-media-viewer-audio'),
          url: url,
        ),
      'document' => ChroniqueReadyDocumentCard(
          key: const ValueKey('chronique-media-viewer-document'),
          media: media,
          url: url.isEmpty ? (media.readUrl ?? '') : url,
        ),
      _ => Center(
          child: Text(
            'Média indisponible',
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
          ),
        ),
    };
  }
}
