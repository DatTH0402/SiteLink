"""
export.py – Excel / KMZ export endpoints (Sites, Cells 3G/4G/5G, Antennas)

Scope of a Sites / Cells export:
  1. `ids` given   -> exactly those rows (the user's selection); other filters ignored
  2. otherwise     -> top-bar filters + column filters (`filters` JSON) [+ sort]

Every Sites / Cells endpoint comes in two flavours:
  GET  /export/<x>  query-string (legacy links; token via Bearer header OR ?token=)
  POST /export/<x>  JSON body {ids, filters, params, sort_by, sort_dir}
                    (needed because a selection can hold thousands of ids)
"""
from __future__ import annotations

import io
import xml.sax.saxutils as _saxutils
import zipfile as _zipfile
from functools import partial
from typing import Any, Callable, Dict, List, Optional

import openpyxl
from openpyxl.styles import PatternFill, Font, Alignment, Border, Side
from openpyxl.utils import get_column_letter
from fastapi import APIRouter, Depends, Query, HTTPException, Request
from fastapi.responses import StreamingResponse
from fastapi.security import OAuth2PasswordBearer
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.site import Site
from app.models.cell_3g import Cell3G
from app.models.cell_4g import Cell4G
from app.models.cell_5g import Cell5G
from app.models.antenna import Antenna
from app.models.user import User
from app.core.security import decode_access_token
from app.services.list_query import build_export_query

router = APIRouter()

HEADER_FILL = PatternFill("solid", fgColor="1F4E79")
HEADER_FONT = Font(color="FFFFFF", bold=True, size=10)
CENTER      = Alignment(horizontal="center", vertical="center", wrap_text=True)
LEFT        = Alignment(horizontal="left",   vertical="center")
THIN        = Side(style="thin", color="D0D0D0")
BORDER      = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
ALT_FILL    = PatternFill("solid", fgColor="EBF3FB")

_EXPOSE = "X-Row-Count, X-Site-Count, X-Valid-Coords"


# ── auth: Bearer header OR ?token= ────────────────────────────────────────────
oauth2_optional = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login", auto_error=False)


def get_optional_user(
    token_header: Optional[str] = Depends(oauth2_optional),
    token_param:  Optional[str] = Query(None, alias="token"),
    db: Session = Depends(get_db),
) -> User:
    raw = token_header or token_param
    if not raw:
        raise HTTPException(status_code=401, detail="Not authenticated")
    payload = decode_access_token(raw)
    if not payload:
        raise HTTPException(status_code=401, detail="Invalid token")
    user = db.query(User).filter(User.username == payload.get("sub")).first()
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="User inactive")
    return user


# ── workbook helpers ──────────────────────────────────────────────────────────
def _make_wb(headers):
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.row_dimensions[1].height = 30
    ws.freeze_panes = "A2"
    for col_idx, (header, width) in enumerate(headers, start=1):
        cell = ws.cell(row=1, column=col_idx, value=header)
        cell.fill = HEADER_FILL; cell.font = HEADER_FONT
        cell.alignment = CENTER; cell.border = BORDER
        ws.column_dimensions[get_column_letter(col_idx)].width = width
    return wb, ws


def _style_row(ws, row_idx, num_cols, alternate):
    fill = ALT_FILL if alternate else None
    for col_idx in range(1, num_cols + 1):
        cell = ws.cell(row=row_idx, column=col_idx)
        cell.alignment = LEFT; cell.border = BORDER
        if fill: cell.fill = fill


def _stream(wb, filename, row_count=None):
    buf = io.BytesIO()
    wb.save(buf); buf.seek(0)
    headers = {
        "Content-Disposition": f'attachment; filename="{filename}"',
        "Access-Control-Expose-Headers": _EXPOSE,
    }
    if row_count is not None:
        headers["X-Row-Count"] = str(row_count)
    return StreamingResponse(
        iter([buf.read()]),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers=headers,
    )


