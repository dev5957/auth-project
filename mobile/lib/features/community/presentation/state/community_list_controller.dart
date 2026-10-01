import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/community.dart';
import '../../providers/community_providers.dart';

sealed class CommunityListState {
  const CommunityListState();
}

final class CommunityListLoading extends CommunityListState {
  const CommunityListLoading();
}

final class CommunityListReady extends CommunityListState {
  const CommunityListReady(this.items);

  final List<Community> items;
}

final class CommunityListError extends CommunityListState {
  const CommunityListError(this.message, {this.statusCode});

  final String message;
  final int? statusCode;
}

class CommunityListController extends AutoDisposeNotifier<CommunityListState> {
  @override
  CommunityListState build() {
    Future<void>.microtask(load);
    return const CommunityListLoading();
  }

  Future<void> load() async {
    try {
      final items = await ref.read(communityRepositoryProvider).list();
      state = CommunityListReady(items);
    } on ApiException catch (error) {
      debugPrint(
        '[community] GET /communities failed status=${error.statusCode} message=${error.message}',
      );
      state = CommunityListError(
        error.message.trim().isEmpty ? 'Unexpected error' : error.message,
        statusCode: error.statusCode,
      );
    } on FormatException {
      state = const CommunityListError('Unexpected error');
    }
  }
}

final communityListControllerProvider =
    AutoDisposeNotifierProvider<CommunityListController, CommunityListState>(
  CommunityListController.new,
);
