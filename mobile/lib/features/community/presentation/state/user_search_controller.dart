import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/community.dart';
import '../../models/community_fields.dart';
import '../../models/invitation_messages.dart';
import '../../providers/community_providers.dart';

const String kUserSearchSelectedNotice = InvitationMessages.selectedHint;

sealed class UserSearchState {
  const UserSearchState();
}

final class UserSearchIdle extends UserSearchState {
  const UserSearchIdle({this.queryError, this.notice});

  final String? queryError;
  final String? notice;
}

final class UserSearchLoading extends UserSearchState {
  const UserSearchLoading();
}

final class UserSearchReady extends UserSearchState {
  const UserSearchReady(this.hit);

  final UserSearchHit hit;
}

final class UserSearchEmpty extends UserSearchState {
  const UserSearchEmpty();
}

final class UserSearchError extends UserSearchState {
  const UserSearchError(this.message, {this.statusCode});

  final String message;
  final int? statusCode;
}

final class UserSearchSelected extends UserSearchState {
  const UserSearchSelected(this.hit);

  final UserSearchHit hit;
}

final class UserSearchSending extends UserSearchState {
  const UserSearchSending(this.hit);

  final UserSearchHit hit;
}

final class UserSearchSendError extends UserSearchState {
  const UserSearchSendError(this.hit, this.message, {this.statusCode});

  final UserSearchHit hit;
  final String message;
  final int? statusCode;
}

class UserSearchController extends AutoDisposeNotifier<UserSearchState> {
  int _generation = 0;
  int _sendGeneration = 0;
  UserSearchMode _lastMode = UserSearchMode.login;
  String _lastRaw = '';

  @override
  UserSearchState build() => const UserSearchIdle();

  Future<void> submit(UserSearchMode mode, String raw) async {
    if (state is UserSearchSending) {
      return;
    }
    final queryError = UserSearchFields.errorFor(mode, raw);
    if (queryError != null) {
      state = UserSearchIdle(queryError: queryError);
      return;
    }
    _lastMode = mode;
    _lastRaw = raw;
    final generation = ++_generation;
    _sendGeneration += 1;
    state = const UserSearchLoading();
    try {
      final items = await ref.read(communityRepositoryProvider).searchUsers(
            login: mode == UserSearchMode.login ? UserSearchFields.preparedLogin(raw) : null,
            phone: mode == UserSearchMode.phone ? UserSearchFields.preparedPhone(raw) : null,
          );
      if (generation != _generation) {
        return;
      }
      if (items.isEmpty) {
        state = const UserSearchEmpty();
      } else {
        state = UserSearchReady(items.first);
      }
    } on ApiException catch (error) {
      if (generation != _generation) {
        return;
      }
      debugPrint(
        '[community] GET /users/search failed '
        'status=${error.statusCode} type=ApiException',
      );
      state = UserSearchError(
        error.statusCode == 401
            ? 'Session expirée'
            : (error.message.trim().isEmpty ? 'Unexpected error' : error.message),
        statusCode: error.statusCode,
      );
    } on FormatException {
      if (generation != _generation) {
        return;
      }
      state = const UserSearchError('Unexpected error');
    }
  }

  Future<void> retry() {
    return submit(_lastMode, _lastRaw);
  }

  void select(UserSearchHit hit) {
    if (state is! UserSearchReady && state is! UserSearchSelected) {
      return;
    }
    state = UserSearchSelected(hit);
  }

  void clearSelection() {
    final current = state;
    if (current is UserSearchSelected) {
      state = UserSearchReady(current.hit);
      return;
    }
    if (current is UserSearchSendError) {
      state = UserSearchReady(current.hit);
    }
  }

  Future<void> sendInvitation({
    required int communityId,
    required UserSearchHit hit,
  }) async {
    if (state is UserSearchSending) {
      return;
    }
    if (state is! UserSearchSelected && state is! UserSearchSendError) {
      return;
    }
    final sendGeneration = ++_sendGeneration;
    state = UserSearchSending(hit);
    try {
      await ref.read(communityRepositoryProvider).createInvitation(
            communityId: communityId,
            userId: hit.userId,
          );
      if (sendGeneration != _sendGeneration) {
        return;
      }
      state = const UserSearchIdle(notice: InvitationMessages.sent);
    } on ApiException catch (error) {
      if (sendGeneration != _sendGeneration) {
        return;
      }
      debugPrint(
        '[community] POST /communities/invitations failed '
        'status=${error.statusCode} type=ApiException',
      );
      state = UserSearchSendError(
        hit,
        InvitationMessages.fromApi(error),
        statusCode: error.statusCode,
      );
    } on FormatException {
      if (sendGeneration != _sendGeneration) {
        return;
      }
      state = UserSearchSendError(hit, InvitationMessages.genericRetry);
    }
  }
}

final userSearchControllerProvider =
    AutoDisposeNotifierProvider<UserSearchController, UserSearchState>(
  UserSearchController.new,
);
