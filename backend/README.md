# Backend — authentification

API REST JSON (Node.js + Express) pour l’authentification des utilisateurs.

## Stack prévue

- **Runtime** : Node.js
- **Framework** : Express
- **Base de données** : PostgreSQL
- **Authentification** : JWT
- **Hash des mots de passe** : bcrypt

## État actuel

Serveur Express minimal avec une route de santé `GET /health`. Aucune authentification, aucune base de données et aucune autre dépendance applicative pour le moment.

## Démarrage

```bash
cd backend
npm install
npm start
```

Le serveur écoute sur le port défini par la variable d’environnement `PORT`, ou **3000** par défaut.

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
