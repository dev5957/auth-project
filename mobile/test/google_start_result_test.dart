import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/auth/models/google_start_result.dart';
import 'package:mobile/features/auth/models/session_tokens.dart';

void main() {
  test('existing Google payload toString omits tokens', () {
    const existing = GoogleStartExisting(
      message: 'Login successful',
      tokens: SessionTokens(accessToken: 'access', refreshToken: 'refresh'),
    );
    expect(existing.toString(), isNot(contains('access')));
    expect(existing.toString(), isNot(contains('refresh')));
  });

  test('pending Google payload is a result, not an error type', () {
    const pending = GoogleStartPending(email: 'ada@example.com');
    expect(pending, isA<GoogleStartResult>());
    expect(pending, isNot(isA<GoogleStartExisting>()));
    expect(pending.toString(), contains('ada@example.com'));
    expect(pending.toString(), isNot(contains('oauth')));
  });
}
