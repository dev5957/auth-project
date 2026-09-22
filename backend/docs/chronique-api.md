# API Chronique (Module 2) — contrat

Documentation **contractuelle de référence** du Module 2.

**Statut :** SQL V1 (`008`, `009`) et architecture backend **gelés**. Implémentation runtime (routes / services) **non livrée**.

Le Module 1 (authentification) reste inchangé : tables `users`, `refresh_tokens`, `phone_verifications`, routes `/auth/*`, middleware JWT existant. Les chroniques s’appuient sur `requireAuth` et `req.user.userId` **tels qu’ils existent**.

---

## 1. Identité produit

Le concept utilisateur est **Chronique**.

L’utilisateur crée une **succession de contenus personnels** qui forment un récit dans le temps. Chaque unité créée s’appelle une **chronique**.

Le mot **« chapitre »** peut exister dans l’expérience visuelle / narrative (client Flutter). Il n’existe **pas** dans l’API :

- pas de champ `chapter_number` ;
- pas de numérotation obligatoire ;
- pas d’entité Chapitre distincte.

| Couche | Nom |
|---|---|
| Produit / UX | Chronique |
| API HTTP | `/chroniques` |
| SQL V1 | `publications`, `publication_media` |
| SQL hors V1 | `themes`, `publication_media_derivatives`, tables sociales |

Le JSON d’API parle de `chronique`. La base nomme `publications` sans exposer ce nom au client.

Architecture relationnelle V1 (métadonnées uniquement) :

```
users  (Module 1, inchangé)
  └── publications              # user_id ON DELETE RESTRICT
        └── publication_media   # publication_id ON DELETE CASCADE
```

PostgreSQL **ne contient pas** de BLOB. Les fichiers vivent dans `StorageService` (Cloudflare R2 en V1). Le modèle métier **ne dépend pas** de Cloudflare.

Le Module 2 est **individuel** : un utilisateur ne lit, ne modifie et ne supprime **que** ses propres chroniques. Aucun fil social fonctionnel, aucun commentaire, aucune visibilité tierce.

Les boutons sociaux pourront **apparaître** visuellement dans l’UI plus tard ; ils restent **non fonctionnels** dans ce module.

