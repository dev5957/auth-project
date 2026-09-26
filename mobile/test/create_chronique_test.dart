import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/widgets/app_button.dart';
import 'package:mobile/features/auth/data/storage/auth_token_storage.dart';
import 'package:mobile/features/auth/models/auth_account.dart';
import 'package:mobile/features/auth/providers/auth_controller.dart';
import 'package:mobile/features/auth/providers/auth_providers.dart';
import 'package:mobile/features/auth/state/auth_state.dart';
import 'package:mobile/features/chronique/media/chronique_local_file_access.dart';
import 'package:mobile/features/chronique/media/chronique_local_media_picker.dart';
import 'package:mobile/features/chronique/media/chronique_media_limits.dart';
import 'package:mobile/features/chronique/media/chronique_microphone_recorder.dart';
import 'package:mobile/features/chronique/models/chronique.dart';
import 'package:mobile/features/chronique/models/chronique_assistant_copy.dart';
import 'package:mobile/features/chronique/models/chronique_date.dart';
import 'package:mobile/features/chronique/models/chronique_media_upload.dart';
import 'package:mobile/features/chronique/models/chronique_page.dart';
import 'package:mobile/features/chronique/models/chronique_schedule_draft.dart';
import 'package:mobile/features/chronique/models/media_draft.dart';
import 'package:mobile/features/chronique/presentation/screens/create_chronique_screen.dart';
import 'package:mobile/features/chronique/presentation/screens/upcoming_chroniques_screen.dart';
import 'package:mobile/features/chronique/presentation/state/create_chronique_controller.dart';
import 'package:mobile/features/chronique/presentation/widgets/media_draft_list.dart';
import 'package:mobile/features/chronique/presentation/screens/mon_fil_screen.dart';
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

class _ChroniqueApiProbe extends ChroniqueApiService {
  _ChroniqueApiProbe()
      : super(ApiClient(config: const AppConfig(apiBaseUrl: 'http://test.invalid')));

  int createCalls = 0;
  int listCalls = 0;
  int createMediaUploadCalls = 0;
  int completeMediaUploadCalls = 0;
  String? lastAccessToken;
  String? lastBody;
  String? lastTitle;
  String? lastPublish;
  String? lastScheduledAt;
  String? lastListStatus;
  bool? lastIsTimeLimited;
  String? lastExpiresAt;
  Map<String, dynamic>? lastCreateData;
  Map<String, dynamic>? lastUploadPayload;
  ApiException? failWith;
  ApiException? failCreateMediaUpload;
  ApiException? failCompleteMediaUpload;
  List<Chronique> listItems = const [];
  int _nextMediaId = 100;

  @override
  Future<Chronique> create({
    required String accessToken,
    required String body,
    String? title,
    String publish = 'now',
    String? scheduledAt,
    bool isTimeLimited = false,
    String? expiresAt,
  }) async {
    createCalls += 1;
    lastAccessToken = accessToken;
    lastBody = body;
    lastTitle = title;
    lastPublish = publish;
    lastScheduledAt = scheduledAt;
    lastIsTimeLimited = isTimeLimited;
    lastExpiresAt = expiresAt;
    lastCreateData = <String, dynamic>{
      'body': body,
      'publish': publish,
      if (title != null && title.isNotEmpty) 'title': title,
      if (publish == 'schedule' && scheduledAt != null) 'scheduled_at': scheduledAt,
      if (isTimeLimited) 'is_time_limited': true,
      if (isTimeLimited && expiresAt != null) 'expires_at': expiresAt,
    };
    final error = failWith;
    if (error != null) {
      throw error;
    }
    return Chronique(
      id: 42,
      title: title,
      body: body,
      status: publish == 'schedule' ? 'scheduled' : 'active',
      publishedAt: publish == 'schedule' ? null : '2026-09-23T12:00:00.000Z',
      scheduledAt: scheduledAt == null ? null : DateTime.tryParse(scheduledAt),
      isTimeLimited: isTimeLimited,
      expiresAt: expiresAt == null ? null : DateTime.tryParse(expiresAt),
    );
  }

  @override
  Future<ChroniquePage> list({
    required String accessToken,
    String? status,
  }) async {
    listCalls += 1;
    lastAccessToken = accessToken;
    lastListStatus = status;
    return ChroniquePage(items: listItems);
  }

  @override
  Future<Chronique> get({
    required String accessToken,
    required int id,
  }) async {
    lastAccessToken = accessToken;
    for (final item in listItems) {
      if (item.id == id) {
        return item;
      }
    }
    throw const ApiException(message: 'Chronique not found', statusCode: 404);
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
    lastAccessToken = accessToken;
    lastUploadPayload = <String, dynamic>{
      'kind': kind,
      'source_type': sourceType,
      'content_type': contentType,
      'byte_size': byteSize,
      'original_filename': originalFilename,
    };
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
    lastAccessToken = accessToken;
    final error = failCompleteMediaUpload;
    if (error != null) {
      throw error;
    }
    return Chronique(
      id: chroniqueId,
      body: lastBody ?? '',
      status: lastPublish == 'schedule' ? 'scheduled' : 'active',
      media: [
        ChroniqueMedia(
          id: mediaId,
          kind: 'image',
          status: 'ready',
        ),
      ],
    );
  }
}

class _AlwaysReadableFileAccess implements ChroniqueLocalFileAccess {
  const _AlwaysReadableFileAccess();

  @override
  Future<bool> isReadable(String path) async => path.trim().isNotEmpty;

  @override
  Future<int> lengthOf(String path) async => 2048;
}

class _FakeMediaUploadClient extends ChroniqueMediaUploadClient {
  int putCalls = 0;
  final List<String> urls = [];
  bool sentAuthorization = false;

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
    urls.add(url);
    if (headers.keys.any((key) => key.toLowerCase() == 'authorization')) {
      sentAuthorization = true;
    }
    onSendProgress?.call(byteSize, byteSize);
  }
}

class _FakeMicrophoneRecorder implements ChroniqueMicrophoneRecorder {
  bool permissionGranted = true;
  MediaPickResult stopResult = const MediaPickSelected(
    kind: MediaDraftKind.audio,
    sourceType: MediaDraftSourceType.microphone,
    fileName: 'mic.m4a',
    byteSize: 2048,
    localPath: '/tmp/mic.m4a',
    contentType: 'audio/mp4',
  );
  int startCalls = 0;
  int discardCalls = 0;

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<void> start() async {
    startCalls += 1;
  }

  @override
  Future<MediaPickResult> stop() async => stopResult;

  @override
  Future<void> discard() async {
    discardCalls += 1;
  }

  @override
  void keep() {}

  @override
  Future<void> dispose() async {}
}

