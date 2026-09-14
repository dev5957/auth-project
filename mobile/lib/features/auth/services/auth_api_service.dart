import '../../../core/network/api_client.dart';
import '../models/session_tokens.dart';

/// Contrats HTTP Auth. Les appels ne sont pas implémentés à cette étape.
class AuthApiService {
  AuthApiService(this._client);

  // ignore: unused_field
  final ApiClient _client;

  /// `POST /auth/register/start`
  Future<String> startRegister(Map<String, dynamic> body) {
    throw UnimplementedError('Auth API not implemented yet');
  }

  /// `POST /auth/register/verify-phone`
  Future<void> verifyRegisterPhone(Map<String, dynamic> body) {
    throw UnimplementedError('Auth API not implemented yet');
  }

  /// `POST /auth/login`
  Future<SessionTokens> login(Map<String, dynamic> body) {
    throw UnimplementedError('Auth API not implemented yet');
  }

  /// `GET /auth/me`
  Future<void> me() {
    throw UnimplementedError('Auth API not implemented yet');
  }

  /// `POST /auth/refresh`
  Future<SessionTokens> refresh(String refreshToken) {
    throw UnimplementedError('Auth API not implemented yet');
  }

  /// `POST /auth/logout`
  Future<void> logout(String refreshToken) {
    throw UnimplementedError('Auth API not implemented yet');
  }
}
