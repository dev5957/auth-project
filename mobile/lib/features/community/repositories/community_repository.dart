import '../../../core/network/api_exception.dart';
import '../../auth/data/storage/auth_token_storage.dart';
import '../models/community.dart';
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

  Future<String> _requireAccessToken() async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(message: 'Unauthorized', statusCode: 401);
    }
    return token;
  }
}
