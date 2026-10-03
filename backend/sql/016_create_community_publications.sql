-- Publications communautaires Module 3 Lot 4.
-- À exécuter MANUELLEMENT dans Neon à l’étape prévue.
-- Le serveur ne l’applique pas. Aucune donnée, aucun secret, aucun BLOB, aucune URL.
-- Prérequis : sql/001_create_users.sql, sql/012_create_communities.sql.
-- Ne modifie pas users, communities, community_members, publications ni publication_media.
-- Pas de FK vers community_members (conservation après leave/remove).
-- Pas d’état archived. Quota 5 médias / 200 Mio : couche service.

CREATE TABLE IF NOT EXISTS community_publications (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  community_id BIGINT NOT NULL,
  author_user_id BIGINT NOT NULL,
  title TEXT,
  body TEXT NOT NULL,
  status TEXT NOT NULL,
  scheduled_at TIMESTAMPTZ,
  published_at TIMESTAMPTZ,
  expired_at TIMESTAMPTZ,
  purge_after TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  deleted_by_user_id BIGINT,
  is_time_limited BOOLEAN NOT NULL DEFAULT FALSE,
  expires_at TIMESTAMPTZ,
  comments_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  media_total_bytes BIGINT NOT NULL DEFAULT 0,
  initial_media_count INTEGER NOT NULL DEFAULT 0,
  initial_media_open BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT community_publications_community_id_fkey
    FOREIGN KEY (community_id) REFERENCES communities (id) ON DELETE RESTRICT,
  CONSTRAINT community_publications_author_user_id_fkey
    FOREIGN KEY (author_user_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT community_publications_deleted_by_user_id_fkey
    FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT community_publications_status_check
    CHECK (status IN (
      'draft',
      'scheduled',
      'active',
      'expired',
      'deleted'
    )),
  CONSTRAINT community_publications_title_length_check
    CHECK (
      title IS NULL
      OR (
        char_length(btrim(title)) > 0
        AND char_length(title) <= 200
      )
    ),
  CONSTRAINT community_publications_body_length_check
    CHECK (
      char_length(regexp_replace(btrim(body), '\s', '', 'g')) >= 10
      AND char_length(body) <= 1000
    ),
  CONSTRAINT community_publications_media_total_bytes_non_negative_check
    CHECK (media_total_bytes >= 0),
  CONSTRAINT community_publications_initial_media_count_check
    CHECK (initial_media_count >= 0 AND initial_media_count <= 5)
);

CREATE INDEX IF NOT EXISTS community_publications_community_active_feed_idx
  ON community_publications (community_id, published_at DESC, id DESC)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS community_publications_author_id_idx
  ON community_publications (author_user_id, updated_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS community_publications_scheduled_job_idx
  ON community_publications (scheduled_at ASC, id ASC)
  WHERE status = 'scheduled';

CREATE INDEX IF NOT EXISTS community_publications_expire_job_idx
  ON community_publications (expires_at ASC, id ASC)
  WHERE status = 'active' AND is_time_limited = TRUE;

CREATE INDEX IF NOT EXISTS community_publications_purge_job_idx
  ON community_publications (purge_after ASC, id ASC)
  WHERE status = 'expired';

CREATE TABLE IF NOT EXISTS community_publication_media (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  community_publication_id BIGINT NOT NULL,
  kind TEXT NOT NULL,
  source_type TEXT NOT NULL,
  storage_key TEXT NOT NULL,
  content_type TEXT NOT NULL,
  byte_size BIGINT NOT NULL,
  original_filename TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending_upload',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT community_publication_media_publication_id_fkey
    FOREIGN KEY (community_publication_id) REFERENCES community_publications (id) ON DELETE CASCADE,
  CONSTRAINT community_publication_media_storage_key_key UNIQUE (storage_key),
  CONSTRAINT community_publication_media_kind_check
    CHECK (kind IN ('image', 'video', 'audio', 'document')),
  CONSTRAINT community_publication_media_source_type_check
    CHECK (source_type IN ('camera', 'gallery', 'microphone', 'upload')),
  CONSTRAINT community_publication_media_status_check
    CHECK (status IN ('pending_upload', 'ready', 'failed')),
  CONSTRAINT community_publication_media_byte_size_check
    CHECK (byte_size >= 1),
  CONSTRAINT community_publication_media_sort_order_check
    CHECK (sort_order >= 0),
  CONSTRAINT community_publication_media_original_filename_length_check
    CHECK (
      original_filename IS NULL
      OR char_length(original_filename) <= 255
    )
);

CREATE INDEX IF NOT EXISTS community_publication_media_publication_sort_idx
  ON community_publication_media (community_publication_id, sort_order);

CREATE UNIQUE INDEX IF NOT EXISTS community_publication_media_ready_sort_key
  ON community_publication_media (community_publication_id, sort_order)
  WHERE status = 'ready';
