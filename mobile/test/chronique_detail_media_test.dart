import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/auth/data/storage/auth_token_storage.dart';
import 'package:mobile/features/auth/models/auth_account.dart';
import 'package:mobile/features/auth/providers/auth_controller.dart';
import 'package:mobile/features/auth/providers/auth_providers.dart';
import 'package:mobile/features/auth/state/auth_state.dart';
import 'package:mobile/features/chronique/media/chronique_local_file_access.dart';
import 'package:mobile/features/chronique/media/chronique_local_media_picker.dart';
import 'package:mobile/features/chronique/media/chronique_microphone_recorder.dart';
import 'package:mobile/features/chronique/models/chronique.dart';
import 'package:mobile/features/chronique/models/chronique_media_upload.dart';
import 'package:mobile/features/chronique/models/chronique_page.dart';
import 'package:mobile/features/chronique/models/media_draft.dart';
import 'package:mobile/features/chronique/presentation/screens/chronique_detail_screen.dart';
import 'package:mobile/features/chronique/presentation/screens/edit_chronique_screen.dart';
import 'package:mobile/features/chronique/presentation/screens/mon_fil_screen.dart';
import 'package:mobile/features/chronique/presentation/screens/upcoming_chroniques_screen.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_ready_remote_media_list.dart';
import 'package:mobile/features/chronique/providers/chronique_providers.dart';
import 'package:mobile/features/chronique/services/chronique_api_service.dart';
import 'package:mobile/features/chronique/services/chronique_media_upload_client.dart';
import 'package:mobile/features/home/presentation/screens/home_screen.dart';
import 'package:mobile/main.dart';

class InMemoryAuthTokenStorage implements AuthTokenStorage {
  InMemoryAuthTokenStorage({
    String? accessToken,
    String? refreshToken,
  })  : _accessToken = accessToken,
        _refreshToken = refreshToken;

  String? _accessToken;
  String? _refreshToken;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
  }

  @override
  Future<bool> hasRefreshToken() async {
    return _refreshToken != null && _refreshToken!.isNotEmpty;
  }
}

class _SeededHomeAuthController extends AuthController {
  @override
  AuthState build() {
    return const AuthAuthenticated(
      user: AuthAccount(
        id: 1,
        login: 'tgjjk',
        authProvider: 'local',
        email: 'ada@example.com',
        phoneVerified: true,
      ),
    );
  }
}

ChroniqueMedia _readyImage(int id, {int sortOrder = 0, required String name}) {
  return ChroniqueMedia(
    id: id,
    kind: 'image',
    status: 'ready',
    originalFilename: name,
    sortOrder: sortOrder,
    readUrl: 'https://example.test/$name',
  );
}

Chronique _active({
  List<ChroniqueMedia> media = const [],
  Duration publishedAgo = Duration.zero,
}) {
  return Chronique(
    id: 42,
    title: 'Premier soir',
    body: 'Le texte de la chronique, d au moins vingt caracteres.',
    status: 'active',
    publishedAt: DateTime.now().toUtc().subtract(publishedAgo).toIso8601String(),
    media: media,
  );
}

Chronique _scheduled({List<ChroniqueMedia> media = const []}) {
  return Chronique(
    id: 42,
    title: 'Premier soir',
    body: 'Le texte de la chronique, d au moins vingt caracteres.',
    status: 'scheduled',
    scheduledAt: DateTime.now().add(const Duration(hours: 2)),
    media: media,
  );
}

class _ChroniqueApiProbe extends ChroniqueApiService {
  _ChroniqueApiProbe(this.item)
      : super(ApiClient(config: const AppConfig(apiBaseUrl: 'http://test.invalid')));

  Chronique item;
  int listCalls = 0;
  int getCalls = 0;
  int archiveCalls = 0;
  int deleteCalls = 0;
  int createMediaUploadCalls = 0;
  int completeMediaUploadCalls = 0;
  int deleteMediaCalls = 0;
  int reorderMediaCalls = 0;
  int? lastDeleteMediaId;
  List<int>? lastReorderIds;
  String? lastListStatus;
  bool expireOnGet = false;
  ApiException? failCreateMediaUpload;
  ApiException? failCompleteMediaUpload;
  ApiException? failDeleteMedia;
  ApiException? failReorderMedia;
  int _nextMediaId = 200;

