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
from app.services.import_excel import parse_cell5g_excel, _CLEAR
from app.services.revision import record_cell5g_revision, _cell5g_snapshot

router = APIRouter()


def _or_404(db: Session, record_id: int) -> Cell5G:
    obj = db.query(Cell5G).filter(Cell5G.id == record_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail="Cell not found")
    return obj


def _ensure_site(db: Session, rec: dict, current_user: User) -> int:
    site_name = rec.get("site_name", "").strip()
    site = db.query(Site).filter(Site.site_name == site_name).first()
    if site:
        return site.id
    new_site = Site(
        site_name=site_name, mien=rec.get("mien") or "",
        tinh=rec.get("tinh") or "", phuong_xa=rec.get("phuong_xa"),
        lat=rec.get("lat"), long=rec.get("long"), created_by=current_user.id,
    )
    db.add(new_site); db.commit(); db.refresh(new_site)
    return new_site.id


def _apply_cell_changes(existing: Cell5G, changes: dict,
                         skip_keys: set = None, is_rename: bool = False) -> None:
    if skip_keys is None:
        skip_keys = set()
    for k, v in changes.items():
        if k in skip_keys or k.startswith("_"):
            continue
        if v is _CLEAR:
            continue
        if k == "cell_name" and not is_rename:
            continue
        if k == "site_id":
            continue
        if hasattr(existing, k):
            setattr(existing, k, v)


@router.get("/", response_model=List[Cell5GRead])
def list_cells(
    skip: int = 0, limit: int = 500,
    search: Optional[str] = Query(None),
    mien:   Optional[List[str]] = Query(None),
    tinh:   Optional[List[str]] = Query(None),
    vendor: Optional[List[str]] = Query(None),
    mimo:   Optional[List[str]] = Query(None),
    vung_phu_song: Optional[List[str]] = Query(None),
    db: Session = Depends(get_db), _=Depends(get_current_user),
):
    q = db.query(Cell5G)
    if search:        q = q.filter(Cell5G.cell_name.ilike(f"%{search}%") | Cell5G.site_name.ilike(f"%{search}%"))
    if mien:          q = q.filter(Cell5G.mien.in_(mien))
    if tinh:          q = q.filter(Cell5G.tinh.in_(tinh))
    if vendor:        q = q.filter(Cell5G.vendor.in_(vendor))
    if mimo:          q = q.filter(Cell5G.mimo.in_(mimo))
    if vung_phu_song: q = q.filter(Cell5G.vung_phu_song.in_(vung_phu_song))
    return q.offset(skip).limit(limit).all()


