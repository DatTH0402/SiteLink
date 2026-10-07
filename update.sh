#!/usr/bin/env bash
# =============================================================================
# update_sitelink.sh
#   1. Excel templates + generator (3G / 4G / 5G cell templates)
#   2. Auto-map Tinh / Phuong xa from the first 6 chars of Cell Name (Excel import only)
#   3. Tinh / Phuong xa are optional (guide, template generation, import validation)
#   4. "Chung anten" drop-list values unified across backend + frontend
#
# Usage:  bash update_sitelink.sh [PROJECT_ROOT]      (default: current dir)
# =============================================================================
set -euo pipefail

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"

[ -f "$ROOT/backend/app/main.py" ] || { echo "ERROR: $ROOT does not look like the SiteLink root (backend/app/main.py not found)"; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 is required"; exit 1; }

if grep -q "lookup_by_cell_name" "$ROOT/backend/app/services/import_excel.py"; then
  echo "Already applied (import_excel.py already contains lookup_by_cell_name). Nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ----------------------------------------------------------------------------
# 0. Backup
# ----------------------------------------------------------------------------
BK="$ROOT/.sitelink_backup_$(date +%Y%m%d_%H%M%S)"
FILES=(
  backend/create_excel_templates.py
  backend/app/main.py
  backend/app/services/import_excel.py
  backend/app/models/cell_3g.py
  backend/app/models/cell_4g.py
  backend/app/models/cell_5g.py
  backend/app/schemas/cell.py
  frontend/src/pages/cells/Cells3GPage.tsx
  frontend/src/pages/cells/Cells4GPage.tsx
  frontend/src/pages/cells/Cells5GPage.tsx
  frontend/src/types/index.ts
)
for f in "${FILES[@]}"; do
  [ -f "$ROOT/$f" ] || { echo "ERROR: missing $f"; exit 1; }
  mkdir -p "$BK/$(dirname "$f")"; cp "$ROOT/$f" "$BK/$f"
done
echo "Backup written to: $BK"

# ----------------------------------------------------------------------------
# 1. Fragment: new cell-template section (replaces sections 7-10 of the generator)
# ----------------------------------------------------------------------------
cat > "$TMP/templates_cell_section.py" <<'PYEOF'
# ══════════════════════════════════════════════════════════════════════════════
# 7.  SHARED CELL COLUMN BUILDER
# ══════════════════════════════════════════════════════════════════════════════

# Required cell column names (must match headers exactly).
# "Tinh" / "Phuong xa" are intentionally NOT required: when they are empty the
# importer fills them from the first 6 characters of "Cell Name".
CELL_REQUIRED = {
    "Site Name",
    "Cell Name",
    "Vendor",
    "Lat",
    "Long",
    "Azimuth",
    "Do cao anten",
    "M-tilt",
    "E-Tilt",
}

_GEO_NOTE = (
    "KHÔNG bắt buộc – để trống thì hệ thống tự điền theo 6 ký tự đầu của "
    "Cell Name (khớp cột ky_tu_1_6 trong danh mục Tỉnh/Xã/Phường); "
    "đã nhập thì giữ nguyên"
)

# (header, note_for_guide, width, is_required)
# ---- block 1: identification / location (before the RNC slot) ---------------
_CELL_COLS_HEAD: List[Tuple[str, str, float, bool]] = [
    ("Mien",           "Miền: MB / MT / MN",                                           8,  False),
    ("Tinh",           "Tỉnh / Thành phố – chọn từ danh sách. " + _GEO_NOTE,          28,  False),
    ("Phuong xa",      "Phường / Xã – chọn từ danh sách. " + _GEO_NOTE,               28,  False),
    ("Site Name",      "Tên site – bắt buộc, phải khớp với site đã có",               28,  True),
    ("Site Name Old",  "Tên site cũ – điền khi site vừa đổi tên",                     24,  False),
    ("Cell Name",      "Tên cell – bắt buộc, duy nhất trong site (vd: HNIHKM44DI4DA)", 28,  True),
    ("Cell Name Old",  "Tên cell cũ – điền khi cell vừa đổi tên",                     24,  False),
    ("Cell VIP",       "Mức độ VIP: VIP hoặc VVIP",                                   10,  False),
    ("MORAN",          "MORAN: VNPT HOST hoặc MBF HOST",                               18,  False),
    ("Lat",            f"Latitude – phải trong {VN_LAT_MIN}–{VN_LAT_MAX}",            14,  True),
    ("Long",           f"Longitude – phải trong {VN_LON_MIN}–{VN_LON_MAX}",           14,  True),
    ("Vung phu song",  "Vùng phủ sóng: Indoor hoặc Outdoor",                          14,  False),
    ("Vendor",         "Hãng thiết bị – bắt buộc, chọn từ danh sách",                 14,  True),
]

# ---- block 2: antenna geometry; "Chung anten" is inserted right after it -----
_CELL_COLS_ANTENNA: List[Tuple[str, str, float, bool]] = [
    ("Do cao anten",   "Độ cao anten – bắt buộc (số hoặc chuỗi, vd: 28 hoặc IBC)",    16,  True),
    ("Azimuth",        "Góc phương vị – bắt buộc (số hoặc chuỗi, vd: 120 hoặc IBC)", 12,  True),
    ("M-tilt",         "Mechanical tilt – bắt buộc (số hoặc chuỗi, vd: 2 hoặc IBC)", 10,  True),
    ("E-Tilt",         "Electrical tilt – bắt buộc (số hoặc chuỗi, vd: 4 hoặc IBC)", 10,  True),
    ("Total Tilt",     "Tổng tilt (số hoặc chuỗi, tự tính hoặc để trống)",            12,  False),
    ("Loai Anten",     "Loại anten – chọn từ danh sách antenna",                       35,  False),
]

# ---- block 3: common tail ----------------------------------------------------
_CELL_COLS_TAIL: List[Tuple[str, str, float, bool]] = [
    ("RF",                         "Tên thiết bị RF",                                  16,  False),
    ("Cell ID",                    "Cell ID (chuỗi hoặc số)",                          14,  False),
    ("MIMO",                       "Cấu hình MIMO – nhập tự do (vd: 2x2, 4x4, 8x8, 32T32R)", 14, False),
    ("Cell max power (dBm)",       "Công suất tối đa cell (dBm)",                      20,  False),
    ("BBUname",                    "Tên BBU",                                          16,  False),
    ("Cell status (at dump time)", "Trạng thái cell tại thời điểm dump",              26,  False),
]

_RNC_COL: Tuple[str, str, float, bool] = (
    "RNC Name", "Tên RNC – chọn từ danh sách theo Vendor", 18, False)

_OSS_COL: Tuple[str, str, float, bool] = (
    "OSS", "Hệ thống OSS nguồn dữ liệu – nhập tự do", 14, False)


def _chung_anten_col(options: List[str]) -> Tuple[str, str, float, bool]:
    return (
        "Chung anten",
        "Chung anten – chọn từ danh sách: " + ", ".join(options),
        20,
        False,
    )


def _cell_columns(
    chung_options: List[str],
    *,
    rnc_col: bool,
    extra_cols: List[Tuple[str, str, float, bool]],
) -> List[Tuple[str, str, float, bool]]:
    """
    Final column order:
      HEAD → [RNC Name (3G only)] → ANTENNA (…Total Tilt, Loai Anten)
           → Chung anten → TAIL (RF …) → tech extras → OSS (always last)
    """
    cols = list(_CELL_COLS_HEAD)
    if rnc_col:
        cols.append(_RNC_COL)
    cols += _CELL_COLS_ANTENNA
    cols.append(_chung_anten_col(chung_options))
    cols += _CELL_COLS_TAIL
    cols += extra_cols
    cols.append(_OSS_COL)
    return cols


def _apply_common_cell_validations(
    wb: Workbook,
    ws: Worksheet,
    cm: Dict[str, int],
    lookup_col_offset: int = 1,
) -> int:
    """Apply all common cell validations. Returns next free lookup col index.
    NOTE: MIMO has no drop-down any more (free text)."""
    lc = lookup_col_offset

    lk_tinh = _write_lookup_col(wb, lc, TINH_LIST,     "Tinh");      lc += 1
    lk_xa   = _write_lookup_col(wb, lc, ALL_PHUONG_XA, "PhuongXa");  lc += 1

    _apply_dv(ws, _dv_list_inline(MIEN_LIST),      cm["Mien"])
    _apply_dv(ws, _dv_list_formula(lk_tinh),        cm["Tinh"])
    _apply_dv(ws, _dv_list_formula(lk_xa),          cm["Phuong xa"])
    _apply_dv(ws, _dv_list_inline(CELL_VIP_LIST),   cm["Cell VIP"])
    _apply_dv(ws, _dv_list_inline(MORAN_LIST),       cm["MORAN"])

    _apply_dv(ws, _dv_decimal(VN_LAT_MIN, VN_LAT_MAX,
                               "Latitude không hợp lệ",
                               f"Latitude phải trong khoảng {VN_LAT_MIN}–{VN_LAT_MAX}"),
              cm["Lat"])
    _apply_dv(ws, _dv_decimal(VN_LON_MIN, VN_LON_MAX,
                               "Longitude không hợp lệ",
                               f"Longitude phải trong khoảng {VN_LON_MIN}–{VN_LON_MAX}"),
              cm["Long"])

    _apply_dv(ws, _dv_list_inline(VUNG_LIST),   cm["Vung phu song"])
    _apply_dv(ws, _dv_list_inline(VENDOR_LIST), cm["Vendor"])

    lk_ant = _write_lookup_col(wb, lc, ANTENNA_NAMES, "LoaiAnten"); lc += 1
    _apply_dv(ws, _dv_list_formula(lk_ant), cm["Loai Anten"])

    return lc


def _build_cell_wb(
    sheet_title: str,
    columns: List[Tuple[str, str, float, bool]],
) -> Tuple[Workbook, Worksheet, Dict[str, int]]:
    """Create workbook from a FULL column list, no note row."""
    req_idx = {idx + 1 for idx, (_h, _n, _w, req) in enumerate(columns) if req}

    wb = Workbook()
    ws = wb.active
    ws.title = sheet_title

    n_cols = len(columns)
    for idx, (hdr, _note, width, _req) in enumerate(columns, start=1):
        ws.cell(row=1, column=idx, value=hdr)
        _set_col_width(ws, idx, width)

    _style_header_row(ws, n_cols, row=1)
    _style_data_rows(ws, n_cols, FIRST_DATA, LAST_DATA, req_idx)
    _freeze(ws, "A2")
    _add_autofilter(ws, n_cols)

    return wb, ws, _col_map(columns)


_CELL_GEO_IMPORT_RULES: List[Tuple[str, str]] = [
    ("Tinh / Phuong xa để trống",
     "→ Tự động điền theo 6 ký tự đầu của Cell Name (khớp cột ky_tu_1_6 trong "
     "danh mục Tỉnh/Xã/Phường). Ví dụ: HNIHKM44DI4DA → HNIHKM"),
    ("Tinh / Phuong xa đã có giá trị",
     "→ Giữ nguyên giá trị đã nhập, KHÔNG tự động điền"),
    ("Không tìm thấy mã 6 ký tự",
     "→ Tinh / Phuong xa để trống (không phải lỗi – các cột này KHÔNG bắt buộc)"),
]


def _finish_cell_template(
    wb: Workbook,
    ws: Worksheet,
    cm: Dict[str, int],
    all_cols: List[Tuple[str, str, float, bool]],
    tech_label: str,
    filename: str,
    sample: Dict[str, Any],
) -> None:
    for k, v in sample.items():
        if k in cm:
            ws.cell(row=FIRST_DATA, column=cm[k], value=v)

    column_notes = [(h, note, req) for h, note, _w, req in all_cols]
    _add_legend_sheet(wb, tech_label, column_notes,
                      extra_import_rules=_CELL_GEO_IMPORT_RULES)
    _finalize_sheets(wb)

    path = os.path.join(OUTPUT_DIR, filename)
    wb.save(path)
    print(f"  ✓  {path}")


# ══════════════════════════════════════════════════════════════════════════════
# 8.  TEMPLATE: CELL 3G
# ══════════════════════════════════════════════════════════════════════════════

def create_cell3g_template() -> None:
    # Removed vs. old template: Baseband, ARFCN.   Added: OSS (last column).
    extra_cols: List[Tuple[str, str, float, bool]] = [
        ("UARFCN",            "UMTS ARFCN",                 12, False),
        ("LAC",               "Location Area Code",         12, False),
        ("RAC",               "Routing Area Code",          12, False),
        ("PSC",               "Primary Scrambling Code",    12, False),
        ("URAId",             "URA ID",                     10, False),
        ("CPICH power (dBm)", "CPICH power (dBm)",          18, False),
    ]
    all_cols = _cell_columns(CHUNG_3G, rnc_col=True, extra_cols=extra_cols)

    wb, ws, cm = _build_cell_wb("Cell_3G", all_cols)
    next_lc    = _apply_common_cell_validations(wb, ws, cm, lookup_col_offset=1)

    _apply_dv(ws, _dv_list_inline(CHUNG_3G), cm["Chung anten"])

    lk_rnc = _write_lookup_col(wb, next_lc, ALL_RNC, "RNCName"); next_lc += 1
    _apply_dv(ws, _dv_list_formula(lk_rnc), cm["RNC Name"])

    _apply_dv(ws, _dv_decimal(-30, 50,
                               "CPICH power không hợp lệ",
                               "CPICH power thường trong khoảng -30 đến 50 dBm"),
              cm["CPICH power (dBm)"])
    _apply_dv(ws, _dv_decimal(-30, 50,
                               "Cell max power không hợp lệ",
                               "Cell max power thường trong khoảng -30 đến 50 dBm"),
              cm["Cell max power (dBm)"])

    sample = {
        "Mien": "MB", "Tinh": TINH_LIST[0] if TINH_LIST else "Hà Nội",
        "Site Name": "HNI_XXXX_001", "Cell Name": "HNI_XXXX_001_C1",
        "Vendor": "Huawei", "Lat": 21.0285, "Long": 105.8542,
        "Azimuth": 120, "Do cao anten": 28, "M-tilt": 2, "E-Tilt": 4,
        "MIMO": "2x2", "Chung anten": CHUNG_3G[0],
    }
    _finish_cell_template(wb, ws, cm, all_cols, "Cell 3G",
                          "template_cell_3g.xlsx", sample)


# ══════════════════════════════════════════════════════════════════════════════
# 9.  TEMPLATE: CELL 4G
# ══════════════════════════════════════════════════════════════════════════════

def create_cell4g_template() -> None:
    # Removed vs. old template: Baseband.   Added: OSS (last column).
    extra_cols: List[Tuple[str, str, float, bool]] = [
        ("EnodeB ID",        "eNodeB ID",                                       16, False),
        ("EARFCN",           "E-UTRA Absolute Radio Frequency Channel Number",  14, False),
        ("TAC",              "Tracking Area Code",                              12, False),
        ("PCI",              "Physical Cell Identity 0–503",                    12, False),
        ("Root Sequence ID", "Root Sequence Index",                             18, False),
        ("Bandwitdh",        "Bandwidth (MHz) – ví dụ: 5, 10, 15, 20",          16, False),
        ("ECI",              "E-UTRAN Cell Identifier",                         16, False),
    ]
    all_cols = _cell_columns(CHUNG_4G, rnc_col=False, extra_cols=extra_cols)

    wb, ws, cm = _build_cell_wb("Cell_4G", all_cols)
    _apply_common_cell_validations(wb, ws, cm, lookup_col_offset=1)

    _apply_dv(ws, _dv_list_inline(CHUNG_4G), cm["Chung anten"])
    _apply_dv(ws, _dv_whole(0, 503, "PCI không hợp lệ",
                             "PCI phải trong khoảng 0 – 503"),
              cm["PCI"])
    _apply_dv(ws, _dv_decimal(-30, 50,
                               "Cell max power không hợp lệ",
                               "Cell max power thường trong khoảng -30 đến 50 dBm"),
              cm["Cell max power (dBm)"])

    sample = {
        "Mien": "MN", "Tinh": TINH_LIST[-1] if TINH_LIST else "TP. Hồ Chí Minh",
        "Site Name": "HCM_XXXX_001", "Cell Name": "HCM_XXXX_001_C1",
        "Vendor": "Ericsson", "Lat": 10.7769, "Long": 106.7009,
        "Azimuth": 0, "Do cao anten": 30, "M-tilt": 3, "E-Tilt": 5,
        "MIMO": "4x4", "Chung anten": CHUNG_4G[0], "PCI": 100,
    }
    _finish_cell_template(wb, ws, cm, all_cols, "Cell 4G",
                          "template_cell_4g.xlsx", sample)


# ══════════════════════════════════════════════════════════════════════════════
# 10. TEMPLATE: CELL 5G
# ══════════════════════════════════════════════════════════════════════════════

def create_cell5g_template() -> None:
    # Removed vs. old template: Baseband, MU-MIMO drop-list.
    # Added: Chung anten (new for 5G), OSS (last column).
    extra_cols: List[Tuple[str, str, float, bool]] = [
        ("gNodeB ID",        "gNodeB ID",                                       16, False),
        ("TAC",              "Tracking Area Code",                              12, False),
        ("PCI",              "Physical Cell Identity 0–1007 (NR)",              12, False),
        ("Root Sequence ID", "Root Sequence Index",                             18, False),
        ("SSB-ARFCN",        "SSB Absolute Radio Frequency Channel Number",     14, False),
        ("Center-ARFCN",     "Center Frequency ARFCN",                          16, False),
        ("GSCN",             "Global Synchronization Channel Number",           14, False),
        ("Bandwidth (MHz)",  "Bandwidth (MHz) – ví dụ: 50, 100, 200",           16, False),
        ("NCI",              "NR Cell Identity",                                16, False),
        ("MU-MIMO",          "Multi-User MIMO – nhập tự do (vd: Yes, No, 16 layers)", 14, False),
    ]
    all_cols = _cell_columns(CHUNG_5G, rnc_col=False, extra_cols=extra_cols)

    wb, ws, cm = _build_cell_wb("Cell_5G", all_cols)
    _apply_common_cell_validations(wb, ws, cm, lookup_col_offset=1)

    _apply_dv(ws, _dv_list_inline(CHUNG_5G), cm["Chung anten"])
    _apply_dv(ws, _dv_whole(0, 1007, "PCI không hợp lệ",
                             "NR PCI phải trong khoảng 0 – 1007"),
              cm["PCI"])
    _apply_dv(ws, _dv_decimal(-30, 60,
                               "Cell max power không hợp lệ",
                               "Cell max power thường trong khoảng -30 đến 60 dBm"),
              cm["Cell max power (dBm)"])

    sample = {
        "Mien": "MT", "Tinh": TINH_LIST[10] if len(TINH_LIST) > 10 else "Đà Nẵng",
        "Site Name": "DNG_XXXX_001", "Cell Name": "DNG_XXXX_001_C1_5G",
        "Vendor": "Nokia", "Lat": 16.0544, "Long": 108.2022,
        "Azimuth": 240, "Do cao anten": 32, "M-tilt": 1, "E-Tilt": 3,
        "MIMO": "8x8", "MU-MIMO": "Yes", "Chung anten": CHUNG_5G[0], "PCI": 200,
    }
    _finish_cell_template(wb, ws, cm, all_cols, "Cell 5G",
                          "template_cell_5g.xlsx", sample)


PYEOF

# ----------------------------------------------------------------------------
# 2. Fragment: new GeoCache (adds ky_tu_1_6 lookup)
# ----------------------------------------------------------------------------
cat > "$TMP/geocache.py" <<'PYEOF'
class GeoCache:
    def __init__(self, db) -> None:
        from app.models.dropdown import DropdownTinhXaPhuong
        rows = (
            db.query(DropdownTinhXaPhuong)
            .order_by(DropdownTinhXaPhuong.id)
            .all()
        )
        self.tinh_map:  Dict[str, str] = {}
        self.xa_map:    Dict[Tuple[str, str], str] = {}
        self.tinh_mien: Dict[str, str] = {}
        # ky_tu_1_6 (e.g. "HNIHKM") -> (ten_tinh, ten_phuong_xa)
        self.code_map:  Dict[str, Tuple[str, str]] = {}
        for r in rows:
            if r.ten_tinh:
                k = _normalize(r.ten_tinh)
                self.tinh_map[k]           = r.ten_tinh
                self.tinh_mien[r.ten_tinh] = r.mien or ""
            if r.ten_tinh and r.ten_phuong_xa:
                self.xa_map[
                    (_normalize(r.ten_tinh), _normalize(r.ten_phuong_xa))
                ] = r.ten_phuong_xa
            # 6-character code used to auto-map Tinh / Phuong xa from Cell Name
            code = (r.ky_tu_1_6 or "").strip().upper()
            if not code:
                code = f"{r.ma_tinh or ''}{r.ma_phuong_xa or ''}".strip().upper()
            if code and r.ten_tinh and code not in self.code_map:
                self.code_map[code] = (r.ten_tinh, r.ten_phuong_xa or "")

    def resolve_tinh(self, raw: Optional[str]) -> Optional[str]:
        if not raw:
            return None
        return self.tinh_map.get(_normalize(raw))

    def resolve_xa(self, tinh_official: str, raw_xa: Optional[str]) -> Optional[str]:
        if not raw_xa or not tinh_official:
            return None
        return self.xa_map.get((_normalize(tinh_official), _normalize(raw_xa)))

    def mien_for(self, tinh_official: str) -> str:
        return self.tinh_mien.get(tinh_official, "")

    def lookup_by_cell_name(self, cell_name: Optional[str]) -> Optional[Tuple[str, str]]:
        """First 6 characters of the cell name (e.g. HNIHKM44DI4DA -> HNIHKM)
        -> (ten_tinh, ten_phuong_xa) from dropdown_tinh_xa_phuong.ky_tu_1_6."""
        if not cell_name:
            return None
        code = str(cell_name).strip().upper()[:6]
        if len(code) < 6:
            return None
        return self.code_map.get(code)


PYEOF

# ----------------------------------------------------------------------------
# 3. Fragment: auto-mapping block inside _cell_common_aware
# ----------------------------------------------------------------------------
cat > "$TMP/geo_block.py" <<'PYEOF'
    raw_tinh   = _v(row, "Tỉnh", "Tinh", "tinh")
    raw_phuong = _v(row, "Phường xã", "Phuong xa", "phuong_xa")
    raw_mien   = _v(row, "Miền", "Mien", "mien")

    cell_name = _v(row, "Cell Name", "Cell name", "cell_name") or ""
    label     = cell_name or f"row {row_num}"

    # ── Auto-map Tỉnh / Phường xã from the first 6 chars of Cell Name ────────
    # Only when the user left Tinh and/or Phuong xa empty. Values the user has
    # already filled in are NEVER overridden. (Excel import only – not forms.)
    auto_xa: Optional[str] = None
    if geo and cell_name and (not raw_tinh or not raw_phuong):
        mapped = geo.lookup_by_cell_name(cell_name)
        if mapped:
            m_tinh, m_xa = mapped
            if not raw_tinh:
                raw_tinh = m_tinh
                if not raw_phuong and m_xa:
                    auto_xa = m_xa
            elif not raw_phuong and m_xa and geo.resolve_tinh(raw_tinh) == m_tinh:
                # user gave Tinh (same province as the code) but no ward
                auto_xa = m_xa

    # Tinh / Phuong xa are NOT required: empty + no mapping found is not an error.
    if geo and raw_tinh:
        tinh_official = geo.resolve_tinh(raw_tinh)
        if not tinh_official:
            errors_out.append(
                f"Row {row_num}: Tỉnh/TP '{raw_tinh}' không tìm thấy trong hệ thống."
            )
            tinh_official = raw_tinh
        mien = geo.mien_for(tinh_official) or raw_mien or ""
        phuong_xa_official: Optional[str] = None
        if raw_phuong:
            phuong_xa_official = geo.resolve_xa(tinh_official, raw_phuong)
        elif auto_xa:
            phuong_xa_official = auto_xa
    else:
        tinh_official      = raw_tinh
        mien               = raw_mien
        phuong_xa_official = raw_phuong
PYEOF

# ----------------------------------------------------------------------------
# 4. Fragment: 5G "Chung anten" validation block for import
# ----------------------------------------------------------------------------
cat > "$TMP/chung5g_block.py" <<'PYEOF'
        chung_val = _v_aware(row, excel_cols, "Chung anten", "chung_anten")
        if chung_val and chung_val is not _CLEAR:
            _check_dropdown(chung_val, "Chung anten", ALLOWED_CHUNG_5G,
                            row_num, label, row_errors)
PYEOF

# ----------------------------------------------------------------------------
# 5. New file: lightweight startup migration (no Alembic in the project)
# ----------------------------------------------------------------------------
cat > "$ROOT/backend/app/db/light_migrations.py" <<'PYEOF'
"""
light_migrations.py
-------------------
Idempotent, startup-time schema/data fixes (the project uses
Base.metadata.create_all, which never alters existing tables).

  1. cells_5g.chung_anten column (new)
  2. widen mimo / mu_mimo to VARCHAR(100) (drop-list removed -> free text)
  3. remap legacy "chung_anten" values to the new drop-list values
"""
from __future__ import annotations

import logging

from sqlalchemy import bindparam, text

from app.db.session import engine

logger = logging.getLogger(__name__)

CHUNG_ANTEN_VALID = {
    "cells_3g": ["3G only", "3G4G", "2G3G", "2G3G4G", "3G5G", "3G4G5G"],
    "cells_4g": ["4G only", "3G4G", "2G3G4G", "4G5G", "3G4G5G"],
    "cells_5g": ["5G only", "3G5G", "4G5G", "3G4G5G"],
}

# legacy -> new. (Legacy "2G/4G" has no equivalent in the new 4G list: left as is.)
CHUNG_ANTEN_REMAP = {
    "cells_3g": {
        "3G": "3G only", "3G/4G": "3G4G", "2G/3G/4G": "2G3G4G",
        "3G/4G/5G": "3G4G5G", "3G/5G": "3G5G",
    },
    "cells_4g": {
        "4G": "4G only", "3G/4G": "3G4G", "2G/3G/4G": "2G3G4G",
        "4G/5G": "4G5G", "3G/4G/5G": "3G4G5G",
    },
    "cells_5g": {},
}


def _widen(conn, table: str, column: str, length: int) -> None:
    cur = conn.execute(
        text(
            "SELECT character_maximum_length FROM information_schema.columns "
            "WHERE table_schema = current_schema() "
            "AND table_name = :t AND column_name = :c"
        ),
        {"t": table, "c": column},
    ).scalar()
    if cur is not None and cur < length:
        conn.execute(text(f"ALTER TABLE {table} ALTER COLUMN {column} TYPE VARCHAR({length})"))
        logger.info("[migrate] %s.%s widened %s -> %s", table, column, cur, length)


def run_light_migrations() -> None:
    try:
        with engine.begin() as conn:
            # 1. new column
            conn.execute(text(
                "ALTER TABLE cells_5g ADD COLUMN IF NOT EXISTS chung_anten VARCHAR(100)"
            ))

            # 2. free-text MIMO / MU-MIMO
            _widen(conn, "cells_3g", "mimo", 100)
            _widen(conn, "cells_4g", "mimo", 100)
            _widen(conn, "cells_5g", "mimo", 100)
            _widen(conn, "cells_5g", "mu_mimo", 100)

            # 3. legacy value remap
            for table, mapping in CHUNG_ANTEN_REMAP.items():
                for old, new in mapping.items():
                    conn.execute(
                        text(f"UPDATE {table} SET chung_anten = :new WHERE chung_anten = :old"),
                        {"new": new, "old": old},
                    )
                stmt = text(
                    f"SELECT COUNT(*) FROM {table} "
                    "WHERE chung_anten IS NOT NULL AND chung_anten <> '' "
                    "AND chung_anten NOT IN :vals"
                ).bindparams(bindparam("vals", expanding=True))
                n = conn.execute(stmt, {"vals": CHUNG_ANTEN_VALID[table]}).scalar()
                if n:
                    logger.warning(
                        "[migrate] %s: %s row(s) have a 'chung_anten' value outside the new list "
                        "(e.g. legacy '2G/4G') – please review manually.", table, n)
    except Exception:
        logger.exception("[migrate] light migration failed (app will continue)")
PYEOF

# ----------------------------------------------------------------------------
# 6. Apply all patches (all-or-nothing: files are written only if every anchor matched)
# ----------------------------------------------------------------------------
python3 - "$ROOT" "$TMP" <<'PYEOF'
import os, re, sys

ROOT, TMP = sys.argv[1], sys.argv[2]
files = {}

def fail(msg):
    print(f"[ERROR] {msg}\nNo file was modified.", file=sys.stderr)
    sys.exit(1)

def load(rel):
    if rel not in files:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
            files[rel] = fh.read()
    return files[rel]

def frag(name):
    with open(os.path.join(TMP, name), encoding="utf-8") as fh:
        return fh.read()

def sub(rel, pattern, repl, expect=1, flags=re.M):
    t = load(rel)
    r = repl if callable(repl) else (lambda m, _r=repl: _r)
    new, n = re.subn(pattern, r, t, flags=flags)
    if n != expect:
        fail(f"{rel}: pattern {pattern!r} matched {n} time(s), expected {expect}")
    files[rel] = new

def line_start(t, idx):
    return t.rfind("\n", 0, idx) + 1

# ═════════════════════════ A. create_excel_templates.py ═════════════════════
T = "backend/create_excel_templates.py"

sub(T, r'^CHUNG_3G\s*=.*$',
    'CHUNG_3G      = ["3G only", "3G4G", "2G3G", "2G3G4G", "3G5G", "3G4G5G"]')
sub(T, r'^CHUNG_4G\s*=.*$',
    'CHUNG_4G      = ["4G only", "3G4G", "2G3G4G", "4G5G", "3G4G5G"]\n'
    'CHUNG_5G      = ["5G only", "3G5G", "4G5G", "3G4G5G"]')

# legend sheet: extra import rules parameter
sub(T, r'^([ ]*column_notes: Optional\[List\[Tuple\[str, str, bool\]\]\] = None,\n)(\) -> None:)',
    lambda m: m.group(1)
              + "    extra_import_rules: Optional[List[Tuple[str, str]]] = None,\n"
              + m.group(2))
sub(T, r'for col_a, col_b in import_rules:',
    'for col_a, col_b in list(import_rules) + list(extra_import_rules or []):')

# replace sections 7..10 (up to the "11. TEMPLATE: ANTENNA" banner)
t = load(T)
m7  = re.search(r'#\s*7\.\s+SHARED CELL COLUMN BUILDER', t)
m11 = re.search(r'#\s*11\.\s+TEMPLATE: ANTENNA', t)
if not m7 or not m11 or m11.start() < m7.start():
    fail(f"{T}: could not locate section 7 / section 11 banners")
s = line_start(t, line_start(t, m7.start()) - 1)     # banner line above the title
e = line_start(t, line_start(t, m11.start()) - 1)
old_region = t[s:e]
if "def create_cell3g_template" not in old_region or "def create_cell5g_template" not in old_region:
    fail(f"{T}: sections 7-10 do not contain the expected functions")
files[T] = t[:s] + frag("templates_cell_section.py") + t[e:]

# ═════════════════════════ B. import_excel.py ════════════════════════════════
I = "backend/app/services/import_excel.py"

sub(I, r'^ALLOWED_CHUNG_3G\s*=.*$',
    'ALLOWED_CHUNG_3G  = {"3G only", "3G4G", "2G3G", "2G3G4G", "3G5G", "3G4G5G"}')
sub(I, r'^ALLOWED_CHUNG_4G\s*=.*$',
    'ALLOWED_CHUNG_4G  = {"4G only", "3G4G", "2G3G4G", "4G5G", "3G4G5G"}\n'
    'ALLOWED_CHUNG_5G  = {"5G only", "3G5G", "4G5G", "3G4G5G"}')

# GeoCache -> new version
t = load(I)
gs = t.find("class GeoCache:")
ge = t.find("def _read_excel(", gs)
if gs < 0 or ge < 0:
    fail(f"{I}: GeoCache / _read_excel anchors not found")
files[I] = t[:gs] + frag("geocache.py") + t[ge:]

# geo block in _cell_common_aware
t = load(I)
ms = re.search(r'^[ ]{4}raw_tinh[ ]+=[ ]+_v\(row, "Tỉnh", "Tinh", "tinh"\)[ ]*$', t, re.M)
if not ms:
    fail(f"{I}: geo block start not found in _cell_common_aware")
me = re.search(r'^[ ]{4}label[ ]+=[ ]+cell_name or f"row \{row_num\}"[ ]*\n', t[ms.start():], re.M)
if not me:
    fail(f"{I}: geo block end not found in _cell_common_aware")
end_abs = ms.start() + me.end()
files[I] = t[:ms.start()] + frag("geo_block.py") + t[end_abs:]

# MIMO: drop-list validation removed (free text)
sub(I, r'[ ]{4}if mimo_val and mimo_val is not _CLEAR:\n[ ]{8}_check_dropdown\(mimo_val,[^)]*\)\n', '')

# OSS column (common to 3G/4G/5G)
sub(I, r'("Cell max power",\s*"cell_max_power"\),)',
    lambda m: m.group(1) + '\n        "oss":            _v_aware(row, excel_cols, "OSS", "Oss", "oss"),')

# 5G: Chung anten (new) + MU-MIMO free text
sub(I, r'[ ]{8}mu_mimo_val = _v_aware\([^\n]*\)\n[ ]{8}if mu_mimo_val and mu_mimo_val is not _CLEAR:\n[ ]{12}_check_dropdown\(mu_mimo_val,[^)]*\)\n',
    frag("chung5g_block.py"))
sub(I, r'("gnodeb_id":\s*_v_aware\(row, excel_cols, "gNodeB ID", "gnodeb_id"\),)',
    lambda m: '"chung_anten":      chung_val,\n            ' + m.group(1))
sub(I, r'"mu_mimo":\s*mu_mimo_val,',
    '"mu_mimo":          _v_aware(row, excel_cols, "MU-MIMO", "mu_mimo"),')

# ═════════════════════════ C. models / schemas ═══════════════════════════════
M5 = "backend/app/models/cell_5g.py"
if "chung_anten" in load(M5):
    fail(f"{M5} already has chung_anten – unexpected state")
sub(M5, r'(^[ ]*loai_anten[ ]*=[ ]*Column\(String\(200\)\)[^\n]*\n)',
    lambda m: m.group(1) + "    chung_anten      = Column(String(100))\n")
for rel in ("backend/app/models/cell_3g.py", "backend/app/models/cell_4g.py", M5):
    sub(rel, r'(^[ ]*(?:mu_)?mimo[ ]*=[ ]*Column\(String\()20(\)\))',
        lambda m: m.group(1) + "100" + m.group(2), expect=1)

SC = "backend/app/schemas/cell.py"
sub(SC, r'^([ ]*)gnodeb_id:[ ]*Optional\[str\] = None\n',
    lambda m: m.group(0) + m.group(1) + "chung_anten:      Optional[str] = None\n", expect=2)

# ═════════════════════════ D. main.py ════════════════════════════════════════
MA = "backend/app/main.py"
sub(MA, r'^from app\.db\.base import Base\n',
    lambda m: m.group(0) + "from app.db.light_migrations import run_light_migrations\n")
sub(MA, r'^def on_startup\(\):\n',
    lambda m: m.group(0) + "    run_light_migrations()   # add cells_5g.chung_anten, widen mimo, remap legacy values\n")

# ═════════════════════════ E. frontend ═══════════════════════════════════════
P3 = "frontend/src/pages/cells/Cells3GPage.tsx"
P4 = "frontend/src/pages/cells/Cells4GPage.tsx"
P5 = "frontend/src/pages/cells/Cells5GPage.tsx"
TY = "frontend/src/types/index.ts"

sub(P3, r'^const CHUNG_ANTEN_3G = \[[^\]]*\]',
    "const CHUNG_ANTEN_3G = ['3G only', '3G4G', '2G3G', '2G3G4G', '3G5G', '3G4G5G']")
sub(P4, r'^const CHUNG_ANTEN_4G = \[[^\]]*\]',
    "const CHUNG_ANTEN_4G = ['4G only', '3G4G', '2G3G4G', '4G5G', '3G4G5G']")

# 5G page: constant + table column + form field
sub(P5, r'^export default function Cells5GPage\(\) \{',
    lambda m: "const CHUNG_ANTEN_5G = ['5G only', '3G5G', '4G5G', '3G4G5G']\n\n" + m.group(0))
sub(P5, r"^([ ]*)\{ title: 'RF', dataIndex: 'rf', width: 100 \},",
    lambda m: m.group(1) + "{ title: 'Chung anten', dataIndex: 'chung_anten', width: 120 },\n" + m.group(0))
sub(P5, r'^([ ]*)<Col span=\{8\}><Form\.Item name="rf" label="RF"><Input /></Form\.Item></Col>',
    lambda m: (m.group(1) + '<Col span={8}><Form.Item name="chung_anten" label="Chung anten">\n'
               + m.group(1) + '  <Select allowClear>{CHUNG_ANTEN_5G.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}</Select>\n'
               + m.group(1) + '</Form.Item></Col>\n' + m.group(0)))

sub(TY, r'(export interface Cell5G extends CellBase \{\n)([ ]*gnodeb_id\?: string\n)',
    lambda m: m.group(1) + "  chung_anten?: string\n" + m.group(2))

# ═════════════════════════ write everything ══════════════════════════════════
for rel, text in files.items():
    with open(os.path.join(ROOT, rel), "w", encoding="utf-8") as fh:
        fh.write(text)
    print(f"  patched  {rel}")
print("All patches applied.")
PYEOF

# ----------------------------------------------------------------------------
# 7. Post-check: places still containing OLD "chung anten" values
# ----------------------------------------------------------------------------
echo
echo "---- Remaining occurrences of legacy chung-anten values (review manually) ----"
grep -rnE "(3G/4G/5G|2G/3G/4G|3G/5G|4G/5G|2G/4G|'3G/4G'|\"3G/4G\")" \
  "$ROOT/backend" "$ROOT/frontend/src" \
  --include=*.py --include=*.ts --include=*.tsx \
  --exclude=light_migrations.py --exclude-dir=node_modules --exclude-dir=__pycache__ \
  | grep -v "$BK" || echo "(none)"

cat <<EOF

DONE.
  1. Restart the backend. On startup it will: add cells_5g.chung_anten, widen mimo columns,
     remap legacy chung_anten values, and regenerate all 5 Excel templates.
  2. Rebuild / reload the frontend.
  3. Backup of originals: $BK
EOF