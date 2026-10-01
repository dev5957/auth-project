import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/router/app_routes.dart';
import 'package:mobile/features/auth/data/storage/auth_token_storage.dart';
import 'package:mobile/features/auth/models/auth_account.dart';
import 'package:mobile/features/auth/providers/auth_controller.dart';
import 'package:mobile/features/auth/providers/auth_providers.dart';
import 'package:mobile/features/auth/state/auth_state.dart';
import 'package:mobile/features/community/models/community.dart';
import 'package:mobile/features/community/models/community_fields.dart';
import 'package:mobile/features/community/presentation/screens/community_detail_screen.dart';
import 'package:mobile/features/community/presentation/screens/community_list_screen.dart';
import 'package:mobile/features/community/presentation/screens/community_search_screen.dart';
import 'package:mobile/features/community/presentation/screens/create_community_screen.dart';
import 'package:mobile/features/community/presentation/state/community_search_controller.dart';
import 'package:mobile/features/community/providers/community_providers.dart';
import 'package:mobile/features/community/services/community_api_service.dart';
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

class _SeededAuthController extends AuthController {
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

class _FakeCommunityApi extends CommunityApiService {
  _FakeCommunityApi()
      : super(ApiClient(config: const AppConfig(apiBaseUrl: 'http://test.invalid')));

  ApiException? failList;
  ApiException? failGet;
  ApiException? failCreate;
  ApiException? failSearch;
  bool holdSearch = false;
  final List<String> searchQueries = <String>[];
  final List<Completer<List<CommunitySearchPreview>>> searchHolds =
      <Completer<List<CommunitySearchPreview>>>[];
  List<CommunitySearchPreview> searchResults = const [];
  int getCalls = 0;
  int listMembersCalls = 0;
  bool holdGet = false;
  final List<Completer<Community>> getHolds = <Completer<Community>>[];
  final List<Community> items = [
    const Community(
      id: 3,
      name: 'Jardin secret',
      visibility: 'private',
      myRole: CommunityRole.owner,
      memberCount: 1,
      description: 'Un cercle privé',
    ),
  ];

  @override
  Future<Community> create({
    required String accessToken,
    required String name,
    String? description,
  }) async {
    if (failCreate != null) {
      throw failCreate!;
    }
    final community = Community(
      id: 8,
      name: name,
      description: description,
      visibility: 'private',
      myRole: CommunityRole.owner,
      memberCount: 1,
    );
    items.add(community);
    return community;
  }

  @override
  Future<List<Community>> list({required String accessToken}) async {
    if (failList != null) {
      throw failList!;
    }
    return List<Community>.from(items);
  }

  @override
  Future<List<CommunitySearchPreview>> search({
    required String accessToken,
    required String q,
  }) async {
    searchQueries.add(q);
    if (failSearch != null) {
      throw failSearch!;
    }
    if (holdSearch) {
      final hold = Completer<List<CommunitySearchPreview>>();
      searchHolds.add(hold);
      return hold.future;
    }
    return List<CommunitySearchPreview>.from(searchResults);
  }

  @override
  Future<Community> get({
    required String accessToken,
    required int id,
  }) async {
    getCalls += 1;
    if (holdGet) {
      final hold = Completer<Community>();
      getHolds.add(hold);
      return hold.future;
    }
    if (failGet != null) {
      throw failGet!;
    }
    return items.firstWhere(
      (item) => item.id == id,
      orElse: () => throw const ApiException(message: 'Community not found', statusCode: 404),
    );
  }

  @override
  Future<List<CommunityMember>> listMembers({
    required String accessToken,
    required int id,
  }) async {
    listMembersCalls += 1;
    if (failGet != null) {
      throw failGet!;
    }
    return const [
      CommunityMember(userId: 1, login: 'tgjjk', role: CommunityRole.owner),
    ];
  }
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required _FakeCommunityApi api,
  AuthTokenStorage? tokens,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authTokenStorageProvider.overrideWithValue(
          tokens ??
              InMemoryAuthTokenStorage(
                accessToken: 'access-test',
                refreshToken: 'refresh-test',
              ),
        ),
        authControllerProvider.overrideWith(() => _SeededAuthController()),
        communityApiServiceProvider.overrideWithValue(api),
      ],
      child: const LuminaApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  test('community name validation uses trim and rune length', () {
    expect(CommunityFields.nameError('short'), isNotNull);
    expect(CommunityFields.nameError('abcdefghij'), isNull);
    expect(CommunityFields.nameError('  Jardin secret  '), isNull);
    expect(CommunityFields.nameError('a' * 101), isNotNull);
    expect(CommunityFields.descriptionError('x' * 501), isNotNull);
    expect(CommunityFields.descriptionError('ok'), isNull);
    expect(CommunityFields.searchQueryError(''), isNotNull);
    expect(CommunityFields.searchQueryError('   '), isNotNull);
    expect(CommunityFields.searchQueryError('Jardin'), isNull);
    expect(CommunityFields.searchQueryError('a' * 100), isNull);
    expect(CommunityFields.searchQueryError('a' * 101), isNotNull);
  });

