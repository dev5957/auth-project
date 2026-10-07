import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../chronique/media/chronique_local_media_picker.dart';
import '../../../chronique/media/chronique_media_limits.dart';
import '../../../chronique/media/chronique_media_mime.dart';
import '../../../chronique/models/media_draft.dart';
import '../../../chronique/providers/chronique_providers.dart';
import '../../models/community.dart';
import '../../models/community_identity_upload.dart';
import '../../providers/community_providers.dart';
import 'community_list_controller.dart';

class CommunityDetailData {
  const CommunityDetailData({
    required this.community,
    required this.members,
  });

  final Community community;
  final List<CommunityMember> members;
}

sealed class CommunityDetailState {
  const CommunityDetailState();
}

final class CommunityDetailLoading extends CommunityDetailState {
  const CommunityDetailLoading();
}

final class CommunityDetailReady extends CommunityDetailState {
  const CommunityDetailReady(this.data);

  final CommunityDetailData data;
}

final class CommunityDetailError extends CommunityDetailState {
  const CommunityDetailError(this.message, {this.statusCode});

  final String message;
  final int? statusCode;
}

class CommunityDetailController extends AutoDisposeFamilyNotifier<CommunityDetailState, int> {
  late int _communityId;

  @override
  CommunityDetailState build(int communityId) {
    _communityId = communityId;
    Future<void>.microtask(load);
    return const CommunityDetailLoading();
  }

  Future<void> load() async {
    final communityId = _communityId;
    try {
      final repo = ref.read(communityRepositoryProvider);
      final community = await repo.get(communityId);
      final members = await repo.listMembers(communityId);
      state = CommunityDetailReady(
        CommunityDetailData(community: community, members: members),
      );
    } on ApiException catch (error) {
      debugPrint(
        '[community] GET /communities/$communityId failed '
        'status=${error.statusCode} message=${error.message}',
      );
      state = CommunityDetailError(
        error.message.trim().isEmpty ? 'Unexpected error' : error.message,
        statusCode: error.statusCode,
      );
    } on FormatException {
      state = const CommunityDetailError('Unexpected error');
    }
  }

  Future<bool> updateMemberRole({required int userId, required String role}) async {
    try {
      final repo = ref.read(communityRepositoryProvider);
      await repo.updateMemberRole(communityId: _communityId, userId: userId, role: role);
      await load();
      return true;
    } on ApiException catch (error) {
      debugPrint(
        '[community] PATCH members failed status=${error.statusCode} message=${error.message}',
      );
      return false;
    }
  }

  Future<bool> removeMember(int userId) async {
    try {
      final repo = ref.read(communityRepositoryProvider);
      await repo.removeMember(communityId: _communityId, userId: userId);
      await load();
      return true;
    } on ApiException catch (error) {
      debugPrint(
        '[community] DELETE members failed status=${error.statusCode} message=${error.message}',
      );
      return false;
    }
  }

  static const _identityTypes = {'image/jpeg', 'image/png', 'image/webp'};

  Future<String?> editIdentity(CommunityIdentitySlot slot) async {
    final picker = ref.read(chroniqueLocalMediaPickerProvider);
    final picked = await picker.pickImage(limit: 1);
    switch (picked) {
      case MediaPickCancelled():
        return null;
      case MediaPickFailed(:final message):
        return message;
      case MediaPickMany(:final items):
        if (items.isEmpty) {
          return null;
        }
        return _uploadIdentity(slot, items.first);
      case MediaPickSelected():
        return _uploadIdentity(slot, picked);
    }
  }

  Future<String?> _uploadIdentity(
    CommunityIdentitySlot slot,
    MediaPickSelected item,
  ) async {
    final mime = resolveChroniqueMediaContentType(
          kind: MediaDraftKind.image,
          fileName: item.fileName,
          localPath: item.localPath,
          platformMime: item.contentType ?? item.platformMime,
        ) ??
        item.contentType;
    if (mime == null || !_identityTypes.contains(mime)) {
      return 'Format d’image non pris en charge';
    }
    final file = File(item.localPath);
    if (!file.existsSync()) {
      return kMediaUploadFailedMessage;
    }
    final byteSize = item.byteSize > 0 ? item.byteSize : file.lengthSync();
    final slotName = slot == CommunityIdentitySlot.banner ? 'banner' : 'avatar';
    try {
      final repo = ref.read(communityRepositoryProvider);
      final session = await repo.createIdentityUpload(
        communityId: _communityId,
        slot: slotName,
        data: <String, dynamic>{
          'content_type': mime,
          'byte_size': byteSize,
        },
      );
      await ref.read(chroniqueMediaUploadClientProvider).putFile(
            url: session.url,
            method: session.method,
            headers: session.headers,
            localPath: item.localPath,
            byteSize: byteSize,
          );
      final community = await repo.completeIdentityUpload(
        communityId: _communityId,
        slot: slotName,
        uploadId: session.uploadId,
      );
      final current = state;
      if (current is CommunityDetailReady) {
        state = CommunityDetailReady(
          CommunityDetailData(community: community, members: current.data.members),
        );
      } else {
        await load();
      }
      ref.read(communityListControllerProvider.notifier).replaceCommunity(community);
      return null;
    } on ApiException catch (error) {
      debugPrint(
        '[community] identity upload failed status=${error.statusCode} message=${error.message}',
      );
      return error.message.trim().isEmpty ? kMediaUploadFailedMessage : error.message;
    } on FormatException {
      return kMediaUploadFailedMessage;
    }
  }

  Future<bool> leave() async {
    try {
      final repo = ref.read(communityRepositoryProvider);
      await repo.leaveCommunity(_communityId);
      return true;
    } on ApiException catch (error) {
      debugPrint(
        '[community] POST leave failed status=${error.statusCode} message=${error.message}',
      );
      return false;
    }
  }
}

final communityDetailControllerProvider = AutoDisposeNotifierProvider.family<
    CommunityDetailController, CommunityDetailState, int>(
  CommunityDetailController.new,
);
