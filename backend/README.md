# Backend — authentification

API REST JSON (Node.js + Express) pour l’authentification des utilisateurs.

## Stack prévue

- **Runtime** : Node.js
- **Framework** : Express
- **Base de données** : PostgreSQL
- **Authentification** : JWT
- **Hash des mots de passe** : bcrypt

## État actuel

Serveur Express avec `GET /health`, inscription locale (`POST /auth/register/start`, `POST /auth/register/verify-phone`), connexion locale `POST /auth/login`, renouvellement `POST /auth/refresh`, déconnexion `POST /auth/logout`, profil JWT `GET /auth/me`, profil SQL `GET /auth/profile`, Google `POST /auth/google/start`, et OAuth téléphone `POST /auth/oauth/start-phone` / `POST /auth/oauth/verify-phone`. Après un login réussi (local ou Google déjà lié) ou une création OAuth, le backend émet un JWT (15 minutes, HS256, claims `userId` / `login` / `auth_provider` / `jti`, `iss`, `aud`) et un refresh token (90 jours, stocké uniquement hashé). `POST /auth/refresh` fait tourner le refresh token dans une transaction. Un compte n’est créé dans `users` qu’après validation du code SMS. Le serveur refuse de démarrer si la configuration JWT est absente ou dangereuse. Le JSON d’entrée est limité à **32 Ko**.

## Schéma utilisateurs

Le fichier `sql/001_create_users.sql` définit la table principale `users` (inscription locale, Google et Apple).

Ce script doit être exécuté **manuellement dans Neon** lors de l’étape prévue à cet effet. Il n’est pas lancé par le serveur. Aucune information secrète ne doit être ajoutée au dépôt.

## Vérifications SMS

Le fichier `sql/002_create_phone_verifications.sql` définit la table temporaire `phone_verifications`.

Un compte **n’est pas créé** dans `users` tant que le code SMS n’a pas été validé. Cette table stocke une demande d’inscription temporaire (jeton aléatoire, numéro, hash du code, expiration), sans `user_id` et sans code SMS en clair.

La migration `sql/003_add_registration_data_to_phone_verifications.sql` ajoute `registration_data` (JSONB) pour conserver temporairement les champs d’une inscription locale (`email`, `birth_date`, `phone_number`, `login`, `password_hash`, `first_name`, `last_name`). Le mot de passe n’est jamais stocké en clair.

Ces scripts doivent être exécutés manuellement dans Neon à l’étape prévue. Aucun secret ni donnée réelle ne doit être ajouté au dépôt.

## Refresh tokens

Le fichier `sql/004_create_refresh_tokens.sql` définit la table `refresh_tokens`. Après un `POST /auth/login` réussi, un refresh token opaque (90 jours) est renvoyé au client ; **seul son hash** (`token_hash`) est stocké en base, avec `user_id` et `expires_at`. Le jeton en clair n’est jamais persisté.

Un **JWT** (access token) est un jeton court (15 minutes, `JWT_EXPIRES_IN=15m`) signé avec `JWT_SECRET` en **HS256**, contenant `userId`, `login`, `auth_provider`, `jti`, `iss` (`JWT_ISSUER`) et `aud` (`JWT_AUDIENCE`). Il sert à authentifier les requêtes API. Un **refresh token** est un secret longue durée, lié à un utilisateur, révocable. `POST /auth/refresh` échange un refresh token valide contre un nouvel access token et un nouveau refresh token (rotation : l’ancien est révoqué via `revoked_at`). Si un refresh token **déjà révoqué** est présenté, tous les refresh tokens actifs de l’utilisateur sont révoqués (réutilisation possible). La réponse client reste `401 Invalid refresh token`.

Un utilisateur a au plus **5 refresh tokens actifs** (`revoked_at IS NULL` et non expirés). Un 6e login révoque le plus ancien (`revoked_at`), sans supprimer la ligne. Les réponses HTTP de login/refresh restent inchangées.

Un nettoyage optionnel (`purgeStaleRefreshTokens`, `npm run purge:refresh-tokens -- --confirm`) **supprime** les lignes révoquées ou expirées depuis **30 jours**. Il ne s’exécute pas tout seul. Les tokens encore actifs ne sont jamais effacés.

