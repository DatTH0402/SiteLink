"""
create_templates.py
-------------------
Generates Excel template files for import.
Run once: python create_templates.py

Features:
- Drop-down lists for enumerated columns (Cell VIP, MORAN, Vendor, etc.)
- Data validation for numeric columns (Lat, Long, Azimuth)
- No guide/note row – templates start with headers on row 1, data from row 2
- "CHƯA XÁC ĐỊNH" is listed first in Loai Anten if present
"""
import os
import openpyxl
from openpyxl.styles import PatternFill, Font, Alignment, Border, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation

TEMPLATE_DIR = os.path.join(os.path.dirname(__file__), "templates")
os.makedirs(TEMPLATE_DIR, exist_ok=True)

HEADER_FILL   = PatternFill("solid", fgColor="1F4E79")
HEADER_FONT   = Font(color="FFFFFF", bold=True, size=11)
REQUIRED_FILL = PatternFill("solid", fgColor="FFE699")
REQUIRED_FONT = Font(color="7B3F00", bold=True, size=11)
CENTER        = Alignment(horizontal="center", vertical="center", wrap_text=True)
LEFT          = Alignment(horizontal="left",   vertical="center", wrap_text=True)
THIN          = Side(style="thin", color="BFBFBF")
BORDER        = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)

# ── Validation constants ───────────────────────────────────────────────────────
VN_LAT_MIN, VN_LAT_MAX = 8.33,   23.39
VN_LON_MIN, VN_LON_MAX = 102.14, 109.47
AZI_MIN,    AZI_MAX    = 0,       359

# ── Drop-list values ───────────────────────────────────────────────────────────
MIEN_LIST        = ["MB", "MT", "MN"]
CELL_VIP_LIST    = ["VIP", "VVIP"]
MORAN_LIST       = ["VNPT HOST", "MBF HOST"]
VENDOR_LIST      = ["Ericsson", "Nokia", "Huawei", "ZTE", "Samsung"]
VUNG_PHU_SONG    = ["Indoor", "Outdoor"]
MIMO_LIST        = ["2x2", "4x4", "8x8"]
SITE_VIP_LIST    = ["VIP", "VVIP"]
PHAN_LOAI_LIST   = ["IBC", "Macro outdoor", "IBC + Outdoor", "Smallcell", "miniDAS"]
CHUNG_ANTEN_3G   = ["3G", "3G/4G", "2G/3G/4G", "3G/4G/5G", "3G/5G"]
CHUNG_ANTEN_4G   = ["4G", "2G/4G", "3G/4G", "2G/3G/4G", "4G/5G"]
BOOL_LIST        = ["x", ""]   # for checkbox-style columns


def _list_formula(values: list) -> str:
    """Build an Excel list formula from a Python list."""
    joined = ",".join(f'"{v}"' for v in values)
    return f'"{",".join(values)}"'


def _dv_list(ws, col_letter: str, values: list,
             start_row: int = 2, end_row: int = 1000,
             error_msg: str = "Vui lòng chọn từ danh sách"):
    """Add a dropdown DataValidation to a column."""
    joined = ",".join(values)
    dv = DataValidation(
        type="list",
        formula1=f'"{joined}"',
        allow_blank=True,
        showDropDown=False,  # False = show the arrow button
        showErrorMessage=True,
        errorTitle="Giá trị không hợp lệ",
        error=error_msg,
    )
    dv.sqref = f"{col_letter}{start_row}:{col_letter}{end_row}"
    ws.add_data_validation(dv)


def _dv_decimal(ws, col_letter: str,
                min_val: float, max_val: float,
                start_row: int = 2, end_row: int = 1000,
                error_msg: str = "Giá trị ngoài phạm vi"):
    """Add a decimal-range DataValidation to a column."""
    dv = DataValidation(
        type="decimal",
        operator="between",
        formula1=str(min_val),
        formula2=str(max_val),
        allow_blank=True,
        showErrorMessage=True,
        errorStyle="warning",   # warning = allow override; "stop" = block
        errorTitle="Giá trị ngoài phạm vi",
        error=error_msg,
    )
    dv.sqref = f"{col_letter}{start_row}:{col_letter}{end_row}"
    ws.add_data_validation(dv)


