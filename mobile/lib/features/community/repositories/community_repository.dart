import '../../../core/network/api_exception.dart';
import '../../auth/data/storage/auth_token_storage.dart';
import '../models/community.dart';
import '../models/community_publication.dart';
import '../models/join_request.dart';
import '../../chronique/models/chronique_media_upload.dart';
import '../../chronique/models/media_draft.dart';
import '../services/community_api_service.dart';

class CommunityRepository {
  CommunityRepository({
    required CommunityApiService api,
    required AuthTokenStorage tokenStorage,
  })  : _api = api,
        _tokenStorage = tokenStorage;

  final CommunityApiService _api;
  final AuthTokenStorage _tokenStorage;

  Future<Community> create({required String name, String? description}) async {
    return _api.create(
      accessToken: await _requireAccessToken(),
      name: name,
      description: description,
    );
  }

  Future<List<Community>> list() async {
    return _api.list(accessToken: await _requireAccessToken());
  }

  Future<List<CommunitySearchPreview>> search(String q) async {
    return _api.search(accessToken: await _requireAccessToken(), q: q);
  }

  Future<List<UserSearchHit>> searchUsers({String? login, String? phone}) async {
    return _api.searchUsers(
      accessToken: await _requireAccessToken(),
      login: login,
      phone: phone,
    );
  }

  Future<Community> get(int id) async {
    return _api.get(accessToken: await _requireAccessToken(), id: id);
  }

  Future<List<CommunityMember>> listMembers(int id) async {
    return _api.listMembers(accessToken: await _requireAccessToken(), id: id);
  }

  Future<CommunityMember> updateMemberRole({
    required int communityId,
    required int userId,
    required String role,
  }) async {
    return _api.updateMemberRole(
      accessToken: await _requireAccessToken(),
      communityId: communityId,
      userId: userId,
      role: role,
    );
  }

  Future<void> removeMember({
    required int communityId,
    required int userId,
  }) async {
    await _api.removeMember(
      accessToken: await _requireAccessToken(),
      communityId: communityId,
      userId: userId,
    );
  }

  Future<Map<String, dynamic>> leaveCommunity(int communityId) async {
    return _api.leaveCommunity(
      accessToken: await _requireAccessToken(),
      communityId: communityId,
    );
  }

  Future<CreatedCommunityInvitation> createInvitation({
    required int communityId,
    required int userId,
  }) async {
    return _api.createInvitation(
      accessToken: await _requireAccessToken(),
      communityId: communityId,
      userId: userId,
    );
  }

  Future<List<ReceivedCommunityInvitation>> listInvitations() async {
    return _api.listInvitations(accessToken: await _requireAccessToken());
  }

  Future<void> acceptInvitation(int invitationId) async {
    await _api.acceptInvitation(
      accessToken: await _requireAccessToken(),
      invitationId: invitationId,
    );
  }

  Future<void> declineInvitation(int invitationId) async {
    await _api.declineInvitation(
      accessToken: await _requireAccessToken(),
      invitationId: invitationId,
    );
  }

  Future<List<SentCommunityInvitation>> listSentInvitations(int communityId) async {
    return _api.listSentInvitations(
      accessToken: await _requireAccessToken(),
      communityId: communityId,
    );
  }

  Future<CreatedJoinRequest> createJoinRequest(int communityId) async {
    return _api.createJoinRequest(
      accessToken: await _requireAccessToken(),
      communityId: communityId,
    );
  }

  Future<List<MyJoinRequest>> listMyJoinRequests() async {
    return _api.listMyJoinRequests(accessToken: await _requireAccessToken());
  }

  Future<List<OwnerJoinRequest>> listCommunityJoinRequests(int communityId) async {
    return _api.listCommunityJoinRequests(
      accessToken: await _requireAccessToken(),
      communityId: communityId,
    );
  }

  Future<void> acceptJoinRequest({
    required int communityId,
    required int requestId,
  }) async {
    await _api.acceptJoinRequest(
      accessToken: await _requireAccessToken(),
      communityId: communityId,
      requestId: requestId,
    );
  }

