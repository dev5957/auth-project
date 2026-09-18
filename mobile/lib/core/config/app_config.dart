/// Configuration runtime du client (aucune logique métier).
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    this.googleServerClientId,
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 15),
  });

  /// Origin du backend Express, sans slash final.
  ///
  /// Émulateur Android : `http://10.0.2.2:3000`
  /// Simulateur iOS / desktop : `http://127.0.0.1:3000`
  /// Appareil physique : `http://<ip-lan>:3000`
  final String apiBaseUrl;

  /// Web OAuth Client ID (`aud` du id_token, même valeur que `GOOGLE_CLIENT_ID` backend).
  /// Compile-time : `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`.
  final String? googleServerClientId;
  final Duration connectTimeout;
  final Duration receiveTimeout;

  static const String defaultApiBaseUrl = 'http://127.0.0.1:3000';

  factory AppConfig.fromEnvironment() {
    const raw = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: defaultApiBaseUrl,
    );
    const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
    return AppConfig(
      apiBaseUrl: raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw,
      googleServerClientId:
          googleServerClientId.trim().isEmpty ? null : googleServerClientId.trim(),
    );
  }
}
