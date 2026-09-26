import 'chronique.dart';

/// Réponse `POST /chroniques/:id/media/uploads` (métadonnées + URL signée).
class ChroniqueMediaUploadSession {
  const ChroniqueMediaUploadSession({
    required this.media,
    required this.method,
    required this.url,
    required this.headers,
    this.expiresAt,
  });

  final ChroniqueMedia media;
  final String method;
  final String url;
  final Map<String, String> headers;
  final String? expiresAt;

  factory ChroniqueMediaUploadSession.fromJson(Map<String, dynamic> json) {
    final mediaRaw = json['media'];
    final uploadRaw = json['upload'];
    if (mediaRaw is! Map || uploadRaw is! Map) {
      throw const FormatException('Invalid media upload payload');
    }
    final media = ChroniqueMedia.fromJson(Map<String, dynamic>.from(mediaRaw));
    if (media.id == null) {
      throw const FormatException('Invalid media upload payload');
    }
    final methodRaw = uploadRaw['method'];
    final urlRaw = uploadRaw['url'];
    if (methodRaw is! String || methodRaw.trim().isEmpty) {
      throw const FormatException('Invalid media upload payload');
    }
    if (urlRaw is! String || urlRaw.trim().isEmpty) {
      throw const FormatException('Invalid media upload payload');
    }
    final headers = <String, String>{};
    final headersRaw = uploadRaw['headers'];
    if (headersRaw is Map) {
      for (final entry in headersRaw.entries) {
        headers['${entry.key}'] = '${entry.value}';
      }
    }
    final expires = uploadRaw['expires_at'];
    return ChroniqueMediaUploadSession(
      media: media,
      method: methodRaw.trim(),
      url: urlRaw.trim(),
      headers: headers,
      expiresAt: expires is String ? expires : null,
    );
  }
}

/// Cible PUT R2 conservée sur le [MediaDraft] le temps de l’envoi.
class MediaDraftRemoteUpload {
  const MediaDraftRemoteUpload({
    required this.mediaId,
    required this.method,
    required this.url,
    required this.headers,
    this.expiresAt,
    this.putCompleted = false,
  });

  final int mediaId;
  final String method;
  final String url;
  final Map<String, String> headers;
  final String? expiresAt;
  final bool putCompleted;

  MediaDraftRemoteUpload copyWith({
    bool? putCompleted,
  }) {
    return MediaDraftRemoteUpload(
      mediaId: mediaId,
      method: method,
      url: url,
      headers: headers,
      expiresAt: expiresAt,
      putCompleted: putCompleted ?? this.putCompleted,
    );
  }
}
