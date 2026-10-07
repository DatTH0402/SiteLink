"""
create_templates.py
-------------------
Generates Excel import templates for SiteLink with:
  - Drop-down lists for all categorical/lookup columns
  - Data validation for numeric fields (lat, long, azimuth, etc.)
  - Province/ward/RNC/antenna data fetched from the PostgreSQL database
  - Formatted headers matching the import parser column names
  - No note row (row 2) in data sheets – notes moved to "Hướng dẫn" sheet
  - "Hướng dẫn" sheet is the SECOND sheet (after the data sheet)
  - Required columns highlighted in yellow for Sites and Cells

Usage:
    python create_templates.py
    # → writes template_site.xlsx, template_cell_3g.xlsx,
    #           template_cell_4g.xlsx, template_cell_5g.xlsx,
    #           template_antenna.xlsx  into ./templates/

Requirements:
    pip install openpyxl psycopg2-binary python-dotenv
"""

from __future__ import annotations

import os
import sys
from typing import Any, Dict, List, Optional, Sequence, Tuple

# ── optional .env loading ─────────────────────────────────────────────────────
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

import openpyxl
from openpyxl import Workbook
from openpyxl.styles import (
    PatternFill, Font, Alignment, Border, Side,
)
from openpyxl.utils import get_column_letter, quote_sheetname
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.worksheet.worksheet import Worksheet

# ══════════════════════════════════════════════════════════════════════════════
# 1.  DATABASE HELPERS
# ══════════════════════════════════════════════════════════════════════════════

# ── DB connection ─────────────────────────────────────────────────────────────
# Priority:
#   1. DATABASE_URL env var (set by template_regen.py from backend settings)
#   2. Individual POSTGRES_* env vars (standard Docker .env names)
#   3. Legacy DB_* env vars
#   4. Hardcoded defaults (last resort, only for standalone manual runs)

def _build_db_params() -> dict:
    """Build psycopg2 connection params from available env vars."""
    import urllib.parse

    # 1. Full DATABASE_URL (highest priority – injected by template_regen.py)
    db_url = os.getenv("DATABASE_URL", "")
    if db_url:
        try:
            p = urllib.parse.urlparse(db_url)
            return {
                "host":     p.hostname or "localhost",
                "port":     str(p.port  or 5432),
                "dbname":   (p.path or "/sitelink_db").lstrip("/"),
                "user":     p.username or "sitelink",
                "password": p.password or "sitelink_pass",
            }
        except Exception:
            pass  # fall through to individual vars

    # 2. Standard Docker env var names (POSTGRES_*)
    # 3. Legacy names (DB_*) as fallback
    return {
        "host":     os.getenv("POSTGRES_HOST",     os.getenv("DB_HOST",     "localhost")),
        "port":     os.getenv("POSTGRES_PORT",     os.getenv("DB_PORT",     "5432")),
        "dbname":   os.getenv("POSTGRES_DB",       os.getenv("DB_NAME",     "sitelink_db")),
        "user":     os.getenv("POSTGRES_USER",     os.getenv("DB_USER",     "sitelink")),
        "password": os.getenv("POSTGRES_PASSWORD", os.getenv("DB_PASSWORD", "sitelink_pass")),
    }


DB_PARAMS = _build_db_params()

_DB_AVAILABLE = False
_db_conn      = None


def _get_conn():
    global _db_conn, _DB_AVAILABLE, DB_PARAMS

    # Re-read params every call so env var injection by template_regen works
    # even if the module was already loaded (importlib caches the module object
    # but we can still refresh the connection params here).
    DB_PARAMS = _build_db_params()

    if _db_conn is not None:
        # Test if existing connection is still alive
        try:
            _db_conn.cursor().execute("SELECT 1")
            return _db_conn
        except Exception:
            _db_conn = None

    try:
        import psycopg2
        _db_conn      = psycopg2.connect(**DB_PARAMS)
        _DB_AVAILABLE = True
        print(
            f"[DB] Connected to PostgreSQL at "
            f"{DB_PARAMS['host']}:{DB_PARAMS['port']}/"
            f"{DB_PARAMS['dbname']} successfully."
        )
        return _db_conn
    except Exception as exc:
        print(
            f"[DB] Cannot connect to PostgreSQL "
            f"({DB_PARAMS['host']}:{DB_PARAMS['port']}/"
            f"{DB_PARAMS['dbname']}): {exc}"
        )
        print("[DB] Templates will use static fallback values.")
        _DB_AVAILABLE = False
        return None


def _query(sql: str, params=None) -> List[tuple]:
    conn = _get_conn()
    if conn is None:
        return []
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params or ())
            return cur.fetchall()
    except Exception as exc:
        print(f"[DB] Query error: {exc}")
        try:
            conn.rollback()
        except Exception:
            pass
        return []


# ── Lookup loaders ────────────────────────────────────────────────────────────

def load_tinh_list() -> List[str]:
    rows = _query(
        "SELECT DISTINCT ten_tinh FROM dropdown_tinh_xa_phuong "
        "WHERE ten_tinh IS NOT NULL ORDER BY ten_tinh"
    )
    result = [r[0] for r in rows if r[0]]
    if not result:
        result = [
            "An Giang", "Bà Rịa - Vũng Tàu", "Bắc Giang", "Bắc Kạn",
            "Bạc Liêu", "Bắc Ninh", "Bến Tre", "Bình Định", "Bình Dương",
            "Bình Phước", "Bình Thuận", "Cà Mau", "Cần Thơ", "Cao Bằng",
            "Đà Nẵng", "Đắk Lắk", "Đắk Nông", "Điện Biên", "Đồng Nai",
            "Đồng Tháp", "Gia Lai", "Hà Giang", "Hà Nam", "Hà Nội",
            "Hà Tĩnh", "Hải Dương", "Hải Phòng", "Hậu Giang", "Hòa Bình",
            "Hưng Yên", "Khánh Hòa", "Kiên Giang", "Kon Tum", "Lai Châu",
            "Lâm Đồng", "Lạng Sơn", "Lào Cai", "Long An", "Nam Định",
            "Nghệ An", "Ninh Bình", "Ninh Thuận", "Phú Thọ", "Phú Yên",
            "Quảng Bình", "Quảng Nam", "Quảng Ngãi", "Quảng Ninh",
            "Quảng Trị", "Sóc Trăng", "Sơn La", "Tây Ninh", "Thái Bình",
            "Thái Nguyên", "Thanh Hóa", "Thừa Thiên Huế", "Tiền Giang",
            "TP. Hồ Chí Minh", "Trà Vinh", "Tuyên Quang", "Vĩnh Long",
            "Vĩnh Phúc", "Yên Bái",
        ]
    return result


