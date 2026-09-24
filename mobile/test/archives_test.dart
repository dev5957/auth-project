import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/auth/data/storage/auth_token_storage.dart';
import 'package:mobile/features/auth/models/auth_account.dart';
import 'package:mobile/features/auth/providers/auth_controller.dart';
import 'package:mobile/features/auth/providers/auth_providers.dart';
import 'package:mobile/features/auth/state/auth_state.dart';
import 'package:mobile/features/chronique/models/chronique.dart';
import 'package:mobile/features/chronique/models/chronique_date.dart';
import 'package:mobile/features/chronique/models/chronique_page.dart';
import 'package:mobile/features/chronique/presentation/screens/archives_screen.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_card.dart';
import 'package:mobile/features/chronique/providers/chronique_providers.dart';
import 'package:mobile/features/chronique/services/chronique_api_service.dart';
import 'package:mobile/features/home/presentation/screens/home_screen.dart';
import 'package:mobile/features/home/presentation/widgets/home_user_menu.dart';
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
  String? lastAccessToken;
  String? lastListStatus;
  List<Chronique> archivedItems = const [];
  ApiException? failWith;

  @override
  Future<ChroniquePage> list({
    required String accessToken,
    String? status,
  }) async {
    listCalls += 1;
    lastAccessToken = accessToken;
    lastListStatus = status;
    final error = failWith;
    if (error != null) {
      throw error;
    }
    if (status == 'archived') {
      return ChroniquePage(items: archivedItems);
    }
    return const ChroniquePage(items: []);
  }
}

Future<ProviderContainer> _pumpHome(
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
  return ProviderScope.containerOf(tester.element(find.byType(LuminaApp)));
}

Future<void> _openArchives(WidgetTester tester) async {
  expect(find.byType(HomeScreen), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('home-user-avatar')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Archives'));
  await tester.pumpAndSettle();
  expect(find.byType(ArchivesScreen), findsOneWidget);
}

void main() {
  testWidgets('inactive menu items show a coming-soon message', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('home-user-avatar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profil'));
    await tester.pump();
    expect(find.text(kSoonAvailableMessage), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Archives navigates from avatar and calls GET status=archived', (
    tester,
  ) async {
    final api = _ChroniqueApiProbe();
    final container = await _pumpHome(tester, api: api);
    await _openArchives(tester);

    expect(find.text('Archives'), findsWidgets);
    expect(api.listCalls, 1);
    expect(api.lastListStatus, 'archived');
    expect(api.lastAccessToken, 'access-test');
    expect(find.text('Aucune chronique archivée.'), findsOneWidget);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('Archives displays archived cards with archive date', (tester) async {
    const archived = Chronique(
      id: 7,
      title: 'Mon souvenir',
      body: 'Texte de la chronique archivee pour les tests.',
      status: 'archived',
      publishedAt: '2026-09-01T08:00:00.000Z',
      archivedAt: '2026-09-23T15:40:00.000Z',
    );
    final api = _ChroniqueApiProbe()..archivedItems = const [archived];
    await _pumpHome(tester, api: api);
    await _openArchives(tester);

    expect(find.byType(ChroniqueCard), findsOneWidget);
    expect(find.text('Mon souvenir'), findsOneWidget);
    expect(find.text('Texte de la chronique archivee pour les tests.'), findsOneWidget);
    expect(find.text(chroniqueDateLabel(archived)), findsOneWidget);
    expect(find.text('Aucune chronique archivée.'), findsNothing);
  });

  testWidgets('Archives API error is shown without logout', (tester) async {
    final api = _ChroniqueApiProbe()
      ..failWith = const ApiException(message: 'Too many requests', statusCode: 429);
    final container = await _pumpHome(tester, api: api);
    await _openArchives(tester);

    expect(find.text('Too many requests'), findsOneWidget);
    expect(find.byType(ArchivesScreen), findsOneWidget);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    expect(find.text('Logout'), findsNothing);
  });
}
