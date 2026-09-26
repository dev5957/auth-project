import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../media/chronique_document_file.dart';
import '../../media/chronique_media_mime.dart';
import '../../models/chronique.dart';
import '../../services/chronique_document_open_service.dart';

export '../../media/chronique_document_file.dart' show
    kChroniqueDocumentFallbackName,
    kChroniqueDocumentOpenFailedMessage,
    kChroniqueDocumentPreparingMessage,
    kChroniqueDocumentRetrieveFailedMessage;
export '../../services/chronique_document_open_service.dart' show
    ChroniqueDocumentOpenHandler,
    ChroniqueDocumentOpenOutcome,
    ChroniqueDocumentOpenService;

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

/// Documents `ready` avec `read_url`. GET R2 puis ouverture locale, sans JWT.
class ChroniqueReadyDocumentList extends StatelessWidget {
  const ChroniqueReadyDocumentList({
    super.key,
    required this.medias,
    this.openHandler,
    this.openService,
  });

  final List<ChroniqueMedia> medias;
  final ChroniqueDocumentOpenHandler? openHandler;
  final ChroniqueDocumentOpenService? openService;

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
            openHandler: openHandler,
            openService: openService,
          ),
        ],
      ],
    );
  }
}

class ChroniqueReadyDocumentCard extends StatefulWidget {
  const ChroniqueReadyDocumentCard({
    super.key,
    required this.media,
    required this.url,
    this.openHandler,
    this.openService,
  });

  final ChroniqueMedia media;
  final String url;
  final ChroniqueDocumentOpenHandler? openHandler;
  final ChroniqueDocumentOpenService? openService;

  @override
  State<ChroniqueReadyDocumentCard> createState() => _ChroniqueReadyDocumentCardState();
}

class _ChroniqueReadyDocumentCardState extends State<ChroniqueReadyDocumentCard> {
  static final _fallbackOpenService = ChroniqueDocumentOpenService();
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
        final handler = widget.openHandler ??
            widget.openService?.open ??
            _fallbackOpenService.open;
      final outcome = await handler(widget.media);
      if (!mounted) {
        return;
      }
      switch (outcome) {
        case ChroniqueDocumentOpenOutcome.opened:
          break;
        case ChroniqueDocumentOpenOutcome.retrieveFailed:
          _showMessage(kChroniqueDocumentRetrieveFailedMessage);
        case ChroniqueDocumentOpenOutcome.openFailed:
          _showMessage(kChroniqueDocumentOpenFailedMessage);
      }
    } catch (_) {
      if (mounted) {
        _showMessage(kChroniqueDocumentOpenFailedMessage);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
                    chroniqueDocumentDisplayName(widget.media),
                    key: ValueKey('chronique-document-name-${widget.url}'),
                    style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    chroniqueDocumentShortType(widget.media),
                    key: ValueKey('chronique-document-type-${widget.url}'),
                    style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            if (_busy)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  kChroniqueDocumentPreparingMessage,
                  key: const ValueKey('chronique-document-preparing'),
                  style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                ),
              )
            else
              TextButton(
                key: ValueKey('chronique-document-open-${widget.url}'),
                onPressed: _open,
                child: const Text('Ouvrir'),
              ),
          ],
        ),
      ),
    );
  }
}
