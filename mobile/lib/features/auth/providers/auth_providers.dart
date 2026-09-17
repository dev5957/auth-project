import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../data/storage/auth_token_storage.dart';
import '../data/storage/secure_auth_token_storage.dart';
import '../repositories/auth_repository.dart';
import '../services/auth_api_service.dart';

final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});

final authTokenStorageProvider = Provider<AuthTokenStorage>((ref) {
  return SecureAuthTokenStorage();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(config: ref.watch(appConfigProvider));
});

final authApiServiceProvider = Provider<AuthApiService>((ref) {
  return AuthApiService(ref.watch(apiClientProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(authApiServiceProvider),
    tokenStorage: ref.watch(authTokenStorageProvider),
  );
});