  @override
  Future<ChroniquePage> list({
    required String accessToken,
    String? status,
  }) async {
    listCalls += 1;
    lastListStatus = status;
    if (status == 'scheduled') {
      return ChroniquePage(items: item.status == 'scheduled' ? [item] : const []);
    }
    if (status == 'archived') {
      return const ChroniquePage(items: []);
    }
    return ChroniquePage(items: item.status == 'active' ? [item] : const []);
  }

  @override
  Future<Chronique> get({
    required String accessToken,
    required int id,
  }) async {
    getCalls += 1;
    if (expireOnGet) {
      item = item.copyWith(
        publishedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 31)).toIso8601String(),
      );
    }
    if (item.id == id) {
      return item;
    }
    throw const ApiException(message: 'Chronique not found', statusCode: 404);
  }

  @override
  Future<Chronique> archive({
    required String accessToken,
    required int id,
  }) async {
    archiveCalls += 1;
    return item;
  }

  @override
  Future<void> delete({
    required String accessToken,
    required int id,
  }) async {
    deleteCalls += 1;
  }

  @override
  Future<ChroniqueMediaUploadSession> createMediaUpload({
    required String accessToken,
    required int chroniqueId,
    required String kind,
    required String sourceType,
    required String contentType,
    required int byteSize,
    String? originalFilename,
  }) async {
    createMediaUploadCalls += 1;
    final error = failCreateMediaUpload;
    if (error != null) {
      throw error;
    }
    _nextMediaId += 1;
    return ChroniqueMediaUploadSession(
      media: ChroniqueMedia(
        id: _nextMediaId,
        kind: kind,
        originalFilename: originalFilename,
        byteSize: byteSize,
        status: 'pending_upload',
        contentType: contentType,
      ),
      method: 'PUT',
      url: 'https://signed.example/r2/$_nextMediaId',
      headers: const {'Content-Type': 'image/jpeg'},
      expiresAt: '2026-09-24T12:00:00.000Z',
    );
  }

  @override
  Future<Chronique> completeMediaUpload({
    required String accessToken,
    required int chroniqueId,
    required int mediaId,
  }) async {
    completeMediaUploadCalls += 1;
    final error = failCompleteMediaUpload;
    if (error != null) {
      throw error;
    }
    final next = [
      ...item.media,
      _readyImage(mediaId, sortOrder: item.media.length, name: 'nouveau.jpg'),
    ];
    item = item.copyWith(media: next);
    return item;
  }

  @override
  Future<Chronique> deleteMedia({
    required String accessToken,
    required int chroniqueId,
    required int mediaId,
  }) async {
    deleteMediaCalls += 1;
    lastDeleteMediaId = mediaId;
    final error = failDeleteMedia;
    if (error != null) {
      throw error;
    }
    item = item.copyWith(
      media: [for (final media in item.media) if (media.id != mediaId) media],
    );
    return item;
  }

  @override
  Future<Chronique> reorderMedia({
    required String accessToken,
    required int chroniqueId,
    required List<int> mediaIds,
  }) async {
    reorderMediaCalls += 1;
    lastReorderIds = mediaIds;
    final error = failReorderMedia;
    if (error != null) {
      throw error;
    }
    final byId = {for (final media in item.media) media.id: media};
    item = item.copyWith(
      media: [
        for (var i = 0; i < mediaIds.length; i++)
          ChroniqueMedia(
            id: mediaIds[i],
            kind: byId[mediaIds[i]]?.kind ?? 'image',
            status: 'ready',
            originalFilename: byId[mediaIds[i]]?.originalFilename,
            sortOrder: i,
            readUrl: byId[mediaIds[i]]?.readUrl,
          ),
      ],
    );
    return item;
  }
}

class _AlwaysReadableFileAccess implements ChroniqueLocalFileAccess {
  const _AlwaysReadableFileAccess();

  @override
  Future<bool> isReadable(String path) async => path.trim().isNotEmpty;

  @override
  Future<int> lengthOf(String path) async => 2048;

  @override
  Future<void> deleteQuietly(String path, {bool Function()? ifStillUnused}) async {}
}

class _FakeMediaUploadClient extends ChroniqueMediaUploadClient {
  int putCalls = 0;

