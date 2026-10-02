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
import 'package:mobile/core/widgets/app_card.dart';
import 'package:mobile/features/community/presentation/screens/community_search_screen.dart';
import 'package:mobile/features/community/presentation/screens/create_community_screen.dart';
import 'package:mobile/features/community/presentation/screens/user_search_screen.dart';
import 'package:mobile/features/community/presentation/state/community_search_controller.dart';
import 'package:mobile/features/community/presentation/state/user_search_controller.dart';
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
  ApiException? failUserSearch;
  List<UserSearchHit> userSearchResults = const [];
  final List<Map<String, String>> userSearchQueries = <Map<String, String>>[];
  final List<String> networkOps = <String>[];
  bool holdUserSearch = false;
  final List<Completer<List<UserSearchHit>>> userSearchHolds =
      <Completer<List<UserSearchHit>>>[];
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
    networkOps.add('POST /communities');
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
    networkOps.add('GET /communities');
    return List<Community>.from(items);
  }

  @override
  Future<List<CommunitySearchPreview>> search({
    required String accessToken,
    required String q,
  }) async {
    searchQueries.add(q);
    networkOps.add('GET /communities/search');
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
    networkOps.add('GET /communities/$id');
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
    networkOps.add('GET /communities/$id/members');
    if (failGet != null) {
      throw failGet!;
    }
    return const [
      CommunityMember(userId: 1, login: 'tgjjk', role: CommunityRole.owner),
    ];
  }

  @override
  Future<List<UserSearchHit>> searchUsers({
    required String accessToken,
    String? login,
    String? phone,
  }) async {
    final query = <String, String>{
      if (login != null) 'login': login,
      if (phone != null) 'phone': phone,
    };
    userSearchQueries.add(query);
    networkOps.add('GET /users/search');
    if (holdUserSearch) {
      final hold = Completer<List<UserSearchHit>>();
      userSearchHolds.add(hold);
      return hold.future;
    }
    if (failUserSearch != null) {
      throw failUserSearch!;
    }
    return List<UserSearchHit>.from(userSearchResults);
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
    expect(AppRoutes.isAuthenticatedLocation('/communities/12/invite'), isTrue);
    expect(AppRoutes.isAuthenticatedLocation('/communities/nope'), isFalse);
    expect(AppRoutes.isAuthenticatedLocation('/communities/search/extra'), isFalse);
    expect(AppRoutes.isAuthenticatedLocation('/communities/12/invite/extra'), isFalse);
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

  test('user search hit rejects private leaks', () {
    expect(
      () => UserSearchHit.fromJson({
        'user_id': 25,
        'login': 'moh5',
        'phone_number': '+33612345678',
      }),
      throwsA(isA<FormatException>()),
    );
    final hit = UserSearchHit.fromJson({'user_id': 25, 'login': 'moh5'});
    expect(hit.userId, 25);
    expect(hit.login, 'moh5');
  });

  test('user search field validation trims without partial match', () {
    expect(UserSearchFields.loginError(''), isNotNull);
    expect(UserSearchFields.loginError('   '), isNotNull);
    expect(UserSearchFields.loginError('moh5'), isNull);
    expect(UserSearchFields.preparedLogin('  Moh5  '), 'moh5');
    expect(UserSearchFields.loginError('a' * 65), isNotNull);
    expect(UserSearchFields.phoneError(''), isNotNull);
    expect(UserSearchFields.phoneError('   '), isNotNull);
    expect(UserSearchFields.phoneError('+33612345678'), isNull);
  });

  void setListedRole(_FakeCommunityApi api, CommunityRole role) {
    api.items
      ..clear()
      ..add(
        Community(
          id: 3,
          name: 'Jardin secret',
          visibility: 'private',
          myRole: role,
          memberCount: 1,
          description: 'Un cercle privé',
        ),
      );
  }

  Future<void> openCommunityDetail(WidgetTester tester, _FakeCommunityApi api) async {
    await _pumpApp(tester, api: api);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-list-item-3')));
    await tester.pumpAndSettle();
  }

  Future<void> openUserSearch(WidgetTester tester, _FakeCommunityApi api) async {
    await openCommunityDetail(tester, api);
    await tester.tap(find.byKey(const ValueKey('community-detail-invite')));
    await tester.pumpAndSettle();
  }

  testWidgets('owner sees invite member button', (tester) async {
    final api = _FakeCommunityApi();
    await openCommunityDetail(tester, api);
    expect(find.byKey(const ValueKey('community-detail-invite')), findsOneWidget);
    expect(find.text('Inviter un membre'), findsOneWidget);
  });

  testWidgets('admin does not see invite member button', (tester) async {
    final api = _FakeCommunityApi();
    setListedRole(api, CommunityRole.admin);
    await openCommunityDetail(tester, api);
    expect(find.byKey(const ValueKey('community-detail-invite')), findsNothing);
    expect(find.text('Inviter un membre'), findsNothing);
  });

  testWidgets('member does not see invite member button', (tester) async {
    final api = _FakeCommunityApi();
    setListedRole(api, CommunityRole.member);
    await openCommunityDetail(tester, api);
    expect(find.byKey(const ValueKey('community-detail-invite')), findsNothing);
    expect(find.text('Inviter un membre'), findsNothing);
  });

  testWidgets('invite search opens from community detail', (tester) async {
    final api = _FakeCommunityApi();
    await openUserSearch(tester, api);
    expect(find.byType(UserSearchScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('user-search-idle')), findsOneWidget);
    expect(api.userSearchQueries, isEmpty);
    expect(api.networkOps.where((op) => op.startsWith('GET /users/search')), isEmpty);
  });

  testWidgets('login search sends only login', (tester) async {
    final api = _FakeCommunityApi()
      ..userSearchResults = const [UserSearchHit(userId: 25, login: 'moh5')];
    await openUserSearch(tester, api);
    await tester.enterText(find.byKey(const ValueKey('user-search-field')), '  Moh5  ');
    await tester.tap(find.byKey(const ValueKey('user-search-submit')));
    await tester.pumpAndSettle();
    expect(api.userSearchQueries, hasLength(1));
    expect(api.userSearchQueries.single, {'login': 'moh5'});
    expect(api.userSearchQueries.single.containsKey('phone'), isFalse);
    expect(find.byKey(const ValueKey('user-search-item-25')), findsOneWidget);
    expect(find.text('moh5'), findsOneWidget);
  });

  testWidgets('phone search sends only phone', (tester) async {
    final api = _FakeCommunityApi()
      ..userSearchResults = const [UserSearchHit(userId: 25, login: 'moh5')];
    await openUserSearch(tester, api);
    await tester.tap(find.byKey(const ValueKey('user-search-mode-phone')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('user-search-field')), '  +15550001111  ');
    await tester.tap(find.byKey(const ValueKey('user-search-submit')));
    await tester.pumpAndSettle();
    expect(api.userSearchQueries, hasLength(1));
    expect(api.userSearchQueries.single, {'phone': '+15550001111'});
    expect(api.userSearchQueries.single.containsKey('login'), isFalse);
    expect(find.text('moh5'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppCard),
        matching: find.text('+15550001111'),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('user-search-item-25')), findsOneWidget);
  });

  testWidgets('empty user search does not call API', (tester) async {
    final api = _FakeCommunityApi();
    await openUserSearch(tester, api);
    await tester.enterText(find.byKey(const ValueKey('user-search-field')), '   ');
    await tester.tap(find.byKey(const ValueKey('user-search-submit')));
    await tester.pump();
    expect(api.userSearchQueries, isEmpty);
    expect(find.text('Saisissez un login'), findsOneWidget);
  });

  testWidgets('empty user search items show empty state', (tester) async {
    final api = _FakeCommunityApi()..userSearchResults = const [];
    await openUserSearch(tester, api);
    await tester.enterText(find.byKey(const ValueKey('user-search-field')), 'moh5');
    await tester.tap(find.byKey(const ValueKey('user-search-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-search-empty')), findsOneWidget);
    expect(find.text('Aucun utilisateur trouvé'), findsOneWidget);
  });

  testWidgets('user search API error is recoverable', (tester) async {
    final api = _FakeCommunityApi()
      ..failUserSearch = const ApiException(message: 'Network error');
    await openUserSearch(tester, api);
    await tester.enterText(find.byKey(const ValueKey('user-search-field')), 'moh5');
    await tester.tap(find.byKey(const ValueKey('user-search-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-search-error')), findsOneWidget);
    expect(find.text('Network error'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('user-search-retry')));
    await tester.pumpAndSettle();
    expect(api.userSearchQueries, hasLength(2));
    expect(api.userSearchQueries.last, {'login': 'moh5'});
  });

  testWidgets('user search 401 shows session error', (tester) async {
    final api = _FakeCommunityApi()
      ..failUserSearch = const ApiException(message: 'Unauthorized', statusCode: 401);
    await openUserSearch(tester, api);
    await tester.enterText(find.byKey(const ValueKey('user-search-field')), 'moh5');
    await tester.tap(find.byKey(const ValueKey('user-search-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-search-error')), findsOneWidget);
    expect(find.text('Session expirée'), findsOneWidget);
  });

  test('user search controller logs omit server error payload', () async {
    const fakePhone = '+15550001111';
    const fakeLogin = 'user-test-alpha';
    final previousPrint = debugPrint;
    final logs = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) {
      logs.add(message ?? '');
    };
    addTearDown(() => debugPrint = previousPrint);

    final api = _FakeCommunityApi()
      ..failUserSearch = const ApiException(
        message: 'lookup failed login=$fakeLogin phone=$fakePhone',
        statusCode: 400,
      );
    final container = ProviderContainer(
      overrides: [
        authTokenStorageProvider.overrideWithValue(
          InMemoryAuthTokenStorage(
            accessToken: 'tok-test-0001',
            refreshToken: 'tok-test-0002',
          ),
        ),
        communityApiServiceProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    container.listen(userSearchControllerProvider, (_, __) {});

    await container.read(userSearchControllerProvider.notifier).submit(
          UserSearchMode.login,
          fakeLogin,
        );

    final blob = logs.join('\n');
    expect(blob, contains('GET /users/search'));
    expect(blob, contains('status=400'));
    expect(blob, contains('type=ApiException'));
    expect(blob, isNot(contains(fakePhone)));
    expect(blob, isNot(contains('15550001111')));
    expect(blob, isNot(contains(fakeLogin)));
    expect(blob, isNot(contains('tok-test-0001')));
    expect(blob, isNot(contains('lookup failed')));

    final state = container.read(userSearchControllerProvider);
    expect(state, isA<UserSearchError>());
    expect((state as UserSearchError).statusCode, 400);
    expect(state.message, 'lookup failed login=$fakeLogin phone=$fakePhone');
  });

  testWidgets('selecting a user does not send an invitation', (tester) async {
    final api = _FakeCommunityApi()
      ..userSearchResults = const [UserSearchHit(userId: 25, login: 'moh5')];
    await openUserSearch(tester, api);
    await tester.enterText(find.byKey(const ValueKey('user-search-field')), 'moh5');
    await tester.tap(find.byKey(const ValueKey('user-search-submit')));
    await tester.pumpAndSettle();
    final opsAfterSearch = List<String>.from(api.networkOps);
    expect(opsAfterSearch.where((op) => op == 'GET /users/search'), hasLength(1));
    expect(opsAfterSearch.where((op) => op.contains('invite')), isEmpty);
    await tester.tap(find.byKey(const ValueKey('user-search-select-25')));
    await tester.pump();
    expect(find.byKey(const ValueKey('user-search-selected-notice')), findsOneWidget);
    expect(find.text(kUserSearchSelectedNotice), findsOneWidget);
    expect(api.userSearchQueries, hasLength(1));
    expect(api.networkOps, opsAfterSearch);
    expect(api.networkOps.where((op) => op.startsWith('POST')), isEmpty);
    expect(
      api.networkOps.where((op) => op.contains('invite') || op.contains('invitation')),
      isEmpty,
    );
  });

  testWidgets('empty phone search does not call API', (tester) async {
    final api = _FakeCommunityApi();
    await openUserSearch(tester, api);
    await tester.tap(find.byKey(const ValueKey('user-search-mode-phone')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('user-search-field')), '   ');
    await tester.tap(find.byKey(const ValueKey('user-search-submit')));
    await tester.pump();
    expect(api.userSearchQueries, isEmpty);
    expect(api.networkOps.where((op) => op == 'GET /users/search'), isEmpty);
    expect(find.text('Saisissez un numéro de téléphone'), findsOneWidget);
  });

  testWidgets('invite search back returns to the same community detail', (tester) async {
    final api = _FakeCommunityApi();
    await openUserSearch(tester, api);
    expect(find.byType(UserSearchScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('user-search-back')));
    await tester.pumpAndSettle();
    expect(find.byType(UserSearchScreen), findsNothing);
    expect(find.byType(CommunityDetailScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('community-detail-name')), findsOneWidget);
    expect(find.text('Jardin secret'), findsOneWidget);
    expect(find.byKey(const ValueKey('community-detail-invite')), findsOneWidget);
  });

  test('stale user search response is ignored', () async {
    final api = _FakeCommunityApi()..holdUserSearch = true;
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
    container.listen(userSearchControllerProvider, (_, __) {});

    final notifier = container.read(userSearchControllerProvider.notifier);
    final first = notifier.submit(UserSearchMode.login, 'alpha');
    for (var i = 0; i < 20 && api.userSearchHolds.isEmpty; i++) {
      await Future<void>.value();
    }
    final second = notifier.submit(UserSearchMode.login, 'beta');
    for (var i = 0; i < 20 && api.userSearchHolds.length < 2; i++) {
      await Future<void>.value();
    }
    expect(api.userSearchHolds, hasLength(2));

    api.userSearchHolds[1].complete(const [
      UserSearchHit(userId: 2, login: 'beta'),
    ]);
    await second;
    expect(container.read(userSearchControllerProvider), isA<UserSearchReady>());
    final ready = container.read(userSearchControllerProvider) as UserSearchReady;
    expect(ready.hit.login, 'beta');
    expect(ready.hit.userId, 2);

    api.userSearchHolds[0].complete(const [
      UserSearchHit(userId: 1, login: 'alpha'),
    ]);
    await first;
    final still = container.read(userSearchControllerProvider) as UserSearchReady;
    expect(still.hit.login, 'beta');
    expect(still.hit.userId, 2);
  });

  test('stale user search error does not replace a newer result', () async {
    final api = _FakeCommunityApi()..holdUserSearch = true;
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
    container.listen(userSearchControllerProvider, (_, __) {});

    final notifier = container.read(userSearchControllerProvider.notifier);
    final first = notifier.submit(UserSearchMode.login, 'alpha');
    for (var i = 0; i < 20 && api.userSearchHolds.isEmpty; i++) {
      await Future<void>.value();
    }
    final second = notifier.submit(UserSearchMode.login, 'beta');
    for (var i = 0; i < 20 && api.userSearchHolds.length < 2; i++) {
      await Future<void>.value();
    }
    expect(api.userSearchHolds, hasLength(2));

    api.userSearchHolds[1].complete(const [
      UserSearchHit(userId: 2, login: 'beta'),
    ]);
    await second;
    expect(container.read(userSearchControllerProvider), isA<UserSearchReady>());

    api.userSearchHolds[0].completeError(
      const ApiException(message: 'Network error'),
    );
    await first;
    final still = container.read(userSearchControllerProvider) as UserSearchReady;
    expect(still.hit.login, 'beta');
    expect(still.hit.userId, 2);
  });
}