  Future<void> declineJoinRequest({
    required int communityId,
    required int requestId,
  }) async {
    await _api.declineJoinRequest(
      accessToken: await _requireAccessToken(),
      communityId: communityId,
      requestId: requestId,
    );
  }

  Future<String> _requireAccessToken() async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(message: 'Unauthorized', statusCode: 401);
    }
    return token;
  }

  Future<CommunityPublication> createPublication({
    required int communityId,
    required String body,
    String? title,
    String publish = 'now',
    String? scheduledAt,
    bool isTimeLimited = false,
    String? expiresAt,
    bool commentsEnabled = false,
    int initialMediaCount = 0,
  }) {
    return _withToken(
      (token) => _api.createPublication(
        accessToken: token,
        communityId: communityId,
        body: body,
        title: title,
        publish: publish,
        scheduledAt: scheduledAt,
        isTimeLimited: isTimeLimited,
        expiresAt: expiresAt,
        commentsEnabled: commentsEnabled,
        initialMediaCount: initialMediaCount,
      ),
    );
  }

  Future<CommunityPublicationPage> listPublications(int communityId) {
    return _withToken(
      (token) => _api.listPublications(accessToken: token, communityId: communityId),
    );
  }

  Future<CommunityPublication> getPublication({
    required int communityId,
    required int publicationId,
  }) {
    return _withToken(
      (token) => _api.getPublication(
        accessToken: token,
        communityId: communityId,
        publicationId: publicationId,
      ),
    );
  }

  Future<CommunityPublication> patchPublication({
    required int communityId,
    required int publicationId,
    String? title,
    String? body,
  }) {
    return _withToken(
      (token) => _api.patchPublication(
        accessToken: token,
        communityId: communityId,
        publicationId: publicationId,
        title: title,
        body: body,
      ),
    );
  }

  Future<void> deletePublication({
    required int communityId,
    required int publicationId,
  }) {
    return _withToken(
      (token) => _api.deletePublication(
        accessToken: token,
        communityId: communityId,
        publicationId: publicationId,
      ),
    );
  }

  Future<CommunityPublication> restorePublication({
    required int communityId,
    required int publicationId,
  }) {
    return _withToken(
      (token) => _api.restorePublication(
        accessToken: token,
        communityId: communityId,
        publicationId: publicationId,
      ),
    );
  }

  Future<ChroniqueMediaUploadSession> createPublicationMediaUpload({
    required int communityId,
    required int publicationId,
    required MediaDraft media,
  }) {
    return _withToken(
      (token) => _api.createPublicationMediaUpload(
        accessToken: token,
        communityId: communityId,
        publicationId: publicationId,
        data: <String, dynamic>{
          'kind': media.kind.name,
          'source_type': media.sourceType.name,
          'content_type': media.contentType,
          'byte_size': media.byteSize,
          if (media.fileName != null) 'original_filename': media.fileName,
        },
      ),
    );
  }

  Future<void> completePublicationMediaUpload({
    required int communityId,
    required int publicationId,
    required int mediaId,
  }) {
    return _withToken(
      (token) => _api.completePublicationMediaUpload(
        accessToken: token,
        communityId: communityId,
        publicationId: publicationId,
        mediaId: mediaId,
      ),
    );
  }

  Future<void> deletePublicationMedia({
    required int communityId,
    required int publicationId,
    required int mediaId,
  }) {
    return _withToken(
      (token) => _api.deletePublicationMedia(
        accessToken: token,
        communityId: communityId,
        publicationId: publicationId,
        mediaId: mediaId,
      ),
    );
  }

  Future<CommunityPublicationPage> listMyPublications(String scope) {
    return _withToken((token) => _api.listMyPublications(accessToken: token, scope: scope));
  }

  Future<CommunityPublication> getMyPublication(int publicationId) {
    return _withToken(
      (token) => _api.getMyPublication(accessToken: token, publicationId: publicationId),
    );
  }

  Future<T> _withToken<T>(Future<T> Function(String token) run) async {
    return run(await _requireAccessToken());
  }
}
