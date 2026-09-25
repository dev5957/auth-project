import '../../../core/network/api_exception.dart';
import '../../auth/data/storage/auth_token_storage.dart';
import '../models/chronique.dart';
import '../models/chronique_media_upload.dart';
import '../models/chronique_page.dart';
import '../models/media_draft.dart';
import '../services/chronique_api_service.dart';

/// Orchestration Chronique : jeton existant + HTTP. Pas de refresh, pas de logout.
class ChroniqueRepository {
  ChroniqueRepository({
    required ChroniqueApiService api,
    required AuthTokenStorage tokenStorage,
  })  : _api = api,
        _tokenStorage = tokenStorage;

  final ChroniqueApiService _api;
  final AuthTokenStorage _tokenStorage;

  /// Publication (`publish: "now"` par défaut, ou `schedule`).
  Future<Chronique> create({
    required String body,
    String? title,
    String publish = 'now',
    String? scheduledAt,
    bool isTimeLimited = false,
    String? expiresAt,
  }) async {
    return _api.create(
      accessToken: await _requireAccessToken(),
      body: body,
      title: title,
      publish: publish,
      scheduledAt: scheduledAt,
      isTimeLimited: isTimeLimited,
      expiresAt: expiresAt,
    );
  }

  /// Fil personnel V1 : `GET /chroniques` (première page, pas de pagination).
  Future<ChroniquePage> list({String? status}) async {
    return _api.list(
      accessToken: await _requireAccessToken(),
      status: status,
    );
  }

  Future<Chronique> archive(int id) async {
    return _api.archive(accessToken: await _requireAccessToken(), id: id);
  }

  Future<Chronique> get(int id) async {
    return _api.get(accessToken: await _requireAccessToken(), id: id);
  }

  Future<Chronique> update({
    required int id,
    required String body,
    String? title,
    String? publish,
    String? scheduledAt,
    bool? isTimeLimited,
    String? expiresAt,
  }) async {
    return _api.update(
      accessToken: await _requireAccessToken(),
      id: id,
      body: body,
      title: title,
      publish: publish,
      scheduledAt: scheduledAt,
      isTimeLimited: isTimeLimited,
      expiresAt: expiresAt,
    );
  }

  Future<void> delete(int id) async {
    await _api.delete(accessToken: await _requireAccessToken(), id: id);
  }

  Future<ChroniqueMediaUploadSession> createMediaUpload({
    required int chroniqueId,
    required MediaDraft media,
  }) async {
    final contentType = media.contentType;
    final byteSize = media.byteSize;
    if (contentType == null || contentType.isEmpty || byteSize == null) {
      throw const ApiException(message: 'content_type is invalid', statusCode: 400);
    }
    return _api.createMediaUpload(
      accessToken: await _requireAccessToken(),
      chroniqueId: chroniqueId,
      kind: media.kind.name,
      sourceType: media.sourceType.name,
      contentType: contentType,
      byteSize: byteSize,
      originalFilename: media.fileName,
    );
  }

  Future<Chronique> completeMediaUpload({
    required int chroniqueId,
    required int mediaId,
  }) async {
    return _api.completeMediaUpload(
      accessToken: await _requireAccessToken(),
      chroniqueId: chroniqueId,
      mediaId: mediaId,
    );
  }

  Future<Chronique> deleteMedia({
    required int chroniqueId,
    required int mediaId,
  }) async {
    return _api.deleteMedia(
      accessToken: await _requireAccessToken(),
      chroniqueId: chroniqueId,
      mediaId: mediaId,
    );
  }

  Future<Chronique> reorderMedia({
    required int chroniqueId,
    required List<int> mediaIds,
  }) async {
    return _api.reorderMedia(
      accessToken: await _requireAccessToken(),
      chroniqueId: chroniqueId,
      mediaIds: mediaIds,
    );
  }

  Future<String> _requireAccessToken() async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiException(message: 'Unauthorized', statusCode: 401);
    }
    return accessToken;
  }
}
