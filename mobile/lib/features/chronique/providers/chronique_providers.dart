import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../media/chronique_local_file_access.dart';
import '../media/chronique_local_media_picker.dart';
import '../media/device_chronique_local_media_picker.dart';
import '../repositories/chronique_repository.dart';
import '../services/chronique_api_service.dart';
import '../services/chronique_media_upload_client.dart';

final chroniqueApiServiceProvider = Provider<ChroniqueApiService>((ref) {
  return ChroniqueApiService(ref.watch(apiClientProvider));
});

final chroniqueRepositoryProvider = Provider<ChroniqueRepository>((ref) {
  return ChroniqueRepository(
    api: ref.watch(chroniqueApiServiceProvider),
    tokenStorage: ref.watch(authTokenStorageProvider),
  );
});

final chroniqueLocalMediaPickerProvider = Provider<ChroniqueLocalMediaPicker>((ref) {
  return DeviceChroniqueLocalMediaPicker();
});

final chroniqueLocalFileAccessProvider = Provider<ChroniqueLocalFileAccess>((ref) {
  return const IoChroniqueLocalFileAccess();
});

final chroniqueMediaUploadClientProvider = Provider<ChroniqueMediaUploadClient>((ref) {
  return ChroniqueMediaUploadClient();
});