## Durcissement SQL (005)

Le fichier `sql/005_harden_users.sql` est une migration **non destructive**, à exécuter **manuellement dans Neon** après `npm run test:sql-hardening`. Le serveur ne l’applique pas.

Elle ajoute :

- `UNIQUE (phone_number)` sur `users` (`users_phone_number_unique`), si aucun doublon n’existe ;
- un index partiel `refresh_tokens_user_id_active_idx` sur `refresh_tokens (user_id) WHERE revoked_at IS NULL` (sessions actives / révocation de réutilisation). L’index existant `refresh_tokens_user_id_idx` est conservé (FK / toutes les lignes).

Aucun CHECK sur `login` / `email` / format téléphone : les nouvelles valeurs sont déjà validées par l’application ; un CHECK `lower(login)` casserait d’éventuels logins historiques en casse mixte ; E.164 n’est pas encore en place.

`phone_verifications.phone_number` **reste non UNIQUE** (plusieurs demandes historiques possibles).

**Migration prête à être appliquée manuellement dans Neon.**

## PostgreSQL

Le backend utilise PostgreSQL. La connexion est gérée par un pool (`pg.Pool`) dans `src/db.js`.

La chaîne de connexion vient **uniquement** de la variable d’environnement `DATABASE_URL`. Elle doit être fournie par l’environnement d’exécution (hébergeur, secrets du déploiement, ou un fichier `.env` local non versionné). Aucun identifiant, mot de passe ni URL de base de données ne doit être ajouté au dépôt Git.

## Variables d’environnement

La configuration du backend passe par des variables d’environnement (port d’écoute, URL PostgreSQL, secret JWT). Elles sont chargées au démarrage depuis un fichier `.env` local, grâce à `dotenv`.

| Variable                      | Rôle                                      | Obligatoire aujourd’hui |
|-------------------------------|-------------------------------------------|-------------------------|
| `PORT`                        | Port HTTP du serveur (défaut : `3000`)    | Non                     |
| `DATABASE_URL`                | Chaîne de connexion PostgreSQL            | Oui pour la base        |
| `JWT_SECRET`                  | Secret de signature des JWT (≥ 16 car.)   | Oui au démarrage        |
| `JWT_ISSUER`                  | Claim `iss` des access tokens             | Oui au démarrage        |
| `JWT_AUDIENCE`                | Claim `aud` des access tokens             | Oui au démarrage        |
| `JWT_EXPIRES_IN`              | Durée de l’access token (défaut : `15m`, max 24h) | Format valide requis |
| `REFRESH_TOKEN_EXPIRES_DAYS`  | Durée du refresh token (défaut : `90`, 1–365) | Format valide requis |
| `DEV_LOG_SMS_CODE`            | Log du code SMS en clair (`true` seulement, défaut : off) | Non |
| `SMS_PROVIDER`                | Fournisseur SMS : `mock` (dev) ou `twilio` (défaut / prod) | Non |
| `TWILIO_ACCOUNT_SID`          | Identifiant compte Twilio                 | Oui si `SMS_PROVIDER=twilio` et envoi réel |
| `TWILIO_AUTH_TOKEN`           | Secret API Twilio                         | Oui si `SMS_PROVIDER=twilio` et envoi réel |
| `TWILIO_PHONE_NUMBER`         | Numéro expéditeur Twilio                  | Oui si `SMS_PROVIDER=twilio` et envoi réel |

Le fichier `.env` ne doit **jamais** être commité : il est ignoré par Git. Le fichier `.env.example` sert de modèle, sans valeurs secrètes.

### Créer un fichier `.env` local

```bash
cd backend
cp .env.example .env
```

Adapte ensuite `.env` si besoin (par exemple `PORT=4000`). Renseigne `DATABASE_URL`, `JWT_SECRET` et `SMS_PROVIDER` (`mock` en local, `twilio` en production). Pour un envoi SMS réel, ajoute les variables Twilio **hors Git**. Ne commitez jamais de secrets. `JWT_ISSUER` et `JWT_AUDIENCE` ne sont pas des secrets ; ils identifient l’émetteur et l’audience du JWT.

