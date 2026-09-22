# API Chronique (Module 2) — contrat

Documentation **contractuelle** du Module 2. Ce fichier fige le modèle et les endpoints **avant** toute implémentation.

**Statut :** conception uniquement. Aucune route, aucun service, aucune migration SQL n’est livrée avec ce document.

Le Module 1 (authentification) reste inchangé : tables `users`, `refresh_tokens`, `phone_verifications`, routes `/auth/*`, middleware JWT existant. Les chroniques s’appuient sur `requireAuth` et `req.user.userId` **tels qu’ils existent**.

Préfixe prévu : `/chroniques`  
Corps JSON : `Content-Type: application/json`  
Limite JSON globale actuelle du serveur : **32 Ko** → `413` `{ "error": "Payload too large" }`  
Les binaires **ne transitent pas** dans ce JSON (voir [Gestion des médias](#6-gestion-des-médias)).  
JSON invalide → `400` `{ "error": "Invalid JSON" }`  
Erreur inattendue → `500` `{ "error": "Internal server error" }`  
Erreurs métier : `{ "error": "<message>" }` (même forme que l’Auth).

Authentification des routes de ce module : header

```http
Authorization: Bearer <access_token>
```

Identité propriétaire = claim JWT `userId`. Un `user_id` dans le body est **ignoré** (et refusé s’il est envoyé pour en usurper un autre).

---

## 1. Présentation du module Chronique

appLumina n’est plus seulement une application d’authentification. Le Module 2 introduit la **création de contenus personnels** : la **Chronique**.

Une chronique personnelle est une **succession de contenus** qui forment un récit dans le temps. L’utilisateur crée des unités appelées **chroniques**.

Le mot **« chapitre »** peut apparaître dans l’expérience visuelle / narrative (client Flutter). Il n’existe **pas** dans l’API :

- pas de champ `chapter_number` ;
- pas de numérotation obligatoire ;
- pas d’entité Chapitre distincte.

Le Module 2 est **individuel** : un utilisateur ne lit, ne modifie et ne supprime **que** ses propres chroniques. Aucun fil social, aucun commentaire, aucune visibilité tierce.

Les champs `is_public`, `audience` et `comments_enabled` sont **prévus dans le modèle** pour un module social futur. Ils ne sont **pas exploitables** dans le Module 2 (valeurs forcées, lectures ignorées par le client).

Architecture cible (fichiers **non créés** à cette étape) :

```
backend/src/routes/chroniques.js
backend/src/controllers/chroniqueController.js
backend/src/services/chroniqueService.js
backend/src/services/chroniqueMediaService.js
backend/src/storage/          # adaptateur objet (R2 derrière une interface)
backend/src/validators/chroniqueFields.js
backend/sql/008_…             # migrations ultérieures, pas maintenant
backend/docs/chronique-api.md # ce contrat
```

Montage prévu dans `index.js` (étape d’implémentation, pas celle-ci) : `app.use('/chroniques', chroniqueRoutes)` — **sans** toucher à `routes/auth.js`.

---

## 2. Modèle métier

### 2.1 Chronique

Une chronique **appartient obligatoirement** à un utilisateur (`user_id` → `users.id`).

| Champ | Obligatoire | Notes |
|---|---|---|
| `id` | oui (généré) | identifiant serveur, même famille que `users.id` (`BIGINT`) |
| `user_id` | oui | issu du JWT, jamais choisi par le client |
| `title` | non | chaîne trimée ; vide / espaces uniquement → `null` ; max **200** caractères |
| `body` | oui | texte central, voir [§4](#4-règles-métier) |
| `status` | oui | voir [§5](#5-cycle-de-vie-complet) |
| `scheduled_at` | si `scheduled` | instant UTC de passage prévu à `active` |
| `published_at` | si `active` (et conservé ensuite) | instant UTC de première activation |
| `is_time_limited` | oui | défaut `false` |
| `expires_at` | si `is_time_limited` | instant UTC de fin de visibilité dans le fil |
| `archived_at` | si `archived` | instant UTC de l’archivage manuel |
| `expired_at` | si `expired` | instant UTC où l’éphémère a quitté le fil |
| `purge_after` | si `expired` | instant UTC de suppression automatique après conservation temporaire |
| `deleted_at` | si `deleted` | instant UTC de suppression |
| `is_public` | oui | **préparé, non fonctionnel** — toujours `false` en Module 2 |
| `audience` | oui | **préparé, non fonctionnel** — toujours `"private"` en Module 2 |
| `comments_enabled` | oui | **préparé, non fonctionnel** — toujours `false` en Module 2 |
| `media_total_bytes` | oui (dérivé) | somme des tailles des médias attachés, max **209 715 200** (200 Mio) |
| `created_at` | oui | |
| `updated_at` | oui | |

Le terme « Chronique » désigne **cette** ressource. Une publication immédiate, planifiée ou éphémère est une chronique dans un statut / avec des champs temporels donnés — pas une seconde entité.

### 2.2 Média

Une chronique peut contenir **plusieurs** médias. Types prévus :

| `kind` | Module 2 |
|---|---|
| `image` | activé |
| `video` | activé |
| `audio` | activé |
| `document` | **réservé** (PDF, texte, …) — rejeté à l’écriture tant que non activé |

| Champ média | Notes |
|---|---|
| `id` | identifiant serveur |
| `chronique_id` | FK |
| `kind` | `image` \| `video` \| `audio` \| `document` |
| `storage_key` | clé d’objet **indépendante du fournisseur** (pas d’URL R2 persistée) |
| `content_type` | MIME validé |
| `byte_size` | entier ≥ 1 |
| `original_filename` | optionnel, affichage |
| `sort_order` | ordre dans la chronique (0, 1, 2, …) |
| `status` | `pending_upload` \| `ready` \| `failed` |
| `created_at` | |

Quota : la **somme** des `byte_size` des médias `ready` + `pending_upload` d’une même chronique **≤ 200 Mio**.

Plafond de cardinalité (Module 2) : **20** médias `ready` ou `pending_upload` par chronique.

### 2.3 Stockage objet

Le binaire n’est **pas** stocké dans PostgreSQL. PostgreSQL (Neon aujourd’hui, instance auto-hébergée demain) ne conserve que les **métadonnées**.

Abstraction prévue : interface de type `ObjectStorage` (`createDirectUpload`, `head`, `delete`). Implémentation initiale : Cloudflare R2 (API S3-compatible). Les services Chronique ne connaissent que `storage_key`.

### 2.4 Ressource JSON `chronique`

Réponse type (champs sociaux présents mais inertes) :

```json
{
  "id": 42,
  "title": "Premier soir",
  "body": "Le texte de la chronique, d'au moins vingt caractères.",
  "status": "active",
  "scheduled_at": null,
  "published_at": "2026-09-22T10:00:00.000Z",
  "is_time_limited": false,
  "expires_at": null,
  "archived_at": null,
  "expired_at": null,
  "purge_after": null,
  "is_public": false,
  "audience": "private",
  "comments_enabled": false,
  "media_total_bytes": 1048576,
  "media": [
    {
      "id": 7,
      "kind": "image",
      "content_type": "image/jpeg",
      "byte_size": 1048576,
      "original_filename": "soir.jpg",
      "sort_order": 0,
      "status": "ready",
      "created_at": "2026-09-22T09:59:00.000Z"
    }
  ],
  "created_at": "2026-09-22T09:50:00.000Z",
  "updated_at": "2026-09-22T10:00:00.000Z"
}
```

`user_id`, `storage_key`, `deleted_at` et les secrets ne sont **pas** renvoyés au client.

Les URLs de lecture média, si nécessaires au client, sont des **URLs signées à courte durée** calculées à la volée, jamais stockées en base. (Détail d’implémentation ; le contrat garantit seulement que le JSON `media[]` ne contient pas d’URL fournisseur stable.)

---

## 3. Endpoints API prévus

Toutes les routes ci-dessous exigent `requireAuth`, sauf mention contraire (aucune n’est publique en Module 2).

Rate limit prévu (implémentation) : même famille que l’Auth (fenêtre 15 min / IP), valeurs à caler à l’implémentation. Dépassement → `429` `{ "error": "Too many requests" }` (`Retry-After`).

CORS actuel du serveur : `GET`, `POST`, `OPTIONS`. L’implémentation des `PATCH` / `DELETE` **web** exigera d’étendre CORS **sans** changer les routes `/auth`. Hors périmètre de ce document.

Identifiant d’une chronique d’un **autre** utilisateur, id inconnu, ou chronique `deleted` : toujours **`404` `{ "error": "Chronique not found" }`** (pas d’énumération).

---

### POST `/chroniques`

Crée une chronique pour l’utilisateur authentifié.

**Authentification :** `requireAuth`.

#### Corps

```json
{
  "title": "Premier soir",
  "body": "Le texte de la chronique, d'au moins vingt caractères.",
  "publish": "draft",
  "scheduled_at": null,
  "is_time_limited": false,
  "expires_at": null
}
```

| Champ | Obligatoire | Notes |
|---|---|---|
| `title` | non | max 200 ; omis / `null` / blancs → `null` |
| `body` | oui | 20–5000 caractères après trim ; pas uniquement des espaces |
| `publish` | non | `"draft"` (défaut) \| `"now"` \| `"schedule"` |
| `scheduled_at` | si `publish = "schedule"` | ISO-8601 UTC **strictement dans le futur** |
| `is_time_limited` | non | booléen, défaut `false` |
| `expires_at` | si `is_time_limited = true` | ISO-8601 UTC **strictement après** l’instant d’activation (immédiat ou `scheduled_at`) |
| `is_public` | interdit | si présent → `400` |
| `audience` | interdit | si présent → `400` |
| `comments_enabled` | interdit | si présent → `400` |
| `user_id` | interdit | si présent → `400` |
| `media` | interdit | les médias se joignent **après** création (voir endpoints médias) |

`publish` :

| Valeur | `status` initial |
|---|---|
| `"draft"` / omis | `draft` |
| `"now"` | `active`, `published_at = NOW()` |
| `"schedule"` | `scheduled`, exige `scheduled_at` |

Une chronique éphémère peut être créée en `draft`, `scheduled` ou `active`. `expires_at` est contrôlé par rapport à l’instant d’activation **effectif** (immédiat ou planifié).

#### Succès — `201`

```json
{
  "message": "Chronique created",
  "chronique": { }
}
```

`chronique` suit le schéma du [§2.4](#24-ressource-json-chronique). `media` est `[]`.

#### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `title is invalid` |
| 400 | `body is required` |
| 400 | `body is too short` |
| 400 | `body is too long` |
| 400 | `publish is invalid` |
| 400 | `scheduled_at is required` |
| 400 | `scheduled_at must be in the future` |
| 400 | `expires_at is required` |
| 400 | `expires_at must be after activation time` |
| 400 | `is_public cannot be set` |
| 400 | `audience cannot be set` |
| 400 | `comments_enabled cannot be set` |
| 400 | `user_id cannot be set` |
| 400 | `media cannot be set on create` |
| 401 | `Unauthorized` |
| 429 | `Too many requests` |
| 503 | `Database is not configured` |

---

### GET `/chroniques`

Fil personnel de l’utilisateur authentifié (pagination).

**Authentification :** `requireAuth`.

#### Paramètres de requête

| Paramètre | Défaut | Notes |
|---|---|---|
| `status` | `active` | Un seul statut. Valeurs : `draft`, `scheduled`, `active`, `archived`, `expired`. **`deleted` interdit** → `400` |
| `limit` | `20` | entier 1–50 |
| `before_id` | omis | curseur : chroniques strictement plus anciennes que cet `id` dans l’ordre du fil |

Ordre :

- `active` : `published_at DESC`, puis `id DESC`
- `scheduled` : `scheduled_at ASC`, puis `id ASC`
- `draft` : `updated_at DESC`, puis `id DESC`
- `archived` : `archived_at DESC`, puis `id DESC`
- `expired` : `expired_at DESC`, puis `id DESC`

Le fil « récit dans le temps » côté produit = `status=active` (défaut).  
La vue archives manuelles = `status=archived`.  
La conservation temporaire des éphémères = `status=expired`.

Aucune chronique d’un autre utilisateur. Aucun mélange de statuts dans une même requête Module 2.

#### Succès — `200`

```json
{
  "items": [ ],
  "next_before_id": 10
}
```

`items` : ressources `chronique` (médias `ready` seulement).  
`next_before_id` : `null` s’il n’y a plus de page.

#### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `status is invalid` |
| 400 | `limit is invalid` |
| 400 | `before_id is invalid` |
| 401 | `Unauthorized` |
| 429 | `Too many requests` |

---

### GET `/chroniques/:id`

Consultation d’**une** chronique **appartenant** à l’utilisateur authentifié.

**Authentification :** `requireAuth`.

#### Paramètres d’URL

| Paramètre | Notes |
|---|---|
| `id` | entier positif |

Statuts lisibles par le propriétaire : `draft`, `scheduled`, `active`, `archived`, `expired`.  
`deleted` → `404` comme un id inconnu.

#### Succès — `200`

```json
{
  "chronique": { }
}
```

#### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `id is invalid` |
| 401 | `Unauthorized` |
| 404 | `Chronique not found` |
| 429 | `Too many requests` |

---

### PATCH `/chroniques/:id`

Modification des champs éditables. **N’archive pas** et **ne supprime pas** (endpoints dédiés).

**Authentification :** `requireAuth`.

#### Corps

Tous les champs sont optionnels ; au moins un champ reconnu est exigé.

```json
{
  "title": "Titre mis à jour",
  "body": "Nouveau texte d'au moins vingt caractères.",
  "publish": "now",
  "scheduled_at": null,
  "is_time_limited": true,
  "expires_at": "2026-09-29T10:00:00.000Z"
}
```

| Champ | Notes |
|---|---|
| `title` | même règles qu’à la création ; `null` efface le titre |
| `body` | 20–5000 après trim |
| `publish` | `"draft"` \| `"now"` \| `"schedule"` — transition explicite (voir [§5](#5-cycle-de-vie-complet)) |
| `scheduled_at` | requis / contrôlé si `publish = "schedule"` ou si déjà `scheduled` |
| `is_time_limited` | booléen |
| `expires_at` | requis si time-limited |

Interdits (400) : `status` brut, `user_id`, `is_public`, `audience`, `comments_enabled`, `media`, `published_at`, `archived_at`, `expired_at`, `purge_after`, `deleted_at`.

**Éditable selon le statut courant :**

| Statut | PATCH autorisé |
|---|---|
| `draft` | titre, body, publish, planification, éphémère |
| `scheduled` | titre, body, publish (`now` / `draft` pour annuler), `scheduled_at`, éphémère |
| `active` | titre, body, éphémère (`expires_at` encore dans le futur). **Pas** de retour en `draft` |
| `archived` | **non** — restaurer d’abord (`POST .../restore`) |
| `expired` | **non** |
| `deleted` | **non** (404) |

#### Succès — `200`

```json
{
  "message": "Chronique updated",
  "chronique": { }
}
```

#### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `title is invalid` |
| 400 | `body is required` |
| 400 | `body is too short` |
| 400 | `body is too long` |
| 400 | `publish is invalid` |
| 400 | `scheduled_at is required` |
| 400 | `scheduled_at must be in the future` |
| 400 | `expires_at is required` |
| 400 | `expires_at must be after activation time` |
| 400 | `No fields to update` |
| 400 | `Chronique cannot be edited in this status` |
| 409 | `Invalid status transition` |
| 401 | `Unauthorized` |
| 404 | `Chronique not found` |
| 429 | `Too many requests` |

---

### POST `/chroniques/:id/archive`

Archivage **manuel**. Conservation **indéfinie**.

**Authentification :** `requireAuth`.

#### Corps

Aucun (objet vide accepté). Pas de JSON requis.

#### Comportement

| Statut avant | Après |
|---|---|
| `active` | `archived`, `archived_at = NOW()` |
| `draft` | `archived` (retire un brouillon du flux de travail) |
| `scheduled` | `archived` (annule la planification) |
| `archived` | **200** idempotent, inchangé |
| `expired` | `400` — l’éphémère suit sa propre conservation (`purge_after`) |
| `deleted` | `404` |

Le fil `status=active` ne la contient plus. Elle apparaît dans `GET /chroniques?status=archived`.

#### Succès — `200`

```json
{
  "message": "Chronique archived",
  "chronique": { }
}
```

#### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `Chronique cannot be archived in this status` |
| 401 | `Unauthorized` |
| 404 | `Chronique not found` |
| 429 | `Too many requests` |

---

### POST `/chroniques/:id/restore`

Restauration **depuis l’archive manuelle** uniquement vers `active`.

**Authentification :** `requireAuth`.

Si `is_time_limited` et `expires_at` est déjà passé : **ne pas** réactiver → `400` `{ "error": "Chronique has expired" }` (rester `archived` ou laisser le client choisir une nouvelle `expires_at` via un PATCH après politique produit — **à valider**, voir fin de document).

#### Succès — `200`

```json
{
  "message": "Chronique restored",
  "chronique": { }
}
```

`status` = `active`. `archived_at` remis à `null`. `published_at` conservé s’il existait, sinon `NOW()`.

#### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `Chronique cannot be restored in this status` |
| 400 | `Chronique has expired` |
| 401 | `Unauthorized` |
| 404 | `Chronique not found` |
| 429 | `Too many requests` |

---

### DELETE `/chroniques/:id`

Suppression **définitive** (statut `deleted`). Hors fil, hors archives, hors lecture.

**Authentification :** `requireAuth`.

#### Corps

Aucun.

#### Comportement

1. `status = deleted`, `deleted_at = NOW()`.
2. Les objets storage des médias sont **programmés pour purge** (best-effort, asynchrone).
3. `GET` et listes → comme si la ressource n’existait pas (`404` / absente).
4. Idempotent : déjà `deleted` → `404` (pas d’aveu d’existence passée au-delà d’un 404).

Autorisé depuis : `draft`, `scheduled`, `active`, `archived`, `expired`.

#### Succès — `200`

```json
{
  "message": "Chronique deleted"
}
```

Pas de ressource dans la réponse.

#### Erreurs

| HTTP | `error` |
|---|---|
| 401 | `Unauthorized` |
| 404 | `Chronique not found` |
| 429 | `Too many requests` |

---

### POST `/chroniques/:id/media/uploads`

Démarre l’ajout d’un média. Le binaire **n’est pas** dans cette requête.

**Authentification :** `requireAuth`.

Statuts autorisés pour ajouter un média : `draft`, `scheduled`, `active`. Interdit sur `archived`, `expired`, `deleted`.

#### Corps

```json
{
  "kind": "image",
  "content_type": "image/jpeg",
  "byte_size": 1048576,
  "original_filename": "soir.jpg"
}
```

| Champ | Obligatoire | Notes |
|---|---|---|
| `kind` | oui | `image` \| `video` \| `audio` — `document` → `400` `document is not enabled` |
| `content_type` | oui | MIME autorisé pour `kind` (table [§6](#6-gestion-des-médias)) |
| `byte_size` | oui | entier ≥ 1 ; `media_total_bytes + byte_size` ≤ 200 Mio |
| `original_filename` | non | max 255, nom d’affichage uniquement |

#### Succès — `201`

```json
{
  "message": "Upload created",
  "media": {
    "id": 7,
    "kind": "image",
    "content_type": "image/jpeg",
    "byte_size": 1048576,
    "original_filename": "soir.jpg",
    "sort_order": 0,
    "status": "pending_upload"
  },
  "upload": {
    "method": "PUT",
    "url": "https://signed-upload.example/...",
    "headers": {
      "Content-Type": "image/jpeg"
    },
    "expires_at": "2026-09-22T10:15:00.000Z"
  }
}
```

`upload.url` est **éphémère** (durée courte, ex. 15 minutes). Le client envoie le binaire **directement** au storage (pas via Express, pas dans la limite JSON 32 Ko).

L’URL et les headers d’upload **ne sont pas** persistés en PostgreSQL.

#### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `kind is required` |
| 400 | `kind is invalid` |
| 400 | `document is not enabled` |
| 400 | `content_type is invalid` |
| 400 | `byte_size is invalid` |
| 400 | `Media quota exceeded` |
| 400 | `Too many media` |
| 400 | `Chronique cannot accept media in this status` |
| 401 | `Unauthorized` |
| 404 | `Chronique not found` |
| 429 | `Too many requests` |
| 503 | `Storage is not configured` |

`Media quota exceeded` : dépassement des **200 Mio** totaux.  
`Too many media` : plus de 20 médias non supprimés.

---

### POST `/chroniques/:id/media/:mediaId/complete`

Confirme la fin d’un upload direct. Le serveur vérifie côté storage (taille, type) avant de passer le média en `ready`.

**Authentification :** `requireAuth`.

#### Corps

Aucun requis.

#### Succès — `200`

```json
{
  "message": "Media ready",
  "chronique": { }
}
```

Si l’objet est absent, trop petit/grand par rapport à `byte_size`, ou d’un type différent : `media.status = failed` et :

`400` `{ "error": "Upload is incomplete" }`

Le quota est recalculé : un `failed` **ne compte plus** dans les 200 Mio ni dans les 20 médias (le client peut réessayer via un nouvel `uploads`).

#### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `Upload is incomplete` |
| 400 | `Media is not pending` |
| 401 | `Unauthorized` |
| 404 | `Chronique not found` |
| 404 | `Media not found` |
| 429 | `Too many requests` |
| 503 | `Storage is not configured` |

---

### DELETE `/chroniques/:id/media/:mediaId`

Retire un média (`pending_upload`, `ready` ou `failed`). Purge l’objet storage. Recalcule `media_total_bytes`.

**Authentification :** `requireAuth`.

Autorisé si la chronique est `draft`, `scheduled` ou `active`.

#### Succès — `200`

```json
{
  "message": "Media deleted",
  "chronique": { }
}
```

#### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `Chronique cannot accept media in this status` |
| 401 | `Unauthorized` |
| 404 | `Chronique not found` |
| 404 | `Media not found` |
| 429 | `Too many requests` |

---

### PATCH `/chroniques/:id/media/order`

Réordonne les médias `ready`.

**Authentification :** `requireAuth`.

#### Corps

```json
{
  "media_ids": [7, 9, 8]
}
```

`media_ids` : permutation **exacte** des ids `ready` de la chronique.

#### Succès — `200`

```json
{
  "message": "Media order updated",
  "chronique": { }
}
```

#### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `media_ids is invalid` |
| 401 | `Unauthorized` |
| 404 | `Chronique not found` |
| 429 | `Too many requests` |

---

## 4. Règles métier

### 4.1 Propriété

- Une chronique a **exactement un** `user_id`.
- Toutes les requêtes filtrent `user_id = req.user.userId`.
- Pas de ressource partagée en Module 2.

### 4.2 Texte

- `body` est **obligatoire** à la création et à chaque PATCH qui l’envoie.
- Longueur mesurée **après `trim()`**, en **points de code Unicode**.
- Minimum : **20**. En dessous → `body is too short`.
- Maximum : **5000**. Au-delà → `body is too long`.
- Chaîne absente, non-string, vide, ou **uniquement des espaces** (y compris Unicode) → `body is required`.
- Le titre n’est **pas** un substitut du body.

### 4.3 Titre

- Optionnel.
- Max **200** points de code après trim.
- Blancs seuls → stocké `null`.
- Pas de numérotation de chapitre, pas de préfixe imposé.

### 4.4 Médias

- Optionnels. Une chronique texte seul est valide.
- Plusieurs médias autorisés (max 20, 200 Mio cumulés).
- `document` : schéma prévu, **écriture refusée** en Module 2.
- Quota calculé sur `pending_upload` + `ready` pour empêcher deux uploads parallèles de dépasser 200 Mio.
- Le JSON de création / mise à jour **ne transporte pas** de binaire (limite Express 32 Ko **conservée** pour ne pas toucher au Module 1).

### 4.5 Temporel

- Publication **immédiate** : `publish = "now"` → `active` + `published_at`.
- Publication **planifiée** : `publish = "schedule"` + `scheduled_at` futur → `scheduled`. Un **job** (hors requête HTTP) passe `scheduled` → `active` quand `scheduled_at <= NOW()`.
- Publication **éphémère** : `is_time_limited = true` + `expires_at`. Un job passe `active` → `expired` quand `expires_at <= NOW()`.

### 4.6 Archives

- **Manuelle** (`POST .../archive`) : `archived`, conservation **indéfinie**, hors fil `active`.
- **Expiration automatique** : d’abord `expired` (plus dans le fil), conservation **temporaire** jusqu’à `purge_after`, puis suppression automatique (`deleted` + purge storage).

Délai de conservation temporaire proposé (à **valider**) : **30 jours** après `expired_at` (`purge_after = expired_at + 30d`). Constante serveur, pas un champ client.

### 4.7 Social (inerte)

À **chaque** écriture Module 2 :

- `is_public = false`
- `audience = "private"`
- `comments_enabled = false`

Toute tentative de les fixer via l’API → `400`.  
Aucun endpoint public. Aucun commentaire.

### 4.8 Jobs requis pour un cycle complet

Non livrés dans cette étape documentaire. L’implémentation devra prévoir (processus ou worker, **pas** dans les routes `/auth`) :

1. `scheduled` → `active` à `scheduled_at` ;
2. `active` + `is_time_limited` → `expired` à `expires_at` (et calcul de `purge_after`) ;
3. `expired` → `deleted` à `purge_after` + suppression des objets storage ;
4. expiration des lignes `pending_upload` trop anciennes (ex. 24 h) → `failed` + libération du quota.

Sans ces jobs, `scheduled` / `expired` / purge ne se matérialisent pas.

---

## 5. Cycle de vie complet

Statuts :

| Statut | Signification |
|---|---|
| `draft` | non publié, invisible du fil personnel `active` |
| `scheduled` | publication programmée (`scheduled_at` futur) |
| `active` | visible dans le fil personnel |
| `archived` | retiré **volontairement**, conservation indéfinie |
| `expired` | éphémère arrivé à `expires_at` ; plus dans le fil ; conservation temporaire |
| `deleted` | suppression définitive ; inaccessible |

Transitions autorisées :

```
          create(draft)
                |
                v
             draft ----------------+
               |                   |
     publish now / schedule        |
               |                   |
       +-------+--------+          |
       v                v          |
   scheduled --(job)--> active     |
       |                |          |
       |         archive (manuel)  |
       |                v          |
       +------------> archived <---+  (archive depuis draft/scheduled/active)
                        |
                        | restore (manuel)
                        v
                      active
                        |
                        | job expires_at (si is_time_limited)
                        v
                     expired
                        |
                        | job purge_after  OU  DELETE utilisateur
                        v
                     deleted
```

Depuis **tout** statut sauf déjà `deleted` : `DELETE` → `deleted`.

Interdit :

- `expired` → `active` (pas de « ressusciter » un éphémère) ;
- `expired` → `archived` (l’expiration n’est pas un archivage manuel) ;
- `archived` → `draft` ;
- `active` → `draft` ;
- `deleted` → quelconque ;
- fixer `status` librement dans un PATCH.

Éphémère + planification : `expires_at` > `scheduled_at` > `NOW()`.  
Éphémère + immédiat : `expires_at` > `NOW()`.

---

## 6. Gestion des médias

### 6.1 Principe

1. Créer (ou détenir) la chronique JSON.
2. `POST /chroniques/:id/media/uploads` → métadonnées + URL signée.
3. Client `PUT` le binaire vers le storage.
4. `POST /chroniques/:id/media/:mediaId/complete` → `ready`.
5. Réordonner / supprimer via les endpoints dédiés.

Express ne reçoit **jamais** les 200 Mio. PostgreSQL ne stocke **jamais** le binaire.

### 6.2 Abstraction fournisseur

| À persister | À ne pas persister |
|---|---|
| `storage_key` | hostname R2 / S3 |
| `content_type`, `byte_size` | URL publique durable |
| `kind` | credentials |

Implémentation initiale attendue : Cloudflare R2. Remplacer l’adaptateur ne doit pas changer ce contrat HTTP.

### 6.3 MIME autorisés (Module 2)

| `kind` | `content_type` |
|---|---|
| `image` | `image/jpeg`, `image/png`, `image/webp`, `image/heic` |
| `video` | `video/mp4`, `video/quicktime` |
| `audio` | `audio/mpeg`, `audio/mp4`, `audio/aac`, `audio/wav` |
| `document` | *non accepté en écriture* |

Liste **à valider** avant implémentation (HEIC, WAV, QuickTime).

### 6.4 Quota 200 Mio

- Unité : **octets**, plafond **209 715 200**.
- Somme par `chronique_id` des médias `pending_upload` et `ready`.
- Contrôle à `uploads` **et** à `complete` (la taille réelle de l’objet prime). Si `complete` révèle un dépassement : média `failed`, `400` `Media quota exceeded`.

### 6.5 Lecture

Le JSON liste les médias `ready`. Le client obtient une URL de lecture **signée, courte** soit :

- dans un champ optionnel `read_url` ajouté **uniquement** en réponse GET (non persisté), soit
- via un endpoint ultérieur si l’on veut éviter d’allonger le GET.

Choix d’implémentation : **`read_url` optionnel sur chaque média `ready` dans GET / GET by id / réponses de mutation**, TTL court (ex. 15 min). Non documenté comme URL stable.

---

## 7. Préparation future sociale

Colonnes / champs JSON toujours présents :

| Champ | Valeur Module 2 | Usage futur |
|---|---|---|
| `is_public` | toujours `false` | visibilité hors propriétaire |
| `audience` | toujours `"private"` | ex. `private` \| `followers` \| `public` |
| `comments_enabled` | toujours `false` | fil de commentaires |

Règles Module 2 :

- écriture client **refusée** (`400`) ;
- serveur **écrase** ces valeurs à la création ;
- **aucune** route de lecture sans `requireAuth` ;
- **aucune** liste globale / découverte ;
- un `is_public = true` présent en base par erreur **ne doit pas** suffire à exposer la ressource : le Module 2 continue de filtrer par `user_id`.

Le module social ultérieur pourra lever ces interdits **sans** changer l’identité `chronique` ni le cycle `draft` / `scheduled` / `active` / `archived` / `expired` / `deleted`.

---

## 8. Hors périmètre de ce document (et de cette étape)

- Création des fichiers `routes` / `controllers` / `services` / `validators`.
- Fichiers `sql/008_…`.
- Modification de `index.js`, CORS, limite JSON 32 Ko.
- Modification de toute route ou table Auth.
- Client Flutter.
- Jobs d’expiration / planification.
- Transcodage vidéo, antivirus, moderation, miniatures.
- Sign in with Apple côté Flutter, refresh Dio 401 (Phase B Auth).
