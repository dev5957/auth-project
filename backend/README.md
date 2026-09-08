# Backend — authentification

API REST JSON (Node.js + Express) pour l’authentification des utilisateurs.

## Stack prévue

- **Runtime** : Node.js
- **Framework** : Express
- **Base de données** : PostgreSQL
- **Authentification** : JWT
- **Hash des mots de passe** : bcrypt

## État actuel

Serveur Express minimal avec une route de santé `GET /health`, chargement des variables d’environnement via `dotenv`, et un pool de connexions PostgreSQL prêt à l’emploi. Le schéma principal des utilisateurs est défini en SQL, mais n’est pas encore appliqué. Aucune authentification applicative pour le moment.

## Schéma utilisateurs

Le fichier `sql/001_create_users.sql` définit la table principale `users` (inscription locale, Google et Apple).

Ce script doit être exécuté **manuellement dans Neon** lors de l’étape prévue à cet effet. Il n’est pas lancé par le serveur. Aucune information secrète ne doit être ajoutée au dépôt.

## PostgreSQL

Le backend utilise PostgreSQL. La connexion est gérée par un pool (`pg.Pool`) dans `src/db.js`.

La chaîne de connexion vient **uniquement** de la variable d’environnement `DATABASE_URL`. Elle doit être fournie par l’environnement d’exécution (hébergeur, secrets du déploiement, ou un fichier `.env` local non versionné). Aucun identifiant, mot de passe ni URL de base de données ne doit être ajouté au dépôt Git.

## Variables d’environnement

La configuration du backend passe par des variables d’environnement (port d’écoute, URL PostgreSQL, secret JWT). Elles sont chargées au démarrage depuis un fichier `.env` local, grâce à `dotenv`.

| Variable        | Rôle                                      | Obligatoire aujourd’hui |
|-----------------|-------------------------------------------|-------------------------|
| `PORT`          | Port HTTP du serveur (défaut : `3000`)    | Non                     |
| `DATABASE_URL`  | Chaîne de connexion PostgreSQL            | Oui pour la base        |
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

### Vérifier la connexion PostgreSQL

Le test réel utilise le pool de `src/db.js` et exécute `SELECT 1`. Il nécessite `DATABASE_URL` **déjà fournie par l’environnement** (variable d’environnement du processus, secret d’hébergement, etc.). Ne commitez jamais cette valeur.

```bash
cd backend
npm run test:db
```
