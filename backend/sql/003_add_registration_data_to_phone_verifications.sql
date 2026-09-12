-- Données d’inscription locale temporaires, avant validation SMS et avant toute ligne dans users.
-- Le mot de passe ne doit jamais être stocké en clair : uniquement password_hash dans le JSON.
-- Champs attendus : email, birth_date, phone_number, login, password_hash, first_name, last_name.
-- Ne contient aucune donnée réelle, aucun secret.

ALTER TABLE phone_verifications
  ADD COLUMN IF NOT EXISTS registration_data JSONB;
