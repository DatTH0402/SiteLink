#!/usr/bin/env bash
# apply_export_scope.sh  –  export exactly the selected rows / filtered rows (incl. column filters)
set -euo pipefail

ROOT="${1:-$(pwd)}"
cd "$ROOT"

FILES=(
  backend/app/api/routes/export.py
  backend/app/services/list_query.py
  frontend/src/api/export.ts
  frontend/src/hooks/useServerTable.tsx
  frontend/src/pages/sites/SitesPage.tsx
  frontend/src/pages/cells/Cells3GPage.tsx
  frontend/src/pages/cells/Cells4GPage.tsx
  frontend/src/pages/cells/Cells5GPage.tsx
)

for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "[FAIL] missing file: $f  (run from the SiteLink root)"; exit 1; }
  [ -e "$f.bak_export" ] || cp "$f" "$f.bak_export"
done
echo "[ok] backups created (*.bak_export)"

# ─────────────────────────────────────────────────────────────────────────────
# 1) backend/app/api/routes/export.py  (full rewrite)
# ─────────────────────────────────────────────────────────────────────────────
cat > backend/app/api/routes/export.py <<'PYEOF'
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
PYEOF
echo "[ok] export.py rewritten"

# ─────────────────────────────────────────────────────────────────────────────
# 2) frontend/src/api/export.ts  (full rewrite)
# ─────────────────────────────────────────────────────────────────────────────
cat > frontend/src/api/export.ts <<'TSEOF'
/**
 * export.ts – Downloads exported Excel / KMZ files from the backend.
 *
 * Sites / Cells exports use POST so that a large selection (thousands of ids)
 * and the column filters fit in the request. Scope rule (enforced server-side):
 *   - `ids` present  -> exactly the selected rows
 *   - otherwise      -> top-bar filters + column filters (+ sort)
 */

function getToken(): string {
  return localStorage.getItem('sl_token') || ''
}

export interface ExportResult {
  /** rows written to the file */
  rows?: number
  /** (KMZ only) sites that had valid coordinates */
  valid?: number
}

/** Extra scope on top of the top-bar filters. Build it with `buildExportScope`. */
export interface ExportScope {
  ids?:      number[]
  filters?:  string            // column filters JSON (same string as the list `filters` param)
  sort_by?:  string
  sort_dir?: 'asc' | 'desc'
}

/** Minimal shape of `useServerQuery()` that we need. */
interface ServerQueryLike {
  filtersJson?: string
  sort: { field: string; order: 'ascend' | 'descend' } | null
}

/**
 * Selected rows win (exact export). With no selection, export everything the
 * table currently shows as filtered (top-bar + column filters), same sort order.
 */
export function buildExportScope(sq: ServerQueryLike, selectedIds: number[] = []): ExportScope {
  const scope: ExportScope = {}
  if (sq.sort) {
    scope.sort_by  = sq.sort.field
    scope.sort_dir = sq.sort.order === 'ascend' ? 'asc' : 'desc'
  }
  if (selectedIds.length > 0) scope.ids = selectedIds
  else if (sq.filtersJson)    scope.filters = sq.filtersJson
  return scope
}

function headerNum(res: Response, name: string): number | undefined {
  const raw = res.headers.get(name)
  if (raw === null || raw === '') return undefined
  const n = Number(raw)
  return Number.isFinite(n) ? n : undefined
}

async function fetchAndSave(url: string, init: RequestInit, filename: string): Promise<ExportResult> {
  const res = await fetch(url, init)
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
  return {
    rows:  headerNum(res, 'X-Row-Count') ?? headerNum(res, 'X-Site-Count'),
    valid: headerNum(res, 'X-Valid-Coords'),
  }
}

function getBlob(url: string, filename: string) {
  return fetchAndSave(url, { headers: { Authorization: `Bearer ${getToken()}` } }, filename)
}

type FilterValue = string | string[] | undefined | null

function cleanParams(params: Record<string, FilterValue>): Record<string, string | string[]> {
  const out: Record<string, string | string[]> = {}
  Object.entries(params).forEach(([k, v]) => {
    if (v === undefined || v === null || v === '') return
    if (Array.isArray(v)) {
      const arr = v.filter((x) => x !== '' && x !== undefined && x !== null)
      if (arr.length) out[k] = arr
    } else {
      out[k] = v
    }
  })
  return out
}