class _FakeLocalMediaPicker implements ChroniqueLocalMediaPicker {
  MediaPickResult imageResult = const MediaPickCancelled();
  List<MediaPickSelected>? imageResults;
  MediaPickResult cameraImageResult = const MediaPickCancelled();
  MediaPickResult videoResult = const MediaPickCancelled();
  List<MediaPickSelected>? videoResults;
  MediaPickResult cameraVideoResult = const MediaPickCancelled();
  MediaPickResult audioResult = const MediaPickCancelled();
  MediaPickResult documentResult = const MediaPickCancelled();
  List<MediaPickSelected>? documentResults;

  @override
  Future<MediaPickResult> pickImage({int? limit}) async {
    if (imageResults != null) {
      if (imageResults!.isEmpty) {
        return const MediaPickCancelled();
      }
      return MediaPickMany(imageResults!);
    }
    return imageResult;
  }

  @override
  Future<MediaPickResult> pickImageFromCamera() async => cameraImageResult;

  @override
  Future<MediaPickResult> pickVideo({int? limit}) async {
    if (videoResults != null) {
      if (videoResults!.isEmpty) {
        return const MediaPickCancelled();
      }
      return MediaPickMany(videoResults!);
    }
    return videoResult;
  }

  @override
  Future<MediaPickResult> pickVideoFromCamera() async => cameraVideoResult;

  @override
  Future<MediaPickResult> pickAudio() async => audioResult;

  @override
  Future<MediaPickResult> pickDocument({int? limit}) async {
    if (documentResults != null) {
      if (documentResults!.isEmpty) {
        return const MediaPickCancelled();
      }
      return MediaPickMany(documentResults!);
    }
    return documentResult;
  }
}

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  required _ChroniqueApiProbe api,
  AuthTokenStorage? storage,
  _FakeLocalMediaPicker? picker,
  _FakeMicrophoneRecorder? recorder,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authTokenStorageProvider.overrideWithValue(
          storage ??
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
        chroniqueMicrophoneRecorderProvider.overrideWithValue(
          recorder ?? _FakeMicrophoneRecorder(),
        ),
        chroniqueLocalFileAccessProvider.overrideWithValue(
          const _AlwaysReadableFileAccess(),
        ),
        chroniqueMediaUploadClientProvider.overrideWithValue(
          _FakeMediaUploadClient(),
        ),
      ],
      child: const LuminaApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(LuminaApp)));
}

Future<void> _openCreate(WidgetTester tester) async {
  expect(find.byType(HomeScreen), findsOneWidget);
  await tester.tap(find.text('CREATE'));
  await tester.pumpAndSettle();
  expect(find.byType(CreateChroniqueScreen), findsOneWidget);
}

const _validBody = 'Le texte de la chronique, d au moins vingt caracteres.';

Future<void> _enterValidBody(WidgetTester tester, {String body = _validBody}) async {
  await tester.enterText(find.byType(TextField).at(1), body);
  await tester.pump();
}

Future<void> _goToPublication(WidgetTester tester) async {
  await tester.tap(find.text('Suivant'));
  await tester.pumpAndSettle();
  expect(find.text('Publication'), findsWidgets);
}

Future<void> _goToPreview(WidgetTester tester) async {
  await _goToPublication(tester);
  await tester.tap(find.text('Suivant'));
  await tester.pumpAndSettle();
  expect(find.text('Aperçu'), findsWidgets);
}

Finder _actionInk(String label) {
  return find.descendant(
    of: find.ancestor(
      of: find.text(label),
      matching: find.byType(AppButton),
    ),
    matching: find.byType(InkWell),
  );
}

InkWell _nextInkWell(WidgetTester tester) {
  return tester.widget<InkWell>(_actionInk('Suivant'));
}

InkWell _publishInkWell(WidgetTester tester) {
  return tester.widget<InkWell>(_actionInk('Publier'));
}

void _expectNoUnsupportedCreateFields(_ChroniqueApiProbe api) {
  final data = api.lastCreateData ?? const <String, dynamic>{};
  expect(data.containsKey('theme_id'), isFalse);
  expect(data.containsKey('comments_enabled'), isFalse);
  expect(data.containsKey('is_public'), isFalse);
  expect(data.containsKey('audience'), isFalse);
}

