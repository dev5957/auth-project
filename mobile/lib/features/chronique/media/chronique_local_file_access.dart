import 'dart:io';

import 'package:flutter/foundation.dart';

/// Accès fichier local pour les contrôles UX avant upload. Pas de lecture du binaire ici.
abstract class ChroniqueLocalFileAccess {
  Future<bool> isReadable(String path);

  Future<int> lengthOf(String path);

  /// Suppression best-effort. Ne doit jamais faire échouer l’appelant métier.
  ///
  /// [ifStillUnused] est évalué juste avant l’unlink, y compris après un
  /// `await` interne, pour abandonner si le chemin a été réattaché.
  Future<void> deleteQuietly(String path, {bool Function()? ifStillUnused});
}

class IoChroniqueLocalFileAccess implements ChroniqueLocalFileAccess {
  const IoChroniqueLocalFileAccess();

  @override
  Future<bool> isReadable(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    try {
      final file = File(trimmed);
      if (!file.existsSync()) {
        return false;
      }
      return file.lengthSync() > 0;
    } on Exception {
      return false;
    }
  }

  @override
  Future<int> lengthOf(String path) async {
    try {
      return File(path).lengthSync();
    } on Exception {
      return 0;
    }
  }

  @override
  Future<void> deleteQuietly(String path, {bool Function()? ifStillUnused}) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return;
    }
    try {
      if (ifStillUnused != null && !ifStillUnused()) {
        return;
      }
      final file = File(trimmed);
      if (!file.existsSync()) {
        return;
      }
      file.deleteSync();
    } catch (error) {
      debugPrint('[chronique-video-thumb] temp jpeg delete failed');
    }
  }
}