def _dv_whole(ws, col_letter: str,
              min_val: int, max_val: int,
              start_row: int = 2, end_row: int = 1000,
              error_msg: str = "Giá trị ngoài phạm vi"):
    dv = DataValidation(
        type="whole",
        operator="between",
        formula1=str(min_val),
        formula2=str(max_val),
        allow_blank=True,
        showErrorMessage=True,
        errorStyle="warning",
        errorTitle="Giá trị ngoài phạm vi",
        error=error_msg,
    )
    dv.sqref = f"{col_letter}{start_row}:{col_letter}{end_row}"
    ws.add_data_validation(dv)


def style_header(ws, col_idx, value, required=False, width=20):
    cell = ws.cell(row=1, column=col_idx, value=value)
    cell.fill      = REQUIRED_FILL if required else HEADER_FILL
    cell.font      = REQUIRED_FONT if required else HEADER_FONT
    cell.alignment = CENTER
    cell.border    = BORDER
    ws.column_dimensions[get_column_letter(col_idx)].width = width


def add_example_row(ws, row_idx, values):
    for col_idx, val in enumerate(values, start=1):
        cell = ws.cell(row=row_idx, column=col_idx, value=val)
        cell.alignment = LEFT
        cell.border    = BORDER


def finalize(ws, num_cols):
    ws.row_dimensions[1].height = 36
    ws.freeze_panes = f"A2"
    ws.auto_filter.ref = f"A1:{get_column_letter(num_cols)}1"


# ── SITE template ─────────────────────────────────────────────────────────────
def create_site_template():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Sites"

    columns = [
        # (header, required, width)
        ("Mien",                         False, 10),   # col 1  A
        ("Tinh",                         True,  22),   # col 2  B
        ("Phuong xa",                    False, 22),   # col 3  C
        ("Site name (cu)",               False, 22),   # col 4  D
        ("Site name",                    True,  25),   # col 5  E
        ("Site VIP",                     False, 12),   # col 6  F
        ("Lat",                          False, 14),   # col 7  G
        ("Long",                         False, 14),   # col 8  H
        ("Tram 2G",                      False, 10),   # col 9  I
        ("Tram 3G",                      False, 10),   # col 10 J
        ("Tram 4G",                      False, 10),   # col 11 K
        ("Tram 5G",                      False, 10),   # col 12 L
        ("Repeater",                     False, 10),   # col 13 M
        ("Booster",                      False, 10),   # col 14 N
        ("Node truyen dan only",         False, 20),   # col 15 O
        ("Tram phu song TSCA",           False, 18),   # col 16 P
        ("Phan loai tram",               False, 22),   # col 17 Q
        ("MORAN 3G",                     False, 15),   # col 18 R
        ("MORAN 4G",                     False, 15),   # col 19 S
        ("MORAN 5G",                     False, 15),   # col 20 T
        ("Ma PTM",                       False, 14),   # col 21 U
        ("Do cao dinh cot anten",        False, 22),   # col 22 V
        ("Do cao cot anten",             False, 20),   # col 23 W
        ("Dia chi",                      False, 30),   # col 24 X
        ("Ghi chu",                      False, 30),   # col 25 Y
    ]

    for i, (hdr, req, w) in enumerate(columns, start=1):
        style_header(ws, i, hdr, required=req, width=w)

    num_cols = len(columns)

    # ── Data validations ───────────────────────────────────────────────
    # Mien (col A=1)
    _dv_list(ws, "A", MIEN_LIST, error_msg="Chọn: MB, MT hoặc MN")
    # Site VIP (col F=6)
    _dv_list(ws, "F", SITE_VIP_LIST, error_msg="Chọn: VIP hoặc VVIP")
    # Lat (col G=7)
    _dv_decimal(ws, "G", VN_LAT_MIN, VN_LAT_MAX,
                error_msg=f"Latitude phải trong khoảng {VN_LAT_MIN}–{VN_LAT_MAX} (Việt Nam)")
    # Long (col H=8)
    _dv_decimal(ws, "H", VN_LON_MIN, VN_LON_MAX,
                error_msg=f"Longitude phải trong khoảng {VN_LON_MIN}–{VN_LON_MAX} (Việt Nam)")
    # Boolean columns: Tram 2G..TSCA (cols I-P = 9-16)
    for col_letter in ["I","J","K","L","M","N","O","P"]:
        _dv_list(ws, col_letter, BOOL_LIST, error_msg='Nhập "x" nếu có, để trống nếu không')
    # Phan loai tram (col Q=17)
    _dv_list(ws, "Q", PHAN_LOAI_LIST, error_msg="Chọn từ danh sách phân loại trạm")
    # MORAN 3G/4G/5G (cols R,S,T = 18,19,20)
    for col_letter in ["R","S","T"]:
        _dv_list(ws, col_letter, MORAN_LIST, error_msg="Chọn: VNPT HOST hoặc MBF HOST")

    # ── Example row (row 2) ────────────────────────────────────────────
    example = [
        "MB", "Ha Noi", "Phuong Trung Hoa", "HN-001-OLD",
        "HN-001", "VIP", 21.0285, 105.8542,
        "x", "x", "x", "x", "", "", "", "",
        "Macro outdoor", "MBF HOST", "MBF HOST", "",
        "PTM-001", 35.5, 30.0,
        "So 1, Duong ABC, Quan Cau Giay, Ha Noi", ""
    ]
    add_example_row(ws, 2, example)
    finalize(ws, num_cols)

    path = os.path.join(TEMPLATE_DIR, "template_site.xlsx")
    wb.save(path)
    print(f"  Created: {path}")


