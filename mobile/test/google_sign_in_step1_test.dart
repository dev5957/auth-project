import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/features/auth/data/storage/auth_token_storage.dart';
import 'package:mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:mobile/features/auth/providers/auth_controller.dart';
import 'package:mobile/features/auth/providers/auth_providers.dart';
import 'package:mobile/features/auth/services/auth_api_service.dart';
import 'package:mobile/features/auth/services/google_identity_service.dart';
import 'package:mobile/features/auth/state/auth_state.dart';
import 'package:mobile/features/home/presentation/screens/home_screen.dart';
import 'package:mobile/main.dart';

class InMemoryAuthTokenStorage implements AuthTokenStorage {
  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {}

  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> clearTokens() async {}

  @override
  Future<bool> hasRefreshToken() async => false;
}

class _IdleApi extends AuthApiService {
  _IdleApi() : super(ApiClient(config: const AppConfig(apiBaseUrl: 'http://test.invalid')));
}

class _ScriptedGoogleIdentity extends GoogleIdentityService {
  _ScriptedGoogleIdentity(this._result) : super(serverClientId: 'test.apps.googleusercontent.com');

  final GoogleIdentityResult _result;
  int calls = 0;

  @override
  Future<GoogleIdentityResult> signIn() async {
    calls += 1;
    return _result;
  }
}

Finder get _carousel => find.text('Discover');
Finder get _loginCopy => find.text('Sign in to continue to Lumina.');

Future<ProviderContainer> _openLogin(
  WidgetTester tester, {
  required GoogleIdentityService google,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authTokenStorageProvider.overrideWithValue(InMemoryAuthTokenStorage()),
        authApiServiceProvider.overrideWithValue(_IdleApi()),
        googleIdentityServiceProvider.overrideWithValue(google),
      ],
      child: const LuminaApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
  expect(_carousel, findsOneWidget);
  await tester.tap(find.text('Skip'));
  await tester.pumpAndSettle();
  expect(find.byType(LoginScreen), findsOneWidget);
  return ProviderScope.containerOf(tester.element(find.byType(LuminaApp)));
}

void main() {
  testWidgets('Google success stays on Login and does not open Home', (tester) async {
    final google = _ScriptedGoogleIdentity(
      const GoogleIdentitySuccess(
        idToken: 'secret-id-token',
        email: 'ada@example.com',
      ),
    );
    final container = await _openLogin(tester, google: google);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(google.calls, 1);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(_loginCopy, findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(_carousel, findsNothing);
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });

  testWidgets('Google cancel stays on Login without Auth or carousel redirect', (tester) async {
    final google = _ScriptedGoogleIdentity(const GoogleIdentityCanceled());
    final container = await _openLogin(tester, google: google);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(google.calls, 1);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(_loginCopy, findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(_carousel, findsNothing);
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });
}
