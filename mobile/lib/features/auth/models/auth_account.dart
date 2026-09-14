import 'json_ids.dart';

/// Compte renvoyé par login, refresh et `register/verify-phone` (`id`, pas `userId`).
class AuthAccount {
  const AuthAccount({
    required this.id,
    required this.login,
    required this.authProvider,
    this.email,
    this.phoneVerified,
  });

  final int id;
  final String login;
  final String authProvider;
  final String? email;
  final bool? phoneVerified;

  factory AuthAccount.fromJson(Map<String, dynamic> json) {
    final login = json['login'];
    final authProvider = json['auth_provider'];
    if (login is! String || authProvider is! String) {
      throw const FormatException('Invalid user payload');
    }
    return AuthAccount(
      id: parseJsonInt(json['id']),
      login: login,
      authProvider: authProvider,
      email: json['email'] as String?,
      phoneVerified: json['phone_verified'] as bool?,
    );
  }
}