def _safe_bool_export(v) -> bool:
    if v is None: return False
    if isinstance(v, bool): return v
    if isinstance(v, int): return v != 0
    if isinstance(v, str): return v.strip().lower() not in ("false", "0", "no", "off", "")
    return bool(v)


def _b(val): return "x" if _safe_bool_export(val) else ""


# ── column definitions ────────────────────────────────────────────────────────
SITE_HEADERS = [
    ("STT", 6), ("Mien", 8), ("Tinh", 22), ("Phuong xa", 22),
    ("Site name (cu)", 22), ("Site name", 25), ("Site VIP", 10),
    ("Lat", 14), ("Long", 14), ("Tram 2G", 10), ("Tram 3G", 10),
    ("Tram 4G", 10), ("Tram 5G", 10), ("Repeater", 10), ("Booster", 10),
    ("Node truyen dan only", 20), ("Tram phu song TSCA", 18),
    ("Phan loai tram", 22), ("MORAN 3G", 15), ("MORAN 4G", 15),
    ("MORAN 5G", 15), ("Ma PTM", 14), ("Do cao dinh cot anten (m)", 22),
    ("Do cao cot anten (m)", 20), ("Dia chi", 30), ("Ghi chu", 30),
]


def _site_row(idx, s):
    return [
        idx, s.mien, s.tinh, s.phuong_xa, s.site_name_cu, s.site_name,
        s.site_vip, s.lat, s.long,
        _b(s.tram_2g), _b(s.tram_3g), _b(s.tram_4g), _b(s.tram_5g),
        _b(s.repeater), _b(s.booster), _b(s.node_truyen_dan_only), _b(s.tram_phu_song_tsca),
        s.phan_loai_tram, s.moran_3g, s.moran_4g, s.moran_5g, s.ma_ptm,
        s.do_cao_dinh_cot_anten, s.do_cao_cot_anten, s.dia_chi, s.ghi_chu,
    ]


CELL3G_HEADERS = [
    ("STT", 6), ("Mien", 8), ("Tinh", 22), ("Phuong xa", 22),
    ("Site Name", 25), ("Site Name Old", 22), ("Cell Name", 25), ("Cell Name Old", 22),
    ("Cell VIP", 10), ("MORAN", 15), ("Lat", 14), ("Long", 14),
    ("Vung phu song", 15), ("Vendor", 14), ("RNC Name", 18),
    ("Do cao anten", 15),
    ("Azimuth", 10), ("M-tilt", 10), ("E-Tilt", 10), ("Total Tilt", 12),
    ("Loai Anten", 30), ("Chung anten", 18), ("Baseband", 18), ("RF", 14),
    ("Cell ID", 14), ("UARFCN", 12), ("LAC", 10), ("RAC", 10),
    ("PSC", 10), ("MIMO", 10), ("URAId", 10),
    ("Cell max power (dBm)", 20), ("CPICH power (dBm)", 18),
    ("BBUname", 16), ("Cell status (at dump time)", 24),
]


def _cell3g_row(idx, c):
    return [
        idx, c.mien, c.tinh, c.phuong_xa,
        c.site_name, c.site_name_old, c.cell_name, c.cell_name_old,
        c.cell_vip, c.moran, c.lat, c.long,
        c.vung_phu_song, c.vendor, c.rnc_name, c.do_cao_anten,
        c.azimuth, c.m_tilt, c.e_tilt, c.total_tilt,
        c.loai_anten, c.chung_anten, c.baseband, c.rf,
        c.cell_id, c.uarfcn, c.lac, c.rac,
        c.psc, c.mimo, c.ura_id,
        c.cell_max_power, c.cpich_power, c.bbu_name, c.cell_status,
    ]