### Configuration SMS (`SMS_PROVIDER`)

L’envoi passe par `backend/src/services/smsService.js` (`sendSms`). Deux modes :

**Développement local** — aucun fournisseur externe :

```bash
SMS_PROVIDER=mock
DEV_LOG_SMS_CODE=true
```

`SMS_PROVIDER=mock` simule un envoi réussi et **n’appelle jamais Twilio**, même si les variables Twilio sont présentes. `DEV_LOG_SMS_CODE=true` affiche uniquement le code OTP dans les logs du serveur (jamais stocké en clair, jamais renvoyé dans une réponse HTTP). Le flux `register/start` → `verify-phone` → création `users` reste inchangé.

**Production** — envoi réel Twilio :

```bash
SMS_PROVIDER=twilio
TWILIO_ACCOUNT_SID=...
TWILIO_AUTH_TOKEN=...
TWILIO_PHONE_NUMBER=...
DEV_LOG_SMS_CODE=false
```

Si `SMS_PROVIDER` est absent, le comportement reste celui de Twilio (envoi si les trois variables sont renseignées, sinon envoi ignoré). Un échec Twilio renvoie **503** `{ "error": "SMS could not be sent" }`, sans détail fournisseur. Le token Twilio et le numéro complet ne sont pas logués.

## Démarrage

```bash
cd backend
npm install
npm start
```

Le serveur écoute sur le port défini par `PORT` dans `.env` (ou dans l’environnement), ou **3000** par défaut.

```bash
PORT=4000 npm start
```

## Tester

```bash
curl http://localhost:3000/health
```

Réponse attendue :

```json
{
  "status": "ok",
  "message": "API is running"
}
```

### Démarrer une inscription locale

`POST /auth/register/start` valide les champs, vérifie qu’email / login / téléphone ne sont pas déjà dans `users`, hash le mot de passe avec bcrypt, puis enregistre une demande dans `phone_verifications` (jeton, hash du code SMS, `registration_data`). Aucune ligne n’est insérée dans `users`. Après stockage du `code_hash`, le backend appelle `smsService.sendSms` : `SMS_PROVIDER=mock` simule un succès sans Twilio ; `SMS_PROVIDER=twilio` envoie via Twilio si `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` et `TWILIO_PHONE_NUMBER` sont renseignés. **Sans ces variables** (et hors mode mock), l’envoi est ignoré et l’inscription continue. Le code SMS n’est logué **que si** `DEV_LOG_SMS_CODE=true` (désactivé par défaut) ; il n’est jamais stocké en clair ni renvoyé dans la réponse HTTP. Les erreurs Twilio ne sont jamais renvoyées au client (**503** générique). Le token Twilio et le numéro complet ne sont pas logués.

Mot de passe (politique centralisée, `src/validators/passwordValidator.js`) : **8 à 72 caractères**, pas vide, pas seulement des espaces. Pas d’obligation de majuscule ni de caractère spécial. Au-delà de 72 caractères, l’inscription est refusée (**400**) et bcrypt n’est pas appelé.

Identifiants (fonctions centralisées, `src/validators/authFields.js`), appliquées avant recherche de doublon, insertion `phone_verifications` et lookup login :

- **email** : `trim` + minuscules, format email inchangé, vide refusé, max 254. `"  Test.User@Example.COM "` → `"test.user@example.com"`.
- **login** : `trim` + minuscules, max 64. `"  Test_User  "` → `"test_user"`. Le stockage et la recherche utilisent la même forme ; `"TEST_USER"` retrouve un compte créé en `"test_user"`. Avant cette étape le login était sensible à la casse. Les lignes historiques encore en casse mixte **ne sont pas réécrites** (pas de migration SQL) et ne matcheraient plus un lookup minuscule.
- **téléphone** (normalisation légère seulement) : `trim`, puis suppression des espaces, tirets et parenthèses. `"+33 6 12-34-56-78"` → `"+33612345678"`. Pas de conversion d’indicatif, pas de pays par défaut, **pas de validation E.164 stricte** (étape ultérieure, avant un vrai fournisseur SMS). Max 32 après nettoyage.

