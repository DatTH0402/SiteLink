"""
create_templates.py
-------------------
Generates Excel template files for import.
Run once: python create_templates.py
"""
import os
import openpyxl
from openpyxl.styles import (
    PatternFill, Font, Alignment, Border, Side
)
from openpyxl.utils import get_column_letter

TEMPLATE_DIR = os.path.join(os.path.dirname(__file__), "templates")
os.makedirs(TEMPLATE_DIR, exist_ok=True)

HEADER_FILL   = PatternFill("solid", fgColor="1F4E79")
HEADER_FONT   = Font(color="FFFFFF", bold=True, size=11)
REQUIRED_FILL = PatternFill("solid", fgColor="FFE699")
REQUIRED_FONT = Font(color="7B3F00", bold=True, size=11)
NOTE_FILL     = PatternFill("solid", fgColor="E2EFDA")
NOTE_FONT     = Font(color="375623", italic=True, size=10)
CENTER        = Alignment(horizontal="center", vertical="center", wrap_text=True)
LEFT          = Alignment(horizontal="left",   vertical="center", wrap_text=True)
THIN          = Side(style="thin", color="BFBFBF")
BORDER        = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)


def style_header(ws, col_idx, value, required=False, width=20):
    cell = ws.cell(row=1, column=col_idx, value=value)
    cell.fill  = REQUIRED_FILL if required else HEADER_FILL
    cell.font  = REQUIRED_FONT if required else HEADER_FONT
    cell.alignment = CENTER
    cell.border    = BORDER
    ws.column_dimensions[get_column_letter(col_idx)].width = width


def add_note_row(ws, num_cols, note):
    ws.row_dimensions[2].height = 28
    cell = ws.cell(row=2, column=1, value=note)
    cell.fill      = NOTE_FILL
    cell.font      = NOTE_FONT
    cell.alignment = LEFT
    cell.border    = BORDER
    if num_cols > 1:
        ws.merge_cells(
            start_row=2, start_column=1,
            end_row=2,   end_column=num_cols
        )


def add_example_row(ws, row_idx, values):
    for col_idx, val in enumerate(values, start=1):
        cell = ws.cell(row=row_idx, column=col_idx, value=val)
        cell.alignment = LEFT
        cell.border    = BORDER


def finalize(ws, num_cols):
    ws.row_dimensions[1].height = 36
    ws.freeze_panes = "A3"
    ws.auto_filter.ref = (
        f"A1:{get_column_letter(num_cols)}1"
    )


# ── SITE template ─────────────────────────────────────────────────────────────
def create_site_template():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Sites"

    columns = [
        # (header, required, width)
        ("Mien",                         False, 10),
        ("Tinh",                         True,  22),
        ("Phuong xa",                    False, 22),
        ("Site name (cu)",               False, 22),
        ("Site name",                    True,  25),
        ("Site VIP",                     False, 12),
        ("Lat",                          False, 14),
        ("Long",                         False, 14),
        ("Tram 2G",                      False, 10),
        ("Tram 3G",                      False, 10),
        ("Tram 4G",                      False, 10),
        ("Tram 5G",                      False, 10),
        ("Repeater",                     False, 10),
        ("Booster",                      False, 10),
        ("Node truyen dan only",         False, 20),
        ("Tram phu song TSCA",           False, 18),
        ("Phan loai tram",               False, 22),
        ("MORAN 3G",                     False, 15),
        ("MORAN 4G",                     False, 15),
        ("MORAN 5G",                     False, 15),
        ("Ma PTM",                       False, 14),
        ("Do cao dinh cot anten",        False, 22),
        ("Do cao cot anten",             False, 20),
        ("Dia chi",                      False, 30),
        ("Ghi chu",                      False, 30),
    ]

    for i, (hdr, req, w) in enumerate(columns, start=1):
        style_header(ws, i, hdr, required=req, width=w)

    note = (
        "Ghi chu: Cot mau VANG la bat buoc. "
        "Tinh phai khop voi danh sach tinh trong he thong. "
        "Lat: 8.33-23.39, Long: 102.14-109.47 (Vietnam). "
        "Tram 2G/3G/4G/5G/Repeater/Booster: nhap 'x' neu co. "
        "MORAN: 'VNPT HOST' hoac 'MBF HOST'."
    )
    add_note_row(ws, len(columns), note)

    example = [
        "MB", "Ha Noi", "Phuong Trung Hoa", "HN-001-OLD",
        "HN-001", "VIP", 21.0285, 105.8542,
        "x", "x", "x", "x", "", "", "", "",
        "Macro outdoor", "MBF HOST", "MBF HOST", "",
        "PTM-001", 35.5, 30.0,
        "So 1, Duong ABC, Quan Cau Giay, Ha Noi", ""
    ]
    add_example_row(ws, 3, example)
    finalize(ws, len(columns))

    path = os.path.join(TEMPLATE_DIR, "template_site.xlsx")
    wb.save(path)
    print(f"  Created: {path}")


