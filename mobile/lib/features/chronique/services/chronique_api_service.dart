import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/chronique.dart';

/// Appels HTTP Chronique. Bearer posé par appel, comme Auth.
class ChroniqueApiService {
  ChroniqueApiService(this._client);

  final ApiClient _client;

  /// `POST /chroniques` — publication immédiate : `publish: "now"`.
  Future<Chronique> create({
    required String accessToken,
    required String body,
    String? title,
  }) async {
    debugPrint('[chronique-http] ChroniqueApiService.create() → POST /chroniques');
    final data = <String, dynamic>{
      'body': body,
      'publish': 'now',
      if (title != null && title.isNotEmpty) 'title': title,
    };
    final json = await _send(
      'POST',
      '/chroniques',
      accessToken: accessToken,
      data: data,
    );
    final chronique = json['chronique'];
    if (chronique is! Map) {
      throw const FormatException('Invalid chronique payload');
    }
    return Chronique.fromJson(asJsonMap(chronique));
  }

  /// `GET /chroniques` — première page du fil `active` (défauts serveur).
  Future<List<Chronique>> list({required String accessToken}) async {
    debugPrint('[chronique-http] ChroniqueApiService.list() → GET /chroniques');
    final json = await _send(
      'GET',
      '/chroniques',
      accessToken: accessToken,
    );
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid chronique list payload');
    }
    return [
      for (final item in items)
        Chronique.fromJson(asJsonMap(item)),
    ];
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? data,
    String? accessToken,
  }) async {
    try {
      final response = await _client.dio.request<dynamic>(
        path,
        data: data,
        options: Options(
          method: method,
          headers: accessToken == null
              ? null
              : <String, dynamic>{'Authorization': 'Bearer $accessToken'},
        ),
      );
      if (response.data == null || response.data == '') {
        return <String, dynamic>{};
      }
      return asJsonMap(response.data);
    } on DioException catch (error) {
      final mapped = error.error;
      if (mapped is ApiException) {
        throw mapped;
      }
      throw ApiException.fromDio(error);
    }
  }
}
