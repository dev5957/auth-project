import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/chronique.dart';
import '../../providers/chronique_providers.dart';

sealed class ExpiredChroniquesState {
  const ExpiredChroniquesState();
}

final class ExpiredChroniquesLoading extends ExpiredChroniquesState {
  const ExpiredChroniquesLoading();
}

final class ExpiredChroniquesReady extends ExpiredChroniquesState {
  const ExpiredChroniquesReady(this.items);

  final List<Chronique> items;
}

final class ExpiredChroniquesError extends ExpiredChroniquesState {
  const ExpiredChroniquesError(this.message);

  final String message;
}

/// `GET /chroniques?status=expired`. Rétention filtrée côté serveur. Aucun logout.
class ExpiredChroniquesController extends AutoDisposeNotifier<ExpiredChroniquesState> {
  @override
  ExpiredChroniquesState build() {
    Future<void>.microtask(load);
    return const ExpiredChroniquesLoading();
  }

  Future<void> load({bool keepReadyOnError = false}) async {
    try {
      final page = await ref.read(chroniqueRepositoryProvider).list(
            status: 'expired',
          );
      state = ExpiredChroniquesReady(page.items);
    } on ApiException catch (error) {
      debugPrint(
        '[chronique-fil] GET /chroniques?status=expired failed '
        'status=${error.statusCode} message=${error.message}',
      );
      if (keepReadyOnError && state is ExpiredChroniquesReady) {
        return;
      }
      final message = error.message.trim();
      state = ExpiredChroniquesError(message.isNotEmpty ? message : 'Unexpected error');
    } on FormatException {
      if (keepReadyOnError && state is ExpiredChroniquesReady) {
        return;
      }
      state = const ExpiredChroniquesError('Unexpected error');
    }
  }

  Future<void> refresh() => load(keepReadyOnError: true);
}

final expiredChroniquesControllerProvider =
    AutoDisposeNotifierProvider<ExpiredChroniquesController, ExpiredChroniquesState>(
  ExpiredChroniquesController.new,
);