# ── CELL 3G template ──────────────────────────────────────────────────────────
def create_cell3g_template():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Cells_3G"

    columns = [
        ("Mien",          False, 10),
        ("Tinh",          False, 22),
        ("Phuong xa",     False, 22),
        ("Site Name",     True,  25),
        ("Cell Name",     True,  25),
        ("Cell VIP",      False, 12),
        ("MORAN",         False, 15),
        ("Lat",           False, 14),
        ("Long",          False, 14),
        ("Vung phu song", False, 15),
        ("Vendor",        False, 14),
        ("Do cao anten",  False, 15),
        ("Azimuth",       False, 12),
        ("M-tilt",        False, 10),
        ("E-Tilt",        False, 10),
        ("Total Tilt",    False, 12),
        ("Loai Anten",    False, 30),
        ("Chung anten",   False, 18),
        ("Baseband",      False, 18),
        ("RF",            False, 14),
        ("Cell ID",       False, 14),
        ("ARFCN",         False, 12),
        ("PSC",           False, 10),
        ("MIMO",          False, 10),
    ]

    for i, (hdr, req, w) in enumerate(columns, start=1):
        style_header(ws, i, hdr, required=req, width=w)

    note = (
        "Ghi chu: Cot mau VANG la bat buoc. "
        "Site Name phai ton tai hoac se duoc tu dong tao. "
        "Lat: 8.33-23.39, Long: 102.14-109.47. "
        "Azimuth: 0-359. Vendor: Ericsson/Nokia/Huawei/ZTE/Samsung. "
        "Vung phu song: Indoor/Outdoor. MIMO: 2x2/4x4/8x8."
    )
    add_note_row(ws, len(columns), note)

    example = [
        "MB", "Ha Noi", "Phuong Trung Hoa",
        "HN-001", "HN-001-3G-1", "", "MBF HOST",
        21.0285, 105.8542, "Outdoor", "Huawei",
        30.0, 45, 2.0, 0.0, 2.0,
        "Huawei ATR4518R10v06", "3G", "BBU3910", "RRU3908",
        "12345", "10562", "100", "2x2"
    ]
    add_example_row(ws, 3, example)
    finalize(ws, len(columns))

    path = os.path.join(TEMPLATE_DIR, "template_cell_3g.xlsx")
    wb.save(path)
    print(f"  Created: {path}")


