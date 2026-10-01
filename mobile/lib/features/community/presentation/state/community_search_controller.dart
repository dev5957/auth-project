import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/community.dart';
import '../../models/community_fields.dart';
import '../../providers/community_providers.dart';

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
  const CommunitySearchReady(this.items, {this.notice});

  final List<CommunitySearchPreview> items;
  final String? notice;
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
        state = CommunitySearchReady(items);
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
        state = CommunitySearchReady(
          current.items,
          notice: kCommunitySearchPrivateNotice,
        );
        return false;
      }
      if (current is CommunitySearchReady) {
        state = CommunitySearchReady(
          current.items,
          notice: error.statusCode == 401
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
        state = CommunitySearchReady(current.items, notice: 'Unexpected error');
        return false;
      }
      state = const CommunitySearchError('Unexpected error');
      return false;
    }
  }
}

final communitySearchControllerProvider =
    AutoDisposeNotifierProvider<CommunitySearchController, CommunitySearchState>(
  CommunitySearchController.new,
);
