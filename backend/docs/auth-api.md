# API d’authentification

Documentation des endpoints **implémentés** dans le backend. Les statuts et messages des sections suivantes (jusqu’à Session Management Policy) sont ceux renvoyés par le code actuel (`authController`, services, `errorHandler`).

La section **OAuth Authentication Contract** (Phase 7A.0) est un **contrat** : ces routes **n’existent pas encore**. Ne pas les appeler.

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

## Session Management Policy

Décisions fonctionnelles pour le client Flutter. Elles décrivent le comportement de session attendu ; elles ne changent pas l’API.

### Session persistante par défaut

La session **reste ouverte** tant que l’utilisateur ne se déconnecte pas explicitement.

- Fermer l’application ≠ logout.
- Passer l’application en arrière-plan ≠ logout.
- Relancer l’application ≠ logout.

Le **`refresh_token`** est le mécanisme qui maintient la session. Le client doit le conserver de façon sécurisée (stockage persistant, pas seulement en mémoire). L’`access_token` est court (~15 min) ; à l’expiration, un `POST /auth/refresh` avec le refresh token stocké émet un nouveau couple access + refresh.

### Logout volontaire

La déconnexion n’a lieu **que** sur une action explicite de l’utilisateur (bouton « se déconnecter », etc.).

- Le client appelle `POST /auth/logout` avec l’`access_token` (header) et le `refresh_token` (corps).
- Le backend révoque ce refresh token (`revoked_at`).
- Après logout, l’ancien `refresh_token` ne doit plus permettre un `POST /auth/refresh` (réponse `401` `{ "error": "Invalid refresh token" }`).
- Le client doit alors supprimer access token, refresh token et état « connecté » du stockage local.

L’access token déjà émis peut encore être accepté jusqu’à son `exp` ; le client ne doit plus l’utiliser après logout.

### Après réouverture de l’application

1. Lire le `refresh_token` persisté.
2. S’il est présent, appeler `POST /auth/refresh` **automatiquement** (sans écran login).
3. Si le refresh réussit (`200`) : stocker les nouveaux tokens, laisser l’utilisateur connecté. **Ne pas** redemander login/mot de passe, ni Google, ni Apple.
4. Si le refresh échoue (`401`) : session invalide (logout, révocation, expiration). Afficher l’écran de connexion.

Sans `refresh_token` en stockage : traiter l’utilisateur comme déconnecté.

### Impact OAuth (Google / Apple)

Google et Apple ne servent qu’à **l’authentification initiale** (création ou liaison du compte).

Après création du compte et **validation du téléphone**, la session est maintenue uniquement par **nos** `access_token` et `refresh_token`, comme pour un compte local.

À chaque ouverture de l’application, le client **ne rappelle pas** Google ni Apple. Il utilise le refresh automatique décrit ci-dessus.

Les routes OAuth ne sont **pas encore implémentées** dans ce backend. La règle ci-dessus s’applique dès qu’elles le seront ; en attendant, seule l’auth locale (`login` / `password`) est disponible.

### Règles d’inscription actuelles

Un compte n’est créé dans `users` qu’après **téléphone vérifié** (SMS).

| Mode | Authentification initiale | Ensuite |
|---|---|---|
| **LOCAL** | `login` + `password` + téléphone vérifié | Session via nos tokens |
| **GOOGLE** | Identité Google + choix d’un `login` + téléphone vérifié | Session via nos tokens (pas de rappel Google) |
| **APPLE** | Identité Apple + choix d’un `login` + téléphone vérifié | Session via nos tokens (pas de rappel Apple) |

LOCAL est implémenté (`/auth/register/start`, `/auth/register/verify-phone`, `/auth/login`). GOOGLE et APPLE : voir le contrat Phase 7A.0 ci-dessous ; les routes OAuth ne sont pas encore implémentées.

---

# OAuth Authentication Contract

**Phase 7A.0 — contrat uniquement.** Aucune de ces routes n’est exposée par le serveur aujourd’hui. Aucune logique OAuth n’est écrite. Cette section fige le comportement attendu pour Flutter et pour l’implémentation backend ultérieure.

## Règles générales

