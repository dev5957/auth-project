import 'package:dio/dio.dart';

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
          handler.next(
            error.copyWith(error: ApiException.fromDio(error)),
          );
        },
      ),
    );
  }

  final Dio dio;
}
