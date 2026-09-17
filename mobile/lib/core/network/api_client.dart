import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'api_exception.dart';

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
          // TEMP diagnostic — original cause, before ApiException wrapping.
          debugPrint(
            '[auth-http-diag] interceptor original type=${error.type} '
            'message=${error.message} '
            'error.runtimeType=${error.error.runtimeType} '
            'error=${error.error} '
            'uri=${error.requestOptions.uri} '
            'response.statusCode=${error.response?.statusCode}',
          );
          debugPrint('[auth-http-diag] interceptor stackTrace=${error.stackTrace}');
          handler.next(
            error.copyWith(error: ApiException.fromDio(error)),
          );
        },
      ),
    );
  }

  final Dio dio;
}
