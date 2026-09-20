-- Passe password_reset_requests du facteur email au numéro de téléphone vérifié.
-- À exécuter MANUELLEMENT dans Neon à l’étape prévue.
-- Le serveur ne l’applique pas. Ne pas réécrire 006 (déjà exécuté).
-- Colonnes conservées : user_id, code_hash, expires_at, attempts, used_at, created_at.
--
-- Inspection recommandée AVANT exécution (SELECT uniquement) :
--   SELECT COUNT(*) AS n FROM password_reset_requests;
--   SELECT COUNT(*) AS active_n
--     FROM password_reset_requests
--    WHERE used_at IS NULL AND expires_at > NOW();
--
-- Stratégie : ALTER TABLE (pas DROP TABLE, pas de recréation).
-- Les éventuelles lignes de l’ère email (phone_number NULL) ne prouvent pas
-- la possession du téléphone : elles sont supprimées. Table vide = no-op.
-- Ne pas réutiliser phone_verifications pour le reset mot de passe.

ALTER TABLE password_reset_requests
  ADD COLUMN IF NOT EXISTS phone_number TEXT;

DELETE FROM password_reset_requests
 WHERE phone_number IS NULL;

ALTER TABLE password_reset_requests
  ALTER COLUMN phone_number SET NOT NULL;

DROP INDEX IF EXISTS password_reset_requests_email_created_at_idx;

ALTER TABLE password_reset_requests
  DROP COLUMN IF EXISTS email;

CREATE INDEX IF NOT EXISTS password_reset_requests_phone_number_created_at_idx
  ON password_reset_requests (phone_number, created_at DESC);

CREATE INDEX IF NOT EXISTS password_reset_requests_user_id_active_idx
  ON password_reset_requests (user_id)
  WHERE used_at IS NULL;