CELL4G_HEADERS = [
    ("STT", 6), ("Mien", 8), ("Tinh", 22), ("Phuong xa", 22),
    ("Site Name", 25), ("Site Name Old", 22), ("Cell Name", 25), ("Cell Name Old", 22),
    ("Cell VIP", 10), ("MORAN", 15), ("Lat", 14), ("Long", 14),
    ("Vung phu song", 15), ("Vendor", 14), ("Do cao anten", 15),
    ("Azimuth", 10), ("M-tilt", 10), ("E-Tilt", 10), ("Total Tilt", 12),
    ("Loai Anten", 30), ("Chung anten", 18), ("Baseband", 18), ("RF", 14),
    ("EnodeB ID", 14), ("Cell ID", 14), ("EARFCN", 12), ("TAC", 10),
    ("PCI", 10), ("Root Sequence ID", 18), ("MIMO", 10), ("Bandwidth", 12),
    ("Cell max power (dBm)", 20), ("ECI", 12),
    ("BBUname", 16), ("Cell status (at dump time)", 24),
]


def _cell4g_row(idx, c):
    return [
        idx, c.mien, c.tinh, c.phuong_xa,
        c.site_name, c.site_name_old, c.cell_name, c.cell_name_old,
        c.cell_vip, c.moran, c.lat, c.long,
        c.vung_phu_song, c.vendor, c.do_cao_anten,
        c.azimuth, c.m_tilt, c.e_tilt, c.total_tilt,
        c.loai_anten, c.chung_anten, c.baseband, c.rf,
        c.enodeb_id, c.cell_id, c.earfcn, c.tac,
        c.pci, c.root_sequence_id, c.mimo, c.bandwidth,
        c.cell_max_power, c.eci, c.bbu_name, c.cell_status,
    ]


CELL5G_HEADERS = [
    ("STT", 6), ("Mien", 8), ("Tinh", 22), ("Phuong xa", 22),
    ("Site Name", 25), ("Site Name Old", 22), ("Cell Name", 25), ("Cell Name Old", 22),
    ("Cell VIP", 10), ("MORAN", 15), ("Lat", 14), ("Long", 14),
    ("Vung phu song", 15), ("Vendor", 14), ("Do cao anten", 15),
    ("Azimuth", 10), ("M-tilt", 10), ("E-Tilt", 10), ("Total Tilt", 12),
    ("Loai Anten", 30), ("Baseband", 18), ("RF", 14),
    ("gNodeB ID", 14), ("Cell ID", 14), ("TAC", 10),
    ("PCI", 10), ("Root Sequence ID", 18), ("MIMO", 10),
    ("SSB-ARFCN", 12), ("Center-ARFCN", 14), ("GSCN", 10),
    ("Bandwidth (MHz)", 14), ("Cell max power (dBm)", 20), ("NCI", 12),
    ("BBUname", 16), ("MU-MIMO", 10), ("Cell status (at dump time)", 24),
]


def _cell5g_row(idx, c):
    return [
        idx, c.mien, c.tinh, c.phuong_xa,
        c.site_name, c.site_name_old, c.cell_name, c.cell_name_old,
        c.cell_vip, c.moran, c.lat, c.long,
        c.vung_phu_song, c.vendor, c.do_cao_anten,
        c.azimuth, c.m_tilt, c.e_tilt, c.total_tilt,
        c.loai_anten, c.baseband, c.rf,
        c.gnodeb_id, c.cell_id, c.tac,
        c.pci, c.root_sequence_id, c.mimo,
        c.ssb_arfcn, c.center_arfcn, c.gscn,
        c.bandwidth, c.cell_max_power, c.nci,
        c.bbu_name, c.mu_mimo, c.cell_status,
    ]


