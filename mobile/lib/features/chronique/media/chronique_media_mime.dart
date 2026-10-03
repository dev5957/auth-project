import '../models/media_draft.dart';

/// MIME V1 identiques au backend (`MIME_BY_KIND`). Pas d’invention hors allowlist.
const Map<MediaDraftKind, Set<String>> kChroniqueMimeByKind = {
  MediaDraftKind.image: {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
  },
  MediaDraftKind.video: {
    'video/mp4',
    'video/quicktime',
    'video/webm',
  },
  MediaDraftKind.audio: {
    'audio/mpeg',
    'audio/mp4',
    'audio/wav',
    'audio/ogg',
  },
  MediaDraftKind.document: {
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'text/plain',
  },
};

const Map<String, String> _extensionToMime = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  'mp3': 'audio/mpeg',
  'mpeg': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'txt': 'text/plain',
};

/// Alias plateforme → type backend, uniquement pour des équivalents connus.
const Map<String, String> _mimeAliases = {
  'image/jpg': 'image/jpeg',
};

bool isChroniqueContentTypeAllowed(MediaDraftKind kind, String? contentType) {
  final normalized = normalizeChroniqueContentType(contentType);
  if (normalized == null) {
    return false;
  }
  return kChroniqueMimeByKind[kind]!.contains(normalized);
}

String? normalizeChroniqueContentType(String? raw) {
  if (raw == null) {
    return null;
  }
  final trimmed = raw.trim().toLowerCase();
  if (trimmed.isEmpty) {
    return null;
  }
  return _mimeAliases[trimmed] ?? trimmed;
}

String? extensionOfFileName(String? fileName) {
  if (fileName == null) {
    return null;
  }
  final trimmed = fileName.trim();
  final slash = trimmed.replaceAll('\\', '/').split('/').last;
  final dot = slash.lastIndexOf('.');
  if (dot < 0 || dot == slash.length - 1) {
    return null;
  }
  return slash.substring(dot + 1).toLowerCase();
}

/// Déduit un MIME allowlisté. `platformMime` (image_picker / file_picker) est préféré s’il est reconnu.
String? resolveChroniqueMediaContentType({
  required MediaDraftKind kind,
  String? fileName,
  String? localPath,
  String? platformMime,
}) {
  final allowed = kChroniqueMimeByKind[kind]!;
  final fromPlatform = normalizeChroniqueContentType(platformMime);
  if (fromPlatform != null) {
    if (allowed.contains(fromPlatform)) {
      return fromPlatform;
    }
    if (fromPlatform != 'application/octet-stream') {
      return null;
    }
  }

  final ext = extensionOfFileName(fileName) ?? extensionOfFileName(localPath);
  if (ext == null) {
    return null;
  }
  final mapped = _extensionToMime[ext];
  if (mapped == null || !allowed.contains(mapped)) {
    return null;
  }
  return mapped;
}
