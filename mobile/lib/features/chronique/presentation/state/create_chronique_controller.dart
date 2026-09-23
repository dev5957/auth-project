import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chronique.dart';
import '../../providers/chronique_providers.dart';

/// Brouillon local de l’assistant de création (prêt pour des étapes futures).
class CreateChroniqueFormData {
  const CreateChroniqueFormData({
    this.title = '',
    this.body = '',
  });

  final String title;
  final String body;
}

class CreateChroniqueController extends AutoDisposeNotifier<CreateChroniqueFormData> {
  @override
  CreateChroniqueFormData build() => const CreateChroniqueFormData();

  void saveDraft({String? title, String? body}) {
    state = CreateChroniqueFormData(
      title: title ?? state.title,
      body: body ?? state.body,
    );
  }

  /// `POST /chroniques` immédiat. La validation UI reste dans l’écran.
  Future<Chronique> publish({
    required String body,
    String? title,
  }) {
    return ref.read(chroniqueRepositoryProvider).create(
          body: body,
          title: title,
        );
  }
}

final createChroniqueControllerProvider =
    AutoDisposeNotifierProvider<CreateChroniqueController, CreateChroniqueFormData>(
  CreateChroniqueController.new,
);
