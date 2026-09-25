import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/api_exception.dart';
import '../media/chronique_document_file.dart';
import '../models/chronique.dart';
import 'chronique_document_read_client.dart';

enum ChroniqueDocumentOpenOutcome {
  opened,
  retrieveFailed,
  openFailed,
}

typedef ChroniqueDocumentCacheDirectory = Future<Directory> Function();
typedef ChroniqueDocumentFileOpener = Future<bool> Function(String path, String mime);
typedef ChroniqueDocumentOpenHandler = Future<ChroniqueDocumentOpenOutcome> Function(
  ChroniqueMedia media,
);

Future<Directory> chroniqueDocumentDefaultCacheRoot() {
  return getTemporaryDirectory();
}

Future<bool> openChroniqueDocumentLocalFile(String path, String mime) async {
  final result = await OpenFilex.open(path, type: mime);
  return result.type == ResultType.done;
}

class ChroniqueDocumentOpenService {
  ChroniqueDocumentOpenService({
    ChroniqueDocumentReadClient? readClient,
    ChroniqueDocumentCacheDirectory? cacheRoot,
    ChroniqueDocumentFileOpener? openFile,
    Duration cacheMaxAge = kChroniqueDocsCacheMaxAge,
  })  : _readClient = readClient ?? ChroniqueDocumentReadClient(),
        _cacheRoot = cacheRoot ?? chroniqueDocumentDefaultCacheRoot,
        _openFile = openFile ?? openChroniqueDocumentLocalFile,
        _cacheMaxAge = cacheMaxAge;

  final ChroniqueDocumentReadClient _readClient;
  final ChroniqueDocumentCacheDirectory _cacheRoot;
  final ChroniqueDocumentFileOpener _openFile;
  final Duration _cacheMaxAge;

  Future<Directory> docsDirectory() async {
    final root = await _cacheRoot();
    final dir = Directory('${root.path}${Platform.pathSeparator}$kChroniqueDocsCacheFolder');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> purgeStale({DateTime? now}) async {
    try {
      final dir = await docsDirectory();
      if (!dir.existsSync()) {
        return;
      }
      final cutoff = (now ?? DateTime.now()).subtract(_cacheMaxAge);
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
          }
        } on Exception {
          // Purge best-effort : ne bloque pas l’ouverture.
        }
      }
    } on Exception {
      // Purge best-effort.
    }
  }

  File localFileFor(Directory docsDir, ChroniqueMedia media) {
    final name = chroniqueDocumentCacheFileName(media);
    final file = File('${docsDir.path}${Platform.pathSeparator}$name');
    if (!chroniqueDocumentPathIsInside(docsDir.path, file.path)) {
      return File(
        '${docsDir.path}${Platform.pathSeparator}${media.id ?? 0}_document.${chroniqueDocumentFileExtension(media)}',
      );
    }
    return file;
  }

  Future<ChroniqueDocumentOpenOutcome> open(ChroniqueMedia media) async {
    final url = media.readUrl?.trim();
    if (url == null || url.isEmpty) {
      return ChroniqueDocumentOpenOutcome.retrieveFailed;
    }
    await purgeStale();
    final docsDir = await docsDirectory();
    final file = localFileFor(docsDir, media);
    try {
      await _readClient.downloadToFile(url: url, savePath: file.path);
    } on ApiException {
      return ChroniqueDocumentOpenOutcome.retrieveFailed;
    } on Exception {
      return ChroniqueDocumentOpenOutcome.retrieveFailed;
    }
    final mime = chroniqueDocumentMime(media);
    if (mime == null) {
      return ChroniqueDocumentOpenOutcome.openFailed;
    }
    try {
      final opened = await _openFile(file.path, mime);
      if (!opened) {
        return ChroniqueDocumentOpenOutcome.openFailed;
      }
      return ChroniqueDocumentOpenOutcome.opened;
    } on Exception {
      return ChroniqueDocumentOpenOutcome.openFailed;
    }
  }
}
