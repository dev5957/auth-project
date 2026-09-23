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

/// Charge le fil personnel. Aucun logout, aucun refresh.
class MonFilController extends AutoDisposeNotifier<MonFilState> {
  @override
  MonFilState build() {
    Future<void>.microtask(load);
    return const MonFilLoading();
  }

  Future<void> load() async {
    try {
      final items = await ref.read(chroniqueRepositoryProvider).list();
      state = MonFilReady(items);
    } on ApiException catch (error) {
      debugPrint(
        '[chronique-fil] GET /chroniques failed '
        'status=${error.statusCode} message=${error.message}',
      );
      final message = error.message.trim();
      state = MonFilError(message.isNotEmpty ? message : 'Unexpected error');
    } on FormatException {
      state = const MonFilError('Unexpected error');
    }
  }
}

final monFilControllerProvider =
    AutoDisposeNotifierProvider<MonFilController, MonFilState>(
  MonFilController.new,
);
