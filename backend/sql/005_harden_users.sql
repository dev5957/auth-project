-- Durcissement PostgreSQL de l’authentification (contraintes / index).
-- À exécuter MANUELLEMENT dans Neon après `npm run test:sql-hardening`.
-- Non destructif : aucun DROP TABLE/COLUMN, DELETE, TRUNCATE, ni UPDATE de données.
-- Idempotent : peut être relancé. Échoue sans modifier les lignes s’il existe
-- des doublons sur users.phone_number (les corriger manuellement puis réexécuter).

-- Index partiel pour les refresh tokens actifs (login : plafond 5 sessions,
-- réutilisation : révocation de tous les jetons non révoqués d’un user_id).
-- N’est pas un doublon de refresh_tokens_user_id_idx (celui-ci n’a pas de prédicat).
CREATE INDEX IF NOT EXISTS refresh_tokens_user_id_active_idx
  ON refresh_tokens (user_id)
  WHERE revoked_at IS NULL;

-- UNIQUE applicatif déjà vérifié dans registerService ; cette contrainte
-- aligne PostgreSQL. Comparaison TEXT sensible à la casse (comme email/login).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'users_phone_number_unique'
      AND conrelid = 'public.users'::regclass
  ) THEN
    IF EXISTS (
      SELECT 1
      FROM public.users
      GROUP BY phone_number
      HAVING COUNT(*) > 1
    ) THEN
      RAISE EXCEPTION
        'Cannot add users_phone_number_unique: duplicate phone_number values exist. Fix those rows manually, then retry this migration.';
    END IF;

    ALTER TABLE public.users
      ADD CONSTRAINT users_phone_number_unique UNIQUE (phone_number);
  END IF;
END $$;
