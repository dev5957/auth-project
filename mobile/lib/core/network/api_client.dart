import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// Client HTTP partagé. Les interceptors Auth (Bearer, refresh) seront ajoutés plus tard.
class ApiClient {
  ApiClient({required AppConfig config})
      : dio = Dio(
          BaseOptions(
            baseUrl: config.apiBaseUrl,
            connectTimeout: config.connectTimeout,
            receiveTimeout: config.receiveTimeout,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          ),
        );

  final Dio dio;
}
