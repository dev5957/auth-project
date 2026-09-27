import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/auth/data/storage/auth_token_storage.dart';
import 'package:mobile/features/auth/providers/auth_providers.dart';
import 'package:mobile/features/chronique/media/chronique_local_file_access.dart';
import 'package:mobile/features/chronique/media/chronique_local_media_picker.dart';
import 'package:mobile/features/chronique/media/chronique_media_limits.dart';
import 'package:mobile/features/chronique/media/chronique_media_mime.dart';
import 'package:mobile/features/chronique/media/chronique_video_thumbnail.dart';
import 'package:mobile/features/chronique/models/chronique.dart';
import 'package:mobile/features/chronique/models/chronique_media_upload.dart';
import 'package:mobile/features/chronique/models/chronique_page.dart';
import 'package:mobile/features/chronique/models/media_draft.dart';
import 'package:mobile/features/chronique/presentation/state/create_chronique_controller.dart';
import 'package:mobile/features/chronique/providers/chronique_providers.dart';
import 'package:mobile/features/chronique/services/chronique_api_service.dart';
import 'package:mobile/features/chronique/services/chronique_media_upload_client.dart';

class _MemoryTokens implements AuthTokenStorage {
  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {}

  @override
  Future<String?> readAccessToken() async => 'access-test';

  @override
  Future<String?> readRefreshToken() async => 'refresh-test';

  @override
  Future<void> clearTokens() async {}

  @override
  Future<bool> hasRefreshToken() async => true;
}

class _FileAccess implements ChroniqueLocalFileAccess {
  _FileAccess({this.readable = true});

  bool readable;
  int length = 1024;
  bool failDelete = false;
  Completer<void>? deleteGate;
  final List<String> deleted = [];
  final List<String> startedDeletes = [];
  final List<String> skippedDeletes = [];

  @override
  Future<bool> isReadable(String path) async => readable && path.trim().isNotEmpty;

  @override
  Future<int> lengthOf(String path) async => length;

  @override
  Future<void> deleteQuietly(String path, {bool Function()? ifStillUnused}) async {
    startedDeletes.add(path);
    final gate = deleteGate;
    if (gate != null) {
      await gate.future;
    }
    if (ifStillUnused != null && !ifStillUnused()) {
      skippedDeletes.add(path);
      return;
    }
    deleted.add(path);
    if (failDelete) {
      throw Exception('delete failed');
    }
  }
}

class _PutClient extends ChroniqueMediaUploadClient {
  int putCalls = 0;
  final List<String> urls = [];
  final List<Map<String, String>> headers = [];
  ApiException? failWith;
  int? failAt;
  int progressLast = 0;

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
    this.headers.add(headers);
    onSendProgress?.call((byteSize / 2).floor(), byteSize);
    onSendProgress?.call(byteSize, byteSize);
    progressLast = 100;
    if (failWith != null && (failAt == null || putCalls == failAt)) {
      throw failWith!;
    }
  }
}

class _Api extends ChroniqueApiService {
  _Api() : super(ApiClient(config: const AppConfig(apiBaseUrl: 'http://test.invalid')));

  int createCalls = 0;
  int initCalls = 0;
  int completeCalls = 0;
  String? lastPublish;
  String? lastScheduledAt;
  Map<String, dynamic>? lastUploadPayload;
  ApiException? failCreate;
  ApiException? failInit;
  ApiException? failComplete;
  int? failInitAt;
  int? failCompleteAt;
  int _nextMediaId = 200;

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
    lastPublish = publish;
    lastScheduledAt = scheduledAt;
    if (failCreate != null) {
      throw failCreate!;
    }
    return Chronique(
      id: 7,
      body: body,
      title: title,
      status: publish == 'schedule' ? 'scheduled' : 'active',
      scheduledAt: scheduledAt == null ? null : DateTime.tryParse(scheduledAt),
    );
  }

  @override
  Future<ChroniquePage> list({required String accessToken, String? status}) async {
    return const ChroniquePage(items: []);
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
    initCalls += 1;
    lastUploadPayload = {
      'kind': kind,
      'source_type': sourceType,
      'content_type': contentType,
      'byte_size': byteSize,
      'original_filename': originalFilename,
    };
    if (failInit != null && (failInitAt == null || initCalls == failInitAt)) {
      throw failInit!;
    }
    _nextMediaId += 1;
    return ChroniqueMediaUploadSession(
      media: ChroniqueMedia(
        id: _nextMediaId,
        kind: kind,
        byteSize: byteSize,
        status: 'pending_upload',
        contentType: contentType,
        originalFilename: originalFilename,
      ),
      method: 'PUT',
      url: 'https://signed.example/object/$_nextMediaId',
      headers: {'Content-Type': contentType},
      thumbnailMethod: kind == 'video' ? 'PUT' : null,
      thumbnailUrl: kind == 'video' ? 'https://signed.example/thumb/$_nextMediaId' : null,
      thumbnailHeaders: kind == 'video' ? const {'Content-Type': 'image/jpeg'} : null,
    );
  }

  @override
  Future<Chronique> completeMediaUpload({
    required String accessToken,
    required int chroniqueId,
    required int mediaId,
  }) async {
    completeCalls += 1;
    if (failComplete != null && (failCompleteAt == null || completeCalls == failCompleteAt)) {
      throw failComplete!;
    }
    return Chronique(
      id: chroniqueId,
      body: 'ok',
      status: lastPublish == 'schedule' ? 'scheduled' : 'active',
      media: [ChroniqueMedia(id: mediaId, kind: 'image', status: 'ready')],
    );
  }
}

