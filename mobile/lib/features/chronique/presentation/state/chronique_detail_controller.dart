import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chronique.dart';
import '../../providers/chronique_providers.dart';

/// Actions du détail (archivage). Pas de logout.
class ChroniqueDetailController extends AutoDisposeNotifier<void> {
  @override
  void build() {}

  Future<Chronique> archive(int id) {
    return ref.read(chroniqueRepositoryProvider).archive(id);
  }
}

final chroniqueDetailControllerProvider =
    AutoDisposeNotifierProvider<ChroniqueDetailController, void>(
  ChroniqueDetailController.new,
);
