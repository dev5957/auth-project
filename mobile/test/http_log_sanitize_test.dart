import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/network/http_log_sanitize.dart';
import 'package:mobile/features/community/services/community_api_service.dart';

const String _kFakePhone = '+15550001111';
const String _kFakeLogin = 'user-test-alpha';
const String _kFakeToken = 'tok-test-0001';

class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.statusCode);

  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"error":"Unexpected error"}',
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('sanitize redacts phone query and keeps path and community q', () {
    final phoneUri = HttpLogSanitize.uri(
      Uri.parse('http://test.invalid/users/search?phone=$_kFakePhone'),
    );
    expect(phoneUri.path, '/users/search');
    expect(phoneUri.queryParameters['phone'], 'REDACTED');
    expect(phoneUri.toString(), isNot(contains('15550001111')));
    expect(phoneUri.toString(), isNot(contains(_kFakePhone)));

    final encoded = HttpLogSanitize.text(
      'uri=http://test.invalid/users/search?phone=${Uri.encodeQueryComponent(_kFakePhone)}',
    );
    expect(encoded, contains('phone=REDACTED'));
    expect(encoded, isNot(contains('15550001111')));

    final community = HttpLogSanitize.uri(
      Uri.parse('http://test.invalid/communities/search?q=Jardin'),
    );
    expect(community.queryParameters['q'], 'Jardin');

    final login = Uri.parse('http://test.invalid/auth/login');
    expect(HttpLogSanitize.uri(login).toString(), 'http://test.invalid/auth/login');
  });

  test('sanitize redacts json map case encoded and repeated forms', () {
    final json = HttpLogSanitize.text(
      '{"phone":"$_kFakePhone","login":"$_kFakeLogin","q":"Jardin"}',
    );
    expect(json, contains('"phone":"REDACTED"'));
    expect(json, contains('"login":"REDACTED"'));
    expect(json, contains('"q":"Jardin"'));
    expect(json, isNot(contains(_kFakePhone)));
    expect(json, isNot(contains(_kFakeLogin)));

    final map = HttpLogSanitize.text(
      '{phone: $_kFakePhone, login: $_kFakeLogin, status: 500}',
    );
    expect(map, contains('phone: REDACTED'));
    expect(map, contains('login: REDACTED'));
    expect(map, contains('status: 500'));
    expect(map, isNot(contains(_kFakePhone)));
    expect(map, isNot(contains(_kFakeLogin)));

    final mixedCase = HttpLogSanitize.text(
      '{"PHONE":"$_kFakePhone", Login: $_kFakeLogin}',
    );
    expect(mixedCase.toLowerCase(), contains('redacted'));
    expect(mixedCase, isNot(contains(_kFakePhone)));
    expect(mixedCase, isNot(contains(_kFakeLogin)));

    final repeated = HttpLogSanitize.uri(
      Uri.parse(
        'http://test.invalid/users/search?phone=aaa&phone=bbb&q=Jardin',
      ),
    );
    expect(repeated.queryParameters['phone'], 'REDACTED');
    expect(repeated.queryParameters['q'], 'Jardin');
    expect(repeated.toString(), isNot(contains('aaa')));
    expect(repeated.toString(), isNot(contains('bbb')));

    final header = HttpLogSanitize.text(
      'Authorization: Bearer $_kFakeToken',
    );
    expect(header, isNot(contains(_kFakeToken)));
    expect(header.toLowerCase(), contains('redacted'));
  });

  test('phone search HTTP error logs omit phone login token and authorization', () async {
    final previousPrint = debugPrint;
    final logs = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) {
      logs.add(message ?? '');
    };
    addTearDown(() => debugPrint = previousPrint);

    final client = ApiClient(
      config: const AppConfig(apiBaseUrl: 'http://test.invalid'),
    );
    client.dio.httpClientAdapter = _StatusAdapter(500);
    final api = CommunityApiService(client);

    await expectLater(
      api.searchUsers(accessToken: _kFakeToken, phone: _kFakePhone),
      throwsA(
        isA<ApiException>().having((error) => error.statusCode, 'statusCode', 500),
      ),
    );

    final blob = logs.join('\n');
    expect(blob, isNot(contains(_kFakePhone)));
    expect(blob, isNot(contains('15550001111')));
    expect(blob, isNot(contains(Uri.encodeQueryComponent(_kFakePhone))));
    expect(blob, isNot(contains(_kFakeLogin)));
    expect(blob, isNot(contains(_kFakeToken)));
    expect(blob.toLowerCase(), isNot(contains('authorization')));
    expect(blob, isNot(contains('Bearer')));
    expect(blob, contains('GET'));
    expect(blob, contains('/users/search'));
    expect(blob, contains('500'));
    expect(blob, contains('phone=REDACTED'));
  });
}
