import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/chronique_correction_window.dart';

Future<bool> confirmArchiveChronique(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Archiver cette chronique ?'),
        content: const Text(
          'Elle sera retirée de Mon Fil\nmais conservée dans vos archives.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archiver'),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}

Future<bool> confirmDeleteChronique(
  BuildContext context, {
  required bool scheduled,
  bool fromArchives = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(
          fromArchives
              ? 'Supprimer cette Chronique ?'
              : scheduled
              ? 'Supprimer cette chronique programmée ?'
              : 'Supprimer cette chronique ?',
        ),
        content: Text(
          fromArchives
              ? 'Cette action supprimera cette publication de vos Archives. Elle ne pourra pas être récupérée.'
              : scheduled
              ? 'Elle sera retirée de À venir.'
              : 'Elle sera retirée de Mon Fil.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}

Future<bool> confirmDeleteChroniqueMedia(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Supprimer ce média ?'),
        content: const Text('Cette action supprimera ce média de la Chronique.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}

String messageForChroniqueApiError(ApiException error) {
  final message = error.message.trim();
  if (message == kCorrectionWindowExpiredCode) {
    return kCorrectionWindowExpiredUserMessage;
  }
  if (message.isNotEmpty) {
    return message;
  }
  switch (error.statusCode) {
    case 401:
      return 'Unauthorized';
    case 429:
      return 'Too many requests';
    default:
      return 'Unexpected error';
  }
}
