from collections import defaultdict
from typing import Optional
from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func, case

from app.db.session import get_db
from app.models.site import Site
from app.models.cell_3g import Cell3G
from app.models.cell_4g import Cell4G
from app.models.cell_5g import Cell5G
from app.utils.deps import get_current_user

router = APIRouter()


@router.get("/summary")
def report_summary(
    mien:          Optional[str] = Query(None),
    tinh:          Optional[str] = Query(None),
    vendor:        Optional[str] = Query(None),
    mimo:          Optional[str] = Query(None),
    vung_phu_song: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    """
    Group by (mien, tinh). One row per province.
    Uses bulk aggregation – no N+1 queries.
    """
    # ── 1. fetch matching sites ──────────────────────────────────────────
    site_q = db.query(Site)
    if mien:
        site_q = site_q.filter(Site.mien == mien)
    if tinh:
        site_q = site_q.filter(Site.tinh == tinh)
    sites = site_q.all()

    if not sites:
        return {"rows": [], "totals": {
            "mien": "TONG", "tinh": "",
            "site_count": 0,
            "site_2g": 0, "site_3g": 0, "site_4g": 0, "site_5g": 0,
            "cell_3g": 0, "cell_4g": 0, "cell_5g": 0,
        }}

    site_ids = [s.id for s in sites]

    # ── 2. bulk cell counts with a single query per technology ───────────
    def bulk_cell_counts(Model):
        q = (
            db.query(
                Model.site_id,
                func.count(Model.id).label("cnt"),
            )
            .filter(Model.site_id.in_(site_ids))
        )
        if vendor:
            q = q.filter(Model.vendor == vendor)
        if mimo:
            q = q.filter(Model.mimo == mimo)
        if vung_phu_song:
            q = q.filter(Model.vung_phu_song == vung_phu_song)
        q = q.group_by(Model.site_id)
        return {row.site_id: row.cnt for row in q.all()}

    counts_3g = bulk_cell_counts(Cell3G)
    counts_4g = bulk_cell_counts(Cell4G)
    counts_5g = bulk_cell_counts(Cell5G)

    # ── 3. aggregate by province ─────────────────────────────────────────
    province_map: dict = defaultdict(lambda: {
        "mien": "", "tinh": "",
        "site_count": 0,
        "site_2g": 0, "site_3g": 0, "site_4g": 0, "site_5g": 0,
        "cell_3g": 0, "cell_4g": 0, "cell_5g": 0,
    })

    for site in sites:
        key = (site.mien or "", site.tinh or "")
        row = province_map[key]
        row["mien"]       = site.mien or ""
        row["tinh"]       = site.tinh or ""
        row["site_count"] += 1
        if site.tram_2g: row["site_2g"] += 1
        if site.tram_3g: row["site_3g"] += 1
        if site.tram_4g: row["site_4g"] += 1
        if site.tram_5g: row["site_5g"] += 1
        row["cell_3g"] += counts_3g.get(site.id, 0)
        row["cell_4g"] += counts_4g.get(site.id, 0)
        row["cell_5g"] += counts_5g.get(site.id, 0)

    result = sorted(province_map.values(), key=lambda r: (r["mien"], r["tinh"]))

    totals = {
        "mien": "TONG", "tinh": "",
        "site_count": sum(r["site_count"] for r in result),
        "site_2g":    sum(r["site_2g"]    for r in result),
        "site_3g":    sum(r["site_3g"]    for r in result),
        "site_4g":    sum(r["site_4g"]    for r in result),
        "site_5g":    sum(r["site_5g"]    for r in result),
        "cell_3g":    sum(r["cell_3g"]    for r in result),
        "cell_4g":    sum(r["cell_4g"]    for r in result),
        "cell_5g":    sum(r["cell_5g"]    for r in result),
    }
    return {"rows": result, "totals": totals}


@router.get("/by-province")
def report_by_province(
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    rows = (
        db.query(Site.tinh, func.count(Site.id).label("site_count"))
        .filter(Site.tinh.isnot(None))
        .group_by(Site.tinh)
        .order_by(Site.tinh)
        .all()
    )
    return [{"tinh": r.tinh, "site_count": r.site_count} for r in rows]


@router.get("/cells-by-province")
def report_cells_by_province(
    tech: str = Query(..., description="3g | 4g | 5g"),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    model_map = {"3g": Cell3G, "4g": Cell4G, "5g": Cell5G}
    Model = model_map.get(tech)
    if Model is None:
        raise HTTPException(status_code=400, detail="tech must be 3g, 4g or 5g")
    rows = (
        db.query(Model.tinh, func.count(Model.id).label("cell_count"))
        .filter(Model.tinh.isnot(None))
        .group_by(Model.tinh)
        .order_by(Model.tinh)
        .all()
    )
    return [{"tinh": r.tinh, "cell_count": r.cell_count} for r in rows]


@router.get("/export-csv")
def export_csv(
    mien:          Optional[str] = Query(None),
    tinh:          Optional[str] = Query(None),
    vendor:        Optional[str] = Query(None),
    mimo:          Optional[str] = Query(None),
    vung_phu_song: Optional[str] = Query(None),
    token:         Optional[str] = Query(None),
    db: Session = Depends(get_db),
):
    from app.core.security import decode_access_token
    from app.models.user import User
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")
    payload = decode_access_token(token)
    if not payload:
        raise HTTPException(status_code=401, detail="Invalid token")
    user = db.query(User).filter(User.username == payload.get("sub")).first()
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="User inactive")

    from fastapi.responses import StreamingResponse
    import csv
    import io

    data = report_summary(
        mien=mien, tinh=tinh, vendor=vendor,
        mimo=mimo, vung_phu_song=vung_phu_song, db=db,
    )
    rows = data["rows"]
    output = io.StringIO()
    if rows:
        writer = csv.DictWriter(output, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    output.seek(0)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=report.csv"},
    )
