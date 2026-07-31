"""
revision.py – Service layer for revision history snapshots.

Rules:
  - CREATE (old_snapshot is None)  → always record (revision_no=1).
  - UPDATE with changes            → record with diff.
  - UPDATE with NO changes         → skip entirely (return None).
"""
from __future__ import annotations

import json
from typing import Any, Dict, Optional
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.models.site_revision import SiteRevision
from app.models.cell_revision import Cell3GRevision, Cell4GRevision, Cell5GRevision
from app.models.site import Site
from app.models.cell_3g import Cell3G
from app.models.cell_4g import Cell4G
from app.models.cell_5g import Cell5G

def _safe_bool(v) -> bool:
    """
    Robustly convert any DB-returned value to Python bool.
    Handles: None, real bool, int (0/1), and string ("false"/"true"/"0"/"1").
    This is necessary because psycopg2 can return the PostgreSQL text
    representation ("false"/"true") instead of a Python bool when the
    server_default is a text expression and the ORM type-map is bypassed.
    """
    if v is None:
        return False
    if isinstance(v, bool):
        return v
    if isinstance(v, int):
        return v != 0
    if isinstance(v, str):
        return v.strip().lower() not in ("false", "0", "no", "off", "")
    return bool(v)




def _normalize(v: Any) -> Any:
    """
    Normalize a value for diff comparison.
    - None and "" are both treated as "empty" (None).
    - False is kept as False (meaningful value, NOT treated as empty).
    - 0 is kept as 0 (meaningful value).
    """
    if v is None or v == "":
        return None
    # Normalize boolean-like integers from DB (psycopg2 may return 0/1)
    if v is True or v == 1 and not isinstance(v, bool):
        return True
    if v is False or v == 0 and not isinstance(v, bool):
        # Only treat int 0 as False-equivalent, not string "0"
        pass
    return v


def _normalize_for_diff(v: Any) -> Any:
    """
    Stricter normalization for diff: treat None/"" as None, booleans as canonical bool.
    """
    if v is None or v == "":
        return None
    if isinstance(v, bool):
        return v
    if isinstance(v, int) and v in (0, 1):
        # psycopg2 sometimes returns int for bool columns
        return bool(v)
    if isinstance(v, str) and v.lower() in ("true", "false"):
        return v.lower() == "true"
    return v


def _diff(old: Dict, new: Dict) -> Dict:
    """Return {field: [old_val, new_val]} for every field that changed."""
    result = {}
    all_keys = set(old) | set(new)
    for k in all_keys:
        ov = _normalize_for_diff(old.get(k))
        nv = _normalize_for_diff(new.get(k))
        if ov != nv:
            result[k] = [old.get(k), new.get(k)]
    return result


def _next_rev_no_site(db: Session, site_id: int) -> int:
    result = db.query(func.max(SiteRevision.revision_no)).filter(
        SiteRevision.site_id == site_id).scalar()
    return (result or 0) + 1


def _next_rev_no_cell3g(db: Session, cell_id_ref: int) -> int:
    result = db.query(func.max(Cell3GRevision.revision_no)).filter(
        Cell3GRevision.cell_id_ref == cell_id_ref).scalar()
    return (result or 0) + 1


def _next_rev_no_cell4g(db: Session, cell_id_ref: int) -> int:
    result = db.query(func.max(Cell4GRevision.revision_no)).filter(
        Cell4GRevision.cell_id_ref == cell_id_ref).scalar()
    return (result or 0) + 1


def _next_rev_no_cell5g(db: Session, cell_id_ref: int) -> int:
    result = db.query(func.max(Cell5GRevision.revision_no)).filter(
        Cell5GRevision.cell_id_ref == cell_id_ref).scalar()
    return (result or 0) + 1


# ── Snapshot helpers ──────────────────────────────────────────────────────────

def _site_snapshot(site: Site) -> Dict[str, Any]:
    return {
        "mien": site.mien, "tinh": site.tinh, "phuong_xa": site.phuong_xa,
        "site_name_cu": site.site_name_cu, "site_vip": site.site_vip,
        "lat": site.lat, "long": site.long,
        "tram_2g": _safe_bool(site.tram_2g),
        "tram_3g": _safe_bool(site.tram_3g),
        "tram_4g": _safe_bool(site.tram_4g),
        "tram_5g": _safe_bool(site.tram_5g),
        "repeater": _safe_bool(site.repeater),
        "booster": _safe_bool(site.booster),
        "node_truyen_dan_only": _safe_bool(site.node_truyen_dan_only),
        "tram_phu_song_tsca": _safe_bool(site.tram_phu_song_tsca),
        "phan_loai_tram": site.phan_loai_tram,
        "moran_3g": site.moran_3g, "moran_4g": site.moran_4g,
        "moran_5g": site.moran_5g,
        "ma_ptm": site.ma_ptm,
        "do_cao_dinh_cot_anten": site.do_cao_dinh_cot_anten,
        "do_cao_cot_anten": site.do_cao_cot_anten,
        "dia_chi": site.dia_chi, "ghi_chu": site.ghi_chu,
        "site_name": site.site_name,
    }