  @override
  Future<void> putFile({
    required String url,
    required String method,
    required Map<String, String> headers,
    required String localPath,
    required int byteSize,
    ProgressCallback? onSendProgress,
  }) async {
    putCalls += 1;
    onSendProgress?.call(byteSize, byteSize);
  }
}

class _FakeMicrophoneRecorder implements ChroniqueMicrophoneRecorder {
  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<MediaPickResult> stop() async => const MediaPickCancelled();

  @override
  Future<void> discard() async {}

  @override
  void keep() {}

  @override
  Future<void> dispose() async {}
}

class _FakeLocalMediaPicker implements ChroniqueLocalMediaPicker {
  MediaPickResult imageResult = const MediaPickCancelled();

  @override
  Future<MediaPickResult> pickImage({int? limit}) async => imageResult;

  @override
  Future<MediaPickResult> pickImageFromCamera() async => const MediaPickCancelled();

  @override
  Future<MediaPickResult> pickVideo({int? limit}) async => const MediaPickCancelled();

  @override
  Future<MediaPickResult> pickVideoFromCamera() async => const MediaPickCancelled();

  @override
  Future<MediaPickResult> pickAudio() async => const MediaPickCancelled();

  @override
  Future<MediaPickResult> pickDocument({int? limit}) async => const MediaPickCancelled();
}

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  required _ChroniqueApiProbe api,
  _FakeLocalMediaPicker? picker,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authTokenStorageProvider.overrideWithValue(
          InMemoryAuthTokenStorage(
            accessToken: 'access-test',
            refreshToken: 'refresh-test',
          ),
        ),
        authControllerProvider.overrideWith(() => _SeededHomeAuthController()),
        chroniqueApiServiceProvider.overrideWithValue(api),
        chroniqueLocalMediaPickerProvider.overrideWithValue(
          picker ?? _FakeLocalMediaPicker(),
        ),
        chroniqueMicrophoneRecorderProvider.overrideWithValue(_FakeMicrophoneRecorder()),
        chroniqueLocalFileAccessProvider.overrideWithValue(const _AlwaysReadableFileAccess()),
        chroniqueMediaUploadClientProvider.overrideWithValue(_FakeMediaUploadClient()),
      ],
      child: const LuminaApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(LuminaApp)));
}

Future<void> _openActiveDetail(WidgetTester tester) async {
  expect(find.byType(HomeScreen), findsOneWidget);
  await tester.tap(find.text('EXPLORE'));
  await tester.pumpAndSettle();
  expect(find.byType(MonFilScreen), findsOneWidget);
  await tester.tap(find.text('Premier soir').first);
  await tester.pumpAndSettle();
  expect(find.byType(ChroniqueDetailScreen), findsOneWidget);
}

