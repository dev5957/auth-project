# mobile

Squelette Flutter du client Auth. Aucun écran métier et aucune logique Auth complète pour l’instant.

## Architecture

```
lib/
  core/           infrastructure (config, HTTP, stockage)
  features/auth/  module Auth (models, services, repositories, providers)
  main.dart
```

Couches prévues :

1. **config** — URL de l’API, timeouts.
2. **network** — client HTTP (Dio). Les interceptors Bearer / refresh 401 viendront plus tard.
3. **storage** — persistance sécurisée des tokens.
4. **services** — appels `/auth/*` (non implémentés).
5. **repositories** — orchestration session (non implémentée).
6. **providers** — injection Riverpod.
7. **screens** — vide jusqu’à la prochaine étape.

Le backend vit dans `../backend`. Contrat : `../backend/docs/auth-api.md`.

## Choix techniques

| Besoin | Package | Pourquoi |
|---|---|---|
| HTTP | `dio` | Interceptors pour `Authorization` et refresh 401, sans `BuildContext`. |
| Tokens | `flutter_secure_storage` | Keychain (iOS) / Keystore (Android). Le `refresh_token` doit survivre au kill de l’app. |
| État | `flutter_riverpod` | Session globale, lisible depuis un interceptor, testable. Moins de boilerplate que Bloc à ce stade ; plus adapté que `Provider` pour un client HTTP hors widget. |

Google Sign-In et Sign in with Apple ne sont **pas** ajoutés dans cette étape.

## URL de l’API

Par défaut : `http://127.0.0.1:3000`.

Surcharge à la compilation :

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

- Émulateur Android : `http://10.0.2.2:3000` (`localhost` du host).
- Simulateur iOS : `http://127.0.0.1:3000`.
- Appareil physique : IP LAN de la machine qui héberge le backend.

## Générer les dossiers plateforme

Ce dépôt ne versionne que le code Dart du squelette. Pour Android / iOS :

```bash
cd mobile
flutter create . --project-name mobile --org com.authproject
```
