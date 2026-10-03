import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/join_request.dart';
import '../../models/join_request_messages.dart';
import '../../providers/community_providers.dart';
import 'community_detail_controller.dart';
import 'community_list_controller.dart';
import 'sent_invitations_controller.dart';

sealed class CommunityJoinRequestsState {
  const CommunityJoinRequestsState();
}

final class CommunityJoinRequestsLoading extends CommunityJoinRequestsState {
  const CommunityJoinRequestsLoading();
}

final class CommunityJoinRequestsReady extends CommunityJoinRequestsState {
  const CommunityJoinRequestsReady({
    required this.pending,
    required this.history,
    this.mutatingId,
    this.notice,
    this.actionError,
  });

  final List<OwnerJoinRequest> pending;
  final List<OwnerJoinRequest> history;
  final int? mutatingId;
  final String? notice;
  final String? actionError;
}

final class CommunityJoinRequestsError extends CommunityJoinRequestsState {
  const CommunityJoinRequestsError(this.message, {this.statusCode});

  final String message;
  final int? statusCode;
}

class CommunityJoinRequestsController
    extends AutoDisposeFamilyNotifier<CommunityJoinRequestsState, int> {
  late int _communityId;
  int _generation = 0;
  int? _mutatingId;

  @override
  CommunityJoinRequestsState build(int communityId) {
    _communityId = communityId;
    Future<void>.microtask(load);
    return const CommunityJoinRequestsLoading();
  }

  Future<void> load({String? notice}) async {
    final communityId = _communityId;
    final generation = ++_generation;
    _mutatingId = null;
    state = const CommunityJoinRequestsLoading();
    try {
      final items = await ref.read(communityRepositoryProvider).listCommunityJoinRequests(communityId);
      if (generation != _generation) {
        return;
      }
      state = CommunityJoinRequestsReady(
        pending: items.where((item) => item.status == 'pending').toList(),
        history: items
            .where((item) => item.status == 'accepted' || item.status == 'declined')
            .toList(),
        notice: notice,
      );
    } on ApiException catch (error) {
      if (generation != _generation) {
        return;
      }
      debugPrint(
        '[community] GET /communities/$communityId/join-requests failed '
        'status=${error.statusCode} type=ApiException',
      );
      state = CommunityJoinRequestsError(
        JoinRequestMessages.fromApi(error),
        statusCode: error.statusCode,
      );
    } on FormatException {
      if (generation != _generation) {
        return;
      }
      state = const CommunityJoinRequestsError(JoinRequestMessages.genericRetry);
    }
  }

  Future<void> accept(int requestId) {
    return _mutate(
      requestId,
      accept: true,
      action: () => ref.read(communityRepositoryProvider).acceptJoinRequest(
            communityId: _communityId,
            requestId: requestId,
          ),
      successNotice: JoinRequestMessages.acceptedNotice,
    );
  }

  Future<void> decline(int requestId) {
    return _mutate(
      requestId,
      accept: false,
      action: () => ref.read(communityRepositoryProvider).declineJoinRequest(
            communityId: _communityId,
            requestId: requestId,
          ),
      successNotice: JoinRequestMessages.declinedNotice,
    );
  }

  Future<void> _mutate(
    int requestId, {
    required bool accept,
    required Future<void> Function() action,
    required String successNotice,
  }) async {
    final current = state;
    if (current is! CommunityJoinRequestsReady) {
      return;
    }
    if (_mutatingId != null) {
      return;
    }
    _mutatingId = requestId;
    final generation = _generation;
    state = CommunityJoinRequestsReady(
      pending: current.pending,
      history: current.history,
      mutatingId: requestId,
    );
    try {
      await action();
      if (generation != _generation) {
        return;
      }
      OwnerJoinRequest? moved;
      final pending = <OwnerJoinRequest>[];
      for (final item in current.pending) {
        if (item.id == requestId) {
          moved = item.copyWithStatus(accept ? 'accepted' : 'declined');
        } else {
          pending.add(item);
        }
      }
      final history = [
        if (moved != null) moved,
        ...current.history,
      ];
      state = CommunityJoinRequestsReady(
        pending: pending,
        history: history,
        notice: successNotice,
      );
      if (accept) {
        try {
          await ref.read(communityDetailControllerProvider(_communityId).notifier).load();
        } catch (error) {
          debugPrint(
            '[community] GET /communities/$_communityId after join accept failed '
            'type=${error.runtimeType}',
          );
        }
        try {
          await ref.read(communityListControllerProvider.notifier).load();
        } catch (error) {
          debugPrint(
            '[community] GET /communities after join accept failed type=${error.runtimeType}',
          );
        }
        try {
          await ref.read(sentInvitationsControllerProvider(_communityId).notifier).load();
        } catch (error) {
          debugPrint(
            '[community] GET /communities/invitations after join accept failed '
            'type=${error.runtimeType}',
          );
        }
      }
    } on ApiException catch (error) {
      if (generation != _generation) {
        return;
      }
      debugPrint(
        '[community] POST /communities/$_communityId/join-requests/$requestId/'
        '${accept ? 'accept' : 'decline'} failed '
        'status=${error.statusCode} type=ApiException',
      );
      if (error.statusCode == 404 ||
          (error.statusCode == 400 &&
              (error.message == 'join request is not pending' ||
                  error.message == 'user is already a member' ||
                  error.message == 'Join request not found'))) {
        await load(notice: JoinRequestMessages.fromApi(error));
        return;
      }
      state = CommunityJoinRequestsReady(
        pending: current.pending,
        history: current.history,
        actionError: JoinRequestMessages.fromApi(error),
      );
    } on FormatException {
      if (generation != _generation) {
        return;
      }
      state = CommunityJoinRequestsReady(
        pending: current.pending,
        history: current.history,
        actionError: JoinRequestMessages.genericRetry,
      );
    } finally {
      if (_mutatingId == requestId) {
        _mutatingId = null;
      }
    }
  }
}

final communityJoinRequestsControllerProvider = AutoDisposeNotifierProvider.family<
    CommunityJoinRequestsController, CommunityJoinRequestsState, int>(
  CommunityJoinRequestsController.new,
);