void main() {
  test('quota counts pending and ready only', () {
    expect(
      chroniqueQuotaMediaCount([
        const ChroniqueMedia(kind: 'image', status: 'pending_upload'),
        const ChroniqueMedia(id: 1, kind: 'image', status: 'ready'),
        const ChroniqueMedia(kind: 'image', status: 'failed'),
      ]),
      2,
    );
  });

  testWidgets('active within 30 min shows add delete confirm cancel and reorder', (tester) async {
    final api = _ChroniqueApiProbe(
      _active(
        media: [
          _readyImage(10, name: 'un.jpg'),
          _readyImage(11, sortOrder: 1, name: 'deux.jpg'),
        ],
      ),
    );
    final picker = _FakeLocalMediaPicker()
      ..imageResult = const MediaPickSelected(
        kind: MediaDraftKind.image,
        sourceType: MediaDraftSourceType.gallery,
        fileName: 'nouveau.jpg',
        byteSize: 2048,
        localPath: '/tmp/nouveau.jpg',
        contentType: 'image/jpeg',
      );
    final container = await _pumpHome(tester, api: api, picker: picker);
    await _openActiveDetail(tester);

    expect(find.byKey(const ValueKey('chronique-detail-add-media')), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-media-delete-10')), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-media-delete-11')), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-media-down-10')), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-media-up-11')), findsOneWidget);
    expect(find.byType(ChroniqueReadyRemoteMediaList), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chronique-media-delete-10')));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer ce média ?'), findsOneWidget);
    expect(
      find.text('Cette action supprimera ce média de la Chronique.'),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Annuler')),
    );
    await tester.pumpAndSettle();
    expect(api.deleteMediaCalls, 0);
    expect(find.byKey(const ValueKey('chronique-media-delete-10')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chronique-media-delete-10')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Supprimer')),
    );
    await tester.pumpAndSettle();
    expect(api.deleteMediaCalls, 1);
    expect(api.lastDeleteMediaId, 10);
    expect(find.byKey(const ValueKey('chronique-media-delete-10')), findsNothing);
    expect(find.byKey(const ValueKey('chronique-media-delete-11')), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-media-down-10')), findsNothing);
    expect(find.byKey(const ValueKey('chronique-media-up-11')), findsNothing);

    api.item = _active(
      media: [
        _readyImage(11, name: 'deux.jpg'),
        _readyImage(12, sortOrder: 1, name: 'trois.jpg'),
      ],
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Premier soir').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chronique-media-down-11')));
    await tester.pumpAndSettle();
    expect(api.reorderMediaCalls, 1);
    expect(api.lastReorderIds, [12, 11]);
    expect(find.byKey(const ValueKey('chronique-media-up-11')), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-media-down-12')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chronique-media-up-11')));
    await tester.pumpAndSettle();
    expect(api.reorderMediaCalls, 2);
    expect(api.lastReorderIds, [11, 12]);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galerie (plusieurs)'));
    await tester.pumpAndSettle();
    expect(api.createMediaUploadCalls, 1);
    expect(api.completeMediaUploadCalls, 1);
    expect(find.byKey(const ValueKey('chronique-media-delete-201')), findsOneWidget);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('active after 30 min hides media mutations but keeps archive delete and media', (
    tester,
  ) async {
    final api = _ChroniqueApiProbe(
      _active(
        publishedAgo: const Duration(minutes: 31),
        media: [
          _readyImage(10, name: 'un.jpg'),
          _readyImage(11, sortOrder: 1, name: 'deux.jpg'),
        ],
      ),
    );
    await _pumpHome(tester, api: api);
    await _openActiveDetail(tester);

    expect(find.byType(ChroniqueReadyRemoteMediaList), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-detail-add-media')), findsNothing);
    expect(find.byKey(const ValueKey('chronique-media-delete-10')), findsNothing);
    expect(find.byKey(const ValueKey('chronique-media-up-11')), findsNothing);
    expect(find.byKey(const ValueKey('chronique-media-down-10')), findsNothing);

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Modifier'), findsNothing);
    expect(find.text('Archiver'), findsOneWidget);
    expect(find.text('Supprimer'), findsOneWidget);
  });

  testWidgets('text edit mode hides media mutations then restores them', (tester) async {
    final api = _ChroniqueApiProbe(
      _active(
        media: [
          _readyImage(10, name: 'un.jpg'),
          _readyImage(11, sortOrder: 1, name: 'deux.jpg'),
        ],
      ),
    );
    await _pumpHome(tester, api: api);
    await _openActiveDetail(tester);
    expect(find.byKey(const ValueKey('chronique-detail-add-media')), findsOneWidget);

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();

    expect(find.text('+ Ajouter un média'), findsNothing);
    expect(find.byKey(const ValueKey('chronique-media-delete-10')), findsNothing);
    expect(find.byKey(const ValueKey('chronique-media-down-10')), findsNothing);
    expect(find.byType(ChroniqueReadyRemoteMediaList), findsOneWidget);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chronique-detail-add-media')), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-media-delete-10')), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-media-down-10')), findsOneWidget);
  });

  testWidgets('five ready media hide the add button', (tester) async {
    final api = _ChroniqueApiProbe(
      _active(
        media: [
          for (var i = 0; i < 5; i++) _readyImage(10 + i, sortOrder: i, name: 'm$i.jpg'),
        ],
      ),
    );
    await _pumpHome(tester, api: api);
    await _openActiveDetail(tester);
    expect(find.byKey(const ValueKey('chronique-detail-add-media')), findsNothing);
    expect(find.byKey(const ValueKey('chronique-media-delete-10')), findsOneWidget);
  });

  testWidgets('scheduled media are managed on detail; title date stay on edit screen', (
    tester,
  ) async {
    final api = _ChroniqueApiProbe(
      _scheduled(
        media: [
          _readyImage(10, name: 'un.jpg'),
          _readyImage(11, sortOrder: 1, name: 'deux.jpg'),
        ],
      ),
    );
    await _pumpHome(tester, api: api);
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-user-avatar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🕒 À venir'));
    await tester.pumpAndSettle();
    expect(find.byType(UpcomingChroniquesScreen), findsOneWidget);
    await tester.tap(find.text('Premier soir').first);
    await tester.pumpAndSettle();
    expect(find.byType(ChroniqueDetailScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-detail-add-media')), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-media-delete-10')), findsOneWidget);
    expect(find.byKey(const ValueKey('chronique-media-down-10')), findsOneWidget);

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();
    expect(find.byType(EditChroniqueScreen), findsOneWidget);
    expect(find.text('Date de publication'), findsOneWidget);
    expect(find.text('+ Ajouter un média'), findsNothing);
    expect(find.byKey(const ValueKey('chronique-media-delete-10')), findsNothing);
  });

  testWidgets('409 on media delete shows french message refreshes and stays signed in', (
    tester,
  ) async {
    final api = _ChroniqueApiProbe(
      _active(
        media: [
          _readyImage(10, name: 'un.jpg'),
          _readyImage(11, sortOrder: 1, name: 'deux.jpg'),
        ],
      ),
    )
      ..failDeleteMedia = const ApiException(
        message: 'correction_window_expired',
        statusCode: 409,
      );
    final container = await _pumpHome(tester, api: api);
    await _openActiveDetail(tester);
    api.expireOnGet = true;
    final getsBefore = api.getCalls;

    await tester.tap(find.byKey(const ValueKey('chronique-media-delete-10')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Supprimer')),
    );
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.deleteMediaCalls, 1);
    expect(api.getCalls, greaterThan(getsBefore));
    expect(find.text('correction_window_expired'), findsNothing);
    expect(find.text('La période de modification est terminée.'), findsWidgets);
    expect(find.byKey(const ValueKey('chronique-detail-add-media')), findsNothing);
    expect(find.byKey(const ValueKey('chronique-media-delete-10')), findsNothing);
    expect(find.byType(ChroniqueReadyRemoteMediaList), findsOneWidget);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    expect(find.text('Logout'), findsNothing);
  });

  testWidgets('409 on add shows french message without logout', (tester) async {
    final api = _ChroniqueApiProbe(_active())
      ..failCreateMediaUpload = const ApiException(
        message: 'correction_window_expired',
        statusCode: 409,
      );
    final picker = _FakeLocalMediaPicker()
      ..imageResult = const MediaPickSelected(
        kind: MediaDraftKind.image,
        sourceType: MediaDraftSourceType.gallery,
        fileName: 'nouveau.jpg',
        byteSize: 2048,
        localPath: '/tmp/nouveau.jpg',
        contentType: 'image/jpeg',
      );
    final container = await _pumpHome(tester, api: api, picker: picker);
    await _openActiveDetail(tester);
    api.expireOnGet = true;

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galerie (plusieurs)'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.createMediaUploadCalls, 1);
    expect(api.completeMediaUploadCalls, 0);
    expect(find.text('La période de modification est terminée.'), findsWidgets);
    expect(find.byKey(const ValueKey('chronique-detail-add-media')), findsNothing);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('409 on reorder shows french message without logout', (tester) async {
    final api = _ChroniqueApiProbe(
      _active(
        media: [
          _readyImage(10, name: 'un.jpg'),
          _readyImage(11, sortOrder: 1, name: 'deux.jpg'),
        ],
      ),
    )
      ..failReorderMedia = const ApiException(
        message: 'correction_window_expired',
        statusCode: 409,
      );
    final container = await _pumpHome(tester, api: api);
    await _openActiveDetail(tester);
    api.expireOnGet = true;

    await tester.tap(find.byKey(const ValueKey('chronique-media-down-10')));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.reorderMediaCalls, 1);
    expect(find.text('La période de modification est terminée.'), findsWidgets);
    expect(find.byKey(const ValueKey('chronique-media-down-10')), findsNothing);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });
}