`POST /auth/register/verify-phone` re-normalise email / login / téléphone lus depuis `registration_data` avant les contrôles d’unicité et l’insertion dans `users`.

Contraintes SQL actuelles (`sql/001_create_users.sql`) : `UNIQUE(email)`, `UNIQUE(login)` (comparaison PostgreSQL sensible à la casse). **`phone_number` n’a pas de contrainte UNIQUE dans 001** (contrôle applicatif seulement jusqu’à `sql/005_harden_users.sql`, à appliquer manuellement dans Neon).

Un rate limiting **en mémoire, par IP**, s’applique à `POST /auth/register/start` (5 / 15 min), `POST /auth/register/verify-phone` (10 / 15 min), `POST /auth/login` (10 / 15 min), `POST /auth/refresh` (30 / 15 min), `POST /auth/google/start` (10 / 15 min), `POST /auth/oauth/start-phone` (5 / 15 min) et `POST /auth/oauth/verify-phone` (10 / 15 min). Dépassement : HTTP **429** et en-tête `Retry-After`. Ce limiteur n’est pas adapté à plusieurs instances de production.

```bash
curl -sS -X POST http://localhost:3000/auth/register/start \
  -H 'Content-Type: application/json' \
  -d '{
    "email": "alex@example.com",
    "birth_date": "1990-01-15",
    "login": "alex",
    "password": "choose-a-strong-password",
    "password_confirmation": "choose-a-strong-password",
    "phone_number": "+33600000000",
    "first_name": "Alex",
    "last_name": "Martin"
  }'
```

Succès attendu :

```json
{
  "message": "Verification code generated",
  "verification_token": "..."
}
```

### Valider le SMS et créer le compte

`POST /auth/register/verify-phone` reçoit `verification_token` et `code`. Le code SMS n’est **jamais** stocké en clair : seule la comparaison bcrypt avec `code_hash` est utilisée.

Si le jeton existe, n’est pas expiré, n’a pas dépassé 5 tentatives et que le code est correct, une transaction PostgreSQL (`SELECT … FOR UPDATE`) :

1. crée la ligne `users` à partir de `registration_data` (`phone_verified = true`, `auth_provider = 'local'`) ;
2. marque la demande comme consommée (`verified_at = NOW()`), sans supprimer la ligne (audit).

Un même `verification_token` ne peut aboutir qu’une fois. Un conflit email / login / téléphone à cette étape renvoie **409** générique (`Email, login or phone number is already in use`). Les deux opérations sont atomiques. Aucun JWT n’est émis.

```bash
curl -sS -X POST http://localhost:3000/auth/register/verify-phone \
  -H 'Content-Type: application/json' \
  -d '{
    "verification_token": "replace-with-token",
    "code": "000000"
  }'
```

Succès attendu :

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

### Connexion locale

`POST /auth/login` reçoit `login` et `password`. L’utilisateur est recherché uniquement par `login` (valeur trimée et mise en minuscules, comme au stockage). Le mot de passe reçu est comparé à `password_hash` avec `bcrypt.compare`. Le téléphone doit être vérifié (`phone_verified = true`).

En cas de succès, le backend retourne un **access token JWT** (15 minutes) et un **refresh token** (90 jours). Seul le hash du refresh token est enregistré dans `refresh_tokens`. Le JWT n’est pas stocké en base. En cas de login ou mot de passe incorrect, **ou si le login n’existe pas**, la réponse est générique (`Invalid credentials`) pour ne pas indiquer si le login existe. Les deux chemins exécutent `bcrypt.compare` (hash factice si le compte est absent) afin d’aligner les temps de réponse.

```bash
curl -sS -X POST http://localhost:3000/auth/login \
  -H 'Content-Type: application/json' \
  -d '{
    "login": "alex",
    "password": "choose-a-strong-password"
  }'
```

Succès attendu :

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

### Renouveler les tokens

`POST /auth/refresh` reçoit `{ "refresh_token": "..." }`. Le jeton est hashé en SHA-256 puis recherché dans `refresh_tokens`. S’il existe, n’est pas expiré et n’est pas révoqué, une transaction PostgreSQL :

