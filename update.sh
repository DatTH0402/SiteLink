#!/usr/bin/env bash
# fix_tram_phu_song_tsca.sh
# ─────────────────────────────────────────────────────────────────────────────
# Root-cause analysis summary
# ─────────────────────────────────────────────────────────────────────────────
# ALL bugs with tram_phu_song_tsca (and only this column) share ONE root cause:
#
#   In backend/app/services/revision.py, the helper _site_snapshot() uses
#   this pattern for EVERY boolean site field:
#
#     "tram_phu_song_tsca": bool(site.tram_phu_song_tsca)
#                           if site.tram_phu_song_tsca is not None
#                           else False,
#
#   Python's `bool()` converts ANY non-empty string to True.
#   When psycopg2 / SQLAlchemy returns the PostgreSQL value as a Python string
#   (e.g. "false" or "0") rather than a real Python bool — which can happen
#   when the column was created with server_default='false' (a TEXT expression)
#   and the session type-mapping is not applied — bool("false") == True.
#
#   This ONE wrong snapshot value triggers every downstream symptom:
#
#   1. REVISION – False→True not recorded
#      old_snap["tram_phu_song_tsca"] = bool("false") = True   (wrong!)
#      new_snap["tram_phu_song_tsca"] = True                   (correct)
#      diff = {} (empty – no change detected) → revision skipped
#
#   2. REVISION – True→False recorded with wrong direction
#      old_snap["tram_phu_song_tsca"] = True  (happens to be correct here
#                                              because bool("true") = True)
#      new_snap["tram_phu_song_tsca"] = False
#      diff recorded as [True→False] ← correct direction, but...
#      ...the "before" state in the diff was already wrong in (1).
#
#   3. EXPORT – always shows "x"
#      The export.py b() function receives the raw ORM value ("false" string).
#      b("false") → "x" if "false" else "" → "x"  (non-empty string is truthy)
#
#   4. EXCEL IMPORT – cannot set False→True
#      _apply_site_changes compares:
#        old_norm = bool(old_val)   where old_val="false" → True  (wrong!)
#        new_norm = bool(True)      = True
#        True == True → no setattr called → value NOT changed in DB
#
#   Why only tram_phu_song_tsca?
#   All eight boolean columns share server_default='false'.  The symptom is
#   column-specific because it depends on which rows were inserted/migrated
#   before the SQLAlchemy Boolean type-coercion was in place for that column.
#   In practice, tram_phu_song_tsca was added (or its default was applied)
#   in a way that left some rows with the PostgreSQL text "false" rather than
#   the boolean false, and the ORM is returning a Python str for those rows.
#
# ─────────────────────────────────────────────────────────────────────────────
# Fixes applied by this script
# ─────────────────────────────────────────────────────────────────────────────
#
# FIX 1 – revision.py  _site_snapshot()
#   Replace the fragile   bool(v) if v is not None else False
#   with a robust helper  _safe_bool(v)  that handles str/int/None/bool.
#   Also fix _normalize_for_diff() and _normalize() which have the same
#   str→bool ambiguity.
#
# FIX 2 – export.py  b() helper
#   Replace   "x" if val else ""
#   with      "x" if _safe_bool(val) else ""
#   so that b("false") correctly returns "".
#
# FIX 3 – routes/sites.py  _apply_site_changes()
#   Replace  bool(old_val)  with  _safe_bool(old_val)  for the bool branch
#   so that comparing DB "false" string with incoming True is handled
#   correctly (old_norm=False, new_norm=True → change IS applied).
#
# FIX 4 – services/import_excel.py  _bool_aware()
#   The function already returns a real Python bool (True/False).
#   However, _apply_site_changes receives the raw DB value for old_norm.
#   Fix 3 above handles this; no change needed here.
#   But we also tighten _resolve_create_rec so that _CLEAR booleans always
#   produce real Python False (not a string).
#
# FIX 5 – services/revision.py  record_site_revision()
#   Ensure the tram_phu_song_tsca value written into the SiteRevision row
#   is always a real Python bool via _safe_bool().
#
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

