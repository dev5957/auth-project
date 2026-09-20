import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/features/auth/data/storage/auth_token_storage.dart';
import 'package:mobile/features/auth/models/auth_user.dart';
import 'package:mobile/features/auth/models/google_start_result.dart';
import 'package:mobile/features/auth/models/session_tokens.dart';
import 'package:mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:mobile/features/auth/presentation/screens/oauth_complete_screen.dart';
import 'package:mobile/features/auth/presentation/screens/register_screen.dart';
import 'package:mobile/features/auth/presentation/screens/signup_method_screen.dart';
import 'package:mobile/features/auth/providers/auth_controller.dart';
import 'package:mobile/features/auth/providers/auth_providers.dart';
import 'package:mobile/features/auth/services/auth_api_service.dart';
import 'package:mobile/features/auth/services/google_identity_service.dart';
import 'package:mobile/features/auth/state/auth_state.dart';
import 'package:mobile/features/home/presentation/screens/home_screen.dart';
import 'package:mobile/main.dart';

class InMemoryAuthTokenStorage implements AuthTokenStorage {
  String? _accessToken;
  String? _refreshToken;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
  }

  @override
  Future<bool> hasRefreshToken() async {
    return _refreshToken != null && _refreshToken!.isNotEmpty;
  }
}

class _SignupApi extends AuthApiService {
  _SignupApi() : super(ApiClient(config: const AppConfig(apiBaseUrl: 'http://test.invalid')));

  GoogleStartResult? startResult;
  int googleStartCalls = 0;
  int meCalls = 0;

  @override
  Future<GoogleStartResult> googleStart({required String idToken}) async {
    googleStartCalls += 1;
    return startResult!;
  }

  @override
  Future<AuthUser> me({required String accessToken}) async {
    meCalls += 1;
    return const AuthUser(userId: 7, login: 'ada', authProvider: 'google');
  }
}

class _ScriptedGoogleIdentity extends GoogleIdentityService {
  _ScriptedGoogleIdentity(this._result)
      : super(serverClientId: 'test.apps.googleusercontent.com');

  final GoogleIdentityResult _result;
  int calls = 0;

  @override
  Future<GoogleIdentityResult> signIn() async {
    calls += 1;
    return _result;
  }
}

Finder get _carousel => find.text('Discover');
Finder get _chooseCopy => find.text('Choose how to create your account');

Future<ProviderContainer> _openApp(
  WidgetTester tester, {
  required _SignupApi api,
  required GoogleIdentityService google,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authTokenStorageProvider.overrideWithValue(InMemoryAuthTokenStorage()),
        authApiServiceProvider.overrideWithValue(api),
        googleIdentityServiceProvider.overrideWithValue(google),
      ],
      child: const LuminaApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
  expect(_carousel, findsOneWidget);
  return ProviderScope.containerOf(tester.element(find.byType(LuminaApp)));
}

Future<void> _openSignupMethod(WidgetTester tester) async {
  final pageView = tester.widget<PageView>(find.byType(PageView));
  pageView.controller!.jumpToPage(4);
  await tester.pumpAndSettle();
  expect(find.text('Get Started'), findsOneWidget);
  await tester.tap(find.text('Get Started'));
  await tester.pumpAndSettle();
  expect(find.byType(SignupMethodScreen), findsOneWidget);
  expect(_chooseCopy, findsOneWidget);
  expect(find.text('Step 1 of 4 · Personal'), findsNothing);
}

void _expectNoApiUrl() {
  expect(find.textContaining('API:'), findsNothing);
  expect(find.textContaining('http://'), findsNothing);
  expect(find.textContaining(':3000'), findsNothing);
}

void main() {
  const identity = GoogleIdentitySuccess(
    idToken: 'secret-id-token',
    email: 'ada@example.com',
  );

  testWidgets('Get Started opens choose method instead of Register', (tester) async {
    await _openApp(
      tester,
      api: _SignupApi(),
      google: _ScriptedGoogleIdentity(const GoogleIdentityCanceled()),
    );
    await _openSignupMethod(tester);
    _expectNoApiUrl();
  });

  testWidgets('choose email/password opens Register step 1 without API URL', (tester) async {
    await _openApp(
      tester,
      api: _SignupApi(),
      google: _ScriptedGoogleIdentity(const GoogleIdentityCanceled()),
    );
    await _openSignupMethod(tester);

    await tester.tap(find.text('Continue with email / password'));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.text('Step 1 of 4 · Personal'), findsOneWidget);
    _expectNoApiUrl();
  });

  testWidgets('choose Google on first tap starts Google Sign-In for a new account', (tester) async {
    final api = _SignupApi()
      ..startResult = const GoogleStartPending(
        email: 'ada@example.com',
        oauthVerificationToken: 'oauth-pending-token',
      );
    final google = _ScriptedGoogleIdentity(identity);
    await _openApp(tester, api: api, google: google);
    await _openSignupMethod(tester);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(google.calls, 1);
    expect(api.googleStartCalls, 1);
    expect(find.byType(OAuthCompleteScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(_carousel, findsNothing);
    expect(find.text('Google id_token is missing'), findsNothing);
  });

  testWidgets('choose Google with existing account opens Home', (tester) async {
    final api = _SignupApi()
      ..startResult = const GoogleStartExisting(
        message: 'Login successful',
        tokens: SessionTokens(
          accessToken: 'access-google',
          refreshToken: 'refresh-google',
        ),
      );
    final google = _ScriptedGoogleIdentity(identity);
    final container = await _openApp(tester, api: api, google: google);
    await _openSignupMethod(tester);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(google.calls, 1);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OAuthCompleteScreen), findsNothing);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('choose Apple stays on choose method without crashing', (tester) async {
    await _openApp(
      tester,
      api: _SignupApi(),
      google: _ScriptedGoogleIdentity(const GoogleIdentityCanceled()),
    );
    await _openSignupMethod(tester);

    await tester.tap(find.text('Continue with Apple'));
    await tester.pumpAndSettle();

    expect(find.byType(SignupMethodScreen), findsOneWidget);
    expect(_chooseCopy, findsOneWidget);
    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('Skip still opens Login with Google and Sign in unchanged', (tester) async {
    await _openApp(
      tester,
      api: _SignupApi(),
      google: _ScriptedGoogleIdentity(const GoogleIdentityCanceled()),
    );
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.byType(SignupMethodScreen), findsNothing);
    expect(find.text('Step 1 of 4 · Personal'), findsNothing);
    _expectNoApiUrl();
  });
}
