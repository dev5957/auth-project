import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/features/auth/data/storage/auth_token_storage.dart';
import 'package:mobile/features/auth/models/auth_account.dart';
import 'package:mobile/features/auth/providers/auth_controller.dart';
import 'package:mobile/features/auth/providers/auth_providers.dart';
import 'package:mobile/features/auth/state/auth_state.dart';
import 'package:mobile/features/chronique/models/chronique_page.dart';
import 'package:mobile/features/chronique/presentation/screens/create_chronique_screen.dart';
import 'package:mobile/features/chronique/presentation/screens/mon_fil_screen.dart';
import 'package:mobile/features/chronique/providers/chronique_providers.dart';
import 'package:mobile/features/chronique/services/chronique_api_service.dart';
import 'package:mobile/features/home/presentation/screens/home_screen.dart';
import 'package:mobile/main.dart';

class InMemoryAuthTokenStorage implements AuthTokenStorage {
  InMemoryAuthTokenStorage({
    String? accessToken,
    String? refreshToken,
  })  : _accessToken = accessToken,
        _refreshToken = refreshToken;

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

class _ChroniqueApiProbe extends ChroniqueApiService {
  _ChroniqueApiProbe()
      : super(ApiClient(config: const AppConfig(apiBaseUrl: 'http://test.invalid')));

  int listCalls = 0;

  @override
  Future<ChroniquePage> list({required String accessToken}) async {
    listCalls += 1;
    return const ChroniquePage(items: []);
  }
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required _ChroniqueApiProbe api,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authTokenStorageProvider.overrideWithValue(
          InMemoryAuthTokenStorage(
            accessToken: 'access-test',
            refreshToken: 'refresh-test',
          ),
        ),
        authControllerProvider.overrideWith(() => _SeededHomeAuthController()),
        chroniqueApiServiceProvider.overrideWithValue(api),
      ],
      child: const LuminaApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('CREATE opens the creation assistant without leaving the session', (
    tester,
  ) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);

    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.tap(find.text('CREATE'));
    await tester.pumpAndSettle();

    expect(find.byType(CreateChroniqueScreen), findsOneWidget);
    expect(find.text('Créer une chronique'), findsOneWidget);
    expect(find.byType(MonFilScreen), findsNothing);
    expect(api.listCalls, 0);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LuminaApp)),
    );
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('EXPLORE opens Mon Fil without leaving the session', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);

    await tester.tap(find.text('EXPLORE'));
    await tester.pumpAndSettle();

    expect(find.byType(MonFilScreen), findsOneWidget);
    expect(find.text('Mon Fil'), findsOneWidget);
    expect(find.byType(CreateChroniqueScreen), findsNothing);
    expect(api.listCalls, 1);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LuminaApp)),
    );
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('back from CREATE returns to Home V1 with Logout', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);

    await tester.tap(find.text('CREATE'));
    await tester.pumpAndSettle();
    expect(find.byType(CreateChroniqueScreen), findsOneWidget);

    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(CreateChroniqueScreen), findsNothing);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
    expect(find.text('CREATE'), findsOneWidget);
    expect(find.text('EXPLORE'), findsOneWidget);
    expect(api.listCalls, 0);
  });
}
