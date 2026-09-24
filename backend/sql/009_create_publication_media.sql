-- Métadonnées médias des chroniques (fichiers hors PostgreSQL : StorageService / R2).
-- À exécuter MANUELLEMENT dans Neon à l’étape prévue.
-- Le serveur ne l’applique pas. Aucune donnée, aucun secret, aucun BLOB, aucune URL.
-- Prérequis : sql/008_create_publications.sql.
-- Ne modifie pas users ni publications (sauf FK enfant).

CREATE TABLE IF NOT EXISTS publication_media (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  publication_id BIGINT NOT NULL,
  kind TEXT NOT NULL,
  source_type TEXT NOT NULL,
  storage_key TEXT NOT NULL,
  content_type TEXT NOT NULL,
  byte_size BIGINT NOT NULL,
  original_filename TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending_upload',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT publication_media_publication_id_fkey
    FOREIGN KEY (publication_id) REFERENCES publications (id) ON DELETE CASCADE,
  CONSTRAINT publication_media_storage_key_key UNIQUE (storage_key),
  CONSTRAINT publication_media_kind_check
    CHECK (kind IN ('image', 'video', 'audio', 'document')),
  CONSTRAINT publication_media_source_type_check
    CHECK (source_type IN ('camera', 'gallery', 'microphone', 'upload')),
  CONSTRAINT publication_media_status_check
    CHECK (status IN ('pending_upload', 'ready', 'failed')),
  CONSTRAINT publication_media_byte_size_check
    CHECK (byte_size >= 1),
  CONSTRAINT publication_media_sort_order_check
    CHECK (sort_order >= 0),
  CONSTRAINT publication_media_original_filename_length_check
    CHECK (
      original_filename IS NULL
      OR char_length(original_filename) <= 255
    )
);

-- Chargement des médias d’une chronique (GET / ordre).
CREATE INDEX IF NOT EXISTS publication_media_publication_id_sort_order_idx
  ON publication_media (publication_id, sort_order);

-- Ordre publié : une position par média ready.
CREATE UNIQUE INDEX IF NOT EXISTS publication_media_publication_id_ready_sort_order_key
  ON publication_media (publication_id, sort_order)
  WHERE status = 'ready';
