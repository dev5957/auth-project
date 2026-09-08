-- Demandes temporaires de vérification SMS, AVANT création d’un compte users.
-- Un utilisateur ne doit pas être inséré dans users tant que le SMS n’est pas validé.
-- Ne contient aucune donnée, aucun code en clair, aucun secret.

CREATE TABLE IF NOT EXISTS phone_verifications (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  verification_token TEXT NOT NULL,
  phone_number TEXT NOT NULL,
  code_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT phone_verifications_verification_token_key UNIQUE (verification_token),
  CONSTRAINT phone_verifications_attempts_check CHECK (attempts >= 0)
);

-- Recherches par numéro et demandes les plus récentes.
CREATE INDEX IF NOT EXISTS phone_verifications_phone_number_created_at_idx
  ON phone_verifications (phone_number, created_at DESC);
