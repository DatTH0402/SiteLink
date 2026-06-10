from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.site import Site
from app.schemas.site import SiteCreate, SiteUpdate, SiteRead
from app.utils.deps import get_current_user
from app.utils.audit import log_action
from app.models.user import User
from app.services.import_excel import parse_site_excel

router = APIRouter()


def _site_or_404(db: Session, site_id: int) -> Site:
    s = db.query(Site).filter(Site.id == site_id).first()
    if not s:
        raise HTTPException(status_code=404, detail="Site not found")
    return s


@router.get("/", response_model=List[SiteRead])
def list_sites(
    skip: int = 0,
    limit: int = 500,
    search: Optional[str] = Query(None),
    mien:   Optional[str] = Query(None),
    tinh:   Optional[str] = Query(None),
    tram_3g: Optional[bool] = Query(None),
    tram_4g: Optional[bool] = Query(None),
    tram_5g: Optional[bool] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    q = db.query(Site)
    if search:
        q = q.filter(Site.site_name.ilike(f"%{search}%"))
    if mien:
        q = q.filter(Site.mien == mien)
    if tinh:
        q = q.filter(Site.tinh == tinh)
    if tram_3g is not None:
        q = q.filter(Site.tram_3g == tram_3g)
    if tram_4g is not None:
        q = q.filter(Site.tram_4g == tram_4g)
    if tram_5g is not None:
        q = q.filter(Site.tram_5g == tram_5g)
    return q.offset(skip).limit(limit).all()


@router.get("/count")
def count_sites(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return {"count": db.query(Site).count()}


@router.get("/{site_id}", response_model=SiteRead)
def get_site(site_id: int, db: Session = Depends(get_db), _=Depends(get_current_user)):
    return _site_or_404(db, site_id)


@router.post("/", response_model=SiteRead, status_code=201)
def create_site(
    payload: SiteCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    site = Site(**payload.model_dump(), created_by=current_user.id)
    db.add(site)
    db.commit()
    db.refresh(site)
    log_action(db, current_user, "CREATE", "sites", site.id,
               new_value=payload.model_dump())
    return site


@router.put("/{site_id}", response_model=SiteRead)
def update_site(
    site_id: int,
    payload: SiteUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    site = _site_or_404(db, site_id)
    old = {c.name: getattr(site, c.name) for c in site.__table__.columns}
    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(site, k, v)
    db.commit()
    db.refresh(site)
    log_action(db, current_user, "UPDATE", "sites", site.id,
               old_value=old, new_value=payload.model_dump(exclude_unset=True))
    return site


@router.delete("/{site_id}")
def delete_site(
    site_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    site = _site_or_404(db, site_id)
    db.delete(site)
    db.commit()
    log_action(db, current_user, "DELETE", "sites", site_id)
    return {"message": "Deleted"}


@router.post("/import-excel")
async def import_sites_excel(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    content = await file.read()
    try:
        records = parse_site_excel(content)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Cannot read Excel: {str(e)}")

    created, updated, errors = 0, 0, []

    for i, rec in enumerate(records):
        row_num = i + 2
        if "__error__" in rec:
            errors.append(f"Row {row_num}: {rec['__error__']}")
            continue
        if not rec.get("site_name"):
            errors.append(f"Row {row_num}: 'Site name' is empty")
            continue
        try:
            existing = db.query(Site).filter(
                Site.site_name == rec["site_name"]
            ).first()
            if existing:
                # UPDATE existing site with non-null values from Excel
                old = {c.name: getattr(existing, c.name)
                       for c in existing.__table__.columns}
                for k, v in rec.items():
                    if v is not None and k != "site_name":
                        setattr(existing, k, v)
                db.commit()
                log_action(db, current_user, "UPDATE", "sites",
                           existing.id, old_value=old, new_value=rec)
                updated += 1
            else:
                # CREATE new site
                site = Site(**rec, created_by=current_user.id)
                db.add(site)
                db.commit()
                log_action(db, current_user, "CREATE", "sites",
                           site.id, new_value=rec)
                created += 1
        except Exception as e:
            db.rollback()
            errors.append(f"Row {row_num}: {str(e)}")

    return {"created": created, "updated": updated, "errors": errors}