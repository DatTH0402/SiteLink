#!/bin/bash
# add_export.sh
# Adds Excel/CSV export functionality to Sites, Cells 3G/4G/5G, and Antenna pages
#
# Usage: chmod +x add_export.sh && ./add_export.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo "SiteLink - Add Export Feature"
echo "========================================"

# ── Step 1: Backend export routes ─────────────────────────────────────────────
echo "[1/8] Creating backend export route..."

cat > backend/app/api/routes/export.py << 'PYEOF'
"""
export.py
---------
Export endpoints for Sites, Cells 3G/4G/5G, and Antennas.
Returns Excel (.xlsx) files using openpyxl via a StreamingResponse.

All endpoints require authentication.
Token can be passed as:
  - Authorization: Bearer <token>  (normal axios call)
  - ?token=<token>                 (window.open download)
"""
from __future__ import annotations

import io
from typing import Optional

import openpyxl
from openpyxl.styles import PatternFill, Font, Alignment, Border, Side
from openpyxl.utils import get_column_letter
from fastapi import APIRouter, Depends, Query, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.site import Site
from app.models.cell_3g import Cell3G
from app.models.cell_4g import Cell4G
from app.models.cell_5g import Cell5G
from app.models.antenna import Antenna
from app.models.user import User
from app.utils.deps import get_current_user
from app.core.security import decode_access_token

router = APIRouter()

# ── Styling helpers ───────────────────────────────────────────────────────────

HEADER_FILL = PatternFill("solid", fgColor="1F4E79")
HEADER_FONT = Font(color="FFFFFF", bold=True, size=10)
CENTER      = Alignment(horizontal="center", vertical="center", wrap_text=True)
LEFT        = Alignment(horizontal="left",   vertical="center")
THIN        = Side(style="thin", color="D0D0D0")
BORDER      = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
ALT_FILL    = PatternFill("solid", fgColor="EBF3FB")


def _make_wb(headers: list[tuple[str, int]]) -> tuple[openpyxl.Workbook, object]:
    """Create a workbook with styled header row. Returns (wb, ws)."""
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.row_dimensions[1].height = 30
    ws.freeze_panes = "A2"

    for col_idx, (header, width) in enumerate(headers, start=1):
        cell = ws.cell(row=1, column=col_idx, value=header)
        cell.fill      = HEADER_FILL
        cell.font      = HEADER_FONT
        cell.alignment = CENTER
        cell.border    = BORDER
        ws.column_dimensions[get_column_letter(col_idx)].width = width

    return wb, ws


def _style_row(ws, row_idx: int, num_cols: int, alternate: bool):
    fill = ALT_FILL if alternate else None
    for col_idx in range(1, num_cols + 1):
        cell = ws.cell(row=row_idx, column=col_idx)
        cell.alignment = LEFT
        cell.border    = BORDER
        if fill:
            cell.fill = fill


def _stream(wb: openpyxl.Workbook, filename: str) -> StreamingResponse:
    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    return StreamingResponse(
        iter([buf.read()]),
        media_type=(
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        ),
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"'
        },
    )


def _resolve_user(
    token: Optional[str],
    current_user: Optional[User],
    db: Session,
) -> User:
    """
    Support both:
      - Normal Bearer token (current_user already resolved by dependency)
      - ?token= query param (for window.open downloads)
    """
    if current_user:
        return current_user
    if token:
        payload = decode_access_token(token)
        if payload:
            user = db.query(User).filter(
                User.username == payload.get("sub")
            ).first()
            if user and user.is_active:
                return user
    raise HTTPException(status_code=401, detail="Not authenticated")


# ── optional auth dependency (allows token param fallback) ────────────────────
from fastapi.security import OAuth2PasswordBearer
from fastapi import Request

oauth2_optional = OAuth2PasswordBearer(
    tokenUrl="/api/v1/auth/login", auto_error=False
)


def get_optional_user(
    token_header: Optional[str] = Depends(oauth2_optional),
    token_param:  Optional[str] = Query(None, alias="token"),
    db: Session = Depends(get_db),
) -> User:
    # Try Bearer header first, then ?token= param
    raw = token_header or token_param
    if not raw:
        raise HTTPException(status_code=401, detail="Not authenticated")
    payload = decode_access_token(raw)
    if not payload:
        raise HTTPException(status_code=401, detail="Invalid token")
    user = db.query(User).filter(
        User.username == payload.get("sub")
    ).first()
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="User inactive")
    return user


# ─────────────────────────────────────────────────────────────────────────────
# SITES export
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/sites")
def export_sites(
    search:  Optional[str]  = Query(None),
    mien:    Optional[str]  = Query(None),
    tinh:    Optional[str]  = Query(None),
    tram_3g: Optional[bool] = Query(None),
    tram_4g: Optional[bool] = Query(None),
    tram_5g: Optional[bool] = Query(None),
    db:      Session        = Depends(get_db),
    _:       User           = Depends(get_optional_user),
):
    q = db.query(Site)
    if search:  q = q.filter(Site.site_name.ilike(f"%{search}%"))
    if mien:    q = q.filter(Site.mien == mien)
    if tinh:    q = q.filter(Site.tinh == tinh)
    if tram_3g is not None: q = q.filter(Site.tram_3g == tram_3g)
    if tram_4g is not None: q = q.filter(Site.tram_4g == tram_4g)
    if tram_5g is not None: q = q.filter(Site.tram_5g == tram_5g)
    sites = q.order_by(Site.mien, Site.tinh, Site.site_name).all()

    headers = [
        ("STT",                        6),
        ("Mien",                       8),
        ("Tinh",                      22),
        ("Phuong xa",                 22),
        ("Site name (cu)",            22),
        ("Site name",                 25),
        ("Site VIP",                  10),
        ("Lat",                       14),
        ("Long",                      14),
        ("Tram 2G",                   10),
        ("Tram 3G",                   10),
        ("Tram 4G",                   10),
        ("Tram 5G",                   10),
        ("Repeater",                  10),
        ("Booster",                   10),
        ("Node truyen dan only",      20),
        ("Tram phu song TSCA",        18),
        ("Phan loai tram",            22),
        ("MORAN 3G",                  15),
        ("MORAN 4G",                  15),
        ("MORAN 5G",                  15),
        ("Ma PTM",                    14),
        ("Do cao dinh cot anten (m)", 22),
        ("Do cao cot anten (m)",      20),
        ("Dia chi",                   30),
        ("Ghi chu",                   30),
    ]

    wb, ws = _make_wb(headers)

    def b(val: bool) -> str:
        return "x" if val else ""

    for idx, s in enumerate(sites, start=1):
        row = idx + 1
        values = [
            idx,
            s.mien, s.tinh, s.phuong_xa, s.site_name_cu, s.site_name,
            s.site_vip, s.lat, s.long,
            b(s.tram_2g), b(s.tram_3g), b(s.tram_4g), b(s.tram_5g),
            b(s.repeater), b(s.booster),
            b(s.node_truyen_dan_only), b(s.tram_phu_song_tsca),
            s.phan_loai_tram,
            s.moran_3g, s.moran_4g, s.moran_5g, s.ma_ptm,
            s.do_cao_dinh_cot_anten, s.do_cao_cot_anten,
            s.dia_chi, s.ghi_chu,
        ]
        for col_idx, val in enumerate(values, start=1):
            ws.cell(row=row, column=col_idx, value=val)
        _style_row(ws, row, len(headers), idx % 2 == 0)

    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}1"
    return _stream(wb, "Sites_Export.xlsx")


# ─────────────────────────────────────────────────────────────────────────────
# CELLS 3G export
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/cells-3g")
def export_cells_3g(
    search:        Optional[str] = Query(None),
    mien:          Optional[str] = Query(None),
    tinh:          Optional[str] = Query(None),
    vendor:        Optional[str] = Query(None),
    mimo:          Optional[str] = Query(None),
    vung_phu_song: Optional[str] = Query(None),
    db:    Session = Depends(get_db),
    _:     User    = Depends(get_optional_user),
):
    q = db.query(Cell3G)
    if search:
        q = q.filter(
            Cell3G.cell_name.ilike(f"%{search}%") |
            Cell3G.site_name.ilike(f"%{search}%")
        )
    if mien:          q = q.filter(Cell3G.mien == mien)
    if tinh:          q = q.filter(Cell3G.tinh == tinh)
    if vendor:        q = q.filter(Cell3G.vendor == vendor)
    if mimo:          q = q.filter(Cell3G.mimo == mimo)
    if vung_phu_song: q = q.filter(Cell3G.vung_phu_song == vung_phu_song)
    cells = q.order_by(Cell3G.mien, Cell3G.tinh, Cell3G.site_name,
                       Cell3G.cell_name).all()

    headers = [
        ("STT",            6), ("Mien",          8), ("Tinh",         22),
        ("Phuong xa",     22), ("Site Name",     25), ("Cell Name",    25),
        ("Cell VIP",      10), ("MORAN",         15), ("Lat",          14),
        ("Long",          14), ("Vung phu song", 15), ("Vendor",       14),
        ("Do cao anten",  15), ("Azimuth",       10), ("M-tilt",       10),
        ("E-Tilt",        10), ("Total Tilt",    12), ("Loai Anten",   30),
        ("Chung anten",   18), ("Baseband",      18), ("RF",           14),
        ("Cell ID",       14), ("ARFCN",         12), ("PSC",          10),
        ("MIMO",          10),
    ]

    wb, ws = _make_wb(headers)

    for idx, c in enumerate(cells, start=1):
        row = idx + 1
        values = [
            idx,
            c.mien, c.tinh, c.phuong_xa, c.site_name, c.cell_name,
            c.cell_vip, c.moran, c.lat, c.long,
            c.vung_phu_song, c.vendor, c.do_cao_anten,
            c.azimuth, c.m_tilt, c.e_tilt, c.total_tilt,
            c.loai_anten, c.chung_anten, c.baseband, c.rf,
            c.cell_id, c.arfcn, c.psc, c.mimo,
        ]
        for col_idx, val in enumerate(values, start=1):
            ws.cell(row=row, column=col_idx, value=val)
        _style_row(ws, row, len(headers), idx % 2 == 0)

    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}1"
    return _stream(wb, "Cells_3G_Export.xlsx")


