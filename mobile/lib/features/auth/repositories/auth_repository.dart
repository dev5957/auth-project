import '../../../core/storage/token_storage.dart';
import '../services/auth_api_service.dart';

/// Orchestration session Auth. Volontairement vide à cette étape.
class AuthRepository {
  AuthRepository({
    required AuthApiService api,
    required TokenStorage tokenStorage,
  })  : _api = api,
        _tokenStorage = tokenStorage;

  // ignore: unused_field
  final AuthApiService _api;
  // ignore: unused_field
  final TokenStorage _tokenStorage;
}
