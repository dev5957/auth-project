/// Statut local d’un média du brouillon. Pas les statuts API.
enum MediaDraftStatus {
  selected,
  pending,
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

/// Média local avant tout appel API / R2.
class MediaDraft {
  const MediaDraft({
    required this.id,
    required this.kind,
    required this.sourceType,
    this.fileName,
    this.byteSize,
    this.localPath,
    this.status = MediaDraftStatus.selected,
  });

  final int id;
  final MediaDraftKind kind;
  final MediaDraftSourceType sourceType;
  final String? fileName;
  final int? byteSize;
  final String? localPath;
  final MediaDraftStatus status;

  static MediaDraftSourceType defaultSourceFor(MediaDraftKind kind) {
    return switch (kind) {
      MediaDraftKind.image => MediaDraftSourceType.gallery,
      MediaDraftKind.video => MediaDraftSourceType.gallery,
      MediaDraftKind.audio => MediaDraftSourceType.upload,
      MediaDraftKind.document => MediaDraftSourceType.upload,
    };
  }
}
