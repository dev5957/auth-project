import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/auth/services/google_identity_service.dart';

void main() {
  test('unconfigured client does not open Google Sign-In', () async {
    final service = GoogleIdentityService(serverClientId: null);
    final result = await service.signIn();
    expect(result, isA<GoogleIdentityFailure>());
    expect((result as GoogleIdentityFailure).message, 'Google Sign-In is not configured');
  });

  test('success toString omits the id token', () {
    const result = GoogleIdentitySuccess(
      idToken: 'secret-id-token',
      email: 'ada@example.com',
      displayName: 'Ada',
    );
    expect(result.toString(), contains('ada@example.com'));
    expect(result.toString(), isNot(contains('secret-id-token')));
    expect(result.toString(), contains('idToken: (omitted)'));
  });
}
