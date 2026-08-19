#!/usr/bin/env bash
# =============================================================================
# update_antenna_import.sh
# =============================================================================
# Adds full dry-run / import / template-download support for the Antenna module,
# matching the Sites & Cells pattern exactly.
#
# Changes:
#   1. backend/app/api/routes/antenna.py   – rewrite import endpoint to return
#                                            dry-run preview matching DryRunPreview
#   2. backend/app/api/routes/templates.py – add "antenna" template key
#   3. frontend/src/api/antenna.ts         – fix dryRunAntennaExcel return type
#   4. frontend/src/pages/antenna/AntennaPage.tsx – wire templateKey="antenna"
#                                            and show full DryRunModal
#
# Usage:
#   chmod +x update_antenna_import.sh && ./update_antenna_import.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend"
FRONTEND_DIR="$SCRIPT_DIR/frontend"

echo "============================================================"
echo "  SiteLink – Antenna Import Feature Update"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Helper: write a file, creating parent dirs as needed
# ---------------------------------------------------------------------------
write_file() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path"
  echo "  ✓  wrote $path"
}

# ===========================================================================
# 1.  BACKEND – antenna.py  (full rewrite of the import section)
# ===========================================================================
echo "[1/4] Updating backend/app/api/routes/antenna.py …"
write_file "$BACKEND_DIR/app/api/routes/antenna.py" << 'PYTHON_EOF'
import io
import os
import uuid
from typing import List, Optional

import pandas as pd
from fastapi import (
    APIRouter, Depends, HTTPException, Query,
    UploadFile, File, status,
)
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.antenna import Antenna
from app.schemas.antenna import AntennaCreate, AntennaUpdate, AntennaRead
from app.utils.deps import get_current_user, require_admin
from app.utils.audit import log_action
from app.models.user import User

router = APIRouter()

# ── upload directory ──────────────────────────────────────────────────────────
UPLOAD_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "..", "uploads", "antenna_specs")
)
os.makedirs(UPLOAD_DIR, exist_ok=True)

ALLOWED_MIME   = {"application/pdf"}
MAX_FILE_SIZE  = 20 * 1024 * 1024   # 20 MB


# ── tiny helpers ──────────────────────────────────────────────────────────────
def _or_404(db: Session, antenna_id: int) -> Antenna:
    obj = db.query(Antenna).filter(Antenna.id == antenna_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail="Antenna not found")
    return obj


def _delete_spec_file(antenna: Antenna) -> None:
    if antenna.spec_file_path:
        full = os.path.join(UPLOAD_DIR, antenna.spec_file_path)
        try:
            if os.path.exists(full):
                os.remove(full)
        except OSError:
            pass


# ── Excel parser (shared by dry-run and real import) ─────────────────────────

def _parse_antenna_excel(content: bytes, db: Session):
    """
    Parse the antenna Excel file.

    Returns a dict:
        {
            "to_create": [ {rec}, ... ],
            "to_update": [ {"existing": <Antenna>, "rec": {rec}}, ... ],
            "errors":    [ "Row N: …", ... ],
        }

    Flexible column aliases match the template column names and the
    existing import_antenna_excel() parser.
    """
    try:
        df = pd.read_excel(io.BytesIO(content), dtype=str)
        df = df.where(pd.notna(df), None)
        df.columns = [str(c).strip() for c in df.columns]
    except Exception as exc:
        raise ValueError(f"Cannot read Excel file: {exc}") from exc

    # ── value extractors ──────────────────────────────────────────────────────
    def _v(row, *keys):
        for k in keys:
            val = row.get(k)
            if val is not None and str(val).strip() not in ("", "nan", "None"):
                return str(val).strip()
        return None

    def _i(row, *keys):
        v = _v(row, *keys)
        if v is None:
            return None
        try:
            return int(float(v))
        except Exception:
            return None

    def _b(row, *keys) -> bool:
        v = _v(row, *keys)
        if v is None:
            return False
        return str(v).strip().lower() in ("x", "true", "yes", "1", "co", "có")

    to_create: list = []
    to_update: list = []
    errors:    list = []

    for i, row in df.iterrows():
        row_num = int(str(i)) + 2

        name = _v(row,
                  "Name", "name", "NAME",
                  "Ten anten", "Ten Anten", "Antenna Name")
        if not name:
            errors.append(f"Row {row_num}: 'Name' column is empty – skipped")
            continue

        rec = {
            "name":           name,
            "no_of_ports":    _i(row, "No_of_ports", "No of ports", "Ports"),
            "band":           _v(row, "Band", "band", "BAND"),
            "no_of_beam":     _i(row, "No_of_beam", "No of beam"),
            "horizontal_bw":  _v(row, "Horizontal BW", "Horizontal_BW", "HBW"),
            "vertical_bw":    _v(row, "Vertical BW",   "Vertical_BW",   "VBW"),
            "gain":           _v(row, "Gain", "gain"),
            "etilt":          _v(row, "Etilt", "ETilt", "E-tilt"),
            "h":              _v(row, "H", "h", "Height"),
            "w":              _v(row, "W", "w", "Width"),
            "d":              _v(row, "D", "d", "Depth"),
            "weight":         _v(row, "Weight", "weight"),
            "connector_type": _v(row, "Connector type", "Connector Type", "Connector"),
            "ghi_chu":        _v(row, "Ghi chú", "Ghi chu", "Note"),
            "is_5g_aau":      _b(row, "5G_AAU", "5g_aau", "AAU", "is_5g_aau"),
        }

        existing = db.query(Antenna).filter(Antenna.name == name).first()
        if existing:
            to_update.append({"existing": existing, "rec": rec, "row_num": row_num})
        else:
            to_create.append({"rec": rec, "row_num": row_num})

    return {"to_create": to_create, "to_update": to_update, "errors": errors}


