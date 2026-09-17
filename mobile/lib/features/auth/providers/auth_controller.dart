import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../models/register_start_result.dart';
import '../models/register_verify_result.dart';
import '../repositories/auth_repository.dart';
import '../state/auth_state.dart';
import 'auth_providers.dart';

/// Session globale. Restaure au premier `watch` si un `refresh_token` est stocké.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future<void>.microtask(restore);
    return const AuthLoading();
  }

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  /// Cold start : `POST /auth/refresh` uniquement s’il existe un refresh token.
  Future<void> restore() async {
    debugPrint('[auth-http-diag][B] AuthController.restore() start');
    try {
      final hasRefreshToken = await _repository.hasStoredRefreshToken();
      debugPrint('[auth-http-diag][B] restore hasRefreshToken=$hasRefreshToken');
      if (!hasRefreshToken) {
        state = const AuthUnauthenticated();
        debugPrint('[auth-http-diag][B] restore → AuthUnauthenticated (no refresh token)');
        return;
      }
      final session = await _repository.refreshSession();
      state = AuthAuthenticated(user: session.user);
      debugPrint('[auth-http-diag][B] restore → AuthAuthenticated');
    } on ApiException catch (error) {
      state = const AuthUnauthenticated();
      debugPrint(
        '[auth-http-diag][B] restore ApiException → AuthUnauthenticated '
        'statusCode=${error.statusCode}',
      );
    } on FormatException {
      state = const AuthUnauthenticated();
      debugPrint('[auth-http-diag][B] restore FormatException → AuthUnauthenticated');
    } catch (error) {
      state = const AuthUnauthenticated();
      debugPrint(
        '[auth-http-diag][B] restore other → AuthUnauthenticated '
        'error.runtimeType=${error.runtimeType}',
      );
    }
  }

  /// Inscription locale : SMS + `verification_token`. Pas une session.
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
    return _repository.startRegister(
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

  /// Finalise l’inscription locale (`users` + téléphone vérifié). Pas une session.
  Future<RegisterVerifyResult> verifyRegisterPhone({
    required String verificationToken,
    required String code,
  }) {
    return _repository.verifyRegisterPhone(
      verificationToken: verificationToken,
      code: code,
    );
  }

  Future<void> login({
    required String login,
    required String password,
  }) async {
    debugPrint('[auth-http-diag][B] AuthController.login() start → AuthLoading');
    state = const AuthLoading();
    try {
      final session = await _repository.login(login: login, password: password);
      state = AuthAuthenticated(user: session.user);
      debugPrint(
        '[auth-http-diag][B] AuthController.login() final state=${state.runtimeType}',
      );
    } on ApiException catch (error) {
      state = const AuthUnauthenticated();
      debugPrint(
        '[auth-http-diag][B] AuthController.login() ApiException → '
        'AuthUnauthenticated statusCode=${error.statusCode}',
      );
      rethrow;
    } on FormatException catch (error) {
      state = const AuthUnauthenticated();
      debugPrint(
        '[auth-http-diag][B] AuthController.login() FormatException → '
        'AuthUnauthenticated error=$error',
      );
      rethrow;
    } catch (error) {
      debugPrint(
        '[auth-http-diag][B] AuthController.login() other error.runtimeType='
        '${error.runtimeType} state remains ${state.runtimeType}',
      );
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await _repository.logout();
    } finally {
      state = const AuthUnauthenticated();
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
