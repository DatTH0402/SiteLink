#!/usr/bin/env bash
# update.sh — SiteLink fixes (v3: auto-detects the project root)
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run with bash:  bash update.sh [ROOT]"; exit 1
fi
set -uo pipefail

# ── Resolve project root (no hard-coded path) ────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
is_root() { [ -d "$1/backend/app" ] && [ -d "$1/frontend/src" ]; }

ROOT=""
if [ -n "${1:-}" ]; then
  ROOT="$(cd "$1" 2>/dev/null && pwd)" || { echo "ERROR: cannot cd to '$1'"; exit 1; }
elif is_root "$SCRIPT_DIR"; then
  ROOT="$SCRIPT_DIR"
elif TOP="$(git rev-parse --show-toplevel 2>/dev/null)" && is_root "$TOP"; then
  ROOT="$TOP"
fi

if [ -z "$ROOT" ] || ! is_root "$ROOT"; then
  echo "ERROR: could not find the SiteLink root (needs backend/app and frontend/src)."
  echo "Usage: bash update.sh /path/to/SiteLink"
  exit 1
fi
command -v python3 >/dev/null || { echo "ERROR: python3 required"; exit 1; }

IS_GIT=0
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 && IS_GIT=1

echo "==> Project root : $ROOT"
echo "==> Git repo     : $([ $IS_GIT -eq 1 ] && git -C "$ROOT" rev-parse --show-toplevel || echo 'NO (not a git repository)')"
echo "==> Current dir  : $(pwd)"
if [ "$(pwd)" != "$ROOT" ] && [ -z "${1:-}" ]; then
  echo "    note: current directory differs from the root being patched"
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$HOME/.sitelink_patch_backups/$STAMP"

# ── New backend helper ───────────────────────────────────────────────────────
mkdir -p "$ROOT/backend/app/services"
cat > "$ROOT/backend/app/services/site_info.py" <<'PYEOF'
"""
services/site_info.py
Cells denormalise a few columns from their parent Site. The cell forms do not
collect them, so they are copied from the Site on the server side.
"""
from typing import Any, Dict

from app.models.site import Site

SITE_INHERITED_FIELDS = ("site_name", "mien", "tinh", "phuong_xa")


def apply_site_info(data: Dict[str, Any], site: Site) -> Dict[str, Any]:
    out = dict(data)
    out["site_id"] = site.id
    for field in SITE_INHERITED_FIELDS:
        value = getattr(site, field, None)
        if value is not None and str(value).strip() != "":
            out[field] = value
    return out
PYEOF
echo "    wrote backend/app/services/site_info.py"

mkdir -p "$ROOT/backend/scripts"
cat > "$ROOT/backend/scripts/backfill_cell_site_info.sql" <<'SQLEOF'
BEGIN;
UPDATE cells_3g c SET
  mien      = COALESCE(NULLIF(c.mien, ''),      s.mien),
  tinh      = COALESCE(NULLIF(c.tinh, ''),      s.tinh),
  phuong_xa = COALESCE(NULLIF(c.phuong_xa, ''), s.phuong_xa)
FROM sites s WHERE c.site_id = s.id
  AND (c.mien IS NULL OR c.mien = '' OR c.tinh IS NULL OR c.tinh = ''
       OR c.phuong_xa IS NULL OR c.phuong_xa = '');
UPDATE cells_4g c SET
  mien      = COALESCE(NULLIF(c.mien, ''),      s.mien),
  tinh      = COALESCE(NULLIF(c.tinh, ''),      s.tinh),
  phuong_xa = COALESCE(NULLIF(c.phuong_xa, ''), s.phuong_xa)
FROM sites s WHERE c.site_id = s.id
  AND (c.mien IS NULL OR c.mien = '' OR c.tinh IS NULL OR c.tinh = ''
       OR c.phuong_xa IS NULL OR c.phuong_xa = '');
UPDATE cells_5g c SET
  mien      = COALESCE(NULLIF(c.mien, ''),      s.mien),
  tinh      = COALESCE(NULLIF(c.tinh, ''),      s.tinh),
  phuong_xa = COALESCE(NULLIF(c.phuong_xa, ''), s.phuong_xa)
