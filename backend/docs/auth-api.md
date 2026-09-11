# API d’authentification

Documentation des endpoints **implémentés** dans le backend. Les statuts et messages ci-dessous sont ceux renvoyés par le code actuel (`authController`, services, `errorHandler`).

Préfixe : `/auth`  
Corps : JSON (`Content-Type: application/json`)  
Limite globale : **32 Ko** → `413` `{ "error": "Payload too large" }`  
JSON invalide → `400` `{ "error": "Invalid JSON" }`  
Erreur inattendue → `500` `{ "error": "Internal server error" }`

Les erreurs métier ont la forme `{ "error": "<message>" }`.

---

## POST `/auth/register/start`

Démarre une inscription locale. Aucune ligne `users` n’est créée. Un code SMS est hashé (bcrypt) et stocké dans `phone_verifications` ; l’envoi dépend de `SMS_PROVIDER`.

**Rate limit :** 5 requêtes / 15 min / IP → `429` `{ "error": "Too many requests" }` (`Retry-After`).

### Corps

| Champ | Obligatoire | Notes |
|---|---|---|
| `email` | oui | trim + minuscules, max 254 |
| `login` | oui | trim + minuscules, max 64 |
| `phone_number` | oui | trim, espaces / tirets / parenthèses retirés, max 32 |
| `birth_date` | oui | chaîne non vide |
| `password` | oui | 8–72 caractères |
| `password_confirmation` | oui | doit égaler `password` |
| `first_name` | non | chaîne ou omis |
| `last_name` | non | chaîne ou omis |

### Succès — `201`

```json
{
  "message": "Verification code generated",
  "verification_token": "..."
}
```

Le code SMS n’est **pas** dans la réponse.

### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `email is required` |
| 400 | `email is invalid` |
| 400 | `login is required` |
| 400 | `login is invalid` |
| 400 | `phone_number is required` |
| 400 | `phone_number is invalid` |
| 400 | `birth_date is required` |
| 400 | `password is required` |
| 400 | `Password must be between 8 and 72 characters` |
| 400 | `password_confirmation is required` |
| 400 | `password and password_confirmation do not match` |
| 400 | `first_name and last_name must be strings when provided` |
| 409 | `Email is already in use` |
| 409 | `Login is already in use` |
| 409 | `Phone number is already in use` |
| 429 | `Too many requests` |
| 503 | `Database is not configured` |
| 503 | `SMS could not be sent` |

---

## POST `/auth/register/verify-phone`

Valide le code SMS puis crée `users` (`phone_verified = true`, `auth_provider = 'local'`). Consomme la vérification (`verified_at`).

**Rate limit :** 10 requêtes / 15 min / IP → `429` `{ "error": "Too many requests" }`.

### Corps

```json
{
  "verification_token": "...",
  "code": "000000"
}
```

### Succès — `201`

```json
{
  "message": "Account created",
  "user": {
    "id": 1,
    "email": "alex@example.com",
    "login": "alex",
    "phone_verified": true,
    "auth_provider": "local"
  }
}
```

Aucun JWT n’est émis.

### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `verification_token is required` |
| 400 | `code is required` |
| 400 | `Verification is no longer valid` |
| 400 | `Verification code has expired` |
| 400 | `Invalid verification code` |
| 400 | `Registration data is missing` |
| 400 | `Registration data is incomplete` |
| 404 | `Verification token not found` |
| 409 | `Email, login or phone number is already in use` |
| 429 | `Too many requests` |
| 429 | `Too many verification attempts` |
| 503 | `Database is not configured` |

---

## POST `/auth/login`

Connexion locale par `login` + `password`. Émet un access token JWT (~15 min) et un refresh token (~90 jours). Seul le hash du refresh token est stocké.

**Rate limit :** 10 requêtes / 15 min / IP → `429` `{ "error": "Too many requests" }`.

### Corps

```json
{
  "login": "alex",
  "password": "choose-a-strong-password"
}
```

`login` est trimé et mis en minuscules. Login inconnu et mot de passe incorrect renvoient le même message.

