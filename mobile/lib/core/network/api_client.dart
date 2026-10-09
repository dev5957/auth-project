import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'api_exception.dart';
import 'http_log_sanitize.dart';

/// Client HTTP partagé (JSON, timeouts, mapping `{ "error": "..." }`).
///
/// Pas de refresh automatique ici : le repository gère les jetons.
class ApiClient {
  ApiClient({required AppConfig config})
      : dio = Dio(
          BaseOptions(
            baseUrl: config.apiBaseUrl,
            connectTimeout: config.connectTimeout,
            receiveTimeout: config.receiveTimeout,
            responseType: ResponseType.json,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          ),
        ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          // TEMP A — native cause only, before ApiException.fromDio.
          // Query values (phone, tokens, …) are redacted; headers are never logged.
          final original = error.error;
          debugPrint(
            '[auth-http-diag][A-NATIVE] type=${error.type} '
            'method=${error.requestOptions.method} '
            'path=${error.requestOptions.path} '
            'message=${HttpLogSanitize.text(error.message)} '
            'error.runtimeType=${original.runtimeType} '
            'error=${HttpLogSanitize.text(original)} '
            'uri=${HttpLogSanitize.requestUri(error.requestOptions)} '
            'response.statusCode=${error.response?.statusCode}',
          );
          debugPrint(
            '[auth-http-diag][A-NATIVE] stackTrace=${HttpLogSanitize.text(error.stackTrace)}',
          );
          handler.next(
            error.copyWith(error: ApiException.fromDio(error)),
          );
        },
      ),
    );
  }

  final Dio dio;
}
