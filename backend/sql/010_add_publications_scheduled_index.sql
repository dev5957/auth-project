-- Index du fil personnel des chroniques programmées (GET /chroniques?status=scheduled).
-- À exécuter MANUELLEMENT dans Neon à l’étape prévue.
-- Le serveur ne l’applique pas. Aucune donnée, aucun secret.
-- Prérequis : sql/008_create_publications.sql.
-- Ne modifie pas users, publications (colonnes), publication_media,
-- ni les index active / archived / expired.

CREATE INDEX IF NOT EXISTS publications_user_id_scheduled_feed_idx
ON public.publications
USING btree (user_id, scheduled_at ASC, id ASC)
WHERE status = 'scheduled';
