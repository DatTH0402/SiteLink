#!/usr/bin/env bash
# fix_site_cell_sync.sh  –  run from the SiteLink project root (or pass the root as $1)
set -euo pipefail

cd "${1:-.}"
for f in backend/app/api/routes/sites.py backend/app/api/routes/cells_3g.py \
         backend/app/api/routes/cells_4g.py backend/app/api/routes/cells_5g.py \
         backend/app/services/site_info.py; do
  [ -f "$f" ] || { echo "ERROR: $f not found – run this from the SiteLink root."; exit 1; }
done

# ── 1. backup ────────────────────────────────────────────────────────────────
BK="_backup_site_cell_sync_$(date +%Y%m%d-%H%M%S)"
for f in backend/app/api/routes/sites.py backend/app/api/routes/cells_3g.py \
         backend/app/api/routes/cells_4g.py backend/app/api/routes/cells_5g.py \
         backend/app/services/site_info.py; do
  mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"
done
echo "Backup written to $BK/"

# ── 2. patch route files (all-or-nothing) ────────────────────────────────────
python3 - <<'PY_EOF'
import pathlib, re, sys

ROOT = pathlib.Path("backend/app")
errors, writes, skipped = [], {}, []

def rd(p): return p.read_text(encoding="utf-8")

def lit(text, old, new, label):
    n = text.count(old)
    if n != 1:
        errors.append(f"{label}: expected exactly 1 match, found {n}")
        return text
    return text.replace(old, new)

def rx(text, pattern, new, label, flags=0):
    ms = list(re.finditer(pattern, text, flags))
    if len(ms) != 1:
        errors.append(f"{label}: expected exactly 1 regex match, found {len(ms)}")
        return text
    m = ms[0]
    return text[:m.start()] + new + text[m.end():]

# ---------------------------------------------------------------- cells_*.py
def patch_cells(tech):
    T = tech.upper()
    M = f"Cell{T}"
    path = ROOT / "api" / "routes" / f"cells_{tech}.py"
    t = rd(path)
    if "get_or_create_site_for_cell" in t:
        skipped.append(str(path)); return
    lab = lambda s: f"{path.name} [{s}]"

    def flag_call(pad_n, var, source, note):
        p = " " * pad_n
        return (
            f'{p}ensure_site_tech_flag(\n'
            f'{p}    db, {var}, "{tech}",\n'
            f'{p}    changed_by_id=current_user.id,\n'
            f'{p}    changed_by_name=current_user.full_name or current_user.username,\n'
            f'{p}    change_source="{source}",\n'
            f'{p}    change_note="{note}",\n'
            f'{p})\n'
        )

    # a) imports
    t = lit(t, "from app.services.site_info import apply_site_info\n",
            "from app.services.site_info import (\n"
            "    apply_site_info, apply_site_to_cell,\n"
            "    ensure_site_tech_flag, get_or_create_site_for_cell,\n"
            ")\n", lab("import"))

    # b) _ensure_site now delegates to the shared helper and returns (site, created)
    t = rx(t, r"def _ensure_site\(.*?return new_site\.id\n",
           "def _ensure_site(db: Session, rec: dict, current_user: User):\n"
           f'    """Return (site, created). A newly created Site gets tram_{tech} = True."""\n'
           f'    return get_or_create_site_for_cell(db, rec, "{tech}", current_user)\n',
           lab("_ensure_site"), re.S)

    # c) Excel create loop: use returned site, inherit its info
    t = rx(t,
           r'site_id = _ensure_site\(db, rec, current_user\)\s+'
           r'if site_id != rec\.get\("site_id"\):\s+sites_auto_created \+= 1\s+'
           r'rec\["site_id"\] = site_id',
           'site, site_created = _ensure_site(db, rec, current_user)\n'
           '            if site_created:\n'
           '                sites_auto_created += 1\n'
           '            # the cell inherits site_name / mien / tinh / phuong_xa from its Site\n'
           '            rec = apply_site_info(rec, site)',
           lab("import-create head"))

    # d) Excel create: flag the technology on the Site
    old = f"cell = {M}(**clean, created_by=current_user.id)\n"
    t = lit(t, old, old + flag_call(12, "site", "excel",
            f"Tự động bật Trạm {T} khi import Cell {T}"), lab("import-create flag"))

    # e) Excel update: stay consistent with Site + make sure the flag is on
    old = '_apply_cell_changes(existing, upd["changes"], is_rename=is_rename)\n'
    new = (old
           + "            # keep the cell consistent with its Site and make sure the Site flags this technology\n"
           + "            _site = db.query(Site).filter(Site.id == existing.site_id).first()\n"
           + "            if _site is not None:\n"
           + "                apply_site_to_cell(existing, _site)\n"
           + flag_call(16, "_site", "excel", f"Tự động bật Trạm {T} khi import Cell {T}"))
    t = lit(t, old, new, lab("import-update"))

    # f) Form create
    old = f"cell = {M}(**apply_site_info(payload.model_dump(), site), created_by=current_user.id)\n"
    t = lit(t, old, old + flag_call(4, "site", "form",
            f"Tự động bật Trạm {T} khi tạo Cell {T}"), lab("form-create"))

    writes[path] = t