### Succès — `200`

```json
{
  "message": "Login successful",
  "access_token": "...",
  "refresh_token": "...",
  "user": {
    "id": 1,
    "login": "alex",
    "email": "alex@example.com",
    "auth_provider": "local"
  }
}
```

### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `login is required` |
| 400 | `password is required` |
| 401 | `Invalid credentials` |
| 403 | `Phone number is not verified` |
| 429 | `Too many requests` |
| 503 | `JWT_SECRET is not configured` |
| 503 | `Database is not configured` |

Un login trop long (> 64) ou un mot de passe > 72 caractères au login renvoient aussi **401** `Invalid credentials` (pas de 400).

---

## GET `/auth/profile`

Profil SQL de l’utilisateur authentifié. Identifiant : claim JWT `userId` (`req.user.userId`).

**Auth :** `Authorization: Bearer <access_token>`  
Pas de rate limit dédié.

### Succès — `200`

```json
{
  "user": {
    "id": 1,
    "login": "example",
    "email": "user@example.com",
    "phone_number": "+33600000000",
    "birth_date": "2000-01-01",
    "auth_provider": "local"
  }
}
```

Champs absents de la réponse : `password_hash`, refresh token, `token_hash`, `provider_user_id`, noms, horodatages internes.

### Erreurs

| HTTP | `error` |
|---|---|
| 401 | `Unauthorized` |
| 404 | `User not found` |
| 503 | `Database is not configured` |
| 503 | `JWT_SECRET is not configured` |
| 503 | `JWT is not configured` |

`401 Unauthorized` : header absent, format invalide, JWT expiré, mauvaise signature, mauvais `iss` / `aud`, algorithme refusé.

---

## POST `/auth/refresh`

Échange un refresh token valide contre un nouvel access token et un nouveau refresh token (rotation). L’ancien refresh est révoqué (`revoked_at`). Pas de JWT d’accès requis.

Si le refresh présenté est **déjà révoqué**, tous les refresh actifs du même utilisateur sont révoqués. La réponse client reste identique.

**Rate limit :** 30 requêtes / 15 min / IP → `429` `{ "error": "Too many requests" }`.

### Corps

```json
{
  "refresh_token": "..."
}
```

### Succès — `200`

```json
{
  "message": "Token refreshed",
  "access_token": "...",
  "refresh_token": "...",
  "user": {
    "id": 1,
    "login": "alex",
    "email": "alex@example.com",
    "auth_provider": "local"
  }
}
```

### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `refresh_token is required` |
| 401 | `Invalid refresh token` |
| 429 | `Too many requests` |
| 503 | `JWT_SECRET is not configured` |
| 503 | `Database is not configured` |

`401 Invalid refresh token` : jeton inconnu, déjà révoqué, expiré, ou utilisateur introuvable.

---

## POST `/auth/logout`

Révoque **un** refresh token (`revoked_at = NOW()`) si `user_id` correspond à l’utilisateur du JWT et que le jeton n’est pas déjà révoqué. La ligne n’est pas supprimée. Les autres sessions restent actives.

**Auth :** `Authorization: Bearer <access_token>`  
Pas de rate limit dédié.

### Corps

```json
{
  "refresh_token": "..."
}
```

### Succès — `200`

```json
{
  "message": "Logged out"
}
```

L’access token JWT n’est pas invalidé : il reste utilisable jusqu’à son `exp`.

### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `Refresh token required` |
| 401 | `Unauthorized` |
| 503 | `Database is not configured` |
| 503 | `JWT_SECRET is not configured` |
| 503 | `JWT is not configured` |

`401 Unauthorized` : JWT absent/invalide, refresh inconnu, déjà révoqué, ou appartenant à un autre utilisateur. Ces cas ne sont pas distingués.

---

## Notes

- `GET /auth/me` existe (JWT only) mais n’est pas documenté ici.
- OAuth Google / Apple : non implémenté.
- Mot de passe et OTP : jamais renvoyés. OTP jamais stocké en clair.
