import '../../../core/network/api_exception.dart';
import '../data/storage/auth_token_storage.dart';
import '../models/auth_session.dart';
import '../models/auth_user.dart';
import '../models/register_start_result.dart';
import '../models/register_verify_result.dart';
import '../models/session_tokens.dart';
import '../services/auth_api_service.dart';

/// Orchestration session : appels API + persistance des jetons.
class AuthRepository {
  AuthRepository({
    required AuthApiService api,
    required AuthTokenStorage tokenStorage,
  })  : _api = api,
        _tokenStorage = tokenStorage;

  final AuthApiService _api;
  final AuthTokenStorage _tokenStorage;

  Future<bool> hasStoredRefreshToken() {
    return _tokenStorage.hasRefreshToken();
  }

  Future<RegisterStartResult> startRegister({
    required String email,
    required String login,
    required String phoneNumber,
    required String birthDate,
    required String password,
    required String passwordConfirmation,
    String? firstName,
    String? lastName,
  }) {
    return _api.startRegister(
      email: email,
      login: login,
      phoneNumber: phoneNumber,
      birthDate: birthDate,
      password: password,
      passwordConfirmation: passwordConfirmation,
      firstName: firstName,
      lastName: lastName,
    );
  }

  Future<RegisterVerifyResult> verifyRegisterPhone({
    required String verificationToken,
    required String code,
  }) {
    return _api.verifyRegisterPhone(
      verificationToken: verificationToken,
      code: code,
    );
  }

  Future<AuthSession> login({
    required String login,
    required String password,
  }) async {
    final session = await _api.login(login: login, password: password);
    await _persist(session.tokens);
    return session;
  }

  Future<AuthUser> me() async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiException(message: 'Unauthorized', statusCode: 401);
    }
    return _api.me(accessToken: accessToken);
  }

  Future<AuthSession> refreshSession() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const ApiException(message: 'refresh_token is required', statusCode: 400);
    }
    try {
      final session = await _api.refresh(refreshToken: refreshToken);
      await _persist(session.tokens);
      return session;
    } catch (_) {
      await _tokenStorage.clearTokens();
      rethrow;
    }
  }

  Future<void> logout() async {
    final accessToken = await _tokenStorage.readAccessToken();
    final refreshToken = await _tokenStorage.readRefreshToken();
    try {
      if (accessToken != null &&
          accessToken.isNotEmpty &&
          refreshToken != null &&
          refreshToken.isNotEmpty) {
        await _api.logout(accessToken: accessToken, refreshToken: refreshToken);
      }
    } on ApiException {
      // Erreurs attendues (401/400) ou réseau : le nettoyage local continue.
    } finally {
      await _tokenStorage.clearTokens();
    }
  }

  Future<void> _persist(SessionTokens tokens) {
    return _tokenStorage.saveTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
  }
}