# ── CELL 4G template ──────────────────────────────────────────────────────────
def create_cell4g_template():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Cells_4G"

    columns = [
        ("Mien",             False, 10),
        ("Tinh",             False, 22),
        ("Phuong xa",        False, 22),
        ("Site Name",        True,  25),
        ("Cell Name",        True,  25),
        ("Cell VIP",         False, 12),
        ("MORAN",            False, 15),
        ("Lat",              False, 14),
        ("Long",             False, 14),
        ("Vung phu song",    False, 15),
        ("Vendor",           False, 14),
        ("Do cao anten",     False, 15),
        ("Azimuth",          False, 12),
        ("M-tilt",           False, 10),
        ("E-Tilt",           False, 10),
        ("Total Tilt",       False, 12),
        ("Loai Anten",       False, 30),
        ("Chung anten",      False, 18),
        ("Baseband",         False, 18),
        ("RF",               False, 14),
        ("Cell ID",          False, 14),
        ("EARFCN",           False, 12),
        ("PCI",              False, 10),
        ("Root Sequence ID", False, 18),
        ("MIMO",             False, 10),
    ]

    for i, (hdr, req, w) in enumerate(columns, start=1):
        style_header(ws, i, hdr, required=req, width=w)

    note = (
        "Ghi chu: Cot mau VANG la bat buoc. "
        "Site Name phai ton tai hoac se duoc tu dong tao. "
        "Lat: 8.33-23.39, Long: 102.14-109.47. "
        "Azimuth: 0-359. Vendor: Ericsson/Nokia/Huawei/ZTE/Samsung. "
        "Vung phu song: Indoor/Outdoor. MIMO: 2x2/4x4/8x8."
    )
    add_note_row(ws, len(columns), note)

    example = [
        "MB", "Ha Noi", "Phuong Trung Hoa",
        "HN-001", "HN-001-4G-1", "", "MBF HOST",
        21.0285, 105.8542, "Outdoor", "Huawei",
        30.0, 45, 2.0, 0.0, 2.0,
        "Huawei ATR4518R10v06", "4G", "BBU5900", "RRU5258",
        "67890", "1825", "100", "0", "4x4"
    ]
    add_example_row(ws, 3, example)
    finalize(ws, len(columns))

    path = os.path.join(TEMPLATE_DIR, "template_cell_4g.xlsx")
    wb.save(path)
    print(f"  Created: {path}")


# ── CELL 5G template ──────────────────────────────────────────────────────────
def create_cell5g_template():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Cells_5G"

    columns = [
        ("Mien",             False, 10),
        ("Tinh",             False, 22),
        ("Phuong xa",        False, 22),
        ("Site Name",        True,  25),
        ("Cell Name",        True,  25),
        ("Cell VIP",         False, 12),
        ("MORAN",            False, 15),
        ("Lat",              False, 14),
        ("Long",             False, 14),
        ("Vung phu song",    False, 15),
        ("Vendor",           False, 14),
        ("Do cao anten",     False, 15),
        ("Azimuth",          False, 12),
        ("M-tilt",           False, 10),
        ("E-Tilt",           False, 10),
        ("Total Tilt",       False, 12),
        ("Loai Anten",       False, 30),
        ("Baseband",         False, 18),
        ("RF",               False, 14),
        ("Cell ID",          False, 14),
        ("NR-ARFCN",         False, 12),
        ("PCI",              False, 10),
        ("Root Sequence ID", False, 18),
        ("MIMO",             False, 10),
    ]

    for i, (hdr, req, w) in enumerate(columns, start=1):
        style_header(ws, i, hdr, required=req, width=w)

    note = (
        "Ghi chu: Cot mau VANG la bat buoc. "
        "Site Name phai ton tai hoac se duoc tu dong tao. "
        "Lat: 8.33-23.39, Long: 102.14-109.47. "
        "Azimuth: 0-359. Vendor: Ericsson/Nokia/Huawei/ZTE/Samsung. "
        "Vung phu song: Indoor/Outdoor. MIMO: 2x2/4x4/8x8."
    )
    add_note_row(ws, len(columns), note)

    example = [
        "MB", "Ha Noi", "Phuong Trung Hoa",
        "HN-001", "HN-001-5G-1", "", "MBF HOST",
        21.0285, 105.8542, "Outdoor", "Huawei",
        30.0, 45, 2.0, 0.0, 2.0,
        "Huawei AAU5614", "BBU5900", "AAU5614",
        "11111", "627264", "100", "0", "8x8"
    ]
    add_example_row(ws, 3, example)
    finalize(ws, len(columns))

    path = os.path.join(TEMPLATE_DIR, "template_cell_5g.xlsx")
    wb.save(path)
    print(f"  Created: {path}")


if __name__ == "__main__":
    create_site_template()
    create_cell3g_template()
    create_cell4g_template()
    create_cell5g_template()
    print("All templates created successfully.")