1. génère un nouvel access token JWT et un nouveau refresh token opaque ;
2. insère le **hash** du nouveau refresh token ;
3. révoque l’ancien (`revoked_at`).

Le refresh token en clair n’est jamais stocké.

```bash
curl -sS -X POST http://localhost:3000/auth/refresh \
  -H 'Content-Type: application/json' \
  -d '{
    "refresh_token": "replace-with-refresh-token"
  }'
```

Succès attendu :

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

Token invalide, expiré ou révoqué :

```json
{
  "error": "Invalid refresh token"
}
```

La présentation d’un refresh token déjà révoqué révoque aussi les autres jetons actifs du même utilisateur, sans le dire au client.

### Route protégée : profil JWT

Les routes protégées exigent le header :

```http
Authorization: Bearer <access_token>
```

Le middleware `requireAuth` (`src/middleware/authMiddleware.js`) vérifie le JWT avec `JWT_SECRET`, **HS256 uniquement**, `issuer` (`JWT_ISSUER`), `audience` (`JWT_AUDIENCE`) et l’expiration `exp` (jeton sans `exp` refusé). Le payload signé contient `userId`, `login`, `auth_provider` et `jti`. En cas de header absent, format invalide, token vide, signature incorrecte, mauvais `iss` / `aud`, algorithme refusé, jeton expiré ou sans `exp`, la réponse est toujours :

```json
{
  "error": "Unauthorized"
}
```

HTTP **401**. Aucun détail JWT, aucun token et aucun secret ne sont renvoyés ni logués.

`GET /auth/me` est la première route protégée. Elle lit uniquement le payload du access token (`userId`, `login`, `auth_provider`). Pas de requête SQL, pas de nouvel login.

```bash
curl -sS http://localhost:3000/auth/me \
  -H 'Authorization: Bearer replace-with-access-token'
```

Succès attendu :

```json
{
  "user": {
    "userId": 1,
    "login": "alex",
    "auth_provider": "local"
  }
}
```

Sans token, ou avec un token invalide :

```json
{
  "error": "Unauthorized"
}
```

### User profile endpoint

`GET /auth/profile` est protégé par `requireAuth` (`Authorization: Bearer <access_token>`). L’identifiant utilisé pour charger le profil est **`req.user.userId`** (claim JWT), jamais le `login` du jeton. Les champs viennent de PostgreSQL (`userService.findUserProfileById`).

```bash
curl -sS http://localhost:3000/auth/profile \
  -H 'Authorization: Bearer replace-with-access-token'
```

Succès (**200**) :

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

Champs volontairement exclus : `password_hash`, refresh token, `token_hash`, `provider_user_id`, noms, horodatages internes.

Utilisateur absent : **404** `{ "error": "User not found" }`. Sans token ou JWT invalide : **401** `{ "error": "Unauthorized" }`.

### Déconnexion

`POST /auth/logout` est protégé par `requireAuth` (`Authorization: Bearer <access_token>`). Le corps JSON doit contenir le **refresh token** de la session à fermer. Le jeton est hashé en SHA-256 (même méthode que le stockage), recherché dans `refresh_tokens`, puis révoqué (`revoked_at = NOW()`) si `user_id` correspond à `req.user.userId` et que `revoked_at IS NULL`. La ligne n’est pas supprimée.

```bash
curl -sS -X POST http://localhost:3000/auth/logout \
  -H 'Authorization: Bearer replace-with-access-token' \
  -H 'Content-Type: application/json' \
  -d '{
    "refresh_token": "replace-with-refresh-token"
  }'
```

Succès (**200**) :

```json
{
  "message": "Logged out"
}
```

Refresh token absent : **400** `{ "error": "Refresh token required" }`.

JWT absent ou invalide, refresh inconnu, déjà révoqué, ou appartenant à un autre utilisateur : **401** `{ "error": "Unauthorized" }`. Ces cas invalides ne distinguent pas l’existence, l’état ni le propriétaire du refresh token.

Les réponses de `login`, `refresh` et `profile` restent inchangées. Aucun refresh token, `token_hash`, JWT ni secret n’est logué.

