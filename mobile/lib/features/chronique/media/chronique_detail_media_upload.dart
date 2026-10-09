import '../../../core/network/api_exception.dart';
import '../models/chronique.dart';
import '../models/media_draft.dart';
import '../repositories/chronique_repository.dart';
import '../services/chronique_media_upload_client.dart';
import 'chronique_local_media_picker.dart';
import 'chronique_media_limits.dart';
import 'chronique_media_mime.dart';

/// PUT signé + complete pour un fichier déjà choisi. Pas le wizard de création.
Future<Chronique> uploadChroniquePickedMedia({
  required ChroniqueRepository repository,
  required ChroniqueMediaUploadClient uploadClient,
  required int chroniqueId,
  required MediaPickSelected pick,
}) async {
  final mime = pick.contentType ??
      resolveChroniqueMediaContentType(
        kind: pick.kind,
        fileName: pick.fileName,
        localPath: pick.localPath,
        platformMime: pick.platformMime,
      );
  if (mime == null || !isChroniqueContentTypeAllowed(pick.kind, mime)) {
    throw const ApiException(message: kMediaUnsupportedMessage, statusCode: 400);
  }
  if (pick.byteSize < 1 || pick.localPath.trim().isEmpty) {
    throw const ApiException(message: kMediaInaccessibleMessage, statusCode: 400);
  }
  if (pick.byteSize > kChroniqueMaxMediaBytes) {
    throw const ApiException(message: kMediaQuotaExceededMessage, statusCode: 400);
  }

  final draft = MediaDraft(
    id: 0,
    kind: pick.kind,
    sourceType: pick.sourceType,
    fileName: pick.fileName,
    byteSize: pick.byteSize,
    localPath: pick.localPath.trim(),
    contentType: mime,
  );
  final session = await repository.createMediaUpload(
    chroniqueId: chroniqueId,
    media: draft,
  );
  final mediaId = session.media.id;
  if (mediaId == null) {
    throw const ApiException(message: kMediaUploadFailedMessage, statusCode: 400);
  }
  await uploadClient.putFile(
    url: session.url,
    method: session.method,
    headers: session.headers,
    localPath: draft.localPath!,
    byteSize: pick.byteSize,
  );
  return repository.completeMediaUpload(
    chroniqueId: chroniqueId,
    mediaId: mediaId,
  );
}
