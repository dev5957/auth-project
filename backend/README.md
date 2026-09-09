# Backend — authentification

API REST JSON (Node.js + Express) pour l’authentification des utilisateurs.

## Stack prévue

- **Runtime** : Node.js
- **Framework** : Express
- **Base de données** : PostgreSQL
- **Authentification** : JWT
- **Hash des mots de passe** : bcrypt

## État actuel

Serveur Express avec `GET /health`, inscription locale (`POST /auth/register/start`, `POST /auth/register/verify-phone`) et connexion locale `POST /auth/login`. Après un login réussi, le backend émet un JWT (access token, 15 minutes) et un refresh token (90 jours, stocké uniquement hashé). Un compte n’est créé dans `users` qu’après validation du code SMS. Les schémas SQL sont définis mais doivent encore être appliqués manuellement dans Neon.

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

Un **JWT** (access token) est un jeton court (15 minutes, `JWT_EXPIRES_IN=15m`) signé avec `JWT_SECRET`, contenant `userId`, `login` et `auth_provider`. Il sert à authentifier les requêtes API. Un **refresh token** est un secret longue durée, lié à un utilisateur, révocable, destiné à obtenir plus tard un nouvel access token. Aucune route de refresh n’existe encore.

## PostgreSQL

Le backend utilise PostgreSQL. La connexion est gérée par un pool (`pg.Pool`) dans `src/db.js`.

La chaîne de connexion vient **uniquement** de la variable d’environnement `DATABASE_URL`. Elle doit être fournie par l’environnement d’exécution (hébergeur, secrets du déploiement, ou un fichier `.env` local non versionné). Aucun identifiant, mot de passe ni URL de base de données ne doit être ajouté au dépôt Git.

## Variables d’environnement

La configuration du backend passe par des variables d’environnement (port d’écoute, URL PostgreSQL, secret JWT). Elles sont chargées au démarrage depuis un fichier `.env` local, grâce à `dotenv`.

| Variable                      | Rôle                                      | Obligatoire aujourd’hui |
|-------------------------------|-------------------------------------------|-------------------------|
| `PORT`                        | Port HTTP du serveur (défaut : `3000`)    | Non                     |
| `DATABASE_URL`                | Chaîne de connexion PostgreSQL            | Oui pour la base        |
| `JWT_SECRET`                  | Secret de signature des JWT               | Oui pour le login       |
| `JWT_EXPIRES_IN`              | Durée de l’access token (défaut : `15m`)  | Non                     |
| `REFRESH_TOKEN_EXPIRES_DAYS`  | Durée du refresh token (défaut : `90`)    | Non                     |

Le fichier `.env` ne doit **jamais** être commité : il est ignoré par Git. Le fichier `.env.example` sert de modèle, sans valeurs secrètes.

### Créer un fichier `.env` local

```bash
cd backend
cp .env.example .env
```

Adapte ensuite `.env` si besoin (par exemple `PORT=4000`). Renseigne `DATABASE_URL` et `JWT_SECRET` **hors Git**. Ne commitez jamais de secrets.

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

`POST /auth/register/start` valide les champs, vérifie qu’email / login / téléphone ne sont pas déjà dans `users`, hash le mot de passe avec bcrypt, puis enregistre une demande dans `phone_verifications` (jeton, hash du code SMS, `registration_data`). Aucune ligne n’est insérée dans `users`. Aucun SMS réel n’est envoyé pour le moment (le code n’apparaît que dans les logs de développement).

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

Si le jeton existe, n’est pas expiré, n’a pas dépassé 5 tentatives et que le code est correct, une transaction PostgreSQL :

1. crée la ligne `users` à partir de `registration_data` (`phone_verified = true`, `auth_provider = 'local'`) ;
2. supprime la demande dans `phone_verifications`.

Les deux opérations sont atomiques. Aucun JWT n’est émis.

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

`POST /auth/login` reçoit `login` et `password`. L’utilisateur est recherché uniquement par `login`. Le mot de passe reçu est comparé à `password_hash` avec `bcrypt.compare`. Le téléphone doit être vérifié (`phone_verified = true`).

En cas de succès, le backend retourne un **access token JWT** (15 minutes) et un **refresh token** (90 jours). Seul le hash du refresh token est enregistré dans `refresh_tokens`. Le JWT n’est pas stocké en base. En cas de login ou mot de passe incorrect, la réponse est générique (`Invalid credentials`) pour ne pas indiquer si le login existe.

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

### Vérifier la connexion PostgreSQL

Le test réel utilise le pool de `src/db.js` et exécute `SELECT 1`. Il nécessite `DATABASE_URL` **déjà fournie par l’environnement** (variable d’environnement du processus, secret d’hébergement, etc.). Ne commitez jamais cette valeur.

```bash
cd backend
npm run test:db
```
