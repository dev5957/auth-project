-- Table principale des chroniques (produit : Chronique, API : /chroniques).
-- À exécuter MANUELLEMENT dans Neon à l’étape prévue.
-- Le serveur ne l’applique pas. Aucune donnée, aucun secret.
-- Ne crée pas publication_media (migration 009).
-- Ne modifie pas users, refresh_tokens, phone_verifications.

CREATE TABLE IF NOT EXISTS publications (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT NOT NULL,
  theme_id BIGINT,
  title TEXT,
  body TEXT NOT NULL,
  status TEXT NOT NULL,
  scheduled_at TIMESTAMPTZ,
  published_at TIMESTAMPTZ,
  archived_at TIMESTAMPTZ,
  expired_at TIMESTAMPTZ,
  purge_after TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  is_time_limited BOOLEAN NOT NULL DEFAULT FALSE,
  expires_at TIMESTAMPTZ,
  is_public BOOLEAN NOT NULL DEFAULT FALSE,
  audience TEXT NOT NULL DEFAULT 'private',
  comments_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  media_total_bytes BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT publications_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT publications_status_check
    CHECK (status IN (
      'draft',
      'scheduled',
      'active',
      'archived',
      'expired',
      'deleted'
    )),
  CONSTRAINT publications_title_length_check
    CHECK (
      title IS NULL
      OR (
        char_length(btrim(title)) > 0
        AND char_length(title) <= 200
      )
    ),
  CONSTRAINT publications_body_length_check
    CHECK (
      char_length(btrim(body)) >= 20
      AND char_length(body) <= 5000
    ),
  CONSTRAINT publications_audience_check
    CHECK (audience IN ('private', 'followers', 'public')),
  CONSTRAINT publications_media_total_bytes_non_negative_check
    CHECK (media_total_bytes >= 0)
);

-- Fil personnel actif (curseur published_at DESC, id DESC).
CREATE INDEX IF NOT EXISTS publications_user_id_active_feed_idx
  ON publications (user_id, published_at DESC, id DESC)
  WHERE status = 'active';

-- Archives volontaires (curseur archived_at DESC, id DESC).
CREATE INDEX IF NOT EXISTS publications_user_id_archived_feed_idx
  ON publications (user_id, archived_at DESC, id DESC)
  WHERE status = 'archived';

-- Éphémères expirés encore conservés (curseur expired_at DESC, id DESC).
CREATE INDEX IF NOT EXISTS publications_user_id_expired_feed_idx
  ON publications (user_id, expired_at DESC, id DESC)
  WHERE status = 'expired';