# ── List / search ─────────────────────────────────────────────────────────────

@router.get("/", response_model=List[AntennaRead])
def list_antennas(
    skip:      int            = 0,
    limit:     int            = 1000,
    search:    Optional[str]  = Query(None),
    band:      Optional[str]  = Query(None),
    is_5g_aau: Optional[bool] = Query(None),
    db:        Session        = Depends(get_db),
    _=Depends(get_current_user),
):
    q = db.query(Antenna)
    if search:
        q = q.filter(Antenna.name.ilike(f"%{search}%"))
    if band:
        q = q.filter(Antenna.band.ilike(f"%{band}%"))
    if is_5g_aau is not None:
        q = q.filter(Antenna.is_5g_aau == is_5g_aau)
    return q.order_by(Antenna.name).offset(skip).limit(limit).all()


@router.get("/count")
def count_antennas(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return {"count": db.query(Antenna).count()}


# ── Excel import: DRY-RUN ─────────────────────────────────────────────────────

@router.post("/import-excel/dry-run")
async def dry_run_antenna_excel(
    file: UploadFile = File(...),
    db:   Session    = Depends(get_db),
    _=Depends(get_current_user),
):
    """
    Dry-run: parse the Excel file and return a preview without saving anything.
    Response shape matches DryRunPreview in the frontend.
    """
    content = await file.read()
    try:
        result = _parse_antenna_excel(content, db)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    to_create = result["to_create"]
    to_update = result["to_update"]
    errors    = result["errors"]

    return {
        "to_create":      len(to_create),
        "to_update":      len(to_update),
        "errors":         len(errors),
        "error_details":  errors[:50],
        "preview_create": [item["rec"]["name"] for item in to_create[:5]],
        "preview_update": [item["existing"].name for item in to_update[:5]],
        "dry_run":        True,
    }


# ── Excel import: REAL ────────────────────────────────────────────────────────

@router.post("/import-excel")
async def import_antenna_excel(
    file:         UploadFile = File(...),
    db:           Session    = Depends(get_db),
    current_user: User       = Depends(get_current_user),
):
    """
    Real import: parse, create / update, commit.
    Response shape matches ImportResultData in the frontend.
    """
    content = await file.read()
    try:
        result = _parse_antenna_excel(content, db)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    to_create = result["to_create"]
    to_update = result["to_update"]
    errors    = list(result["errors"])   # copy so we can append runtime errors
    created = updated = 0

    # ── create new records ────────────────────────────────────────────────────
    for item in to_create:
        rec     = item["rec"]
        row_num = item["row_num"]
        try:
            obj = Antenna(**rec)
            db.add(obj)
            db.commit()
            db.refresh(obj)
            created += 1
        except Exception as exc:
            db.rollback()
            errors.append(f"Row {row_num} (create '{rec.get('name')}'): {exc}")

    # ── update existing records ───────────────────────────────────────────────
    for item in to_update:
        existing = item["existing"]
        rec      = item["rec"]
        row_num  = item["row_num"]
        try:
            for k, v in rec.items():
                if k != "name":          # never overwrite the primary key / name
                    setattr(existing, k, v)
            db.commit()
            db.refresh(existing)
            updated += 1
        except Exception as exc:
            db.rollback()
            errors.append(f"Row {row_num} (update '{rec.get('name')}'): {exc}")

    log_action(
        db, current_user, "IMPORT", "antennas", 0,
        new_value={"created": created, "updated": updated},
    )

    return {
        "created": created,
        "updated": updated,
        "errors":  errors,
        "dry_run": False,
    }


# ── Spec file upload ──────────────────────────────────────────────────────────

@router.post("/{antenna_id}/spec-file", response_model=AntennaRead)
async def upload_spec_file(
    antenna_id:   int,
    file:         UploadFile = File(...),
    db:           Session    = Depends(get_db),
    current_user: User       = Depends(get_current_user),
):
    obj = _or_404(db, antenna_id)
    if file.content_type not in ALLOWED_MIME:
        raise HTTPException(
            status_code=400,
            detail=f"Only PDF files are allowed (got: {file.content_type})",
        )
    content = await file.read()
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=400,
            detail=f"File too large. Maximum size is {MAX_FILE_SIZE // (1024*1024)} MB.",
        )
    _delete_spec_file(obj)
    ext       = os.path.splitext(file.filename or "spec.pdf")[1] or ".pdf"
    safe_name = f"{antenna_id}_{uuid.uuid4().hex}{ext}"
    dest      = os.path.join(UPLOAD_DIR, safe_name)
    with open(dest, "wb") as f:
        f.write(content)
    obj.spec_file_path = safe_name
    obj.spec_file_name = file.filename or safe_name
    db.commit()
    db.refresh(obj)
    log_action(db, current_user, "UPDATE", "antennas", obj.id,
               new_value={"spec_file": file.filename})
    return obj