- Google et Apple sont des **méthodes d’authentification externes**. Elles ne remplacent pas la vérification du téléphone.
- **Aucun compte OAuth n’est créé** dans `users` avant validation du téléphone.
- Le **`login` est obligatoire** pour tous les comptes (choisi par l’utilisateur à la finalisation).
- Les comptes Google / Apple **n’ont pas de `password_hash`** (`password_hash` = `NULL`).
- L’**email** fourni par Google / Apple est **obligatoire** et conservé dans `users.email`.
- Après création du compte, la session est gérée par **nos** `access_token` et `refresh_token` (même politique que la section Session Management Policy).
- Google / Apple **ne sont pas rappelés** à chaque ouverture de l’application.

---

## POST `/auth/google/start`

Démarre une authentification Google.

### Request

```json
{
  "id_token": "google_identity_token"
}
```

### Comportement backend (contrat)

1. Vérifier le token Google.
2. Récupérer :
   - `provider_user_id` Google
   - `email`
   - `first_name`
   - `last_name`

### Cas 1 — compte Google existant

Le `provider_user_id` correspond déjà à un `users` (`auth_provider = 'google'`).

Réponse (même idée que le login local) :

```json
{
  "message": "Login successful",
  "access_token": "...",
  "refresh_token": "..."
}
```

### Cas 2 — nouveau compte Google

**Ne pas** créer immédiatement la ligne `users`.

Réponse :

```json
{
  "message": "Phone verification required",
  "verification_token": "...",
  "provider": "google",
  "email": "..."
}
```

Le client enchaîne ensuite sur `POST /auth/oauth/verify-phone` (téléphone + choix du `login`).

---

## POST `/auth/apple/start`

Même principe que Google.

### Request

```json
{
  "identity_token": "apple_identity_token"
}
```

### Comportement backend (contrat)

- Vérifier l’Apple Identity Token.
- Récupérer :
  - `provider_user_id` Apple
  - `email`
  - `first_name`
  - `last_name`

### Compte existant

Retourner `access_token` + `refresh_token` :

```json
{
  "message": "Login successful",
  "access_token": "...",
  "refresh_token": "..."
}
```

### Nouveau compte

Demander la vérification téléphone. **Ne pas** créer `users`.

```json
{
  "message": "Phone verification required",
  "verification_token": "...",
  "provider": "apple",
  "email": "..."
}
```

---

## POST `/auth/oauth/verify-phone`

Finalise la création d’un compte OAuth **après** validation du téléphone.

### Request

```json
{
  "verification_token": "...",
  "code": "SMS_CODE",
  "login": "chosen_login"
}
```

### Comportement backend (contrat)

1. Vérifier le code SMS.
2. Vérifier que le `login` est disponible.
3. Créer le compte `users` (pas avant).

**Exemple Google :**

| Champ | Valeur |
|---|---|
| `email` | email Google |
| `login` | login choisi |
| `phone_verified` | `true` |
| `auth_provider` | `google` |
| `provider_user_id` | google id |
| `password_hash` | `NULL` |

**Exemple Apple :**

| Champ | Valeur |
|---|---|
| `email` | email Apple |
| `login` | login choisi |
| `phone_verified` | `true` |
| `auth_provider` | `apple` |
| `provider_user_id` | apple id |
| `password_hash` | `NULL` |

### Succès

```json
{
  "message": "Account created",
  "access_token": "...",
  "refresh_token": "..."
}
```

Contrairement au `POST /auth/register/verify-phone` local, la finalisation OAuth **émet** déjà la session (access + refresh).

---

## Authentication methods summary

| Méthode | Authentification initiale | Compte `users` |
|---|---|---|
| **LOCAL** | `login` + `password` + téléphone vérifié | `auth_provider = 'local'`, `password_hash` bcrypt |
| **GOOGLE** | Identité Google + choix d’un `login` + téléphone vérifié | `auth_provider = 'google'`, `password_hash` `NULL` |
| **APPLE** | Identité Apple + choix d’un `login` + téléphone vérifié | `auth_provider = 'apple'`, `password_hash` `NULL` |

Dans les trois cas : pas de ligne `users` avant SMS validé ; ensuite session = nos tokens uniquement.

---

## Notes

- `GET /auth/me` existe (JWT only) mais n’est pas documenté ici.
- Mot de passe et OTP : jamais renvoyés. OTP jamais stocké en clair.
