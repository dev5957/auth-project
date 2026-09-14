import 'package:dio/dio.dart';

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

  factory ApiException.fromDio(DioException error) {
    if (error.response != null) {
      return ApiException.fromResponse(
        statusCode: error.response?.statusCode,
        body: error.response?.data,
      );
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return const ApiException(message: 'Network error');
      default:
        return const ApiException(message: 'Network error');
    }
  }

  @override
  String toString() => 'ApiException($statusCode, $message)';
}

Map<String, dynamic> asJsonMap(Object? data) {
  if (data is Map<String, dynamic>) {
    return data;
  }
  if (data is Map) {
    return Map<String, dynamic>.from(data);
  }
  throw const ApiException(message: 'Invalid JSON');
}