_SPECS: Dict[str, Dict[str, Any]] = {
    "sites": dict(
        model=Site, kind="site", headers=SITE_HEADERS, row=_site_row,
        order=(Site.mien, Site.tinh, Site.site_name), filename="Sites_Export.xlsx"),
    "cells_3g": dict(
        model=Cell3G, kind="cell", headers=CELL3G_HEADERS, row=_cell3g_row,
        order=(Cell3G.mien, Cell3G.tinh, Cell3G.site_name, Cell3G.cell_name),
        filename="Cells_3G_Export.xlsx"),
    "cells_4g": dict(
        model=Cell4G, kind="cell", headers=CELL4G_HEADERS, row=_cell4g_row,
        order=(Cell4G.mien, Cell4G.tinh, Cell4G.site_name, Cell4G.cell_name),
        filename="Cells_4G_Export.xlsx"),
    "cells_5g": dict(
        model=Cell5G, kind="cell", headers=CELL5G_HEADERS, row=_cell5g_row,
        order=(Cell5G.mien, Cell5G.tinh, Cell5G.site_name, Cell5G.cell_name),
        filename="Cells_5G_Export.xlsx"),
}


def _rows_for(key, db, params, filters, ids, sort_by, sort_dir):
    spec = _SPECS[key]
    q = build_export_query(
        db, spec["model"], spec["kind"], params,
        filters=filters, ids=ids, sort_by=sort_by, sort_dir=sort_dir,
        default_order=spec["order"],
    )
    return q.all()


def _excel(key, db, params, filters, ids, sort_by, sort_dir):
    spec = _SPECS[key]
    rows = _rows_for(key, db, params, filters, ids, sort_by, sort_dir)
    headers = spec["headers"]
    wb, ws = _make_wb(headers)
    for idx, obj in enumerate(rows, start=1):
        row = idx + 1
        for col_idx, val in enumerate(spec["row"](idx, obj), start=1):
            ws.cell(row=row, column=col_idx, value=val)
        _style_row(ws, row, len(headers), idx % 2 == 0)
    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}1"
    return _stream(wb, spec["filename"], len(rows))


# ── KMZ (KML inside a ZIP — readable by Google Earth) ─────────────────────────
def _build_kml(sites: list) -> str:
    def esc(v) -> str:
        if v is None:
            return ""
        return _saxutils.escape(str(v))

    placemarks = []
    for s in sites:
        if s.lat is None or s.long is None:
            continue
        description = (
            f"<b>Tỉnh/TP:</b> {esc(s.tinh)}<br/>"
            f"<b>Phường/Xã:</b> {esc(s.phuong_xa)}<br/>"
            f"<b>Site name:</b> {esc(s.site_name)}<br/>"
            f"<b>Site name (cũ):</b> {esc(s.site_name_cu)}<br/>"
        )
        placemarks.append(f"""  <Placemark>
    <name>{esc(s.site_name)}</name>
    <description><![CDATA[{description}]]></description>
    <Point>
      <coordinates>{s.long},{s.lat},0</coordinates>
    </Point>
  </Placemark>""")

    kml_body = "\n".join(placemarks)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>SiteLink – Site Locations</name>
    <description>Exported from SiteLink</description>
    <Style id="siteIcon">
      <IconStyle>
        <color>ff0000ff</color>
        <scale>1.0</scale>
        <Icon>
          <href>http://maps.google.com/mapfiles/kml/paddle/red-circle.png</href>
        </Icon>
      </IconStyle>
    </Style>
{kml_body}
  </Document>
