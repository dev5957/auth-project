import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/community_publication.dart';
import '../../providers/community_providers.dart';

sealed class CommunityFeedState {
  const CommunityFeedState();
}

final class CommunityFeedLoading extends CommunityFeedState {
  const CommunityFeedLoading();
}

final class CommunityFeedReady extends CommunityFeedState {
  const CommunityFeedReady(this.items);
  final List<CommunityPublication> items;
}

final class CommunityFeedError extends CommunityFeedState {
  const CommunityFeedError(this.message);
  final String message;
}

class CommunityFeedController extends AutoDisposeFamilyNotifier<CommunityFeedState, int> {
  late int _communityId;

  @override
  CommunityFeedState build(int communityId) {
    _communityId = communityId;
    Future<void>.microtask(load);
    return const CommunityFeedLoading();
  }

  Future<void> load() async {
    final id = _communityId;
    state = const CommunityFeedLoading();
    try {
      final page = await ref.read(communityRepositoryProvider).listPublications(id);
      state = CommunityFeedReady(page.items);
    } on ApiException catch (error) {
      state = CommunityFeedError(error.message);
    } catch (_) {
      state = const CommunityFeedError('Impossible de charger les publications');
    }
  }

  void applyPublication(CommunityPublication updated) {
    final current = state;
    if (current is! CommunityFeedReady) {
      return;
    }
    state = CommunityFeedReady([
      for (final item in current.items)
        if (item.id == updated.id) updated else item,
    ]);
  }

  Future<void> toggleLike(CommunityPublication item) async {
    try {
      final result = item.likedByMe
          ? await ref.read(communityRepositoryProvider).unlikePublication(
                communityId: item.communityId,
                publicationId: item.id,
              )
          : await ref.read(communityRepositoryProvider).likePublication(
                communityId: item.communityId,
                publicationId: item.id,
              );
      applyPublication(
        item.copyWith(likedByMe: result.likedByMe, likeCount: result.likeCount),
      );
    } catch (_) {
      // Keep the current counters; the next feed load reconciles.
    }
  }
}

final communityFeedControllerProvider =
    AutoDisposeNotifierProvider.family<CommunityFeedController, CommunityFeedState, int>(
  CommunityFeedController.new,
);
