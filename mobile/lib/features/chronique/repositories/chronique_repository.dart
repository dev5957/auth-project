import '../../../core/network/api_exception.dart';
import '../../auth/data/storage/auth_token_storage.dart';
import '../models/chronique.dart';
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

  /// Publication immédiate (`publish: "now"`).
  Future<Chronique> create({
    required String body,
    String? title,
  }) async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiException(message: 'Unauthorized', statusCode: 401);
    }
    return _api.create(
      accessToken: accessToken,
      body: body,
      title: title,
    );
  }

  /// Fil personnel V1 : `GET /chroniques` (première page, pas de pagination).
  Future<List<Chronique>> list() async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiException(message: 'Unauthorized', statusCode: 401);
    }
    return _api.list(accessToken: accessToken);
  }
}
