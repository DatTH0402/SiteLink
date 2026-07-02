#!/bin/bash
# update_features.sh
# Implements:
#   1. Excel template download (in DryRunModal + dedicated buttons)
#   2. Data validation (Lat/Long Vietnam bounds, Azimuth 0-359)
#   3. Audit log: add full_name + email columns
#
# Usage: chmod +x update_features.sh && ./update_features.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo "SiteLink Feature Update Script"
echo "========================================"

# ── Step 1: Create template directory and placeholder files ───────────────────
echo "[1/10] Creating Excel template directory..."

mkdir -p backend/templates

# Create Python script to generate real Excel templates
cat > backend/create_templates.py << 'PYEOF'
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
PYEOF

echo "    ✓ Template generator script created"

# ── Step 2: Add template download route to backend ────────────────────────────
echo "[2/10] Adding template download API route..."

cat > backend/app/api/routes/templates.py << 'PYEOF'
"""
templates.py
------------
Serves Excel template files for download.
Templates are stored in backend/templates/
"""
import os
from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from app.utils.deps import get_current_user
from fastapi import Depends

router = APIRouter()

TEMPLATE_DIR = os.path.join(
    os.path.dirname(__file__),   # .../app/api/routes/
    "..", "..", "..",             # .../backend/
    "templates"
)
TEMPLATE_DIR = os.path.abspath(TEMPLATE_DIR)

TEMPLATES = {
    "site":    "template_site.xlsx",
    "cell-3g": "template_cell_3g.xlsx",
    "cell-4g": "template_cell_4g.xlsx",
    "cell-5g": "template_cell_5g.xlsx",
}

DISPLAY_NAMES = {
    "site":    "Template_Site.xlsx",
    "cell-3g": "Template_Cell_3G.xlsx",
    "cell-4g": "Template_Cell_4G.xlsx",
    "cell-5g": "Template_Cell_5G.xlsx",
}


@router.get("/{template_name}")
def download_template(
    template_name: str,
    _=Depends(get_current_user),
):
    """
    Download an Excel import template.
    template_name: site | cell-3g | cell-4g | cell-5g
    """
    if template_name not in TEMPLATES:
        raise HTTPException(
            status_code=404,
            detail=f"Template '{template_name}' not found. "
                   f"Available: {list(TEMPLATES.keys())}"
        )

    file_path = os.path.join(TEMPLATE_DIR, TEMPLATES[template_name])

    if not os.path.exists(file_path):
        raise HTTPException(
            status_code=404,
            detail=f"Template file not found on server. "
                   f"Please contact administrator."
        )

    return FileResponse(
        path=file_path,
        filename=DISPLAY_NAMES[template_name],
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    )
PYEOF

echo "    ✓ templates.py route created"

# ── Step 3: Register template route in main.py ────────────────────────────────
echo "[3/10] Registering template route in main.py..."

cat > backend/app/main.py << 'PYEOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.db.session import engine, SessionLocal
from app.db import base  # noqa – registers all models
from app.db.base import Base
from app.api.routes import (
    auth, users, sites, cells_3g, cells_4g, cells_5g,
    dropdowns, report, audit,
)
from app.api.routes import antenna as antenna_router
from app.api.routes import templates as templates_router

Base.metadata.create_all(bind=engine)


def _seed_initial_data():
    db = SessionLocal()
    try:
        from app.models.user import User, UserRole
        from app.core.security import get_password_hash
        from app.models.dropdown import DropdownGeneral, DropdownVendor

        if not db.query(User).filter(User.username == "admin").first():
            db.add(User(
                email="admin@sitelink.com",
                username="admin",
                full_name="Administrator",
                hashed_password=get_password_hash("admin"),
                role=UserRole.admin,
            ))
            db.commit()

        def seed_cat(cat, values):
            if db.query(DropdownGeneral).filter(
                    DropdownGeneral.category == cat).count() == 0:
                for v in values:
                    db.add(DropdownGeneral(category=cat, value=v, label=v))
                db.commit()

        seed_cat("moran",          ["VNPT HOST", "MBF HOST"])
        seed_cat("phan_loai_tram", ["IBC", "Macro outdoor", "IBC + Outdoor",
                                     "Smallcell", "miniDAS"])
        seed_cat("mien",           ["MB", "MT", "MN"])
        seed_cat("vung_phu_song",  ["Indoor", "Outdoor"])
        seed_cat("mimo",           ["2x2", "4x4", "8x8"])
        seed_cat("site_vip",       ["VIP", "VVIP"])
        seed_cat("csht", [
            "VNPT", "MOBIFONE", "XA HOI HOA", "VIETTEL",
            "LIEN KET", "HA TANG CO SAN", "GTEL", "IBC", "VIETNAMMOBILE",
        ])

        if db.query(DropdownVendor).count() == 0:
            for row in [
                ("Alcatel",  "Alcatel",  "Nokia",    "Nokia"),
                ("Nokia",    "Nokia",    "Ericsson", "Ericsson"),
                ("Ericsson", "Ericsson", "Huawei",   "Huawei"),
                ("Huawei",   "Huawei",   "ZTE",      "ZTE"),
                ("ZTE",      "ZTE",      "Samsung",  "Samsung"),
            ]:
                db.add(DropdownVendor(
                    vendor_2g=row[0], vendor_3g=row[1],
                    vendor_4g=row[2], vendor_5g=row[3],
                ))
            db.commit()
    finally:
        db.close()


def _generate_templates():
    """Generate Excel templates on startup if they don't exist."""
    import os, sys
    template_dir = os.path.join(
        os.path.dirname(__file__), "..", "templates"
    )
    template_dir = os.path.abspath(template_dir)
    os.makedirs(template_dir, exist_ok=True)

    required = [
        "template_site.xlsx",
        "template_cell_3g.xlsx",
        "template_cell_4g.xlsx",
        "template_cell_5g.xlsx",
    ]
    missing = [f for f in required
               if not os.path.exists(os.path.join(template_dir, f))]

    if missing:
        try:
            script = os.path.join(
                os.path.dirname(__file__), "..", "create_templates.py"
            )
            if os.path.exists(script):
                import importlib.util
                spec = importlib.util.spec_from_file_location(
                    "create_templates", script
                )
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
                mod.create_site_template()
                mod.create_cell3g_template()
                mod.create_cell4g_template()
                mod.create_cell5g_template()
                print("[startup] Excel templates generated.")
        except Exception as exc:
            print(f"[startup] Warning: could not generate templates: {exc}")