# ── CELL 3G template ──────────────────────────────────────────────────────────
def create_cell3g_template():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Cells_3G"

    columns = [
        ("Mien",           False, 10),   #  1 A
        ("Tinh",           False, 22),   #  2 B
        ("Phuong xa",      False, 22),   #  3 C
        ("Site Name Old",  False, 25),   #  4 D
        ("Cell Name Old",  False, 25),   #  5 E
        ("Site Name",      True,  25),   #  6 F
        ("Cell Name",      True,  25),   #  7 G
        ("Cell VIP",       False, 12),   #  8 H
        ("MORAN",          False, 15),   #  9 I
        ("Lat",            False, 14),   # 10 J
        ("Long",           False, 14),   # 11 K
        ("Vung phu song",  False, 15),   # 12 L
        ("Vendor",         False, 14),   # 13 M
        ("Do cao anten",   False, 15),   # 14 N
        ("Azimuth",        False, 12),   # 15 O
        ("M-tilt",         False, 10),   # 16 P
        ("E-Tilt",         False, 10),   # 17 Q
        ("Total Tilt",     False, 12),   # 18 R
        ("Loai Anten",     False, 30),   # 19 S
        ("Chung anten",    False, 18),   # 20 T
        ("Baseband",       False, 18),   # 21 U
        ("RF",             False, 14),   # 22 V
        ("Cell ID",        False, 14),   # 23 W
        ("ARFCN",          False, 12),   # 24 X
        ("PSC",            False, 10),   # 25 Y
        ("MIMO",           False, 10),   # 26 Z
    ]

    for i, (hdr, req, w) in enumerate(columns, start=1):
        style_header(ws, i, hdr, required=req, width=w)

    num_cols = len(columns)

    # ── Data validations ───────────────────────────────────────────────
    _dv_list(ws, "A", MIEN_LIST)
    # Cell VIP (H=8)
    _dv_list(ws, "H", CELL_VIP_LIST)
    # MORAN (I=9)
    _dv_list(ws, "I", MORAN_LIST, error_msg="Chọn: VNPT HOST hoặc MBF HOST")
    # Lat (J=10)
    _dv_decimal(ws, "J", VN_LAT_MIN, VN_LAT_MAX,
                error_msg=f"Latitude phải trong khoảng {VN_LAT_MIN}–{VN_LAT_MAX}")
    # Long (K=11)
    _dv_decimal(ws, "K", VN_LON_MIN, VN_LON_MAX,
                error_msg=f"Longitude phải trong khoảng {VN_LON_MIN}–{VN_LON_MAX}")
    # Vung phu song (L=12)
    _dv_list(ws, "L", VUNG_PHU_SONG)
    # Vendor (M=13)
    _dv_list(ws, "M", VENDOR_LIST)
    # Azimuth (O=15)
    _dv_whole(ws, "O", AZI_MIN, AZI_MAX,
              error_msg=f"Azimuth phải trong khoảng {AZI_MIN}–{AZI_MAX}")
    # Chung anten (T=20)
    _dv_list(ws, "T", CHUNG_ANTEN_3G,
             error_msg="Chọn: " + ", ".join(CHUNG_ANTEN_3G))
    # MIMO (Z=26)
    _dv_list(ws, "Z", MIMO_LIST)

    # ── Example row ────────────────────────────────────────────────────
    example = [
        "MB", "Ha Noi", "Phuong Trung Hoa",
        "HN-001-OLD", "HN-001-3G-1-OLD",
        "HN-001", "HN-001-3G-1",
        "", "MBF HOST",
        21.0285, 105.8542, "Outdoor", "Huawei",
        30.0, 45, 2.0, 0.0, 2.0,
        "Huawei ATR4518R10v06", "3G", "BBU3910", "RRU3908",
        "12345", "10562", "100", "2x2"
    ]
    add_example_row(ws, 2, example)
    finalize(ws, num_cols)

    path = os.path.join(TEMPLATE_DIR, "template_cell_3g.xlsx")
    wb.save(path)
    print(f"  Created: {path}")