def _cell3g_snapshot(cell: Cell3G) -> Dict[str, Any]:
    return {
        "site_name": cell.site_name, "site_name_old": cell.site_name_old,
        "cell_name": cell.cell_name, "cell_name_old": cell.cell_name_old,
        "mien": cell.mien, "tinh": cell.tinh, "phuong_xa": cell.phuong_xa,
        "cell_vip": cell.cell_vip, "moran": cell.moran,
        "lat": cell.lat, "long": cell.long,
        "vung_phu_song": cell.vung_phu_song, "vendor": cell.vendor,
        "do_cao_anten": cell.do_cao_anten, "azimuth": cell.azimuth,
        "m_tilt": cell.m_tilt, "e_tilt": cell.e_tilt,
        "total_tilt": cell.total_tilt,
        "loai_anten": cell.loai_anten, "chung_anten": cell.chung_anten,
        "baseband": cell.baseband, "rf": cell.rf, "cell_id": cell.cell_id,
        "arfcn": cell.arfcn, "uarfcn": cell.uarfcn,
        "lac": cell.lac, "rac": cell.rac,
        "psc": cell.psc, "ura_id": cell.ura_id, "mimo": cell.mimo,
        "cell_max_power": cell.cell_max_power, "cpich_power": cell.cpich_power,
        "bbu_name": cell.bbu_name, "cell_status": cell.cell_status,
    }


def _cell4g_snapshot(cell: Cell4G) -> Dict[str, Any]:
    return {
        "site_name": cell.site_name, "site_name_old": cell.site_name_old,
        "cell_name": cell.cell_name, "cell_name_old": cell.cell_name_old,
        "mien": cell.mien, "tinh": cell.tinh, "phuong_xa": cell.phuong_xa,
        "cell_vip": cell.cell_vip, "moran": cell.moran,
        "lat": cell.lat, "long": cell.long,
        "vung_phu_song": cell.vung_phu_song, "vendor": cell.vendor,
        "do_cao_anten": cell.do_cao_anten, "azimuth": cell.azimuth,
        "m_tilt": cell.m_tilt, "e_tilt": cell.e_tilt,
        "total_tilt": cell.total_tilt,
        "loai_anten": cell.loai_anten, "chung_anten": cell.chung_anten,
        "baseband": cell.baseband, "rf": cell.rf,
        "enodeb_id": cell.enodeb_id, "cell_id": cell.cell_id,
        "earfcn": cell.earfcn, "tac": cell.tac,
        "pci": cell.pci, "root_sequence_id": cell.root_sequence_id,
        "mimo": cell.mimo, "bandwidth": cell.bandwidth,
        "cell_max_power": cell.cell_max_power, "eci": cell.eci,
        "bbu_name": cell.bbu_name, "cell_status": cell.cell_status,
    }


def _cell5g_snapshot(cell: Cell5G) -> Dict[str, Any]:
    return {
        "site_name":        cell.site_name,
        "site_name_old":    cell.site_name_old,
        "cell_name":        cell.cell_name,
        "cell_name_old":    cell.cell_name_old,
        "mien":             cell.mien,
        "tinh":             cell.tinh,
        "phuong_xa":        cell.phuong_xa,
        "cell_vip":         cell.cell_vip,
        "moran":            cell.moran,
        "lat":              cell.lat,
        "long":             cell.long,
        "vung_phu_song":    cell.vung_phu_song,
        "vendor":           cell.vendor,
        "do_cao_anten":     cell.do_cao_anten,
        "azimuth":          cell.azimuth,
        "m_tilt":           cell.m_tilt,
        "e_tilt":           cell.e_tilt,
        "total_tilt":       cell.total_tilt,
        "loai_anten":       cell.loai_anten,
        "baseband":         cell.baseband,
        "rf":               cell.rf,
        "gnodeb_id":        cell.gnodeb_id,
        "cell_id":          cell.cell_id,
        "tac":              cell.tac,
        "pci":              cell.pci,
        "root_sequence_id": cell.root_sequence_id,
        "mimo":             cell.mimo,
        "ssb_arfcn":        cell.ssb_arfcn,
        "center_arfcn":     cell.center_arfcn,
        "gscn":             cell.gscn,
        "bandwidth":        cell.bandwidth,
        "cell_max_power":   cell.cell_max_power,
        "nci":              cell.nci,
        "bbu_name":         cell.bbu_name,
        "mu_mimo":          cell.mu_mimo,
        "cell_status":      cell.cell_status,
    }


