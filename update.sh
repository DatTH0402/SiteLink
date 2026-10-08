#!/usr/bin/env bash
# =============================================================================
# set_kmz_default_opacity.sh – SiteLink KMZ: default cell transparency 50% -> 35%
#
#   EDIT backend/app/services/kmz_export.py                      (idempotent)
#   EDIT frontend/src/components/shared/KmzExportModal.tsx       (optional, cosmetic)
# Usage: bash set_kmz_default_opacity.sh [PROJECT_ROOT]
# =============================================================================
set -euo pipefail

ROOT="${1:-$(pwd)}"
ROOT="$(cd "$ROOT" && pwd)"
PY="backend/app/services/kmz_export.py"
TSX="frontend/src/components/shared/KmzExportModal.tsx"

[[ -f "$ROOT/$PY" ]] || { echo "ERROR: $ROOT/$PY not found (check the project root)"; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 is required"; exit 1; }

BACKUP="$ROOT/.kmz_opacity_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP"
(cd "$ROOT" && cp --parents "$PY" "$BACKUP/")
[[ -f "$ROOT/$TSX" ]] && (cd "$ROOT" && cp --parents "$TSX" "$BACKUP/")
echo "==> Backup: $BACKUP"

python3 - "$ROOT/$PY" "$ROOT/$TSX" <<'__PATCH__'
import re, sys
from pathlib import Path

py_path, tsx_path = Path(sys.argv[1]), Path(sys.argv[2])
problems, writes = [], {}

# ---- backend ---------------------------------------------------------------
t = py_path.read_text(encoding="utf-8")
if '"default_opacity": "35"' in t:
    print("== kmz_export.py: already set to 35%, skipped")
else:
    # 1) default sent to the UI
    old1 = '"default_opacity": "50",'
    if t.count(old1) != 1:
        problems.append(f'kmz_export.py: default_opacity: expected 1 match, found {t.count(old1)}')
    else:
        t = t.replace(old1, '"default_opacity": "35",', 1)

    # 2) server-side fallback when the request has no / an invalid opacity
    old2 = '    if opacity not in OPACITY_MAP:\n        opacity = "50"\n'
    if t.count(old2) != 1:
        problems.append(f'kmz_export.py: opacity fallback: expected 1 match, found {t.count(old2)}')
    else:
        t = t.replace(old2, '    if opacity not in OPACITY_MAP:\n        opacity = "35"\n', 1)

    if not problems:
        writes[py_path] = t

# ---- frontend (cosmetic: the backend value overwrites it on load) ------------
if tsx_path.exists():
    s = tsx_path.read_text(encoding="utf-8")
    pat = r"(const \[opacity,\s*setOpacity\]\s*=\s*useState\()'50'(\))"
    if re.search(pat, s):
        writes[tsx_path] = re.sub(pat, r"\1'35'\2", s, count=1)
    else:
        print("== KmzExportModal.tsx: initial opacity already changed / not found, skipped")
else:
    print("== KmzExportModal.tsx not found, skipped")

if problems:
    print("PATCH ABORTED - nothing was modified:")
    for p in problems:
        print("  - " + p)
    sys.exit(2)

for p, text in writes.items():
    p.write_text(text, encoding="utf-8")
    print(f"== patched {p.name}")
__PATCH__

echo "==> Syntax check"
python3 -m py_compile "$ROOT/$PY"

echo "==> Self-test"
python3 - "$ROOT/$PY" <<'__TEST__'
import importlib.util, io, re, sys, zipfile
from types import SimpleNamespace as NS

spec = importlib.util.spec_from_file_location("kmz_export_test", sys.argv[1])
m = importlib.util.module_from_spec(spec)
sys.modules["kmz_export_test"] = m
spec.loader.exec_module(m)

cols = [{"attr": a, "label": a, "conv": None} for a in
        ("tinh", "site_name", "cell_name", "lat", "long", "azimuth", "vung_phu_song", "earfcn")]

# 1) default announced to the UI
meta = m.layer_meta("cells_4g", cols)
assert meta["default_opacity"] == "35", f"default_opacity is {meta['default_opacity']}"
print("   OK  layer_meta default_opacity = 35")

# 2) a request WITHOUT opacity must produce 35% alpha (hex 59)
rows = [NS(tinh="Da Nang", site_name="S1", cell_name="C1", lat=16.0, long=108.0,
           azimuth="0", vung_phu_song="Outdoor", earfcn="1650")]
kml = zipfile.ZipFile(io.BytesIO(m.build_kmz("cells_4g", rows, cols, {"color_col": "earfcn"}).data)
                      ).read("doc.kml").decode("utf-8")
assert re.search(r"<PolyStyle><color>59[0-9A-F]{6}</color><fill>1</fill>", kml), "default fill alpha is not 59 (35%)"
print("   OK  default export uses alpha 59 (35%)")

# 3) the other choices still work
for key, alpha in (("50", "7F"), ("70", "B3")):
    kml = zipfile.ZipFile(io.BytesIO(m.build_kmz("cells_4g", rows, cols,
          {"color_col": "earfcn", "opacity": key}).data)).read("doc.kml").decode("utf-8")
    assert f"<PolyStyle><color>{alpha}" in kml, f"opacity {key} broken"
print("   OK  50% and 70% still selectable")
print("   All self-tests passed.")
__TEST__

cat <<EOF

==> DONE.
    1. Restart the backend.
    2. Hard-reload the web page (Ctrl+F5): the dialog caches the options it
       got from the server, so an already-open tab keeps showing 50%.
    Backup: $BACKUP
EOF