from typing import Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.db.session import get_db
from app.models.site import Site
from app.models.cell_3g import Cell3G
from app.models.cell_4g import Cell4G
from app.models.cell_5g import Cell5G
from app.utils.deps import get_current_user

router = APIRouter()


@router.get("/summary")
def report_summary(
    mien: Optional[str] = Query(None),
    tinh: Optional[str] = Query(None),
    vendor: Optional[str] = Query(None),
    mimo: Optional[str] = Query(None),
    vung_phu_song: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    site_q = db.query(Site)
    if mien:
        site_q = site_q.filter(Site.mien == mien)
    if tinh:
        site_q = site_q.filter(Site.tinh == tinh)
    sites = site_q.all()

    def cell_count(Model, site_id: int) -> int:
        q = db.query(func.count(Model.id)).filter(Model.site_id == site_id)
        if vendor:
            q = q.filter(Model.vendor == vendor)
        if mimo:
            q = q.filter(Model.mimo == mimo)
        if vung_phu_song:
            q = q.filter(Model.vung_phu_song == vung_phu_song)
        return q.scalar() or 0

    result = []
    for site in sites:
        c3g = cell_count(Cell3G, site.id)
        c4g = cell_count(Cell4G, site.id)
        c5g = cell_count(Cell5G, site.id)
        result.append({
            "mien":     site.mien,
            "tinh":     site.tinh,
            "site_name": site.site_name,
            "site_2g":  1 if site.tram_2g else 0,
            "site_3g":  1 if site.tram_3g else 0,
            "site_4g":  1 if site.tram_4g else 0,
            "site_5g":  1 if site.tram_5g else 0,
            "cell_2g":  0,
            "cell_3g":  c3g,
            "cell_4g":  c4g,
            "cell_5g":  c5g,
        })

    totals = {
        "mien": "TONG", "tinh": "", "site_name": "",
        "site_2g": sum(r["site_2g"] for r in result),
        "site_3g": sum(r["site_3g"] for r in result),
        "site_4g": sum(r["site_4g"] for r in result),
        "site_5g": sum(r["site_5g"] for r in result),
        "cell_2g": 0,
        "cell_3g": sum(r["cell_3g"] for r in result),
        "cell_4g": sum(r["cell_4g"] for r in result),
        "cell_5g": sum(r["cell_5g"] for r in result),
    }
    return {"rows": result, "totals": totals}


@router.get("/export-csv")
def export_csv(
    mien: Optional[str] = Query(None),
    tinh: Optional[str] = Query(None),
    vendor: Optional[str] = Query(None),
    mimo: Optional[str] = Query(None),
    vung_phu_song: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    from fastapi.responses import StreamingResponse
    import csv, io
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
