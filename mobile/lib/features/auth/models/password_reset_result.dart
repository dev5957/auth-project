/// `POST /auth/password/forgot` et `POST /auth/password/reset`.
class PasswordResetResult {
  const PasswordResetResult({required this.message});

  final String message;

  factory PasswordResetResult.fromJson(Map<String, dynamic> json) {
    final message = json['message'];
    if (message is! String || message.isEmpty) {
      throw const FormatException('Invalid password reset payload');
    }
    return PasswordResetResult(message: message);
  }
}
