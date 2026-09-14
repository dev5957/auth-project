# mobile

Squelette Flutter du client Auth. Couche HTTP locale + session implémentée. Aucun écran métier, pas de Google / Apple.

## Architecture

```
lib/
  core/           infrastructure (config, HTTP, stockage)
  features/auth/  module Auth (models, services, repositories, providers)
  main.dart
```

Couches :

1. **config** — URL de l’API, timeouts (`API_BASE_URL`).
2. **network** — Dio JSON + mapping `{ "error": "..." }` → `ApiException`.
3. **storage** — `flutter_secure_storage` (access + refresh).
4. **services** — `AuthApiService` : register/start, register/verify-phone, login, me, refresh, logout.
5. **repositories** — persiste les jetons après login/refresh, les lit pour me/refresh/logout.
6. **providers** — injection Riverpod.
7. **screens** — vide.

Le backend vit dans `../backend`. Contrat : `../backend/docs/auth-api.md`.

## Choix techniques

| Besoin | Package | Pourquoi |
|---|---|---|
| HTTP | `dio` | Interceptors d’erreur, headers Bearer par requête protégée. |
| Tokens | `flutter_secure_storage` | Keychain / Keystore. |
| État | `flutter_riverpod` | Injection de `AuthRepository`. |

Google Sign-In et Sign in with Apple ne sont **pas** ajoutés.

## Tester la communication Flutter ↔ backend

1. Démarrer l’API :

```bash
cd backend
# JWT_SECRET, DATABASE_URL, SMS_PROVIDER=mock dans l’environnement
npm start
```

2. Générer les dossiers plateforme si besoin, puis un binaire Dart (pas d’écran Auth) :

```bash
cd mobile
flutter create . --project-name mobile --org com.authproject
flutter pub get
```

3. URL :

- Desktop / simulateur iOS : `http://127.0.0.1:3000` (défaut)
- Émulateur Android : `--dart-define=API_BASE_URL=http://10.0.2.2:3000`
- Appareil physique : IP LAN du host

4. Exercer la couche (depuis un test ou un snippet temporaire), via `authRepositoryProvider` :

- `startRegister` → `POST /auth/register/start` → `verification_token`
- `verifyRegisterPhone` → `POST /auth/register/verify-phone` → `user` (pas de JWT)
- `login` → `POST /auth/login` → stocke `access_token` + `refresh_token`
- `me` → `GET /auth/me` avec Bearer
- `refreshSession` → `POST /auth/refresh` (rotation, anciens jetons remplacés en stockage ; 401 purge locale)
- `logout` → Bearer + `{ refresh_token }` puis purge locale

Les erreurs backend arrivent en `ApiException.message` (ex. `Invalid credentials`).

Le refresh automatique sur 401 n’est **pas** encore branché : appeler `refreshSession()` explicitement.

## Générer les dossiers plateforme

```bash
cd mobile
flutter create . --project-name mobile --org com.authproject
```
