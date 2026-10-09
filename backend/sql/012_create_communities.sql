-- Communautés Module 3 Lot 1 (métadonnées uniquement).
-- À exécuter MANUELLEMENT dans Neon à l’étape prévue.
-- Le serveur ne l’applique pas. Aucune donnée, aucun secret, aucun BLOB, aucune URL.
-- Prérequis : sql/001_create_users.sql.
-- Ne modifie pas users, publications, publication_media ni les jobs Chronique.
-- Homonymes autorisés : pas d’UNIQUE sur communities.name.
-- Conservation MVP : pas de DELETE CASCADE qui viderait une communauté.
-- Un seul propriétaire par communauté (index unique partiel).

CREATE TABLE IF NOT EXISTS communities (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  visibility TEXT NOT NULL DEFAULT 'private',
  created_by BIGINT NOT NULL,
  avatar_storage_key TEXT,
  banner_storage_key TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT communities_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT communities_visibility_check
    CHECK (visibility = 'private'),
  CONSTRAINT communities_name_length_check
    CHECK (
      char_length(btrim(name)) >= 10
      AND char_length(btrim(name)) <= 100
    ),
  CONSTRAINT communities_description_length_check
    CHECK (
      description IS NULL
      OR char_length(btrim(description)) <= 500
    )
);

CREATE TABLE IF NOT EXISTS community_members (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  community_id BIGINT NOT NULL,
  user_id BIGINT NOT NULL,
  role TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT community_members_community_id_fkey
    FOREIGN KEY (community_id) REFERENCES communities (id) ON DELETE RESTRICT,
  CONSTRAINT community_members_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT community_members_community_id_user_id_key
    UNIQUE (community_id, user_id),
  CONSTRAINT community_members_role_check
    CHECK (role IN ('owner', 'admin', 'member'))
);

-- Un seul owner par communauté.
CREATE UNIQUE INDEX IF NOT EXISTS community_members_one_owner_per_community_key
  ON community_members (community_id)
  WHERE role = 'owner';

-- Liste personnelle : communautés d’un utilisateur.
CREATE INDEX IF NOT EXISTS community_members_user_id_idx
  ON community_members (user_id);

-- Membres et rôles d’une communauté.
CREATE INDEX IF NOT EXISTS community_members_community_id_role_idx
  ON community_members (community_id, role);

-- Recherche / liste par nom (homonymes possibles).
CREATE INDEX IF NOT EXISTS communities_name_id_idx
  ON communities (name, id);
