#!/bin/bash
set -e

BACKEND="./backend/app"

# ─────────────────────────────────────────────────────────────────────────────
# fix_revision_5g_500.sh
#
# Root cause:
#   backend/app/api/routes/revision.py list_cell5g_revisions() references
#   r.nr_arfcn which does NOT exist on Cell5GRevision model.
#   The model has: ssb_arfcn, center_arfcn, gscn, bandwidth, nci, mu_mimo.
#   Accessing a non-existent SQLAlchemy attribute raises AttributeError
#   which FastAPI converts to a 500 response.
#
# Fix:
#   Rewrite revision.py with the correct field names for every technology,
#   cross-checked against the actual model columns defined in
#   backend/app/models/cell_revision.py.
# ─────────────────────────────────────────────────────────────────────────────

cat > "${BACKEND}/api/routes/revision.py" << 'PYEOF'
"""
revision.py  –  Read-only API for revision history.

Field names in each _fmt_rev() call are cross-checked against the actual
SQLAlchemy model columns in app/models/cell_revision.py to avoid
AttributeError → HTTP 500.
"""
from __future__ import annotations

import json
from typing import Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from sqlalchemy import desc

from app.db.session import get_db
from app.models.site_revision import SiteRevision
from app.models.cell_revision import Cell3GRevision, Cell4GRevision, Cell5GRevision
from app.utils.deps import get_current_user

router = APIRouter()


def _fmt_rev(rev, extra: dict = None) -> dict:
    base = {
        "id":              rev.id,
        "revision_no":     rev.revision_no,
        "changed_by_name": rev.changed_by_name or "",
        "change_source":   rev.change_source,
        "change_note":     rev.change_note,
        "changed_fields":  json.loads(rev.changed_fields)
                           if rev.changed_fields else {},
        "created_at":      rev.created_at.isoformat()
                           if rev.created_at else None,
    }
    if extra:
        base.update(extra)
    return base


# ── Site revisions ────────────────────────────────────────────────────────────

