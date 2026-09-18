import '../models/auth_account.dart';

/// État de session pour la future UI. Pas d’écran ici.
sealed class AuthState {
  const AuthState();
}

/// Restauration de session au cold start. Pas les soumissions de formulaire Login.
final class AuthLoading extends AuthState {
  const AuthLoading();
}

/// `refreshSession` / `login` a réussi. [user] vient du backend (pas les jetons).
final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.user});

  final AuthAccount user;
}

/// Pas de session (premier lancement, refresh invalide, ou logout).
/// Une erreur de formulaire Login ne doit pas passer par cet état.
final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}
