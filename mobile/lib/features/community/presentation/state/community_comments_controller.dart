import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/community_comment.dart';
import '../../providers/community_providers.dart';
import '../../repositories/community_repository.dart';

typedef CommunityCommentsKey = ({int communityId, int publicationId});

sealed class CommunityCommentsState {
  const CommunityCommentsState();
}

final class CommunityCommentsLoading extends CommunityCommentsState {
  const CommunityCommentsLoading();
}

final class CommunityCommentsReady extends CommunityCommentsState {
  const CommunityCommentsReady(this.items, {this.busy = false, this.error});
  final List<CommunityComment> items;
  final bool busy;
  final String? error;
}

final class CommunityCommentsError extends CommunityCommentsState {
  const CommunityCommentsError(this.message);
  final String message;
}

class CommunityCommentsController
    extends AutoDisposeFamilyNotifier<CommunityCommentsState, CommunityCommentsKey> {
  late CommunityCommentsKey _key;

  @override
  CommunityCommentsState build(CommunityCommentsKey key) {
    _key = key;
    Future<void>.microtask(load);
    return const CommunityCommentsLoading();
  }

  Future<void> load() async {
    state = const CommunityCommentsLoading();
    try {
      final page = await ref.read(communityRepositoryProvider).listComments(
            communityId: _key.communityId,
            publicationId: _key.publicationId,
          );
      state = CommunityCommentsReady(page.items);
    } on ApiException catch (error) {
      state = CommunityCommentsError(error.message);
    } catch (_) {
      state = const CommunityCommentsError('Impossible de charger les commentaires');
    }
  }

  Future<bool> create(String body, {int? parentCommentId}) async {
    return _run((repo) async {
      final comment = await repo.createComment(
        communityId: _key.communityId,
        publicationId: _key.publicationId,
        body: body,
        parentCommentId: parentCommentId,
      );
      final current = state;
      if (current is CommunityCommentsReady) {
        state = CommunityCommentsReady(_insertCreated(current.items, comment));
      }
    });
  }

  List<CommunityComment> _insertCreated(List<CommunityComment> items, CommunityComment comment) {
    if (comment.parentCommentId == null) {
      return [comment, ...items];
    }
    final parentId = comment.parentCommentId!;
    var insertAt = -1;
    for (var i = 0; i < items.length; i++) {
      if (items[i].id == parentId || items[i].parentCommentId == parentId) {
        insertAt = i + 1;
      }
    }
    if (insertAt < 0) {
      return [comment, ...items];
    }
    return [
      ...items.take(insertAt),
      comment,
      ...items.skip(insertAt),
    ];
  }

  Future<bool> update(int commentId, String body) async {
    return _run((repo) async {
      final updated = await repo.updateComment(
        communityId: _key.communityId,
        publicationId: _key.publicationId,
        commentId: commentId,
        body: body,
      );
      _replace(updated);
    });
  }

  Future<bool> remove(int commentId) async {
    return _run((repo) async {
      await repo.deleteComment(
        communityId: _key.communityId,
        publicationId: _key.publicationId,
        commentId: commentId,
      );
      await load();
    });
  }

  Future<bool> restore(int commentId) async {
    return _run((repo) async {
      final restored = await repo.restoreComment(
        communityId: _key.communityId,
        publicationId: _key.publicationId,
        commentId: commentId,
      );
      _replace(restored);
    });
  }

  void _replace(CommunityComment updated) {
    final current = state;
    if (current is! CommunityCommentsReady) {
      return;
    }
    state = CommunityCommentsReady([
      for (final item in current.items)
        if (item.id == updated.id) updated else item,
    ]);
  }

  Future<bool> _run(Future<void> Function(CommunityRepository repo) action) async {
    final current = state;
    if (current is CommunityCommentsReady) {
      state = CommunityCommentsReady(current.items, busy: true);
    }
    try {
      await action(ref.read(communityRepositoryProvider));
      return true;
    } on ApiException catch (error) {
      if (current is CommunityCommentsReady) {
        state = CommunityCommentsReady(current.items, error: error.message);
      } else {
        state = CommunityCommentsError(error.message);
      }
      return false;
    } catch (_) {
      if (current is CommunityCommentsReady) {
        state = CommunityCommentsReady(current.items, error: 'Action impossible');
      }
      return false;
    }
  }
}

final communityCommentsControllerProvider = AutoDisposeNotifierProvider.family<
    CommunityCommentsController, CommunityCommentsState, CommunityCommentsKey>(
  CommunityCommentsController.new,
);
