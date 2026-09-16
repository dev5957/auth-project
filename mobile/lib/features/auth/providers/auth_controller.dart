import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../repositories/auth_repository.dart';
import '../state/auth_state.dart';
import 'auth_providers.dart';

/// Session globale. Restaure au premier `watch` via `refreshSession()`.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future<void>.microtask(restore);
    return const AuthLoading();
  }

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  /// Cold start : le contrat client exige `POST /auth/refresh`, pas `GET /auth/me`.
  Future<void> restore() async {
    try {
      final session = await _repository.refreshSession();
      state = AuthAuthenticated(user: session.user);
    } on ApiException {
      state = const AuthUnauthenticated();
    } on FormatException {
      state = const AuthUnauthenticated();
    }
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
    await _repository.logout();
    state = const AuthUnauthenticated();
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
