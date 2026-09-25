import 'chronique_local_media_picker.dart';

/// Enregistrement micro local. Pas d’upload, pas d’API.
abstract class ChroniqueMicrophoneRecorder {
  Future<bool> hasPermission();

  Future<void> start();

  /// Fichier validé (taille + MIME) ou échec. Jamais une annulation.
  Future<MediaPickResult> stop();

  Future<void> discard();

  /// Le fichier est conservé pour le MediaDraft : ne plus le supprimer.
  void keep();

  Future<void> dispose();
}
