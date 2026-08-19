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
