import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../media/chronique_media_mime.dart';
import '../../models/chronique.dart';

typedef ChroniqueDocumentOpener = Future<bool> Function(Uri uri);

const String kChroniqueDocumentOpenFailedMessage = 'Impossible d\'ouvrir le document.';
const String kChroniqueDocumentFallbackName = 'Document';

bool chroniqueMediaIsDisplayableDocument(ChroniqueMedia media) {
  if (media.kind != 'document') {
    return false;
  }
  if (media.status != 'ready') {
    return false;
  }
  final url = media.readUrl;
  return url != null && url.trim().isNotEmpty;
}

List<ChroniqueMedia> displayableChroniqueDocuments(Iterable<ChroniqueMedia> medias) {
  final documents = [
    for (final media in medias)
      if (chroniqueMediaIsDisplayableDocument(media)) media,
  ];
  documents.sort((a, b) {
    final order = (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0);
    if (order != 0) {
      return order;
    }
    return (a.id ?? 0).compareTo(b.id ?? 0);
  });
  return documents;
}

String chroniqueDocumentDisplayName(ChroniqueMedia media) {
  final name = media.originalFilename?.trim();
  if (name == null || name.isEmpty) {
    return kChroniqueDocumentFallbackName;
  }
  return name;
}

String chroniqueDocumentShortType(ChroniqueMedia media) {
  final mime = normalizeChroniqueContentType(media.contentType);
  final fromMime = _shortTypeForMime(mime);
  if (fromMime != null) {
    return fromMime;
  }
  return _shortTypeForExtension(extensionOfFileName(media.originalFilename)) ??
      kChroniqueDocumentFallbackName;
}

String? _shortTypeForMime(String? mime) {
  switch (mime) {
    case 'application/pdf':
      return 'PDF';
    case 'application/msword':
      return 'DOC';
    case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
      return 'DOCX';
    case 'text/plain':
      return 'TXT';
    default:
      return null;
  }
}

String? _shortTypeForExtension(String? extension) {
  switch (extension) {
    case 'pdf':
      return 'PDF';
    case 'doc':
      return 'DOC';
    case 'docx':
      return 'DOCX';
    case 'txt':
      return 'TXT';
    default:
      return null;
  }
}

Future<bool> openChroniqueDocumentReadUrl(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Documents `ready` avec `read_url`. Ouverture externe, sans JWT.
class ChroniqueReadyDocumentList extends StatelessWidget {
  const ChroniqueReadyDocumentList({
    super.key,
    required this.medias,
    this.openDocument,
  });

  final List<ChroniqueMedia> medias;
  final ChroniqueDocumentOpener? openDocument;

  @override
  Widget build(BuildContext context) {
    final documents = displayableChroniqueDocuments(medias);
    if (documents.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < documents.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.lg),
          ChroniqueReadyDocumentCard(
            key: ValueKey('chronique-ready-document-${documents[i].id ?? i}'),
            media: documents[i],
            url: documents[i].readUrl!,
            openDocument: openDocument,
          ),
        ],
      ],
    );
  }
}

class ChroniqueReadyDocumentCard extends StatelessWidget {
  const ChroniqueReadyDocumentCard({
    super.key,
    required this.media,
    required this.url,
    this.openDocument,
  });

  final ChroniqueMedia media;
  final String url;
  final ChroniqueDocumentOpener? openDocument;

  Future<void> _open(BuildContext context) async {
    try {
      final opener = openDocument ?? openChroniqueDocumentReadUrl;
      final opened = await opener(Uri.parse(url));
      if (!opened && context.mounted) {
        _showOpenFailed(context);
      }
    } catch (_) {
      if (context.mounted) {
        _showOpenFailed(context);
      }
    }
  }

  void _showOpenFailed(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text(kChroniqueDocumentOpenFailedMessage)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgRaised,
        borderRadius: BorderRadius.circular(AppSpacing.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.description_outlined, color: colors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chroniqueDocumentDisplayName(media),
                    key: ValueKey('chronique-document-name-$url'),
                    style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    chroniqueDocumentShortType(media),
                    key: ValueKey('chronique-document-type-$url'),
                    style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            TextButton(
              key: ValueKey('chronique-document-open-$url'),
              onPressed: () => _open(context),
              child: const Text('Ouvrir'),
            ),
          ],
        ),
      ),
    );
  }
}
