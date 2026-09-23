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
import 'package:mobile/features/chronique/models/chronique_page.dart';
import 'package:mobile/features/chronique/presentation/screens/chronique_detail_screen.dart';
import 'package:mobile/features/chronique/presentation/screens/mon_fil_screen.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_card.dart';
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
  String? lastAccessToken;
  List<Chronique> items = const [];
  ApiException? failWith;

  @override
  Future<ChroniquePage> list({required String accessToken}) async {
    listCalls += 1;
    lastAccessToken = accessToken;
    final error = failWith;
    if (error != null) {
      throw error;
    }
    return ChroniquePage(items: items);
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

Future<void> _openMonFil(WidgetTester tester) async {
  expect(find.byType(HomeScreen), findsOneWidget);
  await tester.tap(find.text('EXPLORE'));
  await tester.pumpAndSettle();
  expect(find.byType(MonFilScreen), findsOneWidget);
}

void main() {
  test('ChroniquePage parses items and a nullable next cursor', () {
    final withNext = ChroniquePage.fromJson({
      'items': [
        {
          'id': 42,
          'title': 'Premier soir',
          'body': 'Le texte de la chronique, d au moins vingt caracteres.',
          'status': 'active',
          'published_at': '2026-09-22T10:00:00.000Z',
        },
      ],
      'next': {
        'before_at': '2026-09-01T12:00:00.000Z',
        'before_id': 10,
      },
    });
    expect(withNext.items, hasLength(1));
    expect(withNext.items.single.id, 42);
    expect(withNext.next?.beforeAt, '2026-09-01T12:00:00.000Z');
    expect(withNext.next?.beforeId, 10);

    final withoutNext = ChroniquePage.fromJson({
      'items': <Object>[],
      'next': null,
    });
    expect(withoutNext.items, isEmpty);
    expect(withoutNext.next, isNull);
  });
  testWidgets('authenticated user opens Mon Fil and calls GET /chroniques', (
    tester,
  ) async {
    final api = _ChroniqueApiProbe();
    final container = await _pumpHome(tester, api: api);
    await _openMonFil(tester);

    expect(find.text('Mon Fil'), findsOneWidget);
    expect(api.listCalls, 1);
    expect(api.lastAccessToken, 'access-test');
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('Mon Fil displays a chronique card', (tester) async {
    final api = _ChroniqueApiProbe()
      ..items = const [
        Chronique(
          id: 42,
          title: 'Premier soir',
          body: 'Le texte de la chronique, d au moins vingt caracteres.',
          status: 'active',
          publishedAt: '2026-09-22T10:00:00.000Z',
        ),
      ];
    await _pumpHome(tester, api: api);
    await _openMonFil(tester);

    expect(find.byType(ChroniqueCard), findsOneWidget);
    expect(find.text('Premier soir'), findsOneWidget);
    expect(
      find.text('Le texte de la chronique, d au moins vingt caracteres.'),
      findsOneWidget,
    );
    expect(find.text('22/09/2026'), findsOneWidget);
    expect(find.text('Aucune chronique pour le moment.'), findsNothing);
  });

  testWidgets('tapping a card opens the detail then back returns to Mon Fil', (
    tester,
  ) async {
    final api = _ChroniqueApiProbe()
      ..items = const [
        Chronique(
          id: 42,
          title: 'Premier soir',
          body: 'Le texte de la chronique, d au moins vingt caracteres.',
          status: 'active',
          publishedAt: '2026-09-22T10:00:00.000Z',
        ),
      ];
    final container = await _pumpHome(tester, api: api);
    await _openMonFil(tester);

    await tester.tap(find.byType(ChroniqueCard));
    await tester.pumpAndSettle();

    expect(find.byType(ChroniqueDetailScreen), findsOneWidget);
    expect(find.text('Premier soir'), findsWidgets);
    expect(
      find.text('Le texte de la chronique, d au moins vingt caracteres.'),
      findsWidgets,
    );
    expect(find.text('22/09/2026'), findsWidgets);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(ChroniqueDetailScreen), findsNothing);
    expect(find.byType(MonFilScreen), findsOneWidget);
    expect(find.byType(ChroniqueCard), findsOneWidget);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('Mon Fil shows an empty state when there are no items', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openMonFil(tester);

    expect(find.text('Aucune chronique pour le moment.'), findsOneWidget);
    expect(find.byType(ChroniqueCard), findsNothing);
    expect(api.listCalls, 1);
  });

  testWidgets('Mon Fil API error is shown without logout', (tester) async {
    final api = _ChroniqueApiProbe()
      ..failWith = const ApiException(message: 'Too many requests', statusCode: 429);
    final container = await _pumpHome(tester, api: api);
    await _openMonFil(tester);

    expect(find.text('Too many requests'), findsOneWidget);
    expect(find.byType(ChroniqueCard), findsNothing);
    expect(find.byType(MonFilScreen), findsOneWidget);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    expect(find.text('Logout'), findsNothing);
  });
}
