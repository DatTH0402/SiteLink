import traceback
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.site import Site
from app.models.cell_3g import Cell3G
from app.models.cell_4g import Cell4G
from app.models.cell_5g import Cell5G
from app.schemas.site import SiteCreate, SiteUpdate, SiteRead
from app.utils.deps import get_current_user
from app.utils.audit import log_action
from app.models.user import User
from app.services.import_excel import parse_site_excel
from app.services.revision import record_site_revision, _site_snapshot

router = APIRouter()

_SITE_BOOL_FIELDS = frozenset({
    'tram_2g', 'tram_3g', 'tram_4g', 'tram_5g',
    'repeater', 'booster', 'node_truyen_dan_only', 'tram_phu_song_tsca',
})


def _to_bool(value) -> bool:
    """Robustly convert any value to Python bool."""
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return bool(value)
    if isinstance(value, str):
        if value.lower() in ('true', 'yes', '1', 'on'):
            return True
        if value.lower() in ('false', 'no', '0', 'off', ''):
            return False
    if value is None:
        return False
    # Last resort
    return bool(value)


def _sanitize_site(obj: Site) -> None:
    """
    Ensure all boolean columns on a Site ORM object hold real Python booleans.
    Call this AFTER setattr() and BEFORE flush/snapshot to prevent SQLAlchemy
    from passing strings to psycopg2's boolean adapter.
    """
    for field in _SITE_BOOL_FIELDS:
        raw = getattr(obj, field, None)
        if not isinstance(raw, bool):
            setattr(obj, field, _to_bool(raw))


def _sanitize_changes(changes: dict) -> dict:
    """Coerce boolean-field values in a changes dict to real Python booleans."""
    out = {}
    for k, v in changes.items():
        if k in _SITE_BOOL_FIELDS:
            out[k] = _to_bool(v)
        else:
            out[k] = v
    return out


def _site_or_404(db: Session, site_id: int) -> Site:
    s = db.query(Site).filter(Site.id == site_id).first()
    if not s:
        raise HTTPException(status_code=404, detail="Site not found")
    return s


# ── Static routes FIRST ──────────────────────────────────────────────────────

