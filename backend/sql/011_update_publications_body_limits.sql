-- Limites de texte Module 2 : 10 caractères non blancs (minimum), 1 000 (maximum).
-- À exécuter MANUELLEMENT dans Neon à l’étape prévue.
-- Le serveur ne l’applique pas. Aucune donnée n’est réécrite. Aucun secret.
-- Prérequis : sql/008_create_publications.sql.
-- Ne modifie pas users, publication_media, ni le quota 200 MiB / 5 médias
-- (le plafond médias reste couche service, sans CHECK SQL, pour ne pas
-- bloquer les chroniques existantes qui ont déjà plus de 5 médias).
--
-- NOT VALID : les lignes déjà présentes (éventuellement > 1 000 caractères
-- après l’ancienne règle 20–5000) ne sont ni validées ni altérées.
-- Les INSERT / UPDATE ultérieurs sont contrôlés.
-- Ne pas exécuter VALIDATE CONSTRAINT tant que les anciens textes longs
-- n’ont pas été traités hors de ce lot.

ALTER TABLE publications
  DROP CONSTRAINT IF EXISTS publications_body_length_check;

ALTER TABLE publications
  ADD CONSTRAINT publications_body_length_check
  CHECK (
    char_length(regexp_replace(btrim(body), '\s', '', 'g')) >= 10
    AND char_length(body) <= 1000
  ) NOT VALID;
