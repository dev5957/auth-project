import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/community.dart';
import '../../models/community_fields.dart';
import '../../models/join_request.dart';
import '../../models/join_request_messages.dart';
import '../../providers/community_providers.dart';
import 'my_join_requests_controller.dart';

const String kCommunitySearchPrivateNotice =
    'Cette communauté est privée. Le détail est accessible uniquement aux membres.';

sealed class CommunitySearchState {
  const CommunitySearchState();
}

final class CommunitySearchIdle extends CommunitySearchState {
  const CommunitySearchIdle({this.queryError});

  final String? queryError;
}

final class CommunitySearchLoading extends CommunitySearchState {
  const CommunitySearchLoading();
}

final class CommunitySearchReady extends CommunitySearchState {
  const CommunitySearchReady(
    this.items, {
    this.notice,
    this.memberCommunityIds = const <int>{},
    this.pendingCommunityIds = const <int>{},
    this.mutatingCommunityId,
    this.actionError,
  });

  final List<CommunitySearchPreview> items;
  final String? notice;
  final Set<int> memberCommunityIds;
  final Set<int> pendingCommunityIds;
  final int? mutatingCommunityId;
  final String? actionError;

  bool isMember(int communityId) => memberCommunityIds.contains(communityId);

  bool isPending(int communityId) => pendingCommunityIds.contains(communityId);

  bool canRequest(int communityId) =>
      !isMember(communityId) && !isPending(communityId);
}

final class CommunitySearchEmpty extends CommunitySearchState {
  const CommunitySearchEmpty();
}

final class CommunitySearchError extends CommunitySearchState {
  const CommunitySearchError(this.message, {this.statusCode});

  final String message;
  final int? statusCode;
}

class CommunitySearchController extends AutoDisposeNotifier<CommunitySearchState> {
  int _generation = 0;
  int? _mutatingCommunityId;

  @override
  CommunitySearchState build() => const CommunitySearchIdle();

  Future<void> submit(String raw) async {
    final queryError = CommunityFields.searchQueryError(raw);
    if (queryError != null) {
      state = CommunitySearchIdle(queryError: queryError);
      return;
    }
    final q = raw.trim();
    final generation = ++_generation;
    state = const CommunitySearchLoading();
    try {
      final items = await ref.read(communityRepositoryProvider).search(q);
      if (generation != _generation) {
        return;
      }
      if (items.isEmpty) {
        state = const CommunitySearchEmpty();
      } else {
        final ready = await _withMembershipContext(items, generation: generation);
        if (generation != _generation) {
          return;
        }
        state = ready;
      }
    } on ApiException catch (error) {
      if (generation != _generation) {
        return;
      }
      debugPrint(
        '[community] GET /communities/search failed '
        'status=${error.statusCode} message=${error.message}',
      );
      state = CommunitySearchError(
        error.statusCode == 401
            ? 'Session expirée'
            : (error.message.trim().isEmpty ? 'Unexpected error' : error.message),
        statusCode: error.statusCode,
      );
    } on FormatException {
      if (generation != _generation) {
        return;
      }
      state = const CommunitySearchError('Unexpected error');
    }
  }

  /// Probe `GET /communities/:id` only. Returns true when the caller may open detail.
  Future<bool> openAccessibleDetail(int communityId) async {
    final current = state;
    final generation = _generation;
    try {
      await ref.read(communityRepositoryProvider).get(communityId);
      if (generation != _generation) {
        return false;
      }
      return true;
    } on ApiException catch (error) {
      if (generation != _generation) {
        return false;
      }
      debugPrint(
        '[community] GET /communities/$communityId (search probe) failed '
        'status=${error.statusCode} message=${error.message}',
      );
      if (error.statusCode == 404 && current is CommunitySearchReady) {
        state = _readyWithNotice(current, kCommunitySearchPrivateNotice);
        return false;
      }
      if (current is CommunitySearchReady) {
        state = _readyWithNotice(
          current,
          error.statusCode == 401
              ? 'Session expirée'
              : (error.message.trim().isEmpty ? 'Unexpected error' : error.message),
        );
        return false;
      }
      state = CommunitySearchError(
        error.statusCode == 401
            ? 'Session expirée'
            : (error.message.trim().isEmpty ? 'Unexpected error' : error.message),
        statusCode: error.statusCode,
      );
      return false;
    } on FormatException {
      if (generation != _generation) {
        return false;
      }
      if (current is CommunitySearchReady) {
        state = _readyWithNotice(current, 'Unexpected error');
        return false;
      }
      state = const CommunitySearchError('Unexpected error');
      return false;
    }
  }

  CommunitySearchReady _readyWithNotice(CommunitySearchReady current, String notice) {
    return CommunitySearchReady(
      current.items,
      notice: notice,
      memberCommunityIds: current.memberCommunityIds,
      pendingCommunityIds: current.pendingCommunityIds,
      mutatingCommunityId: current.mutatingCommunityId,
      actionError: current.actionError,
    );
  }

