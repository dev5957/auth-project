import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/community_publication.dart';
import 'community_feed_controller.dart';
import 'my_community_publications_controller.dart';
import 'my_favorites_controller.dart';

const kMyCommunityPublicationScopes = <String>['current', 'left', 'expired'];

class CommunityPublicationInteractionPatch {
  const CommunityPublicationInteractionPatch({
    this.likeCount,
    this.likedByMe,
    this.commentCount,
    this.favoriteCount,
    this.favoritedByMe,
  });

  final int? likeCount;
  final bool? likedByMe;
  final int? commentCount;
  final int? favoriteCount;
  final bool? favoritedByMe;

  bool get isEmpty =>
      likeCount == null &&
      likedByMe == null &&
      commentCount == null &&
      favoriteCount == null &&
      favoritedByMe == null;

  CommunityPublicationInteractionPatch merge(CommunityPublicationInteractionPatch other) {
    return CommunityPublicationInteractionPatch(
      likeCount: other.likeCount ?? likeCount,
      likedByMe: other.likedByMe ?? likedByMe,
      commentCount: other.commentCount ?? commentCount,
      favoriteCount: other.favoriteCount ?? favoriteCount,
      favoritedByMe: other.favoritedByMe ?? favoritedByMe,
    );
  }

  CommunityPublication applyTo(CommunityPublication item) {
    return item.copyWith(
      likeCount: likeCount,
      likedByMe: likedByMe,
      commentCount: commentCount,
      favoriteCount: favoriteCount,
      favoritedByMe: favoritedByMe,
    );
  }
}

void storePublicationPatch(
  Map<int, CommunityPublicationInteractionPatch> patches,
  int publicationId,
  CommunityPublicationInteractionPatch incoming,
) {
  if (incoming.isEmpty) {
    return;
  }
  final current = patches[publicationId];
  patches[publicationId] = current == null ? incoming : current.merge(incoming);
}

List<CommunityPublication> mergePublicationPatch(
  List<CommunityPublication> items,
  Map<int, CommunityPublicationInteractionPatch> patches,
) {
  return [
    for (final item in items) patches[item.id]?.applyTo(item) ?? item,
  ];
}

List<CommunityPublication> takePublicationPatches(
  List<CommunityPublication> items,
  Map<int, CommunityPublicationInteractionPatch> patches,
) {
  return [
    for (final item in items) patches.remove(item.id)?.applyTo(item) ?? item,
  ];
}

void syncCommunityPublication(
  WidgetRef ref, {
  required int publicationId,
  required int communityId,
  required CommunityPublicationInteractionPatch patch,
}) {
  if (communityId > 0) {
    final feed = communityFeedControllerProvider(communityId);
    if (ref.exists(feed)) {
      ref.read(feed.notifier).applyPublication(publicationId, patch);
    }
  }
  for (final scope in kMyCommunityPublicationScopes) {
    final mine = myCommunityPublicationsControllerProvider(scope);
    if (ref.exists(mine)) {
      ref.read(mine.notifier).applyPublication(publicationId, patch);
    }
  }
  final favorites = myFavoritesControllerProvider;
  if (ref.exists(favorites)) {
    ref.read(favorites.notifier).applyPublication(publicationId, patch);
  }
}

void syncMyCommunityPublications(
  Ref ref, {
  required int publicationId,
  required CommunityPublicationInteractionPatch patch,
}) {
  for (final scope in kMyCommunityPublicationScopes) {
    final mine = myCommunityPublicationsControllerProvider(scope);
    if (ref.exists(mine)) {
      ref.read(mine.notifier).applyPublication(publicationId, patch);
    }
  }
  final favorites = myFavoritesControllerProvider;
  if (ref.exists(favorites)) {
    ref.read(favorites.notifier).applyPublication(publicationId, patch);
  }
}