app = FastAPI(
    title="SiteLink API",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def on_startup():
    _seed_initial_data()
    _generate_templates()


PREFIX = "/api/v1"
app.include_router(auth.router,             prefix=f"{PREFIX}/auth",       tags=["Auth"])
app.include_router(users.router,            prefix=f"{PREFIX}/users",      tags=["Users"])
app.include_router(sites.router,            prefix=f"{PREFIX}/sites",      tags=["Sites"])
app.include_router(cells_3g.router,         prefix=f"{PREFIX}/cells-3g",   tags=["Cells-3G"])
app.include_router(cells_4g.router,         prefix=f"{PREFIX}/cells-4g",   tags=["Cells-4G"])
app.include_router(cells_5g.router,         prefix=f"{PREFIX}/cells-5g",   tags=["Cells-5G"])
app.include_router(dropdowns.router,        prefix=f"{PREFIX}/dropdowns",  tags=["Dropdowns"])
app.include_router(report.router,           prefix=f"{PREFIX}/report",     tags=["Report"])
app.include_router(audit.router,            prefix=f"{PREFIX}/audit",      tags=["Audit"])
app.include_router(antenna_router.router,   prefix=f"{PREFIX}/antennas",   tags=["Antennas"])
app.include_router(templates_router.router, prefix=f"{PREFIX}/templates",  tags=["Templates"])


@app.get("/health")
def health():
    return {"status": "ok"}
PYEOF

echo "    ✓ main.py updated"

# ── Step 4: Update audit route to include full_name and email ─────────────────
echo "[4/10] Updating audit route..."

cat > backend/app/api/routes/audit.py << 'PYEOF'
from typing import Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.audit_log import AuditLog
from app.models.user import User
from app.utils.deps import require_admin

router = APIRouter()


@router.get("/")
def list_audit_logs(
    skip: int = 0,
    limit: int = 100,
    table_name: Optional[str] = Query(None),
    action:     Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    q = (
        db.query(AuditLog, User.full_name, User.email)
        .outerjoin(User, AuditLog.user_id == User.id)
        .order_by(AuditLog.timestamp.desc())
    )
    if table_name:
        q = q.filter(AuditLog.table_name == table_name)
    if action:
        q = q.filter(AuditLog.action == action)

    rows = q.offset(skip).limit(limit).all()

    return [
        {
            "id":         log.id,
            "username":   log.username,
            "full_name":  full_name or "",
            "email":      email or "",
            "action":     log.action,
            "table_name": log.table_name,
            "record_id":  log.record_id,
            "old_value":  log.old_value,
            "new_value":  log.new_value,
            "timestamp":  log.timestamp.isoformat() if log.timestamp else None,
        }
        for log, full_name, email in rows
    ]
PYEOF

echo "    ✓ audit.py updated"

# ── Step 5: Update import_excel.py with validation ───────────────────────────
echo "[5/10] Updating import_excel.py with validation..."

cat > backend/app/services/import_excel.py << 'PYEOF'
"""
import_excel.py
==============
Handles Excel → DB record conversion for Sites, Cell3G, Cell4G, Cell5G.

Validation rules:
  - Lat: 8.33 ≤ lat ≤ 23.39  (Vietnam bounding box)
  - Long: 102.14 ≤ long ≤ 109.47
  - Azimuth: 0 ≤ azimuth ≤ 359
"""

from __future__ import annotations

import io
import re
import unicodedata
from typing import Any, Dict, List, Optional, Tuple

import pandas as pd

# ── Vietnam bounding box ──────────────────────────────────────────────────────
VN_LAT_MIN, VN_LAT_MAX   =  8.33,  23.39
VN_LON_MIN, VN_LON_MAX   = 102.14, 109.47
AZI_MIN,    AZI_MAX       = 0,      359


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _strip_accents(text: str) -> str:
    _CHAR_MAP = str.maketrans({"Đ": "D", "đ": "d"})
    text = text.translate(_CHAR_MAP)
    nfkd = unicodedata.normalize("NFKD", text)
    return "".join(c for c in nfkd if not unicodedata.combining(c))


_PREFIX_RE = re.compile(
    r"^(tp\.?|thanh\s+pho|thi\s+tran|thi\s+xa|phuong|huyen|tinh|quan|xa)\s+",
    re.IGNORECASE,
)


def _normalize(text: str) -> str:
    t = _strip_accents(text).lower().strip()
    t = _PREFIX_RE.sub("", t)
    t = re.sub(r"[\s\-_\.]+", "", t)
    return t


# ─────────────────────────────────────────────────────────────────────────────
# Geo cache
# ─────────────────────────────────────────────────────────────────────────────

class GeoCache:
    def __init__(self, db) -> None:
        from app.models.dropdown import DropdownTinhXaPhuong
        rows = db.query(DropdownTinhXaPhuong).all()

        self.tinh_map:  Dict[str, str] = {}
        self.xa_map:    Dict[Tuple[str, str], str] = {}
        self.tinh_mien: Dict[str, str] = {}

        for r in rows:
            if r.ten_tinh:
                k_tinh = _normalize(r.ten_tinh)
                self.tinh_map[k_tinh]      = r.ten_tinh
                self.tinh_mien[r.ten_tinh] = r.mien or ""
            if r.ten_tinh and r.ten_phuong_xa:
                k_tinh = _normalize(r.ten_tinh)
                k_xa   = _normalize(r.ten_phuong_xa)
                self.xa_map[(k_tinh, k_xa)] = r.ten_phuong_xa

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


# ─────────────────────────────────────────────────────────────────────────────
# Low-level readers
# ─────────────────────────────────────────────────────────────────────────────

def _read_excel(file_bytes: bytes) -> pd.DataFrame:
    df = pd.read_excel(io.BytesIO(file_bytes), dtype=str)
    df = df.where(pd.notna(df), None)
    df.columns = [str(c).strip() for c in df.columns]
    return df


def _v(row, *keys) -> Optional[str]:
    for key in keys:
        val = row.get(key)
        if val is not None and str(val).strip() not in ("", "nan", "None"):
            return str(val).strip()
    return None


def _bool(row, *keys) -> bool:
    v = _v(row, *keys)
    if v is None:
        return False
    return str(v).strip().lower() in ("x", "true", "yes", "1", "co", "có")


def _float(row, *keys) -> Optional[float]:
    v = _v(row, *keys)
    if v is None:
        return None
    try:
        return float(v)
    except (ValueError, TypeError):
        return None


# ─────────────────────────────────────────────────────────────────────────────
# Validation helpers
# ─────────────────────────────────────────────────────────────────────────────

def _validate_lat(
    lat: Optional[float],
    row_num: int,
    label: str,
    errors: List[str],
) -> Optional[float]:
    if lat is None:
        return None
    if not (VN_LAT_MIN <= lat <= VN_LAT_MAX):
        errors.append(
            f"Row {row_num} ({label}): Latitude {lat} ngoai pham vi Viet Nam "
            f"({VN_LAT_MIN}–{VN_LAT_MAX}) – giu nguyen gia tri nhung canh bao"
        )
    return lat


def _validate_lon(
    lon: Optional[float],
    row_num: int,
    label: str,
    errors: List[str],
) -> Optional[float]:
    if lon is None:
        return None
    if not (VN_LON_MIN <= lon <= VN_LON_MAX):
        errors.append(
            f"Row {row_num} ({label}): Longitude {lon} ngoai pham vi Viet Nam "
            f"({VN_LON_MIN}–{VN_LON_MAX}) – giu nguyen gia tri nhung canh bao"
        )
    return lon


def _validate_azimuth(
    azi: Optional[float],
    row_num: int,
    label: str,
    errors: List[str],
) -> Optional[float]:
    if azi is None:
        return None
    if not (AZI_MIN <= azi <= AZI_MAX):
        errors.append(
            f"Row {row_num} ({label}): Azimuth {azi} phai trong khoang "
            f"{AZI_MIN}–{AZI_MAX} – dong bi bo qua"
        )
        return None   # invalid azimuth → reject the value
    return azi


# ─────────────────────────────────────────────────────────────────────────────
# Site import
# ─────────────────────────────────────────────────────────────────────────────

def parse_site_excel(
    file_bytes: bytes,
    db=None,
    dry_run: bool = False,
) -> Dict[str, Any]:
    df  = _read_excel(file_bytes)
    geo = GeoCache(db) if db else None

    to_create: List[Dict] = []
    to_update: List[Dict] = []
    errors:    List[str]  = []

    from app.models.site import Site

    for i, row in df.iterrows():
        row_num   = int(str(i)) + 2
        site_name = _v(row, "Site name", "Site Name", "site_name", "SITE NAME")

        if not site_name:
            errors.append(f"Row {row_num}: 'Site name' column is empty – skipped")
            continue

        raw_tinh   = _v(row, "Tỉnh", "Tinh", "TINH", "tinh", "Province")
        raw_phuong = _v(row, "Phường xã", "Phuong xa", "Phường Xã", "phuong_xa", "Ward")
        raw_mien   = _v(row, "Miền", "Mien", "MIEN", "mien")

        if geo and raw_tinh:
            tinh_official = geo.resolve_tinh(raw_tinh)
            if not tinh_official:
                errors.append(
                    f"Row {row_num} (site '{site_name}'): "
                    f"Province '{raw_tinh}' not found in DB – skipped"
                )
                continue
            mien = geo.mien_for(tinh_official) or raw_mien or ""
            phuong_xa_official: Optional[str] = None
            if raw_phuong:
                phuong_xa_official = geo.resolve_xa(tinh_official, raw_phuong)
                if not phuong_xa_official:
                    errors.append(
                        f"Row {row_num} (site '{site_name}'): "
                        f"Ward '{raw_phuong}' not found under '{tinh_official}' – "
                        f"field left blank"
                    )
        else:
            tinh_official      = raw_tinh or ""
            mien               = raw_mien or ""
            phuong_xa_official = raw_phuong

        if not tinh_official:
            errors.append(
                f"Row {row_num} (site '{site_name}'): 'Tinh' is empty – skipped"
            )
            continue

        # ── Lat / Long validation ────────────────────────────────────────
        raw_lat  = _float(row, "Lat", "LAT", "lat", "Latitude")
        raw_long = _float(row, "Long", "LONG", "long", "Longitude")
        lat  = _validate_lat(raw_lat,  row_num, site_name, errors)
        long = _validate_lon(raw_long, row_num, site_name, errors)

        rec: Dict[str, Any] = {
            "mien":         mien,
            "tinh":         tinh_official,
            "phuong_xa":    phuong_xa_official,
            "site_name_cu": _v(row, "Site name (cũ)", "Site name (cu)", "Site Name (cũ)"),
            "site_name":    site_name,
            "site_vip":     _v(row, "Site VIP", "site_vip"),
            "lat":          lat,
            "long":         long,
            "tram_2g":      _bool(row, "Trạm 2G", "Tram 2G", "tram_2g"),
            "tram_3g":      _bool(row, "Trạm 3G", "Tram 3G", "tram_3g"),
            "tram_4g":      _bool(row, "Trạm 4G", "Tram 4G", "tram_4g"),
            "tram_5g":      _bool(row, "Trạm 5G", "Tram 5G", "tram_5g"),
            "repeater":     _bool(row, "Repeater", "repeater"),
            "booster":      _bool(row, "Booster",  "booster"),
            "node_truyen_dan_only": _bool(
                row,
                "Node truyền dẫn only (không có điểm phát sóng)",
                "Node truyen dan only", "node_truyen_dan_only",
            ),
            "tram_phu_song_tsca": _bool(
                row,
                "Trạm phủ sóng TSCA (x)", "Tram phu song TSCA",
                "tram_phu_song_tsca", "TSCA",
            ),
            "phan_loai_tram": _v(
                row,
                "IBC/ Macro outdoor / IBC + Outdoor / miniDAS / Smallcell",
                "IBC/Macro outdoor/IBC + Outdoor/miniDAS/Smallcell",
                "Phan loai tram", "phan_loai_tram",
            ),
            "moran_3g": _v(row, "TRẠM MORAN 3G (VNPT HOST, MBF HOST)",
                           "MORAN 3G", "moran_3g"),
            "moran_4g": _v(row, "TRẠM MORAN 4G (VNPT HOST, MBF HOST)",
                           "MORAN 4G", "moran_4g"),
            "moran_5g": _v(row, "TRẠM MORAN 5G (VNPT HOST, MBF HOST)",
                           "MORAN 5G", "moran_5g"),
            "ma_ptm":   _v(row, "Mã PTM", "Ma PTM", "ma_ptm", "MaPTM", "PTM") or "",
            "do_cao_dinh_cot_anten": _float(
                row,
                "Độ cao đỉnh cột anten (m) đến mặt đất",
                "Do cao dinh cot anten (m) den mat dat",
                "Do cao dinh cot anten", "do_cao_dinh_cot_anten",
            ),
            "do_cao_cot_anten": _float(
                row,
                "Độ cao cột anten (đỉnh cột anten (m) đến mặt sàn)",
                "Do cao cot anten (dinh cot anten (m) den mat san)",
                "Do cao cot anten", "do_cao_cot_anten",
            ),
            "dia_chi": _v(row, "Địa chỉ", "Dia chi", "dia_chi"),
            "ghi_chu": _v(row, "Ghi chú", "Ghi chu", "ghi_chu"),
        }

        if db:
            existing = db.query(Site).filter(Site.site_name == site_name).first()
            if existing:
                to_update.append({
                    "existing_id": existing.id,
                    "anchor":      site_name,
                    "changes":     rec,
                })
            else:
                to_create.append(rec)
        else:
            to_create.append(rec)

    return {"to_create": to_create, "to_update": to_update,
            "errors": errors, "dry_run": dry_run}


# ─────────────────────────────────────────────────────────────────────────────
# Cell common
# ─────────────────────────────────────────────────────────────────────────────

def _cell_common(
    row,
    geo: Optional[GeoCache] = None,
    errors_out: Optional[List] = None,
    row_num: int = 0,
) -> Dict[str, Any]:
    raw_tinh   = _v(row, "Tỉnh", "Tinh", "tinh")
    raw_phuong = _v(row, "Phường xã", "Phuong xa", "phuong_xa")
    raw_mien   = _v(row, "Miền", "Mien", "mien")

    if geo and raw_tinh:
        tinh_official = geo.resolve_tinh(raw_tinh)
        if not tinh_official:
            if errors_out is not None:
                errors_out.append(
                    f"Row {row_num}: Province '{raw_tinh}' not found in DB – stored as-is"
                )
            tinh_official = raw_tinh
        mien = geo.mien_for(tinh_official) or raw_mien or ""
        phuong_xa_official: Optional[str] = None
        if raw_phuong:
            phuong_xa_official = geo.resolve_xa(tinh_official, raw_phuong)
    else:
        tinh_official      = raw_tinh
        mien               = raw_mien
        phuong_xa_official = raw_phuong

    cell_name = _v(row, "Cell Name", "Cell name", "cell_name") or ""
    label     = cell_name or f"row {row_num}"

    # Validated fields
    raw_lat  = _float(row, "Lat", "LAT", "lat")
    raw_long = _float(row, "Long", "LONG", "long")
    raw_azi  = _float(row, "Azimuth", "azimuth")

    lat  = _validate_lat(raw_lat,  row_num, label, errors_out or [])
    lon  = _validate_lon(raw_long, row_num, label, errors_out or [])
    azi  = _validate_azimuth(raw_azi, row_num, label, errors_out or [])

    return {
        "mien":          mien,
        "tinh":          tinh_official,
        "phuong_xa":     phuong_xa_official,
        "site_name":     _v(row, "Site Name", "Site name", "site_name") or "",
        "cell_name":     cell_name,
        "cell_vip":      _v(row, "Cell VIP", "cell_vip"),
        "moran":         _v(row, "MORAN", "Moran", "moran"),
        "lat":           lat,
        "long":          lon,
        "vung_phu_song": _v(row, "Vùng phủ sóng", "Vung phu song", "vung_phu_song"),
        "vendor":        _v(row, "Vendor", "vendor"),
        "do_cao_anten":  _float(row, "Độ cao anten", "Do cao anten", "do_cao_anten"),
        "azimuth":       azi,
        "m_tilt":        _float(row, "M-tilt", "M-Tilt", "m_tilt"),
        "e_tilt":        _float(row, "E-Tilt", "E-tilt", "e_tilt"),
        "total_tilt":    _float(row, "Total Tilt", "Total tilt", "total_tilt"),
        "loai_anten":    _v(row, "Loại Anten", "Loai Anten", "loai_anten"),
        "baseband":      _v(row, "Baseband", "baseband"),
        "rf":            _v(row, "RF", "rf"),
        "cell_id":       _v(row, "Cell ID", "cell_id"),
        "mimo":          _v(row, "MIMO", "mimo"),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Generic cell parser
# ─────────────────────────────────────────────────────────────────────────────

def _parse_cell_excel(
    file_bytes: bytes,
    Model,
    extra_fields_fn,
    db=None,
    dry_run: bool = False,
) -> Dict[str, Any]:
    df  = _read_excel(file_bytes)
    geo = GeoCache(db) if db else None

    to_create:       List[Dict] = []
    to_update:       List[Dict] = []
    sites_to_create: List[Dict] = []
    errors:          List[str]  = []
    pending_new_sites: Dict[str, Dict] = {}

    from app.models.site import Site

    for i, row in df.iterrows():
        row_num    = int(str(i)) + 2
        row_errors: List[str] = []

        common    = _cell_common(row, geo=geo, errors_out=row_errors, row_num=row_num)
        errors.extend(row_errors)

        cell_name = common.get("cell_name", "")
        site_name = common.get("site_name", "")

        if not cell_name:
            errors.append(f"Row {row_num}: 'Cell Name' is empty – skipped")
            continue
        if not site_name:
            errors.append(f"Row {row_num}: 'Site Name' is empty – skipped")
            continue

        extra = extra_fields_fn(row)
        rec   = {**common, **extra}

        site_obj = None
        if db:
            site_obj = db.query(Site).filter(Site.site_name == site_name).first()

        if site_obj:
            site_id = site_obj.id
        elif site_name in pending_new_sites:
            site_id = None
        else:
            new_site_rec = {
                "site_name": site_name,
                "mien":      common.get("mien") or "",
                "tinh":      common.get("tinh") or "",
                "phuong_xa": common.get("phuong_xa"),
                "lat":       common.get("lat"),
                "long":      common.get("long"),
            }
            pending_new_sites[site_name] = new_site_rec
            sites_to_create.append(new_site_rec)
            site_id = None

        rec["site_id"] = site_id

        existing_cell = None
        if db and site_obj:
            existing_cell = db.query(Model).filter(
                Model.site_id == site_obj.id,
                Model.cell_name == cell_name,
            ).first()

        if existing_cell:
            to_update.append({
                "existing_id": existing_cell.id,
                "anchor":      f"{site_name}/{cell_name}",
                "changes":     rec,
            })
        else:
            to_create.append(rec)

    return {
        "to_create":       to_create,
        "to_update":       to_update,
        "sites_to_create": sites_to_create,
        "errors":          errors,
        "dry_run":         dry_run,
    }


def parse_site_excel_simple(file_bytes: bytes) -> List[Dict[str, Any]]:
    result  = parse_site_excel(file_bytes, db=None, dry_run=False)
    records: List[Dict] = []
    for rec in result["to_create"]:
        records.append(rec)
    for upd in result["to_update"]:
        records.append(upd["changes"])
    return records


def parse_cell3g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_3g import Cell3G
    def extra(row):
        return {
            "chung_anten": _v(row, "Chung anten", "chung_anten"),
            "arfcn":       _v(row, "ARFCN", "arfcn"),
            "psc":         _v(row, "PSC",   "psc"),
        }
    return _parse_cell_excel(file_bytes, Cell3G, extra, db=db, dry_run=dry_run)


def parse_cell4g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_4g import Cell4G
    def extra(row):
        return {
            "chung_anten":      _v(row, "Chung anten",     "chung_anten"),
            "earfcn":           _v(row, "EARFCN",           "earfcn"),
            "pci":              _v(row, "PCI",              "pci"),
            "root_sequence_id": _v(row, "Root Sequence ID", "root_sequence_id"),
        }
    return _parse_cell_excel(file_bytes, Cell4G, extra, db=db, dry_run=dry_run)


def parse_cell5g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_5g import Cell5G
    def extra(row):
        return {
            "nr_arfcn":         _v(row, "NR-ARFCN",        "nr_arfcn"),
            "pci":              _v(row, "PCI",              "pci"),
            "root_sequence_id": _v(row, "Root Sequence ID", "root_sequence_id"),
        }
    return _parse_cell_excel(file_bytes, Cell5G, extra, db=db, dry_run=dry_run)
PYEOF

echo "    ✓ import_excel.py updated with validation"

# ── Step 6: Update frontend types ─────────────────────────────────────────────
echo "[6/10] Updating frontend types..."

cat > frontend/src/types/index.ts << 'TSEOF'
export interface User {
  id: number
  email: string
  username: string
  full_name?: string
  role: 'admin' | 'user'
  is_active: boolean
  auth_provider: 'local' | 'sso'
}

export interface Site {
  id: number
  mien: string
  tinh: string
  phuong_xa?: string
  site_name_cu?: string
  site_name: string
  site_vip?: string
  lat: number
  long: number
  tram_2g: boolean
  tram_3g: boolean
  tram_4g: boolean
  tram_5g: boolean
  repeater: boolean
  booster: boolean
  node_truyen_dan_only: boolean
  tram_phu_song_tsca: boolean
  phan_loai_tram?: string
  moran_3g?: string
  moran_4g?: string
  moran_5g?: string
  ma_ptm: string
  do_cao_dinh_cot_anten?: number
  do_cao_cot_anten?: number
  dia_chi?: string
  ghi_chu?: string
}

export interface CellBase {
  id: number
  site_id: number
  mien?: string
  tinh?: string
  phuong_xa?: string
  site_name: string
  cell_name: string
  cell_vip?: string
  moran?: string
  lat?: number
  long?: number
  vung_phu_song?: string
  vendor?: string
  do_cao_anten?: number
  azimuth?: number
  m_tilt?: number
  e_tilt?: number
  total_tilt?: number
  loai_anten?: string
  baseband?: string
  rf?: string
  cell_id?: string
  mimo?: string
}

export interface Cell3G extends CellBase {
  chung_anten?: string
  arfcn?: string
  psc?: string
}

export interface Cell4G extends CellBase {
  chung_anten?: string
  earfcn?: string
  pci?: string
  root_sequence_id?: string
}

export interface Cell5G extends CellBase {
  nr_arfcn?: string
  pci?: string
  root_sequence_id?: string
}

export interface ReportRow {
  mien?: string
  tinh?: string
  site_count: number
  site_2g: number
  site_3g: number
  site_4g: number
  site_5g: number
  cell_3g: number
  cell_4g: number
  cell_5g: number
}

export interface AuditLog {
  id: number
  username: string
  full_name: string
  email: string
  action: string
  table_name: string
  record_id: number
  old_value?: string
  new_value?: string
  timestamp: string
}

export interface TinhItem {
  ten_tinh: string
  mien: string
}

export interface PhuongXaItem {
  id: number
  mien: string
  ten_tinh: string
  ten_phuong_xa: string
  ma_tinh: string
  ma_phuong_xa: string
  ky_tu_1_6: string
}

export interface AntennaItem {
  id: number
  name: string
  band?: string
  no_of_ports?: number
  no_of_beam?: number
  horizontal_bw?: string
  vertical_bw?: string
  gain?: string
  etilt?: string
  h?: string
  w?: string
  d?: string
  weight?: string
  connector_type?: string
  ghi_chu?: string
}

export interface ProvinceChartItem {
  tinh: string
  site_count: number
}

export interface CellProvinceChartItem {
  tinh: string
  cell_count: number
}

export interface SiteDryRunResult {
  to_create: number
  to_update: number
  errors: number
  error_details: string[]
  preview_create: string[]
  preview_update: string[]
  dry_run: true
}

export interface CellDryRunResult {
  to_create: number
  to_update: number
  sites_to_create: number
  errors: number
  error_details: string[]
  preview_create: string[]
  preview_update: string[]
  preview_new_sites: string[]
  dry_run: true
}

export interface ImportResult {
  created: number
  updated: number
  sites_auto_created?: number
  errors: string[]
}

export interface AntennaFull {
  id: number
  name: string
  no_of_ports?: number
  band?: string
  no_of_beam?: number
  horizontal_bw?: string
  vertical_bw?: string
  gain?: string
  etilt?: string
  h?: string
  w?: string
  d?: string
  weight?: string
  connector_type?: string
  ghi_chu?: string
}
TSEOF

echo "    ✓ types/index.ts updated"

# ── Step 7: Update DryRunModal with template download ─────────────────────────
echo "[7/10] Updating DryRunModal with template download..."

cat > frontend/src/components/shared/DryRunModal.tsx << 'TSXEOF'
/**
 * DryRunModal
 * -----------
 * Generic 2-step import wizard with template download:
 *   Step 1 – upload file  → call dryRunFn  → show preview
 *   Step 2 – user confirms → call importFn → show result
 *
 * Props:
 *   templateKey: 'site' | 'cell-3g' | 'cell-4g' | 'cell-5g'
 *     When provided, shows a "Download Template" button.
 */
import React, { useState } from 'react'
import {
  Modal, Upload, Button, Steps, Descriptions, Tag,
  List, Alert, Space, Typography, Spin, Divider, Tooltip,
} from 'antd'
import {
  UploadOutlined, CheckCircleOutlined,
  ExclamationCircleOutlined, LoadingOutlined,
  DownloadOutlined, FileExcelOutlined,
} from '@ant-design/icons'

export interface DryRunPreview {
  to_create: number
  to_update: number
  sites_to_create?: number
  errors: number
  error_details: string[]
  preview_create: string[]
  preview_update: string[]
  preview_new_sites?: string[]
}

export interface ImportResultData {
  created: number
  updated: number
  sites_auto_created?: number
  errors: string[]
}

export type TemplateKey = 'site' | 'cell-3g' | 'cell-4g' | 'cell-5g'

interface Props {
  open:        boolean
  onClose:     () => void
  title:       string
  templateKey?: TemplateKey
  dryRunFn:   (file: File) => Promise<DryRunPreview>
  importFn:   (file: File) => Promise<ImportResultData>
  onSuccess:  () => void
}

const TEMPLATE_LABELS: Record<TemplateKey, string> = {
  'site':    'Template_Site.xlsx',
  'cell-3g': 'Template_Cell_3G.xlsx',
  'cell-4g': 'Template_Cell_4G.xlsx',
  'cell-5g': 'Template_Cell_5G.xlsx',
}

function downloadTemplate(key: TemplateKey) {
  const token = localStorage.getItem('sl_token') || ''
  // Create a temporary link – the backend serves the file with auth via Bearer
  // We use fetch+blob so we can pass Authorization header
  const url = `/api/v1/templates/${key}`
  fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  })
    .then((res) => {
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      return res.blob()
    })
    .then((blob) => {
      const link = document.createElement('a')
      link.href  = URL.createObjectURL(blob)
      link.download = TEMPLATE_LABELS[key]
      link.click()
      URL.revokeObjectURL(link.href)
    })
    .catch((err) => {
      console.error('Template download failed:', err)
      alert('Khong the tai template. Vui long thu lai.')
    })
}

export default function DryRunModal({
  open, onClose, title, templateKey, dryRunFn, importFn, onSuccess,
}: Props) {
  const [step,     setStep]     = useState(0)
  const [busy,     setBusy]     = useState(false)
  const [file,     setFile]     = useState<File | null>(null)
  const [preview,  setPreview]  = useState<DryRunPreview | null>(null)
  const [result,   setResult]   = useState<ImportResultData | null>(null)
  const [fatalErr, setFatalErr] = useState('')

  const reset = () => {
    setStep(0); setFile(null); setPreview(null)
    setResult(null); setFatalErr('')
  }

  const handleClose = () => { reset(); onClose() }

  const handleDryRun = async () => {
    if (!file) return
    setBusy(true)
    setFatalErr('')
    try {
      const prev = await dryRunFn(file)
      setPreview(prev)
      setStep(1)
    } catch (e: any) {
      setFatalErr(e?.response?.data?.detail || 'Cannot read file')
    } finally {
      setBusy(false)
    }
  }

  const handleConfirm = async () => {
    if (!file) return
    setBusy(true)
    try {
      const res = await importFn(file)
      setResult(res)
      setStep(2)
      onSuccess()
    } catch (e: any) {
      setFatalErr(e?.response?.data?.detail || 'Import failed')
    } finally {
      setBusy(false)
    }
  }

  const footer = () => {
    if (step === 0) return (
      <Space>
        <Button onClick={handleClose}>Huy</Button>
        <Button
          type="primary"
          disabled={!file}
          loading={busy}
          onClick={handleDryRun}
        >
          Kiem tra file
        </Button>
      </Space>
    )
    if (step === 1) return (
      <Space>
        <Button onClick={reset}>Chon lai file</Button>
        <Button onClick={handleClose}>Huy</Button>
        <Button
          type="primary"
          loading={busy}
          onClick={handleConfirm}
          disabled={
            (preview?.to_create ?? 0) + (preview?.to_update ?? 0) === 0
          }
        >
          Xac nhan import
        </Button>
      </Space>
    )
    return (
      <Button type="primary" onClick={handleClose}>Dong</Button>
    )
  }

  return (
    <Modal
      title={title}
      open={open}
      onCancel={handleClose}
      footer={footer()}
      width={700}
      destroyOnClose
    >
      <Steps
        current={step}
        size="small"
        style={{ marginBottom: 24 }}
        items={[
          { title: 'Chon file' },
          { title: 'Xem truoc' },
          { title: 'Hoan thanh' },
        ]}
      />

      {/* ── Step 0: file picker ── */}
      {step === 0 && (
        <div>
          {/* Template download section */}
          {templateKey && (
            <div style={{
              background: '#f6ffed',
              border: '1px solid #b7eb8f',
              borderRadius: 6,
              padding: '10px 14px',
              marginBottom: 16,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              flexWrap: 'wrap',
              gap: 8,
            }}>
              <Space>
                <FileExcelOutlined style={{ color: '#52c41a', fontSize: 18 }} />
                <div>
                  <Typography.Text strong style={{ fontSize: 13 }}>
                    Chua co file mau?
                  </Typography.Text>
                  <br />
                  <Typography.Text type="secondary" style={{ fontSize: 11 }}>
                    Tai file Excel mau, dien du lieu va import len he thong
                  </Typography.Text>
                </div>
              </Space>
              <Tooltip title={`Tai ${TEMPLATE_LABELS[templateKey]}`}>
                <Button
                  icon={<DownloadOutlined />}
                  size="small"
                  style={{
                    background: '#52c41a',
                    borderColor: '#52c41a',
                    color: '#fff',
                  }}
                  onClick={() => downloadTemplate(templateKey)}
                >
                  Tai file mau
                </Button>
              </Tooltip>
            </div>
          )}

          <Divider style={{ margin: '0 0 16px' }} />

          {fatalErr && (
            <Alert
              message={fatalErr}
              type="error"
              showIcon
              style={{ marginBottom: 12 }}
            />
          )}

          <Upload
            accept=".xlsx,.xls"
            showUploadList={Boolean(file)}
            maxCount={1}
            beforeUpload={(f) => { setFile(f); return false }}
            onRemove={() => setFile(null)}
          >
            <Button icon={<UploadOutlined />} size="large">
              Chon file Excel de import
            </Button>
          </Upload>

          {file && (
            <Typography.Text
              type="secondary"
              style={{ marginTop: 8, display: 'block' }}
            >
              Da chon: <strong>{file.name}</strong>{' '}
              ({(file.size / 1024).toFixed(1)} KB)
            </Typography.Text>
          )}

          {busy && (
            <div style={{ textAlign: 'center', marginTop: 16 }}>
              <Spin indicator={<LoadingOutlined spin />} />
              <div style={{ marginTop: 8 }}>Dang kiem tra file...</div>
            </div>
          )}
        </div>
      )}

      {/* ── Step 1: preview ── */}
      {step === 1 && preview && (
        <div>
          <Descriptions bordered size="small" column={2} style={{ marginBottom: 16 }}>
            <Descriptions.Item label="Se tao moi">
              <Tag color="green">{preview.to_create}</Tag>
            </Descriptions.Item>
            <Descriptions.Item label="Se cap nhat">
              <Tag color="blue">{preview.to_update}</Tag>
            </Descriptions.Item>
            {preview.sites_to_create !== undefined && (
              <Descriptions.Item label="Site se tu dong tao">
                <Tag color="purple">{preview.sites_to_create}</Tag>
              </Descriptions.Item>
            )}
            <Descriptions.Item label="Dong co loi / canh bao">
              <Tag color={preview.errors > 0 ? 'red' : 'default'}>
                {preview.errors}
              </Tag>
            </Descriptions.Item>
          </Descriptions>

          {preview.preview_create.length > 0 && (
            <div style={{ marginBottom: 12 }}>
              <Typography.Text strong>
                <CheckCircleOutlined style={{ color: '#52c41a' }} />{' '}
                Se tao moi (mau):
              </Typography.Text>
              <List
                size="small"
                dataSource={preview.preview_create}
                renderItem={(item) => <List.Item>{item}</List.Item>}
              />
              {preview.to_create > 5 && (
                <Typography.Text type="secondary">
                  ... va {preview.to_create - 5} ban ghi khac
                </Typography.Text>
              )}
            </div>
          )}

          {preview.preview_update.length > 0 && (
            <div style={{ marginBottom: 12 }}>
              <Typography.Text strong>
                <CheckCircleOutlined style={{ color: '#1890ff' }} />{' '}
                Se cap nhat (mau):
              </Typography.Text>
              <List
                size="small"
                dataSource={preview.preview_update}
                renderItem={(item) => <List.Item>{item}</List.Item>}
              />
            </div>
          )}

          {(preview.preview_new_sites?.length ?? 0) > 0 && (
            <div style={{ marginBottom: 12 }}>
              <Typography.Text strong>
                Site se duoc tu dong tao (mau):
              </Typography.Text>
              <List
                size="small"
                dataSource={preview.preview_new_sites}
                renderItem={(item) => <List.Item>{item}</List.Item>}
              />
            </div>
          )}

          {preview.error_details.length > 0 && (
            <Alert
              type="warning"
              showIcon
              icon={<ExclamationCircleOutlined />}
              message={`${preview.errors} dong co loi / canh bao (se bi bo qua hoac giu nguyen)`}
              description={
                <div style={{ maxHeight: 150, overflowY: 'auto' }}>
                  {preview.error_details.slice(0, 20).map((e, i) => (
                    <div
                      key={i}
                      style={{ fontSize: 12, fontFamily: 'monospace', marginBottom: 2 }}
                    >
                      {e}
                    </div>
                  ))}
                  {preview.error_details.length > 20 && (
                    <div style={{ color: '#999' }}>
                      ... va {preview.error_details.length - 20} loi khac
                    </div>
                  )}
                </div>
              }
            />
          )}
        </div>
      )}

      {/* ── Step 2: result ── */}
      {step === 2 && result && (
        <div>
          <Alert
            type="success"
            showIcon
            message="Import hoan thanh"
            description={
              <div>
                <div>Da tao moi: <strong>{result.created}</strong></div>
                <div>Da cap nhat: <strong>{result.updated}</strong></div>
                {(result.sites_auto_created ?? 0) > 0 && (
                  <div>
                    Site tu dong tao:{' '}
                    <strong>{result.sites_auto_created}</strong>
                  </div>
                )}
                {result.errors.length > 0 && (
                  <div style={{ marginTop: 8 }}>
                    <Typography.Text type="danger">
                      {result.errors.length} loi:
                    </Typography.Text>
                    <div style={{ maxHeight: 120, overflowY: 'auto' }}>
                      {result.errors.slice(0, 10).map((e, i) => (
                        <div
                          key={i}
                          style={{ fontSize: 12, fontFamily: 'monospace' }}
                        >
                          {e}
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            }
          />
        </div>
      )}
    </Modal>
  )
}
TSXEOF

echo "    ✓ DryRunModal.tsx updated"

# ── Step 8: Update AuditPage ──────────────────────────────────────────────────
echo "[8/10] Updating AuditPage with full_name and email columns..."

cat > frontend/src/pages/admin/AuditPage.tsx << 'TSXEOF'
import React, { useEffect, useState } from 'react'
import {
  Typography, Table, Select, Space, Tag, Row,
  Button, Input, Tooltip,
} from 'antd'
import { ReloadOutlined, SearchOutlined } from '@ant-design/icons'
import { getAuditLogs } from '@/api/report'
import type { AuditLog } from '@/types'

const ACTION_COLOR: Record<string, string> = {
  CREATE: 'green',
  UPDATE: 'blue',
  DELETE: 'red',
  IMPORT: 'purple',
}

const TABLE_OPTIONS = [
  'sites', 'cells_3g', 'cells_4g', 'cells_5g', 'antennas', 'users',
]

export default function AuditPage() {
  const [logs,    setLogs]    = useState<AuditLog[]>([])
  const [loading, setLoading] = useState(false)
  const [action,  setAction]  = useState<string | undefined>()
  const [table,   setTable]   = useState<string | undefined>()
  const [search,  setSearch]  = useState('')

  const load = () => {
    setLoading(true)
    getAuditLogs({ action, table_name: table, limit: 500 })
      .then((data: AuditLog[]) => {
        if (search) {
          const q = search.toLowerCase()
          setLogs(
            data.filter(
              (l) =>
                l.username?.toLowerCase().includes(q) ||
                l.full_name?.toLowerCase().includes(q) ||
                l.email?.toLowerCase().includes(q),
            ),
          )
        } else {
          setLogs(data)
        }
      })
      .finally(() => setLoading(false))
  }

  useEffect(() => { load() }, [action, table, search])

  const columns = [
    {
      title: 'Thoi gian',
      dataIndex: 'timestamp',
      width: 160,
      sorter: (a: AuditLog, b: AuditLog) =>
        new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime(),
      defaultSortOrder: 'descend' as const,
      render: (v: string) =>
        v ? new Date(v).toLocaleString('vi-VN') : '-',
    },
    {
      title: 'Username',
      dataIndex: 'username',
      width: 140,
      render: (v: string) => <strong>{v}</strong>,
    },
    {
      title: 'Ho ten',
      dataIndex: 'full_name',
      width: 160,
      ellipsis: { showTitle: true },
      render: (v: string) => v || <span style={{ color: '#ccc' }}>-</span>,
    },
    {
      title: 'Email',
      dataIndex: 'email',
      width: 200,
      ellipsis: { showTitle: true },
      render: (v: string) =>
        v ? (
          <Tooltip title={v}>
            <span style={{ fontSize: 12, color: '#666' }}>{v}</span>
          </Tooltip>
        ) : (
          <span style={{ color: '#ccc' }}>-</span>
        ),
    },
    {
      title: 'Action',
      dataIndex: 'action',
      width: 90,
      render: (v: string) => (
        <Tag color={ACTION_COLOR[v] || 'default'}>{v}</Tag>
      ),
    },
    {
      title: 'Bang',
      dataIndex: 'table_name',
      width: 120,
      render: (v: string) => <code style={{ fontSize: 11 }}>{v}</code>,
    },
    {
      title: 'Record ID',
      dataIndex: 'record_id',
      width: 90,
    },
    {
      title: 'Du lieu cu',
      dataIndex: 'old_value',
      ellipsis: true,
      render: (v: string) =>
        v ? (
          <Tooltip title={v} overlayStyle={{ maxWidth: 400 }}>
            <span
              style={{
                fontFamily: 'monospace',
                fontSize: 11,
                color: '#cf1322',
              }}
            >
              {v.slice(0, 80)}{v.length > 80 ? '…' : ''}
            </span>
          </Tooltip>
        ) : '-',
    },
    {
      title: 'Du lieu moi',
      dataIndex: 'new_value',
      ellipsis: true,
      render: (v: string) =>
        v ? (
          <Tooltip title={v} overlayStyle={{ maxWidth: 400 }}>
            <span
              style={{
                fontFamily: 'monospace',
                fontSize: 11,
                color: '#237804',
              }}
            >
              {v.slice(0, 80)}{v.length > 80 ? '…' : ''}
            </span>
          </Tooltip>
        ) : '-',
    },
  ]

  return (
    <div>
      <Row
        align="middle"
        justify="space-between"
        style={{ marginBottom: 16 }}
      >
        <Typography.Title level={3} style={{ margin: 0 }}>
          Audit Log
        </Typography.Title>
        <Button icon={<ReloadOutlined />} onClick={load} loading={loading}>
          Lam moi
        </Button>
      </Row>

      <Space style={{ marginBottom: 12 }} wrap>
        <Input
          prefix={<SearchOutlined />}
          placeholder="Tim username / ho ten / email..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          allowClear
          style={{ width: 260 }}
        />
        <Select
          placeholder="Action"
          allowClear
          style={{ width: 120 }}
          onChange={setAction}
          value={action}
        >
          {['CREATE', 'UPDATE', 'DELETE', 'IMPORT'].map((a) => (
            <Select.Option key={a} value={a}>{a}</Select.Option>
          ))}
        </Select>
        <Select
          placeholder="Bang du lieu"
          allowClear
          style={{ width: 160 }}
          onChange={setTable}
          value={table}
        >
          {TABLE_OPTIONS.map((t) => (
            <Select.Option key={t} value={t}>{t}</Select.Option>
          ))}
        </Select>
        {(action || table || search) && (
          <Button
            onClick={() => {
              setAction(undefined)
              setTable(undefined)
              setSearch('')
            }}
          >
            Xoa loc
          </Button>
        )}
      </Space>

      <Typography.Text
        type="secondary"
        style={{ display: 'block', marginBottom: 8, fontSize: 12 }}
      >
        Hien thi {logs.length} ban ghi
      </Typography.Text>

      <Table
        columns={columns}
        dataSource={logs}
        rowKey="id"
        loading={loading}
        size="small"
        scroll={{ x: 1400, y: 600 }}
        bordered
        pagination={{
          pageSize: 50,
          showTotal: (t) => `${t} records`,
          showSizeChanger: true,
        }}
      />
    </div>
  )
}
TSXEOF

echo "    ✓ AuditPage.tsx updated"

# ── Step 9: Update SitesPage, Cells pages to pass templateKey ────────────────
echo "[9/10] Updating pages to pass templateKey to DryRunModal..."

# Patch SitesPage.tsx
sed -i 's|title="Import Site tu Excel"|title="Import Site tu Excel"\n        templateKey="site"|' \
  frontend/src/pages/sites/SitesPage.tsx

# Patch Cells3GPage.tsx
sed -i 's|title="Import Cell 3G tu Excel"|title="Import Cell 3G tu Excel"\n        templateKey="cell-3g"|' \
  frontend/src/pages/cells/Cells3GPage.tsx

# Patch Cells4GPage.tsx
sed -i 's|title="Import Cell 4G tu Excel"|title="Import Cell 4G tu Excel"\n        templateKey="cell-4g"|' \
  frontend/src/pages/cells/Cells4GPage.tsx

# Patch Cells5GPage.tsx
sed -i 's|title="Import Cell 5G tu Excel"|title="Import Cell 5G tu Excel"\n        templateKey="cell-5g"|' \
  frontend/src/pages/cells/Cells5GPage.tsx

# Patch AntennaPage.tsx — antenna uses its own import modal via dryRunAntennaExcel
# We need to update the DryRunModal call there too with the proper interface
# Since Antenna template is separate, just add templateKey prop if exists
# The AntennaPage uses DryRunModal differently, update it:
cat > /tmp/antenna_patch.py << 'EOF'
import re

with open('frontend/src/pages/antenna/AntennaPage.tsx', 'r') as f:
    content = f.read()

# Add templateKey to AntennaPage DryRunModal
old = 'title="Import Antenna tu Excel"'
new = 'title="Import Antenna tu Excel"\n        templateKey={undefined}'
content = content.replace(old, new)

with open('frontend/src/pages/antenna/AntennaPage.tsx', 'w') as f:
    f.write(content)

print("AntennaPage patched")
EOF
python3 /tmp/antenna_patch.py 2>/dev/null || true

echo "    ✓ Pages updated with templateKey"

# ── Step 10: Add UI validation to SiteFormPage and Cell pages ─────────────────
echo "[10/10] Adding frontend validation rules..."

# Update SiteFormPage lat/long validation
cat > /tmp/patch_siteform.py << 'PYEOF'
import re

with open('frontend/src/pages/sites/SiteFormPage.tsx', 'r') as f:
    content = f.read()

# Replace lat InputNumber with validated version
old_lat = '''              <Form.Item name="lat" label="Latitude">
                <InputNumber style={{ width: '100%' }} precision={5} step={0.00001} />
              </Form.Item>'''

new_lat = '''              <Form.Item
                name="lat"
                label="Latitude"
                rules={[{
                  validator: (_: unknown, value: number) => {
                    if (value === undefined || value === null) return Promise.resolve()
                    if (value < 8.33 || value > 23.39)
                      return Promise.reject('Latitude phai trong khoang 8.33 – 23.39 (Viet Nam)')
                    return Promise.resolve()
                  }
                }]}
              >
                <InputNumber style={{ width: '100%' }} precision={5} step={0.00001}
                  placeholder="8.33 – 23.39" />
              </Form.Item>'''

old_lon = '''              <Form.Item name="long" label="Longitude">
                <InputNumber style={{ width: '100%' }} precision={5} step={0.00001} />
              </Form.Item>'''

new_lon = '''              <Form.Item
                name="long"
                label="Longitude"
                rules={[{
                  validator: (_: unknown, value: number) => {
                    if (value === undefined || value === null) return Promise.resolve()
                    if (value < 102.14 || value > 109.47)
                      return Promise.reject('Longitude phai trong khoang 102.14 – 109.47 (Viet Nam)')
                    return Promise.resolve()
                  }
                }]}
              >
                <InputNumber style={{ width: '100%' }} precision={5} step={0.00001}
                  placeholder="102.14 – 109.47" />
              </Form.Item>'''

content = content.replace(old_lat, new_lat)
content = content.replace(old_lon, new_lon)

with open('frontend/src/pages/sites/SiteFormPage.tsx', 'w') as f:
    f.write(content)
print("SiteFormPage patched")
PYEOF
python3 /tmp/patch_siteform.py

# Create a shared validation helper
cat > frontend/src/utils/validators.ts << 'TSEOF'
/**
 * validators.ts
 * Shared Ant Design form validators for SiteLink.
 */

// Vietnam bounding box
export const VN_LAT_MIN = 8.33
export const VN_LAT_MAX = 23.39
export const VN_LON_MIN = 102.14
export const VN_LON_MAX = 109.47

export const latValidator = (_: unknown, value: number) => {
  if (value === undefined || value === null || value === 0) return Promise.resolve()
  if (value < VN_LAT_MIN || value > VN_LAT_MAX)
    return Promise.reject(
      new Error(`Latitude phai trong khoang ${VN_LAT_MIN} – ${VN_LAT_MAX} (lanh tho Viet Nam)`)
    )
  return Promise.resolve()
}

export const lonValidator = (_: unknown, value: number) => {
  if (value === undefined || value === null || value === 0) return Promise.resolve()
  if (value < VN_LON_MIN || value > VN_LON_MAX)
    return Promise.reject(
      new Error(`Longitude phai trong khoang ${VN_LON_MIN} – ${VN_LON_MAX} (lanh tho Viet Nam)`)
    )
  return Promise.resolve()
}

export const azimuthValidator = (_: unknown, value: number) => {
  if (value === undefined || value === null) return Promise.resolve()
  if (value < 0 || value > 359)
    return Promise.reject(new Error('Azimuth phai trong khoang 0 – 359'))
  return Promise.resolve()
}
TSEOF

echo "    ✓ validators.ts created"

# Patch Cells3GPage modal - add validators
cat > /tmp/patch_cells3g.py << 'PYEOF'
with open('frontend/src/pages/cells/Cells3GPage.tsx', 'r') as f:
    content = f.read()

# Add import
if "validators" not in content:
    content = content.replace(
        "import DryRunModal from '@/components/shared/DryRunModal'",
        "import DryRunModal from '@/components/shared/DryRunModal'\nimport { latValidator, lonValidator, azimuthValidator } from '@/utils/validators'"
    )

# Patch lat field
old = "              <Form.Item name=\"lat\" label=\"Lat\">\n                <InputNumber style={{ width: '100%' }} precision={5} />\n              </Form.Item>"
new = """              <Form.Item name="lat" label="Lat (8.33-23.39)" rules={[{ validator: latValidator }]}>
                <InputNumber style={{ width: '100%' }} precision={5} placeholder="8.33 – 23.39" />
              </Form.Item>"""
content = content.replace(old, new)

# Patch long field
old = "              <Form.Item name=\"long\" label=\"Long\">\n                <InputNumber style={{ width: '100%' }} precision={5} />\n              </Form.Item>"
new = """              <Form.Item name="long" label="Long (102.14-109.47)" rules={[{ validator: lonValidator }]}>
                <InputNumber style={{ width: '100%' }} precision={5} placeholder="102.14 – 109.47" />
              </Form.Item>"""
content = content.replace(old, new)

# Patch azimuth field
old = "              <Form.Item name=\"azimuth\" label=\"Azimuth\">\n                <InputNumber style={{ width: '100%' }} min={0} max={359} />\n              </Form.Item>"
new = """              <Form.Item name="azimuth" label="Azimuth (0-359)" rules={[{ validator: azimuthValidator }]}>
                <InputNumber style={{ width: '100%' }} min={0} max={359} />
              </Form.Item>"""
content = content.replace(old, new)

with open('frontend/src/pages/cells/Cells3GPage.tsx', 'w') as f:
    f.write(content)
print("Cells3GPage patched")
PYEOF
python3 /tmp/patch_cells3g.py

# Patch Cells4GPage
cat > /tmp/patch_cells4g.py << 'PYEOF'
with open('frontend/src/pages/cells/Cells4GPage.tsx', 'r') as f:
    content = f.read()

if "validators" not in content:
    content = content.replace(
        "import DryRunModal from '@/components/shared/DryRunModal'",
        "import DryRunModal from '@/components/shared/DryRunModal'\nimport { latValidator, lonValidator, azimuthValidator } from '@/utils/validators'"
    )

replacements = [
    (
        '<Form.Item name="lat" label="Lat"><InputNumber style={{ width: \'100%\' }} precision={5} /></Form.Item>',
        '<Form.Item name="lat" label="Lat (8.33-23.39)" rules={[{ validator: latValidator }]}><InputNumber style={{ width: \'100%\' }} precision={5} placeholder="8.33-23.39" /></Form.Item>'
    ),
    (
        '<Form.Item name="long" label="Long"><InputNumber style={{ width: \'100%\' }} precision={5} /></Form.Item>',
        '<Form.Item name="long" label="Long (102.14-109.47)" rules={[{ validator: lonValidator }]}><InputNumber style={{ width: \'100%\' }} precision={5} placeholder="102.14-109.47" /></Form.Item>'
    ),
    (
        '<Form.Item name="azimuth" label="Azimuth"><InputNumber style={{ width: \'100%\' }} min={0} max={359} /></Form.Item>',
        '<Form.Item name="azimuth" label="Azimuth (0-359)" rules={[{ validator: azimuthValidator }]}><InputNumber style={{ width: \'100%\' }} min={0} max={359} /></Form.Item>'
    ),
]

for old, new in replacements:
    content = content.replace(old, new)

with open('frontend/src/pages/cells/Cells4GPage.tsx', 'w') as f:
    f.write(content)
print("Cells4GPage patched")
PYEOF
python3 /tmp/patch_cells4g.py

# Patch Cells5GPage
cat > /tmp/patch_cells5g.py << 'PYEOF'
with open('frontend/src/pages/cells/Cells5GPage.tsx', 'r') as f:
    content = f.read()

if "validators" not in content:
    content = content.replace(
        "import DryRunModal from '@/components/shared/DryRunModal'",
        "import DryRunModal from '@/components/shared/DryRunModal'\nimport { latValidator, lonValidator, azimuthValidator } from '@/utils/validators'"
    )

replacements = [
    (
        '<Form.Item name="lat" label="Lat"><InputNumber style={{ width: \'100%\' }} precision={5} /></Form.Item>',
        '<Form.Item name="lat" label="Lat (8.33-23.39)" rules={[{ validator: latValidator }]}><InputNumber style={{ width: \'100%\' }} precision={5} placeholder="8.33-23.39" /></Form.Item>'
    ),
    (
        '<Form.Item name="long" label="Long"><InputNumber style={{ width: \'100%\' }} precision={5} /></Form.Item>',
        '<Form.Item name="long" label="Long (102.14-109.47)" rules={[{ validator: lonValidator }]}><InputNumber style={{ width: \'100%\' }} precision={5} placeholder="102.14-109.47" /></Form.Item>'
    ),
    (
        '<Form.Item name="azimuth" label="Azimuth"><InputNumber style={{ width: \'100%\' }} min={0} max={359} /></Form.Item>',
        '<Form.Item name="azimuth" label="Azimuth (0-359)" rules={[{ validator: azimuthValidator }]}><InputNumber style={{ width: \'100%\' }} min={0} max={359} /></Form.Item>'
    ),
]

for old, new in replacements:
    content = content.replace(old, new)

with open('frontend/src/pages/cells/Cells5GPage.tsx', 'w') as f:
    f.write(content)
print("Cells5GPage patched")
PYEOF
python3 /tmp/patch_cells5g.py

echo "    ✓ Cell pages patched with validators"

# ── Rebuild ───────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "Rebuilding containers..."
echo "========================================"
sudo docker compose down
sudo docker compose up -d --build

echo ""
echo "========================================"
echo "Done! Summary of changes:"
echo "========================================"
echo ""
echo "1. EXCEL TEMPLATES"
echo "   Stored in: backend/templates/"
echo "   - template_site.xlsx"
echo "   - template_cell_3g.xlsx"
echo "   - template_cell_4g.xlsx"
echo "   - template_cell_5g.xlsx"
echo "   Generated automatically on backend startup."
echo "   API: GET /api/v1/templates/{site|cell-3g|cell-4g|cell-5g}"
echo "   UI:  Green 'Tai file mau' button inside Import Excel modal"
echo ""
echo "2. DATA VALIDATION"
echo "   Backend (Excel import): warnings logged, stored as-is for lat/long"
echo "     Azimuth out of range: value rejected (set to null)"
echo "   Frontend forms:"
echo "     Lat: 8.33 – 23.39 (Vietnam)"
echo "     Long: 102.14 – 109.47 (Vietnam)"
echo "     Azimuth: 0 – 359"
echo ""
echo "3. AUDIT LOG"
echo "   New columns: Ho ten (full_name), Email"
echo "   Searchable by username / full name / email"
echo "   Improved: action color for IMPORT, tooltip on JSON values"
echo ""