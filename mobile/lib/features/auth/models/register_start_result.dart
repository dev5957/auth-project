/// `POST /auth/register/start` — 201.
class RegisterStartResult {
  const RegisterStartResult({
    required this.message,
    required this.verificationToken,
  });

  final String message;
  final String verificationToken;

  factory RegisterStartResult.fromJson(Map<String, dynamic> json) {
    final message = json['message'];
    final token = json['verification_token'];
    if (message is! String || token is! String) {
      throw const FormatException('Invalid register/start payload');
    }
    return RegisterStartResult(
      message: message,
      verificationToken: token,
    );
  }
}
