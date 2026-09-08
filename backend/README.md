# Backend — authentification

API REST JSON (Node.js + Express) pour l’authentification des utilisateurs.

## Stack prévue

- **Runtime** : Node.js
- **Framework** : Express
- **Base de données** : PostgreSQL
- **Authentification** : JWT
- **Hash des mots de passe** : bcrypt

## État actuel

Serveur Express minimal avec une route de santé `GET /health` et chargement des variables d’environnement via `dotenv`. Aucune authentification, aucune base de données et aucune autre fonctionnalité applicative pour le moment.

## Variables d’environnement

La configuration du backend passe par des variables d’environnement (port d’écoute, URL PostgreSQL, secret JWT). Elles sont chargées au démarrage depuis un fichier `.env` local, grâce à `dotenv`.

| Variable        | Rôle                                      | Obligatoire aujourd’hui |
|-----------------|-------------------------------------------|-------------------------|
| `PORT`          | Port HTTP du serveur (défaut : `3000`)    | Non                     |
| `DATABASE_URL`  | Connexion PostgreSQL (prévue plus tard)   | Non                     |
| `JWT_SECRET`    | Secret de signature des jetons JWT        | Non                     |

Le fichier `.env` ne doit **jamais** être commité : il est ignoré par Git. Le fichier `.env.example` sert de modèle, sans valeurs secrètes.

### Créer un fichier `.env` local

```bash
cd backend
cp .env.example .env
```

Adapte ensuite `.env` si besoin (par exemple `PORT=4000`). `DATABASE_URL` et `JWT_SECRET` peuvent rester vides pour cette étape.

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
