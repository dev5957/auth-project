import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/community.dart';
import '../../providers/community_providers.dart';

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
}

final communityDetailControllerProvider = AutoDisposeNotifierProvider.family<
    CommunityDetailController, CommunityDetailState, int>(
  CommunityDetailController.new,
);