# ── Public record_* functions ─────────────────────────────────────────────────

def record_site_revision(
    db: Session, site: Site, old_snapshot: Optional[Dict],
    changed_by_id: Optional[int], changed_by_name: Optional[str],
    change_source: str = "form", change_note: Optional[str] = None,
    site_name_old_ref: Optional[str] = None,
) -> Optional[SiteRevision]:
    new_snap = _site_snapshot(site)
    if old_snapshot is None:
        diff: Dict = {}
    else:
        diff = _diff(old_snapshot, new_snap)
        if not diff:
            return None

    rev = SiteRevision(
        site_id=site.id, site_name=site.site_name,
        revision_no=_next_rev_no_site(db, site.id),
        changed_by=changed_by_id, changed_by_name=changed_by_name,
        change_source=change_source, change_note=change_note,
        site_name_old_ref=site_name_old_ref,
        mien=site.mien, tinh=site.tinh, phuong_xa=site.phuong_xa,
        site_name_cu=site.site_name_cu, site_vip=site.site_vip,
        lat=site.lat, long=site.long,
        tram_2g=_safe_bool(site.tram_2g), tram_3g=_safe_bool(site.tram_3g),
        tram_4g=_safe_bool(site.tram_4g), tram_5g=_safe_bool(site.tram_5g),
        repeater=_safe_bool(site.repeater), booster=_safe_bool(site.booster),
        node_truyen_dan_only=_safe_bool(site.node_truyen_dan_only),
        tram_phu_song_tsca=_safe_bool(site.tram_phu_song_tsca),
        phan_loai_tram=site.phan_loai_tram,
        moran_3g=site.moran_3g, moran_4g=site.moran_4g,
        moran_5g=site.moran_5g, ma_ptm=site.ma_ptm,
        do_cao_dinh_cot_anten=site.do_cao_dinh_cot_anten,
        do_cao_cot_anten=site.do_cao_cot_anten,
        dia_chi=site.dia_chi, ghi_chu=site.ghi_chu,
        changed_fields=json.dumps(diff, ensure_ascii=False, default=str),
    )
    db.add(rev)
    return rev


def record_cell3g_revision(
    db: Session, cell: Cell3G, old_snapshot: Optional[Dict],
    changed_by_id: Optional[int], changed_by_name: Optional[str],
    change_source: str = "form", change_note: Optional[str] = None,
) -> Optional[Cell3GRevision]:
    new_snap = _cell3g_snapshot(cell)
    if old_snapshot is None:
        diff: Dict = {}
    else:
        diff = _diff(old_snapshot, new_snap)
        if not diff:
            return None

    rev = Cell3GRevision(
        cell_id_ref=cell.id, site_id=cell.site_id,
        site_name=cell.site_name, cell_name=cell.cell_name,
        revision_no=_next_rev_no_cell3g(db, cell.id),
        changed_by=changed_by_id, changed_by_name=changed_by_name,
        change_source=change_source, change_note=change_note,
        mien=cell.mien, tinh=cell.tinh, phuong_xa=cell.phuong_xa,
        site_name_old=cell.site_name_old, cell_name_old=cell.cell_name_old,
        cell_vip=cell.cell_vip, moran=cell.moran,
        lat=cell.lat, long=cell.long,
        vung_phu_song=cell.vung_phu_song, vendor=cell.vendor,
        do_cao_anten=cell.do_cao_anten, azimuth=cell.azimuth,
        m_tilt=cell.m_tilt, e_tilt=cell.e_tilt, total_tilt=cell.total_tilt,
        loai_anten=cell.loai_anten, chung_anten=cell.chung_anten,
        baseband=cell.baseband, rf=cell.rf, cell_id=cell.cell_id,
        arfcn=cell.arfcn, uarfcn=cell.uarfcn,
        lac=cell.lac, rac=cell.rac,
        psc=cell.psc, ura_id=cell.ura_id, mimo=cell.mimo,
        cell_max_power=cell.cell_max_power, cpich_power=cell.cpich_power,
        bbu_name=cell.bbu_name, cell_status=cell.cell_status,
        changed_fields=json.dumps(diff, ensure_ascii=False, default=str),
    )
    db.add(rev)
    return rev


