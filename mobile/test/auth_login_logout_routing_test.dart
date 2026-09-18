import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/auth/data/storage/auth_token_storage.dart';
import 'package:mobile/features/auth/models/auth_account.dart';
import 'package:mobile/features/auth/models/auth_session.dart';
import 'package:mobile/features/auth/models/session_tokens.dart';
import 'package:mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:mobile/features/auth/providers/auth_providers.dart';
import 'package:mobile/features/auth/services/auth_api_service.dart';
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

class _RoutingApi extends AuthApiService {
  _RoutingApi() : super(ApiClient(config: const AppConfig(apiBaseUrl: 'http://test.invalid')));

  int loginCalls = 0;
  bool failLogin = false;
  String loginError = 'Invalid credentials';

  @override
  Future<AuthSession> login({
    required String login,
    required String password,
  }) async {
    loginCalls += 1;
    if (failLogin) {
      throw ApiException(message: loginError, statusCode: 401);
    }
    return AuthSession(
      message: 'ok',
      tokens: const SessionTokens(
        accessToken: 'access-login',
        refreshToken: 'refresh-login',
      ),
      user: AuthAccount(
        id: 1,
        login: login,
        authProvider: 'local',
        email: 'ada@example.com',
        phoneVerified: true,
      ),
    );
  }
}

Finder get _carousel => find.text('Discover');
Finder get _loginCopy => find.text('Sign in to continue to Lumina.');

Future<void> _pumpApp(
  WidgetTester tester, {
  required InMemoryAuthTokenStorage storage,
  required _RoutingApi api,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authTokenStorageProvider.overrideWithValue(storage),
        authApiServiceProvider.overrideWithValue(api),
      ],
      child: const LuminaApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _openLoginFromCarousel(WidgetTester tester) async {
  expect(_carousel, findsOneWidget);
  await tester.tap(find.text('Skip'));
  await tester.pumpAndSettle();
  expect(find.byType(LoginScreen), findsOneWidget);
  expect(_loginCopy, findsOneWidget);
}

Future<void> _submitLogin(
  WidgetTester tester, {
  required String login,
  required String password,
}) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), login);
  await tester.enterText(fields.at(1), password);
  await tester.tap(find.text('Sign in'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('cold start without session shows the Welcome carousel', (tester) async {
    await _pumpApp(
      tester,
      storage: InMemoryAuthTokenStorage(),
      api: _RoutingApi(),
    );

    expect(_carousel, findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('incorrect login stays on LoginScreen with an error and no carousel', (
    tester,
  ) async {
    final api = _RoutingApi()
      ..failLogin = true
      ..loginError = 'Invalid credentials';

    await _pumpApp(
      tester,
      storage: InMemoryAuthTokenStorage(),
      api: api,
    );
    await _openLoginFromCarousel(tester);
    await _submitLogin(tester, login: 'wrong', password: 'wrong');
    await tester.pumpAndSettle();

    expect(api.loginCalls, 1);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(_loginCopy, findsOneWidget);
    expect(find.text('Invalid credentials'), findsOneWidget);
    expect(_carousel, findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('incorrect login with empty API message uses the local fallback', (
    tester,
  ) async {
    final api = _RoutingApi()
      ..failLogin = true
      ..loginError = '  ';

    await _pumpApp(
      tester,
      storage: InMemoryAuthTokenStorage(),
      api: api,
    );
    await _openLoginFromCarousel(tester);
    await _submitLogin(tester, login: 'wrong', password: 'wrong');
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Incorrect login or password'), findsOneWidget);
    expect(_carousel, findsNothing);
  });

  testWidgets('correct login opens Home V1', (tester) async {
    final api = _RoutingApi();
    await _pumpApp(
      tester,
      storage: InMemoryAuthTokenStorage(),
      api: api,
    );
    await _openLoginFromCarousel(tester);
    await _submitLogin(tester, login: 'ada', password: 'password1');
    await tester.pumpAndSettle();

    expect(api.loginCalls, 1);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('ada'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(_carousel, findsNothing);
  });
}
