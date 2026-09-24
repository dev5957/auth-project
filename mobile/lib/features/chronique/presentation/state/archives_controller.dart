import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/chronique.dart';
import '../../providers/chronique_providers.dart';

sealed class ArchivesState {
  const ArchivesState();
}

final class ArchivesLoading extends ArchivesState {
  const ArchivesLoading();
}

final class ArchivesReady extends ArchivesState {
  const ArchivesReady(this.items);

  final List<Chronique> items;
}

final class ArchivesError extends ArchivesState {
  const ArchivesError(this.message);

  final String message;
}

/// `GET /chroniques?status=archived`. Aucun logout.
class ArchivesController extends AutoDisposeNotifier<ArchivesState> {
  @override
  ArchivesState build() {
    Future<void>.microtask(load);
    return const ArchivesLoading();
  }

  Future<void> load({bool keepReadyOnError = false}) async {
    try {
      final page = await ref.read(chroniqueRepositoryProvider).list(
            status: 'archived',
          );
      state = ArchivesReady(page.items);
    } on ApiException catch (error) {
      debugPrint(
        '[chronique-fil] GET /chroniques?status=archived failed '
        'status=${error.statusCode} message=${error.message}',
      );
      if (keepReadyOnError && state is ArchivesReady) {
        return;
      }
      final message = error.message.trim();
      state = ArchivesError(message.isNotEmpty ? message : 'Unexpected error');
    } on FormatException {
      if (keepReadyOnError && state is ArchivesReady) {
        return;
      }
      state = const ArchivesError('Unexpected error');
    }
  }

  Future<void> refresh() => load(keepReadyOnError: true);
}

final archivesControllerProvider =
    AutoDisposeNotifierProvider<ArchivesController, ArchivesState>(
  ArchivesController.new,
);