def record_cell4g_revision(
    db: Session, cell: Cell4G, old_snapshot: Optional[Dict],
    changed_by_id: Optional[int], changed_by_name: Optional[str],
    change_source: str = "form", change_note: Optional[str] = None,
) -> Optional[Cell4GRevision]:
    new_snap = _cell4g_snapshot(cell)
    if old_snapshot is None:
        diff: Dict = {}
    else:
        diff = _diff(old_snapshot, new_snap)
        if not diff:
            return None

    rev = Cell4GRevision(
        cell_id_ref=cell.id, site_id=cell.site_id,
        site_name=cell.site_name, cell_name=cell.cell_name,
        revision_no=_next_rev_no_cell4g(db, cell.id),
        changed_by=changed_by_id, changed_by_name=changed_by_name,
        change_source=change_source, change_note=change_note,
        mien=cell.mien, tinh=cell.tinh, phuong_xa=cell.phuong_xa,
        site_name_old=cell.site_name_old, cell_name_old=cell.cell_name_old,
        cell_vip=cell.cell_vip, moran=cell.moran,
        lat=cell.lat, long=cell.long,
        vung_phu_song=cell.vung_phu_song, vendor=cell.vendor,
        do_cao_anten=cell.do_cao_anten, azimuth=cell.azimuth,
        m_tilt=cell.m_tilt, e_tilt=cell.e_tilt, total_tilt=cell.total_tilt,
        loai_anten=cell.loai_anten, chung_anten=cell.chung_anten,
        baseband=cell.baseband, rf=cell.rf,
        enodeb_id=cell.enodeb_id, cell_id=cell.cell_id,
        earfcn=cell.earfcn, tac=cell.tac,
        pci=cell.pci, root_sequence_id=cell.root_sequence_id,
        mimo=cell.mimo, bandwidth=cell.bandwidth,
        cell_max_power=cell.cell_max_power, eci=cell.eci,
        bbu_name=cell.bbu_name, cell_status=cell.cell_status,
        changed_fields=json.dumps(diff, ensure_ascii=False, default=str),
    )
    db.add(rev)
    return rev


def record_cell5g_revision(
    db: Session, cell: Cell5G, old_snapshot: Optional[Dict],
    changed_by_id: Optional[int], changed_by_name: Optional[str],
    change_source: str = "form", change_note: Optional[str] = None,
) -> Optional[Cell5GRevision]:
    new_snap = _cell5g_snapshot(cell)
    if old_snapshot is None:
        diff: Dict = {}
    else:
        diff = _diff(old_snapshot, new_snap)
        if not diff:
            return None

    rev = Cell5GRevision(
        cell_id_ref=cell.id, site_id=cell.site_id,
        site_name=cell.site_name, cell_name=cell.cell_name,
        revision_no=_next_rev_no_cell5g(db, cell.id),
        changed_by=changed_by_id, changed_by_name=changed_by_name,
        change_source=change_source, change_note=change_note,
        mien=cell.mien, tinh=cell.tinh, phuong_xa=cell.phuong_xa,
        site_name_old=cell.site_name_old, cell_name_old=cell.cell_name_old,
        cell_vip=cell.cell_vip, moran=cell.moran,
        lat=cell.lat, long=cell.long,
        vung_phu_song=cell.vung_phu_song, vendor=cell.vendor,
        do_cao_anten=cell.do_cao_anten, azimuth=cell.azimuth,
        m_tilt=cell.m_tilt, e_tilt=cell.e_tilt, total_tilt=cell.total_tilt,
        loai_anten=cell.loai_anten,
        baseband=cell.baseband, rf=cell.rf,
        gnodeb_id=cell.gnodeb_id, cell_id=cell.cell_id,
        tac=cell.tac, pci=cell.pci,
        root_sequence_id=cell.root_sequence_id, mimo=cell.mimo,
        ssb_arfcn=cell.ssb_arfcn, center_arfcn=cell.center_arfcn,
        gscn=cell.gscn, bandwidth=cell.bandwidth,
        cell_max_power=cell.cell_max_power, nci=cell.nci,
        bbu_name=cell.bbu_name, mu_mimo=cell.mu_mimo,
        cell_status=cell.cell_status,
        changed_fields=json.dumps(diff, ensure_ascii=False, default=str),
    )
    db.add(rev)
    return rev
