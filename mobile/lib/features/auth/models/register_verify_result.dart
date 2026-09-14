import 'auth_account.dart';

/// `POST /auth/register/verify-phone` — 201, sans JWT.
class RegisterVerifyResult {
  const RegisterVerifyResult({
    required this.message,
    required this.user,
  });

  final String message;
  final AuthAccount user;

  factory RegisterVerifyResult.fromJson(Map<String, dynamic> json) {
    final message = json['message'];
    final user = json['user'];
    if (message is! String || user is! Map) {
      throw const FormatException('Invalid register/verify-phone payload');
    }
    return RegisterVerifyResult(
      message: message,
      user: AuthAccount.fromJson(Map<String, dynamic>.from(user)),
    );
  }
}
