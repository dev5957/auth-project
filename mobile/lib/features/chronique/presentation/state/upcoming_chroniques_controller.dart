import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/chronique.dart';
import '../../providers/chronique_providers.dart';

sealed class UpcomingChroniquesState {
  const UpcomingChroniquesState();
}

final class UpcomingChroniquesLoading extends UpcomingChroniquesState {
  const UpcomingChroniquesLoading();
}

final class UpcomingChroniquesReady extends UpcomingChroniquesState {
  const UpcomingChroniquesReady(this.items);

  final List<Chronique> items;
}

final class UpcomingChroniquesError extends UpcomingChroniquesState {
  const UpcomingChroniquesError(this.message);

  final String message;
}

/// `GET /chroniques?status=scheduled`. Aucun logout.
class UpcomingChroniquesController extends AutoDisposeNotifier<UpcomingChroniquesState> {
  @override
  UpcomingChroniquesState build() {
    Future<void>.microtask(load);
    return const UpcomingChroniquesLoading();
  }

  Future<void> load({bool keepReadyOnError = false}) async {
    try {
      final page = await ref.read(chroniqueRepositoryProvider).list(
            status: 'scheduled',
          );
      state = UpcomingChroniquesReady(page.items);
    } on ApiException catch (error) {
      debugPrint(
        '[chronique-fil] GET /chroniques?status=scheduled failed '
        'status=${error.statusCode} message=${error.message}',
      );
      if (keepReadyOnError && state is UpcomingChroniquesReady) {
        return;
      }
      final message = error.message.trim();
      state = UpcomingChroniquesError(message.isNotEmpty ? message : 'Unexpected error');
    } on FormatException {
      if (keepReadyOnError && state is UpcomingChroniquesReady) {
        return;
      }
      state = const UpcomingChroniquesError('Unexpected error');
    }
  }

  Future<void> refresh() => load(keepReadyOnError: true);

  void upsert(Chronique chronique) {
    final current = state;
    if (current is! UpcomingChroniquesReady) {
      return;
    }
    if (chronique.status != 'scheduled') {
      removeById(chronique.id);
      return;
    }
    final items = [
      for (final item in current.items)
        if (item.id == chronique.id) chronique else item,
    ];
    final exists = current.items.any((item) => item.id == chronique.id);
    state = UpcomingChroniquesReady(exists ? items : [...items, chronique]);
  }

  void removeById(int id) {
    final current = state;
    if (current is! UpcomingChroniquesReady) {
      return;
    }
    state = UpcomingChroniquesReady([
      for (final item in current.items)
        if (item.id != id) item,
    ]);
  }
}

final upcomingChroniquesControllerProvider = AutoDisposeNotifierProvider<
    UpcomingChroniquesController, UpcomingChroniquesState>(
  UpcomingChroniquesController.new,
);
