import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/router/session_splash_screen.dart';
import 'package:mobile/features/auth/data/storage/auth_token_storage.dart';
import 'package:mobile/features/auth/models/auth_account.dart';
import 'package:mobile/features/auth/models/auth_session.dart';
import 'package:mobile/features/auth/models/session_tokens.dart';
import 'package:mobile/features/auth/providers/auth_controller.dart';
import 'package:mobile/features/auth/providers/auth_providers.dart';
import 'package:mobile/features/auth/services/auth_api_service.dart';
import 'package:mobile/features/auth/state/auth_state.dart';
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

class _FakeAuthApi extends AuthApiService {
  _FakeAuthApi() : super(ApiClient(config: const AppConfig(apiBaseUrl: 'http://test.invalid')));

  int refreshCalls = 0;
  int logoutCalls = 0;
  String? lastRefreshToken;
  bool failRefresh = false;
  bool failLogout = false;
  Duration refreshDelay = Duration.zero;

  AuthSession _session({
    required String accessToken,
    required String refreshToken,
    String login = 'ada',
  }) {
    return AuthSession(
      message: 'ok',
      tokens: SessionTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
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

  @override
  Future<AuthSession> login({
    required String login,
    required String password,
  }) async {
    return _session(
      accessToken: 'access-login',
      refreshToken: 'refresh-login',
      login: login,
    );
  }

  @override
  Future<AuthSession> refresh({required String refreshToken}) async {
    refreshCalls += 1;
    lastRefreshToken = refreshToken;
    if (refreshDelay > Duration.zero) {
      await Future<void>.delayed(refreshDelay);
    }
    if (failRefresh) {
      throw const ApiException(message: 'Invalid refresh token', statusCode: 401);
    }
    return _session(
      accessToken: 'access-rotated',
      refreshToken: 'refresh-rotated',
    );
  }

  @override
  Future<void> logout({
    required String accessToken,
    required String refreshToken,
  }) async {
    logoutCalls += 1;
    if (failLogout) {
      throw const ApiException(message: 'Unauthorized', statusCode: 401);
    }
  }
}

ProviderContainer _container({
  required InMemoryAuthTokenStorage storage,
  required _FakeAuthApi api,
}) {
  return ProviderContainer(
    overrides: [
      authTokenStorageProvider.overrideWithValue(storage),
      authApiServiceProvider.overrideWithValue(api),
    ],
  );
}

Future<void> _waitUntilSettled(ProviderContainer container) async {
  container.read(authControllerProvider);
  for (var i = 0; i < 20; i++) {
    if (container.read(authControllerProvider) is! AuthLoading) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('AuthController stayed in AuthLoading');
}

void main() {
  test('login persists access_token and refresh_token', () async {
    final storage = InMemoryAuthTokenStorage();
    final api = _FakeAuthApi();
    final container = _container(storage: storage, api: api);
    addTearDown(container.dispose);

    await _waitUntilSettled(container);
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
    expect(api.refreshCalls, 0);

    await container.read(authControllerProvider.notifier).login(
          login: 'ada',
          password: 'password1',
        );

    expect(await storage.readAccessToken(), 'access-login');
    expect(await storage.readRefreshToken(), 'refresh-login');
    final state = container.read(authControllerProvider);
    expect(state, isA<AuthAuthenticated>());
    expect((state as AuthAuthenticated).user.login, 'ada');
  });

  test('restart with refresh_token calls refresh and restores the user', () async {
    final storage = InMemoryAuthTokenStorage();
    await storage.saveTokens(
      accessToken: 'access-stale',
      refreshToken: 'refresh-stored',
    );
    final api = _FakeAuthApi();
    final container = _container(storage: storage, api: api);
    addTearDown(container.dispose);

    await _waitUntilSettled(container);

    expect(api.refreshCalls, 1);
    expect(api.lastRefreshToken, 'refresh-stored');
    expect(await storage.readAccessToken(), 'access-rotated');
    expect(await storage.readRefreshToken(), 'refresh-rotated');
    final state = container.read(authControllerProvider);
    expect(state, isA<AuthAuthenticated>());
    expect((state as AuthAuthenticated).user.login, 'ada');
  });

  test('no refresh_token leaves the user unauthenticated without refresh', () async {
    final storage = InMemoryAuthTokenStorage();
    final api = _FakeAuthApi();
    final container = _container(storage: storage, api: api);
    addTearDown(container.dispose);

    await _waitUntilSettled(container);

    expect(api.refreshCalls, 0);
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });

  test('failed refresh clears tokens and signs the user out', () async {
    final storage = InMemoryAuthTokenStorage();
    await storage.saveTokens(
      accessToken: 'access-stale',
      refreshToken: 'refresh-invalid',
    );
    final api = _FakeAuthApi()..failRefresh = true;
    final container = _container(storage: storage, api: api);
    addTearDown(container.dispose);

    await _waitUntilSettled(container);

    expect(api.refreshCalls, 1);
    expect(await storage.readAccessToken(), isNull);
    expect(await storage.readRefreshToken(), isNull);
    expect(await storage.hasRefreshToken(), isFalse);
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });

  test('logout clears secure storage even if the API returns an expected error', () async {
    final storage = InMemoryAuthTokenStorage();
    final api = _FakeAuthApi()..failLogout = true;
    final container = _container(storage: storage, api: api);
    addTearDown(container.dispose);

    await _waitUntilSettled(container);
    await container.read(authControllerProvider.notifier).login(
          login: 'ada',
          password: 'password1',
        );
    expect(await storage.hasRefreshToken(), isTrue);

    await container.read(authControllerProvider.notifier).logout();

    expect(api.logoutCalls, 1);
    expect(await storage.readAccessToken(), isNull);
    expect(await storage.readRefreshToken(), isNull);
    expect(await storage.hasRefreshToken(), isFalse);
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });

  testWidgets('AuthLoading shows splash and never the onboarding carousel', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_StuckLoadingAuthController.new),
        ],
        child: const LuminaApp(),
      ),
    );
    await tester.pump();

