from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.dropdown import (
    DropdownTinhXaPhuong, DropdownAntenna, DropdownVendor, DropdownGeneral,
)
from app.utils.deps import get_current_user

router = APIRouter()


@router.get("/tinh-xa-phuong")
def get_tinh_xa_phuong(db: Session = Depends(get_db), _=Depends(get_current_user)):
    rows = db.query(DropdownTinhXaPhuong).all()
    return [
        {
            "id": r.id, "mien": r.mien, "ten_tinh": r.ten_tinh,
            "ten_phuong_xa": r.ten_phuong_xa, "ma_tinh": r.ma_tinh,
            "ma_phuong_xa": r.ma_phuong_xa, "ky_tu_1_6": r.ky_tu_1_6,
        }
        for r in rows
    ]


@router.get("/antenna")
def get_antenna(db: Session = Depends(get_db), _=Depends(get_current_user)):
    rows = db.query(DropdownAntenna).all()
    return [
        {"id": r.id, "name": r.name, "band": r.band,
         "no_of_ports": r.no_of_ports, "gain": r.gain}
        for r in rows
    ]


@router.get("/vendor")
def get_vendor(db: Session = Depends(get_db), _=Depends(get_current_user)):
    rows = db.query(DropdownVendor).all()
    return [
        {"id": r.id, "vendor_2g": r.vendor_2g, "vendor_3g": r.vendor_3g,
         "vendor_4g": r.vendor_4g, "vendor_5g": r.vendor_5g}
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
    ).all()
    return [{"id": r.id, "value": r.value, "label": r.label} for r in rows]