ProviderContainer _container({
  required _Api api,
  _PutClient? put,
  _FileAccess? files,
  ChroniqueVideoThumbnailExtractor? thumbs,
}) {
  final container = ProviderContainer(
    overrides: [
      authTokenStorageProvider.overrideWithValue(_MemoryTokens()),
      chroniqueApiServiceProvider.overrideWithValue(api),
      chroniqueMediaUploadClientProvider.overrideWithValue(put ?? _PutClient()),
      chroniqueLocalFileAccessProvider.overrideWithValue(files ?? _FileAccess()),
      chroniqueVideoThumbnailExtractorProvider.overrideWithValue(
        thumbs ?? const _SilentThumbnails(),
      ),
    ],
  );
  container.listen(createChroniqueControllerProvider, (_, __) {});
  return container;
}

class _SilentThumbnails implements ChroniqueVideoThumbnailExtractor {
  const _SilentThumbnails();

  @override
  Future<String?> extractJpeg({required String videoPath}) async => null;
}

class _ImmediateThumbnails implements ChroniqueVideoThumbnailExtractor {
  const _ImmediateThumbnails(this.path);

  final String path;

  @override
  Future<String?> extractJpeg({required String videoPath}) async => path;
}

class _QueuedThumbnails implements ChroniqueVideoThumbnailExtractor {
  final List<Completer<String?>> pending = [];
  final List<String> videoPaths = [];

  @override
  Future<String?> extractJpeg({required String videoPath}) {
    videoPaths.add(videoPath);
    final completer = Completer<String?>();
    pending.add(completer);
    return completer.future;
  }
}

MediaDraft _video({
  required int id,
  String name = 'clip.mp4',
  int bytes = 4096,
  String path = '/tmp/clip.mp4',
  String? thumbnailPath,
}) {
  return MediaDraft(
    id: id,
    kind: MediaDraftKind.video,
    sourceType: MediaDraftSourceType.gallery,
    fileName: name,
    byteSize: bytes,
    localPath: path,
    localThumbnailPath: thumbnailPath,
    contentType: 'video/mp4',
  );
}

const MediaPickSelected _videoPick = MediaPickSelected(
  kind: MediaDraftKind.video,
  sourceType: MediaDraftSourceType.gallery,
  fileName: 'clip.mp4',
  byteSize: 4096,
  localPath: '/tmp/clip.mp4',
  contentType: 'video/mp4',
);

Future<void> _flushMicrotasks() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

MediaDraft _image({
  required int id,
  String name = 'photo.jpg',
  int bytes = 1024,
  String mime = 'image/jpeg',
  String path = '/tmp/photo.jpg',
}) {
  return MediaDraft(
    id: id,
    kind: MediaDraftKind.image,
    sourceType: MediaDraftSourceType.gallery,
    fileName: name,
    byteSize: bytes,
    localPath: path,
    contentType: mime,
  );
}

void _add(CreateChroniqueController controller, MediaDraft media) {
  controller.addMediaDraft(
    kind: media.kind,
    sourceType: media.sourceType,
    fileName: media.fileName,
    byteSize: media.byteSize,
    localPath: media.localPath,
    localThumbnailPath: media.localThumbnailPath,
    contentType: media.contentType,
  );
}

