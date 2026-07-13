-- ============================================================
-- SiteLink DB Migration: add new columns
-- Run with: psql -U sitelink -d sitelink_db -f migrate_add_fields.sql
-- Or inside docker: docker exec -i sitelink_postgres psql -U sitelink -d sitelink_db < migrate_add_fields.sql
-- ============================================================

-- Cell 3G
ALTER TABLE cells_3g
  ADD COLUMN IF NOT EXISTS site_name_old VARCHAR(100),
  ADD COLUMN IF NOT EXISTS cell_name_old VARCHAR(100);

-- Cell 4G
ALTER TABLE cells_4g
  ADD COLUMN IF NOT EXISTS site_name_old VARCHAR(100),
  ADD COLUMN IF NOT EXISTS cell_name_old VARCHAR(100);

-- Cell 5G
ALTER TABLE cells_5g
  ADD COLUMN IF NOT EXISTS site_name_old VARCHAR(100),
  ADD COLUMN IF NOT EXISTS cell_name_old VARCHAR(100);

-- Antennas
ALTER TABLE antennas
  ADD COLUMN IF NOT EXISTS is_5g_aau     BOOLEAN     NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS spec_file_path VARCHAR(500),
  ADD COLUMN IF NOT EXISTS spec_file_name VARCHAR(255);

SELECT 'Migration completed successfully.' AS result;
