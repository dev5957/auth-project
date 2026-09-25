import 'chronique_media_upload.dart';

/// Statut local d’un média du brouillon. Pas les statuts API (`pending_upload` / `ready`).
enum MediaDraftStatus {
  selected,
  uploading,
  uploaded,
  failed,
}

enum MediaDraftKind {
  image,
  video,
  audio,
  document,
}

enum MediaDraftSourceType {
  camera,
  gallery,
  microphone,
  upload,
}

/// Média local avant / pendant l’upload R2.
class MediaDraft {
  const MediaDraft({
    required this.id,
    required this.kind,
    required this.sourceType,
    this.fileName,
    this.byteSize,
    this.localPath,
    this.contentType,
    this.status = MediaDraftStatus.selected,
    this.uploadProgress = 0,
    this.errorMessage,
    this.remoteUpload,
  });

  final int id;
  final MediaDraftKind kind;
  final MediaDraftSourceType sourceType;
  final String? fileName;
  final int? byteSize;
  final String? localPath;
  final String? contentType;
  final MediaDraftStatus status;
  final int uploadProgress;
  final String? errorMessage;
  final MediaDraftRemoteUpload? remoteUpload;

  bool get needsUpload =>
      status == MediaDraftStatus.selected || status == MediaDraftStatus.failed;

  bool get isUploaded => status == MediaDraftStatus.uploaded;

  MediaDraft copyWith({
    MediaDraftKind? kind,
    MediaDraftSourceType? sourceType,
    String? fileName,
    int? byteSize,
    String? localPath,
    String? contentType,
    MediaDraftStatus? status,
    int? uploadProgress,
    String? errorMessage,
    MediaDraftRemoteUpload? remoteUpload,
    bool clearError = false,
    bool clearRemoteUpload = false,
  }) {
    return MediaDraft(
      id: id,
      kind: kind ?? this.kind,
      sourceType: sourceType ?? this.sourceType,
      fileName: fileName ?? this.fileName,
      byteSize: byteSize ?? this.byteSize,
      localPath: localPath ?? this.localPath,
      contentType: contentType ?? this.contentType,
      status: status ?? this.status,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      remoteUpload: clearRemoteUpload ? null : (remoteUpload ?? this.remoteUpload),
    );
  }

  static MediaDraftSourceType defaultSourceFor(MediaDraftKind kind) {
    return switch (kind) {
      MediaDraftKind.image => MediaDraftSourceType.gallery,
      MediaDraftKind.video => MediaDraftSourceType.gallery,
      MediaDraftKind.audio => MediaDraftSourceType.upload,
      MediaDraftKind.document => MediaDraftSourceType.upload,
    };
  }
}
