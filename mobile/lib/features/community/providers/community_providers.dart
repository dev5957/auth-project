import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../repositories/community_repository.dart';
import '../services/community_api_service.dart';

final communityApiServiceProvider = Provider<CommunityApiService>((ref) {
  return CommunityApiService(ref.watch(apiClientProvider));
});

final communityRepositoryProvider = Provider<CommunityRepository>((ref) {
  return CommunityRepository(
    api: ref.watch(communityApiServiceProvider),
    tokenStorage: ref.watch(authTokenStorageProvider),
  );
});
