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
import 'package:mobile/features/chronique/presentation/screens/chronique_detail_screen.dart';
import 'package:mobile/features/chronique/presentation/screens/mon_fil_screen.dart';
import 'package:mobile/features/chronique/presentation/state/mon_fil_controller.dart';
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
  int getCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;
  int archiveCalls = 0;
  String? lastAccessToken;
  String? lastBody;
  String? lastTitle;
  String? lastListStatus;
  int? lastGetId;
  int? lastUpdateId;
  int? lastDeleteId;
  int? lastArchiveId;
  List<Chronique> items = const [];
  List<Chronique> archivedItems = const [];
  ApiException? failWith;
  ApiException? failUpdateWith;
  ApiException? failDeleteWith;
  ApiException? failArchiveWith;

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
    return ChroniquePage(items: items);
  }

  @override
  Future<Chronique> get({
    required String accessToken,
    required int id,
  }) async {
    getCalls += 1;
    lastAccessToken = accessToken;
    lastGetId = id;
    for (final item in items) {
      if (item.id == id) {
        return item;
      }
    }
    throw const ApiException(message: 'Chronique not found', statusCode: 404);
  }

  @override
  Future<Chronique> update({
    required String accessToken,
    required int id,
    required String body,
    String? title,
    String? publish,
    String? scheduledAt,
    bool? isTimeLimited,
    String? expiresAt,
  }) async {
    updateCalls += 1;
    lastAccessToken = accessToken;
    lastUpdateId = id;
    lastBody = body;
    lastTitle = title;
    final error = failUpdateWith;
    if (error != null) {
      throw error;
    }
    final updated = Chronique(
      id: id,
      title: title,
      body: body,
      status: 'active',
      publishedAt: '2026-09-22T10:00:00.000Z',
    );
    items = [
      for (final item in items)
        if (item.id == id) updated else item,
    ];
    return updated;
  }

  @override
  Future<void> delete({
    required String accessToken,
    required int id,
  }) async {
    deleteCalls += 1;
    lastAccessToken = accessToken;
    lastDeleteId = id;
    final error = failDeleteWith;
    if (error != null) {
      throw error;
    }
    items = [
      for (final item in items)
        if (item.id != id) item,
    ];
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

  test('ChroniquePage keeps list media, order, and empty collections', () {
    final page = ChroniquePage.fromJson({
      'items': [
        {
          'id': 1,
          'body': 'Le texte de la chronique, d au moins vingt caracteres.',
          'status': 'active',
          'media': <Object>[],
        },
        {
          'id': 2,
          'title': 'Avec medias',
          'body': 'Le texte de la chronique, d au moins vingt caracteres.',
          'status': 'active',
          'media': [
            {
              'id': 10,
              'kind': 'image',
              'content_type': 'image/jpeg',
              'original_filename': 'a.jpg',
              'byte_size': 100,
              'sort_order': 0,
              'status': 'ready',
              'read_url': 'https://example.test/a.jpg',
              'read_expires_at': '2026-09-25T10:16:00.000Z',
            },
            {
              'id': 20,
              'kind': 'video',
              'content_type': 'video/mp4',
              'original_filename': null,
              'byte_size': 200,
              'sort_order': 1,
              'status': 'ready',
              'read_url': 'https://example.test/b.mp4',
              'read_expires_at': '2026-09-25T10:16:00.000Z',
            },
          ],
        },
        {
          'id': 3,
          'body': 'Le texte de la chronique, d au moins vingt caracteres.',
          'status': 'active',
        },
      ],
      'next': null,
    });

    expect(page.items, hasLength(3));
    expect(page.items[0].media, isEmpty);
    expect(page.items[2].media, isEmpty);

    final medias = page.items[1].media;
    expect(medias, hasLength(2));
    expect(medias.map((item) => item.id), [10, 20]);
    expect(medias.map((item) => item.kind), ['image', 'video']);
    expect(medias[0].originalFilename, 'a.jpg');
    expect(medias[1].originalFilename, isNull);
    expect(medias[0].byteSize, 100);
    expect(medias[0].sortOrder, 0);
    expect(medias[0].status, 'ready');
    expect(medias[0].readUrl, 'https://example.test/a.jpg');
    expect(medias[0].readExpiresAt, DateTime.parse('2026-09-25T10:16:00.000Z'));
    expect(medias[1].readUrl, 'https://example.test/b.mp4');
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

  testWidgets('Mon Fil keeps list media without fetching each chronique', (tester) async {
    const image = ChroniqueMedia(
      id: 10,
      kind: 'image',
      originalFilename: 'a.jpg',
      byteSize: 100,
      status: 'ready',
      contentType: 'image/jpeg',
      sortOrder: 0,
      readUrl: 'https://example.test/a.jpg',
    );
    const video = ChroniqueMedia(
      id: 20,
      kind: 'video',
      status: 'ready',
      contentType: 'video/mp4',
      sortOrder: 1,
      readUrl: 'https://example.test/b.mp4',
    );
    final api = _ChroniqueApiProbe()
      ..items = const [
        Chronique(
          id: 1,
          body: 'Le texte de la chronique, d au moins vingt caracteres.',
          status: 'active',
          publishedAt: '2026-09-22T10:00:00.000Z',
        ),
        Chronique(
          id: 2,
          title: 'Avec medias',
          body: 'Le texte de la chronique, d au moins vingt caracteres.',
          status: 'active',
          publishedAt: '2026-09-22T11:00:00.000Z',
          media: [image, video],
        ),
      ];
    final container = await _pumpHome(tester, api: api);
    await _openMonFil(tester);

    expect(api.listCalls, 1);
    expect(api.getCalls, 0);
    final state = container.read(monFilControllerProvider);
    expect(state, isA<MonFilReady>());
    final items = (state as MonFilReady).items;
    expect(items, hasLength(2));
    expect(items[0].media, isEmpty);
    expect(items[1].media.map((item) => item.id), [10, 20]);
    expect(items[1].media.map((item) => item.readUrl), [
      'https://example.test/a.jpg',
      'https://example.test/b.mp4',
    ]);
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
    expect(find.text(chroniqueDateLabel(api.items.single)), findsOneWidget);
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
    expect(find.text(chroniqueDateLabel(api.items.single)), findsWidgets);
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

  testWidgets('Mon Fil pull-to-refresh calls GET /chroniques again', (tester) async {
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

    expect(api.listCalls, 1);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.text('Modifier'), findsNothing);
    expect(find.text('Supprimer'), findsNothing);

    await tester.fling(find.byType(ChroniqueCard), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(api.listCalls, greaterThan(1));
  });

  testWidgets('scheduled and ephemeral cards show temporal labels', (tester) async {
    final api = _ChroniqueApiProbe()
      ..items = [
        Chronique(
          id: 8,
          title: 'Plus tard',
          body: 'Le texte de la chronique, d au moins vingt caracteres.',
          status: 'scheduled',
          scheduledAt: DateTime.parse('2026-09-24T16:30:00.000Z'),
        ),
        Chronique(
          id: 9,
          title: 'Éphémère',
          body: 'Le texte de la chronique, d au moins vingt caracteres.',
          status: 'active',
          publishedAt: '2026-09-23T15:57:00.000Z',
          isTimeLimited: true,
          expiresAt: DateTime.parse('2026-09-25T15:57:00.000Z'),
        ),
      ];
    await _pumpHome(tester, api: api);
    await _openMonFil(tester);

    expect(find.text('Programmée'), findsOneWidget);
    expect(find.text('Expire le'), findsOneWidget);
    expect(find.text('Plus tard'), findsOneWidget);
    expect(find.text('Éphémère'), findsOneWidget);
  });

  testWidgets('active card overflow menu offers Modifier and Archiver', (tester) async {
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

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Modifier'), findsOneWidget);
    expect(find.text('Archiver'), findsOneWidget);
    expect(find.text('Supprimer'), findsNothing);
  });
}
