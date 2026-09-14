import 'auth_account.dart';
import 'session_tokens.dart';

/// Session après `POST /auth/login` ou `POST /auth/refresh`.
class AuthSession {
  const AuthSession({
    required this.message,
    required this.tokens,
    required this.user,
  });

  final String message;
  final SessionTokens tokens;
  final AuthAccount user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final message = json['message'];
    final user = json['user'];
    if (message is! String || user is! Map) {
      throw const FormatException('Invalid session payload');
    }
    return AuthSession(
      message: message,
      tokens: SessionTokens.fromJson(json),
      user: AuthAccount.fromJson(Map<String, dynamic>.from(user)),
    );
  }
}