function postExport(
  path: string, filename: string,
  params: Record<string, FilterValue>, scope?: ExportScope,
) {
  const hasIds = Boolean(scope?.ids && scope.ids.length > 0)
  const body = {
    // when rows are selected the server ignores every other filter
    params:   hasIds ? {} : cleanParams(params),
    ids:      hasIds ? scope!.ids : undefined,
    filters:  hasIds ? undefined : scope?.filters,
    sort_by:  scope?.sort_by,
    sort_dir: scope?.sort_dir ?? 'asc',
  }
  return fetchAndSave(
    `/api/v1/export/${path}`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${getToken()}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    },
    filename,
  )
}

// ── Sites ────────────────────────────────────────────────────────────────────
export interface SiteExportFilters {
  search?:       string
  site_name_cu?: string
  mien?:         string[]
  tinh?:         string[]
  phuong_xa?:    string[]
}

export const exportSites = (filters: SiteExportFilters = {}, scope?: ExportScope) =>
  postExport('sites', 'Sites_Export.xlsx', filters as Record<string, FilterValue>, scope)

export const exportSitesKmz = (filters: SiteExportFilters = {}, scope?: ExportScope) =>
  postExport('sites-kmz', 'Sites_Export.kmz', filters as Record<string, FilterValue>, scope)

// ── Cells ────────────────────────────────────────────────────────────────────
export interface CellExportFilters {
  search?:        string
  cell_name_old?: string
  mien?:          string[]
  tinh?:          string[]
  phuong_xa?:     string[]
  vendor?:        string[]
  mimo?:          string[]
  vung_phu_song?: string[]
}

export const exportCells3G = (filters: CellExportFilters = {}, scope?: ExportScope) =>
  postExport('cells-3g', 'Cells_3G_Export.xlsx', filters as Record<string, FilterValue>, scope)

export const exportCells4G = (filters: CellExportFilters = {}, scope?: ExportScope) =>
  postExport('cells-4g', 'Cells_4G_Export.xlsx', filters as Record<string, FilterValue>, scope)

export const exportCells5G = (filters: CellExportFilters = {}, scope?: ExportScope) =>
  postExport('cells-5g', 'Cells_5G_Export.xlsx', filters as Record<string, FilterValue>, scope)

// ── Antennas (unchanged, GET) ────────────────────────────────────────────────
function buildQS(params: Record<string, FilterValue>): string {
  const qs = new URLSearchParams()
  Object.entries(params).forEach(([k, v]) => {
    if (v === undefined || v === null) return
    if (Array.isArray(v)) {
      v.forEach((item) => { if (item) qs.append(k, item) })
    } else if (v !== '') {
      qs.append(k, v)
    }
  })
  const s = qs.toString()
  return s ? `?${s}` : ''
}

export function exportAntennas(filters: { search?: string; band?: string }) {
  return getBlob(`/api/v1/export/antennas${buildQS(filters)}`, 'Antennas_Export.xlsx')
}
TSEOF
echo "[ok] export.ts rewritten"

# ─────────────────────────────────────────────────────────────────────────────
# 3) patch list_query.py + hook hint text + 4 pages
# ─────────────────────────────────────────────────────────────────────────────
python3 - <<'PYEOF'
import pathlib, re, sys

def read(p):  return pathlib.Path(p).read_text(encoding="utf-8")
def write(p, s): pathlib.Path(p).write_text(s, encoding="utf-8")

def sub_text(src, old, new, label):
    if old not in src:
        sys.exit(f"[FAIL] anchor not found: {label}")
    return src.replace(old, new, 1)

def sub_regex(src, pattern, new, label):
    out, n = re.subn(pattern, lambda m: new, src, count=1, flags=re.S)
    if n != 1:
        sys.exit(f"[FAIL] anchor not found: {label}")
    return out

def sub_fn(src, pattern, fn, label):
    out, n = re.subn(pattern, fn, src, count=1, flags=re.S)
    if n != 1:
        sys.exit(f"[FAIL] anchor not found: {label}")
    return out

# ── list_query.py ────────────────────────────────────────────────────────────
LQ = "backend/app/services/list_query.py"
src = read(LQ)
if "def base_query_from_params" in src:
    print("[skip] list_query.py already patched")
