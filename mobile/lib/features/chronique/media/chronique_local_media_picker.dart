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

/// Plusieurs fichiers issus d’une même ouverture du sélecteur.
final class MediaPickMany extends MediaPickResult {
  const MediaPickMany(this.items);

  final List<MediaPickSelected> items;
}

/// Sélection locale téléphone. Pas d’upload, pas d’API.
abstract class ChroniqueLocalMediaPicker {
  Future<MediaPickResult> pickImage({int? limit});

  Future<MediaPickResult> pickImageFromCamera();

  Future<MediaPickResult> pickVideo({int? limit});

  Future<MediaPickResult> pickVideoFromCamera();

  Future<MediaPickResult> pickAudio();

  Future<MediaPickResult> pickDocument({int? limit});
}

const String kMediaInaccessibleMessage = 'Le fichier est inaccessible';
const String kMediaUnsupportedMessage = 'Ce type de fichier n\'est pas pris en charge';
const String kCameraAccessDeniedMessage = 'Impossible d\'accéder à l\'appareil photo.';
const String kMicrophoneAccessDeniedMessage =
    'Impossible d\'accéder au microphone.';