@router.get("/sites")
def list_site_revisions(
    site_id:   Optional[int] = Query(None),
    site_name: Optional[str] = Query(None),
    skip:      int = 0,
    limit:     int = 200,
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    q = db.query(SiteRevision)
    if site_id:
        q = q.filter(SiteRevision.site_id == site_id)
    if site_name:
        q = q.filter(
            SiteRevision.site_name.ilike(f"%{site_name}%") |
            SiteRevision.site_name_old_ref.ilike(f"%{site_name}%")
        )
    rows = q.order_by(desc(SiteRevision.created_at)).offset(skip).limit(limit).all()
    return [
        _fmt_rev(r, {
            "site_id":               r.site_id,
            "site_name":             r.site_name,
            "site_name_old_ref":     r.site_name_old_ref,
            "mien":                  r.mien,
            "tinh":                  r.tinh,
            "phuong_xa":             r.phuong_xa,
            "site_name_cu":          r.site_name_cu,
            "site_vip":              r.site_vip,
            "lat":                   r.lat,
            "long":                  r.long,
            "tram_2g":               r.tram_2g,
            "tram_3g":               r.tram_3g,
            "tram_4g":               r.tram_4g,
            "tram_5g":               r.tram_5g,
            "repeater":              r.repeater,
            "booster":               r.booster,
            "node_truyen_dan_only":  r.node_truyen_dan_only,
            "tram_phu_song_tsca":    r.tram_phu_song_tsca,
            "phan_loai_tram":        r.phan_loai_tram,
            "moran_3g":              r.moran_3g,
            "moran_4g":              r.moran_4g,
            "moran_5g":              r.moran_5g,
            "ma_ptm":                r.ma_ptm,
            "do_cao_dinh_cot_anten": r.do_cao_dinh_cot_anten,
            "do_cao_cot_anten":      r.do_cao_cot_anten,
            "dia_chi":               r.dia_chi,
            "ghi_chu":               r.ghi_chu,
        })
        for r in rows
    ]


@router.get("/sites/{site_id}")
def get_site_revisions(
    site_id: int,
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    return list_site_revisions(site_id=site_id, db=db)


# ── Cell 3G revisions ─────────────────────────────────────────────────────────
# Model columns (cell_revision.py → Cell3GRevision):
#   cell_id_ref, site_id, site_name, cell_name, revision_no,
#   changed_by, changed_by_name, change_source, change_note,
#   mien, tinh, phuong_xa, site_name_old, cell_name_old,
#   cell_vip, moran, lat, long, vung_phu_song, vendor,
#   do_cao_anten, azimuth, m_tilt, e_tilt, total_tilt,
#   loai_anten, chung_anten, baseband, rf, cell_id,
#   arfcn, uarfcn, lac, rac, psc, ura_id, mimo,
#   cell_max_power, cpich_power, bbu_name, cell_status,
#   changed_fields, created_at

@router.get("/cells-3g")
def list_cell3g_revisions(
    cell_id:   Optional[int] = Query(None),
    site_name: Optional[str] = Query(None),
    cell_name: Optional[str] = Query(None),
    skip:      int = 0,
    limit:     int = 200,
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    q = db.query(Cell3GRevision)
    if cell_id:
        q = q.filter(Cell3GRevision.cell_id_ref == cell_id)
    if site_name:
        q = q.filter(
            Cell3GRevision.site_name.ilike(f"%{site_name}%") |
            Cell3GRevision.site_name_old.ilike(f"%{site_name}%")
        )
    if cell_name:
        q = q.filter(
            Cell3GRevision.cell_name.ilike(f"%{cell_name}%") |
            Cell3GRevision.cell_name_old.ilike(f"%{cell_name}%")
        )
    rows = (
        q.order_by(desc(Cell3GRevision.created_at))
         .offset(skip).limit(limit).all()
    )
    return [
        _fmt_rev(r, {
            "cell_id_ref":   r.cell_id_ref,
            "site_id":       r.site_id,
            "site_name":     r.site_name,
            "site_name_old": r.site_name_old,
            "cell_name":     r.cell_name,
            "cell_name_old": r.cell_name_old,
            "mien":          r.mien,
            "tinh":          r.tinh,
            "phuong_xa":     r.phuong_xa,
            "cell_vip":      r.cell_vip,
            "moran":         r.moran,
            "lat":           r.lat,
            "long":          r.long,
            "vung_phu_song": r.vung_phu_song,
            "vendor":        r.vendor,
            "do_cao_anten":  r.do_cao_anten,
            "azimuth":       r.azimuth,
            "m_tilt":        r.m_tilt,
            "e_tilt":        r.e_tilt,
            "total_tilt":    r.total_tilt,
            "loai_anten":    r.loai_anten,
            "chung_anten":   r.chung_anten,
            "baseband":      r.baseband,
            "rf":            r.rf,
            "cell_id":       r.cell_id,
            # 3G-specific
            "arfcn":         r.arfcn,
            "uarfcn":        r.uarfcn,
            "lac":           r.lac,
            "rac":           r.rac,
            "psc":           r.psc,
            "ura_id":        r.ura_id,
            "mimo":          r.mimo,
            "cell_max_power": r.cell_max_power,
            "cpich_power":   r.cpich_power,
            "bbu_name":      r.bbu_name,
            "cell_status":   r.cell_status,
        })
        for r in rows
    ]


# ── Cell 4G revisions ─────────────────────────────────────────────────────────
# Model columns (cell_revision.py → Cell4GRevision):
#   cell_id_ref, site_id, site_name, cell_name, revision_no,
#   changed_by, changed_by_name, change_source, change_note,
#   mien, tinh, phuong_xa, site_name_old, cell_name_old,
#   cell_vip, moran, lat, long, vung_phu_song, vendor,
#   do_cao_anten, azimuth, m_tilt, e_tilt, total_tilt,
#   loai_anten, chung_anten, baseband, rf,
#   enodeb_id, cell_id, earfcn, tac, pci, root_sequence_id,
#   mimo, bandwidth, cell_max_power, eci,
#   bbu_name, cell_status, changed_fields, created_at

@router.get("/cells-4g")
def list_cell4g_revisions(
    cell_id:   Optional[int] = Query(None),
    site_name: Optional[str] = Query(None),
    cell_name: Optional[str] = Query(None),
    skip:      int = 0,
    limit:     int = 200,
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    q = db.query(Cell4GRevision)
    if cell_id:
        q = q.filter(Cell4GRevision.cell_id_ref == cell_id)
    if site_name:
        q = q.filter(
            Cell4GRevision.site_name.ilike(f"%{site_name}%") |
            Cell4GRevision.site_name_old.ilike(f"%{site_name}%")
        )
    if cell_name:
        q = q.filter(
            Cell4GRevision.cell_name.ilike(f"%{cell_name}%") |
            Cell4GRevision.cell_name_old.ilike(f"%{cell_name}%")
        )
    rows = (
        q.order_by(desc(Cell4GRevision.created_at))
         .offset(skip).limit(limit).all()
    )
    return [
        _fmt_rev(r, {
            "cell_id_ref":    r.cell_id_ref,
            "site_id":        r.site_id,
            "site_name":      r.site_name,
            "site_name_old":  r.site_name_old,
            "cell_name":      r.cell_name,
            "cell_name_old":  r.cell_name_old,
            "mien":           r.mien,
            "tinh":           r.tinh,
            "phuong_xa":      r.phuong_xa,
            "cell_vip":       r.cell_vip,
            "moran":          r.moran,
            "lat":            r.lat,
            "long":           r.long,
            "vung_phu_song":  r.vung_phu_song,
            "vendor":         r.vendor,
            "do_cao_anten":   r.do_cao_anten,
            "azimuth":        r.azimuth,
            "m_tilt":         r.m_tilt,
            "e_tilt":         r.e_tilt,
            "total_tilt":     r.total_tilt,
            "loai_anten":     r.loai_anten,
            "chung_anten":    r.chung_anten,
            "baseband":       r.baseband,
            "rf":             r.rf,
            # 4G-specific
            "enodeb_id":      r.enodeb_id,
            "cell_id":        r.cell_id,
            "earfcn":         r.earfcn,
            "tac":            r.tac,
            "pci":            r.pci,
            "root_sequence_id": r.root_sequence_id,
            "mimo":           r.mimo,
            "bandwidth":      r.bandwidth,
            "cell_max_power": r.cell_max_power,
            "eci":            r.eci,
            "bbu_name":       r.bbu_name,
            "cell_status":    r.cell_status,
        })
        for r in rows
    ]


# ── Cell 5G revisions ─────────────────────────────────────────────────────────
# Model columns (cell_revision.py → Cell5GRevision):
#   cell_id_ref, site_id, site_name, cell_name, revision_no,
#   changed_by, changed_by_name, change_source, change_note,
#   mien, tinh, phuong_xa, site_name_old, cell_name_old,
#   cell_vip, moran, lat, long, vung_phu_song, vendor,
#   do_cao_anten, azimuth, m_tilt, e_tilt, total_tilt,
#   loai_anten, baseband, rf,
#   gnodeb_id, cell_id, tac, pci, root_sequence_id, mimo,
#   ssb_arfcn, center_arfcn, gscn, bandwidth,
#   cell_max_power, nci, bbu_name, mu_mimo, cell_status,
#   changed_fields, created_at
#
# NOTE: Cell5GRevision does NOT have:
#   nr_arfcn   ← was referenced in old code → caused HTTP 500
#   arfcn      ← 3G only
#   earfcn     ← 4G only
#   chung_anten← 3G/4G only

@router.get("/cells-5g")
def list_cell5g_revisions(
    cell_id:   Optional[int] = Query(None),
    site_name: Optional[str] = Query(None),
    cell_name: Optional[str] = Query(None),
    skip:      int = 0,
    limit:     int = 200,
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    q = db.query(Cell5GRevision)
    if cell_id:
        q = q.filter(Cell5GRevision.cell_id_ref == cell_id)
    if site_name:
        q = q.filter(
            Cell5GRevision.site_name.ilike(f"%{site_name}%") |
            Cell5GRevision.site_name_old.ilike(f"%{site_name}%")
        )
    if cell_name:
        q = q.filter(
            Cell5GRevision.cell_name.ilike(f"%{cell_name}%") |
            Cell5GRevision.cell_name_old.ilike(f"%{cell_name}%")
        )
    rows = (
        q.order_by(desc(Cell5GRevision.created_at))
         .offset(skip).limit(limit).all()
    )
    return [
        _fmt_rev(r, {
            "cell_id_ref":      r.cell_id_ref,
            "site_id":          r.site_id,
            "site_name":        r.site_name,
            "site_name_old":    r.site_name_old,
            "cell_name":        r.cell_name,
            "cell_name_old":    r.cell_name_old,
            "mien":             r.mien,
            "tinh":             r.tinh,
            "phuong_xa":        r.phuong_xa,
            "cell_vip":         r.cell_vip,
            "moran":            r.moran,
            "lat":              r.lat,
            "long":             r.long,
            "vung_phu_song":    r.vung_phu_song,
            "vendor":           r.vendor,
            "do_cao_anten":     r.do_cao_anten,
            "azimuth":          r.azimuth,
            "m_tilt":           r.m_tilt,
            "e_tilt":           r.e_tilt,
            "total_tilt":       r.total_tilt,
            "loai_anten":       r.loai_anten,
            # 5G-specific (NO chung_anten, NO arfcn/earfcn/nr_arfcn)
            "baseband":         r.baseband,
            "rf":               r.rf,
            "gnodeb_id":        r.gnodeb_id,
            "cell_id":          r.cell_id,
            "tac":              r.tac,
            "pci":              r.pci,
            "root_sequence_id": r.root_sequence_id,
            "mimo":             r.mimo,
            "ssb_arfcn":        r.ssb_arfcn,
            "center_arfcn":     r.center_arfcn,
            "gscn":             r.gscn,
            "bandwidth":        r.bandwidth,
            "cell_max_power":   r.cell_max_power,
            "nci":              r.nci,
            "bbu_name":         r.bbu_name,
            "mu_mimo":          r.mu_mimo,
            "cell_status":      r.cell_status,
        })
        for r in rows
    ]
PYEOF

echo "✓ Patched backend/app/api/routes/revision.py"

# ── Verify no stray nr_arfcn references remain ────────────────────────────────
if grep -r "nr_arfcn" "${BACKEND}/api/routes/revision.py" 2>/dev/null; then
    echo "✗ ERROR: nr_arfcn still present in revision.py!"
    exit 1
else
    echo "✓ Verified: no stray nr_arfcn references in revision.py"
fi

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "  Patch applied."
echo ""
echo "  Root cause:"
echo "    list_cell5g_revisions() referenced r.nr_arfcn which does not"
echo "    exist on Cell5GRevision model → AttributeError → HTTP 500."
echo "    The Cell5GRevision model uses ssb_arfcn / center_arfcn / gscn"
echo "    instead of nr_arfcn."
echo ""
echo "  What changed in revision.py:"
echo "    Cell 5G  – removed nr_arfcn, added ssb_arfcn, center_arfcn,"
echo "               gscn, bandwidth, nci, mu_mimo, gnodeb_id, tac,"
echo "               root_sequence_id (all matching model columns exactly)"
echo "    Cell 3G  – explicit field list replacing old implicit access"
echo "    Cell 4G  – explicit field list replacing old implicit access"
echo "    Sites    – unchanged (was already correct)"
echo ""
echo "  Restart backend:"
echo "    docker compose restart backend"
echo "════════════════════════════════════════════════════════════════════"