import '../models/media_draft.dart';

sealed class MediaPickResult {
  const MediaPickResult();
}

final class MediaPickCancelled extends MediaPickResult {
  const MediaPickCancelled();
}

final class MediaPickFailed extends MediaPickResult {
  const MediaPickFailed(this.message);

  final String message;
}

final class MediaPickSelected extends MediaPickResult {
  const MediaPickSelected({
    required this.kind,
    required this.sourceType,
    required this.fileName,
    required this.byteSize,
    required this.localPath,
    this.contentType,
    this.platformMime,
  });

  final MediaDraftKind kind;
  final MediaDraftSourceType sourceType;
  final String fileName;
  final int byteSize;
  final String localPath;
  final String? contentType;
  final String? platformMime;
}

/// Sélection locale téléphone. Pas d’upload, pas d’API.
abstract class ChroniqueLocalMediaPicker {
  Future<MediaPickResult> pickImage();

  Future<MediaPickResult> pickVideo();

  Future<MediaPickResult> pickAudio();

  Future<MediaPickResult> pickDocument();
}

const String kMediaInaccessibleMessage = 'Le fichier est inaccessible';
const String kMediaUnsupportedMessage = 'Ce type de fichier n\'est pas pris en charge';
