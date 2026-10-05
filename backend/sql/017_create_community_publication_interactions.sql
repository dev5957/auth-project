-- Interactions communautaires Module 3 Lot 5 (likes, commentaires, traces éphémères).
-- À exécuter MANUELLEMENT dans Neon à l’étape prévue.
-- Le serveur ne l’applique pas. Aucune donnée, aucun secret, aucun BLOB, aucune URL.
-- Prérequis : sql/016_create_community_publications.sql.
-- Ne modifie pas users, communities, community_members, publications ni publication_media.
-- Pas de FK vers community_members (conservation des commentaires après leave/remove).

ALTER TABLE community_publications
  ADD COLUMN IF NOT EXISTS like_count BIGINT NOT NULL DEFAULT 0;

ALTER TABLE community_publications
  ADD COLUMN IF NOT EXISTS comment_count BIGINT NOT NULL DEFAULT 0;

ALTER TABLE community_publications
  DROP CONSTRAINT IF EXISTS community_publications_like_count_non_negative_check;

ALTER TABLE community_publications
  ADD CONSTRAINT community_publications_like_count_non_negative_check
  CHECK (like_count >= 0);

ALTER TABLE community_publications
  DROP CONSTRAINT IF EXISTS community_publications_comment_count_non_negative_check;

ALTER TABLE community_publications
  ADD CONSTRAINT community_publications_comment_count_non_negative_check
  CHECK (comment_count >= 0);

CREATE TABLE IF NOT EXISTS community_publication_likes (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  community_id BIGINT NOT NULL,
  community_publication_id BIGINT NOT NULL,
  user_id BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT community_publication_likes_community_id_fkey
    FOREIGN KEY (community_id) REFERENCES communities (id) ON DELETE RESTRICT,
  CONSTRAINT community_publication_likes_publication_id_fkey
    FOREIGN KEY (community_publication_id) REFERENCES community_publications (id) ON DELETE CASCADE,
  CONSTRAINT community_publication_likes_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT community_publication_likes_publication_user_key
    UNIQUE (community_publication_id, user_id)
);

CREATE INDEX IF NOT EXISTS community_publication_likes_community_user_idx
  ON community_publication_likes (community_id, user_id);

CREATE TABLE IF NOT EXISTS community_publication_comments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  community_id BIGINT NOT NULL,
  community_publication_id BIGINT NOT NULL,
  author_user_id BIGINT NOT NULL,
  body TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'visible',
  deleted_at TIMESTAMPTZ,
  deleted_by_user_id BIGINT,
  moderated_by_role TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT community_publication_comments_community_id_fkey
    FOREIGN KEY (community_id) REFERENCES communities (id) ON DELETE RESTRICT,
  CONSTRAINT community_publication_comments_publication_id_fkey
    FOREIGN KEY (community_publication_id) REFERENCES community_publications (id) ON DELETE CASCADE,
  CONSTRAINT community_publication_comments_author_user_id_fkey
    FOREIGN KEY (author_user_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT community_publication_comments_deleted_by_user_id_fkey
    FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT community_publication_comments_status_check
    CHECK (status IN ('visible', 'author_deleted', 'moderated')),
  CONSTRAINT community_publication_comments_moderated_by_role_check
    CHECK (
      moderated_by_role IS NULL
      OR moderated_by_role IN ('publication_author', 'owner', 'admin')
    ),
  CONSTRAINT community_publication_comments_moderation_shape_check
    CHECK (
      (status = 'visible' AND deleted_at IS NULL AND deleted_by_user_id IS NULL AND moderated_by_role IS NULL)
      OR (status = 'author_deleted' AND moderated_by_role IS NULL AND deleted_by_user_id IS NOT NULL)
      OR (status = 'moderated' AND moderated_by_role IS NOT NULL AND deleted_by_user_id IS NOT NULL)
    ),
  CONSTRAINT community_publication_comments_body_length_check
    CHECK (
      char_length(btrim(body)) >= 2
      AND char_length(body) <= 200
    )
);

CREATE INDEX IF NOT EXISTS community_publication_comments_visible_list_idx
  ON community_publication_comments (community_publication_id, created_at DESC, id DESC)
  WHERE status = 'visible';

CREATE INDEX IF NOT EXISTS community_publication_comments_moderation_list_idx
  ON community_publication_comments (community_publication_id, created_at DESC, id DESC)
  WHERE status IN ('visible', 'moderated');

CREATE TABLE IF NOT EXISTS community_comment_ephemeral_traces (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT NOT NULL,
  community_id BIGINT NOT NULL,
  community_publication_id BIGINT,
  publication_author_user_id BIGINT NOT NULL,
  publication_author_login TEXT NOT NULL,
  published_at TIMESTAMPTZ,
  expired_at TIMESTAMPTZ,
  comment_id BIGINT NOT NULL,
  comment_body TEXT NOT NULL,
  comment_created_at TIMESTAMPTZ NOT NULL,
  is_ephemeral BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT community_comment_ephemeral_traces_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT community_comment_ephemeral_traces_comment_id_key
    UNIQUE (comment_id)
);

CREATE INDEX IF NOT EXISTS community_comment_ephemeral_traces_user_idx
  ON community_comment_ephemeral_traces (user_id, comment_created_at DESC, comment_id DESC);
