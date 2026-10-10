import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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
import 'package:mobile/features/community/models/community_identity_upload.dart';
import 'package:mobile/features/community/presentation/widgets/community_avatar.dart';
import 'package:mobile/features/chronique/media/chronique_local_media_picker.dart';
import 'package:mobile/features/chronique/models/media_draft.dart';
import 'package:mobile/features/chronique/providers/chronique_providers.dart';
import 'package:mobile/features/chronique/services/chronique_media_upload_client.dart';
import 'package:mobile/features/community/models/community_fields.dart';
import 'package:mobile/features/community/models/community_comment.dart';
import 'package:mobile/features/community/models/community_publication.dart';
import 'package:mobile/features/community/models/invitation_messages.dart';
import 'package:mobile/features/community/models/join_request.dart';
import 'package:mobile/features/community/models/join_request_messages.dart';
import 'package:mobile/features/community/presentation/screens/community_comment_traces_screen.dart';
import 'package:mobile/features/community/presentation/screens/community_detail_screen.dart';
import 'package:mobile/features/community/presentation/screens/community_list_screen.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/widgets/app_button.dart';
import 'package:mobile/core/widgets/app_card.dart';
import 'package:mobile/core/widgets/app_loading.dart';
import 'package:mobile/features/community/presentation/screens/community_search_screen.dart';
import 'package:mobile/features/chronique/models/chronique.dart';
import 'package:mobile/features/chronique/models/chronique_correction_window.dart';
import 'package:mobile/features/chronique/models/chronique_date.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_card_menu.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_media_viewer.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_ready_remote_media_list.dart';
import 'package:mobile/features/community/presentation/screens/community_publication_detail_screen.dart';
import 'package:mobile/features/community/presentation/screens/edit_community_publication_screen.dart';
import 'package:mobile/features/community/presentation/widgets/community_comments_section.dart';
import 'package:mobile/features/community/presentation/screens/create_community_publication_screen.dart';
import 'package:mobile/features/community/presentation/screens/create_community_screen.dart';
import 'package:mobile/features/community/presentation/screens/my_community_publications_screen.dart';
import 'package:mobile/features/community/presentation/screens/my_favorites_screen.dart';
import 'package:mobile/features/community/presentation/state/my_favorites_controller.dart';
import 'package:mobile/features/chronique/models/chronique_page.dart';
import 'package:mobile/features/community/presentation/screens/invitation_inbox_screen.dart';
import 'package:mobile/features/community/presentation/screens/my_join_requests_screen.dart';
import 'package:mobile/features/community/presentation/screens/user_search_screen.dart';
import 'package:mobile/features/community/presentation/widgets/community_join_requests_section.dart';
import 'package:mobile/features/community/presentation/widgets/community_leave_bar.dart';
import 'package:mobile/features/community/presentation/widgets/community_member_dialogs.dart';
import 'package:mobile/features/community/presentation/widgets/community_member_tile.dart';
import 'package:mobile/features/community/presentation/widgets/community_owner_leave_flow.dart';
import 'package:mobile/features/community/presentation/state/community_feed_controller.dart';
import 'package:mobile/features/community/presentation/state/community_publication_sync.dart';
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

  ApiException? failIdentityUpload;
  ApiException? failIdentityComplete;
  String? lastIdentitySlot;
  String? lastIdentityUploadId;

  @override
  Future<CommunityIdentityUploadSession> createIdentityUpload({
    required String accessToken,
    required int communityId,
    required String slot,
    required Map<String, dynamic> data,
  }) async {
    networkOps.add('POST /communities/$communityId/$slot/uploads');
    lastIdentitySlot = slot;
    if (failIdentityUpload != null) {
      throw failIdentityUpload!;
    }
    return CommunityIdentityUploadSession(
      slot: slot,
      uploadId: 'opaque-upload',
      method: 'PUT',
      url: 'https://upload.test/identity',
      headers: const {'Content-Type': 'image/jpeg'},
    );
  }

  @override
  Future<Community> completeIdentityUpload({
    required String accessToken,
    required int communityId,
    required String slot,
    required String uploadId,
  }) async {
    networkOps.add('POST /communities/$communityId/$slot/complete');
    lastIdentityUploadId = uploadId;
    if (failIdentityComplete != null) {
      throw failIdentityComplete!;
    }
    final index = items.indexWhere((item) => item.id == communityId);
    if (index < 0) {
      throw const ApiException(message: 'Community not found', statusCode: 404);
    }
    final current = items[index];
    final updated = current.copyWith(
      avatarReadUrl: slot == 'avatar' ? 'https://read.test/avatar.jpg' : current.avatarReadUrl,
      bannerReadUrl: slot == 'banner' ? 'https://read.test/banner.jpg' : current.bannerReadUrl,
    );
    items[index] = updated;
    return updated;
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
    items.removeWhere((item) => item.id == communityId);
    return <String, dynamic>{'left': true, 'transferred': false};
  }

  List<CommunityPublication> publications = const [];
  List<CommunityPublication> myPublications = const [];
  final List<Map<String, dynamic>> createPublicationCalls = <Map<String, dynamic>>[];
  final List<CommunityPublication> _removedPublications = <CommunityPublication>[];
  final List<int> deletedPublicationIds = <int>[];
  final List<int> restoredPublicationIds = <int>[];
  final List<int> patchedPublicationIds = <int>[];
  String? lastPatchTitle;
  String? lastPatchBody;
  int nextPublicationId = 90;
  ApiException? failListPublications;
  ApiException? failCreatePublication;
  ApiException? failGetPublication;
  int viewerUserId = 1;
  ApiException? failPatchPublication;
  ApiException? failDeletePublication;
  ApiException? failRestorePublication;

  @override
  Future<CommunityPublication> createPublication({
    required String accessToken,
    required int communityId,
    required String body,
    String? title,
    String publish = 'now',
    String? scheduledAt,
    bool isTimeLimited = false,
    String? expiresAt,
    bool commentsEnabled = false,
    int initialMediaCount = 0,
  }) async {
    networkOps.add('POST /communities/$communityId/publications');
    createPublicationCalls.add(<String, dynamic>{
      'communityId': communityId,
      'body': body,
      'title': title,
      'publish': publish,
      'scheduledAt': scheduledAt,
      'isTimeLimited': isTimeLimited,
      'expiresAt': expiresAt,
      'commentsEnabled': commentsEnabled,
      'initialMediaCount': initialMediaCount,
    });
    if (failCreatePublication != null) {
      throw failCreatePublication!;
    }
    final publication = CommunityPublication(
      id: nextPublicationId++,
      communityId: communityId,
      author: const CommunityPublicationAuthor(
        userId: 1,
        login: 'tgjjk',
        isFormerMember: false,
      ),
      body: body,
      title: title,
      status: publish == 'schedule' ? 'scheduled' : 'active',
      scheduledAt: scheduledAt,
      commentsEnabled: commentsEnabled,
      isTimeLimited: isTimeLimited,
      expiresAt: expiresAt,
    );
    publications = [...publications, publication];
    return publication;
  }

  @override
  Future<CommunityPublicationPage> listPublications({
    required String accessToken,
    required int communityId,
  }) async {
    networkOps.add('GET /communities/$communityId/publications');
    if (failListPublications != null) {
      throw failListPublications!;
    }
    return CommunityPublicationPage(
      items: [
        for (final item in publications)
          if (item.communityId == communityId && item.status == 'active') item,
      ],
    );
  }

  @override
  Future<CommunityPublication> getPublication({
    required String accessToken,
    required int communityId,
    required int publicationId,
  }) async {
    networkOps.add('GET /communities/$communityId/publications/$publicationId');
    if (failGetPublication != null) {
      throw failGetPublication!;
    }
    final found = publications.firstWhere(
      (item) => item.id == publicationId && item.communityId == communityId,
      orElse: () => throw const ApiException(
        message: 'Community publication not found',
        statusCode: 404,
      ),
    );
    if (found.author.userId != viewerUserId) {
      throw const ApiException(
        message: 'Community publication not found',
        statusCode: 404,
      );
    }
    return found;
  }

  @override
  Future<CommunityPublication> patchPublication({
    required String accessToken,
    required int communityId,
    required int publicationId,
    String? title,
    String? body,
  }) async {
    networkOps.add('PATCH /communities/$communityId/publications/$publicationId');
    patchedPublicationIds.add(publicationId);
    lastPatchTitle = title;
    lastPatchBody = body;
    if (failPatchPublication != null) {
      throw failPatchPublication!;
    }
    publications = [
      for (final item in publications)
        if (item.id == publicationId) _copyPublication(item, title: title, body: body) else item,
    ];
    myPublications = [
      for (final item in myPublications)
        if (item.id == publicationId) _copyPublication(item, title: title, body: body) else item,
    ];
    return [...publications, ...myPublications].firstWhere((item) => item.id == publicationId);
  }

  @override
  Future<void> deletePublication({
    required String accessToken,
    required int communityId,
    required int publicationId,
  }) async {
    networkOps.add('DELETE /communities/$communityId/publications/$publicationId');
    deletedPublicationIds.add(publicationId);
    if (failDeletePublication != null) {
      throw failDeletePublication!;
    }
    for (final item in publications) {
      if (item.id == publicationId) {
        _removedPublications.add(item);
      }
    }
    for (final item in myPublications) {
      if (item.id == publicationId && !_removedPublications.any((removed) => removed.id == item.id)) {
        _removedPublications.add(item);
      }
    }
    publications = [for (final item in publications) if (item.id != publicationId) item];
    myPublications = [for (final item in myPublications) if (item.id != publicationId) item];
  }

  @override
  Future<CommunityPublication> restorePublication({
    required String accessToken,
    required int communityId,
    required int publicationId,
  }) async {
    networkOps.add('POST /communities/$communityId/publications/$publicationId/restore');
    restoredPublicationIds.add(publicationId);
    if (failRestorePublication != null) {
      throw failRestorePublication!;
    }
    final index = _removedPublications.lastIndexWhere((item) => item.id == publicationId);
    if (index < 0) {
      throw const ApiException(message: 'Not found', statusCode: 404);
    }
    final restored = _removedPublications.removeAt(index);
    if (!publications.any((item) => item.id == restored.id) && restored.status == 'active') {
      publications = [...publications, restored];
    }
    if (!myPublications.any((item) => item.id == restored.id)) {
      myPublications = [...myPublications, restored];
    }
    return restored;
  }

  @override
  Future<CommunityPublicationPage> listMyPublications({
    required String accessToken,
    required String scope,
  }) async {
    networkOps.add('GET /me/community-publications');
    return CommunityPublicationPage(
      items: [
        for (final item in myPublications)
          if (_matchesMeScope(item, scope)) item,
      ],
    );
  }

  @override
  Future<CommunityPublication> getMyPublication({
    required String accessToken,
    required int publicationId,
  }) async {
    networkOps.add('GET /me/community-publications/$publicationId');
    return myPublications.firstWhere(
      (item) => item.id == publicationId,
      orElse: () => throw const ApiException(message: 'Not found', statusCode: 404),
    );
  }

  ApiException? failLike;
  bool holdLike = false;
  final List<Completer<void>> likeHolds = <Completer<void>>[];
  List<CommunityComment> comments = const [];
  List<CommunityCommentTrace> traces = const [];
  final List<Map<String, dynamic>> createCommentCalls = <Map<String, dynamic>>[];
  final List<int> likedPublicationIds = <int>[];
  final List<int> unlikedPublicationIds = <int>[];
  int nextCommentId = 500;

  CommunityPublication _withLike(CommunityPublication item, CommunityLikeState like) {
    return item.copyWith(likedByMe: like.likedByMe, likeCount: like.likeCount);
  }

  CommunityPublication _withFavorite(CommunityPublication item, CommunityFavoriteState favorite) {
    return item.copyWith(
      favoritedByMe: favorite.favoritedByMe,
      favoriteCount: favorite.favoriteCount,
    );
  }

  ApiException? failFavorite;
  bool holdFavorite = false;
  final List<Completer<void>> favoriteHolds = <Completer<void>>[];
  final List<int> favoritedPublicationIds = <int>[];
  final List<int> unfavoritedPublicationIds = <int>[];
  List<CommunityPublication> myFavorites = const [];
  ChroniqueCursor? myFavoritesNext;
  ApiException? failListMyFavorites;
  bool holdListMyFavorites = false;
  final List<Completer<CommunityPublicationPage>> listMyFavoritesHolds =
      <Completer<CommunityPublicationPage>>[];
  int listMyFavoritesCalls = 0;

  CommunityPublication _byId(int publicationId) {
    return [...publications, ...myPublications].firstWhere(
      (item) => item.id == publicationId,
      orElse: () => throw const ApiException(message: 'Not found', statusCode: 404),
    );
  }

  void _replacePublication(CommunityPublication updated) {
    publications = [
      for (final item in publications)
        if (item.id == updated.id) updated else item,
    ];
    myPublications = [
      for (final item in myPublications)
        if (item.id == updated.id) updated else item,
    ];
    myFavorites = [
      for (final item in myFavorites)
        if (item.id == updated.id) updated else item,
    ];
  }

  @override
  Future<CommunityLikeState> likePublication({
    required String accessToken,
    required int communityId,
    required int publicationId,
  }) async {
    networkOps.add('PUT /communities/$communityId/publications/$publicationId/like');
    if (failLike != null) {
      throw failLike!;
    }
    if (holdLike) {
      final hold = Completer<void>();
      likeHolds.add(hold);
      await hold.future;
    }
    likedPublicationIds.add(publicationId);
    final current = _byId(publicationId);
    final like = CommunityLikeState(
      liked: true,
      likeCount: current.likedByMe ? current.likeCount : current.likeCount + 1,
      likedByMe: true,
    );
    _replacePublication(_withLike(current, like));
    return like;
  }

  @override
  Future<CommunityLikeState> unlikePublication({
    required String accessToken,
    required int communityId,
    required int publicationId,
  }) async {
    networkOps.add('DELETE /communities/$communityId/publications/$publicationId/like');
    unlikedPublicationIds.add(publicationId);
    final current = _byId(publicationId);
    final like = CommunityLikeState(
      liked: false,
      likeCount: current.likedByMe && current.likeCount > 0 ? current.likeCount - 1 : current.likeCount,
      likedByMe: false,
    );
    _replacePublication(_withLike(current, like));
    return like;
  }

  @override
  Future<CommunityFavoriteState> favoritePublication({
    required String accessToken,
    required int communityId,
    required int publicationId,
  }) async {
    networkOps.add('PUT /communities/$communityId/publications/$publicationId/favorite');
    if (failFavorite != null) {
      throw failFavorite!;
    }
    if (holdFavorite) {
      final hold = Completer<void>();
      favoriteHolds.add(hold);
      await hold.future;
    }
    favoritedPublicationIds.add(publicationId);
    final current = _byId(publicationId);
    final favorite = CommunityFavoriteState(
      favorited: true,
      favoriteCount: current.favoritedByMe ? current.favoriteCount : current.favoriteCount + 1,
      favoritedByMe: true,
    );
    final updated = _withFavorite(current, favorite);
    _replacePublication(updated);
    if (!myFavorites.any((item) => item.id == updated.id)) {
      myFavorites = [updated, ...myFavorites];
    } else {
      myFavorites = [for (final item in myFavorites) if (item.id == updated.id) updated else item];
    }
    return favorite;
  }

  @override
  Future<CommunityFavoriteState> unfavoritePublication({
    required String accessToken,
    required int communityId,
    required int publicationId,
  }) async {
    networkOps.add('DELETE /communities/$communityId/publications/$publicationId/favorite');
    unfavoritedPublicationIds.add(publicationId);
    final current = _byId(publicationId);
    final favorite = CommunityFavoriteState(
      favorited: false,
      favoriteCount: current.favoritedByMe && current.favoriteCount > 0
          ? current.favoriteCount - 1
          : current.favoriteCount,
      favoritedByMe: false,
    );
    final updated = _withFavorite(current, favorite);
    _replacePublication(updated);
    myFavorites = [for (final item in myFavorites) if (item.id != updated.id) item];
    return favorite;
  }

  @override
  Future<CommunityPublicationPage> listMyFavorites({
    required String accessToken,
    String? beforeAt,
    int? beforeId,
    int? limit,
  }) async {
    listMyFavoritesCalls += 1;
    networkOps.add('GET /me/community-favorites');
    if (holdListMyFavorites) {
      final hold = Completer<CommunityPublicationPage>();
      listMyFavoritesHolds.add(hold);
      return hold.future;
    }
    if (failListMyFavorites != null) {
      throw failListMyFavorites!;
    }
    if (beforeId != null) {
      return CommunityPublicationPage(
        items: [
          for (final item in myFavorites)
            if (item.id != beforeId) item,
        ],
      );
    }
    return CommunityPublicationPage(items: List<CommunityPublication>.from(myFavorites), next: myFavoritesNext);
  }

  @override
  Future<CommunityCommentPage> listComments({
    required String accessToken,
    required int communityId,
    required int publicationId,
    String? beforeAt,
    int? beforeId,
  }) async {
    networkOps.add('GET /communities/$communityId/publications/$publicationId/comments');
    return CommunityCommentPage(
      items: [
        for (final item in comments)
          if (item.communityPublicationId == publicationId) item,
      ],
    );
  }

  @override
  Future<CommunityComment> createComment({
    required String accessToken,
    required int communityId,
    required int publicationId,
    required String body,
    int? parentCommentId,
  }) async {
    networkOps.add('POST /communities/$communityId/publications/$publicationId/comments');
    createCommentCalls.add(<String, dynamic>{
      'body': body,
      'parentCommentId': parentCommentId,
    });
    final comment = CommunityComment(
      id: nextCommentId++,
      communityId: communityId,
      communityPublicationId: publicationId,
      parentCommentId: parentCommentId,
      body: body,
      status: 'visible',
      author: const CommunityCommentAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
    );
    comments = [comment, ...comments];
    final current = _byId(publicationId);
    _replacePublication(
      current.copyWith(commentCount: memberVisibleCommentCount(comments.where((item) => item.communityPublicationId == publicationId))),
    );
    return comment;
  }

  @override
  Future<CommunityComment> updateComment({
    required String accessToken,
    required int communityId,
    required int publicationId,
    required int commentId,
    required String body,
  }) async {
    networkOps.add('PATCH /communities/$communityId/publications/$publicationId/comments/$commentId');
    comments = [
      for (final item in comments)
        if (item.id == commentId) item.copyWith(body: body) else item,
    ];
    return comments.firstWhere((item) => item.id == commentId);
  }

  @override
  Future<void> deleteComment({
    required String accessToken,
    required int communityId,
    required int publicationId,
    required int commentId,
  }) async {
    networkOps.add('DELETE /communities/$communityId/publications/$publicationId/comments/$commentId');
    comments = [for (final item in comments) if (item.id != commentId) item];
    final current = _byId(publicationId);
    _replacePublication(
      current.copyWith(
        commentCount: memberVisibleCommentCount(
          comments.where((item) => item.communityPublicationId == publicationId),
        ),
      ),
    );
  }

  @override
  Future<CommunityComment> restoreComment({
    required String accessToken,
    required int communityId,
    required int publicationId,
    required int commentId,
  }) async {
    networkOps.add(
      'POST /communities/$communityId/publications/$publicationId/comments/$commentId/restore',
    );
    comments = [
      for (final item in comments)
        if (item.id == commentId) item.copyWith(status: 'visible') else item,
    ];
    final current = _byId(publicationId);
    _replacePublication(
      current.copyWith(
        commentCount: memberVisibleCommentCount(
          comments.where((item) => item.communityPublicationId == publicationId),
        ),
      ),
    );
    return comments.firstWhere((item) => item.id == commentId);
  }

  @override
  Future<CommunityCommentTracePage> listMyCommentTraces({
    required String accessToken,
    String? beforeAt,
    int? beforeId,
  }) async {
    networkOps.add('GET /me/community-comment-traces');
    return CommunityCommentTracePage(items: traces);
  }

  bool _matchesMeScope(CommunityPublication item, String scope) {
    final currentOrScheduled = item.status == 'active' || item.status == 'scheduled';
    if (scope == 'expired') {
      return item.status == 'expired';
    }
    if (scope == 'left') {
      return currentOrScheduled && item.author.isFormerMember;
    }
    return currentOrScheduled && !item.author.isFormerMember;
  }

  CommunityPublication _copyPublication(
    CommunityPublication item, {
    String? title,
    String? body,
  }) {
    return CommunityPublication(
      id: item.id,
      communityId: item.communityId,
      communityName: item.communityName,
      author: item.author,
      body: body ?? item.body,
      title: title ?? item.title,
      status: item.status,
      scheduledAt: item.scheduledAt,
      publishedAt: item.publishedAt,
      expiresAt: item.expiresAt,
      expiredAt: item.expiredAt,
      isTimeLimited: item.isTimeLimited,
      commentsEnabled: item.commentsEnabled,
      likeCount: item.likeCount,
      commentCount: item.commentCount,
      likedByMe: item.likedByMe,
      favoriteCount: item.favoriteCount,
      favoritedByMe: item.favoritedByMe,
      deletedByUserId: item.deletedByUserId,
      media: item.media,
    );
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

class _FakeIdentityPicker implements ChroniqueLocalMediaPicker {
  _FakeIdentityPicker({this.imageResult = const MediaPickCancelled()});

  MediaPickResult imageResult;

  @override
  Future<MediaPickResult> pickImage({int? limit}) async => imageResult;

  @override
  Future<MediaPickResult> pickImageFromCamera() async => const MediaPickCancelled();

  @override
  Future<MediaPickResult> pickVideo({int? limit}) async => const MediaPickCancelled();

  @override
  Future<MediaPickResult> pickVideoFromCamera() async => const MediaPickCancelled();

  @override
  Future<MediaPickResult> pickAudio() async => const MediaPickCancelled();

  @override
  Future<MediaPickResult> pickDocument({int? limit}) async => const MediaPickCancelled();
}

class _FakeIdentityPutClient extends ChroniqueMediaUploadClient {
  int puts = 0;
  Object? putError;

  @override
  Future<void> putFile({
    required String url,
    required String method,
    required Map<String, String> headers,
    required String localPath,
    required int byteSize,
    onSendProgress,
  }) async {
    if (putError != null) {
      throw putError!;
    }
    puts += 1;
  }
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required _FakeCommunityApi api,
  AuthTokenStorage? tokens,
  ChroniqueLocalMediaPicker? picker,
  ChroniqueMediaUploadClient? uploadClient,
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
        if (picker != null) chroniqueLocalMediaPickerProvider.overrideWithValue(picker),
        if (uploadClient != null)
          chroniqueMediaUploadClientProvider.overrideWithValue(uploadClient),
      ],
      child: const LuminaApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  const sampleInvite = ReceivedCommunityInvitation(
    id: 11,
    communityId: 3,
    communityName: 'Jardin secret',
    invitedByLogin: 'owner42',
    status: 'pending',
    createdAt: '2026-10-02T12:00:00.000Z',
  );

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
    expect(
      () => CommunitySearchPreview.fromJson({
        'id': 1,
        'name': 'Jardin secret',
        'member_count': 2,
        'avatar_storage_key': 'secret',
      }),
      throwsA(isA<FormatException>()),
    );
    final withAvatar = CommunitySearchPreview.fromJson({
      'id': 1,
      'name': 'Jardin secret',
      'member_count': 2,
      'avatar_read_url': 'https://read.test/avatar.jpg',
    });
    expect(withAvatar.avatarReadUrl, 'https://read.test/avatar.jpg');
  });

  test('community json rejects identity storage keys', () {
    expect(
      () => Community.fromJson({
        'id': 1,
        'name': 'Jardin secret',
        'visibility': 'private',
        'my_role': 'owner',
        'member_count': 1,
        'avatar_storage_key': 'secret',
      }),
      throwsA(isA<FormatException>()),
    );
    final parsed = Community.fromJson({
      'id': 1,
      'name': 'Jardin secret',
      'visibility': 'private',
      'my_role': 'owner',
      'member_count': 1,
      'avatar_read_url': 'https://read.test/avatar.jpg',
      'banner_read_url': 'https://read.test/banner.jpg',
    });
    expect(parsed.avatarReadUrl, 'https://read.test/avatar.jpg');
    expect(parsed.bannerReadUrl, 'https://read.test/banner.jpg');
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
    expect(find.text('Un cercle privé'), findsNothing);
    expect(find.text('vérification de la création et du rôle propriétaire'), findsNothing);
  });

  testWidgets('community list and search show compact avatars', (tester) async {
    final api = _FakeCommunityApi();
    api.items[0] = api.items[0].copyWith(avatarReadUrl: 'https://read.test/avatar.jpg');
    api.searchResults = [
        CommunitySearchPreview(
          id: 99,
          name: 'Cercle fermé',
          memberCount: 4,
          avatarReadUrl: 'https://read.test/search-avatar.jpg',
        ),
      ];
    await _pumpApp(tester, api: api);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityAvatar), findsWidgets);
    expect(find.byKey(const ValueKey('community-identity-avatar-image')), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('community-search-open')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('community-search-field')), 'Cercle');
    await tester.tap(find.byKey(const ValueKey('community-search-submit')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityAvatar), findsWidgets);
    expect(find.byKey(const ValueKey('community-identity-avatar-image')), findsWidgets);
  });

  testWidgets('owner identity upload replaces avatar after complete', (tester) async {
    final file = File('${Directory.systemTemp.path}/lumina-identity-avatar.jpg')
      ..writeAsBytesSync(List<int>.filled(32, 1));
    addTearDown(() {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });
    final picker = _FakeIdentityPicker(
      imageResult: MediaPickSelected(
        kind: MediaDraftKind.image,
        sourceType: MediaDraftSourceType.gallery,
        fileName: 'avatar.jpg',
        byteSize: 32,
        localPath: file.path,
        contentType: 'image/jpeg',
      ),
    );
    final putClient = _FakeIdentityPutClient();
    final api = _FakeCommunityApi();
    await _pumpApp(tester, api: api, picker: picker, uploadClient: putClient);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-list-item-3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-identity-avatar-edit')));
    await tester.pumpAndSettle();
    expect(api.lastIdentitySlot, 'avatar');
    expect(api.lastIdentityUploadId, 'opaque-upload');
    expect(putClient.puts, 1);
    expect(find.byKey(const ValueKey('community-identity-avatar-image')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-placeholder-Avatar')), findsNothing);
  });

  testWidgets('failed identity put keeps previous avatar', (tester) async {
    final file = File('${Directory.systemTemp.path}/lumina-identity-keep.jpg')
      ..writeAsBytesSync(List<int>.filled(32, 1));
    addTearDown(() {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });
    final picker = _FakeIdentityPicker(
      imageResult: MediaPickSelected(
        kind: MediaDraftKind.image,
        sourceType: MediaDraftSourceType.gallery,
        fileName: 'avatar.jpg',
        byteSize: 32,
        localPath: file.path,
        contentType: 'image/jpeg',
      ),
    );
    final putClient = _FakeIdentityPutClient()
      ..putError = const ApiException(message: 'put failed');
    final api = _FakeCommunityApi();
    api.items[0] = api.items[0].copyWith(avatarReadUrl: 'https://read.test/old-avatar.jpg');
    await _pumpApp(tester, api: api, picker: picker, uploadClient: putClient);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-list-item-3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-identity-avatar-image')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-identity-avatar-edit')));
    await tester.pumpAndSettle();
    expect(api.lastIdentityUploadId, isNull);
    expect(api.items[0].avatarReadUrl, 'https://read.test/old-avatar.jpg');
    expect(find.byKey(const ValueKey('community-identity-avatar-image')), findsOneWidget);
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
    expect(find.byKey(const ValueKey('community-detail-error-back')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-detail-close')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-detail-error-back')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityListScreen), findsOneWidget);
    expect(find.byType(CommunityDetailScreen), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('home-communities')), findsOneWidget);
  });

  Future<void> expectListKeepsHome(WidgetTester tester) async {
    expect(find.byType(CommunityDetailScreen), findsNothing);
    expect(find.byType(CommunityListScreen), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('home-communities')), findsOneWidget);
    expect(find.byType(CommunityListScreen), findsNothing);
  }

  testWidgets('detail close pops back to list keeping Home', (tester) async {
    final api = _FakeCommunityApi();
    await _pumpApp(tester, api: api);
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityListScreen), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-list-item-3')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityDetailScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-detail-close')));
    await tester.pumpAndSettle();
    await expectListKeepsHome(tester);
  });

  testWidgets('after accepting an invitation, detail close keeps Home under list', (tester) async {
    final api = _FakeCommunityApi()..invitations = const [sampleInvite];
    await _pumpApp(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('home-invitations')));
    await tester.pumpAndSettle();
    expect(find.byType(InvitationInboxScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('invitation-inbox-accept-11')));
    await tester.pumpAndSettle();
    expect(find.byType(InvitationInboxScreen), findsOneWidget);
    expect(find.text(InvitationMessages.accepted), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-communities')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityListScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-list-item-3')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityDetailScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-detail-close')));
    await tester.pumpAndSettle();
    await expectListKeepsHome(tester);
  });

  testWidgets('detail close falls back to go communities when nothing to pop', (tester) async {
    final api = _FakeCommunityApi();
    await _pumpApp(tester, api: api);
    expect(find.byType(HomeScreen), findsOneWidget);
    GoRouter.of(tester.element(find.byType(HomeScreen))).go(AppRoutes.communityDetail(3));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityDetailScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(CommunityListScreen), findsNothing);
    await tester.tap(find.byKey(const ValueKey('community-detail-close')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityListScreen), findsOneWidget);
    expect(find.byType(CommunityDetailScreen), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(BackButton), findsNothing);
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

  Future<void> revealCommunityFeed(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('community-nav-feed')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('community-publish-open')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('community-feed-scroll')),
        matching: find.byType(Scrollable),
      ).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> openFeedComments(WidgetTester tester, {int publicationId = 21}) async {
    await tester.tap(find.byKey(ValueKey('community-comments-$publicationId')));
    await tester.pumpAndSettle();
  }

  Future<void> openCommunityMembersTab(WidgetTester tester) async {
    final tab = find.byKey(const ValueKey('community-nav-members'));
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  Future<void> openCommunityManagementTab(WidgetTester tester) async {
    final tab = find.byKey(const ValueKey('community-nav-manage'));
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  Future<void> expandCommunityManagementSection(
    WidgetTester tester,
    Key titleKey,
  ) async {
    final title = find.byKey(titleKey);
    final manageScroll = find.descendant(
      of: find.byKey(const ValueKey('community-manage-scroll')),
      matching: find.byType(Scrollable),
    );
    if (manageScroll.evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(title, 120, scrollable: manageScroll.first);
    } else {
      await tester.ensureVisible(title);
    }
    await tester.pumpAndSettle();
    await tester.tap(title);
    await tester.pumpAndSettle();
  }

  Future<void> openUserSearch(WidgetTester tester, _FakeCommunityApi api) async {
    await openCommunityDetail(tester, api);
    await openCommunityMembersTab(tester);
    await tester.tap(find.byKey(const ValueKey('community-detail-invite')));
    await tester.pumpAndSettle();
  }

  testWidgets('detail shows identity images when read urls exist', (tester) async {
    final api = _FakeCommunityApi();
    api.items[0] = api.items[0].copyWith(
      avatarReadUrl: 'https://read.test/avatar.jpg',
      bannerReadUrl: 'https://read.test/banner.jpg',
    );
    await openCommunityDetail(tester, api);
    expect(find.byKey(const ValueKey('community-identity-avatar-image')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-identity-banner-image')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-placeholder-Avatar')), findsNothing);
    expect(find.byKey(const ValueKey('community-placeholder-Bannière')), findsNothing);
  });

  testWidgets('community header avatar overlaps a centered circular banner', (tester) async {
    final api = _FakeCommunityApi();
    await openCommunityDetail(tester, api);
    final banner = tester.getRect(find.byKey(const ValueKey('community-identity-banner')));
    final avatar = tester.getRect(find.byKey(const ValueKey('community-identity-avatar')));
    expect(avatar.width, closeTo(avatar.height, 0.5));
    expect(avatar.center.dx, closeTo(banner.center.dx, 1));
    expect(avatar.top, lessThan(banner.bottom));
    expect(avatar.bottom, greaterThan(banner.bottom));
    expect(find.byType(CommunityAvatar), findsWidgets);
  });

  testWidgets('owner can edit community identity', (tester) async {
    final ownerApi = _FakeCommunityApi();
    await openCommunityDetail(tester, ownerApi);
    expect(find.byKey(const ValueKey('community-identity-avatar-edit')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-identity-banner-edit')), findsOneWidget);
  });

  testWidgets('admin cannot edit community identity', (tester) async {
    final adminApi = _FakeCommunityApi();
    setListedRole(adminApi, CommunityRole.admin);
    await openCommunityDetail(tester, adminApi);
    expect(find.byKey(const ValueKey('community-identity-avatar-edit')), findsNothing);
    expect(find.byKey(const ValueKey('community-identity-banner-edit')), findsNothing);
  });

  testWidgets('member cannot edit community identity', (tester) async {
    final memberApi = _FakeCommunityApi();
    setListedRole(memberApi, CommunityRole.member);
    await openCommunityDetail(tester, memberApi);
    expect(find.byKey(const ValueKey('community-identity-avatar-edit')), findsNothing);
    expect(find.byKey(const ValueKey('community-identity-banner-edit')), findsNothing);
  });

  testWidgets('owner sees invite member button', (tester) async {
    final api = _FakeCommunityApi();
    await openCommunityDetail(tester, api);
    await openCommunityMembersTab(tester);
    expect(find.byKey(const ValueKey('community-detail-invite')), findsOneWidget);
    expect(find.text('Inviter un membre'), findsOneWidget);
  });

  testWidgets('admin sees invite member button', (tester) async {
    final api = _FakeCommunityApi();
    setListedRole(api, CommunityRole.admin);
    await openCommunityDetail(tester, api);
    await openCommunityMembersTab(tester);
    expect(find.byKey(const ValueKey('community-detail-invite')), findsOneWidget);
    expect(find.text('Inviter un membre'), findsOneWidget);
  });

  testWidgets('member does not see invite member button', (tester) async {
    final api = _FakeCommunityApi();
    setListedRole(api, CommunityRole.member);
    await openCommunityDetail(tester, api);
    expect(find.byKey(const ValueKey('community-nav-manage')), findsNothing);
    await openCommunityMembersTab(tester);
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
    await openCommunityManagementTab(tester);
    expect(find.byKey(const ValueKey('community-sent-invitations-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-manage-invitations')), findsOneWidget);
    expect(find.text('Invitations envoyées'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('community-sent-invitation-login-21')).hitTestable(),
      findsNothing,
    );
    await expandCommunityManagementSection(
      tester,
      const ValueKey('community-sent-invitations-title'),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('community-manage-invitations')),
        matching: find.text('moh5'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('community-manage-invitations')),
        matching: find.text('Acceptée'),
      ),
      findsOneWidget,
    );
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
    await openCommunityManagementTab(tester);
    expect(find.byKey(const ValueKey('community-sent-invitations-title')), findsOneWidget);
    expect(find.text('Invitations envoyées'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('community-sent-invitation-login-21')).hitTestable(),
      findsNothing,
    );
    await expandCommunityManagementSection(
      tester,
      const ValueKey('community-sent-invitations-title'),
    );
    expect(
      find.byKey(const ValueKey('community-sent-invitation-login-21')).hitTestable(),
      findsOneWidget,
    );
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
    expect(find.byKey(const ValueKey('community-nav-manage')), findsNothing);
    expect(find.text('Invitations envoyées'), findsNothing);
    expect(api.listSentInvitationsCalls, 0);
  });

  testWidgets('owner sent invitations empty state', (tester) async {
    final api = _FakeCommunityApi();
    await openCommunityDetail(tester, api);
    await openCommunityManagementTab(tester);
    expect(
      find.byKey(const ValueKey('community-sent-invitations-empty')).hitTestable(),
      findsNothing,
    );
    await expandCommunityManagementSection(
      tester,
      const ValueKey('community-sent-invitations-title'),
    );
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
    final manageTab = find.byKey(const ValueKey('community-nav-manage'));
    await tester.ensureVisible(manageTab);
    await tester.tap(manageTab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('community-sent-invitations-title')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-sent-invitations-title')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
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
    await openCommunityManagementTab(tester);
    await expandCommunityManagementSection(
      tester,
      const ValueKey('community-sent-invitations-title'),
    );
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
    await openCommunityManagementTab(tester);
    expect(find.byKey(const ValueKey('community-join-requests-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-manage-join-requests')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-manage-history')), findsOneWidget);
    expect(find.text('Demandes d’adhésion'), findsOneWidget);
    expect(find.byKey(const ValueKey('community-join-request-pending-31')), findsNothing);
    expect(find.byKey(const ValueKey('community-join-history-32')), findsNothing);
    await expandCommunityManagementSection(
      tester,
      const ValueKey('community-join-requests-title'),
    );
    await expandCommunityManagementSection(
      tester,
      const ValueKey('community-join-requests-history-title'),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('community-manage-join-requests')),
        matching: find.byKey(const ValueKey('community-join-request-pending-31')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('community-manage-history')),
        matching: find.byKey(const ValueKey('community-join-history-32')),
      ),
      findsOneWidget,
    );
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
    await openCommunityManagementTab(tester);
    expect(find.byKey(const ValueKey('community-join-requests-title')), findsNothing);
    expect(find.byKey(const ValueKey('community-manage-join-requests')), findsNothing);
    expect(find.byKey(const ValueKey('community-manage-history')), findsNothing);
    expect(find.byKey(const ValueKey('community-manage-invitations')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-join-accept-31')), findsNothing);
    expect(api.listCommunityJoinRequestsCalls, 0);
  });

  testWidgets('owner management sections start collapsed and can open together', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeCommunityApi()
      ..sentInvitations = const [
        SentCommunityInvitation(id: 21, status: 'pending', inviteeLogin: 'moh5'),
      ]
      ..ownerJoinRequests = const [
        OwnerJoinRequest(id: 31, status: 'pending', requesterLogin: 'invitee7'),
        OwnerJoinRequest(id: 32, status: 'accepted', requesterLogin: 'ada'),
      ];
    await openCommunityDetail(tester, api);
    await openCommunityManagementTab(tester);
    expect(find.text('Invitations envoyées'), findsOneWidget);
    expect(find.text('Demandes d’adhésion'), findsOneWidget);
    expect(find.text('Historique'), findsOneWidget);
    expect(find.byKey(const ValueKey('community-sent-invitation-login-21')), findsNothing);
    expect(find.byKey(const ValueKey('community-join-request-pending-31')), findsNothing);
    expect(find.byKey(const ValueKey('community-join-history-32')), findsNothing);
    await expandCommunityManagementSection(
      tester,
      const ValueKey('community-sent-invitations-title'),
    );
    expect(find.byKey(const ValueKey('community-sent-invitation-login-21')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-join-request-pending-31')), findsNothing);
    await expandCommunityManagementSection(
      tester,
      const ValueKey('community-join-requests-title'),
    );
    expect(find.byKey(const ValueKey('community-sent-invitation-login-21')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-join-request-pending-31')), findsOneWidget);
    await expandCommunityManagementSection(
      tester,
      const ValueKey('community-join-requests-history-title'),
    );
    expect(find.byKey(const ValueKey('community-sent-invitation-login-21')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-join-request-pending-31')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-join-history-32')), findsOneWidget);
  });

  testWidgets('member does not see join request owner actions', (tester) async {
    final api = _FakeCommunityApi();
    setListedRole(api, CommunityRole.member);
    await openCommunityDetail(tester, api);
    expect(find.byKey(const ValueKey('community-nav-manage')), findsNothing);
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
    await expandCommunityManagementSection(
      tester,
      const ValueKey('community-join-requests-title'),
    );
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
    await expandCommunityManagementSection(
      tester,
      const ValueKey('community-join-requests-history-title'),
    );
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
    await expandCommunityManagementSection(
      tester,
      const ValueKey('community-join-requests-history-title'),
    );
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
    await expandCommunityManagementSection(
      tester,
      const ValueKey('community-join-requests-history-title'),
    );
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

  Future<void> confirmLeaveFromDetail(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpAndSettle();
    await openCommunityMembersTab(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('community-leave')));
    await tester.tap(find.byKey(const ValueKey('community-leave')));
    await tester.pumpAndSettle();
  }

  Future<void> expectLeaveReturnsToListKeepingHome(WidgetTester tester) async {
    expect(find.byType(CommunityDetailScreen), findsNothing);
    expect(find.byType(CommunityListScreen), findsOneWidget);
    expect(find.text('Aucune communauté pour le moment'), findsOneWidget);
    expect(find.byKey(const ValueKey('community-list-item-3')), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('home-communities')), findsOneWidget);
    expect(find.byType(CommunityListScreen), findsNothing);
  }

  testWidgets('member leave closes detail and reloads empty list', (tester) async {
    final api = _FakeCommunityApi();
    setListedRole(api, CommunityRole.member);
    await openCommunityDetail(tester, api);
    await confirmLeaveFromDetail(tester);
    expect(find.byKey(const ValueKey('community-leave-confirm')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-leave-confirm-yes')));
    await tester.pumpAndSettle();
    expect(api.leaveCalls, 1);
    await expectLeaveReturnsToListKeepingHome(tester);
  });

  testWidgets('admin leave closes detail and reloads empty list', (tester) async {
    final api = _FakeCommunityApi();
    setListedRole(api, CommunityRole.admin);
    await openCommunityDetail(tester, api);
    await confirmLeaveFromDetail(tester);
    expect(find.byKey(const ValueKey('community-leave-confirm')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-leave-confirm-yes')));
    await tester.pumpAndSettle();
    expect(api.leaveCalls, 1);
    await expectLeaveReturnsToListKeepingHome(tester);
  });

  testWidgets('owner transfer leave closes detail and reloads list', (tester) async {
    final api = _FakeCommunityApi()
      ..members = [
        const CommunityMember(userId: 1, login: 'moh5', role: CommunityRole.owner),
        CommunityMember(
          userId: 7,
          login: 'sag5',
          role: CommunityRole.admin,
          roleAssignedAt: DateTime.utc(2026, 1, 1),
        ),
        CommunityMember(
          userId: 8,
          login: 'joe5',
          role: CommunityRole.admin,
          roleAssignedAt: DateTime.utc(2026, 2, 1),
        ),
      ];
    await openCommunityDetail(tester, api);
    await confirmLeaveFromDetail(tester);
    expect(find.byKey(const ValueKey('community-transfer-confirm')), findsOneWidget);
    expect(find.textContaining('sag5'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('community-transfer-confirm-yes')));
    await tester.pumpAndSettle();
    expect(api.leaveCalls, 1);
    await expectLeaveReturnsToListKeepingHome(tester);
  });

  testWidgets('community detail shows empty publication feed and publish', (tester) async {
    final api = _FakeCommunityApi();
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(find.byKey(const ValueKey('community-publish-open')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-feed-empty')), findsOneWidget);
    expect(api.networkOps, contains('GET /communities/3/publications'));
  });

  testWidgets('community feed lists active publications only', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = const [
        CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          title: 'Titre actif',
          body: 'Texte de publication active assez long.',
          status: 'active',
        ),
        CommunityPublication(
          id: 22,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Publication programmee invisible.',
          status: 'scheduled',
        ),
      ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(find.byKey(const ValueKey('community-feed-item-21')), findsOneWidget);
    expect(find.text('Titre actif'), findsOneWidget);
    expect(find.byKey(const ValueKey('community-feed-item-22')), findsNothing);
  });

  testWidgets('feed tap opens own publication detail only', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = [
        const CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Texte de publication active assez long.',
          status: 'active',
        ),
        const CommunityPublication(
          id: 22,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 2, login: 'other', isFormerMember: false),
          body: 'Publication active d un autre membre.',
          status: 'active',
        ),
      ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(find.byKey(const ValueKey('community-feed-mod-menu-21')), findsNothing);
    expect(find.byKey(const ValueKey('community-feed-mod-menu-22')), findsOneWidget);
    expect(find.byType(ChroniqueCardMenu), findsNothing);
    await tester.tap(find.byKey(const ValueKey('community-feed-item-21')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityPublicationDetailScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('community-publication-author')), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-feed-item-22')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
    expect(find.text('Publication indisponible'), findsNothing);
  });

  CommunityPublication feedPublication({
    required int id,
    required List<ChroniqueMedia> media,
  }) {
    return CommunityPublication(
      id: id,
      communityId: 3,
      author: const CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
      title: 'Publication media',
      body: 'Texte de publication active assez long.',
      status: 'active',
      media: media,
    );
  }

  Future<void> openCommunityFeedMedia(
    WidgetTester tester,
    _FakeCommunityApi api, {
    required ChroniqueMedia media,
  }) async {
    api.publications = [feedPublication(id: 21, media: [media])];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('chronique-feed-media-${media.id}')),
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('community-feed-scroll')),
        matching: find.byType(Scrollable),
      ).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapCommunityFeedMedia(WidgetTester tester, int mediaId) async {
    await tester.tap(find.byKey(ValueKey('chronique-feed-media-$mediaId')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  test('community publication JSON maps signed media urls including video thumbnail', () {
    final publication = CommunityPublication.fromJson({
      'id': 21,
      'community_id': 3,
      'author': {'user_id': 1, 'login': 'tgjjk', 'is_former_member': false},
      'body': 'Texte de publication active assez long.',
      'status': 'active',
      'media': [
        {
          'id': 1,
          'kind': 'image',
          'status': 'ready',
          'read_url': 'https://example.test/pic.jpg',
          'read_expires_at': '2026-10-05T10:16:00.000Z',
        },
        {
          'id': 2,
          'kind': 'video',
          'status': 'ready',
          'read_url': 'https://example.test/clip.mp4',
          'read_expires_at': '2026-10-05T10:16:00.000Z',
          'thumbnail_url': 'https://example.test/clip.jpg',
          'thumbnail_expires_at': '2026-10-05T10:16:00.000Z',
        },
      ],
    });
    expect(publication.media[0].readUrl, 'https://example.test/pic.jpg');
    expect(publication.media[0].thumbnailUrl, isNull);
    expect(publication.media[1].readUrl, 'https://example.test/clip.mp4');
    expect(publication.media[1].thumbnailUrl, 'https://example.test/clip.jpg');
    expect(publication.media[1].thumbnailExpiresAt, DateTime.parse('2026-10-05T10:16:00.000Z'));
    expect(publication.likeCount, 0);
    expect(publication.commentCount, 0);
    expect(publication.likedByMe, isFalse);
    expect(publication.favoriteCount, 0);
    expect(publication.favoritedByMe, isFalse);
  });

  test('community publication JSON maps interaction counters', () {
    final publication = CommunityPublication.fromJson({
      'id': 21,
      'community_id': 3,
      'author': {'user_id': 1, 'login': 'tgjjk', 'is_former_member': false},
      'body': 'Texte de publication active assez long.',
      'status': 'active',
      'like_count': 4,
      'comment_count': 2,
      'liked_by_me': true,
      'favorite_count': 3,
      'favorited_by_me': true,
    });
    expect(publication.likeCount, 4);
    expect(publication.commentCount, 2);
    expect(publication.likedByMe, isTrue);
    expect(publication.favoriteCount, 3);
    expect(publication.favoritedByMe, isTrue);
  });

  testWidgets('community feed image is shown and tap opens the viewer', (tester) async {
    const image = ChroniqueMedia(
      id: 10,
      kind: 'image',
      status: 'ready',
      contentType: 'image/jpeg',
      sortOrder: 0,
      readUrl: 'https://example.test/a.jpg',
    );
    final api = _FakeCommunityApi();
    await openCommunityFeedMedia(tester, api, media: image);
    expect(find.byKey(const ValueKey('chronique-feed-media-10')), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    await tapCommunityFeedMedia(tester, 10);
    expect(find.byType(ChroniqueMediaViewerPage), findsOneWidget);
    expect(find.text('Image'), findsWidgets);
    expect(
      api.networkOps.where((op) => op.contains('/publications/21') && !op.contains('/comments')),
      isEmpty,
    );
  });

  testWidgets('community feed video with thumbnail shows poster and tap opens player', (tester) async {
    const video = ChroniqueMedia(
      id: 11,
      kind: 'video',
      status: 'ready',
      contentType: 'video/mp4',
      originalFilename: 'clip.mp4',
      sortOrder: 0,
      readUrl: 'https://example.test/clip.mp4',
      thumbnailUrl: 'https://example.test/clip.jpg',
    );
    final api = _FakeCommunityApi();
    await openCommunityFeedMedia(tester, api, media: video);
    expect(find.byKey(const ValueKey('chronique-feed-video-thumb')), findsOneWidget);
    expect(find.byIcon(Icons.play_circle), findsWidgets);
    await tapCommunityFeedMedia(tester, 11);
    expect(find.byType(ChroniqueMediaViewerPage), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-media-viewer-video')), findsOneWidget);
  });

  testWidgets('community feed video without thumbnail keeps fallback and tap still opens player', (
    tester,
  ) async {
    const video = ChroniqueMedia(
      id: 12,
      kind: 'video',
      status: 'ready',
      contentType: 'video/mp4',
      originalFilename: 'clip.mp4',
      sortOrder: 0,
      readUrl: 'https://example.test/clip.mp4',
    );
    final api = _FakeCommunityApi();
    await openCommunityFeedMedia(tester, api, media: video);
    expect(find.byKey(const ValueKey('chronique-feed-video-thumb')), findsNothing);
    expect(find.text('Vidéo'), findsOneWidget);
    await tapCommunityFeedMedia(tester, 12);
    expect(find.byType(ChroniqueMediaViewerPage), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-media-viewer-video')), findsOneWidget);
  });

  testWidgets('community feed audio chrome tap opens the audio viewer', (tester) async {
    const audio = ChroniqueMedia(
      id: 13,
      kind: 'audio',
      status: 'ready',
      contentType: 'audio/mpeg',
      originalFilename: 'voix.mp3',
      sortOrder: 0,
      readUrl: 'https://example.test/voix.mp3',
    );
    final api = _FakeCommunityApi();
    await openCommunityFeedMedia(tester, api, media: audio);
    expect(find.text('voix.mp3'), findsOneWidget);
    await tapCommunityFeedMedia(tester, 13);
    expect(find.byType(ChroniqueMediaViewerPage), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-media-viewer-audio')), findsOneWidget);
  });

  testWidgets('community feed document chrome tap opens the document viewer', (tester) async {
    const document = ChroniqueMedia(
      id: 14,
      kind: 'document',
      status: 'ready',
      contentType: 'application/pdf',
      originalFilename: 'note.pdf',
      sortOrder: 0,
      readUrl: 'https://example.test/note.pdf',
    );
    final api = _FakeCommunityApi();
    await openCommunityFeedMedia(tester, api, media: document);
    expect(find.text('note.pdf'), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    await tapCommunityFeedMedia(tester, 14);
    expect(find.byType(ChroniqueMediaViewerPage), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-media-viewer-document')), findsOneWidget);
  });

  testWidgets('non-member community feed error does not expose media tiles', (tester) async {
    final api = _FakeCommunityApi()
      ..failListPublications = const ApiException(message: 'Community not found', statusCode: 404)
      ..publications = [
        feedPublication(
          id: 21,
          media: const [
            ChroniqueMedia(
              id: 10,
              kind: 'image',
              status: 'ready',
              readUrl: 'https://example.test/secret.jpg',
            ),
          ],
        ),
      ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(find.byKey(const ValueKey('community-feed-error')), findsOneWidget);
    expect(find.text('Community not found'), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-feed-media-10')), findsNothing);
    expect(find.byKey(const ValueKey('community-feed-item-21')), findsNothing);
  });

  testWidgets('community assistant has three steps without public audience or themes', (
    tester,
  ) async {
    final api = _FakeCommunityApi();
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await tester.tap(find.byKey(const ValueKey('community-publish-open')));
    await tester.pumpAndSettle();
    expect(find.byType(CreateCommunityPublicationScreen), findsOneWidget);
    expect(find.text('Contenu'), findsWidgets);
    expect(find.text('Titre (optionnel)'), findsOneWidget);
    expect(find.text('Texte *'), findsOneWidget);
    expect(find.text('+ Ajouter un média'), findsOneWidget);
    expect(find.text('+ Média'), findsOneWidget);
    expect(find.byKey(const ValueKey('wizard-add-media')), findsOneWidget);
    expect(find.byKey(const ValueKey('wizard-next')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Titre (optionnel)')).dy,
      lessThan(tester.getTopLeft(find.text('Texte *')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Texte *')).dy,
      lessThan(tester.getTopLeft(find.text('+ Ajouter un média')).dy),
    );
    expect(find.byKey(const ValueKey('community-assistant-comments')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-comments-yes')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-comments-no')), findsOneWidget);
    expect(find.text('Public'), findsNothing);
    expect(find.text('Privé'), findsNothing);
    expect(find.text('Thèmes'), findsNothing);

    await tester.enterText(find.byType(TextField).at(1), 'Le texte communautaire de plus de dix car.');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('community-comments-yes')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wizard-next')));
    await tester.pumpAndSettle();

    expect(find.text('Paramètres'), findsWidgets);
    expect(find.text('+ Média'), findsNothing);
    expect(find.byKey(const ValueKey('community-assistant-context-name')), findsOneWidget);
    expect(find.text('Jardin secret'), findsWidgets);
    expect(find.byKey(const ValueKey('publish-now')), findsOneWidget);
    expect(find.byKey(const ValueKey('publish-schedule')), findsOneWidget);
    expect(find.byKey(const ValueKey('expiration-yes')), findsOneWidget);
    expect(find.text('Public'), findsNothing);
    expect(find.text('Privé'), findsNothing);
    expect(find.text('Thèmes'), findsNothing);
    expect(find.text('Famille'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('wizard-next')));
    await tester.pumpAndSettle();
    expect(find.text('Aperçu'), findsWidgets);
    expect(find.byKey(const ValueKey('chronique-preview-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('wizard-publish')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('wizard-publish')));
    await tester.pumpAndSettle();
    expect(api.createPublicationCalls, isNotEmpty);
    expect(api.createPublicationCalls.single['publish'], 'now');
    expect(api.createPublicationCalls.single['commentsEnabled'], isTrue);
    expect(api.createPublicationCalls.single['body'], 'Le texte communautaire de plus de dix car.');
    expect(find.byType(CreateCommunityPublicationScreen), findsNothing);
    expect(find.byType(CommunityDetailScreen), findsOneWidget);
  });

  testWidgets('community assistant can schedule a publication', (tester) async {
    final api = _FakeCommunityApi();
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await tester.tap(find.byKey(const ValueKey('community-publish-open')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'Texte programme assez long pour passer.');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wizard-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('publish-schedule')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wizard-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wizard-publish')));
    await tester.pumpAndSettle();
    expect(api.createPublicationCalls.single['publish'], 'schedule');
    expect(api.createPublicationCalls.single['scheduledAt'], isNotNull);
  });

  testWidgets('community assistant content bar keeps + Média and Suivant with keyboard inset', (
    tester,
  ) async {
    final api = _FakeCommunityApi();
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await tester.tap(find.byKey(const ValueKey('community-publish-open')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'Le texte communautaire de plus de dix car.');
    await tester.pump();
    await tester.showKeyboard(find.byType(TextField).at(1));
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    expect(find.byKey(const ValueKey('wizard-add-media')).hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('wizard-next')).hitTestable(), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('wizard-add-media'))).bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height / tester.view.devicePixelRatio),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('wizard-next'))).bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height / tester.view.devicePixelRatio),
    );

    await tester.tap(find.byKey(const ValueKey('wizard-add-media')));
    await tester.pumpAndSettle();
    expect(find.text('Image'), findsOneWidget);
    expect(find.text('Vidéo'), findsOneWidget);
    expect(api.createPublicationCalls, isEmpty);
  });

  testWidgets('home menu opens mes publications communautaires', (tester) async {
    final api = _FakeCommunityApi()
      ..myPublications = const [
        CommunityPublication(
          id: 44,
          communityId: 3,
          communityName: 'Jardin secret',
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Ma publication actuelle dans le cercle.',
          status: 'active',
        ),
      ];
    await _pumpApp(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('home-user-avatar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-my-community-publications')));
    await tester.pumpAndSettle();
    expect(find.byType(MyCommunityPublicationsScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('me-pubs-current')), findsOneWidget);
    expect(find.byKey(const ValueKey('me-pubs-left')), findsOneWidget);
    expect(find.byKey(const ValueKey('me-pubs-expired')), findsOneWidget);
    expect(find.text('Ma publication actuelle dans le cercle.'), findsOneWidget);
  });

  CommunityPublication scheduledMine({
    int id = 70,
    bool formerMember = false,
    int authorId = 1,
    String status = 'scheduled',
    String? scheduledAt = '2026-10-10T15:30:00.000Z',
    String title = 'Soirée jardin',
    String body = 'Publication programmee assez longue.',
  }) {
    return CommunityPublication(
      id: id,
      communityId: 3,
      communityName: 'Jardin secret',
      author: CommunityPublicationAuthor(
        userId: authorId,
        login: authorId == 1 ? 'tgjjk' : 'other',
        isFormerMember: formerMember,
      ),
      title: title,
      body: body,
      status: status,
      scheduledAt: scheduledAt,
    );
  }

  String recentPublishedAt() =>
      DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String();

  String closedWindowPublishedAt() =>
      DateTime.now().toUtc().subtract(const Duration(minutes: 31)).toIso8601String();

  CommunityPublication authorActivePublication({
    int id = 80,
    int authorId = 1,
    String? publishedAt,
    String title = 'Titre actif auteur',
    String body = 'Publication active auteur encore membre.',
    List<ChroniqueMedia> media = const [],
    bool commentsEnabled = true,
    int likeCount = 0,
  }) {
    return CommunityPublication(
      id: id,
      communityId: 3,
      communityName: 'Jardin secret',
      author: CommunityPublicationAuthor(
        userId: authorId,
        login: authorId == 1 ? 'tgjjk' : 'other',
        isFormerMember: false,
      ),
      title: title,
      body: body,
      status: 'active',
      publishedAt: publishedAt ?? recentPublishedAt(),
      commentsEnabled: commentsEnabled,
      likeCount: likeCount,
      media: media,
    );
  }

  Future<void> openCommunityPublicationMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('community-publication-menu')));
    await tester.pumpAndSettle();
  }

  Future<void> enterAuthorCorrection(WidgetTester tester) async {
    await openCommunityPublicationMenu(tester);
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();
  }

  Future<void> pumpPublicationDetailOnStack(
    WidgetTester tester,
    _FakeCommunityApi api, {
    required int publicationId,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authTokenStorageProvider.overrideWithValue(
            InMemoryAuthTokenStorage(accessToken: 'access-test', refreshToken: 'refresh-test'),
          ),
          authControllerProvider.overrideWith(() => _SeededAuthController()),
          communityApiServiceProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  key: const ValueKey('open-community-publication-detail'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CommunityPublicationDetailScreen(
                          communityId: 3,
                          publicationId: publicationId,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-community-publication-detail')));
    await tester.pumpAndSettle();
  }

  Future<void> openMyPublications(WidgetTester tester, _FakeCommunityApi api) async {
    await _pumpApp(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('home-user-avatar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-my-community-publications')));
    await tester.pumpAndSettle();
  }

  Future<void> pumpPublicationDetail(
    WidgetTester tester,
    _FakeCommunityApi api, {
    required int publicationId,
    bool fromMe = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authTokenStorageProvider.overrideWithValue(
            InMemoryAuthTokenStorage(accessToken: 'access-test', refreshToken: 'refresh-test'),
          ),
          authControllerProvider.overrideWith(() => _SeededAuthController()),
          communityApiServiceProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: CommunityPublicationDetailScreen(
            communityId: 3,
            publicationId: publicationId,
            fromMe: fromMe,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('A me actuelles shows scheduled label and datetime', (tester) async {
    final scheduledAt = DateTime.parse('2026-10-10T15:30:00.000Z');
    final api = _FakeCommunityApi()
      ..myPublications = [
        scheduledMine(),
        const CommunityPublication(
          id: 71,
          communityId: 3,
          communityName: 'Jardin secret',
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Publication active actuelle.',
          status: 'active',
        ),
      ];
    await openMyPublications(tester, api);
    expect(find.byKey(const ValueKey('me-pub-scheduled-label-70')), findsOneWidget);
    expect(find.text('Programmée'), findsOneWidget);
    expect(find.text(formatOptionalChroniqueDate(scheduledAt)!), findsOneWidget);
    expect(find.text('Publication active actuelle.'), findsOneWidget);
    expect(find.byKey(const ValueKey('me-pub-scheduled-label-71')), findsNothing);
  });

  testWidgets('B me detail scheduled author shows edit and delete', (tester) async {
    final api = _FakeCommunityApi()..myPublications = [scheduledMine()];
    await openMyPublications(tester, api);
    await tester.tap(find.byKey(const ValueKey('me-pub-current-70')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-publication-menu')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-publication-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Modifier'), findsOneWidget);
    expect(find.text('Supprimer'), findsOneWidget);
  });

  testWidgets('C scheduled edit keeps status and scheduled_at', (tester) async {
    final original = scheduledMine();
    final api = _FakeCommunityApi()..myPublications = [original];
    await openMyPublications(tester, api);
    await tester.tap(find.byKey(const ValueKey('me-pub-current-70')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-publication-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();
    expect(find.text('Modifier la publication'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Nouveau titre jardin');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('community-publication-save')));
    await tester.pumpAndSettle();
    expect(api.patchedPublicationIds, [70]);
    expect(find.text('Nouveau titre jardin'), findsOneWidget);
    final updated = api.myPublications.singleWhere((item) => item.id == 70);
    expect(updated.status, 'scheduled');
    expect(updated.scheduledAt, original.scheduledAt);
    expect(updated.title, 'Nouveau titre jardin');
  });

  testWidgets('D scheduled author can delete from me detail', (tester) async {
    final api = _FakeCommunityApi()..myPublications = [scheduledMine()];
    await openMyPublications(tester, api);
    await tester.tap(find.byKey(const ValueKey('me-pub-current-70')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-publication-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Elle ne sera plus programmée.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
    await tester.pump();
    for (var i = 0; i < 80; i++) {
      if (find.text('Publication supprimée').evaluate().isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(api.deletedPublicationIds, [70]);
    expect(find.byKey(const ValueKey('community-publication-restore-action')), findsWidgets);
    expect(find.text('Restaurer'), findsWidgets);
    expect(find.text('Publication supprimée'), findsWidgets);
    ScaffoldMessenger.of(tester.element(find.byType(MyCommunityPublicationsScreen))).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(find.byType(MyCommunityPublicationsScreen), findsOneWidget);
    expect(find.text('Publication programmee assez longue.'), findsNothing);
  });

  testWidgets('E owner cannot edit or delete someone else scheduled', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = [scheduledMine(authorId: 2)]
      ..myPublications = [scheduledMine(authorId: 2)];
    await pumpPublicationDetail(tester, api, publicationId: 70);
    expect(find.text('Publication indisponible'), findsOneWidget);
    expect(find.byKey(const ValueKey('community-publication-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-publication-menu')), findsNothing);
    expect(find.byKey(const ValueKey('community-publication-author')), findsNothing);
    expect(find.text('vous n’êtes pas l’auteur'), findsNothing);
    expect(find.text("vous n'êtes pas l'auteur"), findsNothing);
  });

  testWidgets('E former member cannot edit or delete scheduled from me', (tester) async {
    final api = _FakeCommunityApi()..myPublications = [scheduledMine(formerMember: true)];
    await pumpPublicationDetail(tester, api, publicationId: 70, fromMe: true);
    expect(find.byKey(const ValueKey('community-publication-menu')), findsNothing);
  });

  testWidgets('F active author from me keeps edit and delete', (tester) async {
    final api = _FakeCommunityApi()
      ..myPublications = [
        scheduledMine(
          id: 72,
          status: 'active',
          scheduledAt: null,
          title: 'Active titre',
          body: 'Publication active auteur encore membre.',
        ),
      ];
    await openMyPublications(tester, api);
    await tester.tap(find.byKey(const ValueKey('me-pub-current-72')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-publication-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Modifier'), findsOneWidget);
    expect(find.text('Supprimer'), findsOneWidget);
  });

  testWidgets('me actuelles author can write a comment from detail', (tester) async {
    final api = _FakeCommunityApi()
      ..myPublications = [
        const CommunityPublication(
          id: 72,
          communityId: 3,
          communityName: 'Jardin secret',
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          title: 'Active titre',
          body: 'Publication active auteur encore membre.',
          status: 'active',
          commentsEnabled: true,
        ),
      ];
    await openMyPublications(tester, api);
    await tester.tap(find.byKey(const ValueKey('me-pub-current-72')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityPublicationDetailScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('community-comment-input')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('community-comment-input')), 'Depuis mes publications');
    await tester.tap(find.byKey(const ValueKey('community-comment-submit')));
    await tester.pumpAndSettle();
    expect(api.networkOps, contains('POST /communities/3/publications/72/comments'));
  });

  testWidgets('F left scheduled stays read only', (tester) async {
    final api = _FakeCommunityApi()
      ..myPublications = [scheduledMine(id: 73, formerMember: true)];
    await openMyPublications(tester, api);
    await tester.tap(find.byKey(const ValueKey('me-pubs-left')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('me-pub-left-73')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('me-pub-left-73')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-publication-menu')), findsNothing);
  });

  testWidgets('F expired from me has no edit or delete', (tester) async {
    final api = _FakeCommunityApi()
      ..myPublications = [
        scheduledMine(
          id: 74,
          status: 'expired',
          scheduledAt: null,
          body: 'Publication expiree de lauteur.',
        ),
      ];
    await openMyPublications(tester, api);
    await tester.tap(find.byKey(const ValueKey('me-pubs-expired')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('me-pub-expired-74')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-publication-menu')), findsNothing);
  });

  testWidgets('community feed shows social bar without module 2 share or like keys', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = [
        const CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          title: 'Titre actif',
          body: 'Texte de publication active assez long.',
          status: 'active',
          likeCount: 3,
          commentCount: 1,
        ),
      ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(find.byKey(const ValueKey('community-like-21')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-like-count-21')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-comment-count-21')), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-like')), findsNothing);
    expect(find.byKey(const ValueKey('chronique-share')), findsNothing);
  });

  testWidgets('community feed like calls PUT like', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = [
        const CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Texte de publication active assez long.',
          status: 'active',
        ),
      ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await tester.tap(find.byKey(const ValueKey('community-like-21')));
    await tester.pumpAndSettle();
    expect(api.likedPublicationIds, [21]);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('community detail comments composer creates a comment', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = [
        const CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Texte de publication active assez long.',
          status: 'active',
          commentsEnabled: true,
        ),
      ];
    await pumpPublicationDetail(tester, api, publicationId: 21);
    expect(find.byKey(const ValueKey('community-comment-input')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('community-comment-input')), 'Super soiree');
    await tester.tap(find.byKey(const ValueKey('community-comment-submit')));
    await tester.pumpAndSettle();
    expect(api.networkOps, contains('POST /communities/3/publications/21/comments'));
    expect(find.byKey(const ValueKey('community-comment-item-500')), findsOneWidget);
    expect(find.text('Super soiree'), findsOneWidget);
  });

  CommunityPublication _activePublication({int id = 21}) {
    return CommunityPublication(
      id: id,
      communityId: 3,
      author: const CommunityPublicationAuthor(userId: 2, login: 'other', isFormerMember: false),
      body: 'Texte de publication active assez long.',
      status: 'active',
      commentsEnabled: true,
    );
  }

  CommunityComment _moderatedComment({int publicationId = 21}) {
    return CommunityComment(
      id: 2,
      communityId: 3,
      communityPublicationId: publicationId,
      body: 'Commentaire masque',
      status: 'moderated',
      author: const CommunityCommentAuthor(userId: 2, login: 'other', isFormerMember: false),
    );
  }

  testWidgets('owner restores moderated comment from feed sheet without opening detail', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeCommunityApi()
      ..publications = [_activePublication()]
      ..comments = [_moderatedComment()];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
    await openFeedComments(tester);
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
    expect(find.byKey(const ValueKey('community-comments-sheet-21')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-feed-21-comment-moderated-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-feed-21-comment-restore-2')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-feed-21-comment-restore-2')));
    await tester.pumpAndSettle();
    expect(api.networkOps, contains('POST /communities/3/publications/21/comments/2/restore'));
    expect(find.byKey(const ValueKey('community-feed-21-comment-item-2')), findsOneWidget);
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
  });

  testWidgets('admin sees restore on moderated comment from feed sheet', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeCommunityApi()
      ..items[0] = const Community(
        id: 3,
        name: 'Jardin secret',
        visibility: 'private',
        myRole: CommunityRole.admin,
        memberCount: 1,
      )
      ..publications = [_activePublication()]
      ..comments = [_moderatedComment()];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await openFeedComments(tester);
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
    expect(find.byKey(const ValueKey('community-feed-21-comment-restore-2')), findsOneWidget);
  });

  testWidgets('publication author sees restore on moderated comment', (tester) async {
    final api = _FakeCommunityApi()
      ..items[0] = Community(
        id: 3,
        name: 'Jardin secret',
        visibility: 'private',
        myRole: CommunityRole.member,
        memberCount: 1,
      )
      ..publications = [
        CommunityPublication(
          id: 21,
          communityId: 3,
          author: const CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Texte de publication active assez long.',
          status: 'active',
          commentsEnabled: true,
        ),
      ]
      ..comments = [_moderatedComment()];
    await pumpPublicationDetail(tester, api, publicationId: 21);
    expect(find.byKey(const ValueKey('community-comment-restore-2')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-comment-restore-2')));
    await tester.pumpAndSettle();
    expect(api.networkOps, contains('POST /communities/3/publications/21/comments/2/restore'));
    expect(find.byKey(const ValueKey('community-comment-item-2')), findsOneWidget);
  });

  testWidgets('member does not see restore on moderated comment from feed sheet', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeCommunityApi()
      ..items[0] = const Community(
        id: 3,
        name: 'Jardin secret',
        visibility: 'private',
        myRole: CommunityRole.member,
        memberCount: 1,
      )
      ..publications = [_activePublication()]
      ..comments = [_moderatedComment()];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await openFeedComments(tester);
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
    expect(find.byKey(const ValueKey('community-feed-21-comment-moderated-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-feed-21-comment-restore-2')), findsNothing);
  });

  testWidgets('community detail hides composer when comments are disabled', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = [
        const CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Texte de publication active assez long.',
          status: 'active',
          commentsEnabled: false,
        ),
      ];
    await pumpPublicationDetail(tester, api, publicationId: 21);
    expect(find.byKey(const ValueKey('community-comments-disabled')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-comment-submit')), findsNothing);
  });

  testWidgets('comment traces screen lists personal traces', (tester) async {
    final api = _FakeCommunityApi()
      ..traces = const [
        CommunityCommentTrace(
          id: 9,
          communityId: 3,
          commentId: 12,
          commentBody: 'Visible keep',
          isEphemeral: true,
          publicationAuthorLogin: 'member2',
          publishedAt: '2026-10-01T10:00:00.000Z',
          expiredAt: '2026-10-02T10:00:00.000Z',
          commentCreatedAt: '2026-10-01T11:00:00.000Z',
        ),
      ];
    await openMyPublications(tester, api);
    await tester.tap(find.byKey(const ValueKey('community-comment-traces-open')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityCommentTracesScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('community-comment-trace-9')), findsOneWidget);
    expect(find.text('Visible keep'), findsOneWidget);
    expect(find.text('Publication éphémère expirée'), findsOneWidget);
    expect(find.textContaining('Publication de member2'), findsOneWidget);
    expect(find.byKey(const ValueKey('community-comment-trace-at-9')), findsOneWidget);
    expect(api.networkOps, contains('GET /me/community-comment-traces'));
  });

  testWidgets('invalid comment error clears after the text becomes valid', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = [
        const CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Texte de publication active assez long.',
          status: 'active',
          commentsEnabled: true,
        ),
      ];
    await pumpPublicationDetail(tester, api, publicationId: 21);
    await tester.enterText(find.byKey(const ValueKey('community-comment-input')), 'x');
    await tester.tap(find.byKey(const ValueKey('community-comment-submit')));
    await tester.pump();
    expect(find.text('Le commentaire doit contenir entre 2 et 200 caractères.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('community-comment-input')), 'Texte valide');
    await tester.pump();
    expect(find.text('Le commentaire doit contenir entre 2 et 200 caractères.'), findsNothing);
  });

  testWidgets('deleting own comment shows snackbar and updates the detail counter', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = [
        const CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Texte de publication active assez long.',
          status: 'active',
          commentsEnabled: true,
          commentCount: 1,
        ),
      ]
      ..comments = [
        const CommunityComment(
          id: 7,
          communityId: 3,
          communityPublicationId: 21,
          body: 'Mon commentaire',
          status: 'visible',
          author: CommunityCommentAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
        ),
      ];
    await pumpPublicationDetail(tester, api, publicationId: 21);
    expect(find.byKey(const ValueKey('community-comment-count-21')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-comment-author-menu-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-comment-deleted')), findsOneWidget);
    expect(find.text('Commentaire supprimé'), findsOneWidget);
    expect(find.byKey(const ValueKey('community-comment-item-7')), findsNothing);
  });

  testWidgets('comment created in detail updates the feed counter after pop', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = [
        const CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Texte de publication active assez long.',
          status: 'active',
          commentsEnabled: true,
        ),
      ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(find.byKey(const ValueKey('community-comment-count-21')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-feed-item-21')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('community-comment-input')), 'Super soiree');
    await tester.tap(find.byKey(const ValueKey('community-comment-submit')));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-comment-count-21')), findsOneWidget);
    expect(
      (tester.widget<Text>(find.byKey(const ValueKey('community-comment-count-21'))).data),
      '1',
    );
  });

  testWidgets('like from detail updates the feed after pop', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = [
        const CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Texte de publication active assez long.',
          status: 'active',
          commentsEnabled: true,
        ),
      ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await tester.tap(find.byKey(const ValueKey('community-feed-item-21')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(CommunityPublicationDetailScreen),
        matching: find.byKey(const ValueKey('community-like-21')),
      ),
    );
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-like-count-21'))).data, '1');
  });

  testWidgets('failed feed like keeps the previous counter', (tester) async {
    final api = _FakeCommunityApi()
      ..failLike = const ApiException(message: 'Network down', statusCode: 503)
      ..publications = [
        const CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Texte de publication active assez long.',
          status: 'active',
        ),
      ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await tester.tap(find.byKey(const ValueKey('community-like-21')));
    await tester.pumpAndSettle();
    expect(api.likedPublicationIds, isEmpty);
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-like-count-21'))).data, '0');
    expect(find.text('Impossible de mettre à jour le j’aime'), findsOneWidget);
  });

  testWidgets('feed shows comments disabled without opening a composer', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = [
        const CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Texte de publication active assez long.',
          status: 'active',
        ),
      ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(find.byKey(const ValueKey('community-comments-disabled-feed-21')), findsOneWidget);
  });

  testWidgets('expired mine publications are historical and read only', (tester) async {
    final api = _FakeCommunityApi()
      ..myPublications = [
        const CommunityPublication(
          id: 74,
          communityId: 3,
          communityName: 'Jardin secret',
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          title: 'Soirée finie',
          body: 'Publication expiree de lauteur.',
          status: 'expired',
          publishedAt: '2026-10-01T10:00:00.000Z',
          expiredAt: '2026-10-02T10:00:00.000Z',
          likeCount: 4,
          commentCount: 2,
        ),
      ];
    await openMyPublications(tester, api);
    await tester.tap(find.byKey(const ValueKey('me-pubs-expired')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('me-pub-expired-label-74')), findsOneWidget);
    expect(find.byKey(const ValueKey('me-pub-counts-expired-74')), findsOneWidget);
    expect(find.text('4 j’aime · 2 commentaires · 0 favoris'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('me-pub-expired-74')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-publication-expired')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-publication-expired-counts')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-like-74')), findsNothing);
    expect(find.byKey(const ValueKey('community-comment-input')), findsNothing);
  });

  Future<ProviderContainer> readyCommunityFeed(_FakeCommunityApi api) async {
    final container = ProviderContainer(
      overrides: [
        authTokenStorageProvider.overrideWithValue(
          InMemoryAuthTokenStorage(accessToken: 'access-test', refreshToken: 'refresh-test'),
        ),
        communityApiServiceProvider.overrideWithValue(api),
      ],
    );
    container.listen(communityFeedControllerProvider(3), (_, __) {});
    await Future<void>.delayed(Duration.zero);
    expect(container.read(communityFeedControllerProvider(3)), isA<CommunityFeedReady>());
    return container;
  }

  CommunityPublication readyFeedPublication(ProviderContainer container) {
    return (container.read(communityFeedControllerProvider(3)) as CommunityFeedReady).items.single;
  }

  test('like patch does not restore a stale comment_count', () async {
    final api = _FakeCommunityApi()
      ..publications = [
        _activePublication().copyWith(title: 'Ancien titre', commentCount: 5),
      ];
    final container = await readyCommunityFeed(api);
    addTearDown(container.dispose);
    final notifier = container.read(communityFeedControllerProvider(3).notifier);
    notifier.applyPublication(21, const CommunityPublicationInteractionPatch(commentCount: 6));
    expect(readyFeedPublication(container).commentCount, 6);

    await notifier.toggleLike(readyFeedPublication(container));
    expect(readyFeedPublication(container).commentCount, 6);
    expect(readyFeedPublication(container).likeCount, 1);
    expect(readyFeedPublication(container).likedByMe, isTrue);

    api.publications = [
      _activePublication().copyWith(
        title: 'Nouveau titre',
        commentCount: 7,
        likeCount: 0,
        likedByMe: false,
      ),
    ];
    await notifier.load();
    expect(readyFeedPublication(container).title, 'Nouveau titre');
    expect(readyFeedPublication(container).commentCount, 6);
    expect(readyFeedPublication(container).likeCount, 1);
    expect(readyFeedPublication(container).likedByMe, isTrue);
  });

  test('toggleLike uses the controller publication instead of a stale widget item', () async {
    final api = _FakeCommunityApi()
      ..publications = [_activePublication().copyWith(commentCount: 6)];
    final container = await readyCommunityFeed(api);
    addTearDown(container.dispose);
    final notifier = container.read(communityFeedControllerProvider(3).notifier);
    final stale = readyFeedPublication(container).copyWith(commentCount: 5);
    await notifier.toggleLike(stale);
    expect(readyFeedPublication(container).commentCount, 6);
    expect(readyFeedPublication(container).likeCount, 1);
    expect(readyFeedPublication(container).likedByMe, isTrue);
  });

  testWidgets('comment then like keeps the updated comment_count on the feed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeCommunityApi()
      ..publications = [_activePublication().copyWith(commentCount: 5)];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-comment-count-21'))).data, '5');
    await openFeedComments(tester);
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('community-feed-21-comment-input')), 'Super soiree');
    await tester.tap(find.byKey(const ValueKey('community-feed-21-comment-submit')));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byKey(const ValueKey('community-comments-sheet-21')))).pop();
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-comment-count-21'))).data, '6');
    await tester.tap(find.byKey(const ValueKey('community-like-21')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-comment-count-21'))).data, '6');
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-like-count-21'))).data, '1');
  });

  testWidgets('feed like then unlike returns to the initial counters', (tester) async {
    final api = _FakeCommunityApi()..publications = [_activePublication().copyWith(likeCount: 5)];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-like-count-21'))).data, '5');
    await tester.tap(find.byKey(const ValueKey('community-like-21')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-like-count-21'))).data, '6');
    await tester.tap(find.byKey(const ValueKey('community-like-21')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-like-count-21'))).data, '5');
    expect(find.byIcon(Icons.favorite_border), findsWidgets);
  });

  test('concurrent feed likes do not send a second mutation', () async {
    final api = _FakeCommunityApi()
      ..holdLike = true
      ..publications = [_activePublication()];
    final container = await readyCommunityFeed(api);
    addTearDown(container.dispose);
    final notifier = container.read(communityFeedControllerProvider(3).notifier);
    final item = readyFeedPublication(container);
    final first = notifier.toggleLike(item);
    await Future<void>.delayed(Duration.zero);
    expect(api.likeHolds, hasLength(1));
    final second = notifier.toggleLike(item.copyWith(commentCount: 5));
    await Future<void>.delayed(Duration.zero);
    expect(api.likeHolds, hasLength(1));
    api.likeHolds.single.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(api.likedPublicationIds, [21]);
    expect(readyFeedPublication(container).likeCount, 1);
    expect(readyFeedPublication(container).likedByMe, isTrue);
    expect(readyFeedPublication(container).commentCount, 0);
  });

  Future<void> waitForDeletedSnackBar(WidgetTester tester) async {
    for (var i = 0; i < 80; i++) {
      if (find.text('Publication supprimée').evaluate().isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('author delete shows a 20 second restore snackbar with countdown', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeCommunityApi()
      ..publications = [
        const CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Texte de publication active assez long.',
          status: 'active',
          commentsEnabled: true,
        ),
      ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await tester.tap(find.byKey(const ValueKey('community-feed-item-21')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-publication-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
    await tester.pump();
    await waitForDeletedSnackBar(tester);
    expect(api.deletedPublicationIds, [21]);
    expect(find.text('Publication supprimée'), findsWidgets);
    expect(find.text('Restaurer'), findsWidgets);
    expect(find.byKey(const ValueKey('community-publication-restore-action')), findsWidgets);
    final countdown = find.byKey(const ValueKey('community-publication-restore-countdown'));
    expect(countdown, findsWidgets);
    expect(tester.widget<Text>(countdown.first).data, '20s');
    expect(
      tester.widgetList<SnackBar>(find.byType(SnackBar)).any(
            (bar) => bar.duration == const Duration(seconds: 20) && !bar.persist,
          ),
      isTrue,
    );
    expect(find.byType(CommunityDetailScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Text>(countdown.first).data, '19s');
    ScaffoldMessenger.of(tester.element(find.byType(CommunityDetailScreen))).hideCurrentSnackBar();
    await tester.pump();
  });

  testWidgets('author restore from snackbar calls existing restore and resyncs the feed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeCommunityApi()
      ..publications = [
        const CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Texte de publication active assez long.',
          status: 'active',
          commentsEnabled: true,
        ),
      ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await tester.tap(find.byKey(const ValueKey('community-feed-item-21')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-publication-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
    await tester.pump();
    await waitForDeletedSnackBar(tester);
    expect(find.byKey(const ValueKey('community-feed-item-21')), findsNothing);
    tester.widget<SnackBarAction>(find.byType(SnackBarAction).last).onPressed!();
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      if (api.restoredPublicationIds.isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(api.restoredPublicationIds, [21]);
    expect(api.networkOps, contains('POST /communities/3/publications/21/restore'));
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      if (find.byKey(const ValueKey('community-feed-item-21')).evaluate().isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('community-feed-item-21')), findsOneWidget);
    expect(find.text('Publication restaurée'), findsWidgets);
  });

  testWidgets('author restore snackbar cannot start two restores', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeCommunityApi()
      ..publications = [
        const CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Texte de publication active assez long.',
          status: 'active',
          commentsEnabled: true,
        ),
      ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await tester.tap(find.byKey(const ValueKey('community-feed-item-21')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-publication-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
    await tester.pump();
    await waitForDeletedSnackBar(tester);
    final restore = tester.widget<SnackBarAction>(find.byType(SnackBarAction).last).onPressed!;
    restore();
    restore();
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      if (api.restoredPublicationIds.isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(api.restoredPublicationIds, [21]);
    expect(
      api.networkOps.where((op) => op == 'POST /communities/3/publications/21/restore'),
      hasLength(1),
    );
  });

  testWidgets('author restore snackbar expires after 20 seconds without restoring', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeCommunityApi()
      ..publications = [
        const CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Texte de publication active assez long.',
          status: 'active',
          commentsEnabled: true,
        ),
      ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await tester.tap(find.byKey(const ValueKey('community-feed-item-21')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-publication-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
    await tester.pump();
    await waitForDeletedSnackBar(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 20));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('community-publication-restore-action')), findsNothing);
    expect(find.text('Restaurer'), findsNothing);
    expect(api.restoredPublicationIds, isEmpty);
    expect(find.byKey(const ValueKey('community-feed-item-21')), findsNothing);
  });

  testWidgets('moderator delete of another author does not show restore snackbar', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = [
        const CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 2, login: 'other', isFormerMember: false),
          body: 'Texte de publication active assez long.',
          status: 'active',
        ),
      ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
    expect(find.byType(ChroniqueCardMenu), findsNothing);
    expect(find.byKey(const ValueKey('community-feed-mod-menu-21')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-feed-mod-menu-21')));
    await tester.pumpAndSettle();
    expect(find.text('Modifier'), findsNothing);
    expect(find.text('Archiver'), findsNothing);
    expect(find.text('Supprimer'), findsOneWidget);
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer la publication ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.deletedPublicationIds, [21]);
    expect(api.networkOps, contains('DELETE /communities/3/publications/21'));
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
    expect(find.text('Publication supprimée'), findsWidgets);
    expect(find.byType(SnackBarAction), findsNothing);
    expect(find.text('Restaurer'), findsNothing);
  });

  testWidgets('member community navigation has feed and members but not management', (tester) async {
    final api = _FakeCommunityApi();
    setListedRole(api, CommunityRole.member);
    await openCommunityDetail(tester, api);
    expect(find.byKey(const ValueKey('community-nav-feed')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-nav-members')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-nav-manage')), findsNothing);
    expect(find.byKey(const ValueKey('community-publish-open')), findsOneWidget);
    await openCommunityMembersTab(tester);
    expect(find.byKey(const ValueKey('community-detail-invite')), findsNothing);
    expect(find.byKey(const ValueKey('community-leave')), findsOneWidget);
  });

  test('community comment parses parent_comment_id', () {
    final root = CommunityComment.fromJson({
      'id': 1,
      'community_id': 3,
      'community_publication_id': 21,
      'parent_comment_id': null,
      'body': 'Racine',
      'status': 'visible',
      'author': {'user_id': 1, 'login': 'tgjjk', 'is_former_member': false},
    });
    final reply = CommunityComment.fromJson({
      'id': 2,
      'community_id': 3,
      'community_publication_id': 21,
      'parent_comment_id': 1,
      'body': 'Reponse',
      'status': 'visible',
      'author': {'user_id': 2, 'login': 'other', 'is_former_member': false},
    });
    expect(root.parentCommentId, isNull);
    expect(root.isRoot, isTrue);
    expect(reply.parentCommentId, 1);
    expect(reply.isReply, isTrue);
    expect(memberVisibleCommentCount([root, reply]), 2);
    expect(
      memberVisibleCommentCount([root.copyWith(status: 'moderated'), reply]),
      0,
    );
  });

  testWidgets('feed comments open in a bottom sheet without opening detail', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeCommunityApi()
      ..publications = [_activePublication()];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(find.byType(CommunityCommentsSection), findsNothing);
    expect(find.byKey(const ValueKey('community-feed-21-comment-input')), findsNothing);
    expect(find.byKey(const ValueKey('community-comments-21')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-comments-21')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
    expect(find.byKey(const ValueKey('community-comments-sheet-21')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-feed-21-comment-input')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('community-feed-21-comment-input')), 'Depuis le fil');
    await tester.tap(find.byKey(const ValueKey('community-feed-21-comment-submit')));
    await tester.pumpAndSettle();
    expect(api.networkOps, contains('POST /communities/3/publications/21/comments'));
    expect(find.byKey(const ValueKey('community-feed-21-comment-item-500')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-comment-count-21'))).data, '1');
  });

  testWidgets('feed comment sheet reply posts parent and can be cancelled', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeCommunityApi()
      ..publications = [_activePublication().copyWith(commentCount: 1)]
      ..comments = [
        const CommunityComment(
          id: 7,
          communityId: 3,
          communityPublicationId: 21,
          body: 'Racine visible',
          status: 'visible',
          author: CommunityCommentAuthor(userId: 2, login: 'other', isFormerMember: false),
        ),
      ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await tester.tap(find.byKey(const ValueKey('community-comments-21')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-feed-21-comment-reply-7')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-feed-21-comment-reply-7')));
    await tester.pump();
    expect(find.byKey(const ValueKey('community-feed-21-comment-reply-mode')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-feed-21-comment-reply-cancel')));
    await tester.pump();
    expect(find.byKey(const ValueKey('community-feed-21-comment-reply-mode')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('community-feed-21-comment-reply-7')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('community-feed-21-comment-input')), 'Ma reponse');
    await tester.tap(find.byKey(const ValueKey('community-feed-21-comment-submit')));
    await tester.pumpAndSettle();
    expect(api.createCommentCalls.single['parentCommentId'], 7);
    expect(find.byKey(const ValueKey('community-feed-21-comment-item-500')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-feed-21-comment-reply-indent-500')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-feed-21-comment-reply-500')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-comment-count-21'))).data, '2');
  });

  testWidgets('closing the comment sheet returns to the feed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeCommunityApi()..publications = [_activePublication()];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await tester.tap(find.byKey(const ValueKey('community-comments-21')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-comments-sheet-21')), findsOneWidget);
    Navigator.of(tester.element(find.byKey(const ValueKey('community-comments-sheet-21')))).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-comments-sheet-21')), findsNothing);
    expect(find.byType(CommunityCommentsSection), findsNothing);
    expect(find.byKey(const ValueKey('community-feed-item-21')), findsOneWidget);
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
  });

  testWidgets('reply is available on roots only and posts parent_comment_id', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeCommunityApi()
      ..publications = [_activePublication().copyWith(commentCount: 1)]
      ..comments = [
        const CommunityComment(
          id: 7,
          communityId: 3,
          communityPublicationId: 21,
          body: 'Racine visible',
          status: 'visible',
          author: CommunityCommentAuthor(userId: 2, login: 'other', isFormerMember: false),
        ),
      ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await openFeedComments(tester);
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
    expect(find.byKey(const ValueKey('community-feed-21-comment-reply-7')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-feed-21-comment-reply-7')));
    await tester.pump();
    expect(find.byKey(const ValueKey('community-feed-21-comment-reply-mode')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-feed-21-comment-reply-cancel')));
    await tester.pump();
    expect(find.byKey(const ValueKey('community-feed-21-comment-reply-mode')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('community-feed-21-comment-reply-7')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('community-feed-21-comment-input')), 'Ma reponse');
    await tester.tap(find.byKey(const ValueKey('community-feed-21-comment-submit')));
    await tester.pumpAndSettle();
    expect(api.createCommentCalls.single['parentCommentId'], 7);
    expect(find.byKey(const ValueKey('community-feed-21-comment-item-500')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-feed-21-comment-reply-indent-500')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-feed-21-comment-reply-500')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-comment-count-21'))).data, '2');
  });

  testWidgets('moderating a parent hides the branch and restore brings it back', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeCommunityApi()
      ..publications = [
        const CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Texte de publication active assez long.',
          status: 'active',
          commentsEnabled: true,
          commentCount: 2,
        ),
      ]
      ..comments = [
        const CommunityComment(
          id: 7,
          communityId: 3,
          communityPublicationId: 21,
          body: 'Racine auteur',
          status: 'visible',
          author: CommunityCommentAuthor(userId: 2, login: 'other', isFormerMember: false),
        ),
        const CommunityComment(
          id: 8,
          communityId: 3,
          communityPublicationId: 21,
          parentCommentId: 7,
          body: 'Reponse visible',
          status: 'visible',
          author: CommunityCommentAuthor(userId: 3, login: 'third', isFormerMember: false),
        ),
      ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await openFeedComments(tester);
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
    expect(find.byKey(const ValueKey('community-feed-21-comment-reply-indent-8')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-feed-21-comment-mod-menu-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modérer'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-feed-21-comment-item-8')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-comment-count-21'))).data, '0');
  });

  testWidgets('comment created in detail keeps the feed counter after pop', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeCommunityApi()
      ..publications = [
        const CommunityPublication(
          id: 21,
          communityId: 3,
          author: CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
          body: 'Texte de publication active assez long.',
          status: 'active',
          commentsEnabled: true,
        ),
      ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await tester.tap(find.byKey(const ValueKey('community-feed-item-21')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityPublicationDetailScreen), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('community-comment-input')), 'Partage etat');
    await tester.tap(find.byKey(const ValueKey('community-comment-submit')));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
    expect(find.byKey(const ValueKey('community-feed-21-comment-input')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-comment-count-21'))).data, '1');
  });

  testWidgets('owner community navigation exposes management', (tester) async {
    final api = _FakeCommunityApi();
    await openCommunityDetail(tester, api);
    expect(find.byKey(const ValueKey('community-nav-feed')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-nav-members')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-nav-manage')), findsOneWidget);
    await openCommunityMembersTab(tester);
    expect(find.byKey(const ValueKey('community-detail-invite')), findsOneWidget);
    await openCommunityManagementTab(tester);
    expect(find.byKey(const ValueKey('community-sent-invitations-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-join-requests-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-manage-invitations')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-manage-join-requests')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-manage-history')), findsOneWidget);
    expect(find.text('Publications supprimées'), findsNothing);
  });

  testWidgets('A author active under 30 minutes sees Modifier', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = [authorActivePublication()]
      ..myPublications = [authorActivePublication()];
    await pumpPublicationDetail(tester, api, publicationId: 80);
    await openCommunityPublicationMenu(tester);
    expect(find.text('Modifier'), findsOneWidget);
    expect(find.text('Supprimer'), findsOneWidget);
  });

  testWidgets('B author Modifier stays on detail and enters edit mode', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = [authorActivePublication()]
      ..myPublications = [authorActivePublication()];
    await pumpPublicationDetail(tester, api, publicationId: 80);
    await enterAuthorCorrection(tester);
    expect(find.byType(CommunityPublicationDetailScreen), findsOneWidget);
    expect(find.byType(EditCommunityPublicationScreen), findsNothing);
    expect(find.text('Modifier la publication'), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget);
    expect(find.text('Enregistrer'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller?.text,
      'Titre actif auteur',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller?.text,
      'Publication active auteur encore membre.',
    );
  });

  testWidgets('C author save patches title only payload through existing PATCH', (tester) async {
    final original = authorActivePublication();
    final api = _FakeCommunityApi()
      ..publications = [original]
      ..myPublications = [original];
    await pumpPublicationDetail(tester, api, publicationId: 80);
    await enterAuthorCorrection(tester);
    await tester.enterText(find.byType(TextField).first, 'Nouveau titre jardin');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('community-publication-save')));
    await tester.pumpAndSettle();
    expect(api.patchedPublicationIds, [80]);
    expect(api.lastPatchTitle, 'Nouveau titre jardin');
    expect(api.lastPatchBody, original.body);
    expect(find.byType(EditCommunityPublicationScreen), findsNothing);
    expect(find.byType(CommunityPublicationDetailScreen), findsOneWidget);
    expect(find.text('Nouveau titre jardin'), findsOneWidget);
    expect(find.text('Modifier la publication'), findsNothing);
  });

  testWidgets('D author save patches body through existing PATCH', (tester) async {
    const nextBody = 'Texte modifié d au moins vingt caracteres.';
    final original = authorActivePublication();
    final api = _FakeCommunityApi()
      ..publications = [original]
      ..myPublications = [original];
    await pumpPublicationDetail(tester, api, publicationId: 80);
    await enterAuthorCorrection(tester);
    await tester.enterText(find.byType(TextField).at(1), nextBody);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('community-publication-save')));
    await tester.pumpAndSettle();
    expect(api.patchedPublicationIds, [80]);
    expect(api.lastPatchTitle, original.title);
    expect(api.lastPatchBody, nextBody);
    expect(find.text(nextBody), findsOneWidget);
  });

  testWidgets('E cancel leaves detail unchanged without PATCH', (tester) async {
    final original = authorActivePublication();
    final api = _FakeCommunityApi()
      ..publications = [original]
      ..myPublications = [original];
    await pumpPublicationDetail(tester, api, publicationId: 80);
    await enterAuthorCorrection(tester);
    await tester.enterText(find.byType(TextField).first, 'Titre abandonné');
    await tester.pump();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(api.patchedPublicationIds, isEmpty);
    expect(find.byType(CommunityPublicationDetailScreen), findsOneWidget);
    expect(find.text('Titre actif auteur'), findsOneWidget);
    expect(find.text('Titre abandonné'), findsNothing);
    expect(find.text('Modifier la publication'), findsNothing);
  });

  testWidgets('F system back exits edit before leaving the detail', (tester) async {
    final original = authorActivePublication();
    final api = _FakeCommunityApi()
      ..publications = [original]
      ..myPublications = [original];
    await pumpPublicationDetailOnStack(tester, api, publicationId: 80);
    await enterAuthorCorrection(tester);
    expect(find.text('Modifier la publication'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CommunityPublicationDetailScreen), findsOneWidget);
    expect(find.text('Modifier la publication'), findsNothing);
    expect(find.text('Titre actif auteur'), findsOneWidget);
    expect(api.patchedPublicationIds, isEmpty);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
  });

  testWidgets('G author after 30 minutes has no Modifier but keeps delete', (tester) async {
    final publication = authorActivePublication(publishedAt: closedWindowPublishedAt());
    final api = _FakeCommunityApi()
      ..publications = [publication]
      ..myPublications = [publication];
    await pumpPublicationDetail(tester, api, publicationId: 80);
    await openCommunityPublicationMenu(tester);
    expect(find.text('Modifier'), findsNothing);
    expect(find.text('Supprimer'), findsOneWidget);
  });

  testWidgets('H author delete remains available inside the correction window', (tester) async {
    final publication = authorActivePublication();
    final api = _FakeCommunityApi()
      ..publications = [publication]
      ..myPublications = [publication];
    await pumpPublicationDetail(tester, api, publicationId: 80);
    await openCommunityPublicationMenu(tester);
    expect(find.text('Supprimer'), findsOneWidget);
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Elle disparaîtra du fil.'), findsOneWidget);
    expect(api.deletedPublicationIds, isEmpty);
  });

  testWidgets('I 409 correction_window_expired shows user message and exits edit', (tester) async {
    final publication = authorActivePublication();
    final api = _FakeCommunityApi()
      ..publications = [publication]
      ..myPublications = [publication]
      ..failPatchPublication = const ApiException(
        message: kCorrectionWindowExpiredCode,
        statusCode: 409,
      );
    await pumpPublicationDetail(tester, api, publicationId: 80);
    final getsBefore = api.networkOps.where((op) => op.contains('GET /communities/3/publications/80')).length;
    await enterAuthorCorrection(tester);
    await tester.enterText(find.byType(TextField).first, 'Titre trop tard');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('community-publication-save')));
    await tester.pumpAndSettle();
    expect(find.text('La période de modification est terminée.'), findsWidgets);
    expect(find.text(kCorrectionWindowExpiredCode), findsNothing);
    expect(find.text('Modifier la publication'), findsNothing);
    expect(find.byType(CommunityPublicationDetailScreen), findsOneWidget);
    expect(find.text('Titre actif auteur'), findsOneWidget);
    expect(
      api.networkOps.where((op) => op.contains('GET /communities/3/publications/80')).length,
      getsBefore + 1,
    );
  });

  testWidgets('J member non-author cannot open someone else detail', (tester) async {
    final api = _FakeCommunityApi()
      ..items[0] = const Community(
        id: 3,
        name: 'Jardin secret',
        visibility: 'private',
        myRole: CommunityRole.member,
        memberCount: 1,
      )
      ..publications = [authorActivePublication(authorId: 2)];
    await pumpPublicationDetail(tester, api, publicationId: 80);
    expect(find.text('Publication indisponible'), findsOneWidget);
    expect(find.byKey(const ValueKey('community-publication-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-publication-author')), findsNothing);
    expect(find.byKey(const ValueKey('community-publication-menu')), findsNothing);
    expect(find.text('Modifier'), findsNothing);
    expect(api.patchedPublicationIds, isEmpty);
    expect(api.networkOps, contains('GET /communities/3/publications/80'));
  });

  testWidgets('K owner non-author deletes from dedicated feed menu without Modifier or PATCH', (
    tester,
  ) async {
    final api = _FakeCommunityApi()..publications = [authorActivePublication(authorId: 2)];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
    expect(find.byType(ChroniqueCardMenu), findsNothing);
    await tester.tap(find.byKey(const ValueKey('community-feed-mod-menu-80')));
    await tester.pumpAndSettle();
    expect(find.text('Modifier'), findsNothing);
    expect(find.text('Archiver'), findsNothing);
    expect(find.text('Supprimer'), findsOneWidget);
    expect(api.patchedPublicationIds, isEmpty);
  });

  testWidgets('L admin non-author deletes from dedicated feed menu without Modifier or PATCH', (
    tester,
  ) async {
    final api = _FakeCommunityApi()
      ..items[0] = const Community(
        id: 3,
        name: 'Jardin secret',
        visibility: 'private',
        myRole: CommunityRole.admin,
        memberCount: 1,
      )
      ..publications = [authorActivePublication(authorId: 2)];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
    expect(find.byType(ChroniqueCardMenu), findsNothing);
    await tester.tap(find.byKey(const ValueKey('community-feed-mod-menu-80')));
    await tester.pumpAndSettle();
    expect(find.text('Modifier'), findsNothing);
    expect(find.text('Archiver'), findsNothing);
    expect(find.text('Supprimer'), findsOneWidget);
    expect(api.patchedPublicationIds, isEmpty);
  });

  testWidgets('M owner who is also author gets Modifier from authorship plus delete', (
    tester,
  ) async {
    final api = _FakeCommunityApi()
      ..publications = [authorActivePublication()]
      ..myPublications = [authorActivePublication()];
    await pumpPublicationDetail(tester, api, publicationId: 80);
    expect(api.items.first.myRole, CommunityRole.owner);
    await openCommunityPublicationMenu(tester);
    expect(find.text('Modifier'), findsOneWidget);
    expect(find.text('Supprimer'), findsOneWidget);
  });

  testWidgets('N existing media stay visible without add-media mutation', (tester) async {
    const image = ChroniqueMedia(
      id: 10,
      kind: 'image',
      status: 'ready',
      contentType: 'image/jpeg',
      sortOrder: 0,
      readUrl: 'https://example.test/a.jpg',
    );
    final publication = authorActivePublication(media: const [image]);
    final api = _FakeCommunityApi()
      ..publications = [publication]
      ..myPublications = [publication];
    await pumpPublicationDetail(tester, api, publicationId: 80);
    expect(find.byType(ChroniqueReadyRemoteMediaList), findsOneWidget);
    expect(find.byKey(const ValueKey('community-media-delete-10')), findsOneWidget);
    expect(find.text('+ Ajouter un média'), findsNothing);
    await enterAuthorCorrection(tester);
    expect(find.byType(ChroniqueReadyRemoteMediaList), findsOneWidget);
    expect(find.byKey(const ValueKey('community-media-delete-10')), findsNothing);
    expect(find.text('+ Ajouter un média'), findsNothing);
  });

  const ChroniqueMedia _authorSpaceImage = ChroniqueMedia(
    id: 10,
    kind: 'image',
    status: 'ready',
    contentType: 'image/jpeg',
    sortOrder: 0,
    readUrl: 'https://example.test/a.jpg',
  );

  testWidgets('author under 30 minutes can delete media', (tester) async {
    final publication = authorActivePublication(media: const [_authorSpaceImage]);
    final api = _FakeCommunityApi()
      ..publications = [publication]
      ..myPublications = [publication];
    await pumpPublicationDetail(tester, api, publicationId: 80);
    expect(find.byKey(const ValueKey('community-media-delete-10')), findsOneWidget);
  });

  testWidgets('author after 30 minutes cannot delete media but can still delete the publication', (
    tester,
  ) async {
    final publication = authorActivePublication(
      publishedAt: closedWindowPublishedAt(),
      media: const [_authorSpaceImage],
    );
    final api = _FakeCommunityApi()
      ..publications = [publication]
      ..myPublications = [publication];
    await pumpPublicationDetail(tester, api, publicationId: 80);
    expect(find.byType(ChroniqueReadyRemoteMediaList), findsOneWidget);
    expect(find.byKey(const ValueKey('community-media-delete-10')), findsNothing);
    await openCommunityPublicationMenu(tester);
    expect(find.text('Modifier'), findsNothing);
    expect(find.text('Supprimer'), findsOneWidget);
  });

  testWidgets('non-author member cannot delete media', (tester) async {
    final api = _FakeCommunityApi()
      ..items[0] = const Community(
        id: 3,
        name: 'Jardin secret',
        visibility: 'private',
        myRole: CommunityRole.member,
        memberCount: 1,
      )
      ..publications = [authorActivePublication(authorId: 2, media: const [_authorSpaceImage])];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
    expect(find.byKey(const ValueKey('community-media-delete-10')), findsNothing);
    expect(find.byKey(const ValueKey('community-feed-mod-menu-80')), findsNothing);
    expect(find.byType(ChroniqueCardMenu), findsNothing);
  });

  testWidgets('owner non-author cannot delete media and keeps publication delete', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = [authorActivePublication(authorId: 2, media: const [_authorSpaceImage])];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
    expect(find.byKey(const ValueKey('community-media-delete-10')), findsNothing);
    expect(find.byType(ChroniqueCardMenu), findsNothing);
    await tester.tap(find.byKey(const ValueKey('community-feed-mod-menu-80')));
    await tester.pumpAndSettle();
    expect(find.text('Modifier'), findsNothing);
    expect(find.text('Archiver'), findsNothing);
    expect(find.text('Supprimer'), findsOneWidget);
  });

  testWidgets('admin non-author cannot delete media and keeps publication delete', (tester) async {
    final api = _FakeCommunityApi()
      ..items[0] = const Community(
        id: 3,
        name: 'Jardin secret',
        visibility: 'private',
        myRole: CommunityRole.admin,
        memberCount: 1,
      )
      ..publications = [authorActivePublication(authorId: 2, media: const [_authorSpaceImage])];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
    expect(find.byKey(const ValueKey('community-media-delete-10')), findsNothing);
    expect(find.byType(ChroniqueCardMenu), findsNothing);
    await tester.tap(find.byKey(const ValueKey('community-feed-mod-menu-80')));
    await tester.pumpAndSettle();
    expect(find.text('Modifier'), findsNothing);
    expect(find.text('Archiver'), findsNothing);
    expect(find.text('Supprimer'), findsOneWidget);
  });

  testWidgets('O likes and comments remain on the author detail hub', (tester) async {
    final publication = authorActivePublication(likeCount: 3);
    final api = _FakeCommunityApi()
      ..publications = [publication]
      ..myPublications = [publication];
    await pumpPublicationDetail(tester, api, publicationId: 80);
    expect(find.byKey(const ValueKey('community-like-80')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-comment-input')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-like-80')));
    await tester.pumpAndSettle();
    expect(api.likedPublicationIds, [80]);
    await tester.enterText(find.byKey(const ValueKey('community-comment-input')), 'Super soiree');
    await tester.tap(find.byKey(const ValueKey('community-comment-submit')));
    await tester.pumpAndSettle();
    expect(api.networkOps, contains('POST /communities/3/publications/80/comments'));
  });

  testWidgets('P scheduled still uses the existing edit screen', (tester) async {
    final original = scheduledMine();
    final api = _FakeCommunityApi()..myPublications = [original];
    await openMyPublications(tester, api);
    await tester.tap(find.byKey(const ValueKey('me-pub-current-70')));
    await tester.pumpAndSettle();
    await enterAuthorCorrection(tester);
    expect(find.byType(EditCommunityPublicationScreen), findsOneWidget);
    expect(find.text('Modifier la publication'), findsOneWidget);
  });

  CommunityPublication favoriteFeedPublication({
    int id = 21,
    int favoriteCount = 2,
    bool favoritedByMe = false,
  }) {
    return CommunityPublication(
      id: id,
      communityId: 3,
      communityName: 'Jardin secret',
      author: const CommunityPublicationAuthor(userId: 2, login: 'other', isFormerMember: false),
      body: 'Texte de publication active assez long.',
      status: 'active',
      commentsEnabled: true,
      favoriteCount: favoriteCount,
      favoritedByMe: favoritedByMe,
    );
  }

  Future<void> openMyFavorites(WidgetTester tester, _FakeCommunityApi api) async {
    await _pumpApp(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('home-user-avatar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-my-favorites')));
    await tester.pumpAndSettle();
  }

  testWidgets('feed shows favorite count and bookmark icon', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = [favoriteFeedPublication(favoritedByMe: true, favoriteCount: 4)];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(find.byKey(const ValueKey('community-favorite-21')), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsWidgets);
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-favorite-count-21'))).data, '4');
  });

  testWidgets('author publication has no favorite action on the feed', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = [
        favoriteFeedPublication().copyWith(),
      ];
    api.publications = [
      CommunityPublication(
        id: 21,
        communityId: 3,
        author: const CommunityPublicationAuthor(userId: 1, login: 'tgjjk', isFormerMember: false),
        body: 'Texte de publication active assez long.',
        status: 'active',
        commentsEnabled: true,
        favoriteCount: 2,
      ),
    ];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    expect(find.byKey(const ValueKey('community-favorite-21')), findsNothing);
    expect(find.byKey(const ValueKey('community-favorite-count-21')), findsOneWidget);
  });

  testWidgets('feed favorite then unfavorite uses server counts', (tester) async {
    final api = _FakeCommunityApi()..publications = [favoriteFeedPublication(favoriteCount: 5)];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await tester.tap(find.byKey(const ValueKey('community-favorite-21')));
    await tester.pumpAndSettle();
    expect(api.favoritedPublicationIds, [21]);
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-favorite-count-21'))).data, '6');
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-like-count-21'))).data, '0');
    await tester.tap(find.byKey(const ValueKey('community-favorite-21')));
    await tester.pumpAndSettle();
    expect(api.unfavoritedPublicationIds, [21]);
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-favorite-count-21'))).data, '5');
  });

  test('concurrent feed favorites do not send a second mutation', () async {
    final api = _FakeCommunityApi()
      ..holdFavorite = true
      ..publications = [favoriteFeedPublication()];
    final container = await readyCommunityFeed(api);
    addTearDown(container.dispose);
    final notifier = container.read(communityFeedControllerProvider(3).notifier);
    final item = readyFeedPublication(container);
    final first = notifier.toggleFavorite(item);
    await Future<void>.delayed(Duration.zero);
    expect(api.favoriteHolds, hasLength(1));
    final second = notifier.toggleFavorite(item.copyWith(commentCount: 5));
    await Future<void>.delayed(Duration.zero);
    expect(api.favoriteHolds, hasLength(1));
    api.favoriteHolds.single.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(api.favoritedPublicationIds, [21]);
    expect(readyFeedPublication(container).favoriteCount, 3);
    expect(readyFeedPublication(container).favoritedByMe, isTrue);
    expect(readyFeedPublication(container).likeCount, 0);
  });

  testWidgets('failed favorite keeps the previous counters', (tester) async {
    final api = _FakeCommunityApi()
      ..failFavorite = const ApiException(message: 'network', statusCode: 503)
      ..publications = [favoriteFeedPublication(favoriteCount: 2)];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await tester.tap(find.byKey(const ValueKey('community-favorite-21')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-favorite-count-21'))).data, '2');
    expect(find.byIcon(Icons.bookmark_border), findsWidgets);
  });

  testWidgets('home menu opens mes favoris', (tester) async {
    final api = _FakeCommunityApi()..myFavorites = [favoriteFeedPublication(favoritedByMe: true)];
    await openMyFavorites(tester, api);
    expect(find.byType(MyFavoritesScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('my-favorite-item-21')), findsOneWidget);
  });

  testWidgets('mes favoris empty state', (tester) async {
    await openMyFavorites(tester, _FakeCommunityApi());
    expect(find.byKey(const ValueKey('my-favorites-empty')), findsOneWidget);
  });

  testWidgets('mes favoris shows loading then content', (tester) async {
    final api = _FakeCommunityApi()
      ..holdListMyFavorites = true
      ..myFavorites = [favoriteFeedPublication(favoritedByMe: true)];
    await _pumpApp(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('home-user-avatar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-my-favorites')));
    await tester.pump();
    expect(find.byType(AppLoading), findsWidgets);
    api.listMyFavoritesHolds.single.complete(
      CommunityPublicationPage(items: api.myFavorites),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('my-favorite-item-21')), findsOneWidget);
  });

  testWidgets('mes favoris loading then error retry', (tester) async {
    final api = _FakeCommunityApi()
      ..failListMyFavorites = const ApiException(message: 'hors ligne', statusCode: 503);
    await openMyFavorites(tester, api);
    expect(find.byKey(const ValueKey('my-favorites-error')), findsOneWidget);
    api.failListMyFavorites = null;
    api.myFavorites = [favoriteFeedPublication(favoritedByMe: true)];
    await tester.tap(find.byKey(const ValueKey('my-favorites-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('my-favorite-item-21')), findsOneWidget);
  });

  testWidgets('removing a favorite drops the card from mes favoris', (tester) async {
    final item = favoriteFeedPublication(favoritedByMe: true, favoriteCount: 1);
    final api = _FakeCommunityApi()
      ..publications = [item]
      ..myFavorites = [item];
    await openMyFavorites(tester, api);
    await tester.tap(find.byKey(const ValueKey('community-favorite-21')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('my-favorite-item-21')), findsNothing);
    expect(find.byKey(const ValueKey('my-favorites-empty')), findsOneWidget);
  });

  testWidgets('mes favoris pagination keeps order and skips duplicates', (tester) async {
    final first = favoriteFeedPublication(id: 31, favoritedByMe: true);
    final second = favoriteFeedPublication(id: 32, favoritedByMe: true);
    final api = _FakeCommunityApi()
      ..myFavorites = [first]
      ..myFavoritesNext = const ChroniqueCursor(beforeAt: '2026-10-08T12:00:00.000Z', beforeId: 31);
    await openMyFavorites(tester, api);
    expect(find.byKey(const ValueKey('my-favorite-item-31')), findsOneWidget);
    expect(find.byKey(const ValueKey('my-favorite-item-32')), findsNothing);
    api.myFavorites = [first, second];
    await tester.tap(find.byKey(const ValueKey('my-favorites-load-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('my-favorite-item-31')), findsOneWidget);
    expect(find.byKey(const ValueKey('my-favorite-item-32')), findsOneWidget);
  });

  testWidgets('mes favoris never opens another author private detail', (tester) async {
    final api = _FakeCommunityApi()..myFavorites = [favoriteFeedPublication(favoritedByMe: true)];
    await openMyFavorites(tester, api);
    await tester.tap(find.byKey(const ValueKey('my-favorite-item-21')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityPublicationDetailScreen), findsNothing);
    expect(
      api.networkOps.where((op) => op.contains('/publications/21') && !op.contains('/favorite')),
      isEmpty,
    );
  });

  testWidgets('favorite mutation does not change like counters', (tester) async {
    final api = _FakeCommunityApi()
      ..publications = [favoriteFeedPublication().copyWith(likeCount: 4, likedByMe: true)];
    await openCommunityDetail(tester, api);
    await revealCommunityFeed(tester);
    await tester.tap(find.byKey(const ValueKey('community-favorite-21')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-like-count-21'))).data, '4');
    expect(tester.widget<Text>(find.byKey(const ValueKey('community-favorite-count-21'))).data, '3');
  });
}
