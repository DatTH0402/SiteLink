from typing import List, Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.rnc import RncName
from app.utils.deps import get_current_user

router = APIRouter()


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
