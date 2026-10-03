import '../models/chronique.dart';
import '../models/media_draft.dart';
import 'chronique_media_mime.dart';

const String kChroniqueDocsCacheFolder = 'chronique_docs';
const Duration kChroniqueDocsCacheMaxAge = Duration(hours: 6);

const String kChroniqueDocumentPreparingMessage = 'Préparation du document…';
const String kChroniqueDocumentRetrieveFailedMessage = 'Impossible de récupérer le document.';
const String kChroniqueDocumentOpenFailedMessage = 'Impossible d\'ouvrir le document.';
const String kChroniqueDocumentFallbackName = 'Document';

const _allowedExtensions = {'pdf', 'doc', 'docx', 'txt'};

String? chroniqueDocumentMime(ChroniqueMedia media) {
  final fromType = normalizeChroniqueContentType(media.contentType);
  if (fromType != null &&
      kChroniqueMimeByKind[MediaDraftKind.document]!.contains(fromType)) {
    return fromType;
  }
  return resolveChroniqueMediaContentType(
    kind: MediaDraftKind.document,
    fileName: media.originalFilename,
  );
}

String chroniqueDocumentFileExtension(ChroniqueMedia media) {
  switch (chroniqueDocumentMime(media)) {
    case 'application/pdf':
      return 'pdf';
    case 'application/msword':
      return 'doc';
    case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
      return 'docx';
    case 'text/plain':
      return 'txt';
  }
  final fromName = extensionOfFileName(media.originalFilename);
  if (fromName != null && _allowedExtensions.contains(fromName)) {
    return fromName;
  }
  return 'pdf';
}

/// Un seul segment, extension allowlistée. Jamais `storage_key`.
String sanitizeChroniqueDocumentBaseName(String? originalFilename, String extension) {
  final ext = extension.toLowerCase();
  var raw = (originalFilename ?? '').trim().replaceAll('\\', '/');
  if (raw.contains('/')) {
    final parts = raw.split('/').where((part) => part.isNotEmpty);
    raw = parts.isEmpty ? '' : parts.last;
  }
  raw = raw.replaceAll('..', '');
  final buffer = StringBuffer();
  for (final unit in raw.codeUnits) {
    final char = String.fromCharCode(unit);
    if (RegExp(r'[A-Za-z0-9._-]').hasMatch(char)) {
      buffer.write(char);
    } else if (char == ' ') {
      buffer.write('_');
    }
  }
  var safe = buffer.toString();
  while (safe.contains('..')) {
    safe = safe.replaceAll('..', '');
  }
  if (safe.startsWith('.')) {
    safe = safe.substring(1);
  }
  if (safe.toLowerCase().endsWith('.$ext')) {
    safe = safe.substring(0, safe.length - ext.length - 1);
  } else {
    final dot = safe.lastIndexOf('.');
    if (dot > 0) {
      safe = safe.substring(0, dot);
    }
  }
  if (safe.isEmpty) {
    safe = 'document';
  }
  return '$safe.$ext';
}

String chroniqueDocumentCacheFileName(ChroniqueMedia media) {
  final extension = chroniqueDocumentFileExtension(media);
  final base = sanitizeChroniqueDocumentBaseName(media.originalFilename, extension);
  final id = media.id ?? 0;
  return '${id}_$base';
}

bool chroniqueDocumentPathIsInside(String directoryPath, String filePath) {
  final root = directoryPath.replaceAll('\\', '/');
  final file = filePath.replaceAll('\\', '/');
  final prefix = root.endsWith('/') ? root : '$root/';
  return file == root || file.startsWith(prefix);
}