  test('search preview rejects private leaks', () {
    expect(
      () => CommunitySearchPreview.fromJson({
        'id': 1,
        'name': 'Jardin secret',
        'member_count': 2,
        'my_role': 'owner',
      }),
      throwsA(isA<FormatException>()),
    );
    final preview = CommunitySearchPreview.fromJson({
      'id': 1,
      'name': 'Jardin secret',
      'description': 'Hello',
      'member_count': 2,
    });
    expect(preview.name, 'Jardin secret');
    expect(preview.memberCount, 2);
  });

  testWidgets('COMMUNITIES opens the membership list', (tester) async {
    final api = _FakeCommunityApi();
    await _pumpApp(tester, api: api);
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityListScreen), findsOneWidget);
    expect(find.text('Jardin secret'), findsOneWidget);
    expect(find.text('Propriétaire'), findsOneWidget);
    expect(find.byKey(const ValueKey('community-placeholder-Avatar')), findsWidgets);
  });

  testWidgets('create community from list after field validation', (tester) async {
    final api = _FakeCommunityApi();
    await _pumpApp(tester, api: api);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-create-open')));
    await tester.pumpAndSettle();
    expect(find.byType(CreateCommunityScreen), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('community-name-field')), 'short');
    await tester.tap(find.byKey(const ValueKey('community-create-submit')));
    await tester.pump();
    expect(find.text('Le nom doit contenir au moins 10 caractères'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('community-name-field')), 'Atelier lumineux');
    await tester.tap(find.byKey(const ValueKey('community-create-submit')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityListScreen), findsOneWidget);
    expect(find.text('Atelier lumineux'), findsOneWidget);
  });

  testWidgets('member can open community detail with placeholders', (tester) async {
    final api = _FakeCommunityApi();
    await _pumpApp(tester, api: api);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-list-item-3')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityDetailScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('community-detail-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-detail-role')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-placeholder-Bannière')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-placeholder-Avatar')), findsOneWidget);
  });

  testWidgets('detail 404 shows introuvable', (tester) async {
    final api = _FakeCommunityApi()
      ..failGet = const ApiException(message: 'Community not found', statusCode: 404);
    await _pumpApp(tester, api: api);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-list-item-3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-detail-error')), findsOneWidget);
    expect(find.text('Communauté introuvable'), findsOneWidget);
  });

  testWidgets('list 401 shows session error', (tester) async {
    final api = _FakeCommunityApi()
      ..failList = const ApiException(message: 'Unauthorized', statusCode: 401);
    await _pumpApp(tester, api: api);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-list-error')), findsOneWidget);
    expect(find.text('Session expirée'), findsOneWidget);
  });

  test('authenticated whitelist includes community routes', () {
    expect(AppRoutes.isAuthenticatedLocation('/communities'), isTrue);
    expect(AppRoutes.isAuthenticatedLocation('/communities/create'), isTrue);
    expect(AppRoutes.isAuthenticatedLocation('/communities/search'), isTrue);
    expect(AppRoutes.isAuthenticatedLocation('/communities/12'), isTrue);
    expect(AppRoutes.isAuthenticatedLocation('/communities/nope'), isFalse);
    expect(AppRoutes.isAuthenticatedLocation('/communities/search/extra'), isFalse);
  });

  Future<void> openSearch(WidgetTester tester, _FakeCommunityApi api) async {
    await _pumpApp(tester, api: api);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-search-open')));
    await tester.pumpAndSettle();
  }

  testWidgets('search action opens dedicated screen without API call', (tester) async {
    final api = _FakeCommunityApi();
    await openSearch(tester, api);
    expect(find.byType(CommunitySearchScreen), findsOneWidget);
    expect(find.byType(CommunityDetailScreen), findsNothing);
    expect(find.byKey(const ValueKey('community-search-idle')), findsOneWidget);
    expect(api.searchQueries, isEmpty);
    expect(find.text('Rejoindre'), findsNothing);
  });

  testWidgets('empty search submit does not call API', (tester) async {
    final api = _FakeCommunityApi();
    await openSearch(tester, api);
    await tester.enterText(find.byKey(const ValueKey('community-search-field')), '   ');
    await tester.tap(find.byKey(const ValueKey('community-search-submit')));
    await tester.pump();
    expect(api.searchQueries, isEmpty);
    expect(find.text('Saisissez un nom de communauté'), findsOneWidget);
  });

  testWidgets('too long search query does not call API', (tester) async {
    final api = _FakeCommunityApi();
    await openSearch(tester, api);
    await tester.enterText(find.byKey(const ValueKey('community-search-field')), 'a' * 101);
    await tester.tap(find.byKey(const ValueKey('community-search-submit')));
    await tester.pump();
    expect(api.searchQueries, isEmpty);
    expect(find.text('Le nom recherché est trop long'), findsOneWidget);
  });

  testWidgets('valid name search shows preview cards without role or join', (tester) async {
    final api = _FakeCommunityApi()
      ..searchResults = const [
        CommunitySearchPreview(
          id: 9,
          name: 'Atelier lumineux',
          description: 'Un cercle privé',
          memberCount: 3,
        ),
        CommunitySearchPreview(
          id: 10,
          name: 'Cercle des autres',
          memberCount: 1,
        ),
      ];
    await openSearch(tester, api);
    await tester.enterText(find.byKey(const ValueKey('community-search-field')), '  Cercle  ');
    await tester.tap(find.byKey(const ValueKey('community-search-submit')));
    await tester.pumpAndSettle();
    expect(api.searchQueries, ['Cercle']);
    expect(find.text('Atelier lumineux'), findsOneWidget);
    expect(find.text('Un cercle privé'), findsOneWidget);
    expect(find.byKey(const ValueKey('community-search-count-9')), findsOneWidget);
    expect(find.text('3 membres'), findsOneWidget);
    expect(find.text('Cercle des autres'), findsOneWidget);
    expect(find.text('1 membre'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('community-search-item-9')),
        matching: find.text('Propriétaire'),
      ),
      findsNothing,
    );
    expect(find.text('Rejoindre'), findsNothing);
    expect(api.listMembersCalls, 0);
  });

  testWidgets('empty search results show empty state', (tester) async {
    final api = _FakeCommunityApi()..searchResults = const [];
    await openSearch(tester, api);
    await tester.enterText(find.byKey(const ValueKey('community-search-field')), 'Jardin');
    await tester.tap(find.byKey(const ValueKey('community-search-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-search-empty')), findsOneWidget);
    expect(api.searchQueries, ['Jardin']);
  });

  testWidgets('search network error is shown', (tester) async {
    final api = _FakeCommunityApi()
      ..failSearch = const ApiException(message: 'Network error');
    await openSearch(tester, api);
    await tester.enterText(find.byKey(const ValueKey('community-search-field')), 'Jardin');
    await tester.tap(find.byKey(const ValueKey('community-search-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-search-error')), findsOneWidget);
    expect(find.text('Network error'), findsOneWidget);
  });

  testWidgets('search 401 shows session error', (tester) async {
    final api = _FakeCommunityApi()
      ..failSearch = const ApiException(message: 'Unauthorized', statusCode: 401);
    await openSearch(tester, api);
    await tester.enterText(find.byKey(const ValueKey('community-search-field')), 'Jardin');
    await tester.tap(find.byKey(const ValueKey('community-search-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-search-error')), findsOneWidget);
    expect(find.text('Session expirée'), findsOneWidget);
  });

  testWidgets('search result 200 opens existing detail', (tester) async {
    final api = _FakeCommunityApi()
      ..searchResults = const [
        CommunitySearchPreview(
          id: 3,
          name: 'Jardin secret',
          description: 'Un cercle privé',
          memberCount: 1,
        ),
      ];
    await openSearch(tester, api);
    await tester.enterText(find.byKey(const ValueKey('community-search-field')), 'Jardin');
    await tester.tap(find.byKey(const ValueKey('community-search-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-search-item-3')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityDetailScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('community-detail-name')), findsOneWidget);
    expect(api.getCalls, greaterThanOrEqualTo(1));
    expect(api.listMembersCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('search result 404 stays on search with private notice', (tester) async {
    final api = _FakeCommunityApi()
      ..searchResults = const [
        CommunitySearchPreview(
          id: 99,
          name: 'Cercle fermé',
          description: 'Aperçu limité',
          memberCount: 4,
        ),
      ];
    await openSearch(tester, api);
    await tester.enterText(find.byKey(const ValueKey('community-search-field')), 'Cercle');
    await tester.tap(find.byKey(const ValueKey('community-search-submit')));
    await tester.pumpAndSettle();
    final membersBeforeTap = api.listMembersCalls;
    await tester.tap(find.byKey(const ValueKey('community-search-item-99')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunitySearchScreen), findsOneWidget);
    expect(find.byType(CommunityDetailScreen), findsNothing);
    expect(find.text('Communauté introuvable'), findsNothing);
    expect(
      find.text(
        'Cette communauté est privée. Le détail est accessible uniquement aux membres.',
      ),
      findsOneWidget,
    );
    expect(find.text('Cercle fermé'), findsOneWidget);
    expect(find.text('Aperçu limité'), findsOneWidget);
    expect(find.text('4 membres'), findsOneWidget);
    expect(find.text('Rejoindre'), findsNothing);
    expect(api.listMembersCalls, membersBeforeTap);
  });

  test('stale search response is ignored', () async {
    final api = _FakeCommunityApi()..holdSearch = true;
    final container = ProviderContainer(
      overrides: [
        authTokenStorageProvider.overrideWithValue(
          InMemoryAuthTokenStorage(
            accessToken: 'access-test',
            refreshToken: 'refresh-test',
          ),
        ),
        communityApiServiceProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    container.listen(communitySearchControllerProvider, (_, __) {});

    final notifier = container.read(communitySearchControllerProvider.notifier);
    final first = notifier.submit('Premier nom');
    await Future<void>.value();
    final second = notifier.submit('Second nom');
    await Future<void>.value();
    expect(api.searchHolds, hasLength(2));

    api.searchHolds[1].complete(const [
      CommunitySearchPreview(id: 2, name: 'Second nomxx', memberCount: 1),
    ]);
    await second;
    expect(container.read(communitySearchControllerProvider), isA<CommunitySearchReady>());
    final ready = container.read(communitySearchControllerProvider) as CommunitySearchReady;
    expect(ready.items.single.name, 'Second nomxx');

    api.searchHolds[0].complete(const [
      CommunitySearchPreview(id: 1, name: 'Premier nomx', memberCount: 8),
    ]);
    await first;
    final still = container.read(communitySearchControllerProvider) as CommunitySearchReady;
    expect(still.items.single.name, 'Second nomxx');
    expect(still.items.single.memberCount, 1);
  });

  test('stale 404 probe does not replace a newer search', () async {
    final api = _FakeCommunityApi()
      ..searchResults = const [
        CommunitySearchPreview(id: 99, name: 'Cercle fermé', memberCount: 4),
      ];
    final container = ProviderContainer(
      overrides: [
        authTokenStorageProvider.overrideWithValue(
          InMemoryAuthTokenStorage(
            accessToken: 'access-test',
            refreshToken: 'refresh-test',
          ),
        ),
        communityApiServiceProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    container.listen(communitySearchControllerProvider, (_, __) {});

    final notifier = container.read(communitySearchControllerProvider.notifier);
    await notifier.submit('Cercle');
    expect(container.read(communitySearchControllerProvider), isA<CommunitySearchReady>());
    expect(
      (container.read(communitySearchControllerProvider) as CommunitySearchReady)
          .items
          .single
          .id,
      99,
    );

    api.holdGet = true;
    final probe = notifier.openAccessibleDetail(99);
    for (var i = 0; i < 20 && api.getHolds.isEmpty; i++) {
      await Future<void>.value();
    }
    expect(api.getHolds, hasLength(1));
    expect(api.listMembersCalls, 0);

    api.searchResults = const [
      CommunitySearchPreview(id: 2, name: 'Second nomxx', memberCount: 1),
    ];
    await notifier.submit('Second nom');
    final afterSearch = container.read(communitySearchControllerProvider) as CommunitySearchReady;
    expect(afterSearch.items.single.id, 2);
    expect(afterSearch.notice, isNull);

    api.getHolds[0].completeError(
      const ApiException(message: 'Community not found', statusCode: 404),
    );
    expect(await probe, isFalse);

    final afterProbe = container.read(communitySearchControllerProvider) as CommunitySearchReady;
    expect(afterProbe.items.single.id, 2);
    expect(afterProbe.items.single.name, 'Second nomxx');
    expect(afterProbe.notice, isNull);
    expect(api.listMembersCalls, 0);
  });
}
