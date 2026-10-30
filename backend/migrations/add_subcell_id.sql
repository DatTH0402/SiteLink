-- Adds the optional Subcell-ID column (plain-SQL alternative to migrate_add_subcell_id.py)
ALTER TABLE cells_3g          ADD COLUMN IF NOT EXISTS subcell_id VARCHAR(50);
ALTER TABLE cells_4g          ADD COLUMN IF NOT EXISTS subcell_id VARCHAR(50);
ALTER TABLE cells_5g          ADD COLUMN IF NOT EXISTS subcell_id VARCHAR(50);
ALTER TABLE cell_3g_revisions ADD COLUMN IF NOT EXISTS subcell_id VARCHAR(50);
ALTER TABLE cell_4g_revisions ADD COLUMN IF NOT EXISTS subcell_id VARCHAR(50);
ALTER TABLE cell_5g_revisions ADD COLUMN IF NOT EXISTS subcell_id VARCHAR(50);

-- Check for UNIQUE indexes that would forbid two cells sharing a cell_name:
-- SELECT tablename, indexname, indexdef FROM pg_indexes
--  WHERE tablename IN ('cells_3g','cells_4g','cells_5g') AND indexdef LIKE 'CREATE UNIQUE%';
