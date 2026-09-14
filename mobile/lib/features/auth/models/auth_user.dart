import 'json_ids.dart';

/// Payload de `GET /auth/me` (`user.userId`, `login`, `auth_provider`).
class AuthUser {
  const AuthUser({
    required this.userId,
    required this.login,
    required this.authProvider,
  });

  final int userId;
  final String login;
  final String authProvider;

  factory AuthUser.fromMeJson(Map<String, dynamic> json) {
    final user = json['user'];
    if (user is! Map) {
      throw const FormatException('Invalid /auth/me payload');
    }
    final login = user['login'];
    final authProvider = user['auth_provider'];
    if (login is! String || authProvider is! String) {
      throw const FormatException('Invalid /auth/me user');
    }
    return AuthUser(
      userId: parseJsonInt(user['userId']),
      login: login,
      authProvider: authProvider,
    );
  }
}
