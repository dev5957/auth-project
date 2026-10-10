import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../chronique/models/chronique_page.dart';
import '../../models/community_publication.dart';
import '../../providers/community_providers.dart';
import 'community_feed_controller.dart';
import 'community_publication_sync.dart';

sealed class MyFavoritesState {
  const MyFavoritesState();
}

final class MyFavoritesLoading extends MyFavoritesState {
  const MyFavoritesLoading();
}

final class MyFavoritesReady extends MyFavoritesState {
  const MyFavoritesReady(this.items, {this.next, this.loadingMore = false});

  final List<CommunityPublication> items;
  final ChroniqueCursor? next;
  final bool loadingMore;
}

final class MyFavoritesError extends MyFavoritesState {
  const MyFavoritesError(this.message);
  final String message;
}

class MyFavoritesController extends AutoDisposeNotifier<MyFavoritesState> {
  final Map<int, CommunityPublicationInteractionPatch> _patches =
      <int, CommunityPublicationInteractionPatch>{};
  final Set<int> _favoriteInFlight = <int>{};
  final Set<int> _likeInFlight = <int>{};
  ChroniqueCursor? _next;

  @override
  MyFavoritesState build() {
    Future<void>.microtask(load);
    return const MyFavoritesLoading();
  }

  Future<void> load() async {
    state = const MyFavoritesLoading();
    try {
      final page = await ref.read(communityRepositoryProvider).listMyFavorites();
      _next = page.next;
      state = MyFavoritesReady(takePublicationPatches(page.items, _patches), next: page.next);
    } on ApiException catch (error) {
      state = MyFavoritesError(error.message);
    } catch (_) {
      state = const MyFavoritesError('Impossible de charger vos favoris');
    }
  }

  Future<void> loadMore() async {
    final current = state;
    final cursor = _next;
    if (current is! MyFavoritesReady || cursor == null || current.loadingMore) {
      return;
    }
    state = MyFavoritesReady(current.items, next: cursor, loadingMore: true);
    try {
      final page = await ref.read(communityRepositoryProvider).listMyFavorites(
            beforeAt: cursor.beforeAt,
            beforeId: cursor.beforeId,
          );
      final seen = <int>{for (final item in current.items) item.id};
      final appended = [
        for (final item in takePublicationPatches(page.items, _patches))
          if (seen.add(item.id)) item,
      ];
      _next = page.next;
      state = MyFavoritesReady([...current.items, ...appended], next: page.next);
    } on ApiException catch (error) {
      state = MyFavoritesError(error.message);
    } catch (_) {
      state = const MyFavoritesError('Impossible de charger vos favoris');
    }
  }

  void applyPublication(int publicationId, CommunityPublicationInteractionPatch patch) {
    storePublicationPatch(_patches, publicationId, patch);
    final current = state;
    if (current is! MyFavoritesReady) {
      return;
    }
    var items = mergePublicationPatch(current.items, _patches);
    if (patch.favoritedByMe == false) {
      items = [for (final item in items) if (item.id != publicationId) item];
    }
    state = MyFavoritesReady(items, next: current.next, loadingMore: current.loadingMore);
  }

  CommunityPublication _sourceFor(CommunityPublication item) {
    final current = state;
    if (current is MyFavoritesReady) {
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
    final current = _sourceFor(item);
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
      if (current.communityId > 0) {
        final feed = communityFeedControllerProvider(current.communityId);
        if (ref.exists(feed)) {
          ref.read(feed.notifier).applyPublication(current.id, patch);
        }
      }
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

  Future<bool> toggleFavorite(CommunityPublication item) async {
    if (!_favoriteInFlight.add(item.id)) {
      return true;
    }
    final current = _sourceFor(item);
    try {
      final result = current.favoritedByMe
          ? await ref.read(communityRepositoryProvider).unfavoritePublication(
                communityId: current.communityId,
                publicationId: current.id,
              )
          : await ref.read(communityRepositoryProvider).favoritePublication(
                communityId: current.communityId,
                publicationId: current.id,
              );
      final patch = CommunityPublicationInteractionPatch(
        favoritedByMe: result.favoritedByMe,
        favoriteCount: result.favoriteCount,
      );
      applyPublication(current.id, patch);
      if (current.communityId > 0) {
        final feed = communityFeedControllerProvider(current.communityId);
        if (ref.exists(feed)) {
          ref.read(feed.notifier).applyPublication(current.id, patch);
        }
      }
      syncMyCommunityPublications(ref, publicationId: current.id, patch: patch);
      return true;
    } on ApiException {
      return false;
    } catch (_) {
      return false;
    } finally {
      _favoriteInFlight.remove(item.id);
    }
  }
}

final myFavoritesControllerProvider =
    AutoDisposeNotifierProvider<MyFavoritesController, MyFavoritesState>(MyFavoritesController.new);
