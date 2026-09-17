import '../models/auth_account.dart';

/// État de session pour la future UI. Pas d’écran ici.
sealed class AuthState {
  const AuthState();
}

/// Restauration ou opération session en cours.
final class AuthLoading extends AuthState {
  const AuthLoading();
}

/// `refreshSession` / `login` a réussi. [user] vient du backend (pas les jetons).
final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.user});

  final AuthAccount user;
}

/// Pas de session, pas de refresh_token, refresh en échec, ou logout.
final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}
