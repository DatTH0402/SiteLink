from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.cell_5g import Cell5G
from app.models.site import Site
from app.schemas.cell import Cell5GCreate, Cell5GUpdate, Cell5GRead
from app.utils.deps import get_current_user
from app.utils.audit import log_action
from app.models.user import User
from app.services.import_excel import parse_cell5g_excel

router = APIRouter()


def _or_404(db: Session, record_id: int) -> Cell5G:
    obj = db.query(Cell5G).filter(Cell5G.id == record_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail="Cell not found")
    return obj


def _get_or_create_site(db: Session, rec: dict, user_id: int) -> Optional[Site]:
    """Find site by name. If not found, create a minimal one from cell data."""
    site_name = rec.get("site_name", "").strip()
    if not site_name:
        return None
    site = db.query(Site).filter(Site.site_name == site_name).first()
    if not site:
        site = Site(
            site_name=site_name,
            mien=rec.get("mien"),
            tinh=rec.get("tinh"),
            phuong_xa=rec.get("phuong_xa"),
            lat=rec.get("lat"),
            long=rec.get("long"),
            created_by=user_id,
        )
        db.add(site)
        db.commit()
        db.refresh(site)
    return site


@router.get("/", response_model=List[Cell5GRead])
def list_cells(
    skip: int = 0,
    limit: int = 500,
    search:        Optional[str] = Query(None),
    mien:          Optional[str] = Query(None),
    tinh:          Optional[str] = Query(None),
    vendor:        Optional[str] = Query(None),
    mimo:          Optional[str] = Query(None),
    vung_phu_song: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
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
    return q.offset(skip).limit(limit).all()


@router.get("/count")
def count_cells(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return {"count": db.query(Cell5G).count()}


@router.get("/{cell_id}", response_model=Cell5GRead)
def get_cell(cell_id: int, db: Session = Depends(get_db), _=Depends(get_current_user)):
    return _or_404(db, cell_id)


@router.post("/", response_model=Cell5GRead, status_code=201)
def create_cell(
    payload: Cell5GCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    cell = Cell5G(**payload.model_dump(), created_by=current_user.id)
    db.add(cell)
    db.commit()
    db.refresh(cell)
    log_action(db, current_user, "CREATE", "cells_5g", cell.id,
               new_value=payload.model_dump())
    return cell


@router.put("/{cell_id}", response_model=Cell5GRead)
def update_cell(
    cell_id: int,
    payload: Cell5GUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    cell = _or_404(db, cell_id)
    old = {c.name: getattr(cell, c.name) for c in cell.__table__.columns}
    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(cell, k, v)
    db.commit()
    db.refresh(cell)
    log_action(db, current_user, "UPDATE", "cells_5g", cell.id,
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
    log_action(db, current_user, "DELETE", "cells_5g", cell_id)
    return {"message": "Deleted"}


@router.post("/import-excel")
async def import_excel(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    content = await file.read()
    try:
        records = parse_cell5g_excel(content)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Cannot read Excel: {str(e)}")

    created, skipped, errors = 0, 0, []
    sites_auto_created = 0

    for i, rec in enumerate(records):
        row_num = i + 2
        if not rec.get("cell_name"):
            errors.append(f"Row {row_num}: 'Cell Name' is empty")
            continue
        try:
            # Auto-create site if not found
            site = _get_or_create_site(db, rec, current_user.id)
            if not site:
                errors.append(f"Row {row_num}: cannot determine site_name")
                continue

            # Track if we auto-created this site
            if site.created_by == current_user.id:
                sites_auto_created += 1

            rec["site_id"] = site.id

            # Check duplicate cell
            existing = db.query(Cell5G).filter(
                Cell5G.site_id == site.id,
                Cell5G.cell_name == rec["cell_name"],
            ).first()
            if existing:
                # Update existing cell
                for k, v in rec.items():
                    if v is not None and k not in ("cell_name", "site_id"):
                        setattr(existing, k, v)
                db.commit()
                skipped += 1
            else:
                cell = Cell5G(**rec, created_by=current_user.id)
                db.add(cell)
                db.commit()
                created += 1
        except Exception as e:
            db.rollback()
            errors.append(f"Row {row_num}: {str(e)}")

    return {
        "created": created,
        "updated": skipped,
        "sites_auto_created": sites_auto_created,
        "errors": errors,
    }