for tech in ("3g", "4g", "5g"):
    patch_cells(tech)

# ------------------------------------------------------------------ sites.py
sp = ROOT / "api" / "routes" / "sites.py"
st = rd(sp)
if "sync_site_info_to_cells" in st:
    skipped.append(str(sp))
else:
    def sync_call(pad_n, site_var, snap_var, source):
        p = " " * pad_n
        return (
            f'{p}_chg = changed_site_fields({snap_var}, {site_var})\n'
            f'{p}if _chg:\n'
            f'{p}    sync_site_info_to_cells(\n'
            f'{p}        db, {site_var}, _chg,\n'
            f'{p}        changed_by_id=current_user.id,\n'
            f'{p}        changed_by_name=current_user.full_name or current_user.username,\n'
            f'{p}        change_source="{source}",\n'
            f'{p}    )\n'
        )
    imp = "from app.services.revision import record_site_revision, _site_snapshot\n"
    st = lit(st, imp, imp + "from app.services.site_info import changed_site_fields, sync_site_info_to_cells\n",
             "sites.py [import]")
    # PUT /sites/{id}
    old = ('change_source="form",\n        site_name_old_ref=site_name_old_ref,\n'
           '    )\n    db.commit()\n    db.refresh(site)\n')
    new = ('change_source="form",\n        site_name_old_ref=site_name_old_ref,\n    )\n'
           + sync_call(4, "site", "old_snap", "form")
           + '    db.commit()\n    db.refresh(site)\n')
    st = lit(st, old, new, "sites.py [update_site]")
    # POST /sites/bulk-update
    old = 'change_note="Bulk update",\n            )\n\n            db.commit()\n'
    new = ('change_note="Bulk update",\n            )\n'
           + sync_call(12, "site", "old_snap", "form")
           + '\n            db.commit()\n')
    st = lit(st, old, new, "sites.py [bulk_update]")
    # POST /sites/import-excel (update loop)
    old = ('change_source="excel",\n                site_name_old_ref=site_name_old_ref,\n'
           '            )\n            db.commit()\n')
    new = ('change_source="excel",\n                site_name_old_ref=site_name_old_ref,\n            )\n'
           + sync_call(12, "existing", "old_snap", "excel")
           + '            db.commit()\n')
    st = lit(st, old, new, "sites.py [import-excel update]")
    writes[sp] = st

if errors:
    print("\nPATCH ABORTED – no route file was modified. Problems:")
    for e in errors: print("  -", e)
    print("Your files probably differ from the version I was given; send me the failing file(s).")
    sys.exit(1)

