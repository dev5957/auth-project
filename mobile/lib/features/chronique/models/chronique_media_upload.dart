import 'chronique.dart';

/// Réponse `POST /chroniques/:id/media/uploads` (métadonnées + URL signée).
class ChroniqueMediaUploadSession {
  const ChroniqueMediaUploadSession({
    required this.media,
    required this.method,
    required this.url,
    required this.headers,
    this.expiresAt,
    this.thumbnailMethod,
    this.thumbnailUrl,
    this.thumbnailHeaders,
    this.thumbnailExpiresAt,
  });

  final ChroniqueMedia media;
  final String method;
  final String url;
  final Map<String, String> headers;
  final String? expiresAt;
  final String? thumbnailMethod;
  final String? thumbnailUrl;
  final Map<String, String>? thumbnailHeaders;
  final String? thumbnailExpiresAt;

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
    final thumbRaw = json['thumbnail_upload'];
    String? thumbMethod;
    String? thumbUrl;
    Map<String, String>? thumbHeaders;
    String? thumbExpires;
    if (thumbRaw is Map) {
      final methodValue = thumbRaw['method'];
      final urlValue = thumbRaw['url'];
      if (methodValue is String &&
          methodValue.trim().isNotEmpty &&
          urlValue is String &&
          urlValue.trim().isNotEmpty) {
        thumbMethod = methodValue.trim();
        thumbUrl = urlValue.trim();
        thumbHeaders = <String, String>{};
        final headersRawThumb = thumbRaw['headers'];
        if (headersRawThumb is Map) {
          for (final entry in headersRawThumb.entries) {
            thumbHeaders['${entry.key}'] = '${entry.value}';
          }
        }
        final thumbExp = thumbRaw['expires_at'];
        thumbExpires = thumbExp is String ? thumbExp : null;
      }
    }
    return ChroniqueMediaUploadSession(
      media: media,
      method: methodRaw.trim(),
      url: urlRaw.trim(),
      headers: headers,
      expiresAt: expires is String ? expires : null,
      thumbnailMethod: thumbMethod,
      thumbnailUrl: thumbUrl,
      thumbnailHeaders: thumbHeaders,
      thumbnailExpiresAt: thumbExpires,
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
    this.thumbnailMethod,
    this.thumbnailUrl,
    this.thumbnailHeaders,
    this.thumbnailExpiresAt,
    this.thumbnailPutCompleted = false,
  });

  final int mediaId;
  final String method;
  final String url;
  final Map<String, String> headers;
  final String? expiresAt;
  final bool putCompleted;
  final String? thumbnailMethod;
  final String? thumbnailUrl;
  final Map<String, String>? thumbnailHeaders;
  final String? thumbnailExpiresAt;
  final bool thumbnailPutCompleted;

  MediaDraftRemoteUpload copyWith({
    bool? putCompleted,
    bool? thumbnailPutCompleted,
  }) {
    return MediaDraftRemoteUpload(
      mediaId: mediaId,
      method: method,
      url: url,
      headers: headers,
      expiresAt: expiresAt,
      putCompleted: putCompleted ?? this.putCompleted,
      thumbnailMethod: thumbnailMethod,
      thumbnailUrl: thumbnailUrl,
      thumbnailHeaders: thumbnailHeaders,
      thumbnailExpiresAt: thumbnailExpiresAt,
      thumbnailPutCompleted: thumbnailPutCompleted ?? this.thumbnailPutCompleted,
    );
  }
}