FROM sites s WHERE c.site_id = s.id
  AND (c.mien IS NULL OR c.mien = '' OR c.tinh IS NULL OR c.tinh = ''
       OR c.phuong_xa IS NULL OR c.phuong_xa = '');
COMMIT;
SQLEOF
echo "    wrote backend/scripts/backfill_cell_site_info.sql"

# ── Patch existing sources ───────────────────────────────────────────────────
python3 - "$ROOT" "$BACKUP_DIR" <<'PYEOF'
import re, sys, shutil
from pathlib import Path

root = Path(sys.argv[1])
bak  = Path(sys.argv[2])
total_fail = 0


class Patch:
    def __init__(self, rel):
        self.rel, self.fail = rel, 0
        p = root / rel
        if not p.is_file():
            print(f"--- {rel}\n  FAIL file not found")
            self.text = self.orig = None
            return
        self.text = self.orig = p.read_text(encoding="utf-8")
        print(f"--- {rel}")

    @property
    def ok(self):
        return self.text is not None

    def _fail(self, label, why):
        self.fail += 1
        print(f"  FAIL {label}: {why}")

    def sub(self, label, pattern, make, flags=0, skip_if=None):
        if skip_if and skip_if in self.text:
            print(f"  skip {label} (already applied)")
            return
        ms = list(re.finditer(pattern, self.text, flags))
        if len(ms) != 1:
            return self._fail(label, f"expected 1 match, found {len(ms)}")
        m = ms[0]
        self.text = self.text[:m.start()] + make(m) + self.text[m.end():]
        print(f"  ok   {label}")

    def item(self, name, block):
        pat = r'<Form\.Item\s+name="%s".*?</Form\.Item>' % re.escape(name)
        self.sub(f"Form.Item {name}", pat, lambda m: block.strip(), re.S)

    def strip_star(self, name):
        pat = r'(<Form\.Item\s+name="%s"\s+label="[^"]*?)\s*\*(\s*")' % re.escape(name)
        if not re.search(pat, self.text):
            print(f"  skip label {name} (no literal star)")
            return
        self.sub(f"label {name}: remove literal *", pat,
                 lambda m: m.group(1) + m.group(2))

    def save(self):
        global total_fail
        total_fail += self.fail
        if self.text != self.orig:
            dst = bak / self.rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(root / self.rel, dst)
            (root / self.rel).write_text(self.text, encoding="utf-8")
            print("  => SAVED (backup made)")
        else:
            print("  => no change")


# ── Backend ──────────────────────────────────────────────────────────────────
for tech in ("3g", "4g", "5g"):
    p = Patch(f"backend/app/api/routes/cells_{tech}.py")
    if not p.ok:
        total_fail += 1
        continue

    p.sub("import apply_site_info",
          r'^from app\.models\.site import Site[ \t]*$',
          lambda m: m.group(0) + "\nfrom app.services.site_info import apply_site_info",
          re.M,
          skip_if="from app.services.site_info import apply_site_info")

    if re.search(r'^\s*site\s*=\s*db\.query\(Site\)\.filter\(Site\.id == payload\.site_id\)',
                 p.text, re.M):
        print("  skip keep-site-variable (already present)")
    else:
        p.sub("keep `site` object in create_cell",
              r'^([ \t]*)if not db\.query\(Site\)\.filter\(Site\.id == payload\.site_id\)\.first\(\):',
              lambda m: (f"{m.group(1)}site = db.query(Site).filter("
                         f"Site.id == payload.site_id).first()\n"
                         f"{m.group(1)}if not site:"),
              re.M)

    p.sub("inherit site info on create",
          r'(Cell[345]G)\(\*\*payload\.model_dump\(\),\s*created_by=current_user\.id\)',
          lambda m: (f"{m.group(1)}(**apply_site_info(payload.model_dump(), site), "
                     f"created_by=current_user.id)"),
          skip_if="apply_site_info(payload.model_dump()")
    p.save()