else:
    new_block = '''def _first(params, name):
    v = params.get(name)
    if isinstance(v, (list, tuple)):
        v = v[0] if v else None
    if v is None or v == "":
        return None
    return v


def _many(params, name):
    v = params.get(name)
    if v is None:
        return []
    if not isinstance(v, (list, tuple)):
        v = [v]
    return [str(x) for x in v if x is not None and x != ""]


def _as_bool(v) -> bool:
    if isinstance(v, bool):
        return v
    return str(v).lower() in ("true", "1", "yes")


def base_query_from_params(db: Session, model, kind: str, params):
    """Top-bar filters from a plain dict (values: str | list[str] | bool)."""
    q = db.query(model)
    search = _first(params, "search")
    if kind == "cell":
        if search:
            q = q.filter(model.cell_name.ilike(f"%{search}%")
                         | model.site_name.ilike(f"%{search}%"))
        old = _first(params, "cell_name_old")
        if old:
            q = q.filter(model.cell_name_old.ilike(f"%{old}%"))
        names = ("mien", "tinh", "phuong_xa", "vendor", "mimo", "vung_phu_song")
    else:
        if search:
            q = q.filter(model.site_name.ilike(f"%{search}%"))
        cu = _first(params, "site_name_cu")
        if cu:
            q = q.filter(model.site_name_cu.ilike(f"%{cu}%"))
        for n in ("tram_3g", "tram_4g", "tram_5g"):
            v = _first(params, n)
            if v is not None:
                q = q.filter(getattr(model, n) == _as_bool(v))
        names = ("mien", "tinh", "phuong_xa")
    for n in names:
        vals = _many(params, n)
        if vals:
            q = q.filter(getattr(model, n).in_(vals))
    return q


def _base_query(db: Session, model, kind: str, request: Request):
    qp = request.query_params
    return base_query_from_params(
        db, model, kind, {k: qp.getlist(k) for k in qp.keys()})


def build_export_query(db: Session, model, kind: str, params,
                       filters: Optional[str] = None, ids: Optional[list] = None,
                       sort_by: Optional[str] = None, sort_dir: str = "asc",
                       default_order=()):
    """
    Query used by the exports.
      * ids given  -> exactly those rows (explicit selection, nothing else applies)
      * otherwise  -> top-bar filters + column filters (same code as the list)
    """
    if ids:
        q = db.query(model).filter(model.id.in_(list(ids)))
    else:
        q = base_query_from_params(db, model, kind, params or {})
        q = apply_column_filters(q, model, filters)
    if sort_by:
        return apply_sort(q, model, sort_by, sort_dir)
    if default_order:
        return q.order_by(*default_order)
    return q.order_by(model.id)
'''
    src = sub_regex(src, r"def _base_query\(.*?\n    return q\n", new_block, "list_query._base_query")
    write(LQ, src)
    print("[ok] list_query.py patched")

# ── useServerTable.tsx (hint text) ───────────────────────────────────────────
HK = "frontend/src/hooks/useServerTable.tsx"
src = read(HK)
if "áp dụng cả bộ lọc cột" in src:
    print("[skip] useServerTable.tsx already patched")
else:
    src = sub_text(
        src,
        "(Xuất file chưa áp dụng bộ lọc cột)",
        "(Xuất file áp dụng cả bộ lọc cột; nếu đã chọn dòng thì chỉ xuất các dòng đã chọn)",
        "useServerTable hint")
    write(HK, src)
    print("[ok] useServerTable.tsx patched")

# ── shared page patches ──────────────────────────────────────────────────────
def tooltip_and_labels(src, kind_label):
    """kind_label: 'Excel' or 'KMZ'"""
    if kind_label == "Excel":
        old_tip = '<Tooltip title="Xuất dữ liệu hiện tại ra Excel">'
        new_tip = ("<Tooltip title={selectedIds.length > 0 "
                   "? `Xuất ${selectedIds.length} dòng đã chọn ra Excel` "
                   ": 'Xuất các dòng đang lọc (gồm cả bộ lọc cột) ra Excel'}>")
    else:
        old_tip = '<Tooltip title="Xuất dữ liệu hiện tại ra KMZ (Google Earth)">'
        new_tip = ("<Tooltip title={selectedIds.length > 0 "
                   "? `Xuất ${selectedIds.length} site đã chọn ra KMZ (Google Earth)` "
                   ": 'Xuất các site đang lọc (gồm cả bộ lọc cột) ra KMZ (Google Earth)'}>")
    src = sub_text(src, old_tip, new_tip, f"tooltip {kind_label}")
    label = f"Xuất {kind_label}"
    src = sub_fn(
        src, re.escape(label) + r"(\s*)</Button>",
        lambda m: label + "{selectedIds.length > 0 ? ` (${selectedIds.length} đã chọn)` : ''}"
                  + m.group(1) + "</Button>",
        f"button label {kind_label}")
    return src

