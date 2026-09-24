import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/chronique.dart';
import '../models/chronique_page.dart';

/// Appels HTTP Chronique. Bearer posé par appel, comme Auth.
class ChroniqueApiService {
  ChroniqueApiService(this._client);

  final ApiClient _client;

  /// `POST /chroniques`. Défaut V1 : `publish: "now"` (aucune régression).
  Future<Chronique> create({
    required String accessToken,
    required String body,
    String? title,
    String publish = 'now',
    String? scheduledAt,
    bool isTimeLimited = false,
    String? expiresAt,
  }) async {
    debugPrint(
      '[chronique-http] ChroniqueApiService.create() → POST /chroniques publish=$publish',
    );
    final data = <String, dynamic>{
      'body': body,
      'publish': publish,
      if (title != null && title.isNotEmpty) 'title': title,
      if (publish == 'schedule' && scheduledAt != null) 'scheduled_at': scheduledAt,
      if (isTimeLimited) 'is_time_limited': true,
      if (isTimeLimited && expiresAt != null) 'expires_at': expiresAt,
    };
    final json = await _send(
      'POST',
      '/chroniques',
      accessToken: accessToken,
      data: data,
    );
    return _chroniqueFrom(json);
  }

  /// `GET /chroniques` — première page. `status` omis = défaut serveur (`active`).
  Future<ChroniquePage> list({
    required String accessToken,
    String? status,
  }) async {
    debugPrint(
      '[chronique-http] ChroniqueApiService.list() → GET /chroniques'
      '${status == null ? '' : '?status=$status'}',
    );
    final json = await _send(
      'GET',
      '/chroniques',
      accessToken: accessToken,
      queryParameters: status == null ? null : <String, dynamic>{'status': status},
    );
    return ChroniquePage.fromJson(json);
  }

  /// `POST /chroniques/:id/archive`
  Future<Chronique> archive({
    required String accessToken,
    required int id,
  }) async {
    debugPrint('[chronique-http] ChroniqueApiService.archive() → POST /chroniques/$id/archive');
    final json = await _send(
      'POST',
      '/chroniques/$id/archive',
      accessToken: accessToken,
    );
    return _chroniqueFrom(json);
  }

  /// `GET /chroniques/:id`
  Future<Chronique> get({
    required String accessToken,
    required int id,
  }) async {
    debugPrint('[chronique-http] ChroniqueApiService.get() → GET /chroniques/$id');
    final json = await _send(
      'GET',
      '/chroniques/$id',
      accessToken: accessToken,
    );
    return _chroniqueFrom(json);
  }

  /// `PATCH /chroniques/:id` — titre et corps uniquement.
  Future<Chronique> update({
    required String accessToken,
    required int id,
    required String body,
    String? title,
  }) async {
    debugPrint('[chronique-http] ChroniqueApiService.update() → PATCH /chroniques/$id');
    final json = await _send(
      'PATCH',
      '/chroniques/$id',
      accessToken: accessToken,
      data: <String, dynamic>{
        'title': title,
        'body': body,
      },
    );
    return _chroniqueFrom(json);
  }

  /// `DELETE /chroniques/:id` — suppression logique côté serveur.
  Future<void> delete({
    required String accessToken,
    required int id,
  }) async {
    debugPrint('[chronique-http] ChroniqueApiService.delete() → DELETE /chroniques/$id');
    await _send(
      'DELETE',
      '/chroniques/$id',
      accessToken: accessToken,
    );
  }

  Chronique _chroniqueFrom(Map<String, dynamic> json) {
    final chronique = json['chronique'];
    if (chronique is! Map) {
      throw const FormatException('Invalid chronique payload');
    }
    return Chronique.fromJson(asJsonMap(chronique));
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    String? accessToken,
  }) async {
    try {
      final response = await _client.dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
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
      debugPrint(
        '[chronique-http] $method $path failed '
        'type=${error.type} status=${error.response?.statusCode} '
        'dioMessage=${error.message}',
      );
      final mapped = error.error;
      if (mapped is ApiException) {
        throw mapped;
      }
      throw ApiException.fromDio(error);
    }
  }
}
