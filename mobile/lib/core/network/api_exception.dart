/// Erreur API alignée sur `{ "error": "<message>" }` du backend.
class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.statusCode,
  });

  final String message;
  final int? statusCode;

  factory ApiException.fromResponse({
    required int? statusCode,
    required Object? body,
  }) {
    if (body is Map && body['error'] is String) {
      return ApiException(message: body['error'] as String, statusCode: statusCode);
    }
    return ApiException(message: 'Unexpected error', statusCode: statusCode);
  }

  @override
  String toString() => 'ApiException($statusCode, $message)';
}
