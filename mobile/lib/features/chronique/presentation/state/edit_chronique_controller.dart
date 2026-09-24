import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chronique.dart';
import '../../providers/chronique_providers.dart';

/// PATCH titre/corps d’une chronique existante. Pas de médias.
class EditChroniqueController extends AutoDisposeNotifier<void> {
  @override
  void build() {}

  Future<Chronique> save({
    required int id,
    required String body,
    String? title,
    String? publish,
    String? scheduledAt,
    bool? isTimeLimited,
    String? expiresAt,
  }) {
    return ref.read(chroniqueRepositoryProvider).update(
          id: id,
          body: body,
          title: title,
          publish: publish,
          scheduledAt: scheduledAt,
          isTimeLimited: isTimeLimited,
          expiresAt: expiresAt,
        );
  }
}

final editChroniqueControllerProvider =
    AutoDisposeNotifierProvider<EditChroniqueController, void>(
  EditChroniqueController.new,
);
