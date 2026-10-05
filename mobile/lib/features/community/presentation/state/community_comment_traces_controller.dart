import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/community_comment.dart';
import '../../providers/community_providers.dart';

sealed class CommunityCommentTracesState {
  const CommunityCommentTracesState();
}

final class CommunityCommentTracesLoading extends CommunityCommentTracesState {
  const CommunityCommentTracesLoading();
}

final class CommunityCommentTracesReady extends CommunityCommentTracesState {
  const CommunityCommentTracesReady(this.items);
  final List<CommunityCommentTrace> items;
}

final class CommunityCommentTracesError extends CommunityCommentTracesState {
  const CommunityCommentTracesError(this.message);
  final String message;
}

class CommunityCommentTracesController extends AutoDisposeNotifier<CommunityCommentTracesState> {
  @override
  CommunityCommentTracesState build() {
    Future<void>.microtask(load);
    return const CommunityCommentTracesLoading();
  }

  Future<void> load() async {
    state = const CommunityCommentTracesLoading();
    try {
      final page = await ref.read(communityRepositoryProvider).listMyCommentTraces();
      state = CommunityCommentTracesReady(page.items);
    } on ApiException catch (error) {
      state = CommunityCommentTracesError(error.message);
    } catch (_) {
      state = const CommunityCommentTracesError('Impossible de charger les traces');
    }
  }
}

final communityCommentTracesControllerProvider =
    AutoDisposeNotifierProvider<CommunityCommentTracesController, CommunityCommentTracesState>(
  CommunityCommentTracesController.new,
);
