-- Demandes d’adhésion Module 3 Lot 2.4.1.
-- À exécuter MANUELLEMENT dans Neon à l’étape prévue.
-- Le serveur ne l’applique pas. Aucune donnée, aucun secret, aucun BLOB, aucune URL.
-- Prérequis : sql/012_create_communities.sql, sql/013_create_community_invitations.sql.
-- Ne modifie pas users, communities, community_members, community_invitations,
-- community_invitation_declines, publications ni publication_media.
-- Conservation MVP : pas de DELETE CASCADE.
-- Pas de compteur de refus pour les demandes d’adhésion.

CREATE TABLE IF NOT EXISTS community_join_requests (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  community_id BIGINT NOT NULL,
  user_id BIGINT NOT NULL,
  status TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT community_join_requests_community_id_fkey
    FOREIGN KEY (community_id) REFERENCES communities (id) ON DELETE RESTRICT,
  CONSTRAINT community_join_requests_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT community_join_requests_status_check
    CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled'))
);

-- Au plus une demande pending par couple communauté / demandeur.
CREATE UNIQUE INDEX IF NOT EXISTS community_join_requests_one_pending_per_pair_key
  ON community_join_requests (community_id, user_id)
  WHERE status = 'pending';

-- File propriétaire : communauté / statut / date.
CREATE INDEX IF NOT EXISTS community_join_requests_community_status_created_idx
  ON community_join_requests (community_id, status, created_at DESC);

-- Demandes d’un utilisateur.
CREATE INDEX IF NOT EXISTS community_join_requests_user_created_idx
  ON community_join_requests (user_id, created_at DESC);