@router.get("/count")
def count_sites(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return {"count": db.query(Site).count()}


@router.post("/import-excel/dry-run")
async def dry_run_sites_excel(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    content = await file.read()
    try:
        result = parse_site_excel(content, db=db, dry_run=True)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Cannot read Excel: {e}")

    to_create = result["to_create"]
    to_update = result["to_update"]
    errors    = result["errors"]

    return {
        "to_create":      len(to_create),
        "to_update":      len(to_update),
        "errors":         len(errors),
        "error_details":  errors[:50],
        "preview_create": [r["site_name"] for r in to_create[:5]],
        "preview_update": [u["anchor"]    for u in to_update[:5]],
        "dry_run":        True,
    }


@router.post("/import-excel")
async def import_sites_excel(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    content = await file.read()
    try:
        result = parse_site_excel(content, db=db, dry_run=False)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Cannot read Excel: {e}")

    to_create = result["to_create"]
    to_update = result["to_update"]
    errors    = list(result["errors"])
    created, updated = 0, 0

    for rec in to_create:
        try:
            site = Site(**rec, created_by=current_user.id)
            db.add(site)
            db.flush()
            record_site_revision(
                db, site, old_snapshot=None,
                changed_by_id=current_user.id,
                changed_by_name=current_user.full_name or current_user.username,
                change_source="excel",
            )
            db.commit()
            log_action(db, current_user, "CREATE", "sites", site.id, new_value=rec)
            created += 1
        except Exception as e:
            db.rollback()
            errors.append(f"Create '{rec.get('site_name')}': {e}")

    for upd in to_update:
        try:
            existing = db.query(Site).filter(Site.id == upd["existing_id"]).first()
            if not existing:
                errors.append(f"Site '{upd['anchor']}' disappeared during import")
                continue
            old_snap = _site_snapshot(existing)
            old_name = existing.site_name
            changes  = upd["changes"]

            new_site_name = changes.get("site_name")
            site_name_old_ref = None
            if new_site_name and new_site_name != old_name:
                site_name_old_ref = old_name

            for k, v in changes.items():
                if v is not None:
                    setattr(existing, k, v)
            _sanitize_site(existing)
            db.flush()
            record_site_revision(
                db, existing, old_snapshot=old_snap,
                changed_by_id=current_user.id,
                changed_by_name=current_user.full_name or current_user.username,
                change_source="excel",
                site_name_old_ref=site_name_old_ref,
            )
            db.commit()
            log_action(db, current_user, "UPDATE", "sites",
                       existing.id, old_value=old_snap, new_value=changes)
            updated += 1
        except Exception as e:
            db.rollback()
            errors.append(f"Update '{upd['anchor']}': {e}")

    return {"created": created, "updated": updated, "errors": errors}


@router.get("/", response_model=List[SiteRead])
def list_sites(
    skip: int = 0,
    limit: int = 500,
    search:  Optional[str]       = Query(None),
    mien:    Optional[List[str]] = Query(None),
    tinh:    Optional[List[str]] = Query(None),
    tram_3g: Optional[bool]      = Query(None),
    tram_4g: Optional[bool]      = Query(None),
    tram_5g: Optional[bool]      = Query(None),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    q = db.query(Site)
    if search: q = q.filter(Site.site_name.ilike(f"%{search}%"))
    if mien:   q = q.filter(Site.mien.in_(mien))
    if tinh:   q = q.filter(Site.tinh.in_(tinh))
    if tram_3g is not None: q = q.filter(Site.tram_3g == tram_3g)
    if tram_4g is not None: q = q.filter(Site.tram_4g == tram_4g)
    if tram_5g is not None: q = q.filter(Site.tram_5g == tram_5g)
    return q.offset(skip).limit(limit).all()


@router.post("/bulk-delete")
def bulk_delete_sites(
    payload: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    ids = payload.get("ids", [])
    if not ids:
        raise HTTPException(status_code=400, detail="No IDs provided")

    errors = []
    deleted = 0
    for site_id in ids:
        site = db.query(Site).filter(Site.id == site_id).first()
        if not site:
            errors.append(f"Site id={site_id} not found")
            continue
        cell_count = (
            db.query(Cell3G).filter(Cell3G.site_id == site_id).count()
            + db.query(Cell4G).filter(Cell4G.site_id == site_id).count()
            + db.query(Cell5G).filter(Cell5G.site_id == site_id).count()
        )
        if cell_count > 0:
            errors.append(f"Site '{site.site_name}' has {cell_count} cell(s) – skipped")
            continue
        try:
            db.delete(site)
            db.commit()
            log_action(db, current_user, "DELETE", "sites", site_id)
            deleted += 1
        except Exception as e:
            db.rollback()
            errors.append(f"Site id={site_id}: {e}")

    return {"deleted": deleted, "errors": errors}


@router.post("/bulk-update")
def bulk_update_sites(
    payload: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    ids     = payload.get("ids", [])
    changes = payload.get("changes", {})

    if not ids:
        raise HTTPException(status_code=400, detail="No IDs provided")
    if not changes:
        raise HTTPException(status_code=400, detail="No changes provided")

    PROTECTED = {"id", "site_name", "created_by", "created_at", "updated_at"}
    safe_changes = {k: v for k, v in changes.items() if k not in PROTECTED}

    if not safe_changes:
        raise HTTPException(
            status_code=400,
            detail="No updatable fields provided after removing protected fields"
        )

    valid_columns = {c.name for c in Site.__table__.columns}
    unknown = [k for k in safe_changes if k not in valid_columns]
    if unknown:
        raise HTTPException(status_code=400, detail=f"Unknown field(s): {unknown}")

    # Coerce boolean strings → real Python booleans in the changes dict
    safe_changes = _sanitize_changes(safe_changes)

    errors:  list[str] = []
    updated: int       = 0

    for site_id in ids:
        try:
            # Always use a fresh query to avoid stale identity-map objects
            db.expire_all()
            site = db.query(Site).filter(Site.id == site_id).first()
            if not site:
                errors.append(f"Site id={site_id} not found")
                continue

            old_snap = _site_snapshot(site)

            for k, v in safe_changes.items():
                setattr(site, k, v)

            # CRITICAL: ensure all boolean columns are real Python booleans
            # AFTER setattr, BEFORE flush/snapshot. This is the definitive fix.
            _sanitize_site(site)

            db.flush()

            record_site_revision(
                db, site,
                old_snapshot=old_snap,
                changed_by_id=current_user.id,
                changed_by_name=current_user.full_name or current_user.username,
                change_source="form",
                change_note="Bulk update",
            )

            db.commit()

            try:
                log_action(
                    db, current_user, "UPDATE", "sites", site_id,
                    old_value=old_snap,
                    new_value=safe_changes,
                )
            except Exception as log_err:
                print(f"[WARN] log_action failed for site {site_id}: {log_err}")

            updated += 1

        except Exception as e:
            tb = traceback.format_exc()
            print(f"[ERROR] bulk_update_sites – site_id={site_id}: {e}\n{tb}")
            try:
                db.rollback()
            except Exception:
                pass
            errors.append(f"Site id={site_id}: {str(e)}")

    return {"updated": updated, "errors": errors}


@router.post("/", response_model=SiteRead, status_code=201)
def create_site(
    payload: SiteCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    existing = db.query(Site).filter(Site.site_name == payload.site_name).first()
    if existing:
        raise HTTPException(status_code=400,
                            detail=f"Site '{payload.site_name}' already exists")
    site = Site(**payload.model_dump(), created_by=current_user.id)
    db.add(site)
    db.flush()
    record_site_revision(
        db, site, old_snapshot=None,
        changed_by_id=current_user.id,
        changed_by_name=current_user.full_name or current_user.username,
        change_source="form",
    )
    db.commit()
    db.refresh(site)
    log_action(db, current_user, "CREATE", "sites", site.id,
               new_value=payload.model_dump())
    return site


@router.get("/{site_id}", response_model=SiteRead)
def get_site(site_id: int, db: Session = Depends(get_db), _=Depends(get_current_user)):
    return _site_or_404(db, site_id)


@router.put("/{site_id}", response_model=SiteRead)
def update_site(
    site_id: int,
    payload: SiteUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    site = _site_or_404(db, site_id)
    old_snap  = _site_snapshot(site)
    old_name  = site.site_name
    data      = payload.model_dump(exclude_unset=True)

    new_site_name = data.get("site_name")
    site_name_old_ref = None
    if new_site_name and new_site_name != old_name:
        site_name_old_ref = old_name

    for k, v in data.items():
        setattr(site, k, v)
    _sanitize_site(site)
    db.flush()
    record_site_revision(
        db, site, old_snapshot=old_snap,
        changed_by_id=current_user.id,
        changed_by_name=current_user.full_name or current_user.username,
        change_source="form",
        site_name_old_ref=site_name_old_ref,
    )
    db.commit()
    db.refresh(site)
    log_action(db, current_user, "UPDATE", "sites", site.id,
               old_value=old_snap, new_value=data)
    return site


@router.delete("/{site_id}")
def delete_site(
    site_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    site = _site_or_404(db, site_id)
    cell_count = (
        db.query(Cell3G).filter(Cell3G.site_id == site_id).count()
        + db.query(Cell4G).filter(Cell4G.site_id == site_id).count()
        + db.query(Cell5G).filter(Cell5G.site_id == site_id).count()
    )
    if cell_count > 0:
        raise HTTPException(status_code=400,
            detail=f"Cannot delete. This site contains {cell_count} cell(s). "
                   f"Please delete the cells first.")
    db.delete(site)
    db.commit()
    log_action(db, current_user, "DELETE", "sites", site_id)
    return {"message": "Deleted"}
