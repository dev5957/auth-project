/// Persistance des jetons de session. Aucune règle métier (refresh, logout) ici.
abstract class TokenStorage {
  Future<void> saveAccessToken(String token);

  Future<void> saveRefreshToken(String token);

  Future<String?> readAccessToken();

  Future<String?> readRefreshToken();

  Future<void> clear();
}
