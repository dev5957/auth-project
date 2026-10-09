import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../media/chronique_media_limits.dart';

/// PUT binaire vers l’URL signée R2. Dio dédié : pas de JWT, pas de JSON, pas d’ApiClient.
class ChroniqueMediaUploadClient {
  ChroniqueMediaUploadClient({
    Dio? dio,
    Duration connectTimeout = const Duration(seconds: 30),
    Duration sendTimeout = const Duration(minutes: 10),
    Duration receiveTimeout = const Duration(minutes: 10),
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: connectTimeout,
                sendTimeout: sendTimeout,
                receiveTimeout: receiveTimeout,
                followRedirects: true,
                validateStatus: (status) => status != null && status >= 200 && status < 300,
              ),
            );

  final Dio _dio;

  Future<void> putFile({
    required String url,
    required String method,
    required Map<String, String> headers,
    required String localPath,
    required int byteSize,
    ProgressCallback? onSendProgress,
  }) async {
    final verb = method.trim().toUpperCase();
    if (verb != 'PUT') {
      throw const ApiException(message: kMediaUploadFailedMessage);
    }
    if (url.trim().isEmpty) {
      throw const ApiException(message: kMediaUploadFailedMessage);
    }

    final file = File(localPath);
    if (!file.existsSync()) {
      throw const ApiException(message: kMediaUploadFailedMessage);
    }

    final requestHeaders = <String, dynamic>{
      ...headers,
      Headers.contentLengthHeader: byteSize,
    };

    try {
      await _dio.request<void>(
        url,
        data: file.openRead(),
        onSendProgress: onSendProgress,
        options: Options(
          method: verb,
          headers: requestHeaders,
          contentType: headers['Content-Type'] ?? headers['content-type'],
        ),
      );
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      debugPrint(
        '[chronique-media-put] failed type=${error.type} '
        'status=${error.response?.statusCode}',
      );
      final mapped = error.error;
      if (mapped is ApiException) {
        throw mapped;
      }
      throw const ApiException(message: kMediaUploadFailedMessage);
    }
  }
}
