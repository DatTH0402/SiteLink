from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.cell_3g import Cell3G
from app.schemas.cell import Cell3GCreate, Cell3GUpdate, Cell3GRead
from app.utils.deps import get_current_user
from app.utils.audit import log_action
from app.models.user import User
from app.services.import_excel import parse_cell3g_excel

router = APIRouter()


def _or_404(db: Session, record_id: int) -> Cell3G:
    obj = db.query(Cell3G).filter(Cell3G.id == record_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail="Cell not found")
    return obj


@router.get("/", response_model=List[Cell3GRead])
def list_cells(
    skip: int = 0,
    limit: int = 200,
    search: Optional[str] = Query(None),
    mien: Optional[str] = Query(None),
    tinh: Optional[str] = Query(None),
    vendor: Optional[str] = Query(None),
    mimo: Optional[str] = Query(None),
    vung_phu_song: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    q = db.query(Cell3G)
    if search:
        q = q.filter(
            Cell3G.cell_name.ilike(f"%{search}%") |
            Cell3G.site_name.ilike(f"%{search}%")
        )
    if mien:
        q = q.filter(Cell3G.mien == mien)
    if tinh:
        q = q.filter(Cell3G.tinh == tinh)
    if vendor:
        q = q.filter(Cell3G.vendor == vendor)
    if mimo:
        q = q.filter(Cell3G.mimo == mimo)
    if vung_phu_song:
        q = q.filter(Cell3G.vung_phu_song == vung_phu_song)
    return q.offset(skip).limit(limit).all()


@router.get("/count")
def count_cells(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return {"count": db.query(Cell3G).count()}


@router.get("/{cell_id}", response_model=Cell3GRead)
def get_cell(cell_id: int, db: Session = Depends(get_db), _=Depends(get_current_user)):
    return _or_404(db, cell_id)


@router.post("/", response_model=Cell3GRead, status_code=201)
def create_cell(
    payload: Cell3GCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    cell = Cell3G(**payload.model_dump(), created_by=current_user.id)
    db.add(cell)
    db.commit()
    db.refresh(cell)
    log_action(db, current_user, "CREATE", "cells_3g", cell.id,
               new_value=payload.model_dump())
    return cell


@router.put("/{cell_id}", response_model=Cell3GRead)
def update_cell(
    cell_id: int,
    payload: Cell3GUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    cell = _or_404(db, cell_id)
    old = {c.name: getattr(cell, c.name) for c in cell.__table__.columns}
    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(cell, k, v)
    db.commit()
    db.refresh(cell)
    log_action(db, current_user, "UPDATE", "cells_3g", cell.id,
               old_value=old, new_value=payload.model_dump(exclude_unset=True))
    return cell


@router.delete("/{cell_id}")
def delete_cell(
    cell_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    cell = _or_404(db, cell_id)
    db.delete(cell)
    db.commit()
    log_action(db, current_user, "DELETE", "cells_3g", cell_id)
    return {"message": "Deleted"}


@router.post("/import-excel")
async def import_excel(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from app.models.site import Site
    content = await file.read()
    records = parse_cell3g_excel(content)
    created, errors = 0, []
    for i, rec in enumerate(records):
        try:
            site = db.query(Site).filter(
                Site.site_name == rec.get("site_name")
            ).first()
            if not site:
                errors.append(
                    f"Row {i+2}: site_name '{rec.get('site_name')}' not found"
                )
                continue
            rec["site_id"] = site.id
            cell = Cell3G(**rec, created_by=current_user.id)
            db.add(cell)
            db.commit()
            created += 1
        except Exception as e:
            db.rollback()
            errors.append(f"Row {i+2}: {str(e)}")
    return {"created": created, "errors": errors}
