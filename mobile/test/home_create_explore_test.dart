import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/features/auth/models/auth_account.dart';
import 'package:mobile/features/auth/providers/auth_controller.dart';
import 'package:mobile/features/auth/providers/auth_providers.dart';
import 'package:mobile/features/auth/services/auth_api_service.dart';
import 'package:mobile/features/auth/state/auth_state.dart';
import 'package:mobile/features/chronique/presentation/screens/create_placeholder_screen.dart';
import 'package:mobile/features/chronique/presentation/screens/explore_placeholder_screen.dart';
import 'package:mobile/features/home/presentation/screens/home_screen.dart';
import 'package:mobile/main.dart';

class _SeededHomeAuthController extends AuthController {
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
}

Future<void> _pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authApiServiceProvider.overrideWithValue(
          AuthApiService(
            ApiClient(config: const AppConfig(apiBaseUrl: 'http://test.invalid')),
          ),
        ),
        authControllerProvider.overrideWith(() => _SeededHomeAuthController()),
      ],
      child: const LuminaApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('CREATE opens the creation placeholder without leaving the session', (
    tester,
  ) async {
    await _pumpHome(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.tap(find.text('CREATE'));
    await tester.pumpAndSettle();

    expect(find.byType(CreatePlaceholderScreen), findsOneWidget);
    expect(find.byType(ExplorePlaceholderScreen), findsNothing);
    expect(find.text('CREATE'), findsWidgets);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LuminaApp)),
    );
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('EXPLORE opens the Chronique placeholder without leaving the session', (
    tester,
  ) async {
    await _pumpHome(tester);

    await tester.tap(find.text('EXPLORE'));
    await tester.pumpAndSettle();

    expect(find.byType(ExplorePlaceholderScreen), findsOneWidget);
    expect(find.byType(CreatePlaceholderScreen), findsNothing);
    expect(find.text('EXPLORE'), findsWidgets);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LuminaApp)),
    );
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('back from CREATE returns to Home V1 with Logout', (tester) async {
    await _pumpHome(tester);

    await tester.tap(find.text('CREATE'));
    await tester.pumpAndSettle();
    expect(find.byType(CreatePlaceholderScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(CreatePlaceholderScreen), findsNothing);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
    expect(find.text('CREATE'), findsOneWidget);
    expect(find.text('EXPLORE'), findsOneWidget);
  });
}
