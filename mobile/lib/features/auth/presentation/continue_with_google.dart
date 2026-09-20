import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../models/google_start_result.dart';
import '../providers/auth_controller.dart';
import 'state/oauth_complete_flow_controller.dart';

/// Navigation UI après Google Sign-In. Pas de logique session ici.
Future<void> continueWithGoogleFromUi({
  required WidgetRef ref,
  required BuildContext context,
  required void Function(String message) onLocalError,
}) async {
  try {
    final result = await ref.read(authControllerProvider.notifier).continueWithGoogle();
    if (!context.mounted) {
      return;
    }
    switch (result) {
      case ContinueWithGoogleAuthenticated():
        context.go(AppRoutes.home);
      case ContinueWithGooglePending(
          :final email,
          :final oauthVerificationToken,
        ):
        ref.read(oauthCompleteFlowProvider.notifier).start(
              email: email,
              oauthVerificationToken: oauthVerificationToken,
            );
        context.push(AppRoutes.oauthComplete);
      case ContinueWithGoogleCanceled():
        debugPrint('[google-identity] Google Sign-In canceled');
    }
  } on ApiException catch (error) {
    if (!context.mounted) {
      return;
    }
    onLocalError(_googleContinueMessage(error));
  } on FormatException {
    if (!context.mounted) {
      return;
    }
    onLocalError('Unexpected error');
  }
}

String _googleContinueMessage(ApiException error) {
  final message = error.message.trim();
  if (message.isNotEmpty) {
    return message;
  }
  switch (error.statusCode) {
    case 401:
      return 'Incorrect login or password';
    case 403:
      return 'Phone number is not verified';
    case 429:
      return 'Too many requests';
    default:
      return 'Unexpected error';
  }
}