def load_all_phuong_xa() -> List[str]:
    rows = _query(
        "SELECT DISTINCT ten_phuong_xa FROM dropdown_tinh_xa_phuong "
        "WHERE ten_phuong_xa IS NOT NULL ORDER BY ten_phuong_xa LIMIT 5000"
    )
    result = [r[0] for r in rows if r[0]]
    if not result:
        result = ["Phường 1", "Phường 2", "Xã An Lạc", "Xã Bình Hưng"]
    return result


def load_rnc_names() -> Dict[str, List[str]]:
    rows = _query("SELECT vendor, name FROM rnc_names ORDER BY vendor, name")
    result: Dict[str, List[str]] = {}
    for vendor, name in rows:
        result.setdefault(vendor, []).append(name)
    if not result:
        result = {
            "Ericsson": [
                "RHNCG1E","RHNCG2E","RHNCG3E","RHNCG4E","RHNHM1E","RHNHM2E",
                "RHNHM3E","RQNHL1E","RQNHL2E","RSG103E","RSG011E","RSG072E",
                "RSG091E","RSG092E","RSG093E","RSG094E","RSG095E","RSG097E",
                "RSG104E","RSG105E","RSGBC2E","RSGBI2E","RSGBT2E","RSGHM1E",
                "RSGTB2E",
            ],
            "Huawei": [
                "iHNCG1H","iHNCG3H","iHNHM1H","iHNHM2H","iHNHM3H","iHNHM5H",
                "iHNHM6H","iHNHM7H","iHNHM8H","RHNCG1H","RHNCG3H","RHNCG4H",
                "RHNHM3H","RHNHM4H","RHNHM5H","RHNHM6H","RHNHM7H","RHNHM8H",
                "RDNG01H","RDNG02H","RQBDH1H","RCTCR11H","RCTCR12H",
            ],
            "Nokia": [
                "RDNCL3N","RDNCL4N","RDNCL5N","RDNCL7N","RDNCL8N","RDNCL9N",
                "RDNST10N","RDNST12N","RDNST13N","RDNST14N","RDNST15N",
                "RDNST7N","RCTCR1N","RCTCR2N","RCTCR8N","RDNBH5N","RSG091N",
                "RSG092N","RSG093N","RSG094N","RSG095N","RSG097N","RSG098N",
                "RSG099N","RSG105N","RTGMT3N",
            ],
            "ZTE": ["RCTCR3Z","RCTCR4Z","RCTCR5Z","RCTCR6Z"],
        }
    return result


def load_antenna_names() -> List[str]:
    rows = _query("SELECT name FROM antennas ORDER BY name LIMIT 2000")
    result = [r[0] for r in rows if r[0]]
    if not result:
        result = ["CHƯA XÁC ĐỊNH", "Antenna_A", "Antenna_B"]
    return result


def load_phan_loai_tram() -> List[str]:
    rows = _query(
        "SELECT value FROM dropdown_general "
        "WHERE category = 'phan_loai_tram' ORDER BY value"
    )
    result = [r[0] for r in rows if r[0]]
    if not result:
        result = ["IBC", "Macro outdoor", "IBC + Outdoor", "Smallcell", "miniDAS"]
    return result


# ══════════════════════════════════════════════════════════════════════════════
# 2.  STYLING CONSTANTS
# ══════════════════════════════════════════════════════════════════════════════

HDR_FILL  = PatternFill("solid", fgColor="1F4E79")   # dark blue  – header
HDR_FONT  = Font(color="FFFFFF", bold=True, size=10)

REQ_FILL  = PatternFill("solid", fgColor="FFF2CC")   # yellow     – required
OPT_FILL  = PatternFill("solid", fgColor="DDEEFF")   # light blue – optional
ALT_FILL  = PatternFill("solid", fgColor="F7FBFF")   # very light – alternating

THIN  = Side(style="thin",   color="B0B0B0")
THICK = Side(style="medium", color="1F4E79")
BORDER_CELL = Border(left=THIN,  right=THIN,  top=THIN,  bottom=THIN)
BORDER_HDR  = Border(left=THICK, right=THICK, top=THICK, bottom=THICK)

CENTER = Alignment(horizontal="center", vertical="center", wrap_text=True)
LEFT   = Alignment(horizontal="left",   vertical="center", wrap_text=True)

LOOKUP_SHEET = "_Lookups"   # hidden sheet for long dropdown lists

# Data rows: start immediately after the single header row
FIRST_DATA = 2
LAST_DATA  = 1001


# ══════════════════════════════════════════════════════════════════════════════
# 3.  LOW-LEVEL HELPERS
# ══════════════════════════════════════════════════════════════════════════════

def _style_header_row(ws: Worksheet, n_cols: int, row: int = 1) -> None:
    ws.row_dimensions[row].height = 36
    for col in range(1, n_cols + 1):
        cell = ws.cell(row=row, column=col)
        cell.fill      = HDR_FILL
        cell.font      = HDR_FONT
        cell.alignment = CENTER
        cell.border    = BORDER_HDR


def _style_data_rows(
    ws: Worksheet,
    n_cols: int,
    start_row: int = FIRST_DATA,
    end_row:   int = LAST_DATA,
    required_cols: Optional[set] = None,
) -> None:
    required_cols = required_cols or set()
    for row in range(start_row, end_row + 1):
        alt = (row % 2 == 0)
        for col in range(1, n_cols + 1):
            cell = ws.cell(row=row, column=col)
            if col in required_cols:
                cell.fill = REQ_FILL
            elif alt:
                cell.fill = ALT_FILL
            cell.alignment = LEFT
            cell.border    = BORDER_CELL


def _set_col_width(ws: Worksheet, col: int, width: float) -> None:
    ws.column_dimensions[get_column_letter(col)].width = width


def _freeze(ws: Worksheet, cell: str = "A2") -> None:
    ws.freeze_panes = cell