@router.delete("/{antenna_id}/spec-file", response_model=AntennaRead)
def delete_spec_file(
    antenna_id:   int,
    db:           Session = Depends(get_db),
    current_user: User    = Depends(get_current_user),
):
    obj = _or_404(db, antenna_id)
    _delete_spec_file(obj)
    obj.spec_file_path = None
    obj.spec_file_name = None
    db.commit()
    db.refresh(obj)
    log_action(db, current_user, "UPDATE", "antennas", obj.id,
               new_value={"spec_file": None})
    return obj


@router.get("/{antenna_id}/spec-file/download")
def download_spec_file(
    antenna_id: int,
    db:         Session = Depends(get_db),
    _=Depends(get_current_user),
):
    obj = _or_404(db, antenna_id)
    if not obj.spec_file_path:
        raise HTTPException(status_code=404, detail="No spec file attached to this antenna")
    full_path = os.path.join(UPLOAD_DIR, obj.spec_file_path)
    if not os.path.exists(full_path):
        raise HTTPException(status_code=404, detail="Spec file not found on server")
    return FileResponse(
        path=full_path,
        filename=obj.spec_file_name or obj.spec_file_path,
        media_type="application/pdf",
    )


# ── CRUD ──────────────────────────────────────────────────────────────────────

@router.get("/{antenna_id}", response_model=AntennaRead)
def get_antenna(
    antenna_id: int,
    db:         Session = Depends(get_db),
    _=Depends(get_current_user),
):
    return _or_404(db, antenna_id)


