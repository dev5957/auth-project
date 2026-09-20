-- Demandes temporaires de réinitialisation de mot de passe (comptes locaux).
-- À exécuter MANUELLEMENT dans Neon à l’étape prévue.
-- Le serveur ne l’applique pas. Aucun code en clair, aucun secret.

CREATE TABLE IF NOT EXISTS password_reset_requests (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT NOT NULL,
  email TEXT NOT NULL,
  code_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT password_reset_requests_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT password_reset_requests_attempts_check CHECK (attempts >= 0)
);

CREATE INDEX IF NOT EXISTS password_reset_requests_email_created_at_idx
  ON password_reset_requests (email, created_at DESC);

CREATE INDEX IF NOT EXISTS password_reset_requests_user_id_active_idx
  ON password_reset_requests (user_id)
  WHERE used_at IS NULL;