    _expectSplashWithoutCarousel();
  });

  testWidgets('cold start with refresh_token shows splash then Home', (tester) async {
    final storage = InMemoryAuthTokenStorage();
    await storage.saveTokens(
      accessToken: 'access-stale',
      refreshToken: 'refresh-stored',
    );
    final api = _FakeAuthApi()..refreshDelay = const Duration(milliseconds: 200);

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
    _expectSplashWithoutCarousel();

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(api.refreshCalls, 1);
    expect(api.lastRefreshToken, 'refresh-stored');
    expect(find.text('Home placeholder'), findsOneWidget);
    expect(_carousel(), findsNothing);
    expect(find.byType(SessionSplashScreen), findsNothing);
  });

  testWidgets('cold start without refresh_token skips refresh and shows Welcome', (tester) async {
    final storage = InMemoryAuthTokenStorage();
    final api = _FakeAuthApi();

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

    expect(api.refreshCalls, 0);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Home placeholder'), findsNothing);
  });

  testWidgets('failed refresh on cold start clears tokens and shows Welcome', (tester) async {
    final storage = InMemoryAuthTokenStorage();
    await storage.saveTokens(
      accessToken: 'access-stale',
      refreshToken: 'refresh-invalid',
    );
    final api = _FakeAuthApi()..failRefresh = true;

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

    expect(api.refreshCalls, 1);
    expect(await storage.hasRefreshToken(), isFalse);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Home placeholder'), findsNothing);
  });
}

class _StuckLoadingAuthController extends AuthController {
  @override
  AuthState build() => const AuthLoading();
}

Finder _carousel() => find.text('Discover');

void _expectSplashWithoutCarousel() {
  expect(find.byType(SessionSplashScreen), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
  expect(_carousel(), findsNothing);
  expect(find.text('Welcome to Lumina'), findsNothing);
  expect(find.text('Home placeholder'), findsNothing);
}