@router.post("/", response_model=AntennaRead, status_code=201)
def create_antenna(
    payload:      AntennaCreate,
    db:           Session = Depends(get_db),
    current_user: User    = Depends(get_current_user),
):
    existing = db.query(Antenna).filter(Antenna.name == payload.name).first()
    if existing:
        raise HTTPException(status_code=400,
                            detail=f"Antenna '{payload.name}' already exists")
    obj = Antenna(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    log_action(db, current_user, "CREATE", "antennas", obj.id,
               new_value=payload.model_dump())
    return obj


@router.put("/{antenna_id}", response_model=AntennaRead)
def update_antenna(
    antenna_id:   int,
    payload:      AntennaUpdate,
    db:           Session = Depends(get_db),
    current_user: User    = Depends(get_current_user),
):
    obj = _or_404(db, antenna_id)
    old = {c.name: getattr(obj, c.name) for c in obj.__table__.columns}
    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(obj, k, v)
    db.commit()
    db.refresh(obj)
    log_action(db, current_user, "UPDATE", "antennas", obj.id,
               old_value=old, new_value=payload.model_dump(exclude_unset=True))
    return obj


@router.delete("/{antenna_id}")
def delete_antenna(
    antenna_id:   int,
    db:           Session = Depends(get_db),
    current_user: User    = Depends(get_current_user),
):
    obj = _or_404(db, antenna_id)
    _delete_spec_file(obj)
    db.delete(obj)
    db.commit()
    log_action(db, current_user, "DELETE", "antennas", antenna_id)
    return {"message": "Deleted"}
PYTHON_EOF

# ===========================================================================
# 2.  BACKEND – templates.py  (add "antenna" key)
# ===========================================================================
echo "[2/4] Updating backend/app/api/routes/templates.py …"
write_file "$BACKEND_DIR/app/api/routes/templates.py" << 'PYTHON_EOF'
"""
templates.py
------------
Serves Excel template files for download.
Templates are stored in backend/templates/
"""
import os
from fastapi import APIRouter, HTTPException, Depends
from fastapi.responses import FileResponse

from app.utils.deps import get_current_user

router = APIRouter()

TEMPLATE_DIR = os.path.abspath(
    os.path.join(
        os.path.dirname(__file__),   # .../app/api/routes/
        "..", "..", "..",             # .../backend/
        "templates",
    )
)

# ── registry ──────────────────────────────────────────────────────────────────
TEMPLATES = {
    "site":     "template_site.xlsx",
    "cell-3g":  "template_cell_3g.xlsx",
    "cell-4g":  "template_cell_4g.xlsx",
    "cell-5g":  "template_cell_5g.xlsx",
    "antenna":  "template_antenna.xlsx",      # ← NEW
}

DISPLAY_NAMES = {
    "site":     "Template_Site.xlsx",
    "cell-3g":  "Template_Cell_3G.xlsx",
    "cell-4g":  "Template_Cell_4G.xlsx",
    "cell-5g":  "Template_Cell_5G.xlsx",
    "antenna":  "Template_Antenna.xlsx",      # ← NEW
}


@router.get("/{template_name}")
def download_template(
    template_name: str,
    _=Depends(get_current_user),
):
    """
    Download an Excel import template.
    template_name: site | cell-3g | cell-4g | cell-5g | antenna
    """
    if template_name not in TEMPLATES:
        raise HTTPException(
            status_code=404,
            detail=(
                f"Template '{template_name}' not found. "
                f"Available: {list(TEMPLATES.keys())}"
            ),
        )

    file_path = os.path.join(TEMPLATE_DIR, TEMPLATES[template_name])
    if not os.path.exists(file_path):
        raise HTTPException(
            status_code=404,
            detail="Template file not found on server. Please contact administrator.",
        )

    return FileResponse(
        path=file_path,
        filename=DISPLAY_NAMES[template_name],
        media_type=(
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        ),
    )
PYTHON_EOF

# ===========================================================================
# 3.  FRONTEND – src/api/antenna.ts  (align dry-run return type)
# ===========================================================================
echo "[3/4] Updating frontend/src/api/antenna.ts …"
write_file "$FRONTEND_DIR/src/api/antenna.ts" << 'TS_EOF'
import api from './client'
import type { AntennaFull, CellDryRunResult, ImportResult } from '@/types'

// Re-export so callers don't need to import from @/types directly
export type { CellDryRunResult as AntennaDryRunResult, ImportResult as AntennaImportResult }

// ── CRUD ──────────────────────────────────────────────────────────────────────

export const getAntennas = (params?: Record<string, unknown>) =>
  api.get<AntennaFull[]>('/api/v1/antennas/', { params }).then((r) => r.data)

export const getAntenna = (id: number) =>
  api.get<AntennaFull>(`/api/v1/antennas/${id}`).then((r) => r.data)

export const createAntenna = (data: Partial<AntennaFull>) =>
  api.post<AntennaFull>('/api/v1/antennas/', data).then((r) => r.data)

export const updateAntenna = (id: number, data: Partial<AntennaFull>) =>
  api.put<AntennaFull>(`/api/v1/antennas/${id}`, data).then((r) => r.data)

export const deleteAntenna = (id: number) =>
  api.delete(`/api/v1/antennas/${id}`)

// ── Excel import ──────────────────────────────────────────────────────────────

/**
 * Dry-run: returns a preview without saving anything.
 * Response shape matches DryRunPreview used by DryRunModal.
 */
export const dryRunAntennaExcel = (file: File): Promise<CellDryRunResult> => {
  const form = new FormData()
  form.append('file', file)
  return api
    .post<CellDryRunResult>('/api/v1/antennas/import-excel/dry-run', form)
    .then((r) => {
      // The antenna dry-run endpoint does not return sites_to_create /
      // preview_new_sites – normalise the shape so DryRunModal is happy.
      const d = r.data as Record<string, unknown>
      return {
        to_create:        Number(d.to_create      ?? 0),
        to_update:        Number(d.to_update      ?? 0),
        sites_to_create:  0,
        errors:           Number(d.errors         ?? 0),
        error_details:    (d.error_details  as string[]) ?? [],
        preview_create:   (d.preview_create as string[]) ?? [],
        preview_update:   (d.preview_update as string[]) ?? [],
        preview_new_sites: [],
        dry_run:          true as const,
      } satisfies CellDryRunResult
    })
}

/**
 * Real import: creates / updates antennas and returns counts.
 */
export const importAntennaExcel = (file: File): Promise<ImportResult> => {
  const form = new FormData()
  form.append('file', file)
  return api
    .post<ImportResult>('/api/v1/antennas/import-excel', form)
    .then((r) => r.data)
}

// ── Spec file management ──────────────────────────────────────────────────────

export const uploadAntennaSpecFile = (id: number, file: File) => {
  const form = new FormData()
  form.append('file', file)
  return api
    .post<AntennaFull>(`/api/v1/antennas/${id}/spec-file`, form)
    .then((r) => r.data)
}

export const deleteAntennaSpecFile = (id: number) =>
  api.delete<AntennaFull>(`/api/v1/antennas/${id}/spec-file`).then((r) => r.data)

export async function downloadAntennaSpecFile(
  id: number,
  fileName: string,
): Promise<void> {
  const token = localStorage.getItem('sl_token') || ''
  const res   = await fetch(`/api/v1/antennas/${id}/spec-file/download`, {
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!res.ok) throw new Error(`Download failed (${res.status})`)
  const blob = await res.blob()
  const link = document.createElement('a')
  link.href     = URL.createObjectURL(blob)
  link.download = fileName
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(link.href)
}
TS_EOF

# ===========================================================================
# 4.  FRONTEND – AntennaPage.tsx  (wire up DryRunModal with templateKey)
# ===========================================================================
echo "[4/4] Updating frontend/src/pages/antenna/AntennaPage.tsx …"
write_file "$FRONTEND_DIR/src/pages/antenna/AntennaPage.tsx" << 'TSX_EOF'
import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Popconfirm,
  message, Row, Col, Modal, Form, InputNumber, Tooltip,
  Switch, Upload, Tag,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, SearchOutlined, UploadOutlined,
  EditOutlined, DeleteOutlined, DownloadOutlined,
  FilePdfOutlined, PaperClipOutlined, DeleteFilled,
} from '@ant-design/icons'
import {
  getAntennas, createAntenna, updateAntenna,
  deleteAntenna, dryRunAntennaExcel, importAntennaExcel,
  uploadAntennaSpecFile, deleteAntennaSpecFile, downloadAntennaSpecFile,
} from '@/api/antenna'
import { exportAntennas } from '@/api/export'
import type { AntennaFull } from '@/types'
import DryRunModal from '@/components/shared/DryRunModal'

// ── helpers ───────────────────────────────────────────────────────────────────

/** Sort so "CHƯA XÁC ĐỊNH" entries float to the top. */
function sortAntennas(list: AntennaFull[]): AntennaFull[] {
  return [...list].sort((a, b) => {
    const aU = a.name.toUpperCase()
    const bU = b.name.toUpperCase()
    const aFirst =
      aU.includes('CHƯA XÁC ĐỊNH') || aU.includes('CHUA XAC DINH')
    const bFirst =
      bU.includes('CHƯA XÁC ĐỊNH') || bU.includes('CHUA XAC DINH')
    if (aFirst && !bFirst) return -1
    if (!aFirst && bFirst) return  1
    return 0
  })
}

// ── component ─────────────────────────────────────────────────────────────────

export default function AntennaPage() {
  const [data,          setData]          = useState<AntennaFull[]>([])
  const [loading,       setLoading]       = useState(false)
  const [exporting,     setExporting]     = useState(false)
  const [search,        setSearch]        = useState('')
  const [modalOpen,     setModalOpen]     = useState(false)
  const [editing,       setEditing]       = useState<AntennaFull | null>(null)
  const [dryRunOpen,    setDryRunOpen]    = useState(false)
  const [detailOpen,    setDetailOpen]    = useState(false)
  const [selected,      setSelected]      = useState<AntennaFull | null>(null)
  const [specUploading, setSpecUploading] = useState<number | null>(null)
  const [specDeleting,  setSpecDeleting]  = useState<number | null>(null)
  const [form] = Form.useForm()

  // ── data loading ────────────────────────────────────────────────────────────

  const load = async () => {
    setLoading(true)
    try {
      const params: Record<string, unknown> = { limit: 2000 }
      if (search) params.search = search
      setData(sortAntennas(await getAntennas(params)))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [search])

  // ── export ──────────────────────────────────────────────────────────────────

  const handleExport = async () => {
    setExporting(true)
    try {
      await exportAntennas({ search: search || undefined })
      message.success(`Xuất Excel thành công (${data.length} antennas)`)
    } catch (e: any) {
      message.error(e?.message || 'Xuất thất bại')
    } finally {
      setExporting(false)
    }
  }

  // ── modal helpers ───────────────────────────────────────────────────────────

  const openCreate = () => {
    setEditing(null)
    form.resetFields()
    setModalOpen(true)
  }

  const openEdit = (r: AntennaFull) => {
    setEditing(r)
    form.setFieldsValue(r)
    setModalOpen(true)
  }

  const openDetail = (r: AntennaFull) => {
    setSelected(r)
    setDetailOpen(true)
  }

  // ── CRUD handlers ───────────────────────────────────────────────────────────

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) {
        await updateAntenna(editing.id, values)
        message.success('Cập nhật thành công')
      } else {
        await createAntenna(values)
        message.success('Tạo antenna thành công')
      }
      setModalOpen(false)
      load()
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Lỗi')
    }
  }

  const handleDelete = async (id: number) => {
    await deleteAntenna(id)
    message.success('Đã xóa')
    load()
  }

  // ── spec-file handlers ──────────────────────────────────────────────────────

  const handleSpecUpload = async (file: File, antenna: AntennaFull) => {
    if (file.type !== 'application/pdf') {
      message.error('Chỉ chấp nhận file PDF')
      return false
    }
    setSpecUploading(antenna.id)
    try {
      const updated = await uploadAntennaSpecFile(antenna.id, file)
      setData((prev) => prev.map((a) => (a.id === updated.id ? updated : a)))
      if (selected?.id === updated.id) setSelected(updated)
      message.success('Tải lên file spec thành công')
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Tải lên thất bại')
    } finally {
      setSpecUploading(null)
    }
    return false
  }

  const handleSpecDelete = async (antenna: AntennaFull) => {
    setSpecDeleting(antenna.id)
    try {
      const updated = await deleteAntennaSpecFile(antenna.id)
      setData((prev) => prev.map((a) => (a.id === updated.id ? updated : a)))
      if (selected?.id === updated.id) setSelected(updated)
      message.success('Đã xoá file spec')
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Xóa thất bại')
    } finally {
      setSpecDeleting(null)
    }
  }

  const handleSpecDownload = async (antenna: AntennaFull) => {
    try {
      await downloadAntennaSpecFile(
        antenna.id,
        antenna.spec_file_name || 'spec.pdf',
      )
    } catch (e: any) {
      message.error(e?.message || 'Tải xuống thất bại')
    }
  }

  // ── table columns ───────────────────────────────────────────────────────────

  const columns: ColumnsType<AntennaFull> = [
    {
      title: 'Hành động',
      key: 'action',
      fixed: 'left',
      width: 160,
      render: (_: unknown, r: AntennaFull) => (
        <Space size={4} wrap>
          <Button size="small" onClick={() => openDetail(r)}>Chi tiết</Button>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xóa antenna này?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    {
      title: 'Name', dataIndex: 'name', fixed: 'left', width: 280,
      render: (v: string) => <strong>{v}</strong>,
    },
    {
      title: '5G AAU', dataIndex: 'is_5g_aau', width: 85,
      render: (v: boolean) =>
        v ? <Tag color="purple">5G AAU</Tag> : <Tag color="default">-</Tag>,
    },
    { title: 'Band',           dataIndex: 'band',           width: 150 },
    { title: 'No of Ports',    dataIndex: 'no_of_ports',    width: 110 },
    { title: 'No of Beam',     dataIndex: 'no_of_beam',     width: 110 },
    { title: 'Horizontal BW',  dataIndex: 'horizontal_bw',  width: 120 },
    { title: 'Vertical BW',    dataIndex: 'vertical_bw',    width: 110 },
    { title: 'Gain',           dataIndex: 'gain',           width: 80  },
    { title: 'Etilt',          dataIndex: 'etilt',          width: 90  },
    { title: 'H (mm)',         dataIndex: 'h',              width: 80  },
    { title: 'W (mm)',         dataIndex: 'w',              width: 80  },
    { title: 'D (mm)',         dataIndex: 'd',              width: 80  },
    { title: 'Weight',         dataIndex: 'weight',         width: 80  },
    { title: 'Connector type', dataIndex: 'connector_type', width: 150 },
    {
      title: 'Specification (PDF)',
      key: 'spec_file',
      width: 230,
      render: (_: unknown, r: AntennaFull) => (
        <Space size={4} wrap>
          {r.spec_file_name ? (
            <>
              <Tooltip title={r.spec_file_name}>
                <Button
                  size="small"
                  type="link"
                  icon={<FilePdfOutlined style={{ color: '#f5222d' }} />}
                  onClick={() => handleSpecDownload(r)}
                  style={{
                    padding: 0, maxWidth: 130,
                    overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                  }}
                >
                  {r.spec_file_name.length > 16
                    ? r.spec_file_name.slice(0, 16) + '…'
                    : r.spec_file_name}
                </Button>
              </Tooltip>
              <Popconfirm
                title="Xóa file spec này?"
                onConfirm={() => handleSpecDelete(r)}
              >
                <Button
                  size="small" danger icon={<DeleteFilled />}
                  loading={specDeleting === r.id}
                />
              </Popconfirm>
            </>
          ) : (
            <Upload
              accept=".pdf"
              showUploadList={false}
              beforeUpload={(file) => handleSpecUpload(file, r)}
            >
              <Button
                size="small"
                icon={<PaperClipOutlined />}
                loading={specUploading === r.id}
              >
                Đính kèm PDF
              </Button>
            </Upload>
          )}
        </Space>
      ),
    },
    { title: 'Ghi chu', dataIndex: 'ghi_chu', width: 200 },
  ]

  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  // ── render ──────────────────────────────────────────────────────────────────

  return (
    <div>
      {/* ── page header ── */}
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>
          Thư viện Antenna
        </Typography.Title>
        <Space>
          <Tooltip title="Xuất dữ liệu hiện tại ra Excel">
            <Button
              icon={<DownloadOutlined />}
              loading={exporting}
              onClick={handleExport}
              style={{ borderColor: '#52c41a', color: '#52c41a' }}
            >
              Xuất Excel ({data.length})
            </Button>
          </Tooltip>
          {/* ── Import button – now opens the full DryRunModal ── */}
          <Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>
            Import Excel
          </Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
            Thêm mới
          </Button>
        </Space>
      </Row>

      {/* ── filter bar ── */}
      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="320px">
          <Input
            prefix={<SearchOutlined />}
            placeholder="Tìm tên antenna..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            allowClear
          />
        </Col>
        <Col>
          <Button onClick={() => setSearch('')}>Xóa lọc</Button>
        </Col>
        <Col>
          <Button onClick={load} loading={loading}>Làm mới</Button>
        </Col>
      </Row>

      {/* ── main table ── */}
      <Table
        columns={columns}
        dataSource={data}
        rowKey="id"
        loading={loading}
        size="small"
        scroll={{ x: scrollX, y: 600 }}
        bordered
        pagination={{
          pageSize: 50,
          showTotal: (t) => `${t} antennas`,
          showSizeChanger: true,
        }}
      />

      {/* ── Detail modal ── */}
      <Modal
        title={selected?.name}
        open={detailOpen}
        onCancel={() => setDetailOpen(false)}
        footer={
          <Space>
            {selected?.spec_file_name && (
              <Button
                icon={<FilePdfOutlined />}
                type="primary"
                onClick={() => selected && handleSpecDownload(selected)}
              >
                Tải Specification PDF
              </Button>
            )}
            <Button onClick={() => setDetailOpen(false)}>Đóng</Button>
          </Space>
        }
        width={620}
      >
        {selected && (
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            {(
              [
                ['5G AAU',         selected.is_5g_aau ? 'Có ✓' : 'Không'],
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
                ['Specification',  selected.spec_file_name || '(chưa đính kèm)'],
                ['Ghi chu',        selected.ghi_chu],
              ] as [string, unknown][]
            ).map(([label, val]) => (
              <tr key={label} style={{ borderBottom: '1px solid #f0f0f0' }}>
                <td style={{
                  padding: '6px 12px', fontWeight: 600,
                  width: 160, color: '#666',
                }}>
                  {label}
                </td>
                <td style={{ padding: '6px 12px' }}>
                  {label === 'Specification' && selected.spec_file_name ? (
                    <Button
                      type="link"
                      icon={<FilePdfOutlined style={{ color: '#f5222d' }} />}
                      onClick={() => handleSpecDownload(selected)}
                      style={{ padding: 0 }}
                    >
                      {selected.spec_file_name}
                    </Button>
                  ) : (
                    String(val ?? '-')
                  )}
                </td>
              </tr>
            ))}
          </table>
        )}
      </Modal>

      {/* ── Create / Edit modal ── */}
      <Modal
        title={editing ? 'Chỉnh sửa Antenna' : 'Thêm Antenna mới'}
        open={modalOpen}
        onOk={handleSave}
        onCancel={() => setModalOpen(false)}
        width={720}
        okText="Lưu"
        destroyOnClose
      >
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={24}>
              <Form.Item
                name="name"
                label="Name (định danh duy nhất)"
                rules={[{ required: true, message: 'Vui lòng nhập tên antenna' }]}
              >
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
            <Col span={6}>
              <Form.Item name="is_5g_aau" label="5G AAU" valuePropName="checked">
                <Switch checkedChildren="Có" unCheckedChildren="Không" />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="horizontal_bw" label="Horizontal BW">
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="vertical_bw" label="Vertical BW">
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="gain" label="Gain (dBi)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="etilt" label="Etilt range">
                <Input placeholder="vd: 0-10" />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="h" label="H – Height (mm)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="w" label="W – Width (mm)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="d" label="D – Depth (mm)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="weight" label="Weight (kg)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="connector_type" label="Connector type">
                <Input />
              </Form.Item>
            </Col>
            <Col span={24}>
              <Form.Item name="ghi_chu" label="Ghi chú">
                <Input.TextArea rows={2} />
              </Form.Item>
            </Col>

            {/* Spec file – only shown when editing an existing record */}
            {editing && (
              <Col span={24}>
                <Form.Item label="Specification PDF">
                  {editing.spec_file_name ? (
                    <Space>
                      <Button
                        icon={<FilePdfOutlined style={{ color: '#f5222d' }} />}
                        onClick={() =>
                          downloadAntennaSpecFile(
                            editing.id,
                            editing.spec_file_name!,
                          )
                        }
                      >
                        {editing.spec_file_name}
                      </Button>
                      <Popconfirm
                        title="Xóa file spec?"
                        onConfirm={async () => {
                          const updated = await deleteAntennaSpecFile(editing.id)
                          setEditing(updated)
                          setData((prev) =>
                            prev.map((a) => (a.id === updated.id ? updated : a)),
                          )
                        }}
                      >
                        <Button danger size="small">Xóa file</Button>
                      </Popconfirm>
                    </Space>
                  ) : (
                    <Upload
                      accept=".pdf"
                      showUploadList={false}
                      beforeUpload={async (file) => {
                        const updated = await uploadAntennaSpecFile(
                          editing.id, file,
                        )
                        setEditing(updated)
                        setData((prev) =>
                          prev.map((a) => (a.id === updated.id ? updated : a)),
                        )
                        message.success('Tải lên thành công')
                        return false
                      }}
                    >
                      <Button icon={<PaperClipOutlined />}>
                        Đính kèm file PDF
                      </Button>
                    </Upload>
                  )}
                </Form.Item>
              </Col>
            )}
          </Row>
        </Form>
      </Modal>

      {/* ── DryRunModal – full import wizard with template download ── */}
      <DryRunModal
        open={dryRunOpen}
        onClose={() => setDryRunOpen(false)}
        title="Import Antenna từ Excel"
        templateKey="antenna"
        dryRunFn={dryRunAntennaExcel}
        importFn={importAntennaExcel}
        onSuccess={load}
      />
    </div>
  )
}
TSX_EOF

# ===========================================================================
# 5.  FRONTEND – DryRunModal.tsx  (add "antenna" to TemplateKey union)
# ===========================================================================
echo "[5/5] Patching frontend/src/components/shared/DryRunModal.tsx …"

MODAL_FILE="$FRONTEND_DIR/src/components/shared/DryRunModal.tsx"

# Replace the TemplateKey type line to include 'antenna'
sed -i "s/export type TemplateKey = 'site' | 'cell-3g' | 'cell-4g' | 'cell-5g'/export type TemplateKey = 'site' | 'cell-3g' | 'cell-4g' | 'cell-5g' | 'antenna'/" "$MODAL_FILE"

# Replace the TEMPLATE_LABELS object to include the antenna entry
# We use a Python one-liner so we don't have to fight bash string escaping
python3 - "$MODAL_FILE" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    src = f.read()

old = """const TEMPLATE_LABELS: Record<TemplateKey, string> = {
  'site':    'Template_Site.xlsx',
  'cell-3g': 'Template_Cell_3G.xlsx',
  'cell-4g': 'Template_Cell_4G.xlsx',
  'cell-5g': 'Template_Cell_5G.xlsx',
}"""

new = """const TEMPLATE_LABELS: Record<TemplateKey, string> = {
  'site':    'Template_Site.xlsx',
  'cell-3g': 'Template_Cell_3G.xlsx',
  'cell-4g': 'Template_Cell_4G.xlsx',
  'cell-5g': 'Template_Cell_5G.xlsx',
  'antenna': 'Template_Antenna.xlsx',
}"""

if old in src:
    src = src.replace(old, new)
    with open(path, 'w') as f:
        f.write(src)
    print("  ✓  patched TEMPLATE_LABELS in DryRunModal.tsx")
else:
    print("  ⚠  TEMPLATE_LABELS block not found – check DryRunModal.tsx manually")
    print("     Add  'antenna': 'Template_Antenna.xlsx',  to TEMPLATE_LABELS.")
PYEOF

# ===========================================================================
# 6.  BACKEND – ensure template generation includes antenna
# ===========================================================================
echo ""
echo "[6/6] Checking backend/app/main.py for antenna template generation …"

MAIN_PY="$BACKEND_DIR/app/main.py"

# Check whether antenna template is already listed
if grep -q "template_antenna.xlsx" "$MAIN_PY"; then
  echo "  ✓  template_antenna.xlsx already referenced in main.py"
else
  echo "  ⚙  Patching main.py to include template_antenna.xlsx …"
  python3 - "$MAIN_PY" << 'PYEOF'
import sys

path = sys.argv[1]
with open(path, 'r') as f:
    src = f.read()

old_required = '''    required = [
        "template_site.xlsx", "template_cell_3g.xlsx",
        "template_cell_4g.xlsx", "template_cell_5g.xlsx",
    ]'''

new_required = '''    required = [
        "template_site.xlsx", "template_cell_3g.xlsx",
        "template_cell_4g.xlsx", "template_cell_5g.xlsx",
        "template_antenna.xlsx",
    ]'''

old_gen = '''                mod.create_site_template()
                mod.create_cell3g_template()
                mod.create_cell4g_template()
                mod.create_cell5g_template()'''

new_gen = '''                mod.create_site_template()
                mod.create_cell3g_template()
                mod.create_cell4g_template()
                mod.create_cell5g_template()
                if hasattr(mod, 'create_antenna_template'):
                    mod.create_antenna_template()'''

changed = False

if old_required in src:
    src = src.replace(old_required, new_required)
    changed = True

if old_gen in src:
    src = src.replace(old_gen, new_gen)
    changed = True

if changed:
    with open(path, 'w') as f:
        f.write(src)
    print("  ✓  patched main.py")
else:
    print("  ⚠  Could not auto-patch main.py.")
    print("     Please manually add 'template_antenna.xlsx' to the required list")
    print("     and call mod.create_antenna_template() in _generate_templates().")
PYEOF
fi

# ===========================================================================
# Done
# ===========================================================================
echo ""
echo "============================================================"
echo "  All updates applied successfully!"
echo "============================================================"
echo ""
echo "Next steps:"
echo "  1. Ensure backend/templates/template_antenna.xlsx exists."
echo "     Run:  python backend/create_templates.py"
echo ""
echo "  2. Restart the backend:"
echo "     cd backend && uvicorn app.main:app --reload"
echo ""
echo "  3. Rebuild / restart the frontend:"
echo "     cd frontend && npm run dev"
echo ""
echo "  4. Open the Antenna page → click 'Import Excel' to verify"
echo "     the 3-step wizard (template download, dry-run, import)."
echo "============================================================"