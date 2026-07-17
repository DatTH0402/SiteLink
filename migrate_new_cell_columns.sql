-- ============================================================
-- SiteLink DB Migration: new cell columns (3G / 4G / 5G)
-- Run with:
--   docker exec -i sitelink_postgres psql -U sitelink -d sitelink_db \
--     < migrate_new_cell_columns.sql
-- ============================================================

-- ── Cell 3G ──────────────────────────────────────────────────────────────────
ALTER TABLE cells_3g
  ADD COLUMN IF NOT EXISTS uarfcn            VARCHAR(50),
  ADD COLUMN IF NOT EXISTS lac               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS rac               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS ura_id            VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cell_max_power    VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cpich_power       VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bbu_name          VARCHAR(100),
  ADD COLUMN IF NOT EXISTS cell_status       VARCHAR(100);

-- ── Cell 4G ──────────────────────────────────────────────────────────────────
ALTER TABLE cells_4g
  ADD COLUMN IF NOT EXISTS enodeb_id         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS tac               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bandwidth         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cell_max_power    VARCHAR(50),
  ADD COLUMN IF NOT EXISTS eci               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bbu_name          VARCHAR(100),
  ADD COLUMN IF NOT EXISTS cell_status       VARCHAR(100);

-- ── Cell 5G ──────────────────────────────────────────────────────────────────
ALTER TABLE cells_5g
  ADD COLUMN IF NOT EXISTS gnodeb_id         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS tac               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS ssb_arfcn         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS center_arfcn      VARCHAR(50),
  ADD COLUMN IF NOT EXISTS gscn              VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bandwidth         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cell_max_power    VARCHAR(50),
  ADD COLUMN IF NOT EXISTS nci               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bbu_name          VARCHAR(100),
  ADD COLUMN IF NOT EXISTS mu_mimo           VARCHAR(20),
  ADD COLUMN IF NOT EXISTS cell_status       VARCHAR(100);

-- ── Cell 3G revisions ─────────────────────────────────────────────────────────
ALTER TABLE cell_3g_revisions
  ADD COLUMN IF NOT EXISTS uarfcn            VARCHAR(50),
  ADD COLUMN IF NOT EXISTS lac               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS rac               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS ura_id            VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cell_max_power    VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cpich_power       VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bbu_name          VARCHAR(100),
  ADD COLUMN IF NOT EXISTS cell_status       VARCHAR(100);

-- ── Cell 4G revisions ─────────────────────────────────────────────────────────
ALTER TABLE cell_4g_revisions
  ADD COLUMN IF NOT EXISTS enodeb_id         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS tac               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bandwidth         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cell_max_power    VARCHAR(50),
  ADD COLUMN IF NOT EXISTS eci               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bbu_name          VARCHAR(100),
  ADD COLUMN IF NOT EXISTS cell_status       VARCHAR(100);

-- ── Cell 5G revisions ─────────────────────────────────────────────────────────
ALTER TABLE cell_5g_revisions
  ADD COLUMN IF NOT EXISTS gnodeb_id         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS tac               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS ssb_arfcn         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS center_arfcn      VARCHAR(50),
  ADD COLUMN IF NOT EXISTS gscn              VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bandwidth         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cell_max_power    VARCHAR(50),
  ADD COLUMN IF NOT EXISTS nci               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bbu_name          VARCHAR(100),
  ADD COLUMN IF NOT EXISTS mu_mimo           VARCHAR(20),
  ADD COLUMN IF NOT EXISTS cell_status       VARCHAR(100);

SELECT 'New cell columns migration completed.' AS result;
