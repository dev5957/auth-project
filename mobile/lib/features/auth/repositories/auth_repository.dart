import 'package:flutter/foundation.dart';

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
    debugPrint('[auth-http-diag][B] AuthRepository.login() start');
    final session = await _api.login(login: login, password: password);
    debugPrint('[auth-http-diag][B] AuthRepository.login() HTTP OK, saveTokens start');
    try {
      await _persist(session.tokens);
      debugPrint('[auth-http-diag][B] AuthRepository.login() saveTokens OK');
    } catch (error, stackTrace) {
      debugPrint(
        '[auth-http-diag][B] AuthRepository.login() saveTokens FAILED '
        'error.runtimeType=${error.runtimeType} error=$error',
      );
      debugPrint('[auth-http-diag][B] saveTokens stackTrace=$stackTrace');
      rethrow;
    }
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
    debugPrint('[auth-restore-diag] AuthRepository.refreshSession() entered');
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      debugPrint('[auth-restore-diag] refreshSession() abort: no refresh token in storage');
      throw const ApiException(message: 'refresh_token is required', statusCode: 400);
    }
    try {
      debugPrint('[auth-restore-diag] refreshSession() → AuthApiService.refresh()');
      final session = await _api.refresh(refreshToken: refreshToken);
      debugPrint('[auth-restore-diag] refreshSession() HTTP OK, saveTokens start');
      await _persist(session.tokens);
      debugPrint('[auth-restore-diag] refreshSession() saveTokens OK');
      return session;
    } catch (error) {
      debugPrint(
        '[auth-restore-diag] refreshSession() FAILED error.runtimeType=${error.runtimeType}',
      );
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
