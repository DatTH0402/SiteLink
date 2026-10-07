#!/usr/bin/env bash
# =============================================================================
# update_sitelink_2.sh   (run AFTER update_sitelink.sh)
#   1. Site import / site form: Tinh + Phuong xa become optional; when empty they are
#      auto-mapped from the first 6 chars of "Site name" (dropdown_tinh_xa_phuong.ky_tu_1_6)
#   2. Excel export: columns + order exactly like the import templates
#      (Sites, Cell 3G, Cell 4G, Cell 5G)
#
# Usage:  bash update_sitelink_2.sh [PROJECT_ROOT]
# =============================================================================
set -euo pipefail

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"

[ -f "$ROOT/backend/app/main.py" ] || { echo "ERROR: $ROOT is not the SiteLink root"; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 is required"; exit 1; }

IMP="$ROOT/backend/app/services/import_excel.py"
GEN="$ROOT/backend/create_excel_templates.py"
EXP="$ROOT/backend/app/api/routes/export.py"
FRM="$ROOT/frontend/src/pages/sites/SiteFormPage.tsx"

for f in "$IMP" "$GEN" "$EXP" "$FRM"; do
  [ -f "$f" ] || { echo "ERROR: missing $f"; exit 1; }
done

grep -q "lookup_by_cell_name" "$IMP" || { echo "ERROR: run update_sitelink.sh first (GeoCache.lookup_by_cell_name not found)."; exit 1; }
grep -q "extra_import_rules"  "$GEN" || { echo "ERROR: run update_sitelink.sh first (extra_import_rules not found in generator)."; exit 1; }
if grep -q "SITE_COLS" "$EXP"; then echo "Already applied (export.py already contains SITE_COLS). Nothing to do."; exit 0; fi

BK="$ROOT/.sitelink_backup2_$(date +%Y%m%d_%H%M%S)"
for f in backend/app/services/import_excel.py backend/create_excel_templates.py \
         backend/app/api/routes/export.py frontend/src/pages/sites/SiteFormPage.tsx; do
  mkdir -p "$BK/$(dirname "$f")"; cp "$ROOT/$f" "$BK/$f"
done
echo "Backup written to: $BK"

python3 - "$ROOT" <<'PYEOF'
import os, re, sys

ROOT = sys.argv[1]
files = {}

def fail(msg):
    print(f"[ERROR] {msg}\nNo file was modified.", file=sys.stderr)
    sys.exit(1)

def load(rel):
    if rel not in files:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
            files[rel] = fh.read()
    return files[rel]

def sub(rel, pattern, repl, expect=1, flags=re.M):
    t = load(rel)
    r = repl if callable(repl) else (lambda m, _r=repl: _r)
    new, n = re.subn(pattern, r, t, flags=flags)
    if n != expect:
        fail(f"{rel}: pattern {pattern!r} matched {n} time(s), expected {expect}")
    files[rel] = new

# ═════════════════ A. import_excel.py – Site: optional + auto-map ═════════════
I = "backend/app/services/import_excel.py"

SITE_GEO = r"""        raw_tinh   = _v(row, "Tỉnh", "Tinh", "TINH", "tinh", "Province")
        raw_phuong = _v(row, "Phường xã", "Phuong xa", "Phường Xã", "phuong_xa", "Ward")
        raw_mien   = _v(row, "Miền", "Mien", "MIEN", "mien")

        tinh_col_present = bool(excel_cols & {"Tỉnh", "Tinh", "TINH", "tinh", "Province"})
        xa_col_present   = bool(excel_cols & {"Phường xã", "Phuong xa", "Phường Xã", "phuong_xa", "Ward"})
        mien_col_present = bool(excel_cols & {"Miền", "Mien", "MIEN", "mien"})

        # ── Auto-map Tỉnh / Phường xã from the first 6 chars of Site name ────
        # Only when the user left them empty; values already filled are kept.
        # (GeoCache.lookup_by_cell_name just uses the first 6 chars of any name.)
        auto_xa: Optional[str] = None
        if geo and (not raw_tinh or not raw_phuong):
            mapped = geo.lookup_by_cell_name(site_name)
            if mapped:
                m_tinh, m_xa = mapped
                if not raw_tinh:
                    raw_tinh = m_tinh
                    if not raw_phuong and m_xa:
                        auto_xa = m_xa
                elif not raw_phuong and m_xa and geo.resolve_tinh(raw_tinh) == m_tinh:
                    auto_xa = m_xa

        if geo and raw_tinh:
            tinh_official = geo.resolve_tinh(raw_tinh)
            if not tinh_official:
                row_errors.append(
                    f"Row {row_num} ({label}): Tỉnh/TP '{raw_tinh}' không tìm thấy trong hệ thống."
                )
                fatal_rows.add(row_num)
                errors.extend(row_errors)
                continue
            mien = geo.mien_for(tinh_official) or raw_mien or ""
            phuong_xa_official: Optional[str] = None
            if raw_phuong:
                phuong_xa_official = geo.resolve_xa(tinh_official, raw_phuong)
                if not phuong_xa_official:
                    row_errors.append(
                        f"Row {row_num} ({label}): Phường/Xã '{raw_phuong}' không tìm thấy "
                        f"trong '{tinh_official}'."
                    )
            elif auto_xa:
                phuong_xa_official = auto_xa
        else:
            tinh_official      = raw_tinh or ""
            mien               = raw_mien or ""
            phuong_xa_official = raw_phuong

        # Tinh / Phuong xa are NOT required any more. Empty + no mapping:
        #   column present in file -> clear the field (None)
        #   column absent from file -> leave the existing value untouched (_CLEAR)
        tinh_out = tinh_official       or (None if tinh_col_present else _CLEAR)
        xa_out   = phuong_xa_official  or (None if xa_col_present   else _CLEAR)
        mien_out = mien                or (None if mien_col_present else _CLEAR)
"""

t = load(I)
a = t.find("def parse_site_excel(")
b = t.find("def _resolve_create_rec(", a)
if a < 0 or b < 0:
    fail(f"{I}: parse_site_excel / _resolve_create_rec not found")
seg = t[a:b]

ms = re.search(r'^[ ]{8}raw_tinh[ ]+=[ ]+_v\(row, "Tỉnh", "Tinh", "TINH", "tinh", "Province"\)[ ]*$', seg, re.M)
if not ms:
    fail(f"{I}: site geo block start not found")
me = re.search(r'^[ ]{8}if not tinh_official:\n[^\n]*\n', seg[ms.start():], re.M)
if not me:
    fail(f"{I}: site geo block end ('Tỉnh bị để trống' check) not found")
seg = seg[:ms.start()] + SITE_GEO + seg[ms.start() + me.end():]

old = '"mien": mien, "tinh": tinh_official, "phuong_xa": phuong_xa_official,'
if seg.count(old) != 1:
    fail(f"{I}: site rec line for mien/tinh/phuong_xa found {seg.count(old)} time(s), expected 1")
seg = seg.replace(old, '"mien": mien_out, "tinh": tinh_out, "phuong_xa": xa_out,')
files[I] = t[:a] + seg + t[b:]

# ═════════════════ B. create_excel_templates.py – Site guide ═════════════════
T = "backend/create_excel_templates.py"

SITE_NOTES = r'''_SITE_GEO_NOTE = (
    "KHÔNG bắt buộc – để trống thì hệ thống tự điền theo 6 ký tự đầu của "
    "Site name (khớp cột ky_tu_1_6 trong danh mục Tỉnh/Xã/Phường); "
    "đã nhập thì giữ nguyên"
)

_SITE_GEO_IMPORT_RULES: List[Tuple[str, str]] = [
    ("Tinh / Phuong xa để trống",
     "→ Tự động điền theo 6 ký tự đầu của Site name (khớp cột ky_tu_1_6 trong "
     "danh mục Tỉnh/Xã/Phường). Ví dụ: HNIHKM0001 → HNIHKM"),
    ("Tinh / Phuong xa đã có giá trị",
     "→ Giữ nguyên giá trị đã nhập, KHÔNG tự động điền"),
    ("Không tìm thấy mã 6 ký tự",
     "→ Tinh / Phuong xa để trống (không phải lỗi – các cột này KHÔNG bắt buộc)"),
]

'''
sub(T, r'^SITE_REQUIRED = \{', lambda m: SITE_NOTES + m.group(0))
sub(T, r'^([ ]{8}\("Tinh",\s+)"Tỉnh / Thành phố – chọn từ danh sách",(\s+28,\s+False\),)$',
    lambda m: m.group(1) + '"Tỉnh / Thành phố – chọn từ danh sách. " + _SITE_GEO_NOTE,' + m.group(2))
sub(T, r'^([ ]{8}\("Phuong xa",\s+)"Phường / Xã – chọn từ danh sách",(\s+28,\s+False\),)$',
    lambda m: m.group(1) + '"Phường / Xã – chọn từ danh sách. " + _SITE_GEO_NOTE,' + m.group(2))
sub(T, re.escape('_add_legend_sheet(wb, "Site", column_notes)'),
    '_add_legend_sheet(wb, "Site", column_notes,\n                      extra_import_rules=_SITE_GEO_IMPORT_RULES)')

# ═════════════════ C. SiteFormPage.tsx – Tinh no longer required ═════════════
F = "frontend/src/pages/sites/SiteFormPage.tsx"
sub(F, r'(<Form\.Item name="tinh" label="Tỉnh / Thành phố")\s*\n\s*rules=\{\[\{ required: true, message: \'Vui lòng chọn tỉnh\' \}\]\}>',
    lambda m: m.group(1) + '>')

# ═════════════════ D. export.py – columns exactly like the templates ═════════
E = "backend/app/api/routes/export.py"

COLS_REGION = r'''# ── column definitions ────────────────────────────────────────────────────────
# Each column: (header, width, attribute[, converter]).
# Header names AND order mirror the import templates generated by
# create_excel_templates.py (no STT column) – keep both in sync.
SITE_COLS = [
    ("Mien", 8, "mien"), ("Tinh", 22, "tinh"), ("Phuong xa", 22, "phuong_xa"),
    ("Site name (cu)", 22, "site_name_cu"), ("Site name", 25, "site_name"),
    ("Site VIP", 10, "site_vip"), ("Ma PTM", 14, "ma_ptm"),
    ("Lat", 14, "lat"), ("Long", 14, "long"),
    ("Tram 2G", 10, "tram_2g", _b), ("Tram 3G", 10, "tram_3g", _b),
    ("Tram 4G", 10, "tram_4g", _b), ("Tram 5G", 10, "tram_5g", _b),
    ("Repeater", 10, "repeater", _b), ("Booster", 10, "booster", _b),
    ("Node truyen dan only", 20, "node_truyen_dan_only", _b),
    ("Tram phu song TSCA", 18, "tram_phu_song_tsca", _b),
    ("Phan loai tram", 22, "phan_loai_tram"),
    ("MORAN 3G", 15, "moran_3g"), ("MORAN 4G", 15, "moran_4g"), ("MORAN 5G", 15, "moran_5g"),
    ("Do cao dinh cot anten", 22, "do_cao_dinh_cot_anten"),
    ("Do cao cot anten", 20, "do_cao_cot_anten"),
    ("Dia chi", 30, "dia_chi"), ("Ghi chu", 30, "ghi_chu"),
]

_CELL_HEAD = [
    ("Mien", 8, "mien"), ("Tinh", 22, "tinh"), ("Phuong xa", 22, "phuong_xa"),
    ("Site Name", 25, "site_name"), ("Site Name Old", 22, "site_name_old"),
    ("Cell Name", 25, "cell_name"), ("Cell Name Old", 22, "cell_name_old"),
    ("Cell VIP", 10, "cell_vip"), ("MORAN", 15, "moran"),
    ("Lat", 14, "lat"), ("Long", 14, "long"),
    ("Vung phu song", 15, "vung_phu_song"), ("Vendor", 14, "vendor"),
]
_CELL_ANTENNA = [
    ("Do cao anten", 15, "do_cao_anten"), ("Azimuth", 10, "azimuth"),
    ("M-tilt", 10, "m_tilt"), ("E-Tilt", 10, "e_tilt"),
    ("Total Tilt", 12, "total_tilt"), ("Loai Anten", 30, "loai_anten"),
]
_CHUNG_ANTEN = [("Chung anten", 18, "chung_anten")]
_CELL_TAIL = [
    ("RF", 14, "rf"), ("Cell ID", 14, "cell_id"), ("MIMO", 14, "mimo"),
    ("Cell max power (dBm)", 20, "cell_max_power"), ("BBUname", 16, "bbu_name"),
    ("Cell status (at dump time)", 24, "cell_status"),
]
_OSS = [("OSS", 14, "oss")]

CELL3G_COLS = (
    _CELL_HEAD
    + [("RNC Name", 18, "rnc_name")]
    + _CELL_ANTENNA + _CHUNG_ANTEN + _CELL_TAIL
    + [("UARFCN", 12, "uarfcn"), ("LAC", 10, "lac"), ("RAC", 10, "rac"),
       ("PSC", 10, "psc"), ("URAId", 10, "ura_id"),
       ("CPICH power (dBm)", 18, "cpich_power")]
    + _OSS
)

CELL4G_COLS = (
    _CELL_HEAD + _CELL_ANTENNA + _CHUNG_ANTEN + _CELL_TAIL
    + [("EnodeB ID", 14, "enodeb_id"), ("EARFCN", 12, "earfcn"), ("TAC", 10, "tac"),
       ("PCI", 10, "pci"), ("Root Sequence ID", 18, "root_sequence_id"),
       ("Bandwitdh", 12, "bandwidth"), ("ECI", 12, "eci")]
    + _OSS
)

CELL5G_COLS = (
    _CELL_HEAD + _CELL_ANTENNA + _CHUNG_ANTEN + _CELL_TAIL
    + [("gNodeB ID", 14, "gnodeb_id"), ("TAC", 10, "tac"), ("PCI", 10, "pci"),
       ("Root Sequence ID", 18, "root_sequence_id"),
       ("SSB-ARFCN", 12, "ssb_arfcn"), ("Center-ARFCN", 14, "center_arfcn"),
       ("GSCN", 10, "gscn"), ("Bandwidth (MHz)", 14, "bandwidth"),
       ("NCI", 12, "nci"), ("MU-MIMO", 12, "mu_mimo")]
    + _OSS
)

_SPECS: Dict[str, Dict[str, Any]] = {
    "sites": dict(
        model=Site, kind="site", cols=SITE_COLS, sheet="Sites",
        order=(Site.mien, Site.tinh, Site.site_name), filename="Sites_Export.xlsx"),
    "cells_3g": dict(
        model=Cell3G, kind="cell", cols=CELL3G_COLS, sheet="Cell_3G",
        order=(Cell3G.mien, Cell3G.tinh, Cell3G.site_name, Cell3G.cell_name),
        filename="Cells_3G_Export.xlsx"),
    "cells_4g": dict(
        model=Cell4G, kind="cell", cols=CELL4G_COLS, sheet="Cell_4G",
        order=(Cell4G.mien, Cell4G.tinh, Cell4G.site_name, Cell4G.cell_name),
        filename="Cells_4G_Export.xlsx"),
    "cells_5g": dict(
        model=Cell5G, kind="cell", cols=CELL5G_COLS, sheet="Cell_5G",
        order=(Cell5G.mien, Cell5G.tinh, Cell5G.site_name, Cell5G.cell_name),
        filename="Cells_5G_Export.xlsx"),
}

'''

EXCEL_REGION = r'''def _excel(key, db, params, filters, ids, sort_by, sort_dir):
    spec = _SPECS[key]
    rows = _rows_for(key, db, params, filters, ids, sort_by, sort_dir)
    cols = spec["cols"]
    wb, ws = _make_wb([(c[0], c[1]) for c in cols])
    ws.title = spec["sheet"]
    n_cols = len(cols)
    for idx, obj in enumerate(rows, start=1):
        row = idx + 1
        for col_idx, c in enumerate(cols, start=1):
            val = getattr(obj, c[2], None)
            if len(c) > 3:
                val = c[3](val)
            ws.cell(row=row, column=col_idx, value=val)
        _style_row(ws, row, n_cols, idx % 2 == 0)
    ws.auto_filter.ref = f"A1:{get_column_letter(n_cols)}1"
    return _stream(wb, spec["filename"], len(rows))


'''

t = load(E)
# region 1: "column definitions" banner ... just before def _rows_for(
s1 = re.search(r'^#[^\n]*column definitions[^\n]*$', t, re.M)
e1 = re.search(r'^def _rows_for\(', t, re.M)
if not s1 or not e1 or e1.start() < s1.start():
    fail(f"{E}: 'column definitions' banner / _rows_for not found")
t = t[:s1.start()] + COLS_REGION + t[e1.start():]

# region 2: def _excel( ... just before the KMZ banner
s2 = re.search(r'^def _excel\(', t, re.M)
e2 = re.search(r'^#[^\n]*KMZ[^\n]*$', t, re.M)
if not s2 or not e2 or e2.start() < s2.start():
    fail(f"{E}: def _excel / KMZ banner not found")
t = t[:s2.start()] + EXCEL_REGION + t[e2.start():]
files[E] = t

# ═════════════════ write everything ══════════════════════════════════════════
for rel, text in files.items():
    with open(os.path.join(ROOT, rel), "w", encoding="utf-8") as fh:
        fh.write(text)
    print(f"  patched  {rel}")
print("All patches applied.")
PYEOF

# ----------------------------------------------------------------------------
# Post-checks
# ----------------------------------------------------------------------------
python3 -m py_compile "$EXP" "$IMP" "$GEN" && echo "Syntax OK (export.py, import_excel.py, create_excel_templates.py)"

echo
echo "---- Other references to the removed export symbols (should be empty) ----"
grep -rnE "CELL[345]G_HEADERS|SITE_HEADERS|_site_row|_cell[345]g_row" "$ROOT/backend" \
  --include=*.py --exclude-dir=__pycache__ || echo "(none)"

cat <<EOF

DONE.
  1. Restart the backend (templates are regenerated on startup; no DB migration needed this time).
  2. Rebuild / reload the frontend.
  3. Backup of originals: $BK
EOF