def _add_autofilter(ws: Worksheet, n_cols: int) -> None:
    ws.auto_filter.ref = f"A1:{get_column_letter(n_cols)}1"


# ── Lookup-sheet helpers ──────────────────────────────────────────────────────

def _ensure_lookup_sheet(wb: Workbook) -> Worksheet:
    if LOOKUP_SHEET in wb.sheetnames:
        return wb[LOOKUP_SHEET]
    ws = wb.create_sheet(LOOKUP_SHEET)
    ws.sheet_state = "hidden"
    return ws


def _write_lookup_col(wb: Workbook, col_idx: int,
                      values: List[str], header: str) -> str:
    ws  = _ensure_lookup_sheet(wb)
    col = get_column_letter(col_idx)
    ws.cell(row=1, column=col_idx, value=header).font = Font(bold=True)
    for i, v in enumerate(values, start=2):
        ws.cell(row=i, column=col_idx, value=v)
    end_row = len(values) + 1
    return f"{quote_sheetname(LOOKUP_SHEET)}!${col}$2:${col}${end_row}"


def _dv_list_formula(formula: str) -> DataValidation:
    return DataValidation(
        type="list",
        formula1=formula,
        allow_blank=True,
        showDropDown=False,
        showErrorMessage=True,
        errorTitle="Giá trị không hợp lệ",
        error="Vui lòng chọn từ danh sách",
    )


def _dv_list_inline(values: Sequence[str]) -> DataValidation:
    formula = '"' + ",".join(str(v) for v in values) + '"'
    return DataValidation(
        type="list",
        formula1=formula,
        allow_blank=True,
        showDropDown=False,
        showErrorMessage=True,
        errorTitle="Giá trị không hợp lệ",
        error="Vui lòng chọn từ danh sách",
    )


def _dv_decimal(min_val: float, max_val: float,
                title: str = "Giá trị không hợp lệ",
                error: str = "") -> DataValidation:
    return DataValidation(
        type="decimal",
        operator="between",
        formula1=str(min_val),
        formula2=str(max_val),
        allow_blank=True,
        showErrorMessage=True,
        errorTitle=title,
        error=error or f"Phải trong khoảng {min_val} – {max_val}",
    )


def _dv_whole(min_val: int, max_val: int,
              title: str = "Giá trị không hợp lệ",
              error: str = "") -> DataValidation:
    return DataValidation(
        type="whole",
        operator="between",
        formula1=str(min_val),
        formula2=str(max_val),
        allow_blank=True,
        showErrorMessage=True,
        errorTitle=title,
        error=error or f"Phải là số nguyên trong khoảng {min_val} – {max_val}",
    )


def _apply_dv(ws: Worksheet, dv: DataValidation,
              col: int,
              first_row: int = FIRST_DATA,
              last_row:  int = LAST_DATA) -> None:
    col_letter = get_column_letter(col)
    dv.sqref   = f"{col_letter}{first_row}:{col_letter}{last_row}"
    ws.add_data_validation(dv)


def _col_map(columns: List[Tuple]) -> Dict[str, int]:
    """Return {header_name: 1-based_col_index}."""
    return {col[0]: idx + 1 for idx, col in enumerate(columns)}


# ══════════════════════════════════════════════════════════════════════════════
# 4.  LOOKUP DATA  (loaded once, shared across all templates)
# ══════════════════════════════════════════════════════════════════════════════

print("Loading lookup data from database …")
TINH_LIST     = load_tinh_list()
ALL_PHUONG_XA = load_all_phuong_xa()
RNC_GROUPED   = load_rnc_names()
ALL_RNC       = sorted({n for names in RNC_GROUPED.values() for n in names})
ANTENNA_NAMES = load_antenna_names()
PHAN_LOAI     = load_phan_loai_tram()

MIEN_LIST     = ["MB", "MT", "MN"]
VENDOR_LIST   = ["Ericsson", "Nokia", "Huawei", "ZTE", "Samsung"]
MORAN_LIST    = ["VNPT HOST", "MBF HOST"]
MIMO_LIST     = ["2x2", "4x4", "8x8"]
VUNG_LIST     = ["Indoor", "Outdoor"]
CELL_VIP_LIST = ["VIP", "VVIP"]
SITE_VIP_LIST = ["VIP", "VVIP"]
BOOL_LIST     = ["x", ""]
CHUNG_3G      = ["3G", "3G/4G", "2G/3G/4G", "3G/4G/5G", "3G/5G"]
CHUNG_4G      = ["4G", "2G/4G", "3G/4G", "2G/3G/4G", "4G/5G"]
MU_MIMO_LIST  = ["Yes", "No"]

VN_LAT_MIN, VN_LAT_MAX = 8.33,   23.39
VN_LON_MIN, VN_LON_MAX = 102.14, 109.47
AZI_MIN,    AZI_MAX    = 0,      359

# Allow the calling process (template_regen.py) to override the output dir
# via environment variable, so templates always land in the right place
# regardless of whether we are running inside Docker or locally.
OUTPUT_DIR = (
    os.environ.get("SITELINK_TEMPLATE_DIR")
    or os.path.join(os.path.dirname(os.path.abspath(__file__)), "backend", "templates")
)
os.makedirs(OUTPUT_DIR, exist_ok=True)


# ══════════════════════════════════════════════════════════════════════════════
# 5.  LEGEND / GUIDE SHEET
#     Added as the SECOND sheet (index 1), after the data sheet.
# ══════════════════════════════════════════════════════════════════════════════

