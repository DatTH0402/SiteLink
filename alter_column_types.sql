-- alter_float_to_string.sql

BEGIN;

-- ── sites ────────────────────────────────────────────────────────────────────
ALTER TABLE sites
  ALTER COLUMN do_cao_dinh_cot_anten TYPE VARCHAR(50) USING do_cao_dinh_cot_anten::TEXT,
  ALTER COLUMN do_cao_cot_anten      TYPE VARCHAR(50) USING do_cao_cot_anten::TEXT;

-- ── cells_3g ─────────────────────────────────────────────────────────────────
ALTER TABLE cells_3g
  ALTER COLUMN do_cao_anten TYPE VARCHAR(50) USING do_cao_anten::TEXT,
  ALTER COLUMN azimuth      TYPE VARCHAR(50) USING azimuth::TEXT,
  ALTER COLUMN m_tilt       TYPE VARCHAR(50) USING m_tilt::TEXT,
  ALTER COLUMN e_tilt       TYPE VARCHAR(50) USING e_tilt::TEXT,
  ALTER COLUMN total_tilt   TYPE VARCHAR(50) USING total_tilt::TEXT;

-- ── cells_4g ─────────────────────────────────────────────────────────────────
ALTER TABLE cells_4g
  ALTER COLUMN do_cao_anten TYPE VARCHAR(50) USING do_cao_anten::TEXT,
  ALTER COLUMN azimuth      TYPE VARCHAR(50) USING azimuth::TEXT,
  ALTER COLUMN m_tilt       TYPE VARCHAR(50) USING m_tilt::TEXT,
  ALTER COLUMN e_tilt       TYPE VARCHAR(50) USING e_tilt::TEXT,
  ALTER COLUMN total_tilt   TYPE VARCHAR(50) USING total_tilt::TEXT;

-- ── cells_5g ─────────────────────────────────────────────────────────────────
ALTER TABLE cells_5g
  ALTER COLUMN do_cao_anten TYPE VARCHAR(50) USING do_cao_anten::TEXT,
  ALTER COLUMN azimuth      TYPE VARCHAR(50) USING azimuth::TEXT,
  ALTER COLUMN m_tilt       TYPE VARCHAR(50) USING m_tilt::TEXT,
  ALTER COLUMN e_tilt       TYPE VARCHAR(50) USING e_tilt::TEXT,
  ALTER COLUMN total_tilt   TYPE VARCHAR(50) USING total_tilt::TEXT;

-- ── revision tables (snapshot columns) ───────────────────────────────────────
ALTER TABLE site_revisions
  ALTER COLUMN do_cao_dinh_cot_anten TYPE VARCHAR(50) USING do_cao_dinh_cot_anten::TEXT,
  ALTER COLUMN do_cao_cot_anten      TYPE VARCHAR(50) USING do_cao_cot_anten::TEXT;

ALTER TABLE cell_3g_revisions
  ALTER COLUMN do_cao_anten TYPE VARCHAR(50) USING do_cao_anten::TEXT,
  ALTER COLUMN azimuth      TYPE VARCHAR(50) USING azimuth::TEXT,
  ALTER COLUMN m_tilt       TYPE VARCHAR(50) USING m_tilt::TEXT,
  ALTER COLUMN e_tilt       TYPE VARCHAR(50) USING e_tilt::TEXT,
  ALTER COLUMN total_tilt   TYPE VARCHAR(50) USING total_tilt::TEXT;

ALTER TABLE cell_4g_revisions
  ALTER COLUMN do_cao_anten TYPE VARCHAR(50) USING do_cao_anten::TEXT,
  ALTER COLUMN azimuth      TYPE VARCHAR(50) USING azimuth::TEXT,
  ALTER COLUMN m_tilt       TYPE VARCHAR(50) USING m_tilt::TEXT,
  ALTER COLUMN e_tilt       TYPE VARCHAR(50) USING e_tilt::TEXT,
  ALTER COLUMN total_tilt   TYPE VARCHAR(50) USING total_tilt::TEXT;

ALTER TABLE cell_5g_revisions
  ALTER COLUMN do_cao_anten TYPE VARCHAR(50) USING do_cao_anten::TEXT,
  ALTER COLUMN azimuth      TYPE VARCHAR(50) USING azimuth::TEXT,
  ALTER COLUMN m_tilt       TYPE VARCHAR(50) USING m_tilt::TEXT,
  ALTER COLUMN e_tilt       TYPE VARCHAR(50) USING e_tilt::TEXT,
  ALTER COLUMN total_tilt   TYPE VARCHAR(50) USING total_tilt::TEXT;

COMMIT;