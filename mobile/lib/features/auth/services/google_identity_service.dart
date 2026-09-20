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

  /// Ne pas appeler [GoogleSignIn.signOut] avant [GoogleSignIn.signIn] :
  /// sur Android le premier clic échoue souvent (erreur plateforme / id_token
  /// manquant) alors que le second réussit. Google peut réutiliser une session
  /// déjà autorisée sans nouvel écran de consentement.
  Future<GoogleIdentityResult> signIn() async {
    final clientId = serverClientId?.trim();
    if (clientId == null || clientId.isEmpty) {
      debugPrint('[google-identity] Google Sign-In is not configured');
      return const GoogleIdentityFailure('Google Sign-In is not configured');
    }

    debugPrint(
      '[google-identity] signIn() start configured=true clientIdLength=${clientId.length}',
    );

    try {
      GoogleSignInAccount? account;
      try {
        account = await _plugin.signInSilently();
        debugPrint('[google-identity] silent hasAccount=${account != null}');
      } catch (error) {
        debugPrint(
          '[google-identity] silent skipped runtimeType=${error.runtimeType}',
        );
        account = null;
      }

      if (account == null) {
        debugPrint('[google-identity] interactive signIn()');
        account = await _plugin.signIn();
      }

      if (account == null) {
        debugPrint('[google-identity] Google Sign-In canceled');
        return const GoogleIdentityCanceled();
      }

      var authentication = await account.authentication;
      var idToken = authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        debugPrint('[google-identity] id_token missing after sign-in, silent retry');
        try {
          account = await _plugin.signInSilently();
        } catch (error) {
          debugPrint(
            '[google-identity] silent retry skipped runtimeType=${error.runtimeType}',
          );
        }
        if (account != null) {
          authentication = await account.authentication;
          idToken = authentication.idToken;
        }
      }

      if (idToken == null || idToken.isEmpty) {
        debugPrint('[google-identity] Google Sign-In missing id_token');
        return const GoogleIdentityFailure('Google id_token is missing');
      }

      final email = account.email.trim().isEmpty ? null : account.email.trim();
      final displayName = account.displayName?.trim();
      debugPrint('[google-identity] signIn() success hasEmail=${email != null}');
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