Les corps JSON de plus de **32 Ko** sont rejetés (**413**). Une erreur interne (**500**) ne renvoie jamais de stack, SQL, secret, ni token.

### Vérifier la connexion PostgreSQL

Le test réel utilise le pool de `src/db.js` et exécute `SELECT 1`. Il nécessite `DATABASE_URL` **déjà fournie par l’environnement** (variable d’environnement du processus, secret d’hébergement, etc.). Ne commitez jamais cette valeur.

```bash
cd backend
npm run test:db
```

### Vérifier le schéma PostgreSQL

`npm run test:schema` interroge uniquement les métadonnées (`information_schema`) pour confirmer la présence des tables `users`, `phone_verifications` et `refresh_tokens`, ainsi que leurs colonnes principales. Aucune donnée n’est modifiée. `DATABASE_URL` doit être fournie par l’environnement.

```bash
cd backend
npm run test:schema
```

### Vérifier la rotation et la réutilisation des refresh tokens

```bash
cd backend
npm run test:refresh-reuse
```

### Vérifier la normalisation email / login / téléphone

```bash
cd backend
npm run test:normalization
```

### Vérifier le middleware JWT et GET /auth/me

```bash
cd backend
npm run test:auth-me
```

### Vérifier le durcissement auth (timing login, JWT iss/aud, JSON 32ko)

```bash
cd backend
npm run test:auth-hardening
```

### Vérifier le durcissement SQL (SELECT uniquement)

`npm run test:sql-hardening` inspecte les fichiers `sql/001`–`005` et, si `DATABASE_URL` est fournie, exécute uniquement des **SELECT** (doublons, contraintes, index). Aucun INSERT/UPDATE/DELETE. **N’applique pas** `sql/005_harden_users.sql`.

```bash
cd backend
npm run test:sql-hardening
```

### Vérifier GET /auth/profile

```bash
cd backend
npm run test:user-profile
```

### Vérifier le service SMS (Twilio mocké)

```bash
cd backend
npm run test:sms
```

### Vérifier la finalisation d’inscription (verify-phone)

```bash
cd backend
npm run test:registration-finalization
```

### Vérifier POST /auth/logout

```bash
cd backend
npm run test:logout
```

### Vérifier POST /auth/google/start

`POST /auth/google/start` appelle `googleAuthService.verifyGoogleIdToken()`. Un compte Google déjà présent (`auth_provider = 'google'` + `provider_user_id`) reçoit la même session que le login local. Sinon aucun `users` n’est créé : un `oauth_verification_token` est stocké dans `phone_verifications` (données provider / email / nom). L’`id_token` n’est jamais logué. Apple n’est pas exposé.

```bash
cd backend
npm run test:google-auth
npm run test:google-start
```

### Vérifier POST /auth/oauth/start-phone

`POST /auth/oauth/start-phone` (`oauthService`) reprend le contexte OAuth, normalise le téléphone, vérifie qu’il n’est pas déjà dans `users`, hash un OTP (même mécanisme que l’inscription locale) et envoie le SMS via `smsService`. Aucun compte `users`, JWT ou refresh token n’est créé à cette étape.

```bash
cd backend
npm run test:oauth-start-phone
```

### Vérifier POST /auth/oauth/verify-phone

`POST /auth/oauth/verify-phone` (`oauthService.verifyOAuthPhoneAndCreateUser`) valide l’OTP, exige `birth_date` et un `login` disponible, crée `users` (`auth_provider = google|apple`, `password_hash` NULL, `phone_verified = true`) puis émet la session existante (`generateAccessToken` + `storeLoginRefreshToken`).

```bash
cd backend
npm run test:oauth-verify-phone
```

### Vérifier le parcours Google OAuth (tests fonctionnels internes)

Suite interne sans Google Cloud : identité Google simulée, base mémoire, vrais endpoints HTTP (`/auth/google/start` → `/auth/oauth/start-phone` → `/auth/oauth/verify-phone`, reconnexion, logout/refresh). Aucune logique métier n’est modifiée.

```bash
cd backend
npm run test:google-oauth-flow
```
