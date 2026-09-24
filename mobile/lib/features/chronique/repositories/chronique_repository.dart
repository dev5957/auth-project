import '../../../core/network/api_exception.dart';
import '../../auth/data/storage/auth_token_storage.dart';
import '../models/chronique.dart';
import '../models/chronique_page.dart';
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

  Future<String> _requireAccessToken() async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiException(message: 'Unauthorized', statusCode: 401);
    }
    return accessToken;
  }
}
