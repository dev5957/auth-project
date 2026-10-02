import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/community.dart';
import '../../models/invitation_messages.dart';
import '../../providers/community_providers.dart';
import 'community_list_controller.dart';

sealed class InvitationInboxState {
  const InvitationInboxState();
}

final class InvitationInboxLoading extends InvitationInboxState {
  const InvitationInboxLoading();
}

final class InvitationInboxReady extends InvitationInboxState {
  const InvitationInboxReady(
    this.items, {
    this.mutatingId,
    this.notice,
    this.actionError,
  });

  final List<ReceivedCommunityInvitation> items;
  final int? mutatingId;
  final String? notice;
  final String? actionError;
}

final class InvitationInboxError extends InvitationInboxState {
  const InvitationInboxError(this.message, {this.statusCode});

  final String message;
  final int? statusCode;
}

class InvitationInboxController extends AutoDisposeNotifier<InvitationInboxState> {
  int _generation = 0;
  int? _mutatingId;

  @override
  InvitationInboxState build() {
    Future<void>.microtask(load);
    return const InvitationInboxLoading();
  }

  Future<void> load() async {
    final generation = ++_generation;
    _mutatingId = null;
    state = const InvitationInboxLoading();
    try {
      final items = await ref.read(communityRepositoryProvider).listInvitations();
      if (generation != _generation) {
        return;
      }
      state = InvitationInboxReady(items);
    } on ApiException catch (error) {
      if (generation != _generation) {
        return;
      }
      debugPrint(
        '[community] GET /invitations failed '
        'status=${error.statusCode} type=ApiException',
      );
      state = InvitationInboxError(
        InvitationMessages.fromApi(error),
        statusCode: error.statusCode,
      );
    } on FormatException {
      if (generation != _generation) {
        return;
      }
      state = const InvitationInboxError(InvitationMessages.genericRetry);
    }
  }

  Future<void> accept(int invitationId) {
    return _mutate(
      invitationId,
      accept: true,
      action: () => ref.read(communityRepositoryProvider).acceptInvitation(invitationId),
      successNotice: InvitationMessages.accepted,
    );
  }

  Future<void> decline(int invitationId) {
    return _mutate(
      invitationId,
      accept: false,
      action: () => ref.read(communityRepositoryProvider).declineInvitation(invitationId),
      successNotice: InvitationMessages.declined,
    );
  }

  Future<void> _mutate(
    int invitationId, {
    required bool accept,
    required Future<void> Function() action,
    required String successNotice,
  }) async {
    final current = state;
    if (current is! InvitationInboxReady) {
      return;
    }
    if (_mutatingId != null) {
      return;
    }
    _mutatingId = invitationId;
    final generation = _generation;
    state = InvitationInboxReady(
      current.items,
      mutatingId: invitationId,
    );
    try {
      await action();
      if (generation != _generation) {
        return;
      }
      final remaining = current.items.where((item) => item.id != invitationId).toList();
      state = InvitationInboxReady(
        remaining,
        notice: successNotice,
      );
      if (accept) {
        try {
          await ref.read(communityListControllerProvider.notifier).load();
        } catch (error) {
          debugPrint(
            '[community] GET /communities after accept failed type=${error.runtimeType}',
          );
        }
      }
    } on ApiException catch (error) {
      if (generation != _generation) {
        return;
      }
      debugPrint(
        '[community] POST /invitations/${accept ? 'accept' : 'decline'} failed '
        'status=${error.statusCode} type=ApiException',
      );
      if (error.statusCode == 404) {
        await load();
        final afterLoad = state;
        if (afterLoad is InvitationInboxReady) {
          state = InvitationInboxReady(
            afterLoad.items,
            notice: InvitationMessages.unavailable,
          );
        }
        return;
      }
      state = InvitationInboxReady(
        current.items,
        actionError: InvitationMessages.fromApi(error),
      );
    } on FormatException {
      if (generation != _generation) {
        return;
      }
      state = InvitationInboxReady(
        current.items,
        actionError: InvitationMessages.genericRetry,
      );
    } finally {
      if (_mutatingId == invitationId) {
        _mutatingId = null;
      }
    }
  }
}

final invitationInboxControllerProvider =
    AutoDisposeNotifierProvider<InvitationInboxController, InvitationInboxState>(
  InvitationInboxController.new,
);
