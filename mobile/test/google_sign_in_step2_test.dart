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

class _GoogleApi extends AuthApiService {
  _GoogleApi() : super(ApiClient(config: const AppConfig(apiBaseUrl: 'http://test.invalid')));

  int googleStartCalls = 0;
  int meCalls = 0;
  int loginCalls = 0;
  GoogleStartResult? startResult;
  Object? startError;

  @override
  Future<GoogleStartResult> googleStart({required String idToken}) async {
    googleStartCalls += 1;
    final error = startError;
    if (error != null) {
      throw error;
    }
    return startResult!;
  }

  @override
  Future<AuthUser> me({required String accessToken}) async {
    meCalls += 1;
    return const AuthUser(userId: 7, login: 'ada', authProvider: 'google');
  }

  @override
  Future<AuthSession> login({
    required String login,
    required String password,
  }) async {
    loginCalls += 1;
    throw StateError('local login should not run for Google');
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
Finder get _loginCopy => find.text('Sign in to continue to Lumina.');

Future<ProviderContainer> _openLogin(
  WidgetTester tester, {
  required GoogleIdentityService google,
  required _GoogleApi api,
  required InMemoryAuthTokenStorage storage,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authTokenStorageProvider.overrideWithValue(storage),
        authApiServiceProvider.overrideWithValue(api),
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
  const identity = GoogleIdentitySuccess(
    idToken: 'secret-id-token',
    email: 'ada@example.com',
  );

  testWidgets('existing Google account saves tokens, calls me, and opens Home', (tester) async {
    final api = _GoogleApi()
      ..startResult = const GoogleStartExisting(
        message: 'Login successful',
        tokens: SessionTokens(
          accessToken: 'access-google',
          refreshToken: 'refresh-google',
        ),
      );
    final storage = InMemoryAuthTokenStorage();
    final google = _ScriptedGoogleIdentity(identity);
    final container = await _openLogin(
      tester,
      google: google,
      api: api,
      storage: storage,
    );

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(google.calls, 1);
    expect(api.googleStartCalls, 1);
    expect(api.meCalls, 1);
    expect(api.loginCalls, 0);
    expect(await storage.readAccessToken(), 'access-google');
    expect(await storage.readRefreshToken(), 'refresh-google');
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('ada'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(_carousel, findsNothing);
    final auth = container.read(authControllerProvider);
    expect(auth, isA<AuthAuthenticated>());
    expect((auth as AuthAuthenticated).user.login, 'ada');
    expect(auth.user.authProvider, 'google');
  });

  testWidgets('unknown Google account stays pending without Home or tokens', (tester) async {
    final api = _GoogleApi()
      ..startResult = const GoogleStartPending(email: 'ada@example.com');
    final storage = InMemoryAuthTokenStorage();
    final google = _ScriptedGoogleIdentity(identity);
    final container = await _openLogin(
      tester,
      google: google,
      api: api,
      storage: storage,
    );

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(api.googleStartCalls, 1);
    expect(api.meCalls, 0);
    expect(api.loginCalls, 0);
    expect(await storage.readAccessToken(), isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(_loginCopy, findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(_carousel, findsNothing);
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });

  testWidgets('Google cancel stays on Login without Auth or carousel redirect', (tester) async {
    final api = _GoogleApi();
    final google = _ScriptedGoogleIdentity(const GoogleIdentityCanceled());
    final container = await _openLogin(
      tester,
      google: google,
      api: api,
      storage: InMemoryAuthTokenStorage(),
    );

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(google.calls, 1);
    expect(api.googleStartCalls, 0);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(_loginCopy, findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(_carousel, findsNothing);
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });

  testWidgets('Google backend error stays on Login with a message', (tester) async {
    final api = _GoogleApi()
      ..startError = const ApiException(
        message: 'Account already exists with another authentication method',
        statusCode: 409,
      );
    final google = _ScriptedGoogleIdentity(identity);
    final container = await _openLogin(
      tester,
      google: google,
      api: api,
      storage: InMemoryAuthTokenStorage(),
    );

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(api.googleStartCalls, 1);
    expect(api.meCalls, 0);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      find.text('Account already exists with another authentication method'),
      findsOneWidget,
    );
    expect(find.byType(HomeScreen), findsNothing);
    expect(_carousel, findsNothing);
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });
}