def _add_legend_sheet(
    wb: Workbook,
    tech: str = "",
    column_notes: Optional[List[Tuple[str, str, bool]]] = None,
) -> None:
    """
    Insert a "Hướng dẫn" sheet as the second sheet (after the data sheet).

    column_notes: list of (column_name, note_text, is_required)
                  describing each column's purpose and whether it is required.
    """
    ws = wb.create_sheet("Hướng dẫn")
    # Move to position 1 (0-based), i.e. second sheet
    wb.move_sheet("Hướng dẫn", offset=-(len(wb.sheetnames) - 2))

    ws.column_dimensions["A"].width = 40
    ws.column_dimensions["B"].width = 60
    ws.column_dimensions["C"].width = 16

    title_font  = Font(bold=True, size=13, color="1F4E79")
    sect_font   = Font(bold=True, size=10, color="FFFFFF")
    sect_fill   = PatternFill("solid", fgColor="1F4E79")
    req_font    = Font(bold=True, size=9,  color="7B3F00")
    opt_font    = Font(size=9, color="333333")
    mono_font   = Font(size=9, color="333333", name="Courier New")

    row = 1

    # ── Title ─────────────────────────────────────────────────────────────────
    ws.merge_cells(f"A{row}:C{row}")
    title_cell = ws.cell(row=row, column=1,
                         value="HƯỚNG DẪN SỬ DỤNG FILE TEMPLATE SITELINK")
    title_cell.font      = title_font
    title_cell.alignment = CENTER
    title_cell.fill      = PatternFill("solid", fgColor="D9E1F2")
    ws.row_dimensions[row].height = 30
    row += 1

    ws.cell(row=row, column=1, value=f"Công nghệ: {tech or 'Site / Cell / Antenna'}")
    ws.cell(row=row, column=1).font = Font(italic=True, size=9, color="555555")
    row += 2

    def _section(title: str) -> None:
        nonlocal row
        ws.merge_cells(f"A{row}:C{row}")
        c = ws.cell(row=row, column=1, value=title)
        c.font      = sect_font
        c.fill      = sect_fill
        c.alignment = LEFT
        ws.row_dimensions[row].height = 20
        row += 1

    def _row(col_a: str, col_b: str = "", col_c: str = "",
             font_a=None, font_b=None, fill_a=None) -> None:
        nonlocal row
        ca = ws.cell(row=row, column=1, value=col_a)
        cb = ws.cell(row=row, column=2, value=col_b)
        cc = ws.cell(row=row, column=3, value=col_c)
        ca.alignment = LEFT
        cb.alignment = LEFT
        cc.alignment = CENTER
        if font_a:
            ca.font = font_a
        if font_b:
            cb.font = font_b
        if fill_a:
            ca.fill = fill_a
        for c in (ca, cb, cc):
            c.border = BORDER_CELL
        row += 1

    # ── Section: Color legend ─────────────────────────────────────────────────
    _section("MÀU SẮC CỘT")
    _row("Màu sắc", "Ý nghĩa", "")
    ws.cell(row=row - 1, column=1).font = Font(bold=True, size=9)
    ws.cell(row=row - 1, column=2).font = Font(bold=True, size=9)

    _row("Nền VÀNG",
         "Cột BẮT BUỘC – phải có dữ liệu, không được để trống",
         "Bắt buộc",
         fill_a=REQ_FILL,
         font_a=req_font)
    _row("Nền TRẮNG / XEN KẼ XANH NHẠT",
         "Cột tùy chọn – có thể để trống",
         "Tùy chọn",
         fill_a=ALT_FILL)
    row += 1

    # ── Section: Data entry rules ─────────────────────────────────────────────
    _section("QUY TẮC NHẬP LIỆU")
    rules = [
        ("Dòng 1 (Header)",
         "Tên cột – KHÔNG sửa, KHÔNG xóa, KHÔNG đổi thứ tự"),
        ("Dòng 2 trở đi",
         "Điền dữ liệu bắt đầu từ dòng 2"),
        ("Cột có drop-down ▼",
         "Chỉ chọn từ danh sách – KHÔNG tự nhập tự do"),
        ("Cột boolean (x / để trống)",
         "Nhập chữ x (thường) để bật, để trống để tắt"),
        ("Lat / Long",
         f"Latitude: {VN_LAT_MIN} – {VN_LAT_MAX}  |  Longitude: {VN_LON_MIN} – {VN_LON_MAX}"),
        ("Azimuth",
         f"Phải trong khoảng {AZI_MIN} – {AZI_MAX} độ"),
        ("M-tilt / E-Tilt",
         "Thường trong khoảng -30 đến 30 độ"),
        ("Độ cao anten / cột anten",
         "Số dương, đơn vị mét (m)"),
    ]
    for col_a, col_b in rules:
        _row(col_a, col_b, font_a=Font(bold=True, size=9))
    row += 1

    # ── Section: Import rules ─────────────────────────────────────────────────
    _section("QUY TẮC IMPORT")
    import_rules = [
        ("Cột CÓ trong file + ô TRỐNG",
         "→ Xóa / làm rỗng dữ liệu trường đó trong database"),
        ("Cột KHÔNG CÓ trong file",
         "→ Giữ nguyên dữ liệu hiện tại trong database (không thay đổi)"),
        ("Dòng thiếu trường bắt buộc",
         "→ Dòng đó bị BỎ QUA hoàn toàn, hiển thị lỗi chi tiết"),
        ("Giá trị dropdown không hợp lệ",
         "→ Dòng bị từ chối, yêu cầu liên hệ quản trị viên"),
        ("Toạ độ ngoài lãnh thổ VN",
         "→ Dòng bị từ chối, kiểm tra lại Lat / Long"),
        ("Site name đã tồn tại",
         "→ Cập nhật bản ghi hiện có (UPDATE)"),
        ("Site name chưa tồn tại",
         "→ Tạo mới bản ghi (INSERT)"),
    ]
    for col_a, col_b in import_rules:
        _row(col_a, col_b, font_a=Font(bold=True, size=9))
    row += 1

    # ── Section: Column descriptions ──────────────────────────────────────────
    if column_notes:
        _section("MÔ TẢ CÁC CỘT")

        # Table header
        hdr_row = row
        for col_idx, label in enumerate(
            ("Tên cột", "Mô tả / Hướng dẫn", "Bắt buộc"), start=1
        ):
            c = ws.cell(row=hdr_row, column=col_idx, value=label)
            c.font      = Font(bold=True, size=9, color="FFFFFF")
            c.fill      = PatternFill("solid", fgColor="2E75B6")
            c.alignment = CENTER
            c.border    = BORDER_CELL
        row += 1

        for col_name, note, is_req in column_notes:
            ca = ws.cell(row=row, column=1, value=col_name)
            cb = ws.cell(row=row, column=2, value=note)
            cc = ws.cell(row=row, column=3, value="✔ Bắt buộc" if is_req else "Tùy chọn")

            ca.font      = Font(bold=is_req, size=9,
                                color="7B3F00" if is_req else "333333")
            ca.fill      = REQ_FILL if is_req else ALT_FILL
            cb.font      = Font(size=9)
            cc.font      = Font(bold=is_req, size=9,
                                color="C00000" if is_req else "555555")
            cc.alignment = CENTER

            for c in (ca, cb, cc):
                c.alignment = LEFT if c.column < 3 else CENTER
                c.border    = BORDER_CELL
            row += 1


