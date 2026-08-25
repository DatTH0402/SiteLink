from typing import Optional, List
from fastapi import APIRouter, Depends, Query, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.dropdown import (
    DropdownTinhXaPhuong, DropdownAntenna, DropdownVendor, DropdownGeneral,
)
from app.models.antenna import Antenna
from app.utils.deps import get_current_user, require_admin
from app.utils.template_regen import schedule_template_regen

router = APIRouter()


# ── Schemas ────────────────────────────────────────────────────────────────────

class DropdownGeneralCreate(BaseModel):
    category: str
    value:    str
    label:    Optional[str] = None

class DropdownGeneralUpdate(BaseModel):
    value: Optional[str] = None
    label: Optional[str] = None


# ── Read endpoints ─────────────────────────────────────────────────────────────

@router.get("/tinh-xa-phuong")
def get_tinh_xa_phuong(
    tinh: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    q = db.query(DropdownTinhXaPhuong)
    if tinh:
        q = q.filter(DropdownTinhXaPhuong.ten_tinh == tinh)
    rows = q.order_by(
        DropdownTinhXaPhuong.ten_tinh,
        DropdownTinhXaPhuong.ten_phuong_xa,
    ).all()
    return [
        {
            "id": r.id, "mien": r.mien, "ten_tinh": r.ten_tinh,
            "ten_phuong_xa": r.ten_phuong_xa, "ma_tinh": r.ma_tinh,
            "ma_phuong_xa": r.ma_phuong_xa, "ky_tu_1_6": r.ky_tu_1_6,
        }
        for r in rows
    ]


@router.get("/tinh-list")
def get_tinh_list(
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    rows = (
        db.query(
            DropdownTinhXaPhuong.ten_tinh,
            DropdownTinhXaPhuong.mien,
        )
        .distinct()
        .order_by(DropdownTinhXaPhuong.ten_tinh)
        .all()
    )
    return [{"ten_tinh": r.ten_tinh, "mien": r.mien} for r in rows]


@router.get("/antenna")
def get_antenna(db: Session = Depends(get_db), _=Depends(get_current_user)):
    """
    Returns from the new 'antennas' managed table (full detail).
    Falls back to legacy dropdown_antenna if antennas table is empty.
    """
    rows = db.query(Antenna).order_by(Antenna.name).all()
    if rows:
        return [
            {
                "id":             r.id,
                "name":           r.name,
                "band":           r.band,
                "no_of_ports":    r.no_of_ports,
                "no_of_beam":     r.no_of_beam,
                "horizontal_bw":  r.horizontal_bw,
                "vertical_bw":    r.vertical_bw,
                "gain":           r.gain,
                "etilt":          r.etilt,
                "h":              r.h,
                "w":              r.w,
                "d":              r.d,
                "weight":         r.weight,
                "connector_type": r.connector_type,
                "ghi_chu":        r.ghi_chu,
            }
            for r in rows
        ]
    # Legacy fallback
    legacy = db.query(DropdownAntenna).order_by(DropdownAntenna.name).all()
    return [
        {
            "id": r.id, "name": r.name, "band": r.band,
            "no_of_ports": r.no_of_ports, "gain": r.gain,
            "no_of_beam": None, "horizontal_bw": None, "vertical_bw": None,
            "etilt": None, "h": None, "w": None, "d": None,
            "weight": None, "connector_type": None, "ghi_chu": None,
        }
        for r in legacy
    ]


@router.get("/vendor")
def get_vendor(db: Session = Depends(get_db), _=Depends(get_current_user)):
    rows = db.query(DropdownVendor).all()
    return [
        {
            "id": r.id, "vendor_2g": r.vendor_2g, "vendor_3g": r.vendor_3g,
            "vendor_4g": r.vendor_4g, "vendor_5g": r.vendor_5g,
        }
        for r in rows
    ]


@router.get("/general/{category}")
def get_general(
    category: str,
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    rows = db.query(DropdownGeneral).filter(
        DropdownGeneral.category == category
    ).order_by(DropdownGeneral.value).all()
    return [{"id": r.id, "value": r.value, "label": r.label} for r in rows]


# ── Write endpoints for dropdown_general (admin only) ─────────────────────────

# Categories that affect Excel templates when changed
_TEMPLATE_CATEGORIES = {
    "phan_loai_tram",   # site template
    "moran",            # site + cell templates
    "mien",             # site + cell templates
    "vung_phu_song",    # cell templates
    "mimo",             # cell templates
    "site_vip",         # site template
}


@router.post("/general", status_code=201)
def create_general(
    payload: DropdownGeneralCreate,
    db:      Session = Depends(get_db),
    _=Depends(require_admin),
):
    """Create a new general dropdown entry."""
    existing = db.query(DropdownGeneral).filter(
        DropdownGeneral.category == payload.category,
        DropdownGeneral.value    == payload.value,
    ).first()
    if existing:
        raise HTTPException(
            status_code=400,
            detail=f"Value '{payload.value}' already exists in category '{payload.category}'",
        )
    obj = DropdownGeneral(
        category=payload.category,
        value=payload.value,
        label=payload.label or payload.value,
    )
    db.add(obj)
    db.commit()
    db.refresh(obj)
    if payload.category in _TEMPLATE_CATEGORIES:
        schedule_template_regen()
    return {"id": obj.id, "value": obj.value, "label": obj.label}


@router.put("/general/{item_id}")
def update_general(
    item_id: int,
    payload: DropdownGeneralUpdate,
    db:      Session = Depends(get_db),
    _=Depends(require_admin),
):
    """Update an existing general dropdown entry."""
    obj = db.query(DropdownGeneral).filter(DropdownGeneral.id == item_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail="Dropdown item not found")
    if payload.value is not None:
        obj.value = payload.value
    if payload.label is not None:
        obj.label = payload.label
    db.commit()
    db.refresh(obj)
    if obj.category in _TEMPLATE_CATEGORIES:
        schedule_template_regen()
    return {"id": obj.id, "value": obj.value, "label": obj.label}


@router.delete("/general/{item_id}")
def delete_general(
    item_id: int,
    db:      Session = Depends(get_db),
    _=Depends(require_admin),
):
    """Delete a general dropdown entry."""
    obj = db.query(DropdownGeneral).filter(DropdownGeneral.id == item_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail="Dropdown item not found")
    category = obj.category
    db.delete(obj)
    db.commit()
    if category in _TEMPLATE_CATEGORIES:
        schedule_template_regen()
    return {"message": "Deleted"}