void main() {
  test('chronique JSON maps public fields without user_id', () {
    final chronique = Chronique.fromJson({
      'id': '42',
      'theme_id': null,
      'title': 'Premier soir',
      'body': 'Le texte de la chronique, d au moins vingt caracteres.',
      'status': 'active',
      'published_at': '2026-09-22T10:00:00.000Z',
      'scheduled_at': null,
      'is_time_limited': false,
      'expires_at': null,
      'created_at': '2026-09-22T09:50:00.000Z',
      'updated_at': '2026-09-22T10:00:00.000Z',
    });
    expect(chronique.id, 42);
    expect(chronique.title, 'Premier soir');
    expect(chronique.status, 'active');
    expect(chronique.isTimeLimited, isFalse);
    expect(chronique.scheduledAt, isNull);

    final scheduled = Chronique.fromJson({
      'id': 7,
      'body': 'Le texte de la chronique, d au moins vingt caracteres.',
      'status': 'scheduled',
      'scheduled_at': '2026-09-24T15:30:00.000Z',
      'is_time_limited': true,
      'expires_at': '2026-09-25T15:30:00.000Z',
    });
    expect(scheduled.scheduledAt, DateTime.parse('2026-09-24T15:30:00.000Z'));
    expect(scheduled.isTimeLimited, isTrue);
    expect(scheduled.expiresAt, DateTime.parse('2026-09-25T15:30:00.000Z'));
  });

  testWidgets('authenticated user opens CREATE as a full-screen create assistant', (
    tester,
  ) async {
    final api = _ChroniqueApiProbe();
    final container = await _pumpHome(tester, api: api);
    await _openCreate(tester);

    expect(find.text('Contenu'), findsOneWidget);
    expect(find.text('Nouvelle chronique'), findsOneWidget);
    expect(find.text('Titre (optionnel)'), findsOneWidget);
    expect(find.text('Texte *'), findsOneWidget);
    expect(find.text('Suivant'), findsOneWidget);
    expect(find.text('Publier'), findsNothing);
    expect(find.text('0 / 1000'), findsOneWidget);
    expect(find.text('+ Ajouter un média'), findsOneWidget);
    expect(find.text('Médias : 0 / 5'), findsOneWidget);
    expect(find.text('Aucun média ajouté'), findsOneWidget);
    expect(find.text(kChroniquePublishScheduleLabel), findsNothing);
    expect(_nextInkWell(tester).onTap, isNull);
    expect(find.byType(CloseButton), findsOneWidget);
    expect(find.text('Chapitre'), findsNothing);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    expect(api.createCalls, 0);
  });

  testWidgets('empty body shows a local error and does not call the API', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await tester.enterText(find.byType(TextField).at(1), 'x');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '');
    await tester.pump();

    expect(find.text('Le texte est obligatoire'), findsOneWidget);
    expect(_nextInkWell(tester).onTap, isNull);
    expect(api.createCalls, 0);
    expect(find.byType(CreateChroniqueScreen), findsOneWidget);
  });

  testWidgets('body with fewer than 10 non-whitespace characters does not call the API', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await tester.enterText(find.byType(TextField).at(1), 'trop court');
    await tester.pump();

    expect(find.text('Le texte doit contenir au moins 10 caractères'), findsOneWidget);
    expect(find.text('10 / 1000'), findsOneWidget);
    expect(_nextInkWell(tester).onTap, isNull);
    await tester.tap(find.text('Suivant'));
    await tester.pump();
    expect(api.createCalls, 0);
  });

  testWidgets('body longer than 1000 characters does not call the API', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);

    final tooLong = 'a' * 1001;
    await tester.enterText(find.byType(TextField).at(1), tooLong);
    await tester.pump();

    expect(find.text('Le texte est trop long'), findsOneWidget);
    expect(find.text('1001 / 1000'), findsOneWidget);
    expect(_nextInkWell(tester).onTap, isNull);
    expect(api.createCalls, 0);
  });

  testWidgets('character counter updates and Publier becomes enabled', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);

    expect(find.text('0 / 1000'), findsOneWidget);
    expect(_nextInkWell(tester).onTap, isNull);

    const body = 'Le texte de la chronique, d au moins vingt caracteres.';
    await tester.enterText(find.byType(TextField).at(1), body);
    await tester.pump();

    expect(find.text('${body.trim().runes.length} / 1000'), findsOneWidget);
    expect(_nextInkWell(tester).onTap, isNotNull);
    expect(api.createCalls, 0);
  });

  testWidgets('publish opens Mon Fil then back returns to Home without logout', (
    tester,
  ) async {
    final api = _ChroniqueApiProbe();
    final container = await _pumpHome(tester, api: api);
    await _openCreate(tester);

    const body = 'Le texte de la chronique, d au moins vingt caracteres.';
    await tester.enterText(find.byType(TextField).at(0), 'Premier soir');
    await tester.enterText(find.byType(TextField).at(1), body);
    await tester.pump();
    await _goToPreview(tester);
    await tester.ensureVisible(find.text('Publier'));
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.lastAccessToken, 'access-test');
    expect(api.lastTitle, 'Premier soir');
    expect(api.lastBody, body);
    expect(api.lastPublish, 'now');
    expect(api.lastScheduledAt, isNull);
    expect(api.lastIsTimeLimited, isFalse);
    expect(api.lastExpiresAt, isNull);
    _expectNoUnsupportedCreateFields(api);
    expect(find.byType(MonFilScreen), findsOneWidget);
    expect(find.text('Mon Fil'), findsOneWidget);
    expect(find.byType(CreateChroniqueScreen), findsNothing);
    expect(api.listCalls, 1);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Logout'), findsNothing);
    expect(find.byKey(const ValueKey('home-user-avatar')), findsOneWidget);
    expect(find.byType(MonFilScreen), findsNothing);
    expect(find.byType(CreateChroniqueScreen), findsNothing);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('API error is shown without logout', (tester) async {
    final api = _ChroniqueApiProbe()
      ..failWith = const ApiException(message: 'body is too short', statusCode: 400);
    final container = await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await tester.enterText(
      find.byType(TextField).at(1),
      'Le texte de la chronique, d au moins vingt caracteres.',
    );
    await tester.pump();
    await _goToPreview(tester);
    await tester.ensureVisible(find.text('Publier'));
    await tester.tap(find.text('Publier'));
    await tester.pump();

    expect(api.createCalls, 1);
    expect(find.text('body is too short'), findsOneWidget);
    expect(find.byType(CreateChroniqueScreen), findsOneWidget);
    expect(find.byType(MonFilScreen), findsNothing);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    expect(find.text('Logout'), findsNothing);
  });

  testWidgets('close returns to Home V1 without publishing', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(CreateChroniqueScreen), findsNothing);
    expect(find.byKey(const ValueKey('home-user-avatar')), findsOneWidget);
    expect(api.createCalls, 0);
  });

  testWidgets('local media can be added and removed without API calls', (tester) async {
    final api = _ChroniqueApiProbe();
    final picker = _FakeLocalMediaPicker()
      ..imageResult = const MediaPickSelected(
        kind: MediaDraftKind.image,
        sourceType: MediaDraftSourceType.gallery,
        fileName: 'photo.jpg',
        byteSize: 2516582,
        localPath: '/tmp/photo.jpg',
      );
    final container = await _pumpHome(tester, api: api, picker: picker);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();

    expect(find.text('Image'), findsOneWidget);
    expect(find.text('Vidéo'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Document'), findsOneWidget);

    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    expect(find.text('Galerie (plusieurs)'), findsOneWidget);
    expect(find.text('Appareil photo'), findsOneWidget);
    await tester.tap(find.text('Galerie (plusieurs)'));
    await tester.pumpAndSettle();

    expect(find.text('Aucun média ajouté'), findsNothing);
    expect(find.byType(MediaDraftList), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('Médias : 1 / 5'), findsOneWidget);
    expect(find.text('2.4 Mo'), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(container.read(createChroniqueControllerProvider).medias, hasLength(1));
    final image = container.read(createChroniqueControllerProvider).medias.single;
    expect(image.kind, MediaDraftKind.image);
    expect(image.sourceType, MediaDraftSourceType.gallery);
    expect(image.localPath, '/tmp/photo.jpg');
    expect(image.status, MediaDraftStatus.selected);
    expect(image.contentType, 'image/jpeg');
    expect(api.createCalls, 0);

    await tester.tap(find.byTooltip('Supprimer'));
    await tester.pump();

    expect(find.text('Aucun média ajouté'), findsOneWidget);
    expect(find.text('Médias : 0 / 5'), findsOneWidget);
    expect(container.read(createChroniqueControllerProvider).medias, isEmpty);
    expect(api.createCalls, 0);
  });

  testWidgets('sixth media is blocked in the assistant without opening the kind sheet', (tester) async {
    final api = _ChroniqueApiProbe();
    final container = await _pumpHome(tester, api: api);
    await _openCreate(tester);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    for (var i = 0; i < kChroniqueMaxMediaCount; i++) {
      controller.addMediaDraft(
        kind: MediaDraftKind.image,
        sourceType: MediaDraftSourceType.gallery,
        fileName: 'p$i.jpg',
        byteSize: 1024,
        localPath: '/tmp/p$i.jpg',
        contentType: 'image/jpeg',
      );
    }
    await tester.pump();

    expect(container.read(createChroniqueControllerProvider).medias, hasLength(5));
    expect(find.text('Médias : 5 / 5'), findsOneWidget);
    expect(find.text(kMediaLimitReachedMessage), findsOneWidget);
    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();

    expect(find.text(kTooManyMediaMessage), findsOneWidget);
    expect(find.text('Image'), findsNothing);
    expect(container.read(createChroniqueControllerProvider).medias, hasLength(5));
    expect(api.createCalls, 0);
  });

  testWidgets('cancelling gallery selection does not change the draft', (tester) async {
    final api = _ChroniqueApiProbe();
    final container = await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    expect(find.text('Galerie (plusieurs)'), findsOneWidget);
    expect(find.text('Appareil photo'), findsOneWidget);
    await tester.tap(find.text('Galerie (plusieurs)'));
    await tester.pumpAndSettle();

    expect(find.text('Aucun média ajouté'), findsOneWidget);
    expect(container.read(createChroniqueControllerProvider).medias, isEmpty);
    expect(api.createCalls, 0);
  });

  testWidgets('camera photo creates an image MediaDraft with sourceType camera', (tester) async {
    final api = _ChroniqueApiProbe();
    final picker = _FakeLocalMediaPicker()
      ..cameraImageResult = const MediaPickSelected(
        kind: MediaDraftKind.image,
        sourceType: MediaDraftSourceType.camera,
        fileName: 'camera.jpg',
        byteSize: 1024,
        localPath: '/tmp/camera.jpg',
        contentType: 'image/jpeg',
      );
    final container = await _pumpHome(tester, api: api, picker: picker);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appareil photo'));
    await tester.pumpAndSettle();

    final image = container.read(createChroniqueControllerProvider).medias.single;
    expect(image.kind, MediaDraftKind.image);
    expect(image.sourceType, MediaDraftSourceType.camera);
    expect(image.fileName, 'camera.jpg');
    expect(image.localPath, '/tmp/camera.jpg');
    expect(image.contentType, 'image/jpeg');
    expect(find.text('camera.jpg'), findsOneWidget);
    expect(api.createCalls, 0);
  });

  testWidgets('cancelling camera capture does not change the draft', (tester) async {
    final api = _ChroniqueApiProbe();
    final container = await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appareil photo'));
    await tester.pumpAndSettle();

    expect(find.text('Aucun média ajouté'), findsOneWidget);
    expect(container.read(createChroniqueControllerProvider).medias, isEmpty);
    expect(api.createCalls, 0);
  });

  testWidgets('camera access denied shows a short message without crash', (tester) async {
    final api = _ChroniqueApiProbe();
    final picker = _FakeLocalMediaPicker()
      ..cameraImageResult = const MediaPickFailed(kCameraAccessDeniedMessage);
    final container = await _pumpHome(tester, api: api, picker: picker);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appareil photo'));
    await tester.pumpAndSettle();

    expect(find.text(kCameraAccessDeniedMessage), findsOneWidget);
    expect(container.read(createChroniqueControllerProvider).medias, isEmpty);
    expect(find.byType(CreateChroniqueScreen), findsOneWidget);
    expect(api.createCalls, 0);
  });

  testWidgets('publish with a camera image sends source_type camera', (tester) async {
    final api = _ChroniqueApiProbe();
    final picker = _FakeLocalMediaPicker()
      ..cameraImageResult = const MediaPickSelected(
        kind: MediaDraftKind.image,
        sourceType: MediaDraftSourceType.camera,
        fileName: 'camera.jpg',
        byteSize: 1024,
        localPath: '/tmp/camera.jpg',
        contentType: 'image/jpeg',
      );
    await _pumpHome(tester, api: api, picker: picker);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appareil photo'));
    await tester.pumpAndSettle();

    const body = 'Le texte de la chronique, d au moins vingt caracteres.';
    await tester.enterText(find.byType(TextField).at(1), body);
    await tester.pump();
    await _goToPreview(tester);
    await tester.ensureVisible(find.text('Publier'));
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.createMediaUploadCalls, 1);
    expect(api.lastUploadPayload?['kind'], 'image');
    expect(api.lastUploadPayload?['source_type'], 'camera');
    expect(api.lastUploadPayload?['content_type'], 'image/jpeg');
    expect(api.lastUploadPayload?.containsKey('storage_key'), isFalse);
    expect(find.byType(MonFilScreen), findsOneWidget);
  });

  testWidgets('gallery video creates a video MediaDraft with sourceType gallery', (tester) async {
    final api = _ChroniqueApiProbe();
    final picker = _FakeLocalMediaPicker()
      ..videoResult = const MediaPickSelected(
        kind: MediaDraftKind.video,
        sourceType: MediaDraftSourceType.gallery,
        fileName: 'clip.mp4',
        byteSize: 4096,
        localPath: '/tmp/clip.mp4',
        contentType: 'video/mp4',
      );
    final container = await _pumpHome(tester, api: api, picker: picker);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vidéo'));
    await tester.pumpAndSettle();
    expect(find.text('Galerie (plusieurs)'), findsOneWidget);
    expect(find.text('Caméra'), findsOneWidget);
    await tester.tap(find.text('Galerie (plusieurs)'));
    await tester.pumpAndSettle();

    final video = container.read(createChroniqueControllerProvider).medias.single;
    expect(video.kind, MediaDraftKind.video);
    expect(video.sourceType, MediaDraftSourceType.gallery);
    expect(video.fileName, 'clip.mp4');
    expect(video.contentType, 'video/mp4');
    expect(find.text('clip.mp4'), findsOneWidget);
    expect(api.createCalls, 0);
  });

  testWidgets('camera video creates a video MediaDraft with sourceType camera', (tester) async {
    final api = _ChroniqueApiProbe();
    final picker = _FakeLocalMediaPicker()
      ..cameraVideoResult = const MediaPickSelected(
        kind: MediaDraftKind.video,
        sourceType: MediaDraftSourceType.camera,
        fileName: 'camera.mp4',
        byteSize: 8192,
        localPath: '/tmp/camera.mp4',
        contentType: 'video/mp4',
      );
    final container = await _pumpHome(tester, api: api, picker: picker);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vidéo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caméra'));
    await tester.pumpAndSettle();

    final video = container.read(createChroniqueControllerProvider).medias.single;
    expect(video.kind, MediaDraftKind.video);
    expect(video.sourceType, MediaDraftSourceType.camera);
    expect(video.fileName, 'camera.mp4');
    expect(video.localPath, '/tmp/camera.mp4');
    expect(video.contentType, 'video/mp4');
    expect(find.text('camera.mp4'), findsOneWidget);
    expect(api.createCalls, 0);
  });

  testWidgets('cancelling camera video does not change the draft', (tester) async {
    final api = _ChroniqueApiProbe();
    final container = await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vidéo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caméra'));
    await tester.pumpAndSettle();

    expect(find.text('Aucun média ajouté'), findsOneWidget);
    expect(container.read(createChroniqueControllerProvider).medias, isEmpty);
    expect(api.createCalls, 0);
  });

  testWidgets('camera video access denied shows a short message without crash', (tester) async {
    final api = _ChroniqueApiProbe();
    final picker = _FakeLocalMediaPicker()
      ..cameraVideoResult = const MediaPickFailed(kCameraAccessDeniedMessage);
    final container = await _pumpHome(tester, api: api, picker: picker);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vidéo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caméra'));
    await tester.pumpAndSettle();

    expect(find.text(kCameraAccessDeniedMessage), findsOneWidget);
    expect(container.read(createChroniqueControllerProvider).medias, isEmpty);
    expect(find.byType(CreateChroniqueScreen), findsOneWidget);
    expect(api.createCalls, 0);
  });

  testWidgets('publish with a camera video sends source_type camera', (tester) async {
    final api = _ChroniqueApiProbe();
    final picker = _FakeLocalMediaPicker()
      ..cameraVideoResult = const MediaPickSelected(
        kind: MediaDraftKind.video,
        sourceType: MediaDraftSourceType.camera,
        fileName: 'camera.mp4',
        byteSize: 8192,
        localPath: '/tmp/camera.mp4',
        contentType: 'video/mp4',
      );
    await _pumpHome(tester, api: api, picker: picker);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vidéo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caméra'));
    await tester.pumpAndSettle();

    const body = 'Le texte de la chronique, d au moins vingt caracteres.';
    await tester.enterText(find.byType(TextField).at(1), body);
    await tester.pump();
    await _goToPreview(tester);
    await tester.ensureVisible(find.text('Publier'));
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.createMediaUploadCalls, 1);
    expect(api.lastUploadPayload?['kind'], 'video');
    expect(api.lastUploadPayload?['source_type'], 'camera');
    expect(api.lastUploadPayload?['content_type'], 'video/mp4');
    expect(api.lastUploadPayload?.containsKey('storage_key'), isFalse);
    expect(find.byType(MonFilScreen), findsOneWidget);
  });

  testWidgets('file audio creates an audio MediaDraft with sourceType upload', (tester) async {
    final api = _ChroniqueApiProbe();
    final picker = _FakeLocalMediaPicker()
      ..audioResult = const MediaPickSelected(
        kind: MediaDraftKind.audio,
        sourceType: MediaDraftSourceType.upload,
        fileName: 'voix.m4a',
        byteSize: 4096,
        localPath: '/tmp/voix.m4a',
        contentType: 'audio/mp4',
      );
    final container = await _pumpHome(tester, api: api, picker: picker);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();
    expect(find.text('Fichier'), findsOneWidget);
    expect(find.text('Microphone'), findsOneWidget);
    await tester.tap(find.text('Fichier'));
    await tester.pumpAndSettle();

    final audio = container.read(createChroniqueControllerProvider).medias.single;
    expect(audio.kind, MediaDraftKind.audio);
    expect(audio.sourceType, MediaDraftSourceType.upload);
    expect(audio.fileName, 'voix.m4a');
    expect(audio.contentType, 'audio/mp4');
    expect(find.text('voix.m4a'), findsOneWidget);
    expect(api.createCalls, 0);
  });

  testWidgets('microphone recording creates an audio MediaDraft with sourceType microphone', (tester) async {
    final api = _ChroniqueApiProbe();
    final recorder = _FakeMicrophoneRecorder();
    final container = await _pumpHome(tester, api: api, recorder: recorder);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Microphone'));
    await tester.pumpAndSettle();

    expect(find.text('🎙️ Prêt à enregistrer'), findsOneWidget);
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();
    expect(find.text('🔴 Enregistrement'), findsOneWidget);
    expect(recorder.startCalls, 1);
    await tester.tap(find.text('Arrêter'));
    await tester.pump();
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();

    final audio = container.read(createChroniqueControllerProvider).medias.single;
    expect(audio.kind, MediaDraftKind.audio);
    expect(audio.sourceType, MediaDraftSourceType.microphone);
    expect(audio.fileName, 'mic.m4a');
    expect(audio.localPath, '/tmp/mic.m4a');
    expect(audio.contentType, 'audio/mp4');
    expect(find.text('mic.m4a'), findsOneWidget);
    expect(api.createCalls, 0);
  });

  testWidgets('cancelling microphone recording does not change the draft', (tester) async {
    final api = _ChroniqueApiProbe();
    final recorder = _FakeMicrophoneRecorder();
    final container = await _pumpHome(tester, api: api, recorder: recorder);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Microphone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(find.text('Aucun média ajouté'), findsOneWidget);
    expect(container.read(createChroniqueControllerProvider).medias, isEmpty);
    expect(recorder.discardCalls, 1);
    expect(api.createCalls, 0);
  });

  testWidgets('microphone access denied shows a short message without crash', (tester) async {
    final api = _ChroniqueApiProbe();
    final recorder = _FakeMicrophoneRecorder()..permissionGranted = false;
    final container = await _pumpHome(tester, api: api, recorder: recorder);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Microphone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(find.text(kMicrophoneAccessDeniedMessage), findsOneWidget);
    expect(container.read(createChroniqueControllerProvider).medias, isEmpty);
    expect(find.byType(CreateChroniqueScreen), findsOneWidget);
    expect(recorder.startCalls, 0);
    expect(api.createCalls, 0);
  });

  testWidgets('invalid microphone file shows a message without MediaDraft', (tester) async {
    final api = _ChroniqueApiProbe();
    final recorder = _FakeMicrophoneRecorder()
      ..stopResult = const MediaPickFailed(kMediaInaccessibleMessage);
    final container = await _pumpHome(tester, api: api, recorder: recorder);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Microphone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();
    await tester.tap(find.text('Arrêter'));
    await tester.pumpAndSettle();

    expect(find.text(kMediaInaccessibleMessage), findsOneWidget);
    expect(container.read(createChroniqueControllerProvider).medias, isEmpty);
    expect(api.createCalls, 0);
  });

  testWidgets('publish with a microphone audio sends source_type microphone', (tester) async {
    final api = _ChroniqueApiProbe();
    final recorder = _FakeMicrophoneRecorder();
    await _pumpHome(tester, api: api, recorder: recorder);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Microphone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();
    await tester.tap(find.text('Arrêter'));
    await tester.pump();
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();

    const body = 'Le texte de la chronique, d au moins vingt caracteres.';
    await tester.enterText(find.byType(TextField).at(1), body);
    await tester.pump();
    await _goToPreview(tester);
    await tester.ensureVisible(find.text('Publier'));
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.createMediaUploadCalls, 1);
    expect(api.lastUploadPayload?['kind'], 'audio');
    expect(api.lastUploadPayload?['source_type'], 'microphone');
    expect(api.lastUploadPayload?['content_type'], 'audio/mp4');
    expect(api.lastUploadPayload?.containsKey('storage_key'), isFalse);
    expect(find.byType(MonFilScreen), findsOneWidget);
  });

  testWidgets('inaccessible file shows a message without logout', (tester) async {
    final api = _ChroniqueApiProbe();
    final picker = _FakeLocalMediaPicker()
      ..imageResult = const MediaPickFailed(kMediaInaccessibleMessage);
    final container = await _pumpHome(tester, api: api, picker: picker);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    expect(find.text('Galerie (plusieurs)'), findsOneWidget);
    expect(find.text('Appareil photo'), findsOneWidget);
    await tester.tap(find.text('Galerie (plusieurs)'));
    await tester.pumpAndSettle();

    expect(find.text(kMediaInaccessibleMessage), findsOneWidget);
    expect(find.text('Aucun média ajouté'), findsOneWidget);
    expect(container.read(createChroniqueControllerProvider).medias, isEmpty);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    expect(api.createCalls, 0);
  });

  testWidgets('unsupported file type shows a message without logout', (tester) async {
    final api = _ChroniqueApiProbe();
    final picker = _FakeLocalMediaPicker()
      ..documentResult = const MediaPickFailed(kMediaUnsupportedMessage);
    final container = await _pumpHome(tester, api: api, picker: picker);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Document'));
    await tester.pumpAndSettle();

    expect(find.text(kMediaUnsupportedMessage), findsOneWidget);
    expect(container.read(createChroniqueControllerProvider).medias, isEmpty);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    expect(api.createCalls, 0);
  });

  testWidgets('document picker adds a local MediaDraft', (tester) async {
    final api = _ChroniqueApiProbe();
    final picker = _FakeLocalMediaPicker()
      ..documentResult = const MediaPickSelected(
        kind: MediaDraftKind.document,
        sourceType: MediaDraftSourceType.upload,
        fileName: 'notes.pdf',
        byteSize: 2048,
        localPath: '/tmp/notes.pdf',
      );
    final container = await _pumpHome(tester, api: api, picker: picker);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Document'));
    await tester.pumpAndSettle();

    expect(find.text('notes.pdf'), findsOneWidget);
    expect(find.text('2 Ko'), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    final doc = container.read(createChroniqueControllerProvider).medias.single;
    expect(doc.kind, MediaDraftKind.document);
    expect(doc.sourceType, MediaDraftSourceType.upload);
    expect(api.createCalls, 0);
  });

  testWidgets('publish with a local document uploads then completes media', (tester) async {
    final api = _ChroniqueApiProbe();
    final picker = _FakeLocalMediaPicker()
      ..documentResult = const MediaPickSelected(
        kind: MediaDraftKind.document,
        sourceType: MediaDraftSourceType.upload,
        fileName: 'notes.pdf',
        byteSize: 2048,
        localPath: '/tmp/notes.pdf',
        contentType: 'application/pdf',
      );
    await _pumpHome(tester, api: api, picker: picker);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Document'));
    await tester.pumpAndSettle();

    const body = 'Le texte de la chronique, d au moins vingt caracteres.';
    await tester.enterText(find.byType(TextField).at(1), body);
    await tester.pump();
    await _goToPreview(tester);
    await tester.ensureVisible(find.text('Publier'));
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.createMediaUploadCalls, 1);
    expect(api.completeMediaUploadCalls, 1);
    expect(api.lastUploadPayload?['kind'], 'document');
    expect(api.lastUploadPayload?['content_type'], 'application/pdf');
    expect(api.lastUploadPayload?['source_type'], 'upload');
    expect(api.lastUploadPayload?.containsKey('storage_key'), isFalse);
    expect(api.lastBody, body);
    expect(api.lastTitle, isNull);
    expect(api.lastPublish, 'now');
    expect(find.byType(MonFilScreen), findsOneWidget);
  });

  testWidgets('schedule mode shows date and time pickers', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);
    await _enterValidBody(tester);
    await _goToPublication(tester);

    await tester.ensureVisible(find.text(kChroniquePublishScheduleLabel));
    await tester.tap(find.text(kChroniquePublishScheduleLabel));
    await tester.pumpAndSettle();

    expect(find.text('Date de publication'), findsOneWidget);
    expect(find.text('Heure de publication'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('schedule-date')));
    await tester.tap(find.byKey(const ValueKey('schedule-date')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('schedule-time')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
  });

  testWidgets('scheduled publish sends UTC scheduled_at and opens À venir', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await _enterValidBody(tester);
    await _goToPublication(tester);
    await tester.ensureVisible(find.text(kChroniquePublishScheduleLabel));
    await tester.tap(find.text(kChroniquePublishScheduleLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Publier'));
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.lastPublish, 'schedule');
    expect(api.lastScheduledAt, isNotNull);
    expect(api.lastScheduledAt, contains('Z'));
    final scheduled = DateTime.parse(api.lastScheduledAt!);
    expect(scheduled.isUtc, isTrue);
    expect(scheduled.isAfter(DateTime.now().toUtc()), isTrue);
    expect(api.lastExpiresAt, isNull);
    expect(find.byType(UpcomingChroniquesScreen), findsOneWidget);
    expect(api.lastListStatus, 'scheduled');
  });

  testWidgets('ephemeral now sends UTC expires_at without scheduled_at', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await _enterValidBody(tester);
    await _goToPublication(tester);
    await tester.tap(find.byKey(const ValueKey('expiration-yes')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('expiration-dropdown')));
    await tester.tap(find.byKey(const ValueKey('expiration-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 heure').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Publier'));
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.lastPublish, 'now');
    expect(api.lastScheduledAt, isNull);
    expect(api.lastIsTimeLimited, isTrue);
    expect(api.lastExpiresAt, contains('Z'));
    final expires = DateTime.parse(api.lastExpiresAt!);
    expect(expires.isUtc, isTrue);
    final delta = expires.difference(DateTime.now().toUtc());
    expect(delta.inMinutes, greaterThan(50));
    expect(delta.inMinutes, lessThan(70));
  });

  testWidgets('scheduled plus ephemeral sends both UTC timestamps', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await _enterValidBody(tester);
    await _goToPublication(tester);
    await tester.ensureVisible(find.text(kChroniquePublishScheduleLabel));
    await tester.tap(find.text(kChroniquePublishScheduleLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expiration-yes')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('expiration-dropdown')));
    await tester.tap(find.byKey(const ValueKey('expiration-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 heure').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Publier'));
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.lastPublish, 'schedule');
    expect(api.lastIsTimeLimited, isTrue);
    final scheduled = DateTime.parse(api.lastScheduledAt!);
    final expires = DateTime.parse(api.lastExpiresAt!);
    expect(scheduled.isUtc, isTrue);
    expect(expires.isUtc, isTrue);
    expect(expires.difference(scheduled).inMinutes, closeTo(60, 1));
  });

  testWidgets('custom expiration before publication is rejected', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await _enterValidBody(tester);
    await _goToPublication(tester);
    await tester.ensureVisible(find.text(kChroniquePublishScheduleLabel));
    await tester.tap(find.text(kChroniquePublishScheduleLabel));
    await tester.pumpAndSettle();
    final state = tester.state<CreateChroniqueScreenState>(find.byType(CreateChroniqueScreen));
    final scheduled = state.scheduleDraft.scheduledAt!;
    state.debugSetScheduleDraft(
      state.scheduleDraft.copyWith(
        expirationEnabled: true,
        expirationPreset: ChroniqueExpirationPreset.custom,
        customExpiresAt: scheduled.subtract(const Duration(hours: 2)),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Suivant'));
    await tester.pump();

    expect(find.text(kExpiresBeforeActivationMessage), findsOneWidget);
    expect(api.createCalls, 0);
    expect(find.byType(CreateChroniqueScreen), findsOneWidget);
  });

  testWidgets('wizard back keeps content and close leaves without publishing', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await tester.enterText(find.byType(TextField).at(0), 'Premier soir');
    await _enterValidBody(tester);
    await _goToPreview(tester);
    expect(find.text('Premier soir'), findsWidgets);
    expect(find.text(_validBody), findsWidgets);
    expect(find.text(kChroniquePublishNowLabel), findsWidgets);
    expect(find.text(kChroniqueNoExpirationLabel), findsOneWidget);

    await tester.tap(find.text('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('Publication'), findsWidgets);
    expect(find.text('Retour'), findsOneWidget);

    await tester.tap(find.text('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('Contenu'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller?.text,
      'Premier soir',
    );

    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(api.createCalls, 0);
  });

  testWidgets('past schedule is rejected and equal expiration is rejected', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);
    await _enterValidBody(tester);
    await _goToPublication(tester);

    final state = tester.state<CreateChroniqueScreenState>(find.byType(CreateChroniqueScreen));
    final past = DateTime.now().subtract(const Duration(hours: 1));
    state.debugSetScheduleDraft(
      ChroniqueScheduleDraft(
        publishMode: ChroniquePublishMode.schedule,
        scheduledAt: past,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Suivant'));
    await tester.pump();
    expect(find.text(kSchedulePastMessage), findsOneWidget);

    final scheduled = DateTime.now().add(const Duration(hours: 2));
    state.debugSetScheduleDraft(
      ChroniqueScheduleDraft(
        publishMode: ChroniquePublishMode.schedule,
        scheduledAt: scheduled,
        expirationEnabled: true,
        expirationPreset: ChroniqueExpirationPreset.custom,
        customExpiresAt: scheduled,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Suivant'));
    await tester.pump();
    expect(find.text(kExpiresBeforeActivationMessage), findsOneWidget);
    expect(api.createCalls, 0);
  });

  testWidgets('publication defaults to immediate and ephemeral off, with paused options', (
    tester,
  ) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);
    await _enterValidBody(tester);
    await _goToPublication(tester);

    expect(find.text(kChroniquePublishNowLabel), findsOneWidget);
    expect(find.byKey(const ValueKey('publish-now')), findsOneWidget);
    expect(tester.widget<Icon>(find.descendant(
      of: find.byKey(const ValueKey('publish-now')),
      matching: find.byType(Icon),
    )).icon, Icons.radio_button_checked);
    expect(find.byKey(const ValueKey('assistant-theme')), findsOneWidget);
    expect(find.text(kChroniqueThemePausedMessage), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-comments')), findsOneWidget);
    expect(find.text(kChroniqueCommentsUnavailableMessage), findsOneWidget);
    expect(find.byKey(const ValueKey('comments-yes')), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-visibility')), findsOneWidget);
    expect(find.byKey(const ValueKey('visibility-private')), findsOneWidget);
    expect(find.byKey(const ValueKey('visibility-public')), findsOneWidget);
    expect(find.text('Famille'), findsOneWidget);
    expect(find.text('Amis'), findsOneWidget);
    expect(find.text('Collègues'), findsOneWidget);
    expect(find.text('Autres'), findsOneWidget);
    expect(find.text(kChroniqueVisibilityUnavailableMessage), findsOneWidget);
    expect(find.text('30 jours'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('expiration-yes')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('expiration-dropdown')));
    await tester.tap(find.byKey(const ValueKey('expiration-dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('30 jours').hitTestable(), findsWidgets);
    await tester.tap(find.text('30 jours').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Aperçu'), findsWidgets);
    expect(find.text(kChroniquePublishNowLabel), findsWidgets);
    expect(find.textContaining('30 jours'), findsOneWidget);
    expect(find.text(kChroniquePausedOptionsPreviewTitle), findsOneWidget);
    expect(find.textContaining(kChroniqueThemePausedMessage), findsWidgets);
    expect(find.textContaining(kChroniqueCommentsUnavailableMessage), findsWidgets);
    expect(find.text('Commentaires activés'), findsNothing);

    await tester.tap(find.text('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('Publication'), findsWidgets);
    expect(find.text('30 jours'), findsOneWidget);

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Publier'));
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.lastPublish, 'now');
    expect(api.lastIsTimeLimited, isTrue);
    _expectNoUnsupportedCreateFields(api);
    final expires = DateTime.parse(api.lastExpiresAt!);
    final delta = expires.difference(DateTime.now().toUtc());
    expect(delta.inHours, greaterThan(29 * 24 - 1));
    expect(delta.inHours, lessThan(30 * 24 + 1));
  });

  testWidgets('preview shows scheduled local datetime and keeps values on back', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);
    await tester.enterText(find.byType(TextField).at(0), 'Soir programmé');
    await _enterValidBody(tester);
    await _goToPublication(tester);
    await tester.ensureVisible(find.text(kChroniquePublishScheduleLabel));
    await tester.tap(find.text(kChroniquePublishScheduleLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();

    expect(find.text('Soir programmé'), findsWidgets);
    expect(find.text(_validBody), findsWidgets);
    expect(find.text(kChroniquePublishScheduleLabel), findsWidgets);
    expect(find.byKey(const ValueKey('preview-scheduled-at')), findsOneWidget);
    expect(find.text(kChroniqueNoExpirationLabel), findsOneWidget);

    await tester.tap(find.text('Retour'));
    await tester.pumpAndSettle();
    expect(find.text(kChroniquePublishScheduleLabel), findsOneWidget);
    await tester.tap(find.text('Retour'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller?.text,
      'Soir programmé',
    );
    expect(api.createCalls, 0);
  });

  testWidgets('gallery multi-select adds several images up to remaining slots', (tester) async {
    final api = _ChroniqueApiProbe();
    final picker = _FakeLocalMediaPicker()
      ..imageResults = [
        const MediaPickSelected(
          kind: MediaDraftKind.image,
          sourceType: MediaDraftSourceType.gallery,
          fileName: 'a.jpg',
          byteSize: 1024,
          localPath: '/tmp/a.jpg',
          contentType: 'image/jpeg',
        ),
        const MediaPickSelected(
          kind: MediaDraftKind.image,
          sourceType: MediaDraftSourceType.gallery,
          fileName: 'b.jpg',
          byteSize: 1024,
          localPath: '/tmp/b.jpg',
          contentType: 'image/jpeg',
        ),
        const MediaPickSelected(
          kind: MediaDraftKind.image,
          sourceType: MediaDraftSourceType.gallery,
          fileName: 'c.jpg',
          byteSize: 1024,
          localPath: '/tmp/c.jpg',
          contentType: 'image/jpeg',
        ),
      ];
    final container = await _pumpHome(tester, api: api, picker: picker);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galerie (plusieurs)'));
    await tester.pumpAndSettle();

    expect(container.read(createChroniqueControllerProvider).medias, hasLength(3));
    expect(find.text('Médias : 3 / 5'), findsOneWidget);
    expect(find.text('a.jpg'), findsOneWidget);
    expect(find.text('b.jpg'), findsOneWidget);
    expect(find.text('c.jpg'), findsOneWidget);
    expect(api.createCalls, 0);
  });

  testWidgets('multi-select never exceeds 5 and keeps existing media', (tester) async {
    final api = _ChroniqueApiProbe();
    final picker = _FakeLocalMediaPicker()
      ..imageResults = [
        for (var i = 0; i < 5; i++)
          MediaPickSelected(
            kind: MediaDraftKind.image,
            sourceType: MediaDraftSourceType.gallery,
            fileName: 'n$i.jpg',
            byteSize: 1024,
            localPath: '/tmp/n$i.jpg',
            contentType: 'image/jpeg',
          ),
      ];
    final container = await _pumpHome(tester, api: api, picker: picker);
    await _openCreate(tester);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    controller.addMediaDraft(
      kind: MediaDraftKind.image,
      sourceType: MediaDraftSourceType.gallery,
      fileName: 'kept.jpg',
      byteSize: 1024,
      localPath: '/tmp/kept.jpg',
      contentType: 'image/jpeg',
    );
    await tester.pump();

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galerie (plusieurs)'));
    await tester.pumpAndSettle();

    final medias = container.read(createChroniqueControllerProvider).medias;
    expect(medias, hasLength(5));
    expect(medias.first.fileName, 'kept.jpg');
    expect(find.text('kept.jpg'), findsOneWidget);
    expect(find.text('Médias : 5 / 5'), findsOneWidget);
    expect(find.text(kSomeMediaSkippedLimitMessage), findsWidgets);
    expect(api.createCalls, 0);
  });

  testWidgets('document multi-select and oversized file are handled on step 1', (tester) async {
    final api = _ChroniqueApiProbe();
    final picker = _FakeLocalMediaPicker()
      ..documentResults = [
        const MediaPickSelected(
          kind: MediaDraftKind.document,
          sourceType: MediaDraftSourceType.upload,
          fileName: 'a.pdf',
          byteSize: 2048,
          localPath: '/tmp/a.pdf',
          contentType: 'application/pdf',
        ),
        const MediaPickSelected(
          kind: MediaDraftKind.document,
          sourceType: MediaDraftSourceType.upload,
          fileName: 'b.pdf',
          byteSize: 2048,
          localPath: '/tmp/b.pdf',
          contentType: 'application/pdf',
        ),
      ];
    final container = await _pumpHome(tester, api: api, picker: picker);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Document'));
    await tester.pumpAndSettle();

    expect(container.read(createChroniqueControllerProvider).medias, hasLength(2));
    expect(find.text('Médias : 2 / 5'), findsOneWidget);
    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.text('b.pdf'), findsOneWidget);

    picker.documentResults = null;
    picker.documentResult = MediaPickSelected(
      kind: MediaDraftKind.document,
      sourceType: MediaDraftSourceType.upload,
      fileName: 'huge.pdf',
      byteSize: kChroniqueMaxMediaBytes + 1,
      localPath: '/tmp/huge.pdf',
      contentType: 'application/pdf',
    );
    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Document'));
    await tester.pumpAndSettle();

    expect(container.read(createChroniqueControllerProvider).medias, hasLength(2));
    expect(find.text(kMediaQuotaExceededMessage), findsOneWidget);

    await _enterValidBody(tester);
    await _goToPublication(tester);
    expect(find.text('a.pdf'), findsNothing);
    await tester.tap(find.text('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.text('b.pdf'), findsOneWidget);
    expect(api.createCalls, 0);
  });

  testWidgets('Next button does not cover the last media in the content step', (tester) async {
    final api = _ChroniqueApiProbe();
    final picker = _FakeLocalMediaPicker()
      ..imageResult = const MediaPickSelected(
        kind: MediaDraftKind.image,
        sourceType: MediaDraftSourceType.gallery,
        fileName: 'last.jpg',
        byteSize: 1024,
        localPath: '/tmp/last.jpg',
        contentType: 'image/jpeg',
      );
    await _pumpHome(tester, api: api, picker: picker);
    await _openCreate(tester);
    await tester.enterText(find.byType(TextField).at(1), 'a' * 400);
    await tester.pump();

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galerie (plusieurs)'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('last.jpg'));
    final mediaBottom = tester.getRect(find.text('last.jpg')).bottom;
    final nextTop = tester.getRect(find.text('Suivant')).top;
    expect(mediaBottom, lessThanOrEqualTo(nextTop));
  });
}