@router.get("/count")
def count_cells(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return {"count": db.query(Cell5G).count()}


@router.post("/bulk-delete")
def bulk_delete(
    payload: dict, db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    ids = payload.get("ids", [])
    if not ids: raise HTTPException(status_code=400, detail="No IDs provided")
    errors, deleted = [], 0
    for cid in ids:
        cell = db.query(Cell5G).filter(Cell5G.id == cid).first()
        if not cell: errors.append(f"Cell id={cid} not found"); continue
        try:
            db.delete(cell); db.commit()
            log_action(db, current_user, "DELETE", "cells_5g", cid)
            deleted += 1
        except Exception as e:
            db.rollback(); errors.append(f"Cell id={cid}: {e}")
    return {"deleted": deleted, "errors": errors}


@router.post("/bulk-update")
def bulk_update(
    payload: dict, db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    ids     = payload.get("ids", [])
    changes = payload.get("changes", {})
    if not ids: raise HTTPException(status_code=400, detail="No IDs provided")
    if not changes: raise HTTPException(status_code=400, detail="No changes provided")
    for f in ("id", "cell_name", "site_id", "created_by", "created_at", "updated_at"):
        changes.pop(f, None)
    errors, updated = [], 0
    for cid in ids:
        cell = db.query(Cell5G).filter(Cell5G.id == cid).first()
        if not cell: errors.append(f"Cell id={cid} not found"); continue
        try:
            old_snap = _cell5g_snapshot(cell)
            for k, v in changes.items():
                if hasattr(cell, k): setattr(cell, k, v)
            db.flush()
            rev = record_cell5g_revision(db, cell, old_snapshot=old_snap,
                changed_by_id=current_user.id,
                changed_by_name=current_user.full_name or current_user.username,
                change_source="form", change_note="Bulk update")
            db.commit()
            if rev is not None:
                log_action(db, current_user, "UPDATE", "cells_5g", cid,
                           old_value=old_snap, new_value=changes)
                updated += 1
        except Exception as e:
            db.rollback(); errors.append(f"Cell id={cid}: {e}")
    return {"updated": updated, "errors": errors}


@router.post("/import-excel/dry-run")
async def dry_run_excel(
    file: UploadFile = File(...), db: Session = Depends(get_db), _=Depends(get_current_user),
):
    content = await file.read()
    try: result = parse_cell5g_excel(content, db=db, dry_run=True)
    except Exception as e: raise HTTPException(status_code=400, detail=f"Cannot read Excel: {e}")
    return {
        "to_create": len(result["to_create"]), "to_update": len(result["to_update"]),
        "sites_to_create": len(result["sites_to_create"]),
        "errors": len(result["errors"]), "error_details": result["errors"][:50],
        "preview_create": [r["cell_name"] for r in result["to_create"][:5]],
        "preview_update": [u["anchor"] for u in result["to_update"][:5]],
        "preview_new_sites": [r["site_name"] for r in result["sites_to_create"][:5]],
        "dry_run": True,
    }


@router.post("/import-excel")
async def import_excel(
    file: UploadFile = File(...), db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    content = await file.read()
    try: result = parse_cell5g_excel(content, db=db, dry_run=False)
    except Exception as e: raise HTTPException(status_code=400, detail=f"Cannot read Excel: {e}")
    errors  = list(result["errors"])
    created, updated, skipped, sites_auto_created = 0, 0, 0, 0
    for rec in result["to_create"]:
        try:
            site_id = _ensure_site(db, rec, current_user)
            if site_id != rec.get("site_id"): sites_auto_created += 1
            rec["site_id"] = site_id
            clean = {k: v for k, v in rec.items()
                     if v is not _CLEAR and hasattr(Cell5G, k)}
            cell = Cell5G(**clean, created_by=current_user.id)
            db.add(cell); db.flush()
            record_cell5g_revision(db, cell, old_snapshot=None,
                changed_by_id=current_user.id,
                changed_by_name=current_user.full_name or current_user.username,
                change_source="excel")
            db.commit(); created += 1
        except Exception as e:
            db.rollback(); errors.append(f"Create cell '{rec.get('cell_name')}': {e}")
    for upd in result["to_update"]:
        try:
            existing = db.query(Cell5G).filter(Cell5G.id == upd["existing_id"]).first()
            if not existing: errors.append(f"Cell '{upd['anchor']}' disappeared"); continue
            old_snap = _cell5g_snapshot(existing)
            is_rename = upd.get("is_rename", False)
            _apply_cell_changes(existing, upd["changes"], is_rename=is_rename)
            db.flush()
            rev = record_cell5g_revision(db, existing, old_snapshot=old_snap,
                changed_by_id=current_user.id,
                changed_by_name=current_user.full_name or current_user.username,
                change_source="excel")
            db.commit()
            if rev is None: skipped += 1
            else: updated += 1
        except Exception as e:
            db.rollback(); errors.append(f"Update cell '{upd['anchor']}': {e}")
    return {"created": created, "updated": updated,
            "skipped_no_change": skipped, "sites_auto_created": sites_auto_created,
            "errors": errors}


@router.get("/{cell_id}", response_model=Cell5GRead)
def get_cell(cell_id: int, db: Session = Depends(get_db), _=Depends(get_current_user)):
    return _or_404(db, cell_id)


@router.post("/", response_model=Cell5GRead, status_code=201)
def create_cell(
    payload: Cell5GCreate, db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if not db.query(Site).filter(Site.id == payload.site_id).first():
        raise HTTPException(status_code=400, detail=f"Site id={payload.site_id} not found.")
    cell = Cell5G(**payload.model_dump(), created_by=current_user.id)
    db.add(cell); db.flush()
    record_cell5g_revision(db, cell, old_snapshot=None,
        changed_by_id=current_user.id,
        changed_by_name=current_user.full_name or current_user.username,
        change_source="form")
    db.commit(); db.refresh(cell)
    log_action(db, current_user, "CREATE", "cells_5g", cell.id, new_value=payload.model_dump())
    return cell


@router.put("/{cell_id}", response_model=Cell5GRead)
def update_cell(
    cell_id: int, payload: Cell5GUpdate,
    db: Session = Depends(get_db), current_user: User = Depends(get_current_user),
):
    cell = _or_404(db, cell_id)
    old_snap = _cell5g_snapshot(cell)
    old_dict = {c.name: getattr(cell, c.name) for c in cell.__table__.columns}
    data = payload.model_dump(exclude_unset=True)
    for k, v in data.items(): setattr(cell, k, v)
    db.flush()
    rev = record_cell5g_revision(db, cell, old_snapshot=old_snap,
        changed_by_id=current_user.id,
        changed_by_name=current_user.full_name or current_user.username,
        change_source="form")
    db.commit(); db.refresh(cell)
    if rev is not None:
        log_action(db, current_user, "UPDATE", "cells_5g", cell.id,
                   old_value=old_dict, new_value=data)
    return cell


@router.delete("/{cell_id}")
def delete_cell(
    cell_id: int, db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    cell = _or_404(db, cell_id)
    db.delete(cell); db.commit()
    log_action(db, current_user, "DELETE", "cells_5g", cell_id)
    return {"message": "Deleted"}
