import 'auth_session.dart';
import 'session_tokens.dart';

/// Résultat de `POST /auth/google/start`. Pas une session [AuthState].
sealed class GoogleStartResult {
  const GoogleStartResult();
}

/// Compte Google déjà dans `users`. Tokens uniquement — pas de `user`.
final class GoogleStartExisting extends GoogleStartResult {
  const GoogleStartExisting({
    required this.message,
    required this.tokens,
  });

  final String message;
  final SessionTokens tokens;

  @override
  String toString() => 'GoogleStartExisting(message: $message, tokens: (omitted))';
}

/// Identité Google valide, profil application incomplet. Pas une erreur.
final class GoogleStartPending extends GoogleStartResult {
  const GoogleStartPending({
    required this.email,
    required this.oauthVerificationToken,
  });

  final String email;
  final String oauthVerificationToken;

  @override
  String toString() => 'GoogleStartPending(email: $email, token: (omitted))';
}

/// Suite repository / controller après Google Sign-In.
sealed class ContinueWithGoogleResult {
  const ContinueWithGoogleResult();
}

final class ContinueWithGoogleAuthenticated extends ContinueWithGoogleResult {
  const ContinueWithGoogleAuthenticated({required this.session});

  final AuthSession session;

  @override
  String toString() => 'ContinueWithGoogleAuthenticated(user: ${session.user.login})';
}

final class ContinueWithGooglePending extends ContinueWithGoogleResult {
  const ContinueWithGooglePending({
    required this.email,
    required this.oauthVerificationToken,
  });

  final String email;
  final String oauthVerificationToken;

  @override
  String toString() => 'ContinueWithGooglePending(email: $email, token: (omitted))';
}

final class ContinueWithGoogleCanceled extends ContinueWithGoogleResult {
  const ContinueWithGoogleCanceled();
}