for p, text in writes.items():
    p.write_text(text, encoding="utf-8")
    print("patched ", p)
for s in skipped:
    print("skipped (already patched):", s)
PY_EOF

# ── 3. new services/site_info.py ─────────────────────────────────────────────
cat > backend/app/services/site_info.py <<'SITEINFO_EOF'
"""
services/site_info.py

Site <-> Cell relationship helpers.

* Cells denormalise a few columns from their parent Site (SITE_INHERITED_FIELDS).
  - apply_site_info / apply_site_to_cell : copy Site -> cell data on create / import
  - changed_site_fields / sync_site_info_to_cells : push a Site edit down to all its cells
* Sites carry tram_3g / tram_4g / tram_5g flags that the report module counts.
  - get_or_create_site_for_cell : Excel cell import (auto-creates the Site with the flag set)
  - ensure_site_tech_flag       : turn the flag on when a cell of that technology exists

None of the functions here commit, except get_or_create_site_for_cell
(it commits only when it has to create a new Site, as the old _ensure_site did).
"""
from typing import Any, Dict, Optional, Set, Tuple

from sqlalchemy.orm import Session

from app.models.site import Site
from app.models.cell_3g import Cell3G
from app.models.cell_4g import Cell4G
from app.models.cell_5g import Cell5G
from app.services.revision import (
    _safe_bool, _site_snapshot, record_site_revision,
    _cell3g_snapshot, _cell4g_snapshot, _cell5g_snapshot,
    record_cell3g_revision, record_cell4g_revision, record_cell5g_revision,
)

SITE_INHERITED_FIELDS = ("site_name", "mien", "tinh", "phuong_xa")

TECH_FLAG = {"3g": "tram_3g", "4g": "tram_4g", "5g": "tram_5g"}

_CELL_TECH = {
    "3g": (Cell3G, _cell3g_snapshot, record_cell3g_revision),
    "4g": (Cell4G, _cell4g_snapshot, record_cell4g_revision),
    "5g": (Cell5G, _cell5g_snapshot, record_cell5g_revision),
}


def _blank(v: Any) -> bool:
    return v is None or str(v).strip() == ""


def _norm(v: Any) -> Optional[str]:
    return None if _blank(v) else str(v).strip()


# ── Site -> cell data copy (create / import) ─────────────────────────────────

def apply_site_info(data: Dict[str, Any], site: Site) -> Dict[str, Any]:
    out = dict(data)
    out["site_id"] = site.id
    for field in SITE_INHERITED_FIELDS:
        value = getattr(site, field, None)
        if value is not None and str(value).strip() != "":
            out[field] = value
    return out


def apply_site_to_cell(cell: Any, site: Site) -> None:
    """Copy the Site's non-empty inherited fields onto an existing cell object."""
    for field in SITE_INHERITED_FIELDS:
        value = getattr(site, field, None)
        if not _blank(value) and getattr(cell, field, None) != value:
            setattr(cell, field, value)


# ── Issue 1: Site edit -> all cells of the Site ──────────────────────────────

def changed_site_fields(old_snapshot: Dict[str, Any], site: Site) -> Set[str]:
    """Which inherited fields differ between the pre-edit snapshot and the Site now."""
    return {
        f for f in SITE_INHERITED_FIELDS
        if _norm(old_snapshot.get(f)) != _norm(getattr(site, f, None))
    }