  Future<void> requestJoin(int communityId) async {
    final current = state;
    if (current is! CommunitySearchReady) {
      return;
    }
    if (!current.canRequest(communityId) || _mutatingCommunityId != null) {
      return;
    }
    _mutatingCommunityId = communityId;
    final generation = _generation;
    state = CommunitySearchReady(
      current.items,
      notice: current.notice,
      memberCommunityIds: current.memberCommunityIds,
      pendingCommunityIds: current.pendingCommunityIds,
      mutatingCommunityId: communityId,
    );
    try {
      await ref.read(communityRepositoryProvider).createJoinRequest(communityId);
      if (generation != _generation) {
        return;
      }
      state = CommunitySearchReady(
        current.items,
        notice: current.notice,
        memberCommunityIds: current.memberCommunityIds,
        pendingCommunityIds: {...current.pendingCommunityIds, communityId},
      );
      ref.invalidate(myJoinRequestsControllerProvider);
    } on ApiException catch (error) {
      if (generation != _generation) {
        return;
      }
      debugPrint(
        '[community] POST /communities/$communityId/join-requests failed '
        'status=${error.statusCode} type=ApiException',
      );
      if (error.statusCode == 400 && error.message == 'join request already pending') {
        final refreshed = await _refreshJoinContext(
          current,
          generation: generation,
          extraPending: communityId,
        );
        if (generation != _generation) {
          return;
        }
        state = CommunitySearchReady(
          refreshed.items,
          notice: JoinRequestMessages.alreadyPending,
          memberCommunityIds: refreshed.memberCommunityIds,
          pendingCommunityIds: refreshed.pendingCommunityIds,
        );
        return;
      }
      if (error.statusCode == 400 && error.message == 'user is already a member') {
        final refreshed = await _refreshJoinContext(
          current,
          generation: generation,
          extraMember: communityId,
        );
        if (generation != _generation) {
          return;
        }
        state = CommunitySearchReady(
          refreshed.items,
          notice: JoinRequestMessages.alreadyMember,
          memberCommunityIds: refreshed.memberCommunityIds,
          pendingCommunityIds: refreshed.pendingCommunityIds,
        );
        return;
      }
      if (error.statusCode == 404) {
        final refreshed = await _refreshJoinContext(current, generation: generation);
        if (generation != _generation) {
          return;
        }
        state = CommunitySearchReady(
          refreshed.items,
          notice: JoinRequestMessages.fromApi(error),
          memberCommunityIds: refreshed.memberCommunityIds,
          pendingCommunityIds: refreshed.pendingCommunityIds,
        );
        return;
      }
      state = CommunitySearchReady(
        current.items,
        notice: current.notice,
        memberCommunityIds: current.memberCommunityIds,
        pendingCommunityIds: current.pendingCommunityIds,
        actionError: JoinRequestMessages.fromApi(error),
      );
    } on FormatException {
      if (generation != _generation) {
        return;
      }
      state = CommunitySearchReady(
        current.items,
        notice: current.notice,
        memberCommunityIds: current.memberCommunityIds,
        pendingCommunityIds: current.pendingCommunityIds,
        actionError: JoinRequestMessages.genericRetry,
      );
    } finally {
      if (_mutatingCommunityId == communityId) {
        _mutatingCommunityId = null;
      }
    }
  }

  Future<CommunitySearchReady> _withMembershipContext(
    List<CommunitySearchPreview> items, {
    required int generation,
    String? notice,
  }) async {
    var memberIds = <int>{};
    var pendingIds = <int>{};
    try {
      final memberships = await ref.read(communityRepositoryProvider).list();
      if (generation != _generation) {
        return CommunitySearchReady(items, notice: notice);
      }
      memberIds = memberships.map((item) => item.id).toSet();
    } on ApiException catch (error) {
      debugPrint(
        '[community] GET /communities (search join context) failed '
        'status=${error.statusCode} type=ApiException',
      );
    } on FormatException {
      debugPrint('[community] GET /communities (search join context) invalid payload');
    }
    try {
      final mine = await ref.read(communityRepositoryProvider).listMyJoinRequests();
      if (generation != _generation) {
        return CommunitySearchReady(items, notice: notice, memberCommunityIds: memberIds);
      }
      pendingIds = pendingCommunityIdsFrom(mine);
    } on ApiException catch (error) {
      debugPrint(
        '[community] GET /join-requests/mine (search join context) failed '
        'status=${error.statusCode} type=ApiException',
      );
    } on FormatException {
      debugPrint('[community] GET /join-requests/mine (search join context) invalid payload');
    }
    return CommunitySearchReady(
      items,
      notice: notice,
      memberCommunityIds: memberIds,
      pendingCommunityIds: pendingIds,
    );
  }

  Future<CommunitySearchReady> _refreshJoinContext(
    CommunitySearchReady current, {
    required int generation,
    int? extraPending,
    int? extraMember,
  }) async {
    final next = await _withMembershipContext(
      current.items,
      generation: generation,
      notice: current.notice,
    );
    return CommunitySearchReady(
      next.items,
      notice: next.notice,
      memberCommunityIds: {
        ...next.memberCommunityIds,
        if (extraMember != null) extraMember,
      },
      pendingCommunityIds: {
        ...next.pendingCommunityIds,
        if (extraPending != null) extraPending,
      },
    );
  }
}

final communitySearchControllerProvider =
    AutoDisposeNotifierProvider<CommunitySearchController, CommunitySearchState>(
  CommunitySearchController.new,
);
