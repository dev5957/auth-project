import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../media/chronique_document_file.dart';

/// GET binaire vers l’URL signée R2. Dio dédié : pas de JWT, pas de JSON, pas d’ApiClient.
class ChroniqueDocumentReadClient {
  ChroniqueDocumentReadClient({
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

  Future<void> downloadToFile({
    required String url,
    required String savePath,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw const ApiException(message: kChroniqueDocumentRetrieveFailedMessage);
    }
    try {
      await _dio.download(
        trimmed,
        savePath,
        options: Options(
          method: 'GET',
          responseType: ResponseType.bytes,
          headers: const <String, dynamic>{},
        ),
      );
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      debugPrint(
        '[chronique-document-get] failed type=${error.type} '
        'status=${error.response?.statusCode}',
      );
      final mapped = error.error;
      if (mapped is ApiException) {
        throw mapped;
      }
      throw const ApiException(message: kChroniqueDocumentRetrieveFailedMessage);
    } on Exception {
      throw const ApiException(message: kChroniqueDocumentRetrieveFailedMessage);
    }
  }
}
