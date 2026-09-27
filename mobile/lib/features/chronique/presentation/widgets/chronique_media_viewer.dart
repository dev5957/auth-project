import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../models/chronique.dart';
import 'chronique_feed_media.dart';
import 'chronique_ready_audio_list.dart';
import 'chronique_ready_document_list.dart';
import 'chronique_ready_video_list.dart';

Future<void> openChroniqueFeedMedia(
  BuildContext context,
  ChroniqueMedia media, {
  String? localPath,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => ChroniqueMediaViewerPage(
      media: media,
      localPath: localPath,
    ),
  );
}

/// Consultation média en fenêtre compacte, calée sur le contenu.
class ChroniqueMediaViewerPage extends StatelessWidget {
  const ChroniqueMediaViewerPage({
    super.key,
    required this.media,
    this.localPath,
  });

  final ChroniqueMedia media;
  final String? localPath;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final size = MediaQuery.sizeOf(context);
    final maxWidth = size.width * 0.92;
    final maxHeight = size.height * 0.78;
    return Dialog(
      key: const ValueKey('chronique-media-viewer-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: colors.bgSurface,
      child: ConstrainedBox(
        key: const ValueKey('chronique-media-viewer-sheet'),
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _title,
                      style: AppTextTheme.titleSmall.copyWith(color: colors.textPrimary),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('chronique-media-viewer-close'),
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: colors.textSecondary),
                  ),
                ],
              ),
              Flexible(
                fit: FlexFit.loose,
                child: _body(colors),
              ),
            ],
          ),
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

  bool get _hasLocalFile {
    final path = localPath?.trim();
    return path != null && path.isNotEmpty;
  }

  Widget _body(LuminaColors colors) {
    final usableRemote = chroniqueFeedHasUsableReadUrl(media);
    if (!usableRemote && !_hasLocalFile) {
      return Text(
        chroniqueFeedReadUrlExpired(media) ? 'Lien expiré' : 'Média indisponible',
        key: const ValueKey('chronique-media-viewer-unavailable'),
        textAlign: TextAlign.center,
        style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
      );
    }
    final url = media.readUrl?.trim() ?? '';
    final filePath = localPath?.trim() ?? '';
    return switch (media.kind) {
      'image' => LayoutBuilder(
          builder: (context, constraints) {
            final maxImageHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MediaQuery.sizeOf(context).height * 0.7;
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxImageHeight),
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: _hasLocalFile
                    ? Image.file(
                        File(filePath),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => _unavailable(colors),
                      )
                    : Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => _unavailable(colors),
                      ),
              ),
            );
          },
        ),
      'video' => KeyedSubtree(
          key: const ValueKey('chronique-media-viewer-video'),
          child: ChroniqueReadyVideoPlayer(
            url: _hasLocalFile ? filePath : url,
            fromFile: _hasLocalFile,
          ),
        ),
      'audio' => ChroniqueReadyAudioPlayer(
          key: const ValueKey('chronique-media-viewer-audio'),
          url: _hasLocalFile ? filePath : url,
          fromFile: _hasLocalFile,
        ),
      'document' => ChroniqueReadyDocumentCard(
          key: const ValueKey('chronique-media-viewer-document'),
          media: media,
          url: url.isEmpty ? (media.readUrl ?? '') : url,
          localPath: _hasLocalFile ? filePath : null,
        ),
      _ => _unavailable(colors),
    };
  }

  Widget _unavailable(LuminaColors colors) {
    return Text(
      'Média indisponible',
      key: const ValueKey('chronique-media-viewer-unavailable'),
      textAlign: TextAlign.center,
      style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
    );
  }
}
