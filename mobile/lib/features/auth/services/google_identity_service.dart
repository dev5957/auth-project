import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Résultat de l’identité Google uniquement. Pas de session applicative.
sealed class GoogleIdentityResult {
  const GoogleIdentityResult();
}

final class GoogleIdentitySuccess extends GoogleIdentityResult {
  const GoogleIdentitySuccess({
    required this.idToken,
    this.email,
    this.displayName,
  });

  final String idToken;
  final String? email;
  final String? displayName;

  @override
  String toString() =>
      'GoogleIdentitySuccess(email: $email, displayName: $displayName, idToken: (omitted))';
}

final class GoogleIdentityCanceled extends GoogleIdentityResult {
  const GoogleIdentityCanceled();
}

final class GoogleIdentityFailure extends GoogleIdentityResult {
  const GoogleIdentityFailure(this.message);

  final String message;
}

/// Google Sign-In natif. Ne parle pas au backend ni à [AuthController].
class GoogleIdentityService {
  GoogleIdentityService({
    required this.serverClientId,
    GoogleSignIn? plugin,
  }) : _plugin = plugin ??
            GoogleSignIn(
              scopes: const <String>['email', 'openid', 'profile'],
              serverClientId: serverClientId,
            );

  /// Web Client ID OAuth. Obligatoire pour un `id_token` dont `aud` = backend.
  final String? serverClientId;
  final GoogleSignIn _plugin;

  Future<GoogleIdentityResult> signIn() async {
    final clientId = serverClientId?.trim();
    if (clientId == null || clientId.isEmpty) {
      debugPrint('[google-identity] Google Sign-In is not configured');
      return const GoogleIdentityFailure('Google Sign-In is not configured');
    }

    try {
      try {
        await _plugin.signOut();
      } catch (_) {
        // Continuer : l’écran de compte Google s’affichera quand même.
      }

      final account = await _plugin.signIn();
      if (account == null) {
        debugPrint('[google-identity] Google Sign-In canceled');
        return const GoogleIdentityCanceled();
      }

      final authentication = await account.authentication;
      final idToken = authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        debugPrint('[google-identity] Google Sign-In missing id_token');
        return const GoogleIdentityFailure('Google id_token is missing');
      }

      final email = account.email.trim().isEmpty ? null : account.email.trim();
      final displayName = account.displayName?.trim();
      return GoogleIdentitySuccess(
        idToken: idToken,
        email: email,
        displayName: (displayName == null || displayName.isEmpty) ? null : displayName,
      );
    } on PlatformException catch (error) {
      if (_isCanceled(error)) {
        debugPrint('[google-identity] Google Sign-In canceled');
        return const GoogleIdentityCanceled();
      }
      debugPrint(
        '[google-identity] Google Sign-In PlatformException code=${error.code}',
      );
      return GoogleIdentityFailure(_safePlatformMessage(error));
    } catch (error) {
      debugPrint(
        '[google-identity] Google Sign-In error.runtimeType=${error.runtimeType}',
      );
      return const GoogleIdentityFailure('Google Sign-In failed');
    }
  }

  static bool _isCanceled(PlatformException error) {
    final code = error.code.toLowerCase();
    return code.contains('cancel') || code == 'sign_in_canceled';
  }

  static String _safePlatformMessage(PlatformException error) {
    final message = error.message?.trim();
    if (message == null || message.isEmpty) {
      return 'Google Sign-In failed';
    }
    if (message.contains('.') && message.length > 80) {
      return 'Google Sign-In failed';
    }
    return message;
  }
}
