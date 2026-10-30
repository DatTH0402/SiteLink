#!/usr/bin/env bash
# =============================================================================
#  add_subcell_id.sh  -  add the optional "Subcell-ID" (DB column: subcell_id)
#  to Cell 3G / 4G / 5G in SiteLink.
#
#  Usage:  bash add_subcell_id.sh [PROJECT_ROOT] [options]
#    --migrate                  run backend/migrate_add_subcell_id.py afterwards
#    --drop-conflicting-unique  (with --migrate) drop UNIQUE indexes on cell_name
#                               and replace them by UNIQUE(site_id, cell_name, subcell_id)
#    --regen-templates          run create_excel_templates.py afterwards
#    --force                    re-apply even if already applied
#
#  - Every modified file is backed up to  <root>/.subcell_backup_<timestamp>/
#  - All anchors are verified in memory first; nothing is written if one fails.
# =============================================================================
set -euo pipefail

usage() { sed -n '2,15p' "$0"; }

ROOT="."; DO_MIGRATE=0; DO_REGEN=0; DROP_UNIQUE=0; FORCE=0
for arg in "$@"; do
  case "$arg" in
    --migrate) DO_MIGRATE=1 ;;
    --regen-templates) DO_REGEN=1 ;;
    --drop-conflicting-unique) DROP_UNIQUE=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $arg" >&2; usage; exit 2 ;;
    *) ROOT="$arg" ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