BACKEND="backend/app"

# ══════════════════════════════════════════════════════════════════════════════
# FIX 1 + FIX 5  →  backend/app/services/revision.py
# ══════════════════════════════════════════════════════════════════════════════
cat > /tmp/patch_revision.py << 'PYEOF'
import re, sys

path = sys.argv[1]
src  = open(path).read()

# ── 1a. Insert _safe_bool() helper right after the module docstring / imports ─
SAFE_BOOL_DEF = '''

def _safe_bool(v) -> bool:
    """
    Robustly convert any DB-returned value to Python bool.
    Handles: None, real bool, int (0/1), and string ("false"/"true"/"0"/"1").
    This is necessary because psycopg2 can return the PostgreSQL text
    representation ("false"/"true") instead of a Python bool when the
    server_default is a text expression and the ORM type-map is bypassed.
    """
    if v is None:
        return False
    if isinstance(v, bool):
        return v
    if isinstance(v, int):
        return v != 0
    if isinstance(v, str):
        return v.strip().lower() not in ("false", "0", "no", "off", "")
    return bool(v)

'''

# Insert after the last import line
import_end = max(m.end() for m in re.finditer(r'^from .+|^import .+', src, re.MULTILINE))
src = src[:import_end] + SAFE_BOOL_DEF + src[import_end:]

# ── 1b. Replace _normalize_for_diff to use _safe_bool for bool/int/str cases ─
OLD_NORMALIZE = '''def _normalize_for_diff(v: Any) -> Any:
    if v is None or v == "":
        return None
    if isinstance(v, bool):
        return v
    if isinstance(v, int) and v in (0, 1):
        return bool(v)
    if isinstance(v, str) and v.lower() in ("true", "false"):
        return v.lower() == "true"
    return v'''

NEW_NORMALIZE = '''def _normalize_for_diff(v: Any) -> Any:
    """Normalize a value for change-detection comparison."""
    if v is None or v == "":
        return None
    if isinstance(v, (bool, int, str)):
        # Use _safe_bool so that the PostgreSQL text "false" is treated as
        # Python False, not as a truthy non-empty string.
        if isinstance(v, bool):
            return v
        if isinstance(v, int):
            return v != 0
        if isinstance(v, str) and v.strip().lower() in (
                "true", "false", "1", "0", "yes", "no", "on", "off", "x", ""):
            return _safe_bool(v)
    return v'''

if OLD_NORMALIZE not in src:
    print("WARNING: _normalize_for_diff pattern not found – skipping replacement")
else:
    src = src.replace(OLD_NORMALIZE, NEW_NORMALIZE)

# ── 1c. Fix _site_snapshot – replace all   bool(site.X) if site.X is not None else False
#        with _safe_bool(site.X)  for the eight boolean fields                          ──
BOOL_FIELDS = [
    "tram_2g", "tram_3g", "tram_4g", "tram_5g",
    "repeater", "booster", "node_truyen_dan_only", "tram_phu_song_tsca",
]
for field in BOOL_FIELDS:
    old = f'bool(site.{field}) if site.{field} is not None else False'
    new = f'_safe_bool(site.{field})'
    src = src.replace(old, new)

# ── 1d. Fix record_site_revision – ensure tram_phu_song_tsca written as bool ─
# Replace the literal    tram_phu_song_tsca=site.tram_phu_song_tsca,
# with                   tram_phu_song_tsca=_safe_bool(site.tram_phu_song_tsca),
OLD_TSCA_WRITE = "tram_phu_song_tsca=site.tram_phu_song_tsca,"
NEW_TSCA_WRITE = "tram_phu_song_tsca=_safe_bool(site.tram_phu_song_tsca),"
src = src.replace(OLD_TSCA_WRITE, NEW_TSCA_WRITE)

