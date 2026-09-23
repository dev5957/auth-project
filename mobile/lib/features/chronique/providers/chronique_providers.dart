import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../repositories/chronique_repository.dart';
import '../services/chronique_api_service.dart';

final chroniqueApiServiceProvider = Provider<ChroniqueApiService>((ref) {
  return ChroniqueApiService(ref.watch(apiClientProvider));
});

final chroniqueRepositoryProvider = Provider<ChroniqueRepository>((ref) {
  return ChroniqueRepository(
    api: ref.watch(chroniqueApiServiceProvider),
    tokenStorage: ref.watch(authTokenStorageProvider),
  );
});
