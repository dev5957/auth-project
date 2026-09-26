import 'dart:io';

/// Accès fichier local pour les contrôles UX avant upload. Pas de lecture du binaire ici.
abstract class ChroniqueLocalFileAccess {
  Future<bool> isReadable(String path);

  Future<int> lengthOf(String path);
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
}
