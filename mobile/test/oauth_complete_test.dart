import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/auth/data/storage/auth_token_storage.dart';
import 'package:mobile/features/auth/models/auth_session.dart';
import 'package:mobile/features/auth/models/auth_user.dart';
import 'package:mobile/features/auth/models/google_start_result.dart';
import 'package:mobile/features/auth/models/session_tokens.dart';
import 'package:mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:mobile/features/auth/presentation/screens/oauth_complete_screen.dart';
import 'package:mobile/features/auth/presentation/state/oauth_complete_flow_controller.dart';
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

class _OAuthApi extends AuthApiService {
  _OAuthApi() : super(ApiClient(config: const AppConfig(apiBaseUrl: 'http://test.invalid')));

  int googleStartCalls = 0;
  int startPhoneCalls = 0;
  int verifyPhoneCalls = 0;
  int meCalls = 0;
  int loginCalls = 0;
  bool failOtp = false;
  String? lastStartToken;
  String? lastPhoneNumber;
  String? lastVerifyToken;
  String? lastVerifyCode;
  String? lastBirthDate;
  String? lastLogin;

  @override
  Future<GoogleStartResult> googleStart({required String idToken}) async {
    googleStartCalls += 1;
    return const GoogleStartPending(
      email: 'ada@example.com',
      oauthVerificationToken: 'oauth-start-token',
    );
  }

  @override
  Future<String> oauthStartPhone({
    required String oauthVerificationToken,
    required String phoneNumber,
  }) async {
    startPhoneCalls += 1;
    lastStartToken = oauthVerificationToken;
    lastPhoneNumber = phoneNumber;
    return 'oauth-phone-token';
  }

  @override
  Future<SessionTokens> oauthVerifyPhone({
    required String oauthVerificationToken,
    required String code,
    required String birthDate,
    required String login,
  }) async {
    verifyPhoneCalls += 1;
    lastVerifyToken = oauthVerificationToken;
    lastVerifyCode = code;
    lastBirthDate = birthDate;
    lastLogin = login;
    if (failOtp || code != '123456') {
      throw const ApiException(message: 'Invalid verification code', statusCode: 400);
    }
    return const SessionTokens(
      accessToken: 'access-oauth',
      refreshToken: 'refresh-oauth',
    );
  }

  @override
  Future<AuthUser> me({required String accessToken}) async {
    meCalls += 1;
    return const AuthUser(userId: 9, login: 'ada-public', authProvider: 'google');
  }

  @override
  Future<AuthSession> login({
    required String login,
    required String password,
  }) async {
    loginCalls += 1;
    throw StateError('local login should not run');
  }
}

class _ScriptedGoogleIdentity extends GoogleIdentityService {
  _ScriptedGoogleIdentity() : super(serverClientId: 'test.apps.googleusercontent.com');

  @override
  Future<GoogleIdentityResult> signIn() async {
    return const GoogleIdentitySuccess(
      idToken: 'secret-id-token',
      email: 'ada@example.com',
    );
  }
}

Finder get _carousel => find.text('Discover');

Future<ProviderContainer> _openPendingComplete(WidgetTester tester, _OAuthApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authTokenStorageProvider.overrideWithValue(InMemoryAuthTokenStorage()),
        authApiServiceProvider.overrideWithValue(api),
        googleIdentityServiceProvider.overrideWithValue(_ScriptedGoogleIdentity()),
      ],
      child: const LuminaApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.tap(find.text('Skip'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue with Google'));
  await tester.pumpAndSettle();
  expect(find.byType(OAuthCompleteScreen), findsOneWidget);
  return ProviderScope.containerOf(tester.element(find.byType(LuminaApp)));
}

Future<void> _fillProfileThroughLogin(
  WidgetTester tester, {
  String otp = '123456',
}) async {
  await tester.enterText(find.byType(TextField), '+33612345678');
  await tester.tap(find.text('Send code'));
  await tester.pumpAndSettle();
  expect(find.text('Enter the code'), findsOneWidget);

  await tester.enterText(find.byType(TextField), otp);
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  expect(find.textContaining('Required by the app'), findsOneWidget);

  await tester.enterText(find.byType(TextField), '2000-01-15');
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  expect(find.textContaining('This is how you appear'), findsOneWidget);

  await tester.enterText(find.byType(TextField), 'ada-public');
}

void main() {
  testWidgets('new Google account completes profile then opens Home', (tester) async {
    final api = _OAuthApi();
    final container = await _openPendingComplete(tester, api);
    await _fillProfileThroughLogin(tester);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(api.googleStartCalls, 1);
    expect(api.startPhoneCalls, 1);
    expect(api.lastStartToken, 'oauth-start-token');
    expect(api.lastPhoneNumber, '+33612345678');
    expect(api.verifyPhoneCalls, 1);
    expect(api.lastVerifyToken, 'oauth-phone-token');
    expect(api.lastVerifyCode, '123456');
    expect(api.lastBirthDate, '2000-01-15');
    expect(api.lastLogin, 'ada-public');
    expect(api.meCalls, 1);
    expect(api.loginCalls, 0);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('ada-public'), findsOneWidget);
    expect(find.byType(OAuthCompleteScreen), findsNothing);
    expect(_carousel, findsNothing);
    final auth = container.read(authControllerProvider);
    expect(auth, isA<AuthAuthenticated>());
    expect((auth as AuthAuthenticated).user.authProvider, 'google');
  });

  testWidgets('wrong OTP stays in OAuth complete without carousel', (tester) async {
    final api = _OAuthApi()..failOtp = true;
    final container = await _openPendingComplete(tester, api);
    await _fillProfileThroughLogin(tester);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(api.verifyPhoneCalls, 1);
    expect(api.meCalls, 0);
    expect(find.byType(OAuthCompleteScreen), findsOneWidget);
    expect(find.text('Invalid verification code'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(_carousel, findsNothing);
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });

  test('OAuth complete flow toString omits the verification token', () {
    const state = OAuthCompleteFlowState(
      email: 'ada@example.com',
      oauthVerificationToken: 'oauth-secret-token',
    );
    expect(state.toString(), contains('ada@example.com'));
    expect(state.toString(), isNot(contains('oauth-secret-token')));
  });
}
