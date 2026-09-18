import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/widgets/app_button.dart';
import 'package:mobile/features/auth/models/auth_account.dart';
import 'package:mobile/features/auth/models/auth_user.dart';
import 'package:mobile/features/auth/providers/auth_controller.dart';
import 'package:mobile/features/auth/providers/auth_providers.dart';
import 'package:mobile/features/auth/services/auth_api_service.dart';
import 'package:mobile/features/auth/state/auth_state.dart';
import 'package:mobile/features/home/presentation/home_user_initials.dart';
import 'package:mobile/features/home/presentation/screens/home_screen.dart';
import 'package:mobile/main.dart';

class _ApiProbe extends AuthApiService {
  _ApiProbe() : super(ApiClient(config: const AppConfig(apiBaseUrl: 'http://test.invalid')));

  int meCalls = 0;
  int refreshCalls = 0;
  int loginCalls = 0;
  int logoutCalls = 0;

  @override
  Future<AuthUser> me({required String accessToken}) async {
    meCalls += 1;
    return const AuthUser(userId: 1, login: 'tgjjk', authProvider: 'local');
  }

  @override
  Future<Never> refresh({required String refreshToken}) async {
    refreshCalls += 1;
    throw StateError('refresh should not run on Home display');
  }

  @override
  Future<Never> login({required String login, required String password}) async {
    loginCalls += 1;
    throw StateError('login should not run on Home display');
  }

  @override
  Future<void> logout({
    required String accessToken,
    required String refreshToken,
  }) async {
    logoutCalls += 1;
  }
}

class _LogoutProbe {
  int calls = 0;
}

class _SeededHomeAuthController extends AuthController {
  _SeededHomeAuthController(
    this.probe, {
    this.logoutDelay = Duration.zero,
  });

  final _LogoutProbe probe;
  final Duration logoutDelay;

  @override
  AuthState build() {
    return const AuthAuthenticated(
      user: AuthAccount(
        id: 1,
        login: 'tgjjk',
        authProvider: 'local',
        email: 'ada@example.com',
        phoneVerified: true,
      ),
    );
  }

  @override
  Future<void> logout() async {
    probe.calls += 1;
    if (logoutDelay > Duration.zero) {
      await Future<void>.delayed(logoutDelay);
    }
    state = const AuthUnauthenticated();
  }
}

void main() {
  test('home initials use the login without inventing a name', () {
    expect(homeUserInitials('tgjjk'), 'TG');
    expect(homeUserInitials(' ada '), 'AD');
    expect(homeUserInitials('x'), 'X');
    expect(homeUserInitials(''), '');
  });

  testWidgets('authenticated session shows Home with the user login', (tester) async {
    final api = _ApiProbe();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authApiServiceProvider.overrideWithValue(api),
          authControllerProvider.overrideWith(
            () => _SeededHomeAuthController(_LogoutProbe()),
          ),
        ],
        child: const LuminaApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('tgjjk'), findsOneWidget);
    expect(find.text('Session active'), findsOneWidget);
    expect(find.text('Your space'), findsOneWidget);
    expect(find.text('Everything is ready.'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
    expect(api.meCalls, 0);
    expect(api.refreshCalls, 0);
    expect(api.loginCalls, 0);
    expect(api.logoutCalls, 0);
  });

  testWidgets('Logout uses AuthController and returns to Login, not the carousel', (tester) async {
    final api = _ApiProbe();
    final probe = _LogoutProbe();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authApiServiceProvider.overrideWithValue(api),
          authControllerProvider.overrideWith(
            () => _SeededHomeAuthController(probe),
          ),
        ],
        child: const LuminaApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LuminaApp)),
    );
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());

    await tester.tap(find.text('Logout'));
    var leftHome = false;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Sign in to continue to Lumina.').evaluate().isNotEmpty &&
          find.byType(HomeScreen).evaluate().isEmpty) {
        leftHome = true;
        break;
      }
    }

    expect(probe.calls, 1);
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
    expect(leftHome, isTrue);
    expect(find.text('Sign in to continue to Lumina.'), findsOneWidget);
    expect(find.text('Discover'), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
    expect(api.meCalls, 0);
  });

  testWidgets('Logout ignores a second tap while loading', (tester) async {
    final probe = _LogoutProbe();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => _SeededHomeAuthController(
              probe,
              logoutDelay: const Duration(milliseconds: 200),
            ),
          ),
        ],
        child: const LuminaApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    final logoutInk = find.descendant(
      of: find.byType(AppButton),
      matching: find.byType(InkWell),
    );
    await tester.tap(logoutInk);
    await tester.pump();
    await tester.tap(logoutInk);
    await tester.pump(const Duration(milliseconds: 50));
    expect(probe.calls, 1);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
  });
}
