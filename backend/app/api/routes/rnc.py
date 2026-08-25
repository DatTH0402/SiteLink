from typing import List, Optional
from fastapi import APIRouter, Depends, Query, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.rnc import RncName
from app.utils.deps import get_current_user, require_admin
from app.utils.template_regen import schedule_template_regen

router = APIRouter()


# ── Schemas ────────────────────────────────────────────────────────────────────

class RncCreate(BaseModel):
    vendor: str
    name:   str

class RncUpdate(BaseModel):
    vendor: Optional[str] = None
    name:   Optional[str] = None

class RncRead(BaseModel):
    id:     int
    vendor: str
    name:   str

    class Config:
        from_attributes = True


# ── Read endpoints ─────────────────────────────────────────────────────────────

@router.get("/")
def list_rnc_names(
    vendor: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    """Return RNC names, optionally filtered by vendor."""
    q = db.query(RncName)
    if vendor:
        q = q.filter(RncName.vendor == vendor)
    rows = q.order_by(RncName.vendor, RncName.name).all()
    return [{"id": r.id, "vendor": r.vendor, "name": r.name} for r in rows]


@router.get("/all")
def list_all_rnc_names(
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    """Return all RNC names grouped by vendor."""
    rows = db.query(RncName).order_by(RncName.vendor, RncName.name).all()
    result: dict = {}
    for r in rows:
        result.setdefault(r.vendor, []).append(r.name)
    return result


# ── Write endpoints (admin only) ───────────────────────────────────────────────

@router.post("/", response_model=RncRead, status_code=201)
def create_rnc_name(
    payload: RncCreate,
    db:      Session = Depends(get_db),
    _=Depends(require_admin),
):
    """Create a new RNC name entry."""
    existing = db.query(RncName).filter(
        RncName.vendor == payload.vendor,
        RncName.name   == payload.name,
    ).first()
    if existing:
        raise HTTPException(
            status_code=400,
            detail=f"RNC '{payload.name}' already exists for vendor '{payload.vendor}'",
        )
    obj = RncName(vendor=payload.vendor, name=payload.name)
    db.add(obj)
    db.commit()
    db.refresh(obj)
    schedule_template_regen()
    return obj


@router.put("/{rnc_id}", response_model=RncRead)
def update_rnc_name(
    rnc_id:  int,
    payload: RncUpdate,
    db:      Session = Depends(get_db),
    _=Depends(require_admin),
):
    """Update an existing RNC name entry."""
    obj = db.query(RncName).filter(RncName.id == rnc_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail="RNC name not found")
    if payload.vendor is not None:
        obj.vendor = payload.vendor
    if payload.name is not None:
        obj.name = payload.name
    db.commit()
    db.refresh(obj)
    schedule_template_regen()
    return obj


@router.delete("/{rnc_id}")
def delete_rnc_name(
    rnc_id: int,
    db:     Session = Depends(get_db),
    _=Depends(require_admin),
):
    """Delete an RNC name entry."""
    obj = db.query(RncName).filter(RncName.id == rnc_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail="RNC name not found")
    db.delete(obj)
    db.commit()
    schedule_template_regen()
    return {"message": "Deleted"}