# ─────────────────────────────────────────────────────────────────────────────
# CELLS 4G export
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/cells-4g")
def export_cells_4g(
    search:        Optional[str] = Query(None),
    mien:          Optional[str] = Query(None),
    tinh:          Optional[str] = Query(None),
    vendor:        Optional[str] = Query(None),
    mimo:          Optional[str] = Query(None),
    vung_phu_song: Optional[str] = Query(None),
    db:    Session = Depends(get_db),
    _:     User    = Depends(get_optional_user),
):
    q = db.query(Cell4G)
    if search:
        q = q.filter(
            Cell4G.cell_name.ilike(f"%{search}%") |
            Cell4G.site_name.ilike(f"%{search}%")
        )
    if mien:          q = q.filter(Cell4G.mien == mien)
    if tinh:          q = q.filter(Cell4G.tinh == tinh)
    if vendor:        q = q.filter(Cell4G.vendor == vendor)
    if mimo:          q = q.filter(Cell4G.mimo == mimo)
    if vung_phu_song: q = q.filter(Cell4G.vung_phu_song == vung_phu_song)
    cells = q.order_by(Cell4G.mien, Cell4G.tinh, Cell4G.site_name,
                       Cell4G.cell_name).all()

    headers = [
        ("STT",              6), ("Mien",          8), ("Tinh",         22),
        ("Phuong xa",       22), ("Site Name",     25), ("Cell Name",    25),
        ("Cell VIP",        10), ("MORAN",         15), ("Lat",          14),
        ("Long",            14), ("Vung phu song", 15), ("Vendor",       14),
        ("Do cao anten",    15), ("Azimuth",       10), ("M-tilt",       10),
        ("E-Tilt",          10), ("Total Tilt",    12), ("Loai Anten",   30),
        ("Chung anten",     18), ("Baseband",      18), ("RF",           14),
        ("Cell ID",         14), ("EARFCN",        12), ("PCI",          10),
        ("Root Sequence ID",18), ("MIMO",          10),
    ]

    wb, ws = _make_wb(headers)

    for idx, c in enumerate(cells, start=1):
        row = idx + 1
        values = [
            idx,
            c.mien, c.tinh, c.phuong_xa, c.site_name, c.cell_name,
            c.cell_vip, c.moran, c.lat, c.long,
            c.vung_phu_song, c.vendor, c.do_cao_anten,
            c.azimuth, c.m_tilt, c.e_tilt, c.total_tilt,
            c.loai_anten, c.chung_anten, c.baseband, c.rf,
            c.cell_id, c.earfcn, c.pci, c.root_sequence_id, c.mimo,
        ]
        for col_idx, val in enumerate(values, start=1):
            ws.cell(row=row, column=col_idx, value=val)
        _style_row(ws, row, len(headers), idx % 2 == 0)

    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}1"
    return _stream(wb, "Cells_4G_Export.xlsx")


# ─────────────────────────────────────────────────────────────────────────────
# CELLS 5G export
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/cells-5g")
def export_cells_5g(
    search:        Optional[str] = Query(None),
    mien:          Optional[str] = Query(None),
    tinh:          Optional[str] = Query(None),
    vendor:        Optional[str] = Query(None),
    mimo:          Optional[str] = Query(None),
    vung_phu_song: Optional[str] = Query(None),
    db:    Session = Depends(get_db),
    _:     User    = Depends(get_optional_user),
):
    q = db.query(Cell5G)
    if search:
        q = q.filter(
            Cell5G.cell_name.ilike(f"%{search}%") |
            Cell5G.site_name.ilike(f"%{search}%")
        )
    if mien:          q = q.filter(Cell5G.mien == mien)
    if tinh:          q = q.filter(Cell5G.tinh == tinh)
    if vendor:        q = q.filter(Cell5G.vendor == vendor)
    if mimo:          q = q.filter(Cell5G.mimo == mimo)
    if vung_phu_song: q = q.filter(Cell5G.vung_phu_song == vung_phu_song)
    cells = q.order_by(Cell5G.mien, Cell5G.tinh, Cell5G.site_name,
                       Cell5G.cell_name).all()

    headers = [
        ("STT",              6), ("Mien",          8), ("Tinh",         22),
        ("Phuong xa",       22), ("Site Name",     25), ("Cell Name",    25),
        ("Cell VIP",        10), ("MORAN",         15), ("Lat",          14),
        ("Long",            14), ("Vung phu song", 15), ("Vendor",       14),
        ("Do cao anten",    15), ("Azimuth",       10), ("M-tilt",       10),
        ("E-Tilt",          10), ("Total Tilt",    12), ("Loai Anten",   30),
        ("Baseband",        18), ("RF",            14), ("Cell ID",      14),
        ("NR-ARFCN",        12), ("PCI",           10),
        ("Root Sequence ID",18), ("MIMO",          10),
    ]

    wb, ws = _make_wb(headers)

    for idx, c in enumerate(cells, start=1):
        row = idx + 1
        values = [
            idx,
            c.mien, c.tinh, c.phuong_xa, c.site_name, c.cell_name,
            c.cell_vip, c.moran, c.lat, c.long,
            c.vung_phu_song, c.vendor, c.do_cao_anten,
            c.azimuth, c.m_tilt, c.e_tilt, c.total_tilt,
            c.loai_anten, c.baseband, c.rf,
            c.cell_id, c.nr_arfcn, c.pci, c.root_sequence_id, c.mimo,
        ]
        for col_idx, val in enumerate(values, start=1):
            ws.cell(row=row, column=col_idx, value=val)
        _style_row(ws, row, len(headers), idx % 2 == 0)

    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}1"
    return _stream(wb, "Cells_5G_Export.xlsx")


# ─────────────────────────────────────────────────────────────────────────────
# ANTENNAS export
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/antennas")
def export_antennas(
    search: Optional[str] = Query(None),
    band:   Optional[str] = Query(None),
    db:     Session       = Depends(get_db),
    _:      User          = Depends(get_optional_user),
):
    q = db.query(Antenna)
    if search: q = q.filter(Antenna.name.ilike(f"%{search}%"))
    if band:   q = q.filter(Antenna.band.ilike(f"%{band}%"))
    antennas = q.order_by(Antenna.name).all()

    headers = [
        ("STT",            6), ("Name",           35), ("Band",          20),
        ("No of Ports",   12), ("No of Beam",     12), ("Horizontal BW", 14),
        ("Vertical BW",   12), ("Gain (dBi)",     12), ("Etilt range",   14),
        ("H (mm)",        10), ("W (mm)",         10), ("D (mm)",        10),
        ("Weight (kg)",   12), ("Connector type", 18), ("Ghi chu",       30),
    ]

    wb, ws = _make_wb(headers)

    for idx, a in enumerate(antennas, start=1):
        row = idx + 1
        values = [
            idx,
            a.name, a.band, a.no_of_ports, a.no_of_beam,
            a.horizontal_bw, a.vertical_bw, a.gain, a.etilt,
            a.h, a.w, a.d, a.weight, a.connector_type, a.ghi_chu,
        ]
        for col_idx, val in enumerate(values, start=1):
            ws.cell(row=row, column=col_idx, value=val)
        _style_row(ws, row, len(headers), idx % 2 == 0)

    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}1"
    return _stream(wb, "Antennas_Export.xlsx")
PYEOF

echo "    ✓ export.py created"

# ── Step 2: Register export router in main.py ─────────────────────────────────
echo "[2/8] Registering export router in main.py..."