# ══════════════════════════════════════════════════════════════════════════════
# 6.  TEMPLATE: SITE
# ══════════════════════════════════════════════════════════════════════════════

# Required site column names (must match the column headers exactly)
SITE_REQUIRED = {
    "Site name",
    "Lat",
    "Long",
    "Dia chi",
    "Do cao dinh cot anten",
}

def create_site_template() -> None:
    # (header, note_for_guide, width, is_required)
    columns: List[Tuple[str, str, float, bool]] = [
        ("Mien",                  "Miền: MB / MT / MN",                                        8,  False),
        ("Tinh",                  "Tỉnh / Thành phố – chọn từ danh sách",                     28,  False),
        ("Phuong xa",             "Phường / Xã – chọn từ danh sách",                          28,  False),
        ("Site name (cu)",        "Tên site cũ – điền khi đổi tên site",                      24,  False),
        ("Site name",             "Tên site hiện tại – bắt buộc, phải là duy nhất",           28,  True),
        ("Site VIP",              "Mức độ VIP: VIP hoặc VVIP – để trống nếu không phải",      12,  False),
        ("Ma PTM",                "Mã PTM của trạm",                                           16,  False),
        ("Lat",                   f"Latitude (vĩ độ) – phải trong {VN_LAT_MIN}–{VN_LAT_MAX}", 14,  True),
        ("Long",                  f"Longitude (kinh độ) – phải trong {VN_LON_MIN}–{VN_LON_MAX}", 14, True),
        ("Tram 2G",               "x = có trạm 2G, để trống = không",                         10,  False),
        ("Tram 3G",               "x = có trạm 3G, để trống = không",                         10,  False),
        ("Tram 4G",               "x = có trạm 4G, để trống = không",                         10,  False),
        ("Tram 5G",               "x = có trạm 5G, để trống = không",                         10,  False),
        ("Repeater",              "x = có Repeater, để trống = không",                         10,  False),
        ("Booster",               "x = có Booster, để trống = không",                         10,  False),
        ("Node truyen dan only",  "x = Node truyền dẫn only, để trống = không",               20,  False),
        ("Tram phu song TSCA",    "x = Trạm phủ sóng TSCA, để trống = không",                 18,  False),
        ("Phan loai tram",        "Phân loại trạm – chọn từ danh sách",                        22,  False),
        ("MORAN 3G",              "MORAN 3G: VNPT HOST hoặc MBF HOST",                        18,  False),
        ("MORAN 4G",              "MORAN 4G: VNPT HOST hoặc MBF HOST",                        18,  False),
        ("MORAN 5G",              "MORAN 5G: VNPT HOST hoặc MBF HOST",                        18,  False),
        ("Do cao dinh cot anten", "Độ cao đỉnh cột anten tới mặt đất – bắt buộc (số hoặc chuỗi, vd: 35 hoặc IBC)", 22, True),
        ("Do cao cot anten",      "Độ cao cột anten – đỉnh đến chân cột (số hoặc chuỗi, vd: 30 hoặc IBC)", 20, False),
        ("Dia chi",               "Địa chỉ chi tiết của trạm – bắt buộc",                     30,  True),
        ("Ghi chu",               "Ghi chú thêm",                                              30,  False),
    ]

    wb  = Workbook()
    ws  = wb.active
    ws.title = "Sites"

    n_cols      = len(columns)
    # Required column indices (1-based) – used for yellow fill
    req_idx_set = {idx + 1 for idx, (h, _, _, req) in enumerate(columns) if req}

    # ── Header row only (no note row) ─────────────────────────────────────────
    for idx, (hdr, _note, width, _req) in enumerate(columns, start=1):
        ws.cell(row=1, column=idx, value=hdr)
        _set_col_width(ws, idx, width)

    _style_header_row(ws, n_cols, row=1)
    _style_data_rows(ws, n_cols, FIRST_DATA, LAST_DATA, req_idx_set)
    _freeze(ws, "A2")
    _add_autofilter(ws, n_cols)

    cm = _col_map(columns)

    # ── Lookup sheet ──────────────────────────────────────────────────────────
    lk_tinh     = _write_lookup_col(wb, 1, TINH_LIST,     "Tinh")
    lk_xa       = _write_lookup_col(wb, 2, ALL_PHUONG_XA, "PhuongXa")
    lk_phanloai = _write_lookup_col(wb, 3, PHAN_LOAI,     "PhanLoai")

    # ── Data validations ──────────────────────────────────────────────────────
    _apply_dv(ws, _dv_list_inline(MIEN_LIST),      cm["Mien"])
    _apply_dv(ws, _dv_list_formula(lk_tinh),        cm["Tinh"])
    _apply_dv(ws, _dv_list_formula(lk_xa),          cm["Phuong xa"])
    _apply_dv(ws, _dv_list_inline(SITE_VIP_LIST),   cm["Site VIP"])

    _apply_dv(ws, _dv_decimal(VN_LAT_MIN, VN_LAT_MAX,
                               "Latitude không hợp lệ",
                               f"Latitude phải trong khoảng {VN_LAT_MIN}–{VN_LAT_MAX}"),
              cm["Lat"])
    _apply_dv(ws, _dv_decimal(VN_LON_MIN, VN_LON_MAX,
                               "Longitude không hợp lệ",
                               f"Longitude phải trong khoảng {VN_LON_MIN}–{VN_LON_MAX}"),
              cm["Long"])

    for col_name in [
        "Tram 2G", "Tram 3G", "Tram 4G", "Tram 5G",
        "Repeater", "Booster", "Node truyen dan only", "Tram phu song TSCA",
    ]:
        _apply_dv(ws, _dv_list_inline(BOOL_LIST), cm[col_name])

    _apply_dv(ws, _dv_list_formula(lk_phanloai), cm["Phan loai tram"])

    for col_name in ["MORAN 3G", "MORAN 4G", "MORAN 5G"]:
        _apply_dv(ws, _dv_list_inline(MORAN_LIST), cm[col_name])

    # do_cao_dinh_cot_anten / do_cao_cot_anten are now free-text strings
    # (accept numeric values like "35" or special values like "IBC")
    # No data validation applied – any non-empty string is valid.

    # ── Sample row ────────────────────────────────────────────────────────────
    sample = {
        "Mien":                  "MB",
        "Tinh":                  TINH_LIST[0] if TINH_LIST else "Hà Nội",
        "Site name":             "HNI_XXXX_001",
        "Ma PTM":                "PTM001",
        "Lat":                   21.0285,
        "Long":                  105.8542,
        "Tram 4G":               "x",
        "Phan loai tram":        PHAN_LOAI[0] if PHAN_LOAI else "Macro outdoor",
        "Do cao dinh cot anten": 35,
        "Dia chi":               "Số 1, Đường ABC, Phường XYZ, Hà Nội",
    }
    for col_name, val in sample.items():
        if col_name in cm:
            ws.cell(row=FIRST_DATA, column=cm[col_name], value=val)

    # ── Guide sheet (second sheet) ────────────────────────────────────────────
    column_notes = [(h, note, req) for h, note, _w, req in columns]
    _add_legend_sheet(wb, "Site", column_notes)

    # ── Ensure _Lookups is last and hidden ────────────────────────────────────
    _finalize_sheets(wb)

    path = os.path.join(OUTPUT_DIR, "template_site.xlsx")
    wb.save(path)
    print(f"  ✓  {path}")


