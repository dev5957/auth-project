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
  }) {
    return ref.read(chroniqueRepositoryProvider).update(
          id: id,
          body: body,
          title: title,
        );
  }
}

final editChroniqueControllerProvider =
    AutoDisposeNotifierProvider<EditChroniqueController, void>(
  EditChroniqueController.new,
);