# ── CELL 4G template ──────────────────────────────────────────────────────────
def create_cell4g_template():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Cells_4G"

    columns = [
        ("Mien",             False, 10),   #  1 A
        ("Tinh",             False, 22),   #  2 B
        ("Phuong xa",        False, 22),   #  3 C
        ("Site Name Old",    False, 25),   #  4 D
        ("Cell Name Old",    False, 25),   #  5 E
        ("Site Name",        True,  25),   #  6 F
        ("Cell Name",        True,  25),   #  7 G
        ("Cell VIP",         False, 12),   #  8 H
        ("MORAN",            False, 15),   #  9 I
        ("Lat",              False, 14),   # 10 J
        ("Long",             False, 14),   # 11 K
        ("Vung phu song",    False, 15),   # 12 L
        ("Vendor",           False, 14),   # 13 M
        ("Do cao anten",     False, 15),   # 14 N
        ("Azimuth",          False, 12),   # 15 O
        ("M-tilt",           False, 10),   # 16 P
        ("E-Tilt",           False, 10),   # 17 Q
        ("Total Tilt",       False, 12),   # 18 R
        ("Loai Anten",       False, 30),   # 19 S
        ("Chung anten",      False, 18),   # 20 T
        ("Baseband",         False, 18),   # 21 U
        ("RF",               False, 14),   # 22 V
        ("Cell ID",          False, 14),   # 23 W
        ("EARFCN",           False, 12),   # 24 X
        ("PCI",              False, 10),   # 25 Y
        ("Root Sequence ID", False, 18),   # 26 Z
        ("MIMO",             False, 10),   # 27 AA
    ]

    for i, (hdr, req, w) in enumerate(columns, start=1):
        style_header(ws, i, hdr, required=req, width=w)

    num_cols = len(columns)

    # ── Data validations ───────────────────────────────────────────────
    _dv_list(ws, "A", MIEN_LIST)
    _dv_list(ws, "H", CELL_VIP_LIST)
    _dv_list(ws, "I", MORAN_LIST, error_msg="Chọn: VNPT HOST hoặc MBF HOST")
    _dv_decimal(ws, "J", VN_LAT_MIN, VN_LAT_MAX,
                error_msg=f"Latitude phải trong khoảng {VN_LAT_MIN}–{VN_LAT_MAX}")
    _dv_decimal(ws, "K", VN_LON_MIN, VN_LON_MAX,
                error_msg=f"Longitude phải trong khoảng {VN_LON_MIN}–{VN_LON_MAX}")
    _dv_list(ws, "L", VUNG_PHU_SONG)
    _dv_list(ws, "M", VENDOR_LIST)
    _dv_whole(ws, "O", AZI_MIN, AZI_MAX,
              error_msg=f"Azimuth phải trong khoảng {AZI_MIN}–{AZI_MAX}")
    # Chung anten (T=20) – 4G list
    _dv_list(ws, "T", CHUNG_ANTEN_4G,
             error_msg="Chọn: " + ", ".join(CHUNG_ANTEN_4G))
    # MIMO (AA=27)
    _dv_list(ws, "AA", MIMO_LIST)

    # ── Example row ────────────────────────────────────────────────────
    example = [
        "MB", "Ha Noi", "Phuong Trung Hoa",
        "HN-001-OLD", "HN-001-4G-1-OLD",
        "HN-001", "HN-001-4G-1",
        "", "MBF HOST",
        21.0285, 105.8542, "Outdoor", "Huawei",
        30.0, 45, 2.0, 0.0, 2.0,
        "Huawei ATR4518R10v06", "4G", "BBU5900", "RRU5258",
        "67890", "1825", "100", "0", "4x4"
    ]
    add_example_row(ws, 2, example)
    finalize(ws, num_cols)

    path = os.path.join(TEMPLATE_DIR, "template_cell_4g.xlsx")
    wb.save(path)
    print(f"  Created: {path}")