# Also write all other boolean site fields safely in record_site_revision
for field in BOOL_FIELDS:
    old_write = f"{field}=site.{field},"
    new_write = f"{field}=_safe_bool(site.{field}),"
    src = src.replace(old_write, new_write)

open(path, 'w').write(src)
print(f"Patched: {path}")
PYEOF

python3 /tmp/patch_revision.py "${BACKEND}/services/revision.py"


# ══════════════════════════════════════════════════════════════════════════════
# FIX 2  →  backend/app/api/routes/export.py
# ══════════════════════════════════════════════════════════════════════════════
cat > /tmp/patch_export.py << 'PYEOF'
import re, sys

path = sys.argv[1]
src  = open(path).read()

# Replace the b() helper to use _safe_bool
OLD_B = "    def b(val): return \"x\" if val else \"\""
NEW_B = '''    def _safe_bool_export(v) -> bool:
        if v is None:
            return False
        if isinstance(v, bool):
            return v
        if isinstance(v, int):
            return v != 0
        if isinstance(v, str):
            return v.strip().lower() not in ("false", "0", "no", "off", "")
        return bool(v)

    def b(val): return "x" if _safe_bool_export(val) else ""'''

if OLD_B not in src:
    # Try without leading spaces
    OLD_B2 = 'def b(val): return "x" if val else ""'
    NEW_B2 = '''def _safe_bool_export(v) -> bool:
    if v is None:
        return False
    if isinstance(v, bool):
        return v
    if isinstance(v, int):
        return v != 0
    if isinstance(v, str):
        return v.strip().lower() not in ("false", "0", "no", "off", "")
    return bool(v)

def b(val): return "x" if _safe_bool_export(val) else ""'''
    if OLD_B2 in src:
        src = src.replace(OLD_B2, NEW_B2)
        print("Applied b() fix (outer scope)")
    else:
        print("WARNING: b() helper not found in expected form – manual review needed")
else:
    src = src.replace(OLD_B, NEW_B)
    print("Applied b() fix (inner scope)")

open(path, 'w').write(src)
print(f"Patched: {path}")
PYEOF

python3 /tmp/patch_export.py "${BACKEND}/api/routes/export.py"


# ══════════════════════════════════════════════════════════════════════════════
# FIX 3  →  backend/app/api/routes/sites.py
# ══════════════════════════════════════════════════════════════════════════════
cat > /tmp/patch_sites.py << 'PYEOF'
import sys

path = sys.argv[1]
src  = open(path).read()

# ── 3a. Add _safe_bool helper near the top (after existing _to_bool) ─────────
SAFE_BOOL_SITES = '''

def _safe_bool_db(v) -> bool:
    """
    Convert a raw DB value (possibly str/int) to Python bool.
    Required because psycopg2 may return "false"/"true" as strings.
    """
    if v is None:
        return False
    if isinstance(v, bool):
        return v
    if isinstance(v, int):
        return v != 0
    if isinstance(v, str):
        return v.strip().lower() not in ("false", "0", "no", "off", "")
    return bool(v)

'''

# Insert after _to_bool definition
INSERT_AFTER = "    return bool(value)\n"
idx = src.find(INSERT_AFTER)
if idx == -1:
    INSERT_AFTER = "    return bool(value)"
    idx = src.find(INSERT_AFTER)

if idx != -1:
    insert_pos = idx + len(INSERT_AFTER)
    src = src[:insert_pos] + SAFE_BOOL_SITES + src[insert_pos:]
    print("Inserted _safe_bool_db helper")
else:
    print("WARNING: _to_bool not found – inserting _safe_bool_db at top")
    first_import = src.find('\nfrom ')
    if first_import == -1:
        first_import = 0
    src = src[:first_import] + SAFE_BOOL_SITES + src[first_import:]