void main() {
  const body = 'Le texte de la chronique, d au moins vingt caracteres.';

  test('MIME allowlist follows backend kinds and extensions', () {
    expect(
      resolveChroniqueMediaContentType(kind: MediaDraftKind.image, fileName: 'a.jpg'),
      'image/jpeg',
    );
    expect(
      resolveChroniqueMediaContentType(
        kind: MediaDraftKind.image,
        fileName: 'a.png',
        platformMime: 'image/png',
      ),
      'image/png',
    );
    expect(
      resolveChroniqueMediaContentType(kind: MediaDraftKind.image, fileName: 'a.gif'),
      isNull,
    );
    expect(
      resolveChroniqueMediaContentType(
        kind: MediaDraftKind.image,
        fileName: 'a.jpg',
        platformMime: 'image/gif',
      ),
      isNull,
    );
    expect(
      resolveChroniqueMediaContentType(kind: MediaDraftKind.document, fileName: 'x.pdf'),
      'application/pdf',
    );
    expect(
      resolveChroniqueMediaContentType(kind: MediaDraftKind.audio, fileName: 'x.mp3'),
      'audio/mpeg',
    );
    expect(
      resolveChroniqueMediaContentType(kind: MediaDraftKind.video, fileName: 'clip.mov'),
      'video/quicktime',
    );
    expect(
      resolveChroniqueMediaContentType(kind: MediaDraftKind.video, fileName: 'camera.mp4'),
      'video/mp4',
    );
    expect(
      resolveChroniqueMediaContentType(kind: MediaDraftKind.audio, fileName: 'mic.m4a'),
      'audio/mp4',
    );
    expect(isChroniqueContentTypeAllowed(MediaDraftKind.image, 'image/webp'), isTrue);
    expect(isChroniqueContentTypeAllowed(MediaDraftKind.image, 'image/gif'), isFalse);
  });

  test('upload session JSON maps media id and signed PUT target', () {
    final session = ChroniqueMediaUploadSession.fromJson({
      'media': {
        'id': 9,
        'kind': 'image',
        'content_type': 'image/jpeg',
        'byte_size': 12,
        'status': 'pending_upload',
        'original_filename': 'a.jpg',
      },
      'upload': {
        'method': 'PUT',
        'url': 'https://signed.example/put',
        'headers': {'Content-Type': 'image/jpeg'},
        'expires_at': '2026-09-24T12:00:00.000Z',
      },
    });
    expect(session.media.id, 9);
    expect(session.method, 'PUT');
    expect(session.url, 'https://signed.example/put');
    expect(session.headers['Content-Type'], 'image/jpeg');
  });

  test('upload session JSON maps optional thumbnail PUT target', () {
    final session = ChroniqueMediaUploadSession.fromJson({
      'media': {
        'id': 4,
        'kind': 'video',
        'content_type': 'video/mp4',
        'byte_size': 12,
        'status': 'pending_upload',
      },
      'upload': {
        'method': 'PUT',
        'url': 'https://signed.example/put-video',
        'headers': {'Content-Type': 'video/mp4'},
      },
      'thumbnail_upload': {
        'method': 'PUT',
        'url': 'https://signed.example/put-thumb',
        'headers': {'Content-Type': 'image/jpeg'},
      },
    });
    expect(session.thumbnailUrl, 'https://signed.example/put-thumb');
    expect(session.thumbnailMethod, 'PUT');
    expect(session.thumbnailHeaders?['Content-Type'], 'image/jpeg');
  });

  test('text-only publish does not start the media pipeline', () async {
    final api = _Api();
    final put = _PutClient();
    final container = _container(api: api, put: put);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    await controller.publish(body: body);
    expect(api.createCalls, 1);
    expect(api.initCalls, 0);
    expect(put.putCalls, 0);
    expect(api.completeCalls, 0);
  });

  test('one image runs init, PUT, complete then marked uploaded', () async {
    final api = _Api();
    final put = _PutClient();
    final container = _container(api: api, put: put);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    _add(controller, _image(id: 0));
    await controller.publish(body: body);
    expect(api.createCalls, 1);
    expect(api.initCalls, 1);
    expect(put.putCalls, 1);
    expect(api.completeCalls, 1);
    expect(api.lastUploadPayload?['kind'], 'image');
    expect(api.lastUploadPayload?['content_type'], 'image/jpeg');
    expect(api.lastUploadPayload?.containsKey('storage_key'), isFalse);
    expect(api.lastUploadPayload?.containsKey('user_id'), isFalse);
    expect(put.urls.single, startsWith('https://signed.example/'));
    expect(put.headers.single.containsKey('Authorization'), isFalse);
    final media = container.read(createChroniqueControllerProvider).medias.single;
    expect(media.status, MediaDraftStatus.uploaded);
    expect(media.uploadProgress, 100);
  });

  test('camera image upload sends source_type camera without JWT on PUT', () async {
    final api = _Api();
    final put = _PutClient();
    final container = _container(api: api, put: put);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    controller.addMediaDraft(
      kind: MediaDraftKind.image,
      sourceType: MediaDraftSourceType.camera,
      fileName: 'camera.jpg',
      byteSize: 1024,
      localPath: '/tmp/camera.jpg',
      contentType: 'image/jpeg',
    );
    await controller.publish(body: body);
    expect(api.initCalls, 1);
    expect(api.lastUploadPayload?['kind'], 'image');
    expect(api.lastUploadPayload?['source_type'], 'camera');
    expect(put.putCalls, 1);
    expect(put.headers.single.containsKey('Authorization'), isFalse);
  });

  test('camera video upload sends source_type camera without JWT on PUT', () async {
    final api = _Api();
    final put = _PutClient();
    final container = _container(api: api, put: put);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    controller.addMediaDraft(
      kind: MediaDraftKind.video,
      sourceType: MediaDraftSourceType.camera,
      fileName: 'camera.mp4',
      byteSize: 8192,
      localPath: '/tmp/camera.mp4',
      contentType: 'video/mp4',
    );
    await controller.publish(body: body);
    expect(api.initCalls, 1);
    expect(api.lastUploadPayload?['kind'], 'video');
    expect(api.lastUploadPayload?['source_type'], 'camera');
    expect(api.lastUploadPayload?['content_type'], 'video/mp4');
    expect(put.putCalls, 1);
    expect(put.headers.single.containsKey('Authorization'), isFalse);
  });

  test('microphone audio upload sends source_type microphone without JWT on PUT', () async {
    final api = _Api();
    final put = _PutClient();
    final container = _container(api: api, put: put);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    controller.addMediaDraft(
      kind: MediaDraftKind.audio,
      sourceType: MediaDraftSourceType.microphone,
      fileName: 'mic.m4a',
      byteSize: 2048,
      localPath: '/tmp/mic.m4a',
      contentType: 'audio/mp4',
    );
    await controller.publish(body: body);
    expect(api.initCalls, 1);
    expect(api.lastUploadPayload?['kind'], 'audio');
    expect(api.lastUploadPayload?['source_type'], 'microphone');
    expect(api.lastUploadPayload?['content_type'], 'audio/mp4');
    expect(put.putCalls, 1);
    expect(put.headers.single.containsKey('Authorization'), isFalse);
  });

  test('several media are uploaded sequentially', () async {
    final api = _Api();
    final put = _PutClient();
    final container = _container(api: api, put: put);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    _add(controller, _image(id: 0, name: 'a.jpg', path: '/tmp/a.jpg'));
    _add(
      controller,
      const MediaDraft(
        id: 0,
        kind: MediaDraftKind.document,
        sourceType: MediaDraftSourceType.upload,
        fileName: 'notes.pdf',
        byteSize: 2048,
        localPath: '/tmp/notes.pdf',
        contentType: 'application/pdf',
      ),
    );
    await controller.publish(body: body);
    expect(api.initCalls, 2);
    expect(put.putCalls, 2);
    expect(api.completeCalls, 2);
    expect(
      container.read(createChroniqueControllerProvider).medias.every((m) => m.isUploaded),
      isTrue,
    );
  });

  test('oversized quota is rejected before POST /chroniques', () async {
    final api = _Api();
    final container = _container(api: api);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    _add(controller, _image(id: 0, bytes: kChroniqueMaxMediaBytes + 1));
    await expectLater(
      controller.publish(body: body),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          kMediaQuotaExceededMessage,
        ),
      ),
    );
    expect(api.createCalls, 0);
  });

  test('more than 5 media is rejected before POST /chroniques', () async {
    final api = _Api();
    final container = _container(api: api);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    for (var i = 0; i < 6; i++) {
      _add(controller, _image(id: 0, name: 'p$i.jpg', path: '/tmp/p$i.jpg', bytes: 1));
    }
    await expectLater(
      controller.publish(body: body),
      throwsA(
        isA<ApiException>().having((e) => e.message, 'message', kTooManyMediaMessage),
      ),
    );
    expect(api.createCalls, 0);
    expect(container.read(createChroniqueControllerProvider).medias, hasLength(6));
  });

  test('five mixed media are accepted at the count limit', () async {
    final api = _Api();
    final put = _PutClient();
    final container = _container(api: api, put: put);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    _add(controller, _image(id: 0, name: 'a.jpg', path: '/tmp/a.jpg', bytes: 10));
    controller.addMediaDraft(
      kind: MediaDraftKind.video,
      sourceType: MediaDraftSourceType.gallery,
      fileName: 'b.mp4',
      byteSize: 20,
      localPath: '/tmp/b.mp4',
      contentType: 'video/mp4',
    );
    controller.addMediaDraft(
      kind: MediaDraftKind.audio,
      sourceType: MediaDraftSourceType.upload,
      fileName: 'c.mp3',
      byteSize: 30,
      localPath: '/tmp/c.mp3',
      contentType: 'audio/mpeg',
    );
    controller.addMediaDraft(
      kind: MediaDraftKind.document,
      sourceType: MediaDraftSourceType.upload,
      fileName: 'd.pdf',
      byteSize: 40,
      localPath: '/tmp/d.pdf',
      contentType: 'application/pdf',
    );
    _add(controller, _image(id: 0, name: 'e.jpg', path: '/tmp/e.jpg', bytes: 50));
    await controller.publish(body: body);
    expect(api.createCalls, 1);
    expect(api.initCalls, 5);
    expect(put.putCalls, 5);
    expect(container.read(createChroniqueControllerProvider).medias, hasLength(5));
  });

  test('exactly 200 MiB is accepted', () async {
    final api = _Api();
    final put = _PutClient();
    final container = _container(api: api, put: put);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    _add(controller, _image(id: 0, bytes: kChroniqueMaxMediaBytes));
    await controller.publish(body: body);
    expect(api.createCalls, 1);
    expect(put.putCalls, 1);
  });

  test('inaccessible file is rejected before POST /chroniques', () async {
    final api = _Api();
    final container = _container(api: api, files: _FileAccess(readable: false));
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    _add(controller, _image(id: 0));
    await expectLater(
      controller.publish(body: body),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Le fichier est inaccessible',
        ),
      ),
    );
    expect(api.createCalls, 0);
  });

  test('unsupported MIME is rejected before POST /chroniques', () async {
    final api = _Api();
    final container = _container(api: api);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    _add(controller, _image(id: 0, mime: 'image/gif'));
    await expectLater(
      controller.publish(body: body),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Ce type de fichier n\'est pas pris en charge',
        ),
      ),
    );
    expect(api.createCalls, 0);
  });

  test('failed upload init marks media failed and does not PUT', () async {
    final api = _Api()
      ..failInit = const ApiException(message: 'content_type is invalid', statusCode: 400);
    final put = _PutClient();
    final container = _container(api: api, put: put);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    _add(controller, _image(id: 0));
    await expectLater(
      controller.publish(body: body),
      throwsA(
        isA<ApiException>().having((e) => e.message, 'message', kPartialMediaUploadMessage),
      ),
    );
    expect(api.createCalls, 1);
    expect(api.initCalls, 1);
    expect(put.putCalls, 0);
    expect(api.completeCalls, 0);
    final media = container.read(createChroniqueControllerProvider).medias.single;
    expect(media.status, MediaDraftStatus.failed);
    expect(media.errorMessage, 'content_type is invalid');
    expect(container.read(createChroniqueControllerProvider).createdChroniqueId, 7);
  });

  test('failed PUT marks media failed and skips complete', () async {
    final api = _Api();
    final put = _PutClient()..failWith = const ApiException(message: kMediaUploadFailedMessage);
    final container = _container(api: api, put: put);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    _add(controller, _image(id: 0));
    await expectLater(controller.publish(body: body), throwsA(isA<ApiException>()));
    expect(api.initCalls, 1);
    expect(put.putCalls, 1);
    expect(api.completeCalls, 0);
    expect(
      container.read(createChroniqueControllerProvider).medias.single.status,
      MediaDraftStatus.failed,
    );
  });

  test('failed complete marks media failed after PUT', () async {
    final api = _Api()
      ..failComplete = const ApiException(message: 'Upload is incomplete', statusCode: 400);
    final put = _PutClient();
    final container = _container(api: api, put: put);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    _add(controller, _image(id: 0));
    await expectLater(controller.publish(body: body), throwsA(isA<ApiException>()));
    expect(put.putCalls, 1);
    expect(api.completeCalls, 1);
    expect(
      container.read(createChroniqueControllerProvider).medias.single.status,
      MediaDraftStatus.failed,
    );
  });

  test('first media success then second failure keeps the ready one', () async {
    final api = _Api()
      ..failInit = const ApiException(message: 'Too many media', statusCode: 400)
      ..failInitAt = 2;
    final put = _PutClient();
    final container = _container(api: api, put: put);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    _add(controller, _image(id: 0, name: 'one.jpg', path: '/tmp/one.jpg'));
    _add(controller, _image(id: 0, name: 'two.jpg', path: '/tmp/two.jpg'));
    await expectLater(controller.publish(body: body), throwsA(isA<ApiException>()));
    final medias = container.read(createChroniqueControllerProvider).medias;
    expect(medias[0].status, MediaDraftStatus.uploaded);
    expect(medias[1].status, MediaDraftStatus.failed);
    expect(put.putCalls, 1);
    expect(api.completeCalls, 1);
  });

  test('scheduled chronique still uploads media after create', () async {
    final api = _Api();
    final put = _PutClient();
    final container = _container(api: api, put: put);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    _add(controller, _image(id: 0));
    await controller.publish(
      body: body,
      publish: 'schedule',
      scheduledAt: '2026-09-25T10:00:00.000Z',
    );
    expect(api.createCalls, 1);
    expect(api.lastPublish, 'schedule');
    expect(api.lastScheduledAt, '2026-09-25T10:00:00.000Z');
    expect(api.initCalls, 1);
    expect(put.putCalls, 1);
    expect(api.completeCalls, 1);
  });

  test('already uploaded media is not sent again on retry', () async {
    final api = _Api();
    final put = _PutClient();
    final container = _container(api: api, put: put);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    _add(controller, _image(id: 0));
    await controller.publish(body: body);
    expect(api.createCalls, 1);
    expect(put.putCalls, 1);
    await controller.publish(body: body);
    expect(api.createCalls, 1);
    expect(put.putCalls, 1);
    expect(api.initCalls, 1);
  });

  test('create failure does not start media upload and keeps local drafts', () async {
    final api = _Api()
      ..failCreate = const ApiException(message: 'body is too short', statusCode: 400);
    final put = _PutClient();
    final container = _container(api: api, put: put);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    _add(controller, _image(id: 0));
    await expectLater(controller.publish(body: body), throwsA(isA<ApiException>()));
    expect(api.initCalls, 0);
    expect(put.putCalls, 0);
    expect(container.read(createChroniqueControllerProvider).medias, hasLength(1));
    expect(
      container.read(createChroniqueControllerProvider).medias.single.status,
      MediaDraftStatus.selected,
    );
  });

  test('video thumbnail PUT is optional and does not fail the media', () async {
    final api = _Api();
    final put = _PutClient()
      ..failAt = 2
      ..failWith = const ApiException(message: 'thumb put failed', statusCode: 400);
    final file = File('${Directory.systemTemp.path}/chronique-unit-thumb.png');
    await file.writeAsBytes(const [1, 2, 3, 4]);
    addTearDown(() {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });
    final container = _container(api: api, put: put);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    _add(
      controller,
      MediaDraft(
        id: 0,
        kind: MediaDraftKind.video,
        sourceType: MediaDraftSourceType.gallery,
        fileName: 'clip.mp4',
        byteSize: 4096,
        localPath: '/tmp/clip.mp4',
        localThumbnailPath: file.path,
        contentType: 'video/mp4',
      ),
    );
    await controller.publish(body: body);
    expect(api.completeCalls, 1);
    expect(put.putCalls, 2);
    expect(put.urls.last, startsWith('https://signed.example/thumb/'));
    expect(
      container.read(createChroniqueControllerProvider).medias.single.status,
      MediaDraftStatus.uploaded,
    );
  });

  test('video without generated thumbnail still completes after a single PUT', () async {
    final api = _Api();
    final put = _PutClient();
    final container = _container(api: api, put: put, thumbs: const _SilentThumbnails());
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    controller.addMediaDraft(
      kind: MediaDraftKind.video,
      sourceType: MediaDraftSourceType.camera,
      fileName: 'camera.mp4',
      byteSize: 8192,
      localPath: '/tmp/camera.mp4',
      contentType: 'video/mp4',
    );
    await controller.publish(body: body);
    expect(put.putCalls, 1);
    expect(api.completeCalls, 1);
    expect(
      container.read(createChroniqueControllerProvider).medias.single.status,
      MediaDraftStatus.uploaded,
    );
  });

  test('JPEG thumbnail is deleted after a successful PUT', () async {
    final api = _Api();
    final put = _PutClient();
    final files = _FileAccess();
    final file = File('${Directory.systemTemp.path}/chronique-thumb-ok.jpg');
    await file.writeAsBytes(const [1, 2, 3, 4]);
    addTearDown(() {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });
    final container = _container(api: api, put: put, files: files);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    _add(controller, _video(id: 0, thumbnailPath: file.path));
    await controller.publish(body: body);
    expect(put.putCalls, 2);
    expect(files.deleted, contains(file.path));
    expect(files.deleted, isNot(contains('/tmp/clip.mp4')));
    expect(
      container.read(createChroniqueControllerProvider).medias.single.localThumbnailPath,
      isNull,
    );
    expect(
      container.read(createChroniqueControllerProvider).medias.single.status,
      MediaDraftStatus.uploaded,
    );
  });

  test('JPEG thumbnail is deleted after a failed thumbnail PUT', () async {
    final api = _Api();
    final put = _PutClient()
      ..failAt = 2
      ..failWith = const ApiException(message: 'thumb put failed', statusCode: 400);
    final files = _FileAccess();
    final file = File('${Directory.systemTemp.path}/chronique-thumb-fail.jpg');
    await file.writeAsBytes(const [1, 2, 3, 4]);
    addTearDown(() {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });
    final container = _container(api: api, put: put, files: files);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    _add(controller, _video(id: 0, thumbnailPath: file.path));
    await controller.publish(body: body);
    expect(put.putCalls, 2);
    expect(files.deleted, contains(file.path));
    expect(
      container.read(createChroniqueControllerProvider).medias.single.status,
      MediaDraftStatus.uploaded,
    );
  });

  test('removing a video while extraction is in flight deletes the orphan JPEG', () async {
    final api = _Api();
    final files = _FileAccess();
    final thumbs = _QueuedThumbnails();
    final container = _container(api: api, files: files, thumbs: thumbs);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    await controller.applyMediaPick(_videoPick);
    final mediaId = container.read(createChroniqueControllerProvider).medias.single.id;
    expect(thumbs.pending, hasLength(1));
    controller.removeMediaDraft(mediaId);
    expect(container.read(createChroniqueControllerProvider).medias, isEmpty);
    thumbs.pending.single.complete('/tmp/orphan-thumb.jpg');
    await _flushMicrotasks();
    expect(container.read(createChroniqueControllerProvider).medias, isEmpty);
    expect(files.deleted, contains('/tmp/orphan-thumb.jpg'));
    expect(files.deleted, isNot(contains('/tmp/clip.mp4')));
  });

  test('clearDraft during extraction deletes the JPEG and ignores the stale task', () async {
    final api = _Api();
    final files = _FileAccess();
    final thumbs = _QueuedThumbnails();
    final container = _container(api: api, files: files, thumbs: thumbs);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    await controller.applyMediaPick(_videoPick);
    expect(thumbs.pending, hasLength(1));
    controller.clearDraft();
    expect(container.read(createChroniqueControllerProvider).medias, isEmpty);
    thumbs.pending.single.complete('/tmp/stale-thumb.jpg');
    await _flushMicrotasks();
    expect(container.read(createChroniqueControllerProvider).medias, isEmpty);
    expect(files.deleted, contains('/tmp/stale-thumb.jpg'));
  });

  test('stale extraction after clearDraft does not mutate the next draft', () async {
    final api = _Api();
    final files = _FileAccess();
    final thumbs = _QueuedThumbnails();
    final container = _container(api: api, files: files, thumbs: thumbs);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    await controller.applyMediaPick(_videoPick);
    final firstId = container.read(createChroniqueControllerProvider).medias.single.id;
    controller.clearDraft();
    await controller.applyMediaPick(
      const MediaPickSelected(
        kind: MediaDraftKind.video,
        sourceType: MediaDraftSourceType.gallery,
        fileName: 'next.mp4',
        byteSize: 4096,
        localPath: '/tmp/next.mp4',
        contentType: 'video/mp4',
      ),
    );
    final second = container.read(createChroniqueControllerProvider).medias.single;
    expect(second.id, isNot(firstId));
    expect(thumbs.pending, hasLength(2));
    thumbs.pending[0].complete('/tmp/old-thumb.jpg');
    await _flushMicrotasks();
    final afterStale = container.read(createChroniqueControllerProvider).medias.single;
    expect(afterStale.id, second.id);
    expect(afterStale.localPath, '/tmp/next.mp4');
    expect(afterStale.localThumbnailPath, isNull);
    expect(files.deleted, contains('/tmp/old-thumb.jpg'));
    thumbs.pending[1].complete('/tmp/new-thumb.jpg');
    await _flushMicrotasks();
    expect(
      container.read(createChroniqueControllerProvider).medias.single.localThumbnailPath,
      '/tmp/new-thumb.jpg',
    );
    expect(files.deleted, isNot(contains('/tmp/new-thumb.jpg')));
  });

  test('JPEG delete failure does not fail video publication', () async {
    final api = _Api();
    final put = _PutClient();
    final files = _FileAccess()..failDelete = true;
    final file = File('${Directory.systemTemp.path}/chronique-thumb-delete-fail.jpg');
    await file.writeAsBytes(const [1, 2, 3, 4]);
    addTearDown(() {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });
    final container = _container(api: api, put: put, files: files);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    _add(controller, _video(id: 0, thumbnailPath: file.path));
    await controller.publish(body: body);
    expect(api.completeCalls, 1);
    expect(
      container.read(createChroniqueControllerProvider).medias.single.status,
      MediaDraftStatus.uploaded,
    );
    expect(files.deleted, contains(file.path));
  });

  test('preview keeps the JPEG until remove or publish release', () async {
    final api = _Api();
    final files = _FileAccess();
    const thumbs = _ImmediateThumbnails('/tmp/preview-thumb.jpg');
    final container = _container(api: api, files: files, thumbs: thumbs);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    await controller.applyMediaPick(_videoPick);
    await _flushMicrotasks();
    expect(
      container.read(createChroniqueControllerProvider).medias.single.localThumbnailPath,
      '/tmp/preview-thumb.jpg',
    );
    expect(files.deleted, isEmpty);
    controller.removeMediaDraft(
      container.read(createChroniqueControllerProvider).medias.single.id,
    );
    await _flushMicrotasks();
    expect(files.deleted, contains('/tmp/preview-thumb.jpg'));
  });

  test('removeMediaDraft never deletes a source path even if it equals the thumbnail path', () async {
    final api = _Api();
    final files = _FileAccess();
    final container = _container(api: api, files: files);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    const shared = '/tmp/same-source-and-thumb.mp4';
    controller.addMediaDraft(
      kind: MediaDraftKind.video,
      sourceType: MediaDraftSourceType.gallery,
      fileName: 'same.mp4',
      byteSize: 4096,
      localPath: shared,
      localThumbnailPath: shared,
      contentType: 'video/mp4',
    );
    final id = container.read(createChroniqueControllerProvider).medias.single.id;
    controller.removeMediaDraft(id);
    await _flushMicrotasks();
    expect(files.deleted, isEmpty);
    expect(files.deleted, isNot(contains(shared)));
    expect(files.skippedDeletes, isEmpty);
  });

  test('in-flight thumbnail delete is aborted if the path is reattached', () async {
    final api = _Api();
    final files = _FileAccess()..deleteGate = Completer<void>();
    final container = _container(api: api, files: files);
    addTearDown(container.dispose);
    final controller = container.read(createChroniqueControllerProvider.notifier);
    const thumb = '/tmp/reattach-thumb.jpg';
    controller.addMediaDraft(
      kind: MediaDraftKind.video,
      sourceType: MediaDraftSourceType.gallery,
      fileName: 'clip.mp4',
      byteSize: 4096,
      localPath: '/tmp/reattach-clip.mp4',
      localThumbnailPath: thumb,
      contentType: 'video/mp4',
    );
    final firstId = container.read(createChroniqueControllerProvider).medias.single.id;
    controller.removeMediaDraft(firstId);
    var started = false;
    for (var i = 0; i < 20; i++) {
      if (files.startedDeletes.contains(thumb)) {
        started = true;
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }
    expect(started, isTrue);
    expect(files.deleted, isEmpty);
    controller.addMediaDraft(
      kind: MediaDraftKind.video,
      sourceType: MediaDraftSourceType.gallery,
      fileName: 'next.mp4',
      byteSize: 4096,
      localPath: '/tmp/reattach-next.mp4',
      localThumbnailPath: thumb,
      contentType: 'video/mp4',
    );
    expect(
      container.read(createChroniqueControllerProvider).medias.single.localThumbnailPath,
      thumb,
    );
    files.deleteGate!.complete();
    await _flushMicrotasks();
    expect(files.deleted, isNot(contains(thumb)));
    expect(files.skippedDeletes, contains(thumb));
    expect(
      container.read(createChroniqueControllerProvider).medias.single.localThumbnailPath,
      thumb,
    );
  });

  test('Flutter sources do not embed R2 credentials', () {
    final root = Directory('lib');
    expect(root.existsSync(), isTrue);
    final forbidden = [
      'R2_SECRET_ACCESS_KEY',
      'R2_ACCESS_KEY_ID',
      'R2_ACCOUNT_ID',
      'CLOUDFLARE_API_TOKEN',
      'aws_secret_access_key',
    ];
    for (final file in root.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) {
        continue;
      }
      final source = file.readAsStringSync();
      for (final needle in forbidden) {
        expect(source.contains(needle), isFalse, reason: '${file.path} contains $needle');
      }
    }
  });
}