# ── CELL 5G template ──────────────────────────────────────────────────────────
def create_cell5g_template():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Cells_5G"

    columns = [
        ("Mien",             False, 10),   #  1 A
        ("Tinh",             False, 22),   #  2 B
        ("Phuong xa",        False, 22),   #  3 C
        ("Site Name Old",    False, 25),   #  4 D
        ("Cell Name Old",    False, 25),   #  5 E
        ("Site Name",        True,  25),   #  6 F
        ("Cell Name",        True,  25),   #  7 G
        ("Cell VIP",         False, 12),   #  8 H
        ("MORAN",            False, 15),   #  9 I
        ("Lat",              False, 14),   # 10 J
        ("Long",             False, 14),   # 11 K
        ("Vung phu song",    False, 15),   # 12 L
        ("Vendor",           False, 14),   # 13 M
        ("Do cao anten",     False, 15),   # 14 N
        ("Azimuth",          False, 12),   # 15 O
        ("M-tilt",           False, 10),   # 16 P
        ("E-Tilt",           False, 10),   # 17 Q
        ("Total Tilt",       False, 12),   # 18 R
        ("Loai Anten",       False, 30),   # 19 S
        ("Baseband",         False, 18),   # 20 T
        ("RF",               False, 14),   # 21 U
        ("Cell ID",          False, 14),   # 22 V
        ("NR-ARFCN",         False, 12),   # 23 W
        ("PCI",              False, 10),   # 24 X
        ("Root Sequence ID", False, 18),   # 25 Y
        ("MIMO",             False, 10),   # 26 Z
    ]

    for i, (hdr, req, w) in enumerate(columns, start=1):
        style_header(ws, i, hdr, required=req, width=w)

    num_cols = len(columns)

    # ── Data validations ───────────────────────────────────────────────
    _dv_list(ws, "A", MIEN_LIST)
    _dv_list(ws, "H", CELL_VIP_LIST)
    _dv_list(ws, "I", MORAN_LIST, error_msg="Chọn: VNPT HOST hoặc MBF HOST")
    _dv_decimal(ws, "J", VN_LAT_MIN, VN_LAT_MAX,
                error_msg=f"Latitude phải trong khoảng {VN_LAT_MIN}–{VN_LAT_MAX}")
    _dv_decimal(ws, "K", VN_LON_MIN, VN_LON_MAX,
                error_msg=f"Longitude phải trong khoảng {VN_LON_MIN}–{VN_LON_MAX}")
    _dv_list(ws, "L", VUNG_PHU_SONG)
    _dv_list(ws, "M", VENDOR_LIST)
    _dv_whole(ws, "O", AZI_MIN, AZI_MAX,
              error_msg=f"Azimuth phải trong khoảng {AZI_MIN}–{AZI_MAX}")
    # MIMO (Z=26)
    _dv_list(ws, "Z", MIMO_LIST)
    # Note: 5G has no Chung anten column

    # ── Example row ────────────────────────────────────────────────────
    example = [
        "MB", "Ha Noi", "Phuong Trung Hoa",
        "HN-001-OLD", "HN-001-5G-1-OLD",
        "HN-001", "HN-001-5G-1",
        "", "MBF HOST",
        21.0285, 105.8542, "Outdoor", "Huawei",
        30.0, 45, 2.0, 0.0, 2.0,
        "Huawei AAU5614", "BBU5900", "AAU5614",
        "11111", "627264", "100", "0", "8x8"
    ]
    add_example_row(ws, 2, example)
    finalize(ws, num_cols)

    path = os.path.join(TEMPLATE_DIR, "template_cell_5g.xlsx")
    wb.save(path)
    print(f"  Created: {path}")


if __name__ == "__main__":
    create_site_template()
    create_cell3g_template()
    create_cell4g_template()
    create_cell5g_template()
    print("All templates created successfully.")