# ══════════════════════════════════════════════════════════════════════════════
# 7.  SHARED CELL COLUMN BUILDER
# ══════════════════════════════════════════════════════════════════════════════

# Required cell column names (must match headers exactly)
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

# (header, note_for_guide, width, is_required)
_COMMON_CELL_COLS: List[Tuple[str, str, float, bool]] = [
    ("Mien",           "Miền: MB / MT / MN",                                           8,  False),
    ("Tinh",           "Tỉnh / Thành phố – chọn từ danh sách",                        28,  False),
    ("Phuong xa",      "Phường / Xã – chọn từ danh sách",                             28,  False),
    ("Site Name",      "Tên site – bắt buộc, phải khớp với site đã có",               28,  True),
    ("Site Name Old",  "Tên site cũ – điền khi site vừa đổi tên",                     24,  False),
    ("Cell Name",      "Tên cell – bắt buộc, duy nhất trong site",                    28,  True),
    ("Cell Name Old",  "Tên cell cũ – điền khi cell vừa đổi tên",                     24,  False),
    ("Cell VIP",       "Mức độ VIP: VIP hoặc VVIP",                                   10,  False),
    ("MORAN",          "MORAN: VNPT HOST hoặc MBF HOST",                               18,  False),
    ("Lat",            f"Latitude – phải trong {VN_LAT_MIN}–{VN_LAT_MAX}",            14,  True),
    ("Long",           f"Longitude – phải trong {VN_LON_MIN}–{VN_LON_MAX}",           14,  True),
    ("Vung phu song",  "Vùng phủ sóng: Indoor hoặc Outdoor",                          14,  False),
    ("Vendor",         "Hãng thiết bị – bắt buộc, chọn từ danh sách",                 14,  True),
    ("Do cao anten",   "Độ cao anten – bắt buộc (số hoặc chuỗi, vd: 28 hoặc IBC)",    16,  True),
    ("Azimuth",        "Góc phương vị – bắt buộc (số hoặc chuỗi, vd: 120 hoặc IBC)", 12,  True),
    ("M-tilt",         "Mechanical tilt – bắt buộc (số hoặc chuỗi, vd: 2 hoặc IBC)", 10,  True),
    ("E-Tilt",         "Electrical tilt – bắt buộc (số hoặc chuỗi, vd: 4 hoặc IBC)", 10,  True),
    ("Total Tilt",     "Tổng tilt (số hoặc chuỗi, tự tính hoặc để trống)",            12,  False),
    ("Loai Anten",     "Loại anten – chọn từ danh sách antenna",                       35,  False),
    ("Baseband",       "Tên thiết bị baseband",                                         18,  False),
    ("RF",             "Tên thiết bị RF",                                              16,  False),
    ("Cell ID",        "Cell ID (chuỗi hoặc số)",                                      14,  False),
    ("MIMO",           "Cấu hình MIMO: 2x2 / 4x4 / 8x8",                              10,  False),
    ("Cell max power (dBm)", "Công suất tối đa cell (dBm)",                            20,  False),
    ("BBUname",        "Tên BBU",                                                       16,  False),
    ("Cell status (at dump time)", "Trạng thái cell tại thời điểm dump",               26,  False),
]


def _apply_common_cell_validations(
    wb: Workbook,
    ws: Worksheet,
    cm: Dict[str, int],
    lookup_col_offset: int = 1,
) -> int:
    """Apply all common cell validations. Returns next free lookup col index."""
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

    # do_cao_anten, azimuth, m_tilt, e_tilt, total_tilt are now free-text strings
    # (accept numeric values like "35" or special values like "IBC")
    # No numeric data validation applied for these columns.

    lk_ant = _write_lookup_col(wb, lc, ANTENNA_NAMES, "LoaiAnten"); lc += 1
    _apply_dv(ws, _dv_list_formula(lk_ant), cm["Loai Anten"])

    _apply_dv(ws, _dv_list_inline(MIMO_LIST), cm["MIMO"])

    return lc


def _build_cell_wb(
    sheet_title: str,
    extra_cols: List[Tuple[str, str, float, bool]],
) -> Tuple[Workbook, Worksheet, Dict[str, int]]:
    """Create workbook with common + extra columns, no note row."""
    columns  = _COMMON_CELL_COLS + extra_cols
    req_idx  = {idx + 1 for idx, (h, _, _, req) in enumerate(columns) if req}

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

    cm = _col_map(columns)
    return wb, ws, cm


# ══════════════════════════════════════════════════════════════════════════════
# 8.  TEMPLATE: CELL 3G
# ══════════════════════════════════════════════════════════════════════════════

