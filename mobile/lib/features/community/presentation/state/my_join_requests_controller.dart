import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/join_request.dart';
import '../../models/join_request_messages.dart';
import '../../providers/community_providers.dart';

sealed class MyJoinRequestsState {
  const MyJoinRequestsState();
}

final class MyJoinRequestsLoading extends MyJoinRequestsState {
  const MyJoinRequestsLoading();
}

final class MyJoinRequestsReady extends MyJoinRequestsState {
  const MyJoinRequestsReady(this.items, {this.notice});

  final List<MyJoinRequest> items;
  final String? notice;
}

final class MyJoinRequestsError extends MyJoinRequestsState {
  const MyJoinRequestsError(this.message, {this.statusCode});

  final String message;
  final int? statusCode;
}

class MyJoinRequestsController extends AutoDisposeNotifier<MyJoinRequestsState> {
  int _generation = 0;

  @override
  MyJoinRequestsState build() {
    Future<void>.microtask(load);
    return const MyJoinRequestsLoading();
  }

  Future<void> load() async {
    final generation = ++_generation;
    state = const MyJoinRequestsLoading();
    try {
      final items = await ref.read(communityRepositoryProvider).listMyJoinRequests();
      if (generation != _generation) {
        return;
      }
      state = MyJoinRequestsReady(items);
    } on ApiException catch (error) {
      if (generation != _generation) {
        return;
      }
      debugPrint(
        '[community] GET /join-requests/mine failed '
        'status=${error.statusCode} type=ApiException',
      );
      state = MyJoinRequestsError(
        JoinRequestMessages.fromApi(error),
        statusCode: error.statusCode,
      );
    } on FormatException {
      if (generation != _generation) {
        return;
      }
      state = const MyJoinRequestsError(JoinRequestMessages.genericRetry);
    }
  }
}

final myJoinRequestsControllerProvider =
    AutoDisposeNotifierProvider<MyJoinRequestsController, MyJoinRequestsState>(
  MyJoinRequestsController.new,
);
