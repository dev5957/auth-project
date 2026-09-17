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
    final hasRefreshToken = await _repository.hasStoredRefreshToken();
    if (!hasRefreshToken) {
      state = const AuthUnauthenticated();
      return;
    }
    try {
      final session = await _repository.refreshSession();
      state = AuthAuthenticated(user: session.user);
    } on ApiException {
      state = const AuthUnauthenticated();
    } on FormatException {
      state = const AuthUnauthenticated();
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
    state = const AuthLoading();
    try {
      final session = await _repository.login(login: login, password: password);
      state = AuthAuthenticated(user: session.user);
    } on ApiException {
      state = const AuthUnauthenticated();
      rethrow;
    } on FormatException {
      state = const AuthUnauthenticated();
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
