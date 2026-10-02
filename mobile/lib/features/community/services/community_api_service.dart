import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/community.dart';

class CommunityApiService {
  CommunityApiService(this._client);

  final ApiClient _client;

  Future<Community> create({
    required String accessToken,
    required String name,
    String? description,
  }) async {
    final json = await _send(
      'POST',
      '/communities',
      accessToken: accessToken,
      data: <String, dynamic>{
        'name': name,
        if (description != null) 'description': description,
      },
    );
    return _communityFrom(json);
  }

  Future<List<Community>> list({required String accessToken}) async {
    final json = await _send('GET', '/communities', accessToken: accessToken);
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid community list payload');
    }
    return [
      for (final item in items) Community.fromJson(_asMap(item)),
    ];
  }

  Future<List<UserSearchHit>> searchUsers({
    required String accessToken,
    String? login,
    String? phone,
  }) async {
    final hasLogin = login != null;
    final hasPhone = phone != null;
    if (hasLogin == hasPhone) {
      throw const FormatException('User search requires login or phone');
    }
    final json = await _send(
      'GET',
      '/users/search',
      accessToken: accessToken,
      queryParameters: hasLogin
          ? <String, dynamic>{'login': login}
          : <String, dynamic>{'phone': phone},
    );
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid user search payload');
    }
    return [
      for (final item in items) UserSearchHit.fromJson(_asMap(item)),
    ];
  }

  Future<List<CommunitySearchPreview>> search({
    required String accessToken,
    required String q,
  }) async {
    final json = await _send(
      'GET',
      '/communities/search',
      accessToken: accessToken,
      queryParameters: <String, dynamic>{'q': q},
    );
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid community search payload');
    }
    return [
      for (final item in items) CommunitySearchPreview.fromJson(_asMap(item)),
    ];
  }

  Future<Community> get({
    required String accessToken,
    required int id,
  }) async {
    final json = await _send('GET', '/communities/$id', accessToken: accessToken);
    return _communityFrom(json);
  }

  Future<List<CommunityMember>> listMembers({
    required String accessToken,
    required int id,
  }) async {
    final json = await _send(
      'GET',
      '/communities/$id/members',
      accessToken: accessToken,
    );
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid community members payload');
    }
    return [
      for (final item in items) CommunityMember.fromJson(_asMap(item)),
    ];
  }

  Community _communityFrom(Map<String, dynamic> json) {
    final community = json['community'] ?? json;
    return Community.fromJson(_asMap(community));
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw const FormatException('Invalid community payload');
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    required String accessToken,
  }) async {
    try {
      final response = await _client.dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: <String, dynamic>{'Authorization': 'Bearer $accessToken'},
        ),
      );
      if (response.data == null || response.data == '') {
        return <String, dynamic>{};
      }
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      throw const FormatException('Invalid community payload');
    } on DioException catch (error) {
      debugPrint(
        '[community-http] $method $path failed '
        'type=${error.type} status=${error.response?.statusCode}',
      );
      final mapped = error.error;
      if (mapped is ApiException) {
        throw mapped;
      }
      throw ApiException.fromDio(error);
    }
  }
}

