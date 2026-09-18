import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/auth_session.dart';
import '../models/auth_user.dart';
import '../models/register_start_result.dart';
import '../models/register_verify_result.dart';

/// Appels HTTP du contrat Auth local + session. Pas de Google / Apple ici.
class AuthApiService {
  AuthApiService(this._client);

  final ApiClient _client;

  /// `POST /auth/register/start`
  Future<RegisterStartResult> startRegister({
    required String email,
    required String login,
    required String phoneNumber,
    required String birthDate,
    required String password,
    required String passwordConfirmation,
    String? firstName,
    String? lastName,
  }) async {
    final json = await _send(
      'POST',
      '/auth/register/start',
      data: {
        'email': email,
        'login': login,
        'phone_number': phoneNumber,
        'birth_date': birthDate,
        'password': password,
        'password_confirmation': passwordConfirmation,
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
      },
    );
    return RegisterStartResult.fromJson(json);
  }

  /// `POST /auth/register/verify-phone`
  Future<RegisterVerifyResult> verifyRegisterPhone({
    required String verificationToken,
    required String code,
  }) async {
    final json = await _send(
      'POST',
      '/auth/register/verify-phone',
      data: {
        'verification_token': verificationToken,
        'code': code,
      },
    );
    return RegisterVerifyResult.fromJson(json);
  }

  /// `POST /auth/login`
  Future<AuthSession> login({
    required String login,
    required String password,
  }) async {
    debugPrint('[auth-http-diag][B] AuthApiService.login() → POST /auth/login');
    debugPrint('[auth-login-diag] AuthApiService.login() entered');
    debugPrint('[auth-login-diag] AuthApiService.login() about to POST /auth/login');
    final json = await _send(
      'POST',
      '/auth/login',
      data: {
        'login': login,
        'password': password,
      },
    );
    debugPrint('[auth-http-diag][B] AuthApiService.login() HTTP success (body not logged)');
    return AuthSession.fromJson(json);
  }

  /// `GET /auth/me`
  Future<AuthUser> me({required String accessToken}) async {
    final json = await _send(
      'GET',
      '/auth/me',
      accessToken: accessToken,
    );
    return AuthUser.fromMeJson(json);
  }

  /// `POST /auth/refresh` — pas de Bearer.
  Future<AuthSession> refresh({required String refreshToken}) async {
    debugPrint(
      '[auth-restore-diag] AuthApiService.refresh() → POST /auth/refresh (token not logged)',
    );
    final json = await _send(
      'POST',
      '/auth/refresh',
      data: {
        'refresh_token': refreshToken,
      },
    );
    debugPrint('[auth-restore-diag] AuthApiService.refresh() HTTP parsed OK (body not logged)');
    return AuthSession.fromJson(json);
  }

  /// `POST /auth/logout`
  Future<void> logout({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _send(
      'POST',
      '/auth/logout',
      accessToken: accessToken,
      data: {
        'refresh_token': refreshToken,
      },
    );
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? data,
    String? accessToken,
  }) async {
    final baseUrl = _client.dio.options.baseUrl;
    final uri = Uri.parse('$baseUrl$path');
    debugPrint('[auth-http-diag] request $method $uri');
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
      debugPrint(
        '[auth-http-diag] response statusCode=${response.statusCode} '
        'uri=${response.realUri}',
      );
      if (response.data == null || response.data == '') {
        return <String, dynamic>{};
      }
      return asJsonMap(response.data);
    } on DioException catch (error) {
      debugPrint(
        '[auth-http-diag][A-AFTER-WRAP] type=${error.type} '
        'wrapped.error=${error.error} '
        'uri=${error.requestOptions.uri}',
      );
      final mapped = error.error;
      if (mapped is ApiException) {
        throw mapped;
      }
      throw ApiException.fromDio(error);
    }
  }
}
