-- Commentaires de publications communautaires : un niveau de réponse (UX-L5-01).
-- À exécuter MANUELLEMENT dans Neon à l’étape prévue.
-- Le serveur ne l’applique pas. Aucune donnée, aucun secret, aucun BLOB, aucune URL.
-- Prérequis : sql/017_create_community_publication_interactions.sql.
-- Ne modifie pas users, communities, community_members, publications, publication_media
-- ni la migration 017.

ALTER TABLE community_publication_comments
  ADD COLUMN IF NOT EXISTS parent_comment_id BIGINT NULL;

ALTER TABLE community_publication_comments
  DROP CONSTRAINT IF EXISTS community_publication_comments_parent_not_self_check;

ALTER TABLE community_publication_comments
  ADD CONSTRAINT community_publication_comments_parent_not_self_check
  CHECK (parent_comment_id IS NULL OR parent_comment_id <> id);

CREATE UNIQUE INDEX IF NOT EXISTS community_publication_comments_id_publication_uidx
  ON community_publication_comments (id, community_publication_id);

ALTER TABLE community_publication_comments
  DROP CONSTRAINT IF EXISTS community_publication_comments_parent_same_publication_fkey;

ALTER TABLE community_publication_comments
  ADD CONSTRAINT community_publication_comments_parent_same_publication_fkey
  FOREIGN KEY (parent_comment_id, community_publication_id)
  REFERENCES community_publication_comments (id, community_publication_id)
  ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS community_publication_comments_parent_idx
  ON community_publication_comments (parent_comment_id, created_at ASC, id ASC)
  WHERE parent_comment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS community_publication_comments_roots_visible_idx
  ON community_publication_comments (community_publication_id, created_at DESC, id DESC)
  WHERE parent_comment_id IS NULL AND status = 'visible';

CREATE INDEX IF NOT EXISTS community_publication_comments_roots_moderation_idx
  ON community_publication_comments (community_publication_id, created_at DESC, id DESC)
  WHERE parent_comment_id IS NULL AND status IN ('visible', 'moderated');

CREATE OR REPLACE FUNCTION community_publication_comments_parent_must_be_root()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.parent_comment_id IS NULL THEN
    RETURN NEW;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM community_publication_comments parent
    WHERE parent.id = NEW.parent_comment_id
      AND parent.parent_comment_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'parent comment must be a root comment'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS community_publication_comments_parent_must_be_root_trg
  ON community_publication_comments;

CREATE TRIGGER community_publication_comments_parent_must_be_root_trg
  BEFORE INSERT OR UPDATE OF parent_comment_id
  ON community_publication_comments
  FOR EACH ROW
  EXECUTE PROCEDURE community_publication_comments_parent_must_be_root();
