import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';
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
    required TokenStorage tokenStorage,
  })  : _api = api,
        _tokenStorage = tokenStorage;

  final AuthApiService _api;
  final TokenStorage _tokenStorage;

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
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _tokenStorage.clear();
      }
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
    } on ApiException catch (error) {
      if (error.statusCode != 401 && error.statusCode != 400) {
        rethrow;
      }
    }
    await _tokenStorage.clear();
  }

  Future<void> _persist(SessionTokens tokens) async {
    await _tokenStorage.saveAccessToken(tokens.accessToken);
    await _tokenStorage.saveRefreshToken(tokens.refreshToken);
  }
}