Préfixe HTTP : `/chroniques`  
Corps JSON : `Content-Type: application/json`  
Limite JSON globale actuelle du serveur : **32 Ko** → `413` `{ "error": "Payload too large" }`  
Les binaires **ne transitent pas** dans ce JSON (voir [§6](#6-gestion-des-médias)).  
JSON invalide → `400` `{ "error": "Invalid JSON" }`  
Erreur inattendue → `500` `{ "error": "Internal server error" }`  
Erreurs métier : `{ "error": "<message>" }` (même forme que l’Auth).

Authentification :

```http
Authorization: Bearer <access_token>
```

Identité propriétaire = claim JWT `userId`. Un `user_id` dans le body est **interdit** (`400`).

Architecture backend **gelée** (fichiers runtime **non créés**) :

```
backend/src/routes/chroniques.js
backend/src/controllers/chroniqueController.js
backend/src/services/chroniqueService.js       # métier, SQL publications, statuts
backend/src/services/chroniqueMediaService.js  # catalogue publication_media + quota
backend/src/services/storageService.js         # interface ; pas de R2 dans le métier
backend/src/validators/chroniqueFields.js
backend/sql/008_create_publications.sql        # existe
backend/sql/009_create_publication_media.sql   # existe
backend/docs/chronique-api.md
```

Couches : **routes → controllers → services → validators**.  
`publication_media` = **catalogue de métadonnées uniquement** (pas de BLOB, pas d’URL).  
`StorageService` est **séparé** du métier Chronique.

Montage prévu : `app.use('/chroniques', chroniqueRoutes)` — **sans** toucher à `routes/auth.js`.

**V1 limites :**

- **Quota utilisateur** (par publication, propriétaire JWT) : 20 médias `pending_upload`+`ready`, 200 Mio — **service**.
- **Rate limit IP** (fenêtre type Auth, 15 min) → `429` `{ "error": "Too many requests" }`. Pas de quota de débit par `userId` en V1 au-delà de l’IP.

---

## 2. Modèle métier

### 2.1 Chronique (`publications` en SQL)

Une chronique **appartient obligatoirement** à un utilisateur (`user_id` → `users.id`).

| Champ | Obligatoire | Notes |
|---|---|---|
| `id` | oui (généré) | identifiant serveur, même famille que `users.id` (`BIGINT`) |
| `user_id` | oui | issu du JWT. FK future `publications.user_id` → `users.id` **`ON DELETE RESTRICT`** : supprimer un utilisateur **ne** cascade **pas** sur ses publications |
| `theme_id` | non | **nullable**, préparation thèmes. **Pas** de table `themes` en V1. **Pas** de logique métier. Toujours `null` en écriture Module 2 |
| `title` | non | chaîne trimée ; vide / espaces uniquement → `null` ; max **200** caractères |
| `body` | oui | texte central, 20–5000 caractères après trim |
| `status` | oui | `draft` \| `scheduled` \| `active` \| `archived` \| `expired` \| `deleted` |
| `scheduled_at` | si `scheduled` | instant UTC de passage prévu à `active` |
| `published_at` | si déjà activée | instant UTC de première activation |
| `is_time_limited` | oui | défaut `false` |
| `expires_at` | si `is_time_limited` | instant UTC de fin de visibilité dans le fil |
| `archived_at` | si `archived` | archivage manuel |
| `expired_at` | si `expired` | instant où l’éphémère a quitté le fil |
| `purge_after` | si `expired` | `expired_at + 30 jours` : passage **logique** `expired` → `deleted` |
| `deleted_at` | si `deleted` | entrée en suppression logique. Hard delete SQL + `StorageService` : **30 jours après `deleted_at`** (job futur). Même délai après `deleted` pour conservation d’expirés et pour `DELETE` utilisateur |
| `is_public` | oui | **inerte** — toujours `false` en Module 2 |
| `audience` | oui | **inerte** — toujours `"private"` en Module 2 |
| `comments_enabled` | oui | **inerte** — toujours `false` en Module 2 |
| `media_total_bytes` | oui (dérivé, applicatif) | somme des tailles. Plafond **200 Mio** et max **20** médias : **couche service**, pas CHECK SQL de quota / MIME |
| `created_at` | oui | |
| `updated_at` | oui | |

Une publication immédiate, planifiée ou éphémère est **la même** ressource, avec un statut et des champs temporels différents.

### 2.2 Média (`publication_media` en SQL)

Une chronique peut contenir **plusieurs** médias. Le système reste **extensible** (nouveaux `kind`, pipeline ultérieur) sans changer l’identité Chronique.

| `kind` | V1 |
|---|---|
| `image` | activé |
| `video` | activé |
| `audio` | activé |
| `document` | **activé** (PDF, DOC, DOCX, TXT ; `source_type` = `upload` uniquement) |

Chaque média a :

- un **type** (`kind`) ;
- une **origine utilisateur** (`source_type`) ;
- des **métadonnées techniques** (`content_type`, `byte_size`, `original_filename`, `storage_key`, `status`).

| Champ média | Notes |
|---|---|
| `id` | identifiant serveur |
| `publication_id` | FK `publication_media.publication_id` → `publications.id` **`ON DELETE CASCADE`**. Un hard delete de la publication (job de purge) enlève **automatiquement** les métadonnées médias. Les objets `StorageService` sont supprimés **à part** par ce même job, avant ou autour du DELETE SQL parent. |
| `kind` | `image` \| `video` \| `audio` \| `document` |
| `source_type` | `camera` \| `gallery` \| `microphone` \| `upload` |
| `storage_key` | clé d’objet **indépendante du fournisseur** |
| `content_type` | MIME V1, voir [§6.3](#63-formats-acceptés-v1) |
| `byte_size` | entier ≥ 1 |
| `original_filename` | optionnel, affichage |
| `sort_order` | ordre dans la chronique |
| `status` | `pending_upload` \| `ready` \| `failed` |
| `created_at` | |

Quota **200 Mio** et plafond **20** médias : validés par le **service** (voir [§6.4](#64-quota-et-formats--couche-service)). La base ne porte que des contraintes **structurelles** (PK, FK **`ON DELETE CASCADE`**, NOT NULL, ensembles `kind` / `source_type` / `status` média, `storage_key` unique, `byte_size >= 1`). **Pas** de CHECK MIME ni de CHECK « 20 lignes / 200 Mio ».

#### Origine utilisateur (`source_type`)

| `kind` | Sources autorisées côté produit | `source_type` API |
|---|---|---|
| `image` | galerie de l’appareil ; photo via caméra intégrée | `gallery`, `camera` |
| `video` | galerie ; import d’une vidéo existante ; enregistrement caméra | `gallery`, `upload`, `camera` |
| `audio` | enregistrement microphone ; import d’un fichier audio | `microphone`, `upload` |
| `document` | import fichier (PDF, DOC, DOCX, TXT) | `upload` **uniquement** |

Couples `kind` / `source_type` **invalides** → `400` `{ "error": "source_type is invalid" }`.

Le serveur **ne vérifie pas** que le fichier a réellement été capturé par la caméra : `source_type` est une déclaration client, conservée pour l’UX et les statistiques. Le contrôle technique porte sur `kind`, MIME, taille et quota.

### 2.3 Stockage — `StorageService`

Le binaire n’est **pas** dans PostgreSQL (Neon aujourd’hui, PostgreSQL auto-hébergé demain = métadonnées seulement).

Abstraction obligatoire : **`StorageService`**. Les services Chronique **ne** parlent **pas** à Cloudflare. Fournisseur **actuel prévu** : Cloudflare R2, derrière cette interface.

Opérations du contrat :

| Opération | Usage |
|---|---|
| URL signée d’**upload** | le client envoie le fichier original **directement** au stockage |
| **Suppression** d’objet | retrait média, purge `deleted` / `expired` |
| URL signée de **lecture** | génération **future / à la volée**, courte durée |

Les **URLs publiques permanentes ne sont pas imposées** et ne doivent **pas** être persistées. Ni hostname fournisseur, ni credentials en base.

V1 : le stockage conserve le **fichier original**. **Aucun** encodage ni transformation automatique. L’architecture doit **permettre un pipeline média futur** (transcodage, miniatures) sans changer ce contrat HTTP.

### 2.4 Ressource JSON `chronique`

```json
{
  "id": 42,
  "theme_id": null,
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
      "source_type": "camera",
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

Non renvoyés : `user_id`, `storage_key`, `deleted_at`, secrets, URL fournisseur stable.  
`theme_id` est renvoyé (toujours `null` tant que les thèmes sont en pause). Le client **ne peut pas** le poser.

Un champ optionnel `read_url` (URL **signée**, courte, **non persistée**) pourra apparaître sur chaque média `ready` dans les GET. Il n’est pas une URL publique permanente.

---

## 3. Endpoints API

Toutes les routes exigent `requireAuth`. Aucune n’est publique en Module 2.

**Rate limit V1 :** par **IP** (famille Auth, 15 min) → `429` `{ "error": "Too many requests" }`.  
**Quota V1 :** par **utilisateur** (publication du JWT) — 20 médias / 200 Mio, couche service.

CORS actuel : `GET`, `POST`, `OPTIONS`. `PATCH` / `DELETE` web exigeront d’étendre CORS **sans** changer `/auth`. Hors de cette étape.

Id d’un **autre** utilisateur, id inconnu, ou `deleted` : **`404` `{ "error": "Chronique not found" }`**.

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
| `body` | oui | 20–5000 après trim ; espaces seuls refusés |
| `publish` | oui* | `"draft"` \| `"now"` \| `"schedule"` — voir modes ci-dessous |
| `scheduled_at` | si mode planifié | ISO-8601 UTC **strictement dans le futur** |
| `is_time_limited` | non | booléen, défaut `false` |
| `expires_at` | si `is_time_limited = true` | ISO-8601 UTC **strictement après** l’activation (immédiat ou `scheduled_at`) |
| `is_public` | interdit | `400` |
| `audience` | interdit | `400` |
| `comments_enabled` | interdit | `400` |
| `theme_id` | interdit | `400` |
| `user_id` | interdit | `400` |
| `media` | interdit | médias après création |

**Modes de création (exclusifs, gelés) :**

| Intention | Corps | `status` |
|---|---|---|
| Création **immédiate** | `publish: "now"` (pas de `scheduled_at`) | `active`, `published_at = NOW()` |
| **Planifiée** | `scheduled_at` strictement futur ; `publish: "schedule"` | `scheduled` |
| **Brouillon explicite** | `publish: "draft"` (pas de `scheduled_at`) | `draft` |

`publish` **omis** et `scheduled_at` absent → `400` `{ "error": "publish is required" }` (le brouillon n’est plus un défaut silencieux).  
`publish: "now"` avec `scheduled_at` → `400`.  
`publish: "schedule"` sans `scheduled_at` futur → `400`.  
`publish: "draft"` avec `scheduled_at` → `400`.

Une chronique éphémère peut naître dans n’importe lequel des trois modes. `expires_at` est contrôlé par rapport à l’instant d’activation **effectif**.

#### Succès — `201`

```json
{
  "message": "Chronique created",
  "chronique": { }
}
```

`media` est `[]`.

#### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `title is invalid` |
| 400 | `body is required` |
| 400 | `body is too short` |
| 400 | `body is too long` |
| 400 | `publish is required` |
| 400 | `publish is invalid` |
| 400 | `scheduled_at is required` |
| 400 | `scheduled_at must be in the future` |
| 400 | `expires_at is required` |
| 400 | `expires_at must be after activation time` |
| 400 | `is_public cannot be set` |
| 400 | `audience cannot be set` |
| 400 | `comments_enabled cannot be set` |
| 400 | `theme_id cannot be set` |
| 400 | `user_id cannot be set` |
| 400 | `media cannot be set on create` |
| 401 | `Unauthorized` |
| 429 | `Too many requests` |
| 503 | `Database is not configured` |

---

### GET `/chroniques`

Fil personnel paginé par **curseur générique** `(before_at, before_id)`. Un `before_id` **seul** est insuffisant.

**Authentification :** `requireAuth`.

| Paramètre | Défaut | Notes |
|---|---|---|
| `status` | `active` | Un seul : `draft`, `scheduled`, `active`, `archived`, `expired`. `deleted` → `400` |
| `limit` | `20` | entier 1–50 |
| `before_at` | omis | horodatage ISO-8601 UTC du dernier item de la page précédente |
| `before_id` | omis | départage si même horodatage ; **jamais seul** |

Curseur : **`before_at` et `before_id` ensemble**, ou aucun des deux.

- Première page : ni `before_at` ni `before_id`.
- Page suivante : couple renvoyé dans `next`.
- Un paramètre sans l’autre → `400` `{ "error": "cursor is incomplete" }`.

Le champ SQL comparé à `before_at` **dépend de la vue** :

| `status` | `before_at` compare | Ordre |
|---|---|---|
| `active` | `published_at` | `published_at DESC`, `id DESC` |
| `archived` | `archived_at` | `archived_at DESC`, `id DESC` |
| `expired` | `expired_at` | `expired_at DESC`, `id DESC` |
| `scheduled` | `scheduled_at` | `scheduled_at ASC`, `id ASC` |
| `draft` | `updated_at` | `updated_at DESC`, `id DESC` |

Fil `active` (prédicat page suivante, ordre décroissant) : `(published_at, id) < (before_at, before_id)`.

Fil « récit » = `status=active`. Archives volontaires = `archived`. Conservation des éphémères **non archivés** = `expired`.

#### Succès — `200`

```json
{
  "items": [ ],
  "next": {
    "before_at": "2026-09-01T12:00:00.000Z",
    "before_id": 10
  }
}
```

`items` : chroniques avec médias `ready` seulement.  
`next` : `null` s’il n’y a plus de page. `before_at` est l’horodatage de tri de **cette** vue.

#### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `status is invalid` |
| 400 | `limit is invalid` |
| 400 | `cursor is incomplete` |
| 400 | `before_at is invalid` |
| 400 | `before_id is invalid` |
| 401 | `Unauthorized` |
| 429 | `Too many requests` |

---

### GET `/chroniques/:id`

Lecture d’une chronique **appartenant** à l’utilisateur.

**Authentification :** `requireAuth`.

`id` : entier positif. Lisibles : `draft`, `scheduled`, `active`, `archived`, `expired`. `deleted` → `404`.

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

Modification. N’archive pas, ne supprime pas.

**Authentification :** `requireAuth`.

Au moins un champ reconnu.

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
| `title` | max 200 ; `null` efface |
| `body` | 20–5000 après trim |
| `publish` | `"draft"` \| `"now"` \| `"schedule"` |
| `scheduled_at` | si planification |
| `is_time_limited` | booléen |
| `expires_at` | si time-limited |

Interdits (`400`) : `status` brut, `user_id`, `theme_id`, `is_public`, `audience`, `comments_enabled`, `media`, horodatages serveur.

| Statut | PATCH |
|---|---|
| `draft` | titre, body, publish, planification, éphémère |
| `scheduled` | titre, body, publish (`now` / `draft` pour annuler), `scheduled_at`, éphémère |
| `active` | titre, body, éphémère (`expires_at` encore futur). **Pas** de retour en `draft` |
| `archived` | **non** — `POST .../restore` d’abord |
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

Archivage **manuel**. Conservation **indéfinie**. Un archivage est un **choix utilisateur**.

**Authentification :** `requireAuth`.

Corps : aucun.

#### Autorisé

| Avant | Après |
|---|---|
| `scheduled` | `archived`, `archived_at = NOW()` (annule la planification) |
| `active` | `archived`, `archived_at = NOW()` |
| `archived` | **200** idempotent |

#### Publication éphémère archivée **avant** `expires_at`

```
active (is_time_limited = true)
  → archive manuelle
archived
```

- elle **n’expire plus automatiquement** (le job d’expiration ne traite que `status = active`) ;
- elle est une **archive volontaire**, conservée comme une archive normale (durée indéfinie) ;
- `expires_at` historique **n’est plus opérant** tant qu’elle reste `archived` ;
- à l’archivage : `is_time_limited = false`, `expires_at = null` (le caractère éphémère ne survit pas au choix d’archiver).

#### Interdit

| Avant | Réponse |
|---|---|
| `draft` | `400` `{ "error": "Chronique cannot be archived in this status" }` |
| `expired` | `400` — déjà sorti du fil par expiration, pas un choix d’archive |
| `deleted` | `404` |

Hors fil `active`. Visible dans `GET /chroniques?status=archived`.

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

Restauration **depuis `archived` uniquement**, vers `active`.

**Authentification :** `requireAuth`.

Une chronique **`expired` ne peut pas être restaurée** (`400` `{ "error": "Chronique cannot be restored in this status" }`).

L’expiration **n’est pas reprise** automatiquement depuis l’ancienne valeur. Après une archive volontaire, le caractère éphémère doit être **redéfini explicitement** (ou laissé inactif).

#### Corps

Optionnel. Défaut : publication **non éphémère**.

```json
{
  "is_time_limited": false,
  "expires_at": null
}
```

| Champ | Notes |
|---|---|
| `is_time_limited` | omis / `false` → `expires_at` ignoré, publication durable |
| `expires_at` | obligatoire si `is_time_limited = true` ; ISO-8601 UTC **strictement dans le futur** |

#### Succès — `200`

```json
{
  "message": "Chronique restored",
  "chronique": { }
}
```

`status` = `active`. `archived_at` = `null`. `published_at` conservé s’il existait, sinon `NOW()`.  
Éphémère uniquement si le corps l’a demandé avec un **nouvel** `expires_at`.

#### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `Chronique cannot be restored in this status` |
| 400 | `expires_at is required` |
| 400 | `expires_at must be after activation time` |
| 401 | `Unauthorized` |
| 404 | `Chronique not found` |
| 429 | `Too many requests` |

---

### DELETE `/chroniques/:id`

Suppression **logique** utilisateur. **Pas de hard delete immédiat.**

**Authentification :** `requireAuth`.

1. `status = deleted`, `deleted_at = NOW()`.
2. La ligne `publications` et ses `publication_media` **restent en base**.
3. Les objets storage **restent**.
4. GET / listes : comme inexistante (`404` / absente).
5. Déjà `deleted` → `404`.
6. **Hard delete** (métadonnées SQL + `StorageService.delete`) : job futur, **30 jours après `deleted_at`**.

Même délai de 30 jours après `deleted` pour :

- une suppression **manuelle** (`DELETE` ci-dessus) ;
- une publication **expirée** après sa conservation (`expired` → `deleted` à `purge_after`, puis 30 jours avant hard delete).

Objectif : ne pas laisser le stockage média et Postgres dans des états divergents. Pas de hard delete immédiat.

Autorisé depuis : `draft`, `scheduled`, `active`, `archived`, `expired`.

#### Succès — `200`

```json
{
  "message": "Chronique deleted"
}
```

#### Erreurs

| HTTP | `error` |
|---|---|
| 401 | `Unauthorized` |
| 404 | `Chronique not found` |
| 429 | `Too many requests` |

---

### POST `/chroniques/:id/media/uploads`

Initie un média. Le **binaire n’est pas** dans cette requête.

**Authentification :** `requireAuth`.

Statuts : `draft`, `scheduled`, `active`. Interdit : `archived`, `expired`, `deleted`.

#### Corps

```json
{
  "kind": "image",
  "source_type": "camera",
  "content_type": "image/jpeg",
  "byte_size": 1048576,
  "original_filename": "soir.jpg"
}
```

| Champ | Obligatoire | Notes |
|---|---|---|
| `kind` | oui | `image` \| `video` \| `audio` \| `document` |
| `source_type` | oui | `camera` \| `gallery` \| `microphone` \| `upload`, cohérent avec `kind` (`document` → `upload` seulement) |
| `content_type` | oui | MIME V1 [§6.3](#63-formats-acceptés-v1) |
| `byte_size` | oui | ≥ 1 ; quota 200 Mio |
| `original_filename` | non | max 255 |

#### Succès — `201`

```json
{
  "message": "Upload created",
  "media": {
    "id": 7,
    "kind": "image",
    "source_type": "camera",
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

`upload.url` : URL **signée**, courte durée (ex. 15 min), produite par `StorageService`. Envoi **direct** client → stockage. URL et headers **non persistés**.

Fichier envoyé = **original**, sans transformation serveur V1.

#### Erreurs

| HTTP | `error` |
|---|---|
| 400 | `kind is required` |
| 400 | `kind is invalid` |
| 400 | `source_type is required` |
| 400 | `source_type is invalid` |
| 400 | `content_type is invalid` |
| 400 | `byte_size is invalid` |
| 400 | `Media quota exceeded` |
| 400 | `Too many media` |
| 400 | `Chronique cannot accept media in this status` |
| 401 | `Unauthorized` |
| 404 | `Chronique not found` |
| 429 | `Too many requests` |
| 503 | `Storage is not configured` |

---

### POST `/chroniques/:id/media/:mediaId/complete`

Confirme l’upload direct. `StorageService` vérifie l’objet (taille) avant `ready`. Pas de ré-encodage.

**Authentification :** `requireAuth`.

#### Succès — `200`

```json
{
  "message": "Media ready",
  "chronique": { }
}
```

Objet absent / taille incohérente → `failed` et `400` `{ "error": "Upload is incomplete" }`.  
`failed` ne compte plus dans le quota ni les 20 médias.

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

Retire un média (`pending_upload`, `ready`, `failed`). `StorageService.delete`. Recalcule le quota.

**Authentification :** `requireAuth`.

Autorisé si chronique `draft`, `scheduled` ou `active`.

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

```json
{
  "media_ids": [7, 9, 8]
}
```

Permutation **exacte** des ids `ready`.

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

- Exactement un `user_id`, toujours `req.user.userId`.
- Pas de ressource partagée en Module 2.

### 4.2 Texte

- `body` obligatoire à la création et à chaque PATCH qui l’envoie.
- Longueur **après `trim()`**, **points de code Unicode**.
- Minimum **20** → sinon `body is too short`.
- Maximum **5000** → sinon `body is too long`.
- Absent, non-string, vide, **espaces seuls** → `body is required`.
- Le titre ne remplace pas le body.

### 4.3 Titre

- Optionnel.
- Maximum **200** après trim.
- Espaces seuls → `null`.
- Pas de numérotation de chapitre.

### 4.4 Médias

- Optionnels (texte seul valide).
- Max **20** médias, **200 Mio** cumulés.
- `kind` + `source_type` + métadonnées techniques.
- `document` : **V1 actif** ; `source_type` = `upload` ; MIME/extensions **service** (PDF, DOC, DOCX, TXT).
- JSON API sans binaire (limite 32 Ko Auth **conservée**).
- Fichier **original** stocké ; pas de transformation V1.

### 4.5 Temporel

- Immédiat : `publish = "now"` → `active`.
- Planifié : `publish = "schedule"` → `scheduled` jusqu’au job.
- Éphémère : `is_time_limited = true` + `expires_at`.

### 4.6 Archives et éphémères

Archivage manuel **uniquement** :

- `scheduled` → `archived`
- `active` → `archived`

**Interdit :** `draft` → `archived`.  
Conservation d’une archive volontaire : **indéfinie**.

Cycle **éphémère resté `active`** jusqu’à `expires_at` :

```
active
  → (job expires_at) expired
  → (expired_at + 30 jours) deleted   // logique
  → (deleted_at + 30 jours) hard delete SQL + StorageService
```

`purge_after = expired_at + 30 days` (passage vers `deleted` seulement).  
Hard delete : **toujours** `deleted_at + 30 days`.  
**`expired` n’est pas restaurable.**

**Archive d’un éphémère avant expiration :**

```
active (is_time_limited)
  → archive manuelle
archived  (plus d’expiration auto, conservation d’archive normale)
```

Le job d’expiration **ignore** `archived`.  
À l’archivage : `is_time_limited = false`, `expires_at = null`.  
Restore : nouvelle expiration **explicite** ou publication durable (voir `POST .../restore`).

### 4.7 Social et thèmes (inertes)

À chaque écriture :

- `is_public = false`
- `audience = "private"`
- `comments_enabled = false`
- `theme_id = null`

Tentative client (`is_public`, `audience`, `comments_enabled`, `theme_id`) → `400`.  
Aucun endpoint public. UI sociale ou thèmes éventuelle **non branchée**.  
Pas de table `themes` en V1.

### 4.8 Jobs futurs (hors de cette étape)

Le contrat **exige** ces traitements pour un cycle complet. **L’implémentation des jobs n’est pas dans cette étape.**

| Job | Effet |
|---|---|
| Publication programmée | `scheduled` → `active` quand `scheduled_at <= NOW()` |
| Expiration automatique | **uniquement** `status = active` **et** `is_time_limited` → `expired` à `expires_at` ; pose `expired_at` et `purge_after`. **Jamais** une ligne `archived` |
| Passage expirés → deleted | `expired` → `deleted` à `purge_after` (`expired_at + 30 j`). Pose `deleted_at = NOW()` |
| Purge hard | `status = deleted` **et** `deleted_at + 30 jours <= NOW()` : 1) `StorageService.delete` des objets ; 2) `DELETE` SQL de la ligne `publications` (les lignes `publication_media` partent par **`ON DELETE CASCADE`**). S’applique aux `DELETE` manuels **et** aux expirés déjà passés en `deleted` |
| (complément technique) | `pending_upload` trop vieux (ex. 24 h) → `failed` + libération quota |

Sans ces jobs, planification, expiration et alignement storage / SQL ne se matérialisent pas.

---

## 5. Cycle de vie

| Statut | Signification |
|---|---|
| `draft` | créé, non publié |
| `scheduled` | planifié à une date future |
| `active` | visible dans le fil personnel |
| `archived` | retiré volontairement ; conservation indéfinie ; **n’expire plus** |
| `expired` | éphémère resté actif jusqu’à `expires_at` |
| `deleted` | suppression logique utilisateur ; métadonnées conservées jusqu’à purge |

```
                 POST /chroniques
                    |
         +----------+-----------+
         |          |           |
         v          v           v
       draft    scheduled     active     (draft explicite / scheduled_at futur / immédiat)
                    |           |
                    | job       | archive (éphémère : plus d’auto-expire)
                    +-----+-----+
                          |
                          v
                      archived
                          |
                          | restore explicite
                          v
                        active
                          |
                          | job expires_at si encore active ET is_time_limited
                          v
                       expired
                          |
                          | job +30 j  OU  DELETE utilisateur
                          v
                       deleted (logique)
                          |
                          | job deleted_at + 30 j
                          v
                    hard delete
```

`DELETE` utilisateur depuis tout statut sauf déjà `deleted` → `deleted` logique. **Pas de hard delete immédiat.** Hard delete = **30 jours après `deleted_at`**.

Interdit :

- `draft` → `archived`
- `expired` → `active` / `archived` / restore
- `archived` → `expired` (l’archive volontaire ne bascule pas en `expired`)
- `archived` → `draft`
- `active` → `draft`
- `deleted` → quelconque
- `status` libre dans un PATCH
- `theme_id` posé par le client

Éphémère + planification : `expires_at` > `scheduled_at` > `NOW()`.  
Éphémère + immédiat : `expires_at` > `NOW()`.

---

## 6. Gestion des médias

### 6.1 Flux

1. Créer / détenir la chronique JSON.
2. `POST /chroniques/:id/media/uploads` (`kind`, `source_type`, MIME, taille) → URL signée (`StorageService`).
3. Client `PUT` le **fichier original** vers le stockage.
4. `POST .../complete` → `ready` (sans transcodage).
5. Ordre / suppression via endpoints dédiés (`StorageService.delete`).

Express ne reçoit pas les 200 Mio. PostgreSQL ne stocke pas le binaire.

### 6.2 `StorageService`

| À persister | À ne pas persister |
|---|---|
| `storage_key` | hostname R2 / S3 |
| `kind`, `source_type`, `content_type`, `byte_size` | URL publique durable |
| | credentials, URL d’upload |

Fournisseur actuel prévu : **Cloudflare R2**. Remplacer l’implémentation de `StorageService` ne change pas ce contrat HTTP.

Lecture : URL **signée** générée à la volée (GET), jamais imposée comme URL publique permanente.

Pipeline **futur** (hors V1) : dérivés (poster, HLS, etc.) pourront s’ajouter **à côté** de l’original, sans remplacer l’obligation V1 de conserver l’original.

### 6.3 Formats acceptés V1

Aucun encodage automatique. MIME refusés → `content_type is invalid`.

| `kind` | `content_type` |
|---|---|
| `image` | `image/jpeg`, `image/png`, `image/webp`, `image/heic` |
| `audio` | `audio/mpeg`, `audio/mp4`, `audio/wav`, `audio/ogg` |
| `video` | `video/mp4`, `video/quicktime`, `video/webm` |
| `document` | `application/pdf`, `application/msword`, `application/vnd.openxmlformats-officedocument.wordprocessingml.document`, `text/plain` (PDF, DOC, DOCX, TXT) |

### 6.4 Quota et formats — couche service

Les règles suivantes **ne sont pas** des CHECK SQL. Elles sont appliquées par le **service / validators** :

- maximum **20** médias (`pending_upload` + `ready`) par publication ;
- quota total **200 Mio** = **209 715 200** octets (`pending_upload` + `ready`) ;
- MIME V1 listés en [§6.3](#63-formats-acceptés-v1) (y compris documents) ;
- couples `kind` / `source_type` (`document` → `upload` seulement).

Contrôle à `uploads` et à `complete`.  
La base : PK/FK, `kind` / `source_type` / `status` fermés, `storage_key` UNIQUE, `byte_size >= 1`, éventuellement colonne `media_total_bytes` **sans** CHECK de plafond.

---

## 7. Préparation sociale et thèmes

Champs toujours présents, **inactifs** en Module 2 :

| Champ | Valeur Module 2 | Futur |
|---|---|---|
| `is_public` | `false` | visibilité hors propriétaire |
| `audience` | `"private"` | ex. `private` \| `followers` \| `public` |
| `comments_enabled` | `false` | commentaires |
| `theme_id` | `null` | FK future vers `themes` |

- écriture client refusée ;
- serveur force ces valeurs à la création / archivage (`theme_id` reste `null`) ;
- **pas de table `themes` en V1** ;
- aucune route sans `requireAuth` ;
- le filtre `user_id` reste obligatoire même si `is_public` était vrai en base par erreur ;
- boutons sociaux / thèmes UI : visuels possibles, **non fonctionnels**.

Tables **hors V1** : `themes`, `publication_media_derivatives`, tables sociales.

Un module ultérieur pourra les activer **sans** changer l’identité Chronique ni les six statuts.

---

## 8. Architecture SQL gelée (prête pour `sql/008`, non créée ici)

Contrat SQL **V1 figé** après cette étape.

```
users
 └── publications              # user_id → users.id ON DELETE RESTRICT
       └── publication_media   # publication_id → publications.id ON DELETE CASCADE
```

**Tables V1 :** `publications`, `publication_media`.  
**Hors V1 :** `themes`, tables sociales, `publication_media_derivatives`.

- Métadonnées PostgreSQL uniquement. Fichiers : `StorageService` (R2 V1), `storage_key` opaque.
- **`publications.user_id` → `users.id` `ON DELETE RESTRICT`**.
- **`publication_media.publication_id` → `publications.id` `ON DELETE CASCADE`** : le hard delete parent retire les métadonnées médias ; les objets storage restent à la charge du job de purge.
- Quota 20 médias / 200 Mio / MIME : **service**, pas CHECK SQL.
- Pagination API : `before_at` + `before_id`.
- Hard delete : `deleted_at + 30 days`.

**Index partiels par vue** (pagination) :

| Vue | Index | Filtre |
|---|---|---|
| Fil actif | `(user_id, published_at DESC, id DESC)` | `WHERE status = 'active'` |
| Archives | `(user_id, archived_at DESC, id DESC)` | `WHERE status = 'archived'` |
| Expirés | `(user_id, expired_at DESC, id DESC)` | `WHERE status = 'expired'` |

Ces index de fil sont dans `008`. Index `publication_media` : `009`.

---

## 9. Architecture backend gelée (runtime non créé)

| Couche | Fichier | Rôle |
|---|---|---|
| routes | `routes/chroniques.js` | Préfixe `/chroniques`, `requireAuth` sur tout le routeur |
| controllers | `chroniqueController.js` | HTTP ↔ services, pas de SQL |
| services | `chroniqueService.js` | Publications, transitions de statut |
| services | `chroniqueMediaService.js` | Catalogue `publication_media`, quota 20 / 200 Mio |
| services | `storageService.js` | Upload/lecture/delete signés ; **pas** de R2 dans le métier |
| validators | `chroniqueFields.js` | Texte, modes POST, MIME, couples `kind`/`source_type` |

`publication_media` reste un **catalogue**. Le binaire ne transite pas par Express.

### Tests fonctionnels prévus (non créés)

Style `check-*.js`, **sans** APPLY SQL, **sans** toucher aux `test:*` Auth :

| Script npm visé | Fichier | Périmètre |
|---|---|---|
| `test:chronique-crud` | `check-chronique-crud.js` | create (3 modes) / list / get / patch, 401, 404 |
| `test:chronique-lifecycle` | `check-chronique-lifecycle.js` | archive, restore, delete logique, transitions interdites |
| `test:chronique-media` | `check-chronique-media.js` | uploads/complete avec StorageService **mock**, quota, MIME, document/`upload` |
| `test:chronique-cursor` | `check-chronique-cursor.js` | `before_at` + `before_id` |

Existants : `test:publications-schema`, `test:publication-media-schema`.

---

## 10. Hors périmètre de cette étape

- Création des fichiers runtime `routes` / `controllers` / `services` / `validators`.
- Scripts `check-chronique-*.js`.
- Modification de `index.js`, CORS, limite JSON 32 Ko.
- Toute route ou table Auth.
- Table `themes`, dérivés média, tables sociales.
- Client Flutter.
- **Implémentation** des jobs — [§4.8](#48-jobs-futurs-hors-de-cette-étape).
- Pipeline média (transcodage, miniatures, antivirus).
- Phase B Auth (refresh Dio 401).