def sync_site_info_to_cells(
    db: Session, site: Site, changed_fields: Optional[Set[str]] = None, *,
    changed_by_id: Optional[int] = None, changed_by_name: Optional[str] = None,
    change_source: str = "form", change_note: str = "Đồng bộ thông tin từ Site",
) -> int:
    """
    Push the Site's site_name / mien / tinh / phuong_xa to every 3G/4G/5G cell of
    the Site and record a cell revision per modified cell. Does NOT commit.

    A blank Site value only clears the cell's value when that field is in
    `changed_fields` (i.e. the user just cleared it on the Site).
    """
    changed = set(changed_fields or ())
    updates: Dict[str, Any] = {}
    for f in SITE_INHERITED_FIELDS:
        v = getattr(site, f, None)
        if _blank(v) and (f == "site_name" or f not in changed):
            continue
        updates[f] = None if _blank(v) else v
    if not updates:
        return 0

    touched = 0
    for _tech, (Model, snap_fn, rec_fn) in _CELL_TECH.items():
        for cell in db.query(Model).filter(Model.site_id == site.id).all():
            diff = {f: v for f, v in updates.items()
                    if _norm(getattr(cell, f, None)) != _norm(v)}
            if not diff:
                continue
            old_snap = snap_fn(cell)
            for f, v in diff.items():
                setattr(cell, f, v)
            db.flush()
            rec_fn(
                db, cell, old_snapshot=old_snap,
                changed_by_id=changed_by_id, changed_by_name=changed_by_name,
                change_source=change_source, change_note=change_note,
            )
            touched += 1
    return touched


# ── Issue 2: tram_3g / tram_4g / tram_5g mapping ─────────────────────────────

def ensure_site_tech_flag(
    db: Session, site: Site, tech: str, *,
    changed_by_id: Optional[int] = None, changed_by_name: Optional[str] = None,
    change_source: str = "form", change_note: Optional[str] = None,
) -> bool:
    """Turn site.tram_<tech> on if it is off (+ Site revision). No commit. True if changed."""
    flag = TECH_FLAG[tech]
    if _safe_bool(getattr(site, flag, None)):
        return False
    old_snap = _site_snapshot(site)
    setattr(site, flag, True)
    db.flush()
    record_site_revision(
        db, site, old_snapshot=old_snap,
        changed_by_id=changed_by_id, changed_by_name=changed_by_name,
        change_source=change_source, change_note=change_note,
    )
    return True


def get_or_create_site_for_cell(
    db: Session, rec: Dict[str, Any], tech: str, current_user: Any,
) -> Tuple[Site, bool]:
    """
    Find the Site by site_name; create it when missing (with tram_<tech> = True and
    a Site revision). Returns (site, created). Commits only when it creates a Site.
    """
    site_name = (rec.get("site_name") or "").strip()
    site = db.query(Site).filter(Site.site_name == site_name).first()
    if site is not None:
        return site, False

    new_site = Site(
        site_name=site_name,
        mien=rec.get("mien") or "",
        tinh=rec.get("tinh") or "",
        phuong_xa=rec.get("phuong_xa"),
        lat=rec.get("lat"),
        long=rec.get("long"),
        created_by=current_user.id,
        **{TECH_FLAG[tech]: True},
    )
    db.add(new_site)
    db.flush()
    record_site_revision(
        db, new_site, old_snapshot=None,
        changed_by_id=current_user.id,
        changed_by_name=current_user.full_name or current_user.username,
        change_source="excel",
        change_note=f"Tự động tạo khi import Cell {tech.upper()}",
    )
    db.commit()
    db.refresh(new_site)
    return new_site, True
SITEINFO_EOF
echo "wrote backend/app/services/site_info.py"

# ── 4. optional one-off SQL for EXISTING data (NOT executed) ─────────────────
mkdir -p backend/scripts
cat > backend/scripts/one_off_backfill_site_cells.sql <<'SQL_EOF'
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
SQL_EOF
echo "wrote backend/scripts/one_off_backfill_site_cells.sql (not executed)"

# ── 5. syntax check ──────────────────────────────────────────────────────────
python3 -m py_compile \
  backend/app/services/site_info.py backend/app/api/routes/sites.py \
  backend/app/api/routes/cells_3g.py backend/app/api/routes/cells_4g.py \
  backend/app/api/routes/cells_5g.py
echo
echo "DONE. Restart the backend (uvicorn/gunicorn) to load the changes."
echo "Originals are in $BK/ – restore with: cp -r $BK/backend/* backend/"