-- Schéma principal des utilisateurs.
-- À exécuter manuellement dans Neon à l’étape prévue.
-- Ne contient aucune donnée, aucun secret, aucun utilisateur de test.

CREATE TABLE IF NOT EXISTS users (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email TEXT NOT NULL,
  birth_date DATE NOT NULL,
  phone_number TEXT NOT NULL,
  phone_verified BOOLEAN NOT NULL DEFAULT FALSE,
  login TEXT NOT NULL,
  password_hash TEXT,
  auth_provider TEXT NOT NULL,
  provider_user_id TEXT,
  first_name TEXT,
  last_name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT users_email_key UNIQUE (email),
  CONSTRAINT users_login_key UNIQUE (login),
  CONSTRAINT users_auth_provider_check
    CHECK (auth_provider IN ('local', 'google', 'apple'))
);

-- Unique lorsque provider_user_id est renseigné (Google/Apple).
-- Les comptes locaux peuvent tous avoir provider_user_id NULL.
CREATE UNIQUE INDEX IF NOT EXISTS users_provider_user_id_key
  ON users (auth_provider, provider_user_id)
  WHERE provider_user_id IS NOT NULL;