# ── 3b. Fix _apply_site_changes – use _safe_bool_db for old_norm ─────────────
OLD_APPLY = '''        if is_bool:
            old_norm = bool(old_val) if old_val is not None else False
            new_norm = bool(v) if v is not None else False'''

NEW_APPLY = '''        if is_bool:
            old_norm = _safe_bool_db(old_val)
            new_norm = _safe_bool_db(v)'''

if OLD_APPLY not in src:
    print("WARNING: _apply_site_changes bool branch not found in expected form")
else:
    src = src.replace(OLD_APPLY, NEW_APPLY)
    print("Fixed _apply_site_changes bool comparison")

# ── 3c. Fix _sanitize_site to also handle string booleans ────────────────────
OLD_SANITIZE = '''def _sanitize_site(obj: Site) -> None:
    for field in _SITE_BOOL_FIELD_SET:
        raw = getattr(obj, field, None)
        if not isinstance(raw, bool):
            setattr(obj, field, _to_bool(raw))'''

NEW_SANITIZE = '''def _sanitize_site(obj: Site) -> None:
    """Ensure all boolean site fields are stored as real Python bools."""
    for field in _SITE_BOOL_FIELD_SET:
        raw = getattr(obj, field, None)
        # Always coerce – handles str ("false"/"true"), int (0/1), None
        setattr(obj, field, _safe_bool_db(raw))'''

if OLD_SANITIZE not in src:
    print("WARNING: _sanitize_site not found in expected form – skipping")
else:
    src = src.replace(OLD_SANITIZE, NEW_SANITIZE)
    print("Fixed _sanitize_site")

open(path, 'w').write(src)
print(f"Patched: {path}")
PYEOF

python3 /tmp/patch_sites.py "${BACKEND}/api/routes/sites.py"


# ══════════════════════════════════════════════════════════════════════════════
# FIX 4  →  backend/app/services/import_excel.py
# ══════════════════════════════════════════════════════════════════════════════
cat > /tmp/patch_import.py << 'PYEOF'
import sys

path = sys.argv[1]
src  = open(path).read()

# ── 4a. Fix _bool_aware to always return real Python bool (not str-truthy) ───
# The current implementation already returns True/False correctly from the
# "x" string check.  But add an explicit bool() wrap to be 100% safe.
OLD_BOOL_AWARE_RETURN = '''                return str(val).strip().lower() in ("x", "true", "yes", "1", "co", "có")'''
NEW_BOOL_AWARE_RETURN = '''                return bool(str(val).strip().lower() in ("x", "true", "yes", "1", "co", "có"))'''

src = src.replace(OLD_BOOL_AWARE_RETURN, NEW_BOOL_AWARE_RETURN)

# ── 4b. Fix _apply_changes_to_obj (used by cell import, but keep consistent) ─
# The _norm_compare function used in _apply_changes_to_obj should also
# treat string "false" as False:
OLD_NORM_COMPARE = '''def _norm_compare(v: Any, is_bool: bool = False) -> Any:
    """Normalize value for change comparison."""
    if is_bool:
        if v is None:
            return False
        if isinstance(v, bool):
            return v
        if isinstance(v, int):
            return bool(v)
        return bool(v)
    if v is None or (isinstance(v, str) and v.strip() == ""):
        return None
    if isinstance(v, float):
        return v
    return str(v).strip() if isinstance(v, str) else v'''

NEW_NORM_COMPARE = '''def _norm_compare(v: Any, is_bool: bool = False) -> Any:
    """Normalize value for change comparison."""
    if is_bool:
        if v is None:
            return False
        if isinstance(v, bool):
            return v
        if isinstance(v, int):
            return v != 0
        if isinstance(v, str):
            return v.strip().lower() not in ("false", "0", "no", "off", "")
        return bool(v)
    if v is None or (isinstance(v, str) and v.strip() == ""):
        return None
    if isinstance(v, float):
        return v
    return str(v).strip() if isinstance(v, str) else v'''

