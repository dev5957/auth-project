/// Payload de `GET /auth/me` (`user.userId`, `login`, `auth_provider`).
class AuthUser {
  const AuthUser({
    required this.userId,
    required this.login,
    required this.authProvider,
  });

  final Object userId;
  final String login;
  final String authProvider;

  factory AuthUser.fromMeJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return AuthUser(
      userId: user['userId'] as Object,
      login: user['login'] as String,
      authProvider: user['auth_provider'] as String,
    );
  }
}
