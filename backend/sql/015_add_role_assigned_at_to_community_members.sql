-- Migration manuelle 015 — Module 3 Lot 3
-- À exécuter manuellement dans Neon.
-- Ajoute role_assigned_at pour départager les admins (successeur du owner).
-- Ne DROP aucune table. Ne CASCADE rien. Ne touche pas 012/013/014.

ALTER TABLE community_members
  ADD COLUMN IF NOT EXISTS role_assigned_at TIMESTAMPTZ;

UPDATE community_members
SET role_assigned_at = COALESCE(role_assigned_at, created_at)
WHERE role = 'admin'
  AND role_assigned_at IS NULL;

CREATE INDEX IF NOT EXISTS community_members_admin_assigned_idx
  ON community_members (community_id, role_assigned_at ASC, user_id ASC)
  WHERE role = 'admin';
