import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:mobile/features/auth/services/google_identity_service.dart';

class _FakeGoogleSignIn extends Fake implements GoogleSignIn {
  int signOutCalls = 0;
  int signInCalls = 0;
  int silentCalls = 0;

  @override
  Future<GoogleSignInAccount?> signInSilently({
    bool suppressErrors = true,
    bool reAuthenticate = false,
  }) async {
    silentCalls += 1;
    return null;
  }

  @override
  Future<GoogleSignInAccount?> signIn() async {
    signInCalls += 1;
    return null;
  }

  @override
  Future<GoogleSignInAccount?> signOut() async {
    signOutCalls += 1;
    return null;
  }
}

void main() {
  test('first signIn does not signOut then fail before interactive Google', () async {
    final plugin = _FakeGoogleSignIn();
    final service = GoogleIdentityService(
      serverClientId: 'test.apps.googleusercontent.com',
      plugin: plugin,
    );

    final result = await service.signIn();

    expect(result, isA<GoogleIdentityCanceled>());
    expect(plugin.signOutCalls, 0);
    expect(plugin.silentCalls, 1);
    expect(plugin.signInCalls, 1);
  });

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