def create_cell3g_template() -> None:
    extra_cols: List[Tuple[str, str, float, bool]] = [
        ("Chung anten",       "Chung anten 3G: 3G / 3G/4G / 2G/3G/4G / 3G/4G/5G / 3G/5G", 20, False),
        ("RNC Name",          "Tên RNC – chọn từ danh sách theo Vendor",                    18, False),
        ("ARFCN",             "Absolute Radio Frequency Channel Number",                     12, False),
        ("UARFCN",            "UMTS ARFCN",                                                  12, False),
        ("LAC",               "Location Area Code",                                          12, False),
        ("RAC",               "Routing Area Code",                                           12, False),
        ("PSC",               "Primary Scrambling Code",                                     12, False),
        ("URAId",             "URA ID",                                                      10, False),
        ("CPICH power (dBm)", "CPICH power (dBm)",                                          18, False),
    ]

    wb, ws, cm = _build_cell_wb("Cell_3G", extra_cols)
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
        "MIMO": "2x2", "Chung anten": "3G",
    }
    for k, v in sample.items():
        if k in cm:
            ws.cell(row=FIRST_DATA, column=cm[k], value=v)

    all_cols = _COMMON_CELL_COLS + extra_cols
    column_notes = [(h, note, req) for h, note, _w, req in all_cols]
    _add_legend_sheet(wb, "Cell 3G", column_notes)
    _finalize_sheets(wb)

    path = os.path.join(OUTPUT_DIR, "template_cell_3g.xlsx")
    wb.save(path)
    print(f"  ✓  {path}")


# ══════════════════════════════════════════════════════════════════════════════
# 9.  TEMPLATE: CELL 4G
# ══════════════════════════════════════════════════════════════════════════════

def create_cell4g_template() -> None:
    extra_cols: List[Tuple[str, str, float, bool]] = [
        ("Chung anten",      "Chung anten 4G: 4G / 2G/4G / 3G/4G / 2G/3G/4G / 4G/5G",  20, False),
        ("EnodeB ID",        "eNodeB ID",                                                  16, False),
        ("EARFCN",           "E-UTRA Absolute Radio Frequency Channel Number",             14, False),
        ("TAC",              "Tracking Area Code",                                          12, False),
        ("PCI",              "Physical Cell Identity 0–503",                                12, False),
        ("Root Sequence ID", "Root Sequence Index",                                         18, False),
        ("Bandwitdh",        "Bandwidth (MHz) – ví dụ: 5, 10, 15, 20",                    16, False),
        ("ECI",              "E-UTRAN Cell Identifier",                                    16, False),
    ]

    wb, ws, cm = _build_cell_wb("Cell_4G", extra_cols)
    next_lc    = _apply_common_cell_validations(wb, ws, cm, lookup_col_offset=1)

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
        "MIMO": "4x4", "Chung anten": "4G", "PCI": 100,
    }
    for k, v in sample.items():
        if k in cm:
            ws.cell(row=FIRST_DATA, column=cm[k], value=v)

    all_cols = _COMMON_CELL_COLS + extra_cols
    column_notes = [(h, note, req) for h, note, _w, req in all_cols]
    _add_legend_sheet(wb, "Cell 4G", column_notes)
    _finalize_sheets(wb)

    path = os.path.join(OUTPUT_DIR, "template_cell_4g.xlsx")
    wb.save(path)
    print(f"  ✓  {path}")


# ══════════════════════════════════════════════════════════════════════════════
# 10. TEMPLATE: CELL 5G
# ══════════════════════════════════════════════════════════════════════════════

def create_cell5g_template() -> None:
    extra_cols: List[Tuple[str, str, float, bool]] = [
        ("gNodeB ID",        "gNodeB ID",                                       16, False),
        ("TAC",              "Tracking Area Code",                               12, False),
        ("PCI",              "Physical Cell Identity 0–1007 (NR)",               12, False),
        ("Root Sequence ID", "Root Sequence Index",                              18, False),
        ("SSB-ARFCN",        "SSB Absolute Radio Frequency Channel Number",      14, False),
        ("Center-ARFCN",     "Center Frequency ARFCN",                           16, False),
        ("GSCN",             "Global Synchronization Channel Number",            14, False),
        ("Bandwidth (MHz)",  "Bandwidth (MHz) – ví dụ: 50, 100, 200",           16, False),
        ("NCI",              "NR Cell Identity",                                 16, False),
        ("MU-MIMO",          "Multi-User MIMO: Yes hoặc No",                    12, False),
    ]

    wb, ws, cm = _build_cell_wb("Cell_5G", extra_cols)
    next_lc    = _apply_common_cell_validations(wb, ws, cm, lookup_col_offset=1)

    _apply_dv(ws, _dv_whole(0, 1007, "PCI không hợp lệ",
                             "NR PCI phải trong khoảng 0 – 1007"),
              cm["PCI"])
    _apply_dv(ws, _dv_list_inline(MU_MIMO_LIST), cm["MU-MIMO"])
    _apply_dv(ws, _dv_decimal(-30, 60,
                               "Cell max power không hợp lệ",
                               "Cell max power thường trong khoảng -30 đến 60 dBm"),
              cm["Cell max power (dBm)"])

    sample = {
        "Mien": "MT", "Tinh": TINH_LIST[10] if len(TINH_LIST) > 10 else "Đà Nẵng",
        "Site Name": "DNG_XXXX_001", "Cell Name": "DNG_XXXX_001_C1_5G",
        "Vendor": "Nokia", "Lat": 16.0544, "Long": 108.2022,
        "Azimuth": 240, "Do cao anten": 32, "M-tilt": 1, "E-Tilt": 3,
        "MIMO": "8x8", "MU-MIMO": "Yes", "PCI": 200,
    }
    for k, v in sample.items():
        if k in cm:
            ws.cell(row=FIRST_DATA, column=cm[k], value=v)

    all_cols = _COMMON_CELL_COLS + extra_cols
    column_notes = [(h, note, req) for h, note, _w, req in all_cols]
    _add_legend_sheet(wb, "Cell 5G", column_notes)
    _finalize_sheets(wb)

    path = os.path.join(OUTPUT_DIR, "template_cell_5g.xlsx")
    wb.save(path)
    print(f"  ✓  {path}")


# ══════════════════════════════════════════════════════════════════════════════
# 11. TEMPLATE: ANTENNA
# ══════════════════════════════════════════════════════════════════════════════