def cells_page(path, fn, topbar_extra=""):
    src = read(path)
    if "buildExportScope" in src:
        print(f"[skip] {path} already patched"); return
    src = sub_text(src, "import { %s } from '@/api/export'" % fn,
                   "import { %s, buildExportScope } from '@/api/export'" % fn, f"{path} import")
    new_handler = '''  const handleExport = async () => {
    setExporting(true)
    try {
      const res = await __FN__(
        {
          search:        search || undefined,
          cell_name_old: cellNameOld || undefined,
          mien:          mien.length ? mien : undefined,
          tinh:          tinh.length ? tinh : undefined,
          phuong_xa:     phuongXa.length ? phuongXa : undefined,
          vendor:        vendor.length ? vendor : undefined,
        },
        // selected rows -> exactly those; otherwise filtered rows incl. column filters
        buildExportScope(sq, selectedIds),
      )
      message.success(`Xuất Excel thành công${res.rows != null ? ` (${res.rows.toLocaleString('vi-VN')} dòng)` : ''}`)
    } catch (e: any) { message.error(e?.message || 'Xuất thất bại')
    } finally { setExporting(false) }
  }
'''.replace("__FN__", fn)
    src = sub_regex(src, r"  const handleExport = async \(\) => \{.*?\n  \}\n", new_handler, f"{path} handleExport")
    src = tooltip_and_labels(src, "Excel")
    write(path, src)
    print(f"[ok] {path} patched")

cells_page("frontend/src/pages/cells/Cells3GPage.tsx", "exportCells3G")
cells_page("frontend/src/pages/cells/Cells4GPage.tsx", "exportCells4G")
cells_page("frontend/src/pages/cells/Cells5GPage.tsx", "exportCells5G")

# ── SitesPage.tsx ────────────────────────────────────────────────────────────
SP = "frontend/src/pages/sites/SitesPage.tsx"
src = read(SP)
if "buildExportScope" in src:
    print(f"[skip] {SP} already patched")
else:
    src = sub_text(src, "import { exportSites, exportSitesKmz } from '@/api/export'",
                   "import { exportSites, exportSitesKmz, buildExportScope } from '@/api/export'",
                   "SitesPage import")
    excel_handler = '''  const handleExport = async () => {
    setExporting(true)
    try {
      const res = await exportSites(
        {
          search:       search || undefined,
          site_name_cu: siteNameCu || undefined,
          mien:         mien.length ? mien : undefined,
          tinh:         tinh.length ? tinh : undefined,
          phuong_xa:    phuongXa.length ? phuongXa : undefined,
        },
        // selected rows -> exactly those; otherwise filtered rows incl. column filters
        buildExportScope(sq, selectedIds),
      )
      message.success(`Xuất Excel thành công${res.rows != null ? ` (${res.rows.toLocaleString('vi-VN')} dòng)` : ''}`)
    } catch (e: any) {
      message.error(e?.message || 'Xuất thất bại')
    } finally {
      setExporting(false)
    }
  }
'''
    kmz_handler = '''  const handleKmzExport = async () => {
    setExportingKmz(true)
    try {
      const res = await exportSitesKmz(
        {
          search:       search || undefined,
          site_name_cu: siteNameCu || undefined,
          mien:         mien.length ? mien : undefined,
          tinh:         tinh.length ? tinh : undefined,
          phuong_xa:    phuongXa.length ? phuongXa : undefined,
        },
        buildExportScope(sq, selectedIds),
      )
      const detail = res.rows != null && res.valid != null
        ? ` (${res.valid.toLocaleString('vi-VN')}/${res.rows.toLocaleString('vi-VN')} site có tọa độ)`
        : ''
      message.success(`Xuất KMZ thành công${detail}`)
    } catch (e: any) {
      message.error(e?.message || 'Xuất KMZ thất bại')
    } finally {
      setExportingKmz(false)
    }
  }
'''
    src = sub_regex(src, r"  const handleExport = async \(\) => \{.*?\n  \}\n", excel_handler, "SitesPage handleExport")
    src = sub_regex(src, r"  const handleKmzExport = async \(\) => \{.*?\n  \}\n", kmz_handler, "SitesPage handleKmzExport")
    src = tooltip_and_labels(src, "Excel")
    src = tooltip_and_labels(src, "KMZ")
    write(SP, src)
    print(f"[ok] {SP} patched")
PYEOF

# ─────────────────────────────────────────────────────────────────────────────
# 4) sanity checks
# ─────────────────────────────────────────────────────────────────────────────
python3 -m py_compile backend/app/api/routes/export.py backend/app/services/list_query.py \
  && echo "[ok] python files compile"

cat <<'MSG'

Done. Restart the backend, then type-check the frontend:
    (cd frontend && npx tsc --noEmit)

Behaviour now:
  * rows selected   -> Excel/KMZ contains exactly those rows
  * nothing selected-> top-bar filters + column filters, in the on-screen sort order
  * old GET export URLs still work (and now also honour ?filters=)
Backups: *.bak_export next to every changed file.
MSG