# ── Frontend blocks ──────────────────────────────────────────────────────────
LAT = """
<Form.Item name="lat" label="Lat"
                rules={[
                  { required: true, message: 'Vui lòng nhập Latitude' },
                  { validator: latValidator },
                ]}>
                <InputNumber style={{ width: '100%' }} precision={5} placeholder="8.33 – 23.39" />
              </Form.Item>"""
LONG = """
<Form.Item name="long" label="Long"
                rules={[
                  { required: true, message: 'Vui lòng nhập Longitude' },
                  { validator: lonValidator },
                ]}>
                <InputNumber style={{ width: '100%' }} precision={5} placeholder="102.14 – 109.47" />
              </Form.Item>"""
DOCAO = """
<Form.Item name="do_cao_anten" label="Độ cao anten (m)"
                rules={[
                  { required: true, whitespace: true, message: 'Vui lòng nhập độ cao anten' },
                  { validator: positiveNumberValidator },
                ]}>
                <Input placeholder="vd: 28 hoặc IBC" />
              </Form.Item>"""
AZ = """
<Form.Item name="azimuth" label="Azimuth"
                rules={[
                  { required: true, whitespace: true, message: 'Vui lòng nhập Azimuth' },
                  { validator: azimuthValidator },
                ]}>
                <Input placeholder="vd: 120 hoặc IBC" />
              </Form.Item>"""
MT = """
<Form.Item name="m_tilt" label="M-tilt"
                rules={[{ required: true, whitespace: true, message: 'Vui lòng nhập M-tilt' }]}>
                <Input placeholder="vd: 2 hoặc IBC" />
              </Form.Item>"""
ET = """
<Form.Item name="e_tilt" label="E-Tilt"
                rules={[{ required: true, whitespace: true, message: 'Vui lòng nhập E-Tilt' }]}>
                <Input placeholder="vd: 2 hoặc IBC" />
              </Form.Item>"""

for tech in ("3G", "4G", "5G"):
    p = Patch(f"frontend/src/pages/cells/Cells{tech}Page.tsx")
    if not p.ok:
        total_fail += 1
        continue
    p.item("lat", LAT)
    p.item("long", LONG)
    p.item("do_cao_anten", DOCAO)
    p.item("azimuth", AZ)
    p.item("m_tilt", MT)
    p.item("e_tilt", ET)
    p.strip_star("vendor")
    p.save()

print()
print(f"Summary: {total_fail} failed edit(s)." if total_fail else "Summary: all edits OK.")
sys.exit(1 if total_fail else 0)
PYEOF
PY_RC=$?

echo "==> Python syntax check"
python3 -m py_compile \
  "$ROOT/backend/app/services/site_info.py" \
  "$ROOT/backend/app/api/routes/cells_3g.py" \
  "$ROOT/backend/app/api/routes/cells_4g.py" \
  "$ROOT/backend/app/api/routes/cells_5g.py" && echo "    OK"

echo "==> Verification (occurrence counts)"
grep -c "apply_site_info" "$ROOT"/backend/app/api/routes/cells_{3g,4g,5g}.py
grep -c "required: true"  "$ROOT"/frontend/src/pages/cells/Cells{3G,4G,5G}Page.tsx

echo "==> git status of $ROOT"
if [ $IS_GIT -eq 1 ]; then
  git -C "$ROOT" status --short
  echo "--- diff stat"
  git -C "$ROOT" diff --stat
else
  echo "    (not a git repository — check the files directly)"
fi
echo "    backups (if any): $BACKUP_DIR"

if [ "$PY_RC" -ne 0 ]; then
  echo; echo "!! Some edits FAILED (see FAIL lines). Send me those lines."
  exit 1
fi

cat <<EOF

==> Done. Now:
  1. Rebuild/restart from the directory that holds docker-compose:
       docker compose up -d --build
  2. Hard refresh the browser (Ctrl+F5).
  3. Optional backfill for cells created before the fix:
       docker compose exec -T postgres psql -U sitelink -d sitelink_db \\
           < $ROOT/backend/scripts/backfill_cell_site_info.sql
EOF