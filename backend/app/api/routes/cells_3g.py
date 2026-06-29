from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.cell_3g import Cell3G
from app.models.site import Site
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


def _require_site(db: Session, site_id: int) -> Site:
    site = db.query(Site).filter(Site.id == site_id).first()
    if not site:
        raise HTTPException(
            status_code=400,
            detail=f"Site id={site_id} not found. Please create the site first.",
        )
    return site


def _ensure_site(db: Session, rec: dict, current_user: User) -> int:
    """Return site_id, auto-creating the site if necessary."""
    site_name = rec.get("site_name", "").strip()
    site = db.query(Site).filter(Site.site_name == site_name).first()
    if site:
        return site.id
    # Auto-create minimal site
    new_site = Site(
        site_name=site_name,
        mien=rec.get("mien") or "",
        tinh=rec.get("tinh") or "",
        phuong_xa=rec.get("phuong_xa"),
        lat=rec.get("lat"),
        long=rec.get("long"),
        created_by=current_user.id,
    )
    db.add(new_site)
    db.commit()
    db.refresh(new_site)
    return new_site.id


@router.get("/", response_model=List[Cell3GRead])
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
    q = db.query(Cell3G)
    if search:
        q = q.filter(
            Cell3G.cell_name.ilike(f"%{search}%") |
            Cell3G.site_name.ilike(f"%{search}%")
        )
    if mien:          q = q.filter(Cell3G.mien == mien)
    if tinh:          q = q.filter(Cell3G.tinh == tinh)
    if vendor:        q = q.filter(Cell3G.vendor == vendor)
    if mimo:          q = q.filter(Cell3G.mimo == mimo)
    if vung_phu_song: q = q.filter(Cell3G.vung_phu_song == vung_phu_song)
    return q.offset(skip).limit(limit).all()


@router.get("/count")
def count_cells(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return {"count": db.query(Cell3G).count()}


# ── Dry-run preview ──────────────────────────────────────────────────────────
@router.post("/import-excel/dry-run")
async def dry_run_excel(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    content = await file.read()
    try:
        result = parse_cell3g_excel(content, db=db, dry_run=True)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Cannot read Excel: {e}")

    return {
        "to_create":        len(result["to_create"]),
        "to_update":        len(result["to_update"]),
        "sites_to_create":  len(result["sites_to_create"]),
        "errors":           len(result["errors"]),
        "error_details":    result["errors"][:50],
        "preview_create":   [r["cell_name"] for r in result["to_create"][:5]],
        "preview_update":   [u["anchor"]    for u in result["to_update"][:5]],
        "preview_new_sites":[r["site_name"] for r in result["sites_to_create"][:5]],
        "dry_run":          True,
    }


# ── Actual import ────────────────────────────────────────────────────────────
@router.post("/import-excel")
async def import_excel(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    content = await file.read()
    try:
        result = parse_cell3g_excel(content, db=db, dry_run=False)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Cannot read Excel: {e}")

    errors  = list(result["errors"])
    created, updated, sites_auto_created = 0, 0, 0

    # ── Create new cells ──────────────────────────────────────────────────
    for rec in result["to_create"]:
        try:
            site_id = _ensure_site(db, rec, current_user)
            if site_id != rec.get("site_id"):
                sites_auto_created += 1
            rec["site_id"] = site_id
            cell = Cell3G(**{k: v for k, v in rec.items()
                             if hasattr(Cell3G, k)},
                          created_by=current_user.id)
            db.add(cell)
            db.commit()
            created += 1
        except Exception as e:
            db.rollback()
            errors.append(f"Create cell '{rec.get('cell_name')}': {e}")

    # ── Update existing cells ─────────────────────────────────────────────
    for upd in result["to_update"]:
        try:
            existing = db.query(Cell3G).filter(
                Cell3G.id == upd["existing_id"]
            ).first()
            if not existing:
                errors.append(f"Cell '{upd['anchor']}' disappeared during import")
                continue
            changes = upd["changes"]
            for k, v in changes.items():
                if k in ("cell_name", "site_id"):
                    continue        # anchors – never overwrite
                if v is not None and hasattr(existing, k):
                    setattr(existing, k, v)
            db.commit()
            updated += 1
        except Exception as e:
            db.rollback()
            errors.append(f"Update cell '{upd['anchor']}': {e}")

    return {
        "created": created,
        "updated": updated,
        "sites_auto_created": sites_auto_created,
        "errors": errors,
    }


@router.get("/{cell_id}", response_model=Cell3GRead)
def get_cell(cell_id: int,
             db: Session = Depends(get_db),
             _=Depends(get_current_user)):
    return _or_404(db, cell_id)


@router.post("/", response_model=Cell3GRead, status_code=201)
def create_cell(
    payload: Cell3GCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_site(db, payload.site_id)
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
    old  = {c.name: getattr(cell, c.name) for c in cell.__table__.columns}
    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(cell, k, v)
    db.commit()
    db.refresh(cell)
    log_action(db, current_user, "UPDATE", "cells_3g", cell.id,
               old_value=old,
               new_value=payload.model_dump(exclude_unset=True))
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