cat > backend/app/main.py << 'PYEOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.db.session import engine, SessionLocal
from app.db import base  # noqa
from app.db.base import Base
from app.api.routes import (
    auth, users, sites, cells_3g, cells_4g, cells_5g,
    dropdowns, report, audit,
)
from app.api.routes import antenna  as antenna_router
from app.api.routes import templates as templates_router
from app.api.routes import export    as export_router

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
    import os
    template_dir = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "templates")
    )
    os.makedirs(template_dir, exist_ok=True)
    required = [
        "template_site.xlsx", "template_cell_3g.xlsx",
        "template_cell_4g.xlsx", "template_cell_5g.xlsx",
    ]
    missing = [
        f for f in required
        if not os.path.exists(os.path.join(template_dir, f))
    ]
    if missing:
        try:
            script = os.path.abspath(
                os.path.join(os.path.dirname(__file__), "..", "create_templates.py")
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
app.include_router(auth.router,              prefix=f"{PREFIX}/auth",       tags=["Auth"])
app.include_router(users.router,             prefix=f"{PREFIX}/users",      tags=["Users"])
app.include_router(sites.router,             prefix=f"{PREFIX}/sites",      tags=["Sites"])
app.include_router(cells_3g.router,          prefix=f"{PREFIX}/cells-3g",   tags=["Cells-3G"])
app.include_router(cells_4g.router,          prefix=f"{PREFIX}/cells-4g",   tags=["Cells-4G"])
app.include_router(cells_5g.router,          prefix=f"{PREFIX}/cells-5g",   tags=["Cells-5G"])
app.include_router(dropdowns.router,         prefix=f"{PREFIX}/dropdowns",  tags=["Dropdowns"])
app.include_router(report.router,            prefix=f"{PREFIX}/report",     tags=["Report"])
app.include_router(audit.router,             prefix=f"{PREFIX}/audit",      tags=["Audit"])
app.include_router(antenna_router.router,    prefix=f"{PREFIX}/antennas",   tags=["Antennas"])
app.include_router(templates_router.router,  prefix=f"{PREFIX}/templates",  tags=["Templates"])
app.include_router(export_router.router,     prefix=f"{PREFIX}/export",     tags=["Export"])


@app.get("/health")
def health():
    return {"status": "ok"}
PYEOF

echo "    ✓ main.py updated"

# ── Step 3: Frontend export API helper ────────────────────────────────────────
echo "[3/8] Creating frontend export API helper..."

cat > frontend/src/api/export.ts << 'TSEOF'
/**
 * export.ts
 * ---------
 * Downloads exported Excel files from the backend.
 * Uses fetch + Blob so Authorization header can be sent.
 * Active filters are passed as query params so the export
 * matches exactly what the user sees on screen.
 */

function getToken(): string {
  return localStorage.getItem('sl_token') || ''
}

async function downloadBlob(url: string, filename: string): Promise<void> {
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${getToken()}` },
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`Export failed (${res.status}): ${text}`)
  }
  const blob = await res.blob()
  const link = document.createElement('a')
  link.href     = URL.createObjectURL(blob)
  link.download = filename
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(link.href)
}

function buildQS(params: Record<string, string | undefined>): string {
  const qs = new URLSearchParams()
  Object.entries(params).forEach(([k, v]) => {
    if (v !== undefined && v !== null && v !== '') qs.append(k, v)
  })
  const s = qs.toString()
  return s ? `?${s}` : ''
}

// ── Sites ─────────────────────────────────────────────────────────────────────
export function exportSites(filters: {
  search?: string
  mien?:   string
  tinh?:   string
}) {
  const qs = buildQS(filters)
  return downloadBlob(`/api/v1/export/sites${qs}`, 'Sites_Export.xlsx')
}

// ── Cells 3G ──────────────────────────────────────────────────────────────────
export function exportCells3G(filters: {
  search?:        string
  mien?:          string
  tinh?:          string
  vendor?:        string
  mimo?:          string
  vung_phu_song?: string
}) {
  const qs = buildQS(filters)
  return downloadBlob(`/api/v1/export/cells-3g${qs}`, 'Cells_3G_Export.xlsx')
}

// ── Cells 4G ──────────────────────────────────────────────────────────────────
export function exportCells4G(filters: {
  search?:        string
  mien?:          string
  tinh?:          string
  vendor?:        string
  mimo?:          string
  vung_phu_song?: string
}) {
  const qs = buildQS(filters)
  return downloadBlob(`/api/v1/export/cells-4g${qs}`, 'Cells_4G_Export.xlsx')
}

// ── Cells 5G ──────────────────────────────────────────────────────────────────
export function exportCells5G(filters: {
  search?:        string
  mien?:          string
  tinh?:          string
  vendor?:        string
  mimo?:          string
  vung_phu_song?: string
}) {
  const qs = buildQS(filters)
  return downloadBlob(`/api/v1/export/cells-5g${qs}`, 'Cells_5G_Export.xlsx')
}

// ── Antennas ──────────────────────────────────────────────────────────────────
export function exportAntennas(filters: {
  search?: string
  band?:   string
}) {
  const qs = buildQS(filters)
  return downloadBlob(`/api/v1/export/antennas${qs}`, 'Antennas_Export.xlsx')
}
TSEOF

echo "    ✓ export.ts created"

# ── Step 4: Update SitesPage ──────────────────────────────────────────────────
echo "[4/8] Updating SitesPage.tsx with export button..."

cat > frontend/src/pages/sites/SitesPage.tsx << 'TSXEOF'
import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, message, Row, Col, Alert, Tooltip,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, UploadOutlined, SearchOutlined,
  EditOutlined, DeleteOutlined, DownloadOutlined,
} from '@ant-design/icons'
import { useNavigate } from 'react-router-dom'
import { getSites, deleteSite, dryRunSitesExcel, importSitesExcel } from '@/api/sites'
import { exportSites } from '@/api/export'
import type { Site } from '@/types'
import DryRunModal from '@/components/shared/DryRunModal'

const boolCell = (v: boolean) =>
  v ? <Tag color="green">x</Tag> : <Tag color="default">-</Tag>

export default function SitesPage() {
  const navigate     = useNavigate()
  const [sites,      setSites]      = useState<Site[]>([])
  const [loading,    setLoading]    = useState(false)
  const [exporting,  setExporting]  = useState(false)
  const [search,     setSearch]     = useState('')
  const [mien,       setMien]       = useState<string | undefined>()
  const [tinh,       setTinh]       = useState<string | undefined>()
  const [loadError,  setLoadError]  = useState<string | null>(null)
  const [dryRunOpen, setDryRunOpen] = useState(false)

  const tinhOptions = [
    ...new Set(sites.map((s) => s.tinh).filter((t): t is string => Boolean(t))),
  ].sort()

  const load = () => {
    setLoading(true)
    setLoadError(null)
    getSites({
      search: search || undefined,
      mien:   mien   || undefined,
      tinh:   tinh   || undefined,
      limit:  500,
    })
      .then(setSites)
      .catch((err) => {
        const detail = err?.response?.data?.detail || err?.message || 'Unknown error'
        setLoadError(`Cannot load sites: ${detail}`)
      })
      .finally(() => setLoading(false))
  }

  useEffect(() => { load() }, [search, mien, tinh])

  const handleDelete = async (id: number) => {
    try {
      await deleteSite(id)
      message.success('Da xoa site')
      load()
    } catch (err: any) {
      const detail = err?.response?.data?.detail || 'Xoa that bai'
      message.error(detail)
    }
  }

  const handleExport = async () => {
    setExporting(true)
    try {
      await exportSites({
        search: search || undefined,
        mien:   mien   || undefined,
        tinh:   tinh   || undefined,
      })
      message.success(`Xuat Excel thanh cong (${sites.length} sites)`)
    } catch (e: any) {
      message.error(e?.message || 'Xuat that bai')
    } finally {
      setExporting(false)
    }
  }

  const columns: ColumnsType<Site> = [
    {
      title: 'Hanh dong', key: 'action', fixed: 'left', width: 80,
      render: (_: unknown, r: Site) => (
        <Space>
          <Button size="small" icon={<EditOutlined />}
                  onClick={() => navigate(`/sites/${r.id}/edit`)} />
          <Popconfirm
            title="Xoa site nay?"
            description="Neu site con cell, thao tac se bi tu choi."
            onConfirm={() => handleDelete(r.id)}
          >
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    { title: 'Mien', dataIndex: 'mien', fixed: 'left', width: 70,
      sorter: (a, b) => (a.mien||'').localeCompare(b.mien||'') },
    { title: 'Tinh', dataIndex: 'tinh', fixed: 'left', width: 160,
      sorter: (a, b) => (a.tinh||'').localeCompare(b.tinh||'') },
    { title: 'Phuong xa',      dataIndex: 'phuong_xa',    width: 160 },
    { title: 'Site name (cu)', dataIndex: 'site_name_cu', width: 200,
      ellipsis: { showTitle: true } },
    { title: 'Site name', dataIndex: 'site_name', fixed: 'left', width: 220,
      sorter: (a, b) => (a.site_name||'').localeCompare(b.site_name||''),
      render: (v: string) => <strong>{v}</strong> },
    { title: 'Site VIP', dataIndex: 'site_vip', width: 90,
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-' },
    { title: 'Lat',  dataIndex: 'lat',  width: 110 },
    { title: 'Long', dataIndex: 'long', width: 110 },
    { title: 'Tram 2G', dataIndex: 'tram_2g', width: 80, render: boolCell },
    { title: 'Tram 3G', dataIndex: 'tram_3g', width: 80, render: boolCell },
    { title: 'Tram 4G', dataIndex: 'tram_4g', width: 80, render: boolCell },
    { title: 'Tram 5G', dataIndex: 'tram_5g', width: 80, render: boolCell },
    { title: 'Repeater', dataIndex: 'repeater', width: 90, render: boolCell },
    { title: 'Booster',  dataIndex: 'booster',  width: 85, render: boolCell },
    { title: 'Node truyen dan only',
      dataIndex: 'node_truyen_dan_only', width: 160, render: boolCell },
    { title: 'Tram phu song TSCA',
      dataIndex: 'tram_phu_song_tsca', width: 160, render: boolCell },
    { title: 'Phan loai tram', dataIndex: 'phan_loai_tram', width: 180 },
    { title: 'MORAN 3G', dataIndex: 'moran_3g', width: 120 },
    { title: 'MORAN 4G', dataIndex: 'moran_4g', width: 120 },
    { title: 'MORAN 5G', dataIndex: 'moran_5g', width: 120 },
    { title: 'Ma PTM',   dataIndex: 'ma_ptm',   width: 120 },
    { title: 'Do cao dinh cot anten (m)',
      dataIndex: 'do_cao_dinh_cot_anten', width: 190 },
    { title: 'Do cao cot anten mat san (m)',
      dataIndex: 'do_cao_cot_anten', width: 210 },
    { title: 'Dia chi', dataIndex: 'dia_chi', width: 200,
      ellipsis: { showTitle: true } },
    { title: 'Ghi chu', dataIndex: 'ghi_chu', width: 200,
      ellipsis: { showTitle: true } },
  ]

  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>
          Quan ly Site
        </Typography.Title>
        <Space>
          <Tooltip title="Xuat du lieu hien tai ra Excel">
            <Button
              icon={<DownloadOutlined />}
              loading={exporting}
              onClick={handleExport}
              style={{ borderColor: '#52c41a', color: '#52c41a' }}
            >
              Xuat Excel ({sites.length})
            </Button>
          </Tooltip>
          <Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>
            Import Excel
          </Button>
          <Button type="primary" icon={<PlusOutlined />}
                  onClick={() => navigate('/sites/new')}>
            Them moi
          </Button>
        </Space>
      </Row>

      {loadError && (
        <Alert message={loadError} type="error" showIcon closable
               style={{ marginBottom: 12 }} onClose={() => setLoadError(null)} />
      )}

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} placeholder="Tim site name..."
                 value={search} onChange={(e) => setSearch(e.target.value)}
                 allowClear />
        </Col>
        <Col>
          <Select placeholder="Mien" allowClear style={{ width: 90 }}
                  value={mien} onChange={setMien}>
            {['MB','MT','MN'].map((m) =>
              <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="200px">
          <Select placeholder="Tinh" allowClear showSearch style={{ width: '100%' }}
                  value={tinh} onChange={setTinh}
                  filterOption={(input, opt) =>
                    String(opt?.children ?? '').toLowerCase()
                      .includes(input.toLowerCase())}>
            {tinhOptions.map((t) =>
              <Select.Option key={t} value={t}>{t}</Select.Option>)}
          </Select>
        </Col>
        <Col>
          <Button onClick={() => {
            setSearch(''); setMien(undefined); setTinh(undefined)
          }}>
            Xoa loc
          </Button>
        </Col>
        <Col>
          <Button onClick={load} loading={loading}>Lam moi</Button>
        </Col>
      </Row>

      <Table
        columns={columns}
        dataSource={sites}
        rowKey="id"
        loading={loading}
        size="small"
        scroll={{ x: scrollX, y: 600 }}
        bordered
        pagination={{
          pageSize: 50,
          showTotal: (t) => `${t} sites`,
          showSizeChanger: true,
        }}
      />

      <DryRunModal
        open={dryRunOpen}
        onClose={() => setDryRunOpen(false)}
        title="Import Site tu Excel"
        templateKey="site"
        dryRunFn={dryRunSitesExcel}
        importFn={importSitesExcel}
        onSuccess={load}
      />
    </div>
  )
}
TSXEOF

echo "    ✓ SitesPage.tsx updated"

# ── Step 5: Update Cells3GPage ────────────────────────────────────────────────
echo "[5/8] Updating Cells3GPage.tsx with export button..."

cat > frontend/src/pages/cells/Cells3GPage.tsx << 'TSXEOF'
import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, message, Row, Col,
  Modal, Form, InputNumber, Tooltip,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, SearchOutlined, UploadOutlined,
  EditOutlined, DeleteOutlined, DownloadOutlined,
} from '@ant-design/icons'
import { cells3gApi } from '@/api/cells'
import { exportCells3G } from '@/api/export'
import type { Cell3G, Site, AntennaItem } from '@/types'
import { getSites } from '@/api/sites'
import { getAntennaList } from '@/api/report'
import DryRunModal from '@/components/shared/DryRunModal'
import { latValidator, lonValidator, azimuthValidator } from '@/utils/validators'

export default function Cells3GPage() {
  const [data,        setData]        = useState<Cell3G[]>([])
  const [loading,     setLoading]     = useState(false)
  const [exporting,   setExporting]   = useState(false)
  const [search,      setSearch]      = useState('')
  const [mien,        setMien]        = useState<string | undefined>()
  const [tinh,        setTinh]        = useState<string | undefined>()
  const [vendor,      setVendor]      = useState<string | undefined>()
  const [sites,       setSites]       = useState<Site[]>([])
  const [antennaList, setAntennaList] = useState<AntennaItem[]>([])
  const [modalOpen,   setModalOpen]   = useState(false)
  const [editing,     setEditing]     = useState<Cell3G | null>(null)
  const [dryRunOpen,  setDryRunOpen]  = useState(false)
  const [form] = Form.useForm()

  const tinhOptions   = [...new Set(data.map((c) => c.tinh).filter(Boolean))].sort() as string[]
  const vendorOptions = [...new Set(data.map((c) => c.vendor).filter(Boolean))].sort() as string[]

  const load = async () => {
    setLoading(true)
    try {
      setData(await cells3gApi.list({
        search: search || undefined, mien: mien || undefined,
        tinh: tinh || undefined, vendor: vendor || undefined, limit: 1000,
      }))
    } finally { setLoading(false) }
  }

  useEffect(() => {
    load()
    getSites({ limit: 2000 }).then(setSites)
    getAntennaList().then(setAntennaList)
  }, [search, mien, tinh, vendor])

  const handleExport = async () => {
    setExporting(true)
    try {
      await exportCells3G({
        search: search || undefined, mien: mien || undefined,
        tinh: tinh || undefined, vendor: vendor || undefined,
      })
      message.success(`Xuat Excel thanh cong (${data.length} cells)`)
    } catch (e: any) {
      message.error(e?.message || 'Xuat that bai')
    } finally { setExporting(false) }
  }

  const handleSiteSelect = (siteId: number) => {
    const site = sites.find((s) => s.id === siteId)
    if (site) form.setFieldValue('site_name', site.site_name)
  }

  const handleAntennaSelect = (antennaName: string) => {
    const ant = antennaList.find((a) => a.name === antennaName)
    if (!ant) return
    form.setFieldsValue({ loai_anten: ant.name })
  }

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (r: Cell3G) => { setEditing(r); form.setFieldsValue(r); setModalOpen(true) }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) {
        await cells3gApi.update(editing.id, values)
        message.success('Cap nhat thanh cong')
      } else {
        await cells3gApi.create(values)
        message.success('Tao cell thanh cong')
      }
      setModalOpen(false); load()
    } catch (e: any) { message.error(e.response?.data?.detail || 'Loi') }
  }

  const handleDelete = async (id: number) => {
    await cells3gApi.remove(id); message.success('Da xoa'); load()
  }

  const columns: ColumnsType<Cell3G> = [
    {
      title: 'Hanh dong', key: 'action', fixed: 'left', width: 80,
      render: (_: unknown, r: Cell3G) => (
        <Space>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xoa cell nay?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    { title: 'Mien',      dataIndex: 'mien',      fixed: 'left', width: 70  },
    { title: 'Tinh',      dataIndex: 'tinh',      fixed: 'left', width: 160 },
    { title: 'Phuong xa', dataIndex: 'phuong_xa',               width: 160 },
    { title: 'Site Name', dataIndex: 'site_name', fixed: 'left', width: 240,
      ellipsis: { showTitle: true }, render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell Name', dataIndex: 'cell_name', fixed: 'left', width: 240,
      ellipsis: { showTitle: true }, render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell VIP', dataIndex: 'cell_vip', width: 90,
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-' },
    { title: 'MORAN',         dataIndex: 'moran',         width: 120 },
    { title: 'Lat',           dataIndex: 'lat',           width: 110 },
    { title: 'Long',          dataIndex: 'long',          width: 110 },
    { title: 'Vung phu song', dataIndex: 'vung_phu_song', width: 120 },
    { title: 'Vendor',        dataIndex: 'vendor',        width: 100 },
    { title: 'Do cao anten',  dataIndex: 'do_cao_anten',  width: 120 },
    { title: 'Azimuth',       dataIndex: 'azimuth',       width: 90  },
    { title: 'M-tilt',        dataIndex: 'm_tilt',        width: 80  },
    { title: 'E-Tilt',        dataIndex: 'e_tilt',        width: 80  },
    { title: 'Total Tilt',    dataIndex: 'total_tilt',    width: 100 },
    { title: 'Loai Anten',    dataIndex: 'loai_anten',    width: 250,
      ellipsis: { showTitle: true } },
    { title: 'Chung anten',   dataIndex: 'chung_anten',   width: 120 },
    { title: 'Baseband',      dataIndex: 'baseband',      width: 120 },
    { title: 'RF',            dataIndex: 'rf',            width: 100 },
    { title: 'Cell ID',       dataIndex: 'cell_id',       width: 100 },
    { title: 'ARFCN',         dataIndex: 'arfcn',         width: 90  },
    { title: 'PSC',           dataIndex: 'psc',           width: 80  },
    { title: 'MIMO', dataIndex: 'mimo', width: 80,
      render: (v: string) => v ? <Tag color="blue">{v}</Tag> : '-' },
  ]
  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Cell 3G</Typography.Title>
        <Space>
          <Tooltip title="Xuat du lieu hien tai ra Excel">
            <Button icon={<DownloadOutlined />} loading={exporting}
                    onClick={handleExport}
                    style={{ borderColor: '#52c41a', color: '#52c41a' }}>
              Xuat Excel ({data.length})
            </Button>
          </Tooltip>
          <Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>
            Import Excel
          </Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
            Them moi
          </Button>
        </Space>
      </Row>

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} placeholder="Tim cell / site name..."
                 value={search} onChange={(e) => setSearch(e.target.value)} allowClear />
        </Col>
        <Col>
          <Select placeholder="Mien" allowClear style={{ width: 90 }}
                  value={mien} onChange={setMien}>
            {['MB','MT','MN'].map((m) =>
              <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="180px">
          <Select placeholder="Tinh" allowClear showSearch style={{ width: '100%' }}
                  value={tinh} onChange={setTinh}
                  filterOption={(i, o) =>
                    String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
            {tinhOptions.map((t) =>
              <Select.Option key={t} value={t}>{t}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="160px">
          <Select placeholder="Vendor" allowClear style={{ width: '100%' }}
                  value={vendor} onChange={setVendor}>
            {vendorOptions.map((v) =>
              <Select.Option key={v} value={v}>{v}</Select.Option>)}
          </Select>
        </Col>
        <Col>
          <Button onClick={() => {
            setSearch(''); setMien(undefined)
            setTinh(undefined); setVendor(undefined)
          }}>
            Xoa loc
          </Button>
        </Col>
      </Row>

      <Table columns={columns} dataSource={data} rowKey="id" loading={loading}
             size="small" scroll={{ x: scrollX, y: 600 }} bordered
             pagination={{ pageSize: 50, showTotal: (t) => `${t} cells`,
                           showSizeChanger: true }} />

      <Modal title={editing ? 'Chinh sua Cell 3G' : 'Them Cell 3G moi'}
             open={modalOpen} onOk={handleSave} onCancel={() => setModalOpen(false)}
             width={800} okText="Luu" destroyOnClose>
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={12}>
              <Form.Item name="site_id" label="Site" rules={[{ required: true }]}>
                <Select showSearch optionFilterProp="children" allowClear
                        placeholder="Chon site..." onChange={handleSiteSelect}
                        filterOption={(i, o) =>
                          String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                  {sites.map((s) =>
                    <Select.Option key={s.id} value={s.id}>{s.site_name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="site_name" label="Site Name (tu dong dien)">
                <Input readOnly style={{ background: '#f5f5f5' }} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="cell_name" label="Cell Name" rules={[{ required: true }]}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="cell_vip" label="Cell VIP">
                <Select allowClear>
                  <Select.Option value="VIP">VIP</Select.Option>
                  <Select.Option value="VVIP">VVIP</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="moran" label="MORAN">
                <Select allowClear>
                  <Select.Option value="VNPT HOST">VNPT HOST</Select.Option>
                  <Select.Option value="MBF HOST">MBF HOST</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="lat" label="Lat (8.33 – 23.39)"
                         rules={[{ validator: latValidator }]}>
                <InputNumber style={{ width: '100%' }} precision={5}
                             placeholder="8.33 – 23.39" />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="long" label="Long (102.14 – 109.47)"
                         rules={[{ validator: lonValidator }]}>
                <InputNumber style={{ width: '100%' }} precision={5}
                             placeholder="102.14 – 109.47" />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="vung_phu_song" label="Vung phu song">
                <Select allowClear>
                  <Select.Option value="Indoor">Indoor</Select.Option>
                  <Select.Option value="Outdoor">Outdoor</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="vendor" label="Vendor">
                <Select allowClear>
                  {['Ericsson','Nokia','Huawei','ZTE','Samsung'].map((v) =>
                    <Select.Option key={v} value={v}>{v}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="do_cao_anten" label="Do cao anten (m)">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="azimuth" label="Azimuth (0 – 359)"
                         rules={[{ validator: azimuthValidator }]}>
                <InputNumber style={{ width: '100%' }} min={0} max={359} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="m_tilt" label="M-tilt">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="e_tilt" label="E-Tilt">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="total_tilt" label="Total Tilt">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={24}>
              <Form.Item name="loai_anten" label="Loai Anten">
                <Select showSearch allowClear placeholder="Chon loai anten..."
                        onChange={handleAntennaSelect}
                        filterOption={(i, o) =>
                          String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                  {antennaList.map((a) =>
                    <Select.Option key={a.id} value={a.name}>{a.name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="chung_anten" label="Chung anten"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="baseband" label="Baseband"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="rf" label="RF"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="cell_id" label="Cell ID"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="arfcn" label="ARFCN"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="psc" label="PSC"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="mimo" label="MIMO">
                <Select allowClear>
                  {['2x2','4x4','8x8'].map((m) =>
                    <Select.Option key={m} value={m}>{m}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
          </Row>
        </Form>
      </Modal>

      <DryRunModal
        open={dryRunOpen}
        onClose={() => setDryRunOpen(false)}
        title="Import Cell 3G tu Excel"
        templateKey="cell-3g"
        dryRunFn={cells3gApi.dryRunExcel}
        importFn={cells3gApi.importExcel}
        onSuccess={load}
      />
    </div>
  )
}
TSXEOF

echo "    ✓ Cells3GPage.tsx updated"

# ── Step 6: Update Cells4GPage ────────────────────────────────────────────────
echo "[6/8] Updating Cells4GPage.tsx with export button..."

cat > frontend/src/pages/cells/Cells4GPage.tsx << 'TSXEOF'
import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, message, Row, Col,
  Modal, Form, InputNumber, Tooltip,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, SearchOutlined, UploadOutlined,
  EditOutlined, DeleteOutlined, DownloadOutlined,
} from '@ant-design/icons'
import { cells4gApi } from '@/api/cells'
import { exportCells4G } from '@/api/export'
import type { Cell4G, Site, AntennaItem } from '@/types'
import { getSites } from '@/api/sites'
import { getAntennaList } from '@/api/report'
import DryRunModal from '@/components/shared/DryRunModal'
import { latValidator, lonValidator, azimuthValidator } from '@/utils/validators'

export default function Cells4GPage() {
  const [data,        setData]        = useState<Cell4G[]>([])
  const [loading,     setLoading]     = useState(false)
  const [exporting,   setExporting]   = useState(false)
  const [search,      setSearch]      = useState('')
  const [mien,        setMien]        = useState<string | undefined>()
  const [tinh,        setTinh]        = useState<string | undefined>()
  const [vendor,      setVendor]      = useState<string | undefined>()
  const [sites,       setSites]       = useState<Site[]>([])
  const [antennaList, setAntennaList] = useState<AntennaItem[]>([])
  const [modalOpen,   setModalOpen]   = useState(false)
  const [editing,     setEditing]     = useState<Cell4G | null>(null)
  const [dryRunOpen,  setDryRunOpen]  = useState(false)
  const [form] = Form.useForm()

  const tinhOptions   = [...new Set(data.map((c) => c.tinh).filter(Boolean))].sort() as string[]
  const vendorOptions = [...new Set(data.map((c) => c.vendor).filter(Boolean))].sort() as string[]

  const load = async () => {
    setLoading(true)
    try {
      setData(await cells4gApi.list({
        search: search || undefined, mien: mien || undefined,
        tinh: tinh || undefined, vendor: vendor || undefined, limit: 1000,
      }))
    } finally { setLoading(false) }
  }

  useEffect(() => {
    load()
    getSites({ limit: 2000 }).then(setSites)
    getAntennaList().then(setAntennaList)
  }, [search, mien, tinh, vendor])

  const handleExport = async () => {
    setExporting(true)
    try {
      await exportCells4G({
        search: search || undefined, mien: mien || undefined,
        tinh: tinh || undefined, vendor: vendor || undefined,
      })
      message.success(`Xuat Excel thanh cong (${data.length} cells)`)
    } catch (e: any) {
      message.error(e?.message || 'Xuat that bai')
    } finally { setExporting(false) }
  }

  const handleSiteSelect = (siteId: number) => {
    const site = sites.find((s) => s.id === siteId)
    if (site) form.setFieldValue('site_name', site.site_name)
  }

  const handleAntennaSelect = (antennaName: string) => {
    const ant = antennaList.find((a) => a.name === antennaName)
    if (!ant) return
    form.setFieldsValue({ loai_anten: ant.name })
  }

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (r: Cell4G) => { setEditing(r); form.setFieldsValue(r); setModalOpen(true) }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) {
        await cells4gApi.update(editing.id, values)
        message.success('Cap nhat thanh cong')
      } else {
        await cells4gApi.create(values)
        message.success('Tao cell thanh cong')
      }
      setModalOpen(false); load()
    } catch (e: any) { message.error(e.response?.data?.detail || 'Loi') }
  }

  const handleDelete = async (id: number) => {
    await cells4gApi.remove(id); message.success('Da xoa'); load()
  }

  const columns: ColumnsType<Cell4G> = [
    {
      title: 'Hanh dong', key: 'action', fixed: 'left', width: 80,
      render: (_: unknown, r: Cell4G) => (
        <Space>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xoa cell nay?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    { title: 'Mien',      dataIndex: 'mien',      fixed: 'left', width: 70  },
    { title: 'Tinh',      dataIndex: 'tinh',      fixed: 'left', width: 160 },
    { title: 'Phuong xa', dataIndex: 'phuong_xa',               width: 160 },
    { title: 'Site Name', dataIndex: 'site_name', fixed: 'left', width: 240,
      ellipsis: { showTitle: true }, render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell Name', dataIndex: 'cell_name', fixed: 'left', width: 240,
      ellipsis: { showTitle: true }, render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell VIP', dataIndex: 'cell_vip', width: 90,
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-' },
    { title: 'MORAN',            dataIndex: 'moran',            width: 120 },
    { title: 'Lat',              dataIndex: 'lat',              width: 110 },
    { title: 'Long',             dataIndex: 'long',             width: 110 },
    { title: 'Vung phu song',    dataIndex: 'vung_phu_song',    width: 120 },
    { title: 'Vendor',           dataIndex: 'vendor',           width: 100 },
    { title: 'Do cao anten',     dataIndex: 'do_cao_anten',     width: 120 },
    { title: 'Azimuth',          dataIndex: 'azimuth',          width: 90  },
    { title: 'M-tilt',           dataIndex: 'm_tilt',           width: 80  },
    { title: 'E-Tilt',           dataIndex: 'e_tilt',           width: 80  },
    { title: 'Total Tilt',       dataIndex: 'total_tilt',       width: 100 },
    { title: 'Loai Anten',       dataIndex: 'loai_anten',       width: 200 },
    { title: 'Chung anten',      dataIndex: 'chung_anten',      width: 120 },
    { title: 'Baseband',         dataIndex: 'baseband',         width: 120 },
    { title: 'RF',               dataIndex: 'rf',               width: 100 },
    { title: 'Cell ID',          dataIndex: 'cell_id',          width: 100 },
    { title: 'EARFCN',           dataIndex: 'earfcn',           width: 90  },
    { title: 'PCI',              dataIndex: 'pci',              width: 80  },
    { title: 'Root Sequence ID', dataIndex: 'root_sequence_id', width: 150 },
    { title: 'MIMO', dataIndex: 'mimo', width: 80,
      render: (v: string) => v ? <Tag color="blue">{v}</Tag> : '-' },
  ]
  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Cell 4G</Typography.Title>
        <Space>
          <Tooltip title="Xuat du lieu hien tai ra Excel">
            <Button icon={<DownloadOutlined />} loading={exporting}
                    onClick={handleExport}
                    style={{ borderColor: '#52c41a', color: '#52c41a' }}>
              Xuat Excel ({data.length})
            </Button>
          </Tooltip>
          <Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>
            Import Excel
          </Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
            Them moi
          </Button>
        </Space>
      </Row>

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} placeholder="Tim cell / site name..."
                 value={search} onChange={(e) => setSearch(e.target.value)} allowClear />
        </Col>
        <Col>
          <Select placeholder="Mien" allowClear style={{ width: 90 }}
                  value={mien} onChange={setMien}>
            {['MB','MT','MN'].map((m) =>
              <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="180px">
          <Select placeholder="Tinh" allowClear showSearch style={{ width: '100%' }}
                  value={tinh} onChange={setTinh}
                  filterOption={(i, o) =>
                    String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
            {tinhOptions.map((t) =>
              <Select.Option key={t} value={t}>{t}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="160px">
          <Select placeholder="Vendor" allowClear style={{ width: '100%' }}
                  value={vendor} onChange={setVendor}>
            {vendorOptions.map((v) =>
              <Select.Option key={v} value={v}>{v}</Select.Option>)}
          </Select>
        </Col>
        <Col>
          <Button onClick={() => {
            setSearch(''); setMien(undefined)
            setTinh(undefined); setVendor(undefined)
          }}>
            Xoa loc
          </Button>
        </Col>
      </Row>

      <Table columns={columns} dataSource={data} rowKey="id" loading={loading}
             size="small" scroll={{ x: scrollX, y: 600 }} bordered
             pagination={{ pageSize: 50, showTotal: (t) => `${t} cells`,
                           showSizeChanger: true }} />

      <Modal title={editing ? 'Chinh sua Cell 4G' : 'Them Cell 4G moi'}
             open={modalOpen} onOk={handleSave} onCancel={() => setModalOpen(false)}
             width={800} okText="Luu" destroyOnClose>
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={12}>
              <Form.Item name="site_id" label="Site" rules={[{ required: true }]}>
                <Select showSearch optionFilterProp="children" allowClear
                        placeholder="Chon site..." onChange={handleSiteSelect}
                        filterOption={(i, o) =>
                          String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                  {sites.map((s) =>
                    <Select.Option key={s.id} value={s.id}>{s.site_name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="site_name" label="Site Name (tu dong dien)">
                <Input readOnly style={{ background: '#f5f5f5' }} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="cell_name" label="Cell Name" rules={[{ required: true }]}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="cell_vip" label="Cell VIP">
                <Select allowClear>
                  <Select.Option value="VIP">VIP</Select.Option>
                  <Select.Option value="VVIP">VVIP</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="moran" label="MORAN">
                <Select allowClear>
                  <Select.Option value="VNPT HOST">VNPT HOST</Select.Option>
                  <Select.Option value="MBF HOST">MBF HOST</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="lat" label="Lat (8.33 – 23.39)"
                         rules={[{ validator: latValidator }]}>
                <InputNumber style={{ width: '100%' }} precision={5}
                             placeholder="8.33 – 23.39" />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="long" label="Long (102.14 – 109.47)"
                         rules={[{ validator: lonValidator }]}>
                <InputNumber style={{ width: '100%' }} precision={5}
                             placeholder="102.14 – 109.47" />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="vung_phu_song" label="Vung phu song">
                <Select allowClear>
                  <Select.Option value="Indoor">Indoor</Select.Option>
                  <Select.Option value="Outdoor">Outdoor</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="vendor" label="Vendor">
                <Select allowClear>
                  {['Ericsson','Nokia','Huawei','ZTE','Samsung'].map((v) =>
                    <Select.Option key={v} value={v}>{v}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="do_cao_anten" label="Do cao anten (m)">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="azimuth" label="Azimuth (0 – 359)"
                         rules={[{ validator: azimuthValidator }]}>
                <InputNumber style={{ width: '100%' }} min={0} max={359} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="m_tilt" label="M-tilt">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="e_tilt" label="E-Tilt">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="total_tilt" label="Total Tilt">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={24}>
              <Form.Item name="loai_anten" label="Loai Anten">
                <Select showSearch allowClear placeholder="Chon loai anten..."
                        onChange={handleAntennaSelect}
                        filterOption={(i, o) =>
                          String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                  {antennaList.map((a) =>
                    <Select.Option key={a.id} value={a.name}>{a.name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="chung_anten" label="Chung anten"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="baseband" label="Baseband"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="rf" label="RF"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="cell_id" label="Cell ID"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="earfcn" label="EARFCN"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="pci" label="PCI"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="root_sequence_id" label="Root Sequence ID">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="mimo" label="MIMO">
                <Select allowClear>
                  {['2x2','4x4','8x8'].map((m) =>
                    <Select.Option key={m} value={m}>{m}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
          </Row>
        </Form>
      </Modal>

      <DryRunModal
        open={dryRunOpen}
        onClose={() => setDryRunOpen(false)}
        title="Import Cell 4G tu Excel"
        templateKey="cell-4g"
        dryRunFn={cells4gApi.dryRunExcel}
        importFn={cells4gApi.importExcel}
        onSuccess={load}
      />
    </div>
  )
}
TSXEOF

echo "    ✓ Cells4GPage.tsx updated"

# ── Step 7: Update Cells5GPage ────────────────────────────────────────────────
echo "[7/8] Updating Cells5GPage.tsx with export button..."

cat > frontend/src/pages/cells/Cells5GPage.tsx << 'TSXEOF'
import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, message, Row, Col,
  Modal, Form, InputNumber, Tooltip,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, SearchOutlined, UploadOutlined,
  EditOutlined, DeleteOutlined, DownloadOutlined,
} from '@ant-design/icons'
import { cells5gApi } from '@/api/cells'
import { exportCells5G } from '@/api/export'
import type { Cell5G, Site, AntennaItem } from '@/types'
import { getSites } from '@/api/sites'
import { getAntennaList } from '@/api/report'
import DryRunModal from '@/components/shared/DryRunModal'
import { latValidator, lonValidator, azimuthValidator } from '@/utils/validators'

export default function Cells5GPage() {
  const [data,        setData]        = useState<Cell5G[]>([])
  const [loading,     setLoading]     = useState(false)
  const [exporting,   setExporting]   = useState(false)
  const [search,      setSearch]      = useState('')
  const [mien,        setMien]        = useState<string | undefined>()
  const [tinh,        setTinh]        = useState<string | undefined>()
  const [vendor,      setVendor]      = useState<string | undefined>()
  const [sites,       setSites]       = useState<Site[]>([])
  const [antennaList, setAntennaList] = useState<AntennaItem[]>([])
  const [modalOpen,   setModalOpen]   = useState(false)
  const [editing,     setEditing]     = useState<Cell5G | null>(null)
  const [dryRunOpen,  setDryRunOpen]  = useState(false)
  const [form] = Form.useForm()

  const tinhOptions   = [...new Set(data.map((c) => c.tinh).filter(Boolean))].sort() as string[]
  const vendorOptions = [...new Set(data.map((c) => c.vendor).filter(Boolean))].sort() as string[]

  const load = async () => {
    setLoading(true)
    try {
      setData(await cells5gApi.list({
        search: search || undefined, mien: mien || undefined,
        tinh: tinh || undefined, vendor: vendor || undefined, limit: 1000,
      }))
    } finally { setLoading(false) }
  }

  useEffect(() => {
    load()
    getSites({ limit: 2000 }).then(setSites)
    getAntennaList().then(setAntennaList)
  }, [search, mien, tinh, vendor])

  const handleExport = async () => {
    setExporting(true)
    try {
      await exportCells5G({
        search: search || undefined, mien: mien || undefined,
        tinh: tinh || undefined, vendor: vendor || undefined,
      })
      message.success(`Xuat Excel thanh cong (${data.length} cells)`)
    } catch (e: any) {
      message.error(e?.message || 'Xuat that bai')
    } finally { setExporting(false) }
  }

  const handleSiteSelect = (siteId: number) => {
    const site = sites.find((s) => s.id === siteId)
    if (site) form.setFieldValue('site_name', site.site_name)
  }

  const handleAntennaSelect = (antennaName: string) => {
    const ant = antennaList.find((a) => a.name === antennaName)
    if (!ant) return
    form.setFieldsValue({ loai_anten: ant.name })
  }

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (r: Cell5G) => { setEditing(r); form.setFieldsValue(r); setModalOpen(true) }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) {
        await cells5gApi.update(editing.id, values)
        message.success('Cap nhat thanh cong')
      } else {
        await cells5gApi.create(values)
        message.success('Tao cell thanh cong')
      }
      setModalOpen(false); load()
    } catch (e: any) { message.error(e.response?.data?.detail || 'Loi') }
  }

  const handleDelete = async (id: number) => {
    await cells5gApi.remove(id); message.success('Da xoa'); load()
  }

  const columns: ColumnsType<Cell5G> = [
    {
      title: 'Hanh dong', key: 'action', fixed: 'left', width: 80,
      render: (_: unknown, r: Cell5G) => (
        <Space>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xoa cell nay?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    { title: 'Mien',      dataIndex: 'mien',      fixed: 'left', width: 70  },
    { title: 'Tinh',      dataIndex: 'tinh',      fixed: 'left', width: 160 },
    { title: 'Phuong xa', dataIndex: 'phuong_xa',               width: 160 },
    { title: 'Site Name', dataIndex: 'site_name', fixed: 'left', width: 240,
      ellipsis: { showTitle: true }, render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell Name', dataIndex: 'cell_name', fixed: 'left', width: 240,
      ellipsis: { showTitle: true }, render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell VIP', dataIndex: 'cell_vip', width: 90,
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-' },
    { title: 'MORAN',            dataIndex: 'moran',            width: 120 },
    { title: 'Lat',              dataIndex: 'lat',              width: 110 },
    { title: 'Long',             dataIndex: 'long',             width: 110 },
    { title: 'Vung phu song',    dataIndex: 'vung_phu_song',    width: 120 },
    { title: 'Vendor',           dataIndex: 'vendor',           width: 100 },
    { title: 'Do cao anten',     dataIndex: 'do_cao_anten',     width: 120 },
    { title: 'Azimuth',          dataIndex: 'azimuth',          width: 90  },
    { title: 'M-tilt',           dataIndex: 'm_tilt',           width: 80  },
    { title: 'E-Tilt',           dataIndex: 'e_tilt',           width: 80  },
    { title: 'Total Tilt',       dataIndex: 'total_tilt',       width: 100 },
    { title: 'Loai Anten',       dataIndex: 'loai_anten',       width: 250,
      ellipsis: { showTitle: true } },
    { title: 'Baseband',         dataIndex: 'baseband',         width: 120 },
    { title: 'RF',               dataIndex: 'rf',               width: 100 },
    { title: 'Cell ID',          dataIndex: 'cell_id',          width: 100 },
    { title: 'NR-ARFCN',         dataIndex: 'nr_arfcn',         width: 100 },
    { title: 'PCI',              dataIndex: 'pci',              width: 80  },
    { title: 'Root Sequence ID', dataIndex: 'root_sequence_id', width: 150 },
    { title: 'MIMO', dataIndex: 'mimo', width: 80,
      render: (v: string) => v ? <Tag color="blue">{v}</Tag> : '-' },
  ]
  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Cell 5G</Typography.Title>
        <Space>
          <Tooltip title="Xuat du lieu hien tai ra Excel">
            <Button icon={<DownloadOutlined />} loading={exporting}
                    onClick={handleExport}
                    style={{ borderColor: '#52c41a', color: '#52c41a' }}>
              Xuat Excel ({data.length})
            </Button>
          </Tooltip>
          <Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>
            Import Excel
          </Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
            Them moi
          </Button>
        </Space>
      </Row>

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} placeholder="Tim cell / site name..."
                 value={search} onChange={(e) => setSearch(e.target.value)} allowClear />
        </Col>
        <Col>
          <Select placeholder="Mien" allowClear style={{ width: 90 }}
                  value={mien} onChange={setMien}>
            {['MB','MT','MN'].map((m) =>
              <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="180px">
          <Select placeholder="Tinh" allowClear showSearch style={{ width: '100%' }}
                  value={tinh} onChange={setTinh}
                  filterOption={(i, o) =>
                    String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
            {tinhOptions.map((t) =>
              <Select.Option key={t} value={t}>{t}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="160px">
          <Select placeholder="Vendor" allowClear style={{ width: '100%' }}
                  value={vendor} onChange={setVendor}>
            {vendorOptions.map((v) =>
              <Select.Option key={v} value={v}>{v}</Select.Option>)}
          </Select>
        </Col>
        <Col>
          <Button onClick={() => {
            setSearch(''); setMien(undefined)
            setTinh(undefined); setVendor(undefined)
          }}>
            Xoa loc
          </Button>
        </Col>
      </Row>

      <Table columns={columns} dataSource={data} rowKey="id" loading={loading}
             size="small" scroll={{ x: scrollX, y: 600 }} bordered
             pagination={{ pageSize: 50, showTotal: (t) => `${t} cells`,
                           showSizeChanger: true }} />

      <Modal title={editing ? 'Chinh sua Cell 5G' : 'Them Cell 5G moi'}
             open={modalOpen} onOk={handleSave} onCancel={() => setModalOpen(false)}
             width={800} okText="Luu" destroyOnClose>
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={12}>
              <Form.Item name="site_id" label="Site" rules={[{ required: true }]}>
                <Select showSearch optionFilterProp="children" allowClear
                        placeholder="Chon site..." onChange={handleSiteSelect}
                        filterOption={(i, o) =>
                          String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                  {sites.map((s) =>
                    <Select.Option key={s.id} value={s.id}>{s.site_name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="site_name" label="Site Name (tu dong dien)">
                <Input readOnly style={{ background: '#f5f5f5' }} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="cell_name" label="Cell Name" rules={[{ required: true }]}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="cell_vip" label="Cell VIP">
                <Select allowClear>
                  <Select.Option value="VIP">VIP</Select.Option>
                  <Select.Option value="VVIP">VVIP</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="moran" label="MORAN">
                <Select allowClear>
                  <Select.Option value="VNPT HOST">VNPT HOST</Select.Option>
                  <Select.Option value="MBF HOST">MBF HOST</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="lat" label="Lat (8.33 – 23.39)"
                         rules={[{ validator: latValidator }]}>
                <InputNumber style={{ width: '100%' }} precision={5}
                             placeholder="8.33 – 23.39" />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="long" label="Long (102.14 – 109.47)"
                         rules={[{ validator: lonValidator }]}>
                <InputNumber style={{ width: '100%' }} precision={5}
                             placeholder="102.14 – 109.47" />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="vung_phu_song" label="Vung phu song">
                <Select allowClear>
                  <Select.Option value="Indoor">Indoor</Select.Option>
                  <Select.Option value="Outdoor">Outdoor</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="vendor" label="Vendor">
                <Select allowClear>
                  {['Ericsson','Nokia','Huawei','ZTE','Samsung'].map((v) =>
                    <Select.Option key={v} value={v}>{v}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="do_cao_anten" label="Do cao anten (m)">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="azimuth" label="Azimuth (0 – 359)"
                         rules={[{ validator: azimuthValidator }]}>
                <InputNumber style={{ width: '100%' }} min={0} max={359} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="m_tilt" label="M-tilt">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="e_tilt" label="E-Tilt">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="total_tilt" label="Total Tilt">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={24}>
              <Form.Item name="loai_anten" label="Loai Anten">
                <Select showSearch allowClear placeholder="Chon loai anten..."
                        onChange={handleAntennaSelect}
                        filterOption={(i, o) =>
                          String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                  {antennaList.map((a) =>
                    <Select.Option key={a.id} value={a.name}>{a.name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="baseband" label="Baseband"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="rf" label="RF"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="cell_id" label="Cell ID"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="nr_arfcn" label="NR-ARFCN"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="pci" label="PCI"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="root_sequence_id" label="Root Sequence ID">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="mimo" label="MIMO">
                <Select allowClear>
                  {['2x2','4x4','8x8'].map((m) =>
                    <Select.Option key={m} value={m}>{m}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
          </Row>
        </Form>
      </Modal>

      <DryRunModal
        open={dryRunOpen}
        onClose={() => setDryRunOpen(false)}
        title="Import Cell 5G tu Excel"
        templateKey="cell-5g"
        dryRunFn={cells5gApi.dryRunExcel}
        importFn={cells5gApi.importExcel}
        onSuccess={load}
      />
    </div>
  )
}
TSXEOF

echo "    ✓ Cells5GPage.tsx updated"

# ── Step 8: Update AntennaPage ────────────────────────────────────────────────
echo "[8/8] Updating AntennaPage.tsx with export button..."

cat > frontend/src/pages/antenna/AntennaPage.tsx << 'TSXEOF'
import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Popconfirm,
  message, Row, Col, Modal, Form, InputNumber, Tooltip,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, SearchOutlined, UploadOutlined,
  EditOutlined, DeleteOutlined, DownloadOutlined,
} from '@ant-design/icons'
import {
  getAntennas, createAntenna, updateAntenna,
  deleteAntenna, dryRunAntennaExcel, importAntennaExcel,
} from '@/api/antenna'
import { exportAntennas } from '@/api/export'
import type { AntennaFull } from '@/types'
import DryRunModal from '@/components/shared/DryRunModal'

export default function AntennaPage() {
  const [data,       setData]       = useState<AntennaFull[]>([])
  const [loading,    setLoading]    = useState(false)
  const [exporting,  setExporting]  = useState(false)
  const [search,     setSearch]     = useState('')
  const [modalOpen,  setModalOpen]  = useState(false)
  const [editing,    setEditing]    = useState<AntennaFull | null>(null)
  const [dryRunOpen, setDryRunOpen] = useState(false)
  const [detailOpen, setDetailOpen] = useState(false)
  const [selected,   setSelected]   = useState<AntennaFull | null>(null)
  const [form] = Form.useForm()

  const load = async () => {
    setLoading(true)
    try {
      setData(await getAntennas({ search: search || undefined, limit: 2000 }))
    } finally { setLoading(false) }
  }

  useEffect(() => { load() }, [search])

  const handleExport = async () => {
    setExporting(true)
    try {
      await exportAntennas({ search: search || undefined })
      message.success(`Xuat Excel thanh cong (${data.length} antennas)`)
    } catch (e: any) {
      message.error(e?.message || 'Xuat that bai')
    } finally { setExporting(false) }
  }

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (r: AntennaFull) => {
    setEditing(r); form.setFieldsValue(r); setModalOpen(true)
  }
  const openDetail = (r: AntennaFull) => { setSelected(r); setDetailOpen(true) }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) {
        await updateAntenna(editing.id, values)
        message.success('Cap nhat thanh cong')
      } else {
        await createAntenna(values)
        message.success('Tao antenna thanh cong')
      }
      setModalOpen(false); load()
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Loi')
    }
  }

  const handleDelete = async (id: number) => {
    await deleteAntenna(id); message.success('Da xoa'); load()
  }

  const columns: ColumnsType<AntennaFull> = [
    {
      title: 'Hanh dong', key: 'action', fixed: 'left', width: 100,
      render: (_: unknown, r: AntennaFull) => (
        <Space>
          <Button size="small" onClick={() => openDetail(r)}>Chi tiet</Button>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xoa antenna nay?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    { title: 'Name',           dataIndex: 'name',           fixed: 'left', width: 280,
      render: (v: string) => <strong>{v}</strong> },
    { title: 'Band',           dataIndex: 'band',           width: 150 },
    { title: 'No of Ports',    dataIndex: 'no_of_ports',    width: 110 },
    { title: 'No of Beam',     dataIndex: 'no_of_beam',     width: 110 },
    { title: 'Horizontal BW',  dataIndex: 'horizontal_bw',  width: 120 },
    { title: 'Vertical BW',    dataIndex: 'vertical_bw',    width: 110 },
    { title: 'Gain',           dataIndex: 'gain',           width: 80  },
    { title: 'Etilt',          dataIndex: 'etilt',          width: 90  },
    { title: 'H (mm)',         dataIndex: 'h',              width: 90  },
    { title: 'W (mm)',         dataIndex: 'w',              width: 90  },
    { title: 'D (mm)',         dataIndex: 'd',              width: 90  },
    { title: 'Weight',         dataIndex: 'weight',         width: 90  },
    { title: 'Connector type', dataIndex: 'connector_type', width: 160 },
    { title: 'Ghi chu',        dataIndex: 'ghi_chu',        width: 200 },
  ]
  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>
          Quan ly Antenna
        </Typography.Title>
        <Space>
          <Tooltip title="Xuat du lieu hien tai ra Excel">
            <Button icon={<DownloadOutlined />} loading={exporting}
                    onClick={handleExport}
                    style={{ borderColor: '#52c41a', color: '#52c41a' }}>
              Xuat Excel ({data.length})
            </Button>
          </Tooltip>
          <Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>
            Import Excel
          </Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
            Them moi
          </Button>
        </Space>
      </Row>

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="320px">
          <Input prefix={<SearchOutlined />} placeholder="Tim ten antenna..."
                 value={search} onChange={(e) => setSearch(e.target.value)} allowClear />
        </Col>
        <Col>
          <Button onClick={() => setSearch('')}>Xoa loc</Button>
        </Col>
        <Col>
          <Button onClick={load} loading={loading}>Lam moi</Button>
        </Col>
      </Row>

      <Table columns={columns} dataSource={data} rowKey="id" loading={loading}
             size="small" scroll={{ x: scrollX, y: 600 }} bordered
             pagination={{ pageSize: 50, showTotal: (t) => `${t} antennas`,
                           showSizeChanger: true }} />

      {/* Detail modal */}
      <Modal title={selected?.name} open={detailOpen}
             onCancel={() => setDetailOpen(false)} footer={null} width={600}>
        {selected && (
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            {([
              ['Band',           selected.band],
              ['No of Ports',    selected.no_of_ports],
              ['No of Beam',     selected.no_of_beam],
              ['Horizontal BW',  selected.horizontal_bw],
              ['Vertical BW',    selected.vertical_bw],
              ['Gain',           selected.gain],
              ['Etilt',          selected.etilt],
              ['H (mm)',         selected.h],
              ['W (mm)',         selected.w],
              ['D (mm)',         selected.d],
              ['Weight',         selected.weight],
              ['Connector type', selected.connector_type],
              ['Ghi chu',        selected.ghi_chu],
            ] as [string, unknown][]).map(([label, val]) => (
              <tr key={label} style={{ borderBottom: '1px solid #f0f0f0' }}>
                <td style={{ padding: '6px 12px', fontWeight: 600,
                             width: 160, color: '#666' }}>{label}</td>
                <td style={{ padding: '6px 12px' }}>{String(val ?? '-')}</td>
              </tr>
            ))}
          </table>
        )}
      </Modal>

      {/* Create/Edit modal */}
      <Modal title={editing ? 'Chinh sua Antenna' : 'Them Antenna moi'}
             open={modalOpen} onOk={handleSave} onCancel={() => setModalOpen(false)}
             width={700} okText="Luu" destroyOnClose>
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={24}>
              <Form.Item name="name" label="Name (dinh danh duy nhat)"
                         rules={[{ required: true, message: 'Vui long nhap ten antenna' }]}>
                <Input disabled={Boolean(editing)} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="band" label="Band">
                <Input placeholder="vd: 900-1800-2100" />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="no_of_ports" label="No of Ports">
                <InputNumber style={{ width: '100%' }} min={1} />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="no_of_beam" label="No of Beam">
                <InputNumber style={{ width: '100%' }} min={1} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="horizontal_bw" label="Horizontal BW">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="vertical_bw" label="Vertical BW">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="gain" label="Gain (dBi)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="etilt" label="Etilt range">
                <Input placeholder="vd: 0-10" />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="h" label="H – Height (mm)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="w" label="W – Width (mm)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="d" label="D – Depth (mm)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="weight" label="Weight (kg)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="connector_type" label="Connector type">
                <Input />
              </Form.Item>
            </Col>
            <Col span={24}>
              <Form.Item name="ghi_chu" label="Ghi chu">
                <Input.TextArea rows={2} />
              </Form.Item>
            </Col>
          </Row>
        </Form>
      </Modal>

      <DryRunModal
        open={dryRunOpen}
        onClose={() => setDryRunOpen(false)}
        title="Import Antenna tu Excel"
        templateKey={undefined}
        dryRunFn={dryRunAntennaExcel}
        importFn={importAntennaExcel}
        onSuccess={load}
      />
    </div>
  )
}
TSXEOF

echo "    ✓ AntennaPage.tsx updated"

# ── Rebuild ───────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "Rebuilding containers..."
echo "========================================"
sudo docker compose down
sudo docker compose up -d --build

echo ""
echo "========================================"
echo "Done! Export feature added."
echo "========================================"
echo ""
echo "New API endpoints:"
echo "  GET /api/v1/export/sites      → Sites_Export.xlsx"
echo "  GET /api/v1/export/cells-3g   → Cells_3G_Export.xlsx"
echo "  GET /api/v1/export/cells-4g   → Cells_4G_Export.xlsx"
echo "  GET /api/v1/export/cells-5g   → Cells_5G_Export.xlsx"
echo "  GET /api/v1/export/antennas   → Antennas_Export.xlsx"
echo ""
echo "All endpoints support filter params matching the page filters."
echo "Export respects active filters → exports exactly what user sees."
echo ""
echo "Frontend:"
echo "  Green 'Xuat Excel (N)' button on each management page"
echo "  Button shows live record count from current filter"
echo "  Uses fetch+Blob with Bearer token (no popup blockers)"
echo ""