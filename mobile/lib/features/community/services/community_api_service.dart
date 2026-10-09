import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/community.dart';
import '../models/community_comment.dart';
import '../models/community_publication.dart';
import '../models/join_request.dart';
import '../models/community_identity_upload.dart';
import '../../chronique/models/chronique_media_upload.dart';

class CommunityApiService {
  CommunityApiService(this._client);

  final ApiClient _client;

  Future<Community> create({
    required String accessToken,
    required String name,
    String? description,
  }) async {
    final json = await _send(
      'POST',
      '/communities',
      accessToken: accessToken,
      data: <String, dynamic>{
        'name': name,
        if (description != null) 'description': description,
      },
    );
    return _communityFrom(json);
  }

  Future<List<Community>> list({required String accessToken}) async {
    final json = await _send('GET', '/communities', accessToken: accessToken);
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid community list payload');
    }
    return [
      for (final item in items) Community.fromJson(_asMap(item)),
    ];
  }

  Future<List<UserSearchHit>> searchUsers({
    required String accessToken,
    String? login,
    String? phone,
  }) async {
    final hasLogin = login != null;
    final hasPhone = phone != null;
    if (hasLogin == hasPhone) {
      throw const FormatException('User search requires login or phone');
    }
    final json = await _send(
      'GET',
      '/users/search',
      accessToken: accessToken,
      queryParameters: hasLogin
          ? <String, dynamic>{'login': login}
          : <String, dynamic>{'phone': phone},
    );
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid user search payload');
    }
    return [
      for (final item in items) UserSearchHit.fromJson(_asMap(item)),
    ];
  }

  Future<List<CommunitySearchPreview>> search({
    required String accessToken,
    required String q,
  }) async {
    final json = await _send(
      'GET',
      '/communities/search',
      accessToken: accessToken,
      queryParameters: <String, dynamic>{'q': q},
    );
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid community search payload');
    }
    return [
      for (final item in items) CommunitySearchPreview.fromJson(_asMap(item)),
    ];
  }

  Future<Community> get({
    required String accessToken,
    required int id,
  }) async {
    final json = await _send('GET', '/communities/$id', accessToken: accessToken);
    return _communityFrom(json);
  }

  Future<CommunityIdentityUploadSession> createIdentityUpload({
    required String accessToken,
    required int communityId,
    required String slot,
    required Map<String, dynamic> data,
  }) async {
    final json = await _send(
      'POST',
      '/communities/$communityId/$slot/uploads',
      accessToken: accessToken,
      data: data,
    );
    return CommunityIdentityUploadSession.fromJson(json);
  }

  Future<Community> completeIdentityUpload({
    required String accessToken,
    required int communityId,
    required String slot,
    required String uploadId,
  }) async {
    final json = await _send(
      'POST',
      '/communities/$communityId/$slot/complete',
      accessToken: accessToken,
      data: <String, dynamic>{'upload_id': uploadId},
    );
    return _communityFrom(json);
  }

  Future<CreatedCommunityInvitation> createInvitation({
    required String accessToken,
    required int communityId,
    required int userId,
  }) async {
    final json = await _send(
      'POST',
      '/communities/$communityId/invitations',
      accessToken: accessToken,
      data: <String, dynamic>{'user_id': userId},
    );
    final invitation = json['invitation'] ?? json;
    return CreatedCommunityInvitation.fromJson(_asMap(invitation));
  }

  Future<List<ReceivedCommunityInvitation>> listInvitations({
    required String accessToken,
  }) async {
    final json = await _send('GET', '/invitations', accessToken: accessToken);
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid invitation list payload');
    }
    return [
      for (final item in items) ReceivedCommunityInvitation.fromJson(_asMap(item)),
    ];
  }

  Future<void> acceptInvitation({
    required String accessToken,
    required int invitationId,
  }) async {
    await _send(
      'POST',
      '/invitations/$invitationId/accept',
      accessToken: accessToken,
    );
  }

  Future<void> declineInvitation({
    required String accessToken,
    required int invitationId,
  }) async {
    await _send(
      'POST',
      '/invitations/$invitationId/decline',
      accessToken: accessToken,
    );
  }

  Future<CreatedJoinRequest> createJoinRequest({
    required String accessToken,
    required int communityId,
  }) async {
    final json = await _send(
      'POST',
      '/communities/$communityId/join-requests',
      accessToken: accessToken,
      data: <String, dynamic>{},
    );
    final joinRequest = json['join_request'] ?? json;
    return CreatedJoinRequest.fromJson(_asMap(joinRequest));
  }

  Future<List<MyJoinRequest>> listMyJoinRequests({
    required String accessToken,
  }) async {
    final json = await _send(
      'GET',
      '/join-requests/mine',
      accessToken: accessToken,
    );
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid join request list payload');
    }
    return [
      for (final item in items) MyJoinRequest.fromJson(_asMap(item)),
    ];
  }

  Future<List<OwnerJoinRequest>> listCommunityJoinRequests({
    required String accessToken,
    required int communityId,
  }) async {
    final json = await _send(
      'GET',
      '/communities/$communityId/join-requests',
      accessToken: accessToken,
    );
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid join request list payload');
    }
    return [
      for (final item in items) OwnerJoinRequest.fromJson(_asMap(item)),
    ];
  }

  Future<void> acceptJoinRequest({
    required String accessToken,
    required int communityId,
    required int requestId,
  }) async {
    await _send(
      'POST',
      '/communities/$communityId/join-requests/$requestId/accept',
      accessToken: accessToken,
    );
  }

  Future<void> declineJoinRequest({
    required String accessToken,
    required int communityId,
    required int requestId,
  }) async {
    await _send(
      'POST',
      '/communities/$communityId/join-requests/$requestId/decline',
      accessToken: accessToken,
    );
  }

  Future<List<SentCommunityInvitation>> listSentInvitations({
    required String accessToken,
    required int communityId,
  }) async {
    final json = await _send(
      'GET',
      '/communities/$communityId/invitations',
      accessToken: accessToken,
    );
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid sent invitation list payload');
    }
    return [
      for (final item in items) SentCommunityInvitation.fromJson(_asMap(item)),
    ];
  }

  Future<List<CommunityMember>> listMembers({
    required String accessToken,
    required int id,
  }) async {
    final json = await _send(
      'GET',
      '/communities/$id/members',
      accessToken: accessToken,
    );
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid community members payload');
    }
    return [
      for (final item in items) CommunityMember.fromJson(_asMap(item)),
    ];
  }

  Future<CommunityMember> updateMemberRole({
    required String accessToken,
    required int communityId,
    required int userId,
    required String role,
  }) async {
    final json = await _send(
      'PATCH',
      '/communities/$communityId/members/$userId',
      accessToken: accessToken,
      data: <String, dynamic>{'role': role},
    );
    final member = json['member'] ?? json;
    return CommunityMember.fromJson(_asMap(member));
  }

  Future<void> removeMember({
    required String accessToken,
    required int communityId,
    required int userId,
  }) async {
    await _send(
      'DELETE',
      '/communities/$communityId/members/$userId',
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> leaveCommunity({
    required String accessToken,
    required int communityId,
  }) async {
    return _send(
      'POST',
      '/communities/$communityId/leave',
      accessToken: accessToken,
    );
  }

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
    final json = await _send(
      'POST',
      '/communities/$communityId/publications',
      accessToken: accessToken,
      data: <String, dynamic>{
        'body': body,
        'publish': publish,
        if (title != null && title.isNotEmpty) 'title': title,
        if (publish == 'schedule' && scheduledAt != null) 'scheduled_at': scheduledAt,
        if (isTimeLimited) 'is_time_limited': true,
        if (isTimeLimited && expiresAt != null) 'expires_at': expiresAt,
        'comments_enabled': commentsEnabled,
        'initial_media_count': initialMediaCount,
      },
    );
    return CommunityPublication.fromJson(_asMap(json['publication'] ?? json));
  }

  Future<CommunityPublicationPage> listPublications({
    required String accessToken,
    required int communityId,
  }) async {
    final json = await _send(
      'GET',
      '/communities/$communityId/publications',
      accessToken: accessToken,
    );
    return CommunityPublicationPage.fromJson(json);
  }

  Future<CommunityPublication> getPublication({
    required String accessToken,
    required int communityId,
    required int publicationId,
  }) async {
    final json = await _send(
      'GET',
      '/communities/$communityId/publications/$publicationId',
      accessToken: accessToken,
    );
    return CommunityPublication.fromJson(_asMap(json['publication'] ?? json));
  }

  Future<CommunityPublication> patchPublication({
    required String accessToken,
    required int communityId,
    required int publicationId,
    String? title,
    String? body,
  }) async {
    final json = await _send(
      'PATCH',
      '/communities/$communityId/publications/$publicationId',
      accessToken: accessToken,
      data: <String, dynamic>{
        if (title != null) 'title': title,
        if (body != null) 'body': body,
      },
    );
    return CommunityPublication.fromJson(_asMap(json['publication'] ?? json));
  }

  Future<void> deletePublication({
    required String accessToken,
    required int communityId,
    required int publicationId,
  }) async {
    await _send(
      'DELETE',
      '/communities/$communityId/publications/$publicationId',
      accessToken: accessToken,
    );
  }

  Future<CommunityPublication> restorePublication({
    required String accessToken,
    required int communityId,
    required int publicationId,
  }) async {
    final json = await _send(
      'POST',
      '/communities/$communityId/publications/$publicationId/restore',
      accessToken: accessToken,
    );
    return CommunityPublication.fromJson(_asMap(json['publication'] ?? json));
  }

  Future<CommunityLikeState> likePublication({
    required String accessToken,
    required int communityId,
    required int publicationId,
  }) async {
    final json = await _send(
      'PUT',
      '/communities/$communityId/publications/$publicationId/like',
      accessToken: accessToken,
    );
    return CommunityLikeState.fromJson(json);
  }

  Future<CommunityLikeState> unlikePublication({
    required String accessToken,
    required int communityId,
    required int publicationId,
  }) async {
    final json = await _send(
      'DELETE',
      '/communities/$communityId/publications/$publicationId/like',
      accessToken: accessToken,
    );
    return CommunityLikeState.fromJson(json);
  }

  Future<CommunityCommentPage> listComments({
    required String accessToken,
    required int communityId,
    required int publicationId,
    String? beforeAt,
    int? beforeId,
  }) async {
    final json = await _send(
      'GET',
      '/communities/$communityId/publications/$publicationId/comments',
      accessToken: accessToken,
      queryParameters: <String, dynamic>{
        if (beforeAt != null) 'before_at': beforeAt,
        if (beforeId != null) 'before_id': beforeId,
      },
    );
    return CommunityCommentPage.fromJson(json);
  }

  Future<CommunityComment> createComment({
    required String accessToken,
    required int communityId,
    required int publicationId,
    required String body,
    int? parentCommentId,
  }) async {
    final json = await _send(
      'POST',
      '/communities/$communityId/publications/$publicationId/comments',
      accessToken: accessToken,
      data: <String, dynamic>{
        'body': body,
        if (parentCommentId != null) 'parent_comment_id': parentCommentId,
      },
    );
    return CommunityComment.fromJson(_asMap(json['comment'] ?? json));
  }

  Future<CommunityComment> updateComment({
    required String accessToken,
    required int communityId,
    required int publicationId,
    required int commentId,
    required String body,
  }) async {
    final json = await _send(
      'PATCH',
      '/communities/$communityId/publications/$publicationId/comments/$commentId',
      accessToken: accessToken,
      data: <String, dynamic>{'body': body},
    );
    return CommunityComment.fromJson(_asMap(json['comment'] ?? json));
  }

  Future<void> deleteComment({
    required String accessToken,
    required int communityId,
    required int publicationId,
    required int commentId,
  }) async {
    await _send(
      'DELETE',
      '/communities/$communityId/publications/$publicationId/comments/$commentId',
      accessToken: accessToken,
    );
  }

  Future<CommunityComment> restoreComment({
    required String accessToken,
    required int communityId,
    required int publicationId,
    required int commentId,
  }) async {
    final json = await _send(
      'POST',
      '/communities/$communityId/publications/$publicationId/comments/$commentId/restore',
      accessToken: accessToken,
    );
    return CommunityComment.fromJson(_asMap(json['comment'] ?? json));
  }

  Future<CommunityCommentTracePage> listMyCommentTraces({
    required String accessToken,
    String? beforeAt,
    int? beforeId,
  }) async {
    final json = await _send(
      'GET',
      '/me/community-comment-traces',
      accessToken: accessToken,
      queryParameters: <String, dynamic>{
        if (beforeAt != null) 'before_at': beforeAt,
        if (beforeId != null) 'before_id': beforeId,
      },
    );
    return CommunityCommentTracePage.fromJson(json);
  }

  Future<ChroniqueMediaUploadSession> createPublicationMediaUpload({
    required String accessToken,
    required int communityId,
    required int publicationId,
    required Map<String, dynamic> data,
  }) async {
    final json = await _send(
      'POST',
      '/communities/$communityId/publications/$publicationId/media/uploads',
      accessToken: accessToken,
      data: data,
    );
    return ChroniqueMediaUploadSession.fromJson(json);
  }

  Future<void> completePublicationMediaUpload({
    required String accessToken,
    required int communityId,
    required int publicationId,
    required int mediaId,
  }) async {
    await _send(
      'POST',
      '/communities/$communityId/publications/$publicationId/media/$mediaId/complete',
      accessToken: accessToken,
    );
  }

  Future<void> deletePublicationMedia({
    required String accessToken,
    required int communityId,
    required int publicationId,
    required int mediaId,
  }) async {
    await _send(
      'DELETE',
      '/communities/$communityId/publications/$publicationId/media/$mediaId',
      accessToken: accessToken,
    );
  }

  Future<CommunityPublicationPage> listMyPublications({
    required String accessToken,
    required String scope,
  }) async {
    final json = await _send(
      'GET',
      '/me/community-publications',
      accessToken: accessToken,
      queryParameters: <String, dynamic>{'scope': scope},
    );
    return CommunityPublicationPage.fromJson(json);
  }

  Future<CommunityPublication> getMyPublication({
    required String accessToken,
    required int publicationId,
  }) async {
    final json = await _send(
      'GET',
      '/me/community-publications/$publicationId',
      accessToken: accessToken,
    );
    return CommunityPublication.fromJson(_asMap(json['publication'] ?? json));
  }

  Community _communityFrom(Map<String, dynamic> json) {
    final community = json['community'] ?? json;
    return Community.fromJson(_asMap(community));
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw const FormatException('Invalid community payload');
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    required String accessToken,
  }) async {
    try {
      final response = await _client.dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: <String, dynamic>{'Authorization': 'Bearer $accessToken'},
        ),
      );
      if (response.data == null || response.data == '') {
        return <String, dynamic>{};
      }
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      throw const FormatException('Invalid community payload');
    } on DioException catch (error) {
      debugPrint(
        '[community-http] $method $path failed '
        'type=${error.type} status=${error.response?.statusCode}',
      );
      final mapped = error.error;
      if (mapped is ApiException) {
        throw mapped;
      }
      throw ApiException.fromDio(error);
    }
  }
}

