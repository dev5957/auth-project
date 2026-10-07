enum CommunityIdentitySlot { avatar, banner }

class CommunityIdentityUploadSession {
  const CommunityIdentityUploadSession({
    required this.slot,
    required this.uploadId,
    required this.method,
    required this.url,
    required this.headers,
    this.expiresAt,
  });

  final String slot;
  final String uploadId;
  final String method;
  final String url;
  final Map<String, String> headers;
  final String? expiresAt;

  factory CommunityIdentityUploadSession.fromJson(Map<String, dynamic> json) {
    final slot = json['slot'];
    final uploadId = json['upload_id'];
    final uploadRaw = json['upload'];
    if (slot is! String || (slot != 'avatar' && slot != 'banner')) {
      throw const FormatException('Invalid identity upload payload');
    }
    if (uploadId is! String || uploadId.trim().isEmpty) {
      throw const FormatException('Invalid identity upload payload');
    }
    if (uploadRaw is! Map) {
      throw const FormatException('Invalid identity upload payload');
    }
    if (json.containsKey('storage_key') ||
        json.containsKey('avatar_storage_key') ||
        json.containsKey('banner_storage_key')) {
      throw const FormatException('Identity upload payload leaked private fields');
    }
    final methodRaw = uploadRaw['method'];
    final urlRaw = uploadRaw['url'];
    if (methodRaw is! String || methodRaw.trim().isEmpty) {
      throw const FormatException('Invalid identity upload payload');
    }
    if (urlRaw is! String || urlRaw.trim().isEmpty) {
      throw const FormatException('Invalid identity upload payload');
    }
    final headers = <String, String>{};
    final headersRaw = uploadRaw['headers'];
    if (headersRaw is Map) {
      for (final entry in headersRaw.entries) {
        headers['${entry.key}'] = '${entry.value}';
      }
    }
    final expires = uploadRaw['expires_at'];
    return CommunityIdentityUploadSession(
      slot: slot,
      uploadId: uploadId.trim(),
      method: methodRaw.trim(),
      url: urlRaw.trim(),
      headers: headers,
      expiresAt: expires is String ? expires : null,
    );
  }
}
