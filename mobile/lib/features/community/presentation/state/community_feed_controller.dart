import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/community_publication.dart';
import '../../providers/community_providers.dart';
import 'community_publication_sync.dart';

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
  final Map<int, CommunityPublicationInteractionPatch> _patches =
      <int, CommunityPublicationInteractionPatch>{};
  final Set<int> _likeInFlight = <int>{};

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
      state = CommunityFeedReady(takePublicationPatches(page.items, _patches));
    } on ApiException catch (error) {
      state = CommunityFeedError(error.message);
    } catch (_) {
      state = const CommunityFeedError('Impossible de charger les publications');
    }
  }

  void applyPublication(int publicationId, CommunityPublicationInteractionPatch patch) {
    storePublicationPatch(_patches, publicationId, patch);
    final current = state;
    if (current is! CommunityFeedReady) {
      return;
    }
    state = CommunityFeedReady(mergePublicationPatch(current.items, _patches));
  }

  CommunityPublication _sourceForLike(CommunityPublication item) {
    final current = state;
    if (current is CommunityFeedReady) {
      for (final candidate in current.items) {
        if (candidate.id == item.id) {
          return candidate;
        }
      }
    }
    return item;
  }

  Future<bool> toggleLike(CommunityPublication item) async {
    if (!_likeInFlight.add(item.id)) {
      return true;
    }
    final current = _sourceForLike(item);
    try {
      final result = current.likedByMe
          ? await ref.read(communityRepositoryProvider).unlikePublication(
                communityId: current.communityId,
                publicationId: current.id,
              )
          : await ref.read(communityRepositoryProvider).likePublication(
                communityId: current.communityId,
                publicationId: current.id,
              );
      final patch = CommunityPublicationInteractionPatch(
        likedByMe: result.likedByMe,
        likeCount: result.likeCount,
      );
      applyPublication(current.id, patch);
      syncMyCommunityPublications(ref, publicationId: current.id, patch: patch);
      return true;
    } on ApiException {
      return false;
    } catch (_) {
      return false;
    } finally {
      _likeInFlight.remove(item.id);
    }
  }
}

final communityFeedControllerProvider =
    AutoDisposeNotifierProvider.family<CommunityFeedController, CommunityFeedState, int>(
  CommunityFeedController.new,
);
