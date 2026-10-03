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
import 'package:mobile/features/community/models/invitation_messages.dart';
import 'package:mobile/features/community/models/join_request.dart';
import 'package:mobile/features/community/models/join_request_messages.dart';
import 'package:mobile/features/community/presentation/screens/community_detail_screen.dart';
import 'package:mobile/features/community/presentation/screens/community_list_screen.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/widgets/app_button.dart';
import 'package:mobile/core/widgets/app_card.dart';
import 'package:mobile/core/widgets/app_loading.dart';
import 'package:mobile/features/community/presentation/screens/community_search_screen.dart';
import 'package:mobile/features/community/presentation/screens/create_community_screen.dart';
import 'package:mobile/features/community/presentation/screens/invitation_inbox_screen.dart';
import 'package:mobile/features/community/presentation/screens/my_join_requests_screen.dart';
import 'package:mobile/features/community/presentation/screens/user_search_screen.dart';
import 'package:mobile/features/community/presentation/widgets/community_join_requests_section.dart';
import 'package:mobile/features/community/presentation/widgets/community_leave_bar.dart';
import 'package:mobile/features/community/presentation/widgets/community_member_dialogs.dart';
import 'package:mobile/features/community/presentation/widgets/community_member_tile.dart';
import 'package:mobile/features/community/presentation/widgets/community_owner_leave_flow.dart';
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
  bool holdList = false;
  final List<Completer<List<Community>>> listHolds = <Completer<List<Community>>>[];
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
  ApiException? failCreateInvitation;
  bool holdCreateInvitation = false;
  final List<Completer<CreatedCommunityInvitation>> createInvitationHolds =
      <Completer<CreatedCommunityInvitation>>[];
  final List<Map<String, int>> createInvitationCalls = <Map<String, int>>[];
  List<ReceivedCommunityInvitation> invitations = const [];
  ApiException? failListInvitations;
  ApiException? failAcceptInvitation;
  ApiException? failDeclineInvitation;
  bool holdAcceptInvitation = false;
  final List<Completer<void>> acceptInvitationHolds = <Completer<void>>[];
  final List<int> acceptedInvitationIds = <int>[];
  final List<int> declinedInvitationIds = <int>[];
  int listInvitationsCalls = 0;
  int listSentInvitationsCalls = 0;
  List<SentCommunityInvitation> sentInvitations = const [];
  ApiException? failListSentInvitations;
  bool holdListSentInvitations = false;
  final List<Completer<List<SentCommunityInvitation>>> listSentHolds =
      <Completer<List<SentCommunityInvitation>>>[];
  List<MyJoinRequest> myJoinRequests = const [];
  List<OwnerJoinRequest> ownerJoinRequests = const [];
  ApiException? failCreateJoinRequest;
  ApiException? failListMyJoinRequests;
  ApiException? failListCommunityJoinRequests;
  ApiException? failAcceptJoinRequest;
  ApiException? failDeclineJoinRequest;
  final List<int> createJoinRequestCalls = <int>[];
  final List<int> acceptedJoinRequestIds = <int>[];
  final List<int> declinedJoinRequestIds = <int>[];
  int listMyJoinRequestsCalls = 0;
  int listCommunityJoinRequestsCalls = 0;
  int nextJoinRequestId = 50;
  int getCalls = 0;
  int listMembersCalls = 0;
  int leaveCalls = 0;
  final List<Map<String, Object>> roleUpdates = <Map<String, Object>>[];
  final List<int> removedMemberIds = <int>[];
  List<CommunityMember> members = const [
    CommunityMember(userId: 1, login: 'tgjjk', role: CommunityRole.owner),
  ];
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
    networkOps.add('GET /communities');
    if (holdList) {
      final hold = Completer<List<Community>>();
      listHolds.add(hold);
      return hold.future;
    }
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
    return List<CommunityMember>.from(members);
  }

  @override
  Future<CommunityMember> updateMemberRole({
    required String accessToken,
    required int communityId,
    required int userId,
    required String role,
  }) async {
    networkOps.add('PATCH /communities/$communityId/members/$userId');
    roleUpdates.add({'userId': userId, 'role': role});
    members = [
      for (final item in members)
        if (item.userId == userId)
          CommunityMember(
            userId: item.userId,
            login: item.login,
            role: CommunityRole.parse(role),
            roleAssignedAt: role == 'admin' ? DateTime.utc(2026, 1, 1) : null,
          )
        else
          item,
    ];
    return members.firstWhere((item) => item.userId == userId);
  }

  @override
  Future<void> removeMember({
    required String accessToken,
    required int communityId,
    required int userId,
  }) async {
    networkOps.add('DELETE /communities/$communityId/members/$userId');
    removedMemberIds.add(userId);
    members = [for (final item in members) if (item.userId != userId) item];
  }

  @override
  Future<Map<String, dynamic>> leaveCommunity({
    required String accessToken,
    required int communityId,
  }) async {
    networkOps.add('POST /communities/$communityId/leave');
    leaveCalls += 1;
    return <String, dynamic>{'left': true, 'transferred': false};
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

  @override
  Future<CreatedCommunityInvitation> createInvitation({
    required String accessToken,
    required int communityId,
    required int userId,
  }) async {
    createInvitationCalls.add({'communityId': communityId, 'userId': userId});
    networkOps.add('POST /communities/$communityId/invitations');
    if (holdCreateInvitation) {
      final hold = Completer<CreatedCommunityInvitation>();
      createInvitationHolds.add(hold);
      return hold.future;
    }
    if (failCreateInvitation != null) {
      throw failCreateInvitation!;
    }
    return CreatedCommunityInvitation(
      id: 41,
      communityId: communityId,
      inviteeUserId: userId,
      status: 'pending',
      createdAt: '2026-10-02T12:00:00.000Z',
    );
  }

  @override
  Future<List<ReceivedCommunityInvitation>> listInvitations({
    required String accessToken,
  }) async {
    listInvitationsCalls += 1;
    networkOps.add('GET /invitations');
    if (failListInvitations != null) {
      throw failListInvitations!;
    }
    return List<ReceivedCommunityInvitation>.from(invitations);
  }

  @override
  Future<void> acceptInvitation({
    required String accessToken,
    required int invitationId,
  }) async {
    networkOps.add('POST /invitations/$invitationId/accept');
    if (holdAcceptInvitation) {
      final hold = Completer<void>();
      acceptInvitationHolds.add(hold);
      await hold.future;
    }
    if (failAcceptInvitation != null) {
      throw failAcceptInvitation!;
    }
    acceptedInvitationIds.add(invitationId);
    invitations = invitations.where((item) => item.id != invitationId).toList();
  }

  @override
  Future<void> declineInvitation({
    required String accessToken,
    required int invitationId,
  }) async {
    networkOps.add('POST /invitations/$invitationId/decline');
    if (failDeclineInvitation != null) {
      throw failDeclineInvitation!;
    }
    declinedInvitationIds.add(invitationId);
    invitations = invitations.where((item) => item.id != invitationId).toList();
  }

  @override
  Future<List<SentCommunityInvitation>> listSentInvitations({
    required String accessToken,
    required int communityId,
  }) async {
    listSentInvitationsCalls += 1;
    networkOps.add('GET /communities/$communityId/invitations');
    if (holdListSentInvitations) {
      final hold = Completer<List<SentCommunityInvitation>>();
      listSentHolds.add(hold);
      return hold.future;
    }
    if (failListSentInvitations != null) {
      throw failListSentInvitations!;
    }
    return List<SentCommunityInvitation>.from(sentInvitations);
  }

  @override
  Future<CreatedJoinRequest> createJoinRequest({
    required String accessToken,
    required int communityId,
  }) async {
    createJoinRequestCalls.add(communityId);
    networkOps.add('POST /communities/$communityId/join-requests');
    if (failCreateJoinRequest != null) {
      throw failCreateJoinRequest!;
    }
    if (items.any((item) => item.id == communityId)) {
      throw const ApiException(message: 'user is already a member', statusCode: 400);
    }
    if (myJoinRequests.any(
      (item) => item.communityId == communityId && item.status == 'pending',
    )) {
      throw const ApiException(message: 'join request already pending', statusCode: 400);
    }
    final created = CreatedJoinRequest(
      id: nextJoinRequestId,
      communityId: communityId,
      status: 'pending',
      createdAt: '2026-10-03T12:00:00.000Z',
    );
    myJoinRequests = [
      MyJoinRequest(
        id: created.id,
        communityId: communityId,
        communityName: 'Communauté $communityId',
        status: 'pending',
        createdAt: created.createdAt,
      ),
      ...myJoinRequests,
    ];
    ownerJoinRequests = [
      OwnerJoinRequest(
        id: created.id,
        status: 'pending',
        requesterLogin: 'invitee7',
        createdAt: created.createdAt,
      ),
      ...ownerJoinRequests,
    ];
    nextJoinRequestId += 1;
    return created;
  }

  @override
  Future<List<MyJoinRequest>> listMyJoinRequests({
    required String accessToken,
  }) async {
    listMyJoinRequestsCalls += 1;
    networkOps.add('GET /join-requests/mine');
    if (failListMyJoinRequests != null) {
      throw failListMyJoinRequests!;
    }
    return List<MyJoinRequest>.from(myJoinRequests);
  }

  @override
  Future<List<OwnerJoinRequest>> listCommunityJoinRequests({
    required String accessToken,
    required int communityId,
  }) async {
    listCommunityJoinRequestsCalls += 1;
    networkOps.add('GET /communities/$communityId/join-requests');
    if (failListCommunityJoinRequests != null) {
      throw failListCommunityJoinRequests!;
    }
    return List<OwnerJoinRequest>.from(ownerJoinRequests);
  }

  @override
  Future<void> acceptJoinRequest({
    required String accessToken,
    required int communityId,
    required int requestId,
  }) async {
    networkOps.add('POST /communities/$communityId/join-requests/$requestId/accept');
    if (failAcceptJoinRequest != null) {
      throw failAcceptJoinRequest!;
    }
    acceptedJoinRequestIds.add(requestId);
    ownerJoinRequests = [
      for (final item in ownerJoinRequests)
        if (item.id == requestId) item.copyWithStatus('accepted') else item,
    ];
    myJoinRequests = [
      for (final item in myJoinRequests)
        if (item.id == requestId)
          MyJoinRequest(
            id: item.id,
            communityId: item.communityId,
            communityName: item.communityName,
            status: 'accepted',
            createdAt: item.createdAt,
          )
        else
          item,
    ];
  }

  @override
  Future<void> declineJoinRequest({
    required String accessToken,
    required int communityId,
    required int requestId,
  }) async {
    networkOps.add('POST /communities/$communityId/join-requests/$requestId/decline');
    if (failDeclineJoinRequest != null) {
      throw failDeclineJoinRequest!;
    }
    declinedJoinRequestIds.add(requestId);
    ownerJoinRequests = [
      for (final item in ownerJoinRequests)
        if (item.id == requestId) item.copyWithStatus('declined') else item,
    ];
    myJoinRequests = [
      for (final item in myJoinRequests)
        if (item.id == requestId)
          MyJoinRequest(
            id: item.id,
            communityId: item.communityId,
            communityName: item.communityName,
            status: 'declined',
            createdAt: item.createdAt,
          )
        else
          item,
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
    expect(AppRoutes.isAuthenticatedLocation('/communities/12/invite'), isTrue);
    expect(AppRoutes.isAuthenticatedLocation('/invitations'), isTrue);
    expect(AppRoutes.isAuthenticatedLocation('/join-requests'), isTrue);
    expect(AppRoutes.isAuthenticatedLocation('/communities/nope'), isFalse);
    expect(AppRoutes.isAuthenticatedLocation('/communities/search/extra'), isFalse);
    expect(AppRoutes.isAuthenticatedLocation('/communities/12/invite/extra'), isFalse);
    expect(AppRoutes.isAuthenticatedLocation('/invitations/extra'), isFalse);
    expect(AppRoutes.isAuthenticatedLocation('/join-requests/extra'), isFalse);
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
    expect(find.text('Demander à rejoindre'), findsNWidgets(2));
    expect(api.listMembersCalls, 0);
    expect(api.listMyJoinRequestsCalls, 1);
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
    expect(find.text('Demander à rejoindre'), findsOneWidget);
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

  testWidgets('admin sees invite member button', (tester) async {
    final api = _FakeCommunityApi();
    setListedRole(api, CommunityRole.admin);
    await openCommunityDetail(tester, api);
    expect(find.byKey(const ValueKey('community-detail-invite')), findsOneWidget);
    expect(find.text('Inviter un membre'), findsOneWidget);
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
    expect(opsAfterSearch.where((op) => op.startsWith('POST')), isEmpty);
    await tester.tap(find.byKey(const ValueKey('user-search-select-25')));
    await tester.pump();
    expect(find.byKey(const ValueKey('user-search-selected-notice')), findsOneWidget);
    expect(find.text(kUserSearchSelectedNotice), findsOneWidget);
    expect(api.userSearchQueries, hasLength(1));
    expect(api.networkOps, opsAfterSearch);
    expect(api.networkOps.where((op) => op.startsWith('POST')), isEmpty);
    expect(api.createInvitationCalls, isEmpty);
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

  test('created invitation payload rejects private leaks', () {
    expect(
      () => CreatedCommunityInvitation.fromJson({
        'id': 1,
        'community_id': 3,
        'invitee_user_id': 25,
        'status': 'pending',
        'email': 'hidden@example.com',
      }),
      throwsA(isA<FormatException>()),
    );
    final created = CreatedCommunityInvitation.fromJson({
      'id': 1,
      'community_id': 3,
      'invitee_user_id': 25,
      'status': 'pending',
      'created_at': '2026-10-02T12:00:00.000Z',
    });
    expect(created.inviteeUserId, 25);
    expect(created.status, 'pending');
  });

  test('received invitation payload rejects member leaks', () {
    expect(
      () => ReceivedCommunityInvitation.fromJson({
        'id': 1,
        'community_id': 3,
        'community_name': 'Jardin secret',
        'invited_by_login': 'owner42',
        'status': 'pending',
        'members': <Object>[],
      }),
      throwsA(isA<FormatException>()),
    );
    final received = ReceivedCommunityInvitation.fromJson({
      'id': 7,
      'community_id': 3,
      'community_name': 'Jardin secret',
      'invited_by_login': 'owner42',
      'status': 'pending',
      'created_at': '2026-10-02T12:00:00.000Z',
    });
    expect(received.communityName, 'Jardin secret');
    expect(received.invitedByLogin, 'owner42');
  });

  Future<void> selectMoh5(WidgetTester tester, _FakeCommunityApi api) async {
    api.userSearchResults = const [UserSearchHit(userId: 25, login: 'moh5')];
    await openUserSearch(tester, api);
    await tester.enterText(find.byKey(const ValueKey('user-search-field')), 'moh5');
    await tester.tap(find.byKey(const ValueKey('user-search-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('user-search-select-25')));
    await tester.pump();
  }

  testWidgets('send invitation posts user_id after explicit send', (tester) async {
    final api = _FakeCommunityApi();
    await selectMoh5(tester, api);
    expect(api.createInvitationCalls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('user-search-send-invite')));
    await tester.pumpAndSettle();
    expect(api.createInvitationCalls, [
      {'communityId': 3, 'userId': 25},
    ]);
    expect(find.byKey(const ValueKey('user-search-sent-notice')), findsOneWidget);
    expect(find.text(InvitationMessages.sent), findsOneWidget);
    expect(find.byKey(const ValueKey('user-search-item-25')), findsNothing);
    expect(find.byKey(const ValueKey('user-search-select-25')), findsNothing);
    expect(find.byKey(const ValueKey('user-search-send-invite')), findsNothing);
    expect((tester.widget<TextField>(find.byType(TextField)).controller?.text ?? ''), isEmpty);
    expect(find.text('Membre'), findsNothing);
    expect(api.listMembersCalls, 1);
  });

  testWidgets('send invitation maps limit reached', (tester) async {
    final api = _FakeCommunityApi()
      ..failCreateInvitation = const ApiException(
        message: 'invitation limit reached',
        statusCode: 400,
      );
    await selectMoh5(tester, api);
    await tester.tap(find.byKey(const ValueKey('user-search-send-invite')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-search-send-error')), findsOneWidget);
    expect(
      find.text(
        'Cet utilisateur a déjà refusé cinq invitations. Invitation impossible pour le moment.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('send invitation maps already member', (tester) async {
    final api = _FakeCommunityApi()
      ..failCreateInvitation = const ApiException(
        message: 'user is already a member',
        statusCode: 400,
      );
    await selectMoh5(tester, api);
    await tester.tap(find.byKey(const ValueKey('user-search-send-invite')));
    await tester.pumpAndSettle();
    expect(find.text('Cet utilisateur est déjà membre.'), findsOneWidget);
  });

  testWidgets('send invitation maps self invite', (tester) async {
    final api = _FakeCommunityApi()
      ..failCreateInvitation = const ApiException(
        message: 'cannot invite yourself',
        statusCode: 400,
      );
    await selectMoh5(tester, api);
    await tester.tap(find.byKey(const ValueKey('user-search-send-invite')));
    await tester.pumpAndSettle();
    expect(find.text('Impossible de s’inviter soi-même.'), findsOneWidget);
  });

  testWidgets('send invitation maps missing user', (tester) async {
    final api = _FakeCommunityApi()
      ..failCreateInvitation = const ApiException(
        message: 'User not found',
        statusCode: 404,
      );
    await selectMoh5(tester, api);
    await tester.tap(find.byKey(const ValueKey('user-search-send-invite')));
    await tester.pumpAndSettle();
    expect(find.text('Utilisateur introuvable'), findsOneWidget);
  });

  testWidgets('send invitation 401 shows session error', (tester) async {
    final api = _FakeCommunityApi()
      ..failCreateInvitation = const ApiException(
        message: 'Unauthorized',
        statusCode: 401,
      );
    await selectMoh5(tester, api);
    await tester.tap(find.byKey(const ValueKey('user-search-send-invite')));
    await tester.pumpAndSettle();
    expect(find.text('Session expirée'), findsOneWidget);
  });

  testWidgets('send invitation disables button while in flight', (tester) async {
    final api = _FakeCommunityApi()..holdCreateInvitation = true;
    await selectMoh5(tester, api);
    await tester.tap(find.byKey(const ValueKey('user-search-send-invite')));
    await tester.pump();
    expect(api.createInvitationHolds, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('user-search-send-invite')));
    await tester.pump();
    expect(api.createInvitationCalls, hasLength(1));
    api.createInvitationHolds.single.complete(
      const CreatedCommunityInvitation(
        id: 9,
        communityId: 3,
        inviteeUserId: 25,
        status: 'pending',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-search-sent-notice')), findsOneWidget);
  });

  testWidgets('clear selection does not send an invitation', (tester) async {
    final api = _FakeCommunityApi();
    await selectMoh5(tester, api);
    await tester.tap(find.byKey(const ValueKey('user-search-clear-selection')));
    await tester.pump();
    expect(api.createInvitationCalls, isEmpty);
    expect(find.byKey(const ValueKey('user-search-select-25')), findsOneWidget);
  });

  const sampleInvite = ReceivedCommunityInvitation(
    id: 11,
    communityId: 3,
    communityName: 'Jardin secret',
    invitedByLogin: 'owner42',
    status: 'pending',
    createdAt: '2026-10-02T12:00:00.000Z',
  );

  testWidgets('home invitations opens inbox', (tester) async {
    final api = _FakeCommunityApi()..invitations = const [sampleInvite];
    await _pumpApp(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('home-invitations')));
    await tester.pumpAndSettle();
    expect(find.byType(InvitationInboxScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('invitation-inbox-item-11')), findsOneWidget);
    expect(find.text('Jardin secret'), findsOneWidget);
    expect(find.text('Invité par owner42'), findsOneWidget);
    expect(api.listInvitationsCalls, 1);
    expect(api.getCalls, 0);
    expect(
      api.networkOps.where((op) => RegExp(r'^GET /communities/\d+').hasMatch(op)),
      isEmpty,
    );
  });

  testWidgets('community list invitations opens the same inbox', (tester) async {
    final api = _FakeCommunityApi();
    await _pumpApp(tester, api: api);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-invitations-open')));
    await tester.pumpAndSettle();
    expect(find.byType(InvitationInboxScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('invitation-inbox-empty')), findsOneWidget);
    expect(find.text(InvitationMessages.emptyInbox), findsOneWidget);
  });

  testWidgets('inbox load error can be retried', (tester) async {
    final api = _FakeCommunityApi()
      ..failListInvitations = const ApiException(message: 'Network error');
    await _pumpApp(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('home-invitations')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('invitation-inbox-error')), findsOneWidget);
    api.failListInvitations = null;
    api.invitations = const [sampleInvite];
    await tester.tap(find.byKey(const ValueKey('invitation-inbox-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('invitation-inbox-item-11')), findsOneWidget);
    expect(api.listInvitationsCalls, 2);
  });

  testWidgets('inbox 401 shows session error', (tester) async {
    final api = _FakeCommunityApi()
      ..failListInvitations = const ApiException(message: 'Unauthorized', statusCode: 401);
    await _pumpApp(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('home-invitations')));
    await tester.pumpAndSettle();
    expect(find.text('Session expirée'), findsOneWidget);
  });

  testWidgets('accept invitation removes it and refreshes communities', (tester) async {
    final api = _FakeCommunityApi()..invitations = const [sampleInvite];
    await _pumpApp(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('home-invitations')));
    await tester.pumpAndSettle();
    final listCallsBefore = api.networkOps.where((op) => op == 'GET /communities').length;
    await tester.tap(find.byKey(const ValueKey('invitation-inbox-accept-11')));
    await tester.pumpAndSettle();
    expect(api.acceptedInvitationIds, [11]);
    expect(find.byKey(const ValueKey('invitation-inbox-item-11')), findsNothing);
    expect(find.text(InvitationMessages.accepted), findsOneWidget);
    expect(find.byType(InvitationInboxScreen), findsOneWidget);
    expect(find.byType(CommunityDetailScreen), findsNothing);
    expect(api.getCalls, 0);
    expect(
      api.networkOps.where((op) => op == 'GET /communities').length,
      greaterThan(listCallsBefore),
    );
    expect(api.declinedInvitationIds, isEmpty);
  });

  testWidgets('decline invitation removes it without membership', (tester) async {
    final api = _FakeCommunityApi()..invitations = const [sampleInvite];
    await _pumpApp(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('home-invitations')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('invitation-inbox-decline-11')));
    await tester.pumpAndSettle();
    expect(api.declinedInvitationIds, [11]);
    expect(api.acceptedInvitationIds, isEmpty);
    expect(find.byKey(const ValueKey('invitation-inbox-item-11')), findsNothing);
    expect(find.text(InvitationMessages.declined), findsOneWidget);
    expect(api.listMembersCalls, 0);
  });

  testWidgets('accept 404 refreshes inbox as unavailable', (tester) async {
    final api = _FakeCommunityApi()
      ..invitations = const [sampleInvite]
      ..failAcceptInvitation = const ApiException(
        message: 'Invitation not found',
        statusCode: 404,
      );
    await _pumpApp(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('home-invitations')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('invitation-inbox-accept-11')));
    await tester.pumpAndSettle();
    expect(find.text(InvitationMessages.unavailable), findsOneWidget);
    expect(api.listInvitationsCalls, 2);
  });

  testWidgets('inbox accept ignores a second tap while in flight', (tester) async {
    final api = _FakeCommunityApi()
      ..invitations = const [sampleInvite]
      ..holdAcceptInvitation = true;
    await _pumpApp(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('home-invitations')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('invitation-inbox-accept-11')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('invitation-inbox-decline-11')));
    await tester.pump();
    expect(api.acceptInvitationHolds, hasLength(1));
    expect(api.declinedInvitationIds, isEmpty);
    api.acceptInvitationHolds.single.complete();
    await tester.pumpAndSettle();
    expect(api.acceptedInvitationIds, [11]);
  });

  test('unknown invitation API error uses a generic French fallback', () {
    expect(
      InvitationMessages.fromApi(
        const ApiException(message: 'internal relation community_invitations', statusCode: 400),
      ),
      InvitationMessages.unknown,
    );
    expect(
      InvitationMessages.fromApi(
        const ApiException(message: 'internal relation community_invitations', statusCode: 400),
      ),
      isNot(contains('community_invitations')),
    );
  });

  testWidgets('send invitation maps community not found', (tester) async {
    final api = _FakeCommunityApi()
      ..failCreateInvitation = const ApiException(
        message: 'Community not found',
        statusCode: 404,
      );
    await selectMoh5(tester, api);
    await tester.tap(find.byKey(const ValueKey('user-search-send-invite')));
    await tester.pumpAndSettle();
    expect(find.text('Communauté introuvable'), findsOneWidget);
  });

  testWidgets('send invitation maps cannot be sent', (tester) async {
    final api = _FakeCommunityApi()
      ..failCreateInvitation = const ApiException(
        message: 'invitation cannot be sent',
        statusCode: 400,
      );
    await selectMoh5(tester, api);
    await tester.tap(find.byKey(const ValueKey('user-search-send-invite')));
    await tester.pumpAndSettle();
    expect(find.text('Invitation impossible à envoyer pour le moment.'), findsOneWidget);
  });

  testWidgets('send invitation unknown error hides English payload', (tester) async {
    const secret = 'relation community_invitations violated user=25';
    final api = _FakeCommunityApi()
      ..failCreateInvitation = const ApiException(message: secret, statusCode: 400);
    await selectMoh5(tester, api);
    await tester.tap(find.byKey(const ValueKey('user-search-send-invite')));
    await tester.pumpAndSettle();
    expect(find.text(InvitationMessages.unknown), findsOneWidget);
    expect(find.textContaining('community_invitations'), findsNothing);
    expect(find.textContaining(secret), findsNothing);
  });

  testWidgets('resend invitation posts the same user_id again', (tester) async {
    final api = _FakeCommunityApi();
    await selectMoh5(tester, api);
    await tester.tap(find.byKey(const ValueKey('user-search-send-invite')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-search-sent-notice')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('user-search-field')), 'moh5');
    await tester.tap(find.byKey(const ValueKey('user-search-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('user-search-select-25')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('user-search-send-invite')));
    await tester.pumpAndSettle();
    expect(api.createInvitationCalls, [
      {'communityId': 3, 'userId': 25},
      {'communityId': 3, 'userId': 25},
    ]);
    expect(find.byKey(const ValueKey('user-search-sent-notice')), findsOneWidget);
    expect(find.text(InvitationMessages.sent), findsOneWidget);
  });

  testWidgets('community list app bar fits a 320px viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final overflowErrors = <Object>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      overflowErrors.add(details.exception);
      previousOnError?.call(details);
    };
    addTearDown(() {
      FlutterError.onError = previousOnError;
    });

    final api = _FakeCommunityApi();
    await _pumpApp(tester, api: api);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityListScreen), findsOneWidget);
    expect(find.byTooltip('Rechercher'), findsOneWidget);
    expect(find.byTooltip('Invitations'), findsOneWidget);
    expect(find.byKey(const ValueKey('community-search-open')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-invitations-open')), findsOneWidget);
    expect(
      overflowErrors.where((error) => error.toString().toLowerCase().contains('overflow')),
      isEmpty,
    );

    await tester.tap(find.byKey(const ValueKey('community-search-open')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunitySearchScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-invitations-open')));
    await tester.pumpAndSettle();
    expect(find.byType(InvitationInboxScreen), findsOneWidget);
  });

  testWidgets('accept removes the card before delayed community list returns', (tester) async {
    final api = _FakeCommunityApi()
      ..invitations = const [sampleInvite]
      ..holdList = true;
    await _pumpApp(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('home-invitations')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('invitation-inbox-item-11')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('invitation-inbox-accept-11')));
    await tester.pump();
    expect(api.acceptedInvitationIds, [11]);
    expect(api.listHolds, isNotEmpty);
    expect(find.byKey(const ValueKey('invitation-inbox-item-11')), findsNothing);
    expect(find.text(InvitationMessages.accepted), findsOneWidget);
    expect(find.byType(InvitationInboxScreen), findsOneWidget);
    expect(find.byType(CommunityDetailScreen), findsNothing);
    expect(api.getCalls, 0);
    for (final hold in api.listHolds) {
      if (!hold.isCompleted) {
        hold.complete(List<Community>.from(api.items));
      }
    }
    await tester.pumpAndSettle();
    expect(find.byType(InvitationInboxScreen), findsOneWidget);
  });

  testWidgets('failed accept keeps the invitation visible', (tester) async {
    final api = _FakeCommunityApi()
      ..invitations = const [sampleInvite]
      ..failAcceptInvitation = const ApiException(
        message: 'invitation is not pending',
        statusCode: 400,
      );
    await _pumpApp(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('home-invitations')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('invitation-inbox-accept-11')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('invitation-inbox-item-11')), findsOneWidget);
    expect(find.text('Cette invitation a déjà été traitée.'), findsOneWidget);
    expect(api.acceptedInvitationIds, isEmpty);
  });

  testWidgets('failed send keeps query and selected user', (tester) async {
    final api = _FakeCommunityApi()
      ..failCreateInvitation = const ApiException(
        message: 'user is already a member',
        statusCode: 400,
      );
    await selectMoh5(tester, api);
    await tester.tap(find.byKey(const ValueKey('user-search-send-invite')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-search-send-error')), findsOneWidget);
    expect(find.text('Cet utilisateur est déjà membre.'), findsOneWidget);
    expect(find.byKey(const ValueKey('user-search-item-25')), findsOneWidget);
    expect(find.byKey(const ValueKey('user-search-send-invite')), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, 'moh5');
  });

  testWidgets('new search works after a successful send reset', (tester) async {
    final api = _FakeCommunityApi();
    await selectMoh5(tester, api);
    await tester.tap(find.byKey(const ValueKey('user-search-send-invite')));
    await tester.pumpAndSettle();
    expect((tester.widget<TextField>(find.byType(TextField)).controller?.text ?? ''), isEmpty);
    api.userSearchResults = const [UserSearchHit(userId: 26, login: 'moh6')];
    await tester.enterText(find.byKey(const ValueKey('user-search-field')), 'moh6');
    await tester.tap(find.byKey(const ValueKey('user-search-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-search-item-26')), findsOneWidget);
    expect(find.byKey(const ValueKey('user-search-sent-notice')), findsNothing);
  });

  test('sent invitation payload rejects secrets and inactive statuses', () {
    expect(
      () => SentCommunityInvitation.fromJson({
        'id': 1,
        'invitee_login': 'moh5',
        'status': 'pending',
        'phone': '+33600000000',
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => SentCommunityInvitation.fromJson({
        'id': 1,
        'invitee_login': 'moh5',
        'status': 'cancelled',
      }),
      throwsA(isA<FormatException>()),
    );
    final declined = SentCommunityInvitation.fromJson({
      'id': 4,
      'invitee_login': 'moh5',
      'status': 'declined',
      'created_at': '2026-10-01T12:00:00.000Z',
      'declined_at': '2026-10-02T12:00:00.000Z',
    });
    expect(declined.inviteeLogin, 'moh5');
    expect(declined.declinedOnLabel, isNotEmpty);
  });

  testWidgets('owner sees sent invitations with French statuses', (tester) async {
    final api = _FakeCommunityApi()
      ..sentInvitations = const [
        SentCommunityInvitation(
          id: 21,
          status: 'pending',
          inviteeLogin: 'moh5',
        ),
        SentCommunityInvitation(
          id: 22,
          status: 'accepted',
          inviteeLogin: 'ada',
        ),
        SentCommunityInvitation(
          id: 23,
          status: 'declined',
          inviteeLogin: 'leo',
          declinedAt: '2026-10-02T12:00:00.000Z',
        ),
      ];
    await openCommunityDetail(tester, api);
    expect(find.byKey(const ValueKey('community-sent-invitations-title')), findsOneWidget);
    expect(find.text('Invitations envoyées'), findsOneWidget);
    expect(find.text('En attente'), findsOneWidget);
    expect(find.text('Acceptée'), findsOneWidget);
    expect(find.text('Refusée'), findsOneWidget);
    expect(find.byKey(const ValueKey('community-sent-invitation-declined-at-23')), findsOneWidget);
    expect(find.textContaining('Refusée le'), findsOneWidget);
    expect(find.text('Annuler'), findsNothing);
    expect(find.text('Renvoyer'), findsNothing);
    expect(api.listSentInvitationsCalls, 1);
    expect(
      api.networkOps.where((op) => op == 'GET /communities/3/invitations'),
      isNotEmpty,
    );
  });

  testWidgets('admin loads sent invitations', (tester) async {
    final api = _FakeCommunityApi()
      ..sentInvitations = const [
        SentCommunityInvitation(id: 21, status: 'pending', inviteeLogin: 'moh5'),
      ];
    setListedRole(api, CommunityRole.admin);
    await openCommunityDetail(tester, api);
    expect(find.byKey(const ValueKey('community-sent-invitations-title')), findsOneWidget);
    expect(find.text('Invitations envoyées'), findsOneWidget);
    expect(api.listSentInvitationsCalls, 1);
    expect(
      api.networkOps.where((op) => op == 'GET /communities/3/invitations'),
      isNotEmpty,
    );
  });

  testWidgets('member does not load sent invitations', (tester) async {
    final api = _FakeCommunityApi();
    setListedRole(api, CommunityRole.member);
    await openCommunityDetail(tester, api);
    expect(find.text('Invitations envoyées'), findsNothing);
    expect(api.listSentInvitationsCalls, 0);
  });

  testWidgets('owner sent invitations empty state', (tester) async {
    final api = _FakeCommunityApi();
    await openCommunityDetail(tester, api);
    expect(find.byKey(const ValueKey('community-sent-invitations-empty')), findsOneWidget);
    expect(find.text(InvitationMessages.sentEmpty), findsOneWidget);
  });

  testWidgets('owner sent invitations shows a loading state', (tester) async {
    final api = _FakeCommunityApi()..holdListSentInvitations = true;
    await _pumpApp(tester, api: api);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-list-item-3')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('community-sent-invitations-title')), findsOneWidget);
    expect(find.byType(AppLoading), findsWidgets);
    for (final hold in api.listSentHolds) {
      if (!hold.isCompleted) {
        hold.complete(const <SentCommunityInvitation>[]);
      }
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-sent-invitations-empty')), findsOneWidget);
  });

  testWidgets('owner sent invitations error can be retried', (tester) async {
    final api = _FakeCommunityApi()
      ..failListSentInvitations = const ApiException(message: 'Network error');
    await openCommunityDetail(tester, api);
    expect(find.byKey(const ValueKey('community-sent-invitations-error')), findsOneWidget);
    api.failListSentInvitations = null;
    api.sentInvitations = const [
      SentCommunityInvitation(id: 21, status: 'pending', inviteeLogin: 'moh5'),
    ];
    await tester.tap(find.byKey(const ValueKey('community-sent-invitations-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-sent-invitation-login-21')), findsOneWidget);
    expect(api.listSentInvitationsCalls, 2);
  });

  test('join request payloads reject secrets and invalid statuses', () {
    expect(
      () => MyJoinRequest.fromJson({
        'id': 1,
        'community_id': 9,
        'community_name': 'Atelier lumineux',
        'status': 'pending',
        'phone': '+33600000000',
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => OwnerJoinRequest.fromJson({
        'id': 1,
        'requester_login': 'invitee7',
        'status': 'cancelled',
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => MyJoinRequest.fromJson({
        'id': 1,
        'community_id': 9,
        'community_name': 'Atelier lumineux',
        'status': 'pending',
        'user_id': 7,
      }),
      throwsA(isA<FormatException>()),
    );
    final mine = MyJoinRequest.fromJson({
      'id': 1,
      'community_id': 9,
      'community_name': 'Atelier lumineux',
      'status': 'cancelled',
      'created_at': '2026-10-03T12:00:00.000Z',
    });
    expect(mine.communityName, 'Atelier lumineux');
    expect(JoinRequestMessages.mineStatusLabel(mine.status), 'Annulée');
  });

  Future<void> searchFor(
    WidgetTester tester,
    _FakeCommunityApi api, {
    String query = 'Cercle',
  }) async {
    await openSearch(tester, api);
    await tester.enterText(find.byKey(const ValueKey('community-search-field')), query);
    await tester.tap(find.byKey(const ValueKey('community-search-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('non-member private search shows ask to join', (tester) async {
    final api = _FakeCommunityApi()
      ..searchResults = const [
        CommunitySearchPreview(id: 99, name: 'Cercle fermé', memberCount: 4),
      ];
    await searchFor(tester, api);
    expect(find.byKey(const ValueKey('community-search-join-99')), findsOneWidget);
    expect(find.text('Demander à rejoindre'), findsOneWidget);
    expect(find.text('Rejoindre'), findsNothing);
  });

  testWidgets('successful join request shows pending and blocks a second send', (tester) async {
    final api = _FakeCommunityApi()
      ..searchResults = const [
        CommunitySearchPreview(id: 99, name: 'Cercle fermé', memberCount: 4),
      ];
    await searchFor(tester, api);
    await tester.tap(find.byKey(const ValueKey('community-search-join-99')));
    await tester.pumpAndSettle();
    expect(api.createJoinRequestCalls, [99]);
    expect(find.text('Demande en attente'), findsWidgets);
    expect(find.byKey(const ValueKey('community-search-pending-99')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-search-join-99')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('community-search-pending-99')));
    await tester.pump();
    expect(api.createJoinRequestCalls, [99]);
  });

  testWidgets('already pending join request shows waiting state', (tester) async {
    final api = _FakeCommunityApi()
      ..searchResults = const [
        CommunitySearchPreview(id: 99, name: 'Cercle fermé', memberCount: 4),
      ]
      ..myJoinRequests = const [
        MyJoinRequest(
          id: 12,
          communityId: 99,
          communityName: 'Cercle fermé',
          status: 'pending',
          createdAt: '2026-10-03T12:00:00.000Z',
        ),
      ];
    await searchFor(tester, api);
    expect(find.byKey(const ValueKey('community-search-join-99')), findsNothing);
    expect(find.byKey(const ValueKey('community-search-pending-99')), findsOneWidget);
    expect(find.text('Demande en attente'), findsOneWidget);
    expect(api.createJoinRequestCalls, isEmpty);
  });

  testWidgets('declined join request can be sent again', (tester) async {
    final api = _FakeCommunityApi()
      ..searchResults = const [
        CommunitySearchPreview(id: 99, name: 'Cercle fermé', memberCount: 4),
      ]
      ..myJoinRequests = const [
        MyJoinRequest(
          id: 12,
          communityId: 99,
          communityName: 'Cercle fermé',
          status: 'declined',
          createdAt: '2026-10-01T12:00:00.000Z',
        ),
      ];
    await searchFor(tester, api);
    expect(find.byKey(const ValueKey('community-search-join-99')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-search-join-99')));
    await tester.pumpAndSettle();
    expect(api.createJoinRequestCalls, [99]);
    expect(find.byKey(const ValueKey('community-search-pending-99')), findsOneWidget);
  });

  testWidgets('member community search does not show join action', (tester) async {
    final api = _FakeCommunityApi()
      ..searchResults = const [
        CommunitySearchPreview(id: 3, name: 'Jardin secret', memberCount: 1),
      ];
    await searchFor(tester, api, query: 'Jardin');
    expect(find.byKey(const ValueKey('community-search-join-3')), findsNothing);
    expect(find.text('Demander à rejoindre'), findsNothing);
  });

  testWidgets('my join requests lists all statuses', (tester) async {
    final api = _FakeCommunityApi()
      ..myJoinRequests = const [
        MyJoinRequest(
          id: 1,
          communityId: 9,
          communityName: 'Atelier lumineux',
          status: 'pending',
          createdAt: '2026-10-03T12:00:00.000Z',
        ),
        MyJoinRequest(
          id: 2,
          communityId: 10,
          communityName: 'Cercle des autres',
          status: 'accepted',
        ),
        MyJoinRequest(
          id: 3,
          communityId: 11,
          communityName: 'Club du soir',
          status: 'declined',
        ),
        MyJoinRequest(
          id: 4,
          communityId: 12,
          communityName: 'Salon annulé',
          status: 'cancelled',
        ),
      ];
    await _pumpApp(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('home-join-requests')));
    await tester.pumpAndSettle();
    expect(find.byType(MyJoinRequestsScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('my-join-request-item-1')), findsOneWidget);
    expect(find.text('Atelier lumineux'), findsOneWidget);
    expect(find.text('Demande en attente'), findsOneWidget);
    expect(find.text('Acceptée'), findsOneWidget);
    expect(find.text('Refusée'), findsOneWidget);
    expect(find.text('Annulée'), findsOneWidget);
    expect(api.listMyJoinRequestsCalls, 1);
    expect(api.networkOps.where((op) => op == 'GET /join-requests/mine'), isNotEmpty);
  });

  testWidgets('community list opens my join requests', (tester) async {
    final api = _FakeCommunityApi();
    await _pumpApp(tester, api: api);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-join-requests-open')));
    await tester.pumpAndSettle();
    expect(find.byType(MyJoinRequestsScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('my-join-requests-empty')), findsOneWidget);
  });

  testWidgets('owner sees pending and history join requests', (tester) async {
    final api = _FakeCommunityApi()
      ..ownerJoinRequests = const [
        OwnerJoinRequest(id: 31, status: 'pending', requesterLogin: 'invitee7'),
        OwnerJoinRequest(id: 32, status: 'accepted', requesterLogin: 'ada'),
        OwnerJoinRequest(id: 33, status: 'declined', requesterLogin: 'leo'),
      ];
    await openCommunityDetail(tester, api);
    expect(find.byKey(const ValueKey('community-join-requests-title')), findsOneWidget);
    expect(find.text('Demandes d’adhésion'), findsOneWidget);
    expect(find.byKey(const ValueKey('community-join-request-pending-31')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-join-accept-31')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-join-decline-31')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-join-history-32')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-join-history-33')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-join-accept-32')), findsNothing);
    expect(api.listCommunityJoinRequestsCalls, 1);
  });

  testWidgets('admin does not see join request owner actions', (tester) async {
    final api = _FakeCommunityApi()
      ..ownerJoinRequests = const [
        OwnerJoinRequest(id: 31, status: 'pending', requesterLogin: 'invitee7'),
      ];
    setListedRole(api, CommunityRole.admin);
    await openCommunityDetail(tester, api);
    expect(find.byKey(const ValueKey('community-join-requests-title')), findsNothing);
    expect(find.byKey(const ValueKey('community-join-accept-31')), findsNothing);
    expect(api.listCommunityJoinRequestsCalls, 0);
  });

  testWidgets('member does not see join request owner actions', (tester) async {
    final api = _FakeCommunityApi();
    setListedRole(api, CommunityRole.member);
    await openCommunityDetail(tester, api);
    expect(find.text('Demandes d’adhésion'), findsNothing);
    expect(api.listCommunityJoinRequestsCalls, 0);
  });

  Future<void> pumpOwnerJoinRequests(WidgetTester tester, _FakeCommunityApi api) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authTokenStorageProvider.overrideWithValue(
            InMemoryAuthTokenStorage(
              accessToken: 'access-test',
              refreshToken: 'refresh-test',
            ),
          ),
          communityApiServiceProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: CommunityJoinRequestsSection(communityId: 3),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('owner accept moves request to history immediately', (tester) async {
    final api = _FakeCommunityApi()
      ..ownerJoinRequests = const [
        OwnerJoinRequest(id: 31, status: 'pending', requesterLogin: 'invitee7'),
      ];
    await pumpOwnerJoinRequests(tester, api);
    await tester.tap(find.byKey(const ValueKey('community-join-accept-31')));
    await tester.pumpAndSettle();
    expect(api.acceptedJoinRequestIds, [31]);
    expect(find.byKey(const ValueKey('community-join-accept-31')), findsNothing);
    expect(find.byKey(const ValueKey('community-join-request-pending-31')), findsNothing);
    expect(find.byKey(const ValueKey('community-join-history-31')), findsOneWidget);
    expect(find.text('Demande acceptée.'), findsOneWidget);
    expect(find.text('Acceptée'), findsOneWidget);
    expect(
      api.networkOps.where((op) => op == 'POST /communities/3/join-requests/31/accept'),
      isNotEmpty,
    );
  });

  testWidgets('owner decline moves request to history immediately', (tester) async {
    final api = _FakeCommunityApi()
      ..ownerJoinRequests = const [
        OwnerJoinRequest(id: 31, status: 'pending', requesterLogin: 'invitee7'),
      ];
    await pumpOwnerJoinRequests(tester, api);
    await tester.tap(find.byKey(const ValueKey('community-join-decline-31')));
    await tester.pumpAndSettle();
    expect(api.declinedJoinRequestIds, [31]);
    expect(api.acceptedJoinRequestIds, isEmpty);
    expect(find.byKey(const ValueKey('community-join-decline-31')), findsNothing);
    expect(find.byKey(const ValueKey('community-join-history-31')), findsOneWidget);
    expect(find.text('Demande refusée.'), findsOneWidget);
    expect(find.text('Refusée'), findsOneWidget);
  });

  testWidgets('stale owner join action refreshes from the server', (tester) async {
    final api = _FakeCommunityApi()
      ..ownerJoinRequests = const [
        OwnerJoinRequest(id: 31, status: 'pending', requesterLogin: 'invitee7'),
      ]
      ..failAcceptJoinRequest = const ApiException(
        message: 'join request is not pending',
        statusCode: 400,
      );
    await pumpOwnerJoinRequests(tester, api);
    api.ownerJoinRequests = const [
      OwnerJoinRequest(id: 31, status: 'accepted', requesterLogin: 'invitee7'),
    ];
    await tester.tap(find.byKey(const ValueKey('community-join-accept-31')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-join-accept-31')), findsNothing);
    expect(find.byKey(const ValueKey('community-join-history-31')), findsOneWidget);
    expect(find.text('Cette demande a déjà été traitée.'), findsOneWidget);
    expect(api.listCommunityJoinRequestsCalls, greaterThan(1));
  });

  testWidgets('already pending API error shows waiting state', (tester) async {
    final api = _FakeCommunityApi()
      ..searchResults = const [
        CommunitySearchPreview(id: 99, name: 'Cercle fermé', memberCount: 4),
      ]
      ..failCreateJoinRequest = const ApiException(
        message: 'join request already pending',
        statusCode: 400,
      );
    await searchFor(tester, api);
    await tester.tap(find.byKey(const ValueKey('community-search-join-99')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-search-pending-99')), findsOneWidget);
    expect(find.text('Demande en attente'), findsWidgets);
  });

  test('oldestCurrentAdmin is deterministic', () {
    const owner = CommunityMember(userId: 1, login: 'owner', role: CommunityRole.owner);
    final lateAdmin = CommunityMember(
      userId: 4,
      login: 'late',
      role: CommunityRole.admin,
      roleAssignedAt: DateTime.utc(2026, 3, 1),
    );
    final earlyAdmin = CommunityMember(
      userId: 9,
      login: 'early',
      role: CommunityRole.admin,
      roleAssignedAt: DateTime.utc(2026, 1, 1),
    );
    expect(oldestCurrentAdmin([owner, lateAdmin, earlyAdmin])!.userId, 9);
    expect(oldestCurrentAdmin([owner]), isNull);
  });

  testWidgets('owner member tile exposes promote and remove', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: CommunityMemberTile(
            member: const CommunityMember(userId: 7, login: 'member7', role: CommunityRole.member),
            viewerRole: CommunityRole.owner,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('community-promote-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-remove-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-demote-7')), findsNothing);
  });

  testWidgets('admin member tile has no governance controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: CommunityMemberTile(
            member: const CommunityMember(userId: 7, login: 'member7', role: CommunityRole.member),
            viewerRole: CommunityRole.admin,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('community-promote-7')), findsNothing);
    expect(find.byKey(const ValueKey('community-remove-7')), findsNothing);
  });

  testWidgets('member member tile has no governance controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: CommunityMemberTile(
            member: const CommunityMember(userId: 9, login: 'admin9', role: CommunityRole.admin),
            viewerRole: CommunityRole.member,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('community-demote-9')), findsNothing);
    expect(find.byKey(const ValueKey('community-remove-9')), findsNothing);
  });

  testWidgets('admin leave bar is available', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: CommunityLeaveBar(myRole: CommunityRole.admin, onLeave: () {}),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('community-leave')), findsOneWidget);
    expect(find.text('Quitter la communauté'), findsOneWidget);
  });

  testWidgets('owner leave without admin explains the block', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: AppButton(
                label: 'open',
                onPressed: () {
                  showOwnerCannotLeave(context, hasMembers: false);
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-owner-cannot-leave')), findsOneWidget);
    expect(find.textContaining('sans owner'), findsOneWidget);
  });

  testWidgets('owner transfer dialog names the successor', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: AppButton(
                label: 'open',
                onPressed: () {
                  confirmOwnerTransfer(context, successorLogin: 'admin9');
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-transfer-confirm')), findsOneWidget);
    expect(find.textContaining('admin9'), findsOneWidget);
  });

  testWidgets('owner remove dialog asks for confirmation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: AppButton(
                label: 'open',
                onPressed: () {
                  confirmRemoveMember(context, login: 'member7');
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-remove-confirm')), findsOneWidget);
    expect(find.textContaining('member7'), findsOneWidget);
  });

  Future<void> pumpLeaveFlow(
    WidgetTester tester, {
    required List<CommunityMember> members,
    required CommunityRole myRole,
    required List<int> promoted,
    required List<int> left,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: AppButton(
                key: const ValueKey('start-leave-flow'),
                label: 'leave',
                onPressed: () {
                  runCommunityLeaveFlow(
                    context: context,
                    myRole: myRole,
                    members: members,
                    updateMemberRole: ({required int userId, required String role}) async {
                      promoted.add(userId);
                      expect(role, 'admin');
                      return true;
                    },
                    leave: () async {
                      left.add(1);
                      return true;
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('start-leave-flow')));
    await tester.pumpAndSettle();
  }

  testWidgets('owner without admin sees member picker instead of a hard stop', (tester) async {
    await pumpLeaveFlow(
      tester,
      myRole: CommunityRole.owner,
      members: const [
        CommunityMember(userId: 1, login: 'tgjjk', role: CommunityRole.owner),
        CommunityMember(userId: 7, login: 'member7', role: CommunityRole.member),
        CommunityMember(userId: 8, login: 'member8', role: CommunityRole.member),
      ],
      promoted: <int>[],
      left: <int>[],
    );
    expect(find.byKey(const ValueKey('community-no-admin-picker')), findsOneWidget);
    expect(find.text('Aucun administrateur'), findsOneWidget);
    expect(find.textContaining('Désignez un membre'), findsOneWidget);
    expect(find.byKey(const ValueKey('community-no-admin-option-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-no-admin-option-8')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-owner-cannot-leave')), findsNothing);
  });

  testWidgets('owner without admin can promote a chosen member then transfer', (tester) async {
    final promoted = <int>[];
    final left = <int>[];
    await pumpLeaveFlow(
      tester,
      myRole: CommunityRole.owner,
      members: const [
        CommunityMember(userId: 1, login: 'tgjjk', role: CommunityRole.owner),
        CommunityMember(userId: 7, login: 'member7', role: CommunityRole.member),
        CommunityMember(userId: 8, login: 'member8', role: CommunityRole.member),
      ],
      promoted: promoted,
      left: left,
    );
    await tester.tap(find.byKey(const ValueKey('community-no-admin-option-8')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('community-no-admin-continue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-promote-confirm')), findsOneWidget);
    expect(find.textContaining('member8'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-promote-confirm-yes')));
    await tester.pumpAndSettle();
    expect(promoted, [8]);
    expect(find.byKey(const ValueKey('community-transfer-confirm')), findsOneWidget);
    expect(find.textContaining('member8'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('community-transfer-confirm-yes')));
    await tester.pumpAndSettle();
    expect(left, [1]);
  });

  testWidgets('cancelling the no-admin picker does not promote or leave', (tester) async {
    final promoted = <int>[];
    final left = <int>[];
    await pumpLeaveFlow(
      tester,
      myRole: CommunityRole.owner,
      members: const [
        CommunityMember(userId: 1, login: 'tgjjk', role: CommunityRole.owner),
        CommunityMember(userId: 7, login: 'member7', role: CommunityRole.member),
      ],
      promoted: promoted,
      left: left,
    );
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(promoted, isEmpty);
    expect(left, isEmpty);
    expect(find.byKey(const ValueKey('community-no-admin-picker')), findsNothing);
  });

  testWidgets('cancelling promote confirmation does not transfer', (tester) async {
    final promoted = <int>[];
    final left = <int>[];
    await pumpLeaveFlow(
      tester,
      myRole: CommunityRole.owner,
      members: const [
        CommunityMember(userId: 1, login: 'tgjjk', role: CommunityRole.owner),
        CommunityMember(userId: 7, login: 'member7', role: CommunityRole.member),
      ],
      promoted: promoted,
      left: left,
    );
    await tester.tap(find.byKey(const ValueKey('community-no-admin-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(promoted, isEmpty);
    expect(left, isEmpty);
  });

  testWidgets('solo owner still cannot leave without a successor', (tester) async {
    final promoted = <int>[];
    final left = <int>[];
    await pumpLeaveFlow(
      tester,
      myRole: CommunityRole.owner,
      members: const [
        CommunityMember(userId: 1, login: 'tgjjk', role: CommunityRole.owner),
      ],
      promoted: promoted,
      left: left,
    );
    expect(find.byKey(const ValueKey('community-owner-cannot-leave')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-no-admin-picker')), findsNothing);
    expect(promoted, isEmpty);
    expect(left, isEmpty);
  });
}
