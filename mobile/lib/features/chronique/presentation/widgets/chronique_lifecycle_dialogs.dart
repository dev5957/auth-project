import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';

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
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(
          scheduled
              ? 'Supprimer cette chronique programmée ?'
              : 'Supprimer cette chronique ?',
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

String messageForChroniqueApiError(ApiException error) {
  final message = error.message.trim();
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
