import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/chronique/media/chronique_document_file.dart';
import 'package:mobile/features/chronique/models/chronique.dart';
import 'package:mobile/features/chronique/services/chronique_document_open_service.dart';
import 'package:mobile/features/chronique/services/chronique_document_read_client.dart';

ChroniqueMedia _doc({
  required int id,
  String? readUrl = 'https://example.test/rapport.docx',
  String? status = 'ready',
  String contentType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  String? originalFilename = 'rapport.docx',
}) {
  return ChroniqueMedia.fromJson({
    'id': id,
    'kind': 'document',
    'status': status,
    'sort_order': 0,
    if (readUrl != null) 'read_url': readUrl,
    'content_type': contentType,
    if (originalFilename != null) 'original_filename': originalFilename,
  });
}

class _FakeReadClient extends ChroniqueDocumentReadClient {
  _FakeReadClient() : super(dio: Dio());

  String? lastUrl;
  String? lastPath;
  int calls = 0;
  bool fail = false;

  @override
  Future<void> downloadToFile({
    required String url,
    required String savePath,
  }) async {
    calls += 1;
    lastUrl = url;
    lastPath = savePath;
    if (fail) {
      throw const ApiException(message: kChroniqueDocumentRetrieveFailedMessage);
    }
    await File(savePath).writeAsBytes(const [1, 2, 3]);
  }
}

class _CaptureAdapter implements HttpClientAdapter {
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromBytes(const [1, 2, 3], 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('chronique_docs_test_');
  });

  tearDown(() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  test('GET uses exact read_url without Authorization', () async {
    final adapter = _CaptureAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = ChroniqueDocumentReadClient(dio: dio);
    final save = File('${root.path}${Platform.pathSeparator}out.bin');
    await client.downloadToFile(url: 'https://example.test/signed.docx', savePath: save.path);
    expect(adapter.last?.uri.toString(), 'https://example.test/signed.docx');
    expect(adapter.last?.method, 'GET');
    expect(adapter.last?.headers['Authorization'], isNull);
    expect(adapter.last?.headers['authorization'], isNull);
    expect(save.existsSync(), isTrue);
  });

  test('open service downloads then opens with mime and safe path', () async {
    final read = _FakeReadClient();
    String? openedPath;
    String? openedMime;
    final service = ChroniqueDocumentOpenService(
      readClient: read,
      cacheRoot: () async => root,
      openFile: (path, mime) async {
        openedPath = path;
        openedMime = mime;
        return true;
      },
    );
    final outcome = await service.open(
      _doc(id: 4, readUrl: 'https://example.test/rapport.docx'),
    );
    expect(outcome, ChroniqueDocumentOpenOutcome.opened);
    expect(read.calls, 1);
    expect(read.lastUrl, 'https://example.test/rapport.docx');
    expect(read.lastUrl!.contains('Authorization'), isFalse);
    expect(openedMime, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
    expect(openedPath, endsWith('${Platform.pathSeparator}chronique_docs${Platform.pathSeparator}4_rapport.docx'));
    expect(openedPath!.contains('..'), isFalse);
    expect(File(openedPath!).existsSync(), isTrue);
    expect(
      chroniqueDocumentPathIsInside(
        Directory('${root.path}${Platform.pathSeparator}$kChroniqueDocsCacheFolder').path,
        openedPath!,
      ),
      isTrue,
    );
  });

  test('GET failure does not open', () async {
    final read = _FakeReadClient()..fail = true;
    var opened = 0;
    final service = ChroniqueDocumentOpenService(
      readClient: read,
      cacheRoot: () async => root,
      openFile: (_, __) async {
        opened += 1;
        return true;
      },
    );
    final outcome = await service.open(_doc(id: 1));
    expect(outcome, ChroniqueDocumentOpenOutcome.retrieveFailed);
    expect(opened, 0);
  });

  test('opener failure is reported', () async {
    final service = ChroniqueDocumentOpenService(
      readClient: _FakeReadClient(),
      cacheRoot: () async => root,
      openFile: (_, __) async => false,
    );
    expect(await service.open(_doc(id: 1)), ChroniqueDocumentOpenOutcome.openFailed);
  });

  test('pdf doc txt mime mapping', () async {
    String? mime;
    final service = ChroniqueDocumentOpenService(
      readClient: _FakeReadClient(),
      cacheRoot: () async => root,
      openFile: (_, value) async {
        mime = value;
        return true;
      },
    );
    await service.open(
      _doc(id: 1, contentType: 'application/pdf', originalFilename: 'a.pdf', readUrl: 'https://example.test/a.pdf'),
    );
    expect(mime, 'application/pdf');
    await service.open(
      _doc(id: 2, contentType: 'application/msword', originalFilename: 'b.doc', readUrl: 'https://example.test/b.doc'),
    );
    expect(mime, 'application/msword');
    await service.open(
      _doc(id: 3, contentType: 'text/plain', originalFilename: 'c.txt', readUrl: 'https://example.test/c.txt'),
    );
    expect(mime, 'text/plain');
  });

  test('malicious filename stays inside chronique_docs', () async {
    String? path;
    final service = ChroniqueDocumentOpenService(
      readClient: _FakeReadClient(),
      cacheRoot: () async => root,
      openFile: (value, _) async {
        path = value;
        return true;
      },
    );
    await service.open(
      _doc(id: 9, originalFilename: '../rapport.docx'),
    );
    final docs = Directory('${root.path}${Platform.pathSeparator}$kChroniqueDocsCacheFolder');
    expect(path, '${docs.path}${Platform.pathSeparator}9_rapport.docx');
    expect(chroniqueDocumentPathIsInside(docs.path, path!), isTrue);
  });

  test('stale cache files are purged before a new open', () async {
    final docs = Directory('${root.path}${Platform.pathSeparator}$kChroniqueDocsCacheFolder');
    await docs.create(recursive: true);
    final stale = File('${docs.path}${Platform.pathSeparator}old.bin');
    await stale.writeAsBytes(const [9]);
    await stale.setLastModified(DateTime.now().subtract(const Duration(hours: 8)));
    final service = ChroniqueDocumentOpenService(
      readClient: _FakeReadClient(),
      cacheRoot: () async => root,
      openFile: (_, __) async => true,
    );
    await service.open(_doc(id: 1));
    expect(stale.existsSync(), isFalse);
  });
}
