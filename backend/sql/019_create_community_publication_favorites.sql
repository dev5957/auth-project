-- Favoris personnels des publications communautaires.
-- À exécuter MANUELLEMENT dans Neon à l’étape prévue.
-- Le serveur ne l’applique pas. Aucune donnée, aucun secret, aucun BLOB, aucune URL.
-- Prérequis : sql/016_create_community_publications.sql.
-- Ne modifie pas users, communities, community_members, publications, publication_media,
-- ni les compteurs like_count / comment_count.
-- Pas de FK vers community_members (les associations sont purgées au leave/remove).
-- Le compteur public est calculé par agrégation SQL (COUNT), sans colonne matérialisée.

CREATE TABLE IF NOT EXISTS community_publication_favorites (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  community_id BIGINT NOT NULL,
  community_publication_id BIGINT NOT NULL,
  user_id BIGINT NOT NULL,
  favorited_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT community_publication_favorites_community_id_fkey
    FOREIGN KEY (community_id) REFERENCES communities (id) ON DELETE RESTRICT,
  CONSTRAINT community_publication_favorites_publication_id_fkey
    FOREIGN KEY (community_publication_id) REFERENCES community_publications (id) ON DELETE CASCADE,
  CONSTRAINT community_publication_favorites_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT community_publication_favorites_publication_user_key
    UNIQUE (community_publication_id, user_id)
);

CREATE INDEX IF NOT EXISTS community_publication_favorites_user_favorited_idx
  ON community_publication_favorites (user_id, favorited_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS community_publication_favorites_community_user_idx
  ON community_publication_favorites (community_id, user_id);

CREATE INDEX IF NOT EXISTS community_publication_favorites_publication_idx
  ON community_publication_favorites (community_publication_id);