[ -f "$ROOT/backend/cell_sync_core.py" ] || { echo "ERROR: $ROOT does not look like the SiteLink root (backend/cell_sync_core.py not found)" >&2; exit 1; }
[ -f "$ROOT/frontend/src/pages/cells/Cells3GPage.tsx" ] || { echo "ERROR: frontend/src/pages/cells/Cells3GPage.tsx not found" >&2; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 is required" >&2; exit 1; }

export SL_ROOT="$ROOT" SL_FORCE="$FORCE" PYTHONIOENCODING=utf-8

python3 - <<'PYEOF'
import os
import re
import sys
import datetime
from pathlib import Path

ROOT = Path(os.environ["SL_ROOT"])
FORCE = os.environ.get("SL_FORCE") == "1"


class Patcher:
    def __init__(self, root):
        self.root = root
        self.texts, self.orig, self.crlf = {}, {}, {}
        self.new_files = {}
        self.errors = []

    def _load(self, rel):
        if rel not in self.texts:
            p = self.root / rel
            if not p.is_file():
                self.errors.append("missing file: " + rel)
                return None
            raw = p.read_bytes().decode("utf-8")
            self.crlf[rel] = "\r\n" in raw
            t = raw.replace("\r\n", "\n")
            self.orig[rel] = t
            self.texts[rel] = t
        return self.texts[rel]

    def replace(self, rel, old, new, count=1):
        t = self._load(rel)
        if t is None:
            return
        n = t.count(old)
        if n != count:
            self.errors.append("%s: anchor found %dx (expected %d): %r" % (rel, n, count, old[:80]))
            return
        self.texts[rel] = t.replace(old, new)

    def regex(self, rel, pattern, fn, count=1, flags=0):
        t = self._load(rel)
        if t is None:
            return
        rx = re.compile(pattern, flags)
        n = len(list(rx.finditer(t)))
        if n != count:
            self.errors.append("%s: regex found %dx (expected %d): %r" % (rel, n, count, pattern[:80]))
            return
        self.texts[rel] = rx.sub(fn, t)

    def between(self, rel, start, end, new, include_end=True):
        t = self._load(rel)
        if t is None:
            return
        if t.count(start) != 1:
            self.errors.append("%s: start marker found %dx: %r" % (rel, t.count(start), start[:80]))
            return
        i = t.find(start)
        j = t.find(end, i + len(start))
        if j < 0:
            self.errors.append("%s: end marker not found: %r" % (rel, end[:80]))
            return
        k = j + len(end) if include_end else j
        self.texts[rel] = t[:i] + new + t[k:]

    def create(self, rel, content):
        if (self.root / rel).exists() and not FORCE:
            self.errors.append("file already exists: " + rel)
            return
        self.new_files[rel] = content

    def commit(self):
        for rel, t in list(self.texts.items()) + list(self.new_files.items()):
            if rel.endswith(".py"):
                try:
                    compile(t, rel, "exec")
                except SyntaxError as e:
                    self.errors.append("%s: patched file has a syntax error: %s" % (rel, e))
        if self.errors:
            print("\nPATCH ABORTED - nothing was written. Problems:")
            for e in self.errors:
                print("  - " + e)
            sys.exit(1)
        stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        bdir = self.root / (".subcell_backup_" + stamp)
        changed = []
        for rel, t in self.texts.items():
            if t == self.orig[rel]:
                continue
            src = self.root / rel
            dst = bdir / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(src.read_bytes())
            out = t.replace("\n", "\r\n") if self.crlf[rel] else t
            src.write_bytes(out.encode("utf-8"))
            changed.append(rel)
        created = []
        for rel, t in self.new_files.items():
            p = self.root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(t.encode("utf-8"))
            created.append(rel)
        print("Backup of original files: " + str(bdir))
        print("\nModified files (%d):" % len(changed))
        for r in changed:
            print("  ~ " + r)
        print("\nCreated files (%d):" % len(created))
        for r in created:
            print("  + " + r)


if (ROOT / "backend/app/services/cell_identity.py").exists() and not FORCE:
    print("Subcell-ID changes seem to be applied already (backend/app/services/cell_identity.py exists). Use --force to re-apply.")
    sys.exit(0)

P = Patcher(ROOT)

# =============================================================================
# 1. NEW FILES
# =============================================================================
P.create("backend/app/services/cell_identity.py", r'''"""
services/cell_identity.py
-------------------------
Identity rules for 3G / 4G / 5G cells.

A cell is identified by  (site_id, cell_name, subcell_id).
  * subcell_id is OPTIONAL; blank == NULL.
  * When subcell_id is empty, cell_name alone identifies the cell.
  * Several cells may share the same cell_name when their subcell_id differ.
  * Syncing from the vendor CSV files only uses cell_name (see cell_sync_core.py):
    cells sharing a name receive the same synced values.
"""
from __future__ import annotations

from typing import Optional

from fastapi import HTTPException
from sqlalchemy import func, or_


def norm_subcell(v) -> Optional[str]:
    """'' / whitespace / None -> None, otherwise the stripped string."""
    if v is None:
        return None
    s = str(v).strip()
    return s or None


def subcell_clause(model, sub: Optional[str]):
    """SQL condition: model.subcell_id equals `sub` (None == blank / NULL)."""
    col = model.subcell_id
    if sub is None:
        return or_(col.is_(None), func.trim(col) == "")
    return func.trim(col) == sub


def find_cell(db, model, cell_name: str, subcell_id: Optional[str],
              site_id: Optional[int] = None, exclude_id: Optional[int] = None):
    """Exact identity lookup: (site_id, cell_name, subcell_id)."""
    q = db.query(model).filter(model.cell_name == cell_name)
    if site_id is not None:
        q = q.filter(model.site_id == site_id)
    q = q.filter(subcell_clause(model, norm_subcell(subcell_id)))
    if exclude_id is not None:
        q = q.filter(model.id != exclude_id)
    return q.order_by(model.id).first()


def assert_no_duplicate(db, model, site_id: Optional[int], cell_name: str,
                        subcell_id: Optional[str], exclude_id: Optional[int] = None) -> None:
    """HTTP 409 when another cell already has the same (site, cell_name, subcell_id)."""
    if not cell_name:
        return
    sub = norm_subcell(subcell_id)
    if find_cell(db, model, cell_name, sub, site_id, exclude_id) is None:
        return
    if sub:
        detail = ("Cell '%s' với Subcell-ID '%s' đã tồn tại trong site này. "
                  "Hãy nhập Subcell-ID khác để phân biệt." % (cell_name, sub))
    else:
        detail = ("Cell '%s' (chưa có Subcell-ID) đã tồn tại trong site này. "
                  "Nếu nhiều cell trùng tên, hãy nhập Subcell-ID để phân biệt." % cell_name)
    raise HTTPException(status_code=409, detail=detail)
''')

P.create("backend/migrate_add_subcell_id.py", r'''"""
migrate_add_subcell_id.py
-------------------------
Adds the optional `subcell_id` column used to tell apart cells that share one cell_name.

    python migrate_add_subcell_id.py                            # add the columns (idempotent)
    python migrate_add_subcell_id.py --drop-conflicting-unique

* cells_3g / cells_4g / cells_5g and cell_3g_revisions / cell_4g_revisions / cell_5g_revisions
  get   subcell_id VARCHAR(50) NULL
* A UNIQUE index / constraint on a cells_* table that involves cell_name but NOT subcell_id
  would stop two cells from sharing a name. They are only REPORTED unless
  --drop-conflicting-unique is given; then they are dropped and replaced by
      UNIQUE (site_id, cell_name, COALESCE(subcell_id, ''))
DB url: env DATABASE_URL, else the default below.
"""
import argparse
import os
import sys

from sqlalchemy import create_engine, text

DATABASE_URL = os.environ.get("DATABASE_URL",
                              "postgresql://sitelink:sitelink_pass@localhost:5432/sitelink_db")
CELL_TABLES = ["cells_3g", "cells_4g", "cells_5g"]
REVISION_TABLES = ["cell_3g_revisions", "cell_4g_revisions", "cell_5g_revisions"]


def main() -> int:
    ap = argparse.ArgumentParser(description="Add subcell_id to SiteLink cell tables")
    ap.add_argument("--drop-conflicting-unique", action="store_true",
                    help="drop UNIQUE indexes on cell_name and replace them with (site_id, cell_name, subcell_id)")
    args = ap.parse_args()

    eng = create_engine(DATABASE_URL, pool_pre_ping=True)
    rc = 0
    try:
        with eng.begin() as conn:
            for t in CELL_TABLES + REVISION_TABLES:
                conn.execute(text("ALTER TABLE %s ADD COLUMN IF NOT EXISTS subcell_id VARCHAR(50)" % t))
                print("  ok   %s.subcell_id" % t)

        for t in CELL_TABLES:
            with eng.connect() as conn:
                rows = conn.execute(text(
                    "SELECT indexname, indexdef FROM pg_indexes "
                    "WHERE schemaname = current_schema() AND tablename = :t "
                    "AND indexdef LIKE 'CREATE UNIQUE INDEX%'"), {"t": t}).fetchall()
            conflicts = [(n, d) for n, d in rows if "cell_name" in d and "subcell_id" not in d]
            for name, ddl in conflicts:
                if not args.drop_conflicting_unique:
                    print("  WARNING %s: unique index '%s' prevents cells from sharing a name:\n"
                          "          %s\n          re-run with --drop-conflicting-unique to replace it" % (t, name, ddl))
                    rc = 1
                    continue
                with eng.begin() as conn:
                    is_con = conn.execute(
                        text("SELECT 1 FROM pg_constraint WHERE conname = :n AND conrelid = CAST(:t AS regclass)"),
                        {"n": name, "t": t}).first()
                    if is_con:
                        conn.execute(text('ALTER TABLE %s DROP CONSTRAINT "%s"' % (t, name)))
                    else:
                        conn.execute(text('DROP INDEX IF EXISTS "%s"' % name))
                print("  dropped %s on %s" % (name, t))
            if args.drop_conflicting_unique and conflicts:
                try:
                    with eng.begin() as conn:
                        conn.execute(text(
                            "CREATE UNIQUE INDEX IF NOT EXISTS uq_%s_site_cell_subcell "
                            "ON %s (site_id, cell_name, COALESCE(subcell_id, ''))" % (t, t)))
                    print("  created uq_%s_site_cell_subcell" % t)
                except Exception as exc:
                    print("  WARNING could not create the replacement unique index on %s "
                          "(duplicate rows already exist?): %s" % (t, exc))
                    rc = 1
    finally:
        eng.dispose()
    print("\nDone." if rc == 0 else "\nFinished with warnings (see above).")
    return rc


if __name__ == "__main__":
    sys.exit(main())
''')

P.create("backend/migrations/add_subcell_id.sql", '''-- Adds the optional Subcell-ID column (plain-SQL alternative to migrate_add_subcell_id.py)
ALTER TABLE cells_3g          ADD COLUMN IF NOT EXISTS subcell_id VARCHAR(50);
ALTER TABLE cells_4g          ADD COLUMN IF NOT EXISTS subcell_id VARCHAR(50);
ALTER TABLE cells_5g          ADD COLUMN IF NOT EXISTS subcell_id VARCHAR(50);
ALTER TABLE cell_3g_revisions ADD COLUMN IF NOT EXISTS subcell_id VARCHAR(50);
ALTER TABLE cell_4g_revisions ADD COLUMN IF NOT EXISTS subcell_id VARCHAR(50);
ALTER TABLE cell_5g_revisions ADD COLUMN IF NOT EXISTS subcell_id VARCHAR(50);

-- Check for UNIQUE indexes that would forbid two cells sharing a cell_name:
-- SELECT tablename, indexname, indexdef FROM pg_indexes
--  WHERE tablename IN ('cells_3g','cells_4g','cells_5g') AND indexdef LIKE 'CREATE UNIQUE%';
''')

# =============================================================================
# 2. MODELS (cells + revisions)
# =============================================================================
def model_line(col_def):
    def fn(m):
        pad = " " * max(1, len("cell_name_old") + len(m.group(2)) - len("subcell_id"))
        return (m.group(0) + m.group(1) + "subcell_id" + pad + "= " + col_def +
                "   # optional: tells apart cells sharing one cell_name\n")
    return fn

for t in ("3g", "4g", "5g"):
    P.regex("backend/app/models/cell_%s.py" % t,
            r'\n( +)cell_name_old( +)= Column\(String\(100\), nullable=True\)\n',
            model_line("Column(String(50), nullable=True)"))

P.regex("backend/app/models/cell_revision.py",
        r'\n( +)cell_name_old( +)= Column\(String\(100\)\)\n',
        model_line("Column(String(50), nullable=True)"), count=3)

# =============================================================================
# 3. SCHEMAS
# =============================================================================
SCH = "backend/app/schemas/cell.py"
P.replace(SCH, "from pydantic import BaseModel, model_validator",
               "from pydantic import BaseModel, field_validator, model_validator")
P.replace(SCH, "    cell_name_old:  Optional[str]   = None\n",
               "    cell_name_old:  Optional[str]   = None\n"
               "    subcell_id:     Optional[str]   = None   # Subcell-ID (optional)\n", count=2)
P.replace(SCH, "    oss:            Optional[str]   = None\n",
'''    oss:            Optional[str]   = None

    @field_validator("subcell_id", mode="before")
    @classmethod
    def _normalize_subcell_id(cls, v):
        # '' / whitespace -> None.  Cell identity = (site, cell_name, subcell_id)
        if v is None:
            return None
        s = str(v).strip()
        if not s:
            return None
        if len(s) > 50:
            raise ValueError("'subcell_id' tối đa 50 ký tự.")
        return s
''', count=2)

# =============================================================================
# 4. REVISION SERVICE (snapshots + revision rows)
# =============================================================================
REV = "backend/app/services/revision.py"
# 3G + 4G snapshots share the same one-line text
P.replace(REV, '        "cell_name": cell.cell_name, "cell_name_old": cell.cell_name_old,\n',
               '        "cell_name": cell.cell_name, "cell_name_old": cell.cell_name_old,\n'
               '        "subcell_id": cell.subcell_id,\n', count=2)
# 5G snapshot (aligned)
P.replace(REV, '        "cell_name_old":    cell.cell_name_old,\n',
               '        "cell_name_old":    cell.cell_name_old,\n'
               '        "subcell_id":       cell.subcell_id,\n')
# revision rows (3G, 4G, 5G)
P.replace(REV, "        site_name_old=cell.site_name_old, cell_name_old=cell.cell_name_old,\n",
               "        site_name_old=cell.site_name_old, cell_name_old=cell.cell_name_old,\n"
               "        subcell_id=cell.subcell_id,\n", count=3)

# =============================================================================
# 5. REVISION API (return + filter by subcell_id)
# =============================================================================
RAPI = "backend/app/api/routes/revision.py"
P.regex(RAPI, r'\n( +)"cell_name_old":( +)r\.cell_name_old,',
        lambda m: m.group(0) + "\n" + m.group(1) + '"subcell_id": r.subcell_id,', count=3)
P.regex(RAPI, r'    cell_name: Optional\[str\] = Query\(None\),\n',
        lambda m: m.group(0) + "    subcell_id: Optional[str] = Query(None),\n", count=3)
P.regex(RAPI, r'    rows = \(\n        q\.order_by\(desc\(Cell(\dG)Revision\.created_at\)\)',
        lambda m: ("    if subcell_id:\n"
                   "        q = q.filter(Cell%sRevision.subcell_id.ilike(f\"%%{subcell_id}%%\"))\n" % m.group(1))
                  + m.group(0), count=3)

# =============================================================================
# 6. CELL ROUTES (duplicate guard + bulk-update protection)
# =============================================================================
UPD_CHECK = '''    if {"cell_name", "subcell_id", "site_id"} & set(data):
        _new_name = data.get("cell_name", cell.cell_name)
        _new_sub  = data.get("subcell_id", cell.subcell_id)
        _new_site = data.get("site_id", cell.site_id)
        if (_new_name != cell.cell_name
                or norm_subcell(_new_sub) != norm_subcell(cell.subcell_id)
                or _new_site != cell.site_id):
            # identity = (site, cell_name, subcell_id); only checked when it actually changes
            assert_no_duplicate(db, CELLCLS, _new_site, _new_name, _new_sub, exclude_id=cell.id)
'''
for t, T in (("3g", "3G"), ("4g", "4G"), ("5g", "5G")):
    f = "backend/app/api/routes/cells_%s.py" % t
    imp = "from app.services.revision import record_cell%s_revision, _cell%s_snapshot\n" % (t, t)
    P.replace(f, imp, imp + "from app.services.cell_identity import assert_no_duplicate, norm_subcell\n")
    P.replace(f, '    for f in ("id", "cell_name", "site_id", "created_by", "created_at", "updated_at"):\n',
                 '    for f in ("id", "cell_name", "subcell_id", "site_id", "created_by", "created_at", "updated_at"):\n')
    create_line = "    cell = Cell%s(**apply_site_info(payload.model_dump(), site), created_by=current_user.id)\n" % T
    P.replace(f, create_line,
              "    # a cell is identified by (site, cell_name, subcell_id)\n"
              "    assert_no_duplicate(db, Cell%s, site.id, payload.cell_name, payload.subcell_id)\n" % T + create_line)
    P.regex(f, r'\n    data( *)= payload\.model_dump\(exclude_unset=True\)\n',
            (lambda T: lambda m: m.group(0) + UPD_CHECK.replace("CELLCLS", "Cell" + T))(T))

# =============================================================================
# 7. EXCEL IMPORT  (identity = site + cell_name + subcell_id)
# =============================================================================
IMP = "backend/app/services/import_excel.py"

P.replace(IMP, "def _parse_cell_excel(\n", r'''# ── Subcell-ID support ─────────────────────────────────────────────────────────
# A cell is identified by (Site Name, Cell Name, Subcell-ID). Subcell-ID is optional:
# when it is empty, Cell Name alone identifies the cell.
from app.services.cell_identity import norm_subcell, subcell_clause  # noqa: E402

SUBCELL_COLUMN_NAMES = (
    "Subcell-ID", "Subcell ID", "SubCell-ID", "SubCell ID", "Subcell_ID",
    "SUBCELL-ID", "SUBCELL ID", "subcell_id",
)
SUBCELL_MAX_LEN = 50


def _norm_subcell(v: Any) -> Optional[str]:
    return None if v is _CLEAR else norm_subcell(v)


def _find_existing_cell(db, Model, name: str, sub: Optional[str], site_id: Optional[int]):
    """
    Return (cell | None, ambiguous_count).
      Subcell-ID given -> exact (cell_name, subcell_id) match only.
      Subcell-ID empty (or column absent) -> cell_name alone is enough:
          the cell WITHOUT a Subcell-ID if there is one, otherwise the single cell
          carrying that name. Several cells with other Subcell-IDs -> ambiguous.
    """
    q = db.query(Model).filter(Model.cell_name == name)
    if site_id is not None:
        q = q.filter(Model.site_id == site_id)
    q = q.order_by(Model.id)
    if sub is not None:
        return q.filter(subcell_clause(Model, sub)).first(), 0
    rows = q.limit(100).all()
    if not rows:
        return None, 0
    blank = [r for r in rows if norm_subcell(r.subcell_id) is None]
    if blank:
        return blank[0], 0
    if len(rows) == 1:
        return rows[0], 0
    return None, len(rows)


def _parse_cell_excel(
''')

P.replace(IMP, '    total_tilt_val = _str_aware(row, excel_cols, "Total Tilt", "Total tilt", "total_tilt")\n',
'''    total_tilt_val = _str_aware(row, excel_cols, "Total Tilt", "Total tilt", "total_tilt")

    # ── Subcell-ID (optional; blank = clear, column absent = untouched) ───────
    subcell_val = _v_aware(row, excel_cols, *SUBCELL_COLUMN_NAMES)
    if isinstance(subcell_val, str) and len(subcell_val) > SUBCELL_MAX_LEN:
        errors_out.append(
            f"Row {row_num} ({label}): 'Subcell-ID' dài quá {SUBCELL_MAX_LEN} ký tự."
        )
''')

P.replace(IMP, '        "cell_name_old": _v_aware(row, excel_cols, "Cell Name Old", "Cell name old",\n',
               '        "subcell_id":    subcell_val,\n'
               '        "cell_name_old": _v_aware(row, excel_cols, "Cell Name Old", "Cell name old",\n')

P.replace(IMP, "    pending_new_sites: Dict[str, Dict] = {}\n",
               "    pending_new_sites: Dict[str, Dict] = {}\n"
               "    seen_keys: Dict[tuple, int] = {}      # (site, cell, subcell) -> first row number\n")

P.replace(IMP, "        rec = {**common, **extra}\n", '''        rec = {**common, **extra}

        # ── Cell identity = (Site Name, Cell Name, Subcell-ID) ────────────────
        sub_key = _norm_subcell(common.get("subcell_id"))
        sub_sfx = f" [{sub_key}]" if sub_key else ""
        dup_key = (site_name.strip(), cell_name.strip(), sub_key or "")
        if dup_key in seen_keys:
            errors.append(
                f"Row {row_num} ({cell_name}{sub_sfx}): Trùng lặp trong file – cell này "
                f"(Site Name + Cell Name + Subcell-ID) đã xuất hiện ở dòng {seen_keys[dup_key]}. "
                f"Nếu nhiều cell trùng Cell Name, hãy điền Subcell-ID khác nhau."
            )
            fatal_rows.add(row_num)
            continue
        seen_keys[dup_key] = row_num
''')

P.between(IMP, "        existing_cell = None\n", 'rec["site_id"] = existing_cell.site_id\n', '''        existing_cell = None
        if db:
            scope_id = site_obj.id if site_obj else None
            existing_cell, n_amb = _find_existing_cell(db, Model, cell_name, sub_key, scope_id)
            if n_amb:
                errors.append(
                    f"Row {row_num} ({cell_name}): Có {n_amb} cell trùng tên nhưng khác Subcell-ID – "
                    f"không xác định được cell cần cập nhật. Vui lòng điền cột 'Subcell-ID'."
                )
                fatal_rows.add(row_num)
                continue
            if not existing_cell and cell_name_old:
                old_cell, n_amb = _find_existing_cell(db, Model, cell_name_old, sub_key, scope_id)
                if n_amb:
                    errors.append(
                        f"Row {row_num} ({cell_name_old}): Có {n_amb} cell trùng tên nhưng khác Subcell-ID – "
                        f"không xác định được cell cần đổi tên. Vui lòng điền cột 'Subcell-ID'."
                    )
                    fatal_rows.add(row_num)
                    continue
                if old_cell:
                    if site_obj:
                        if sub_key is None and norm_subcell(old_cell.subcell_id) is not None:
                            rec["subcell_id"] = _CLEAR      # matched by name only: keep its Subcell-ID
                        to_update.append({
                            "existing_id": old_cell.id,
                            "anchor":      f"{site_name}/{cell_name_old}{sub_sfx}",
                            "changes":     rec,
                            "is_rename":   True,
                        })
                        continue
                    existing_cell = old_cell
            if existing_cell:
                if sub_key is None and norm_subcell(existing_cell.subcell_id) is not None:
                    rec["subcell_id"] = _CLEAR              # matched by name only: keep its Subcell-ID
                if not site_obj:
                    rec["site_id"] = existing_cell.site_id
''')

P.replace(IMP, '"anchor":      f"{site_name}/{cell_name}",',
               '"anchor":      f"{site_name}/{cell_name}{sub_sfx}",')

# =============================================================================
# 8. SYNC CORE  (match by cell_name ONLY; every cell sharing the name is updated)
# =============================================================================
SYNC = "backend/cell_sync_core.py"

P.replace(SYNC, '    "site_name_old", "cell_name_old", "cell_vip", "moran", "lat", "long",',
                '    "site_name_old", "cell_name_old", "subcell_id", "cell_vip", "moran", "lat", "long",')

P.between(SYNC, "def fetch_current_cells(", "    return result\n", '''def fetch_current_cells(conn: Connection, table: str, cell_names: List[str]) -> Dict[str, List[Dict]]:
    """cell_name -> ALL DB rows carrying that name (cells sharing a name differ by subcell_id)."""
    result: Dict[str, List[Dict]] = {}
    n_rows = 0
    for i in range(0, len(cell_names), 500):
        batch = cell_names[i:i + 500]
        ph = ", ".join(f":n{j}" for j in range(len(batch)))
        params = {f"n{j}": n for j, n in enumerate(batch)}
        rows = conn.execute(
            text(f"SELECT * FROM {table} WHERE cell_name IN ({ph}) ORDER BY id"), params).mappings().all()
        for row in rows:
            result.setdefault(row["cell_name"], []).append(dict(row))
            n_rows += 1
    log.info("fetch_current_cells %s: requested=%d names_found=%d rows=%d",
             table, len(cell_names), len(result), n_rows)
    return result
''')

P.replace(SYNC, '[r["id"] for r in current_map.values()]',
                '[r["id"] for rows in current_map.values() for r in rows]')

P.between(SYNC, "        plans: List[Dict[str, Any]] = []\n",
                '        n_full = sum(p["kind"] == "full" for p in plans)\n', '''        plans: List[Dict[str, Any]] = []
        for name in cell_names:
            cur_rows = current_map.get(name)
            if not cur_rows:
                stats["not_in_db"] += 1
                continue
            src = source_map.get(name)
            if src is None:
                stats["not_in_csv"] += len(cur_rows)
                continue

            # The source CSVs are keyed by cell_name ONLY. Cells that share a cell_name
            # (they differ by subcell_id) therefore all receive the same synced values.
            eff_cols  = [c for c in cols if src.get(c) != _KEEP]
            new_vals  = {c: _clean(src.get(c)) for c in eff_cols}
            meta_vals = {c: _clean(src.get(c)) for c in META_COLUMNS}

            for cur in cur_rows:
                label = f"{name} [{cur['subcell_id']}]" if _canon(cur.get("subcell_id")) else name
                diff  = _diff({c: cur.get(c) for c in eff_cols}, new_vals)
                meta_changed = any(_canon(cur.get(k)) != _canon(v) for k, v in meta_vals.items())

                if diff:
                    rev_no = rev_no_map.get(cur["id"], 0) + 1
                    rev_no_map[cur["id"]] = rev_no
                    plans.append({"kind": "full", "name": label, "cur": cur, "new_vals": new_vals,
                                  "meta_vals": meta_vals, "diff": diff, "rev_no": rev_no})
                elif meta_changed:
                    plans.append({"kind": "meta", "name": label, "cur": cur, "meta_vals": meta_vals})
                else:
                    stats["skipped"] += 1

''', include_end=False)

# =============================================================================
# 9. EXCEL EXPORT
# =============================================================================
P.replace("backend/app/api/routes/export.py",
          '("Cell Name", 25, "cell_name"), ("Cell Name Old", 22, "cell_name_old"),',
          '("Cell Name", 25, "cell_name"), ("Subcell-ID", 14, "subcell_id"),\n'
          '    ("Cell Name Old", 22, "cell_name_old"),')

# =============================================================================
# 10. EXCEL TEMPLATES  (column, text format, guidance sheet)
# =============================================================================
TPL = "backend/create_excel_templates.py"

P.replace(TPL, '"Tên cell – bắt buộc, duy nhất trong site (vd: HNIHKM44DI4DA)"',
               '"Tên cell – bắt buộc; (Cell Name + Subcell-ID) phải duy nhất trong site (vd: HNIHKM44DI4DA)"')

P.replace(TPL, '    ("Cell Name Old",  "Tên cell cũ',
'''    ("Subcell-ID",     "Subcell-ID – KHÔNG bắt buộc. Chỉ điền khi nhiều cell trùng Cell Name: "
                       "(Site Name + Cell Name + Subcell-ID) xác định duy nhất 1 cell. "
                       "Để trống nếu Cell Name đã đủ phân biệt",                      14,  False),
    ("Cell Name Old",  "Tên cell cũ''')

P.replace(TPL, "def _finish_cell_template(\n", '''_CELL_SUBCELL_IMPORT_RULES: List[Tuple[str, str]] = [
    ("Subcell-ID (không bắt buộc)",
     "→ Dùng khi nhiều cell có cùng Cell Name. Một cell được xác định bởi "
     "(Site Name + Cell Name + Subcell-ID)"),
    ("Subcell-ID để trống / không có cột",
     "→ Chỉ dùng Cell Name để tìm cell (cell chưa có Subcell-ID, hoặc cell duy nhất mang tên đó). "
     "Nếu nhiều cell trùng tên và đều đã có Subcell-ID → báo lỗi, cần điền Subcell-ID"),
    ("Cùng Cell Name, khác Subcell-ID",
     "→ Là các cell khác nhau: mỗi dòng được tạo mới / cập nhật riêng"),
    ("Cùng Cell Name + cùng Subcell-ID",
     "→ Là cùng 1 cell: cập nhật bản ghi hiện có (UPDATE). 2 dòng trùng nhau trong file → báo lỗi"),
    ("Đổi Subcell-ID của cell đã có",
     "→ Không thực hiện được bằng Excel (sẽ bị coi là cell mới). Hãy sửa trên form Chỉnh sửa Cell"),
    ("Đồng bộ dữ liệu từ hệ thống nguồn (CSV)",
     "→ Chỉ dùng Cell Name: các cell trùng tên (khác Subcell-ID) nhận cùng giá trị đồng bộ"),
]


def _finish_cell_template(
''')

P.replace(TPL, "    sample: Dict[str, Any],\n) -> None:\n",
'''    sample: Dict[str, Any],
) -> None:
    # Subcell-ID is an identifier: keep it as TEXT so Excel never turns "001" into 1
    if "Subcell-ID" in cm:
        for _r in range(FIRST_DATA, LAST_DATA + 1):
            ws.cell(row=_r, column=cm["Subcell-ID"]).number_format = "@"
''')

P.replace(TPL, "extra_import_rules=_CELL_GEO_IMPORT_RULES)",
               "extra_import_rules=_CELL_GEO_IMPORT_RULES + _CELL_SUBCELL_IMPORT_RULES)")

# =============================================================================
# 11. FRONTEND
# =============================================================================
P.replace("frontend/src/types/index.ts", "  cell_name_old?: string\n",
          "  cell_name_old?: string\n  subcell_id?: string        // optional - tells apart cells sharing one cell_name\n")
P.replace("frontend/src/api/revision.ts", "  cell_name_old?: string\n",
          "  cell_name_old?: string\n  subcell_id?: string\n")

SUB_FORM_ITEM = '''<Col span={12}>
              <Form.Item name="subcell_id" label="Subcell-ID"
                tooltip="Không bắt buộc. Chỉ nhập khi nhiều cell trùng Cell Name – (Cell Name + Subcell-ID) xác định duy nhất 1 cell.">
                <Input placeholder="Để trống nếu Cell Name đã đủ phân biệt" maxLength={50} />
              </Form.Item>
            </Col>
            '''
for T in ("3G", "4G", "5G"):
    f = "frontend/src/pages/cells/Cells%sPage.tsx" % T
    # table column (sticky, right after Cell Name)
    P.replace(f, "{ title: 'Cell VIP',",
                 "{ title: 'Subcell-ID', dataIndex: 'subcell_id', fixed: 'left', width: 110 },\n"
                 "    { title: 'Cell VIP',")
    # create / edit form field (right after Cell Name)
    P.regex(f, r'<Col span=\{6\}>\s*<Form\.Item name="cell_vip"',
            lambda m: SUB_FORM_ITEM + m.group(0))

RP = "frontend/src/pages/revision/RevisionPage.tsx"
P.replace(RP, "    { title: 'Site Name Old', dataIndex: 'site_name_old',",
'''    { title: 'Subcell-ID', dataIndex: 'subcell_id', width: 100, fixed: 'left',
      render: (v: string) => v || <span style={{ color: '#ccc' }}>-</span> },
    { title: 'Site Name Old', dataIndex: 'site_name_old',''')
P.replace(RP, "  const [cellName, setCellName] = useState('')\n",
              "  const [cellName, setCellName] = useState('')\n"
              "  const [subcellId, setSubcellId] = useState('')\n")
P.replace(RP, "      if (cellName.trim()) params.cell_name = cellName.trim()\n",
              "      if (cellName.trim()) params.cell_name = cellName.trim()\n"
              "      if (subcellId.trim()) params.subcell_id = subcellId.trim()\n")
P.replace(RP, "  }, [siteName, cellName, tinh, fetchFn])", "  }, [siteName, cellName, subcellId, tinh, fetchFn])")
P.regex(RP, r'value=\{cellName\} onChange=\{e => setCellName\(e\.target\.value\)\}\s*onPressEnter=\{load\} allowClear />\s*</Col>',
        lambda m: m.group(0) + '''
        <Col flex="170px">
          <Input prefix={<SearchOutlined />}
            placeholder="Subcell-ID..."
            value={subcellId} onChange={e => setSubcellId(e.target.value)}
            onPressEnter={load} allowClear />
        </Col>''')
P.replace(RP, "onClick={() => { setSiteName(''); setCellName(''); setTinh(undefined) }}",
              "onClick={() => { setSiteName(''); setCellName(''); setSubcellId(''); setTinh(undefined) }}")

# =============================================================================
P.commit()
PYEOF

echo
if [ "$DO_MIGRATE" = "1" ]; then
  echo ">> Running DB migration ..."
  EXTRA=""; [ "$DROP_UNIQUE" = "1" ] && EXTRA="--drop-conflicting-unique"
  (cd "$ROOT/backend" && python3 migrate_add_subcell_id.py $EXTRA)
fi

if [ "$DO_REGEN" = "1" ]; then
  echo ">> Regenerating Excel templates ..."
  (cd "$ROOT/backend" && SITELINK_TEMPLATE_DIR="$ROOT/backend/templates" python3 create_excel_templates.py)
fi

cat <<'EOF'

=============================== NEXT STEPS ===================================
1. DB migration (REQUIRED before restarting the backend - the sync writes
   subcell_id into the revision tables):
     python backend/migrate_add_subcell_id.py          # add --drop-conflicting-unique if it warns
   Docker:  docker compose exec backend python migrate_add_subcell_id.py
   Or plain SQL:  psql ... -f backend/migrations/add_subcell_id.sql
2. Restart the backend and rebuild the frontend.
3. Excel templates are regenerated by template_regen.py; or re-run this script
   with --regen-templates (or run create_excel_templates.py) to refresh them now.
==============================================================================
EOF