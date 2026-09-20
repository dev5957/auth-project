import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../models/google_start_result.dart';
import '../models/register_start_result.dart';
import '../models/register_verify_result.dart';
import '../repositories/auth_repository.dart';
import '../services/google_identity_service.dart';
import '../state/auth_state.dart';
import 'auth_providers.dart';

/// Session globale. Restaure au premier `watch` si un `refresh_token` est stocké.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    debugPrint(
      '[auth-restore-diag] AuthController.build() → AuthLoading, scheduling restore()',
    );
    Future<void>.microtask(restore);
    return const AuthLoading();
  }

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  /// Cold start : `POST /auth/refresh` uniquement s’il existe un refresh token.
  Future<void> restore() async {
    debugPrint('[auth-restore-diag] restore() entered');
    try {
      final hasRefreshToken = await _repository.hasStoredRefreshToken();
      debugPrint('[auth-restore-diag] hasRefreshToken=$hasRefreshToken');
      if (!hasRefreshToken) {
        state = const AuthUnauthenticated();
        debugPrint('[auth-restore-diag] skip refreshSession() → AuthUnauthenticated');
        return;
      }
      debugPrint('[auth-restore-diag] calling refreshSession()');
      final session = await _repository.refreshSession();
      state = AuthAuthenticated(user: session.user);
      debugPrint('[auth-restore-diag] refreshSession() OK → AuthAuthenticated');
    } on ApiException catch (error) {
      state = const AuthUnauthenticated();
      debugPrint(
        '[auth-restore-diag] refresh/restore ApiException → AuthUnauthenticated '
        'statusCode=${error.statusCode}',
      );
    } on FormatException {
      state = const AuthUnauthenticated();
      debugPrint('[auth-restore-diag] restore FormatException → AuthUnauthenticated');
    } catch (error) {
      state = const AuthUnauthenticated();
      debugPrint(
        '[auth-restore-diag] restore other → AuthUnauthenticated '
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

  /// Soumission Login : erreur = locale (formulaire). Succès = [AuthAuthenticated].
  /// Ne pas passer par [AuthLoading] / [AuthUnauthenticated] (redirect Carousel).
  Future<void> login({
    required String login,
    required String password,
  }) async {
    debugPrint(
      '[auth-login-diag] AuthController.login() entered '
      'state=${state.runtimeType}',
    );
    debugPrint(
      '[auth-http-diag][B] AuthController.login() start '
      '(no global AuthLoading — form loading only)',
    );
    try {
      debugPrint('[auth-login-diag] AuthController.login() calling repository.login()');
      final session = await _repository.login(login: login, password: password);
      state = AuthAuthenticated(user: session.user);
      debugPrint(
        '[auth-http-diag][B] AuthController.login() final state=${state.runtimeType}',
      );
      debugPrint(
        '[auth-login-diag] AuthController.login() repository returned → '
        'state=${state.runtimeType}',
      );
    } on ApiException catch (error) {
      debugPrint(
        '[auth-http-diag][B] AuthController.login() ApiException '
        'statusCode=${error.statusCode} state stays ${state.runtimeType}',
      );
      debugPrint(
        '[auth-login-diag] AuthController.login() ApiException captured, '
        'global auth unchanged (${state.runtimeType}) statusCode=${error.statusCode}',
      );
      rethrow;
    } on FormatException catch (error) {
      debugPrint(
        '[auth-http-diag][B] AuthController.login() FormatException → '
        'state stays ${state.runtimeType} error=$error',
      );
      debugPrint(
        '[auth-login-diag] AuthController.login() FormatException captured, '
        'global auth unchanged (${state.runtimeType})',
      );
      rethrow;
    } catch (error) {
      debugPrint(
        '[auth-http-diag][B] AuthController.login() other error.runtimeType='
        '${error.runtimeType} state remains ${state.runtimeType}',
      );
      debugPrint(
        '[auth-login-diag] AuthController.login() other error captured '
        'error.runtimeType=${error.runtimeType} state=${state.runtimeType} '
        '(not converted to AuthUnauthenticated here)',
      );
      rethrow;
    }
  }

  /// Google existant → session. Pending → pas une erreur. Pas d’[AuthLoading].
  Future<ContinueWithGoogleResult> continueWithGoogle() async {
    final identity = await ref.read(googleIdentityServiceProvider).signIn();
    switch (identity) {
      case GoogleIdentityCanceled():
        return const ContinueWithGoogleCanceled();
      case GoogleIdentityFailure(:final message):
        throw ApiException(message: message);
      case GoogleIdentitySuccess(:final idToken):
        try {
          final result = await _repository.continueWithGoogle(idToken: idToken);
          switch (result) {
            case ContinueWithGoogleAuthenticated(:final session):
              state = AuthAuthenticated(user: session.user);
              return result;
            case ContinueWithGooglePending():
              return result;
            case ContinueWithGoogleCanceled():
              return result;
          }
        } on ApiException catch (error) {
          debugPrint(
            '[google-identity] AuthController.continueWithGoogle ApiException '
            'statusCode=${error.statusCode} state stays ${state.runtimeType}',
          );
          rethrow;
        } on FormatException {
          debugPrint(
            '[google-identity] AuthController.continueWithGoogle FormatException '
            'state stays ${state.runtimeType}',
          );
          rethrow;
        }
    }
  }

  Future<String> startOAuthPhone({
    required String oauthVerificationToken,
    required String phoneNumber,
  }) {
    return _repository.startOAuthPhone(
      oauthVerificationToken: oauthVerificationToken,
      phoneNumber: phoneNumber,
    );
  }

  /// Succès uniquement → [AuthAuthenticated]. Erreurs locales, pas d’[AuthLoading].
  Future<void> continueOAuthProfile({
    required String oauthVerificationToken,
    required String code,
    required String birthDate,
    required String login,
  }) async {
    try {
      final session = await _repository.continueOAuthProfile(
        oauthVerificationToken: oauthVerificationToken,
        code: code,
        birthDate: birthDate,
        login: login,
      );
      state = AuthAuthenticated(user: session.user);
    } on ApiException catch (error) {
      debugPrint(
        '[google-identity] continueOAuthProfile ApiException '
        'statusCode=${error.statusCode} state stays ${state.runtimeType}',
      );
      rethrow;
    } on FormatException {
      debugPrint(
        '[google-identity] continueOAuthProfile FormatException '
        'state stays ${state.runtimeType}',
      );
      rethrow;
    }
  }

  /// Forgot password : pas de session. Erreurs locales, pas d’[AuthLoading].
  Future<String> requestPasswordReset({required String email}) {
    return _repository.requestPasswordReset(email: email);
  }

  Future<String> confirmPasswordReset({
    required String email,
    required String code,
    required String password,
    required String passwordConfirmation,
  }) {
    return _repository.confirmPasswordReset(
      email: email,
      code: code,
      password: password,
      passwordConfirmation: passwordConfirmation,
    );
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