</kml>"""


def _build_kmz(kml_content: str) -> bytes:
    buf = io.BytesIO()
    with _zipfile.ZipFile(buf, mode="w", compression=_zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("doc.kml", kml_content.encode("utf-8"))
    buf.seek(0)
    return buf.read()


def _kmz(db, params, filters, ids, sort_by, sort_dir):
    sites = _rows_for("sites", db, params, filters, ids, sort_by, sort_dir)
    valid_count = sum(1 for s in sites if s.lat is not None and s.long is not None)
    kmz_bytes = _build_kmz(_build_kml(sites))
    return StreamingResponse(
        iter([kmz_bytes]),
        media_type="application/vnd.google-earth.kmz",
        headers={
            "Content-Disposition": 'attachment; filename="Sites_Export.kmz"',
            "X-Site-Count": str(len(sites)),
            "X-Row-Count": str(len(sites)),
            "X-Valid-Coords": str(valid_count),
            "Access-Control-Expose-Headers": _EXPOSE,
        },
    )


# ── route registration (GET + POST for every sites / cells export) ────────────
class ExportRequest(BaseModel):
    ids:      Optional[List[int]] = None            # selected rows -> exact export
    filters:  Optional[str] = None                  # column filters (same JSON as ?filters=)
    params:   Dict[str, Any] = Field(default_factory=dict)   # top-bar filters
    sort_by:  Optional[str] = None
    sort_dir: str = "asc"


_RESERVED = {"token", "filters", "sort_by", "sort_dir", "ids"}


def _add_routes(path: str, tag: str, run: Callable[..., StreamingResponse]) -> None:
    def get_endpoint(
        request: Request,
        db: Session = Depends(get_db),
        _: User = Depends(get_optional_user),
    ):
        qp = request.query_params
        params = {k: qp.getlist(k) for k in qp.keys() if k not in _RESERVED}
        return run(db, params, qp.get("filters"), None,
                   qp.get("sort_by"), qp.get("sort_dir") or "asc")

    def post_endpoint(
        body: ExportRequest,
        db: Session = Depends(get_db),
        _: User = Depends(get_optional_user),
    ):
        return run(db, body.params, body.filters, body.ids,
                   body.sort_by, body.sort_dir)

    router.add_api_route(path, get_endpoint,  methods=["GET"],  name=f"export_{tag}_get")
    router.add_api_route(path, post_endpoint, methods=["POST"], name=f"export_{tag}_post")


_add_routes("/sites",     "sites",     partial(_excel, "sites"))
_add_routes("/cells-3g",  "cells_3g",  partial(_excel, "cells_3g"))
_add_routes("/cells-4g",  "cells_4g",  partial(_excel, "cells_4g"))
_add_routes("/cells-5g",  "cells_5g",  partial(_excel, "cells_5g"))
_add_routes("/sites-kmz", "sites_kmz", _kmz)


# ── antennas (unchanged) ──────────────────────────────────────────────────────
@router.get("/antennas")
def export_antennas(
    search:    Optional[str]  = Query(None),
    band:      Optional[str]  = Query(None),
    is_5g_aau: Optional[bool] = Query(None),
    db:        Session        = Depends(get_db),
    _:         User           = Depends(get_optional_user),
):
    q = db.query(Antenna)
    if search:    q = q.filter(Antenna.name.ilike(f"%{search}%"))
    if band:      q = q.filter(Antenna.band.ilike(f"%{band}%"))
    if is_5g_aau is not None: q = q.filter(Antenna.is_5g_aau == is_5g_aau)
    antennas = q.order_by(Antenna.name).all()
    headers = [
        ("STT", 6), ("Name", 35), ("Band", 20), ("5G AAU", 10),
        ("No of Ports", 12), ("No of Beam", 12), ("Horizontal BW", 14),
        ("Vertical BW", 12), ("Gain (dBi)", 12), ("Etilt range", 14),
        ("H (mm)", 10), ("W (mm)", 10), ("D (mm)", 10),
        ("Weight (kg)", 12), ("Connector type", 18),
        ("Spec File", 30), ("Ghi chu", 30),
    ]
    wb, ws = _make_wb(headers)
    for idx, a in enumerate(antennas, start=1):
        row = idx + 1
        values = [
            idx, a.name, a.band, "x" if a.is_5g_aau else "",
            a.no_of_ports, a.no_of_beam, a.horizontal_bw, a.vertical_bw,
            a.gain, a.etilt, a.h, a.w, a.d, a.weight, a.connector_type,
            a.spec_file_name or "", a.ghi_chu,
        ]
        for col_idx, val in enumerate(values, start=1):
            ws.cell(row=row, column=col_idx, value=val)
        _style_row(ws, row, len(headers), idx % 2 == 0)
    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}1"
    return _stream(wb, "Antennas_Export.xlsx", len(antennas))
