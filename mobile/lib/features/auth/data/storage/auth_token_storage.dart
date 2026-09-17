/// Persistance sécurisée des jetons de session. Aucune règle métier ici.
///
/// Ne jamais logger [access_token] ni [refresh_token].
abstract class AuthTokenStorage {
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  });

  Future<String?> readAccessToken();

  Future<String?> readRefreshToken();

  Future<void> clearTokens();

  Future<bool> hasRefreshToken();
}
