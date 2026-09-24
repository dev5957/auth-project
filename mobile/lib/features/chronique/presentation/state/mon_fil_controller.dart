import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/chronique.dart';
import '../../providers/chronique_providers.dart';

sealed class MonFilState {
  const MonFilState();
}

final class MonFilLoading extends MonFilState {
  const MonFilLoading();
}

final class MonFilReady extends MonFilState {
  const MonFilReady(this.items);

  final List<Chronique> items;
}

final class MonFilError extends MonFilState {
  const MonFilError(this.message);

  final String message;
}

/// Charge le fil personnel. Aucun logout.
class MonFilController extends AutoDisposeNotifier<MonFilState> {
  @override
  MonFilState build() {
    Future<void>.microtask(load);
    return const MonFilLoading();
  }

  Future<void> load({bool keepReadyOnError = false}) async {
    try {
      final page = await ref.read(chroniqueRepositoryProvider).list();
      state = MonFilReady(page.items);
    } on ApiException catch (error) {
      debugPrint(
        '[chronique-fil] GET /chroniques failed '
        'status=${error.statusCode} message=${error.message}',
      );
      if (keepReadyOnError && state is MonFilReady) {
        return;
      }
      final message = error.message.trim();
      state = MonFilError(message.isNotEmpty ? message : 'Unexpected error');
    } on FormatException {
      if (keepReadyOnError && state is MonFilReady) {
        return;
      }
      state = const MonFilError('Unexpected error');
    }
  }

  Future<void> refresh() => load(keepReadyOnError: true);

  void upsert(Chronique chronique) {
    final current = state;
    if (current is! MonFilReady) {
      return;
    }
    state = MonFilReady([
      for (final item in current.items)
        if (item.id == chronique.id) chronique else item,
    ]);
  }

  void removeById(int id) {
    final current = state;
    if (current is! MonFilReady) {
      return;
    }
    state = MonFilReady([
      for (final item in current.items)
        if (item.id != id) item,
    ]);
  }
}

final monFilControllerProvider =
    AutoDisposeNotifierProvider<MonFilController, MonFilState>(
  MonFilController.new,
);
