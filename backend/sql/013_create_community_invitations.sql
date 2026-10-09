-- Invitations Module 3 Lot 2.3.1.
-- À exécuter MANUELLEMENT dans Neon à l’étape prévue.
-- Le serveur ne l’applique pas. Aucune donnée, aucun secret, aucun BLOB, aucune URL.
-- Prérequis : sql/012_create_communities.sql.
-- Ne modifie pas users, communities, community_members, publications ni publication_media.
-- Conservation MVP : pas de DELETE CASCADE.
-- Pas de table de demandes d’adhésion (lot 2.4).
-- Compteur de refus persisté et réinitialisable (pas un COUNT historique des declined).

CREATE TABLE IF NOT EXISTS community_invitations (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  community_id BIGINT NOT NULL,
  invitee_user_id BIGINT NOT NULL,
  invited_by_user_id BIGINT NOT NULL,
  status TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT community_invitations_community_id_fkey
    FOREIGN KEY (community_id) REFERENCES communities (id) ON DELETE RESTRICT,
  CONSTRAINT community_invitations_invitee_user_id_fkey
    FOREIGN KEY (invitee_user_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT community_invitations_invited_by_user_id_fkey
    FOREIGN KEY (invited_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT community_invitations_status_check
    CHECK (status IN ('pending', 'accepted', 'declined', 'replaced', 'cancelled')),
  CONSTRAINT community_invitations_no_self_invite_check
    CHECK (invitee_user_id <> invited_by_user_id)
);

-- Au plus une invitation pending par couple communauté / destinataire.
CREATE UNIQUE INDEX IF NOT EXISTS community_invitations_one_pending_per_pair_key
  ON community_invitations (community_id, invitee_user_id)
  WHERE status = 'pending';

-- Inbox destinataire.
CREATE INDEX IF NOT EXISTS community_invitations_invitee_status_created_idx
  ON community_invitations (invitee_user_id, status, created_at DESC);

-- Liste / lock par communauté.
CREATE INDEX IF NOT EXISTS community_invitations_community_status_idx
  ON community_invitations (community_id, status);

CREATE TABLE IF NOT EXISTS community_invitation_declines (
  community_id BIGINT NOT NULL,
  invitee_user_id BIGINT NOT NULL,
  decline_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT community_invitation_declines_pkey
    PRIMARY KEY (community_id, invitee_user_id),
  CONSTRAINT community_invitation_declines_community_id_fkey
    FOREIGN KEY (community_id) REFERENCES communities (id) ON DELETE RESTRICT,
  CONSTRAINT community_invitation_declines_invitee_user_id_fkey
    FOREIGN KEY (invitee_user_id) REFERENCES users (id) ON DELETE RESTRICT,
  CONSTRAINT community_invitation_declines_count_check
    CHECK (decline_count >= 0 AND decline_count <= 5)
);
