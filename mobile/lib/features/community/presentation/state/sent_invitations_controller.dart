import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/community.dart';
import '../../models/invitation_messages.dart';
import '../../providers/community_providers.dart';

sealed class SentInvitationsState {
  const SentInvitationsState();
}

final class SentInvitationsLoading extends SentInvitationsState {
  const SentInvitationsLoading();
}

final class SentInvitationsReady extends SentInvitationsState {
  const SentInvitationsReady(this.items);

  final List<SentCommunityInvitation> items;
}

final class SentInvitationsError extends SentInvitationsState {
  const SentInvitationsError(this.message, {this.statusCode});

  final String message;
  final int? statusCode;
}

class SentInvitationsController extends AutoDisposeFamilyNotifier<SentInvitationsState, int> {
  late int _communityId;
  int _generation = 0;

  @override
  SentInvitationsState build(int communityId) {
    _communityId = communityId;
    Future<void>.microtask(load);
    return const SentInvitationsLoading();
  }

  Future<void> load() async {
    final communityId = _communityId;
    final generation = ++_generation;
    state = const SentInvitationsLoading();
    try {
      final items = await ref.read(communityRepositoryProvider).listSentInvitations(communityId);
      if (generation != _generation) {
        return;
      }
      state = SentInvitationsReady(items);
    } on ApiException catch (error) {
      if (generation != _generation) {
        return;
      }
      debugPrint(
        '[community] GET /communities/invitations failed '
        'status=${error.statusCode} type=ApiException',
      );
      state = SentInvitationsError(
        InvitationMessages.fromApi(error),
        statusCode: error.statusCode,
      );
    } on FormatException {
      if (generation != _generation) {
        return;
      }
      state = const SentInvitationsError(InvitationMessages.genericRetry);
    }
  }
}

final sentInvitationsControllerProvider = AutoDisposeNotifierProvider.family<
    SentInvitationsController, SentInvitationsState, int>(
  SentInvitationsController.new,
);
