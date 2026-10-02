import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/community.dart';
import '../../models/community_fields.dart';
import '../../providers/community_providers.dart';

const String kUserSearchSelectedNotice =
    'Utilisateur sélectionné. L’envoi des invitations sera disponible dans une prochaine étape.';

sealed class UserSearchState {
  const UserSearchState();
}

final class UserSearchIdle extends UserSearchState {
  const UserSearchIdle({this.queryError});

  final String? queryError;
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

class UserSearchController extends AutoDisposeNotifier<UserSearchState> {
  int _generation = 0;
  UserSearchMode _lastMode = UserSearchMode.login;
  String _lastRaw = '';

  @override
  UserSearchState build() => const UserSearchIdle();

  Future<void> submit(UserSearchMode mode, String raw) async {
    final queryError = UserSearchFields.errorFor(mode, raw);
    if (queryError != null) {
      state = UserSearchIdle(queryError: queryError);
      return;
    }
    _lastMode = mode;
    _lastRaw = raw;
    final generation = ++_generation;
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
}

final userSearchControllerProvider =
    AutoDisposeNotifierProvider<UserSearchController, UserSearchState>(
  UserSearchController.new,
);
