-- One-off backfill for data that already exists (PostgreSQL). Review, back up, then run manually.
-- Bypasses the ORM: no revisions are written and updated_at is not touched.

-- A) cells take mien/tinh/phuong_xa/site_name from their Site (never overwriting with blanks)
UPDATE cells_3g c SET site_name = s.site_name,
  mien = COALESCE(NULLIF(s.mien,''), c.mien), tinh = COALESCE(NULLIF(s.tinh,''), c.tinh),
  phuong_xa = COALESCE(NULLIF(s.phuong_xa,''), c.phuong_xa)
FROM sites s WHERE c.site_id = s.id AND (c.site_name IS DISTINCT FROM s.site_name
  OR c.mien IS DISTINCT FROM COALESCE(NULLIF(s.mien,''), c.mien)
  OR c.tinh IS DISTINCT FROM COALESCE(NULLIF(s.tinh,''), c.tinh)
  OR c.phuong_xa IS DISTINCT FROM COALESCE(NULLIF(s.phuong_xa,''), c.phuong_xa));
UPDATE cells_4g c SET site_name = s.site_name,
  mien = COALESCE(NULLIF(s.mien,''), c.mien), tinh = COALESCE(NULLIF(s.tinh,''), c.tinh),
  phuong_xa = COALESCE(NULLIF(s.phuong_xa,''), c.phuong_xa)
FROM sites s WHERE c.site_id = s.id AND (c.site_name IS DISTINCT FROM s.site_name
  OR c.mien IS DISTINCT FROM COALESCE(NULLIF(s.mien,''), c.mien)
  OR c.tinh IS DISTINCT FROM COALESCE(NULLIF(s.tinh,''), c.tinh)
  OR c.phuong_xa IS DISTINCT FROM COALESCE(NULLIF(s.phuong_xa,''), c.phuong_xa));
UPDATE cells_5g c SET site_name = s.site_name,
  mien = COALESCE(NULLIF(s.mien,''), c.mien), tinh = COALESCE(NULLIF(s.tinh,''), c.tinh),
  phuong_xa = COALESCE(NULLIF(s.phuong_xa,''), c.phuong_xa)
FROM sites s WHERE c.site_id = s.id AND (c.site_name IS DISTINCT FROM s.site_name
  OR c.mien IS DISTINCT FROM COALESCE(NULLIF(s.mien,''), c.mien)
  OR c.tinh IS DISTINCT FROM COALESCE(NULLIF(s.tinh,''), c.tinh)
  OR c.phuong_xa IS DISTINCT FROM COALESCE(NULLIF(s.phuong_xa,''), c.phuong_xa));

-- B) sites that already have cells of a technology get the matching flag
UPDATE sites SET tram_3g = TRUE WHERE tram_3g IS NOT TRUE AND id IN (SELECT DISTINCT site_id FROM cells_3g);
UPDATE sites SET tram_4g = TRUE WHERE tram_4g IS NOT TRUE AND id IN (SELECT DISTINCT site_id FROM cells_4g);
UPDATE sites SET tram_5g = TRUE WHERE tram_5g IS NOT TRUE AND id IN (SELECT DISTINCT site_id FROM cells_5g);