def create_antenna_template() -> None:
    # (header, note, width, is_required)
    columns: List[Tuple[str, str, float, bool]] = [
        ("Name",           "Tên antenna – bắt buộc, phải là duy nhất trong hệ thống",  35, True),
        ("Band",           "Băng tần – ví dụ: 900, 1800, 900-1800-2100",              22, False),
        ("5G_AAU",         "x = là 5G AAU, để trống = không phải AAU",                10, False),
        ("No_of_ports",    "Số cổng (số nguyên dương, ví dụ: 4)",                     14, False),
        ("No_of_beam",     "Số beam (số nguyên dương, ví dụ: 1)",                     14, False),
        ("Horizontal BW",  "Horizontal beamwidth – ví dụ: 65°",                       16, False),
        ("Vertical BW",    "Vertical beamwidth – ví dụ: 7°",                          14, False),
        ("Gain",           "Gain (dBi) – ví dụ: 17.5",                                12, False),
        ("Etilt",          "Dải electrical tilt – ví dụ: 0-10",                       14, False),
        ("H",              "Chiều cao antenna (mm)",                                   10, False),
        ("W",              "Chiều rộng antenna (mm)",                                  10, False),
        ("D",              "Chiều sâu / dày antenna (mm)",                             10, False),
        ("Weight",         "Trọng lượng (kg)",                                         10, False),
        ("Connector type", "Loại đầu nối – ví dụ: 4.3-10, 7/16 DIN",                18, False),
        ("Ghi chú",        "Ghi chú thêm về antenna",                                 30, False),
    ]

    wb  = Workbook()
    ws  = wb.active
    ws.title = "Antennas"

    n_cols      = len(columns)
    req_idx_set = {idx + 1 for idx, (h, _, _, req) in enumerate(columns) if req}

    for idx, (hdr, _note, width, _req) in enumerate(columns, start=1):
        ws.cell(row=1, column=idx, value=hdr)
        _set_col_width(ws, idx, width)

    _style_header_row(ws, n_cols, row=1)
    _style_data_rows(ws, n_cols, FIRST_DATA, LAST_DATA, req_idx_set)
    _freeze(ws, "A2")
    _add_autofilter(ws, n_cols)

    cm = _col_map(columns)

    # Validations
    _apply_dv(ws, _dv_list_inline(BOOL_LIST), cm["5G_AAU"])
    _apply_dv(ws, _dv_whole(1, 32, "Số cổng không hợp lệ",
                             "Phải là số nguyên 1 – 32"),
              cm["No_of_ports"])
    _apply_dv(ws, _dv_whole(1, 64, "Số beam không hợp lệ",
                             "Phải là số nguyên 1 – 64"),
              cm["No_of_beam"])

    common_bands = [
        "700", "850", "900", "1800", "2100", "2600", "3500",
        "900-1800", "900-2100", "1800-2100",
        "700-1800-2100", "900-1800-2100",
        "700-1800-2100-2600", "3500-26000",
    ]
    _apply_dv(ws, _dv_list_inline(common_bands), cm["Band"])

    connector_types = ["4.3-10", "7/16 DIN", "N-Type", "SMA", "TNC", "EIA 7/8\""]
    _apply_dv(ws, _dv_list_inline(connector_types), cm["Connector type"])

    # Sample
    sample = {
        "Name": "HUAWEI_AAU5613-1", "Band": "2100", "5G_AAU": "",
        "No_of_ports": 4, "No_of_beam": 1,
        "Horizontal BW": "65°", "Vertical BW": "7°",
        "Gain": "17.5", "Etilt": "0-10",
        "H": "1340", "W": "385", "D": "177", "Weight": "17",
        "Connector type": "4.3-10",
    }
    for k, v in sample.items():
        if k in cm:
            ws.cell(row=FIRST_DATA, column=cm[k], value=v)

    column_notes = [(h, note, req) for h, note, _w, req in columns]
    _add_legend_sheet(wb, "Antenna", column_notes)
    _finalize_sheets(wb)

    path = os.path.join(OUTPUT_DIR, "template_antenna.xlsx")
    wb.save(path)
    print(f"  ✓  {path}")


# ══════════════════════════════════════════════════════════════════════════════
# 12. SHEET ORDER FINALIZER
# ══════════════════════════════════════════════════════════════════════════════

def _finalize_sheets(wb: Workbook) -> None:
    """
    Ensure final sheet order:
      [0] Data sheet  (Sites / Cell_3G / etc.)
      [1] Hướng dẫn
      [2] _Lookups    (hidden)
    """
    # Make sure _Lookups is last and hidden
    if LOOKUP_SHEET in wb.sheetnames:
        # Move to absolute last position
        sheets = wb.sheetnames
        current_pos = sheets.index(LOOKUP_SHEET)
        offset = len(sheets) - 1 - current_pos
        if offset != 0:
            wb.move_sheet(LOOKUP_SHEET, offset=offset)
        wb[LOOKUP_SHEET].sheet_state = "hidden"

    # Ensure "Hướng dẫn" is at position 1 (second)
    if "Hướng dẫn" in wb.sheetnames:
        sheets = wb.sheetnames
        current_pos = sheets.index("Hướng dẫn")
        target_pos  = 1
        offset      = target_pos - current_pos
        if offset != 0:
            wb.move_sheet("Hướng dẫn", offset=offset)

    # Activate the first (data) sheet so it opens by default
    wb.active = wb.worksheets[0]


# ══════════════════════════════════════════════════════════════════════════════
# 13. MAIN
# ══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    print(f"\n{'='*60}")
    print("  SiteLink – Excel Template Generator")
    print(f"{'='*60}\n")
    print(f"Output directory: {OUTPUT_DIR}\n")

    print("Generating template_site.xlsx …")
    create_site_template()

    print("Generating template_cell_3g.xlsx …")
    create_cell3g_template()

    print("Generating template_cell_4g.xlsx …")
    create_cell4g_template()

    print("Generating template_cell_5g.xlsx …")
    create_cell5g_template()

    print("Generating template_antenna.xlsx …")
    create_antenna_template()

    print(f"\n{'='*60}")
    print("  All templates generated successfully!")
    print(f"{'='*60}\n")

    if not _DB_AVAILABLE:
        print("⚠️  WARNING: Database was not available.")
        print("   Province/ward/RNC/antenna lists used static fallback values.")
        print("   For production data, set correct DB credentials in .env\n")