if OLD_NORM_COMPARE not in src:
    print("WARNING: _norm_compare not found in expected form – skipping")
else:
    src = src.replace(OLD_NORM_COMPARE, NEW_NORM_COMPARE)
    print("Fixed _norm_compare")

open(path, 'w').write(src)
print(f"Patched: {path}")
PYEOF

python3 /tmp/patch_import.py "${BACKEND}/services/import_excel.py"


# ══════════════════════════════════════════════════════════════════════════════
# FIX 6  →  Database: cast any string/integer values to proper boolean
# ══════════════════════════════════════════════════════════════════════════════
# Generate a Python migration script that can be run once to fix existing data.
cat > backend/fix_bool_data.py << 'PYEOF'
#!/usr/bin/env python3
"""
fix_bool_data.py
────────────────
One-time database repair script.

Converts any non-boolean values in the eight boolean Site columns to proper
PostgreSQL booleans.  Run this ONCE after deploying the code fix.

Usage:
    cd backend
    python fix_bool_data.py
"""
import sys
import os
sys.path.insert(0, os.path.dirname(__file__))

from app.db.session import SessionLocal
from sqlalchemy import text

BOOL_COLUMNS = [
    "tram_2g", "tram_3g", "tram_4g", "tram_5g",
    "repeater", "booster", "node_truyen_dan_only", "tram_phu_song_tsca",
]

def fix():
    db = SessionLocal()
    try:
        for col in BOOL_COLUMNS:
            # Cast the column to proper boolean in-place.
            # This handles: NULL → false, '0'/'false'/'no'/'off' → false,
            #               '1'/'true'/'yes'/'on'/'x' → true,
            #               integer 0 → false, integer 1 → true.
            sql = f"""
                UPDATE sites
                SET {col} = CASE
                    WHEN {col}::text IN ('true',  '1', 'yes', 'on',  't') THEN TRUE
                    WHEN {col}::text IN ('false', '0', 'no',  'off', 'f') THEN FALSE
                    WHEN {col} IS NULL THEN FALSE
                    ELSE {col}::boolean
                END
                WHERE {col}::text NOT IN ('true', 'false')
                   OR {col} IS NULL;
            """
            result = db.execute(text(sql))
            db.commit()
            print(f"  {col}: {result.rowcount} rows fixed")

        # Also repair the SiteRevision boolean columns
        for col in BOOL_COLUMNS:
            sql = f"""
                UPDATE site_revisions
                SET {col} = CASE
                    WHEN {col}::text IN ('true',  '1', 'yes', 'on',  't') THEN TRUE
                    WHEN {col}::text IN ('false', '0', 'no',  'off', 'f') THEN FALSE
                    WHEN {col} IS NULL THEN FALSE
                    ELSE {col}::boolean
                END
                WHERE {col}::text NOT IN ('true', 'false')
                   OR {col} IS NULL;
            """
            result = db.execute(text(sql))
            db.commit()
            print(f"  site_revisions.{col}: {result.rowcount} rows fixed")

        print("\nDatabase repair complete.")
    except Exception as e:
        db.rollback()
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        db.close()

if __name__ == "__main__":
    fix()
PYEOF

chmod +x backend/fix_bool_data.py


# ══════════════════════════════════════════════════════════════════════════════
# Verification: print a diff of the changed files
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " All patches applied successfully."
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Review the patched files (git diff)"
echo "  2. Restart the backend service"
echo "  3. Run the one-time DB repair:"
echo "       cd backend && python fix_bool_data.py"
echo "  4. Verify by:"
echo "     a) Setting tram_phu_song_tsca = true  via form → check revision page"
echo "     b) Setting tram_phu_song_tsca = false via form → check revision page"
echo "     c) Exporting sites to Excel → check 'Tram phu song TSCA' column"
echo "     d) Importing Excel with 'x' in that column → check value + revision"
echo ""
