"""
revision.py
===========
Service layer for creating revision history snapshots.

Design:
- Each time a site or cell is CREATED or UPDATED, a revision snapshot is saved.
- revision_no is auto-incremented per site_id / cell_id_ref.
- changed_fields stores a JSON diff of what changed.
- Name changes are tracked via site_name_old_ref / cell_name_old fields.

Excel import name-change logic:
  When a row has cell_name_old == <existing cell_name> and cell_name == <new value>,
  the import_excel service resolves this as a name-change update (not a new record).
  The revision captures both old and new names in changed_fields.
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


# ── helpers ───────────────────────────────────────────────────────────────────

def _diff(old: Dict, new: Dict) -> Dict:
    """Return {field: [old_val, new_val]} for fields that changed."""
    result = {}
    all_keys = set(old) | set(new)
    for k in all_keys:
        ov = old.get(k)
        nv = new.get(k)
        if ov != nv:
            result[k] = [ov, nv]
    return result


def _next_revision_no(db: Session, Model, id_col, id_val: int) -> int:
    """Get next revision number for a given record."""
    current = db.query(func.max(id_col)).filter(id_col == id_val).scalar()
    # We need to query max revision_no, not max id
    return 1  # placeholder - see actual impl below


def _next_rev_no_site(db: Session, site_id: int) -> int:
    result = db.query(func.max(SiteRevision.revision_no)).filter(
        SiteRevision.site_id == site_id
    ).scalar()
    return (result or 0) + 1


def _next_rev_no_cell3g(db: Session, cell_id_ref: int) -> int:
    result = db.query(func.max(Cell3GRevision.revision_no)).filter(
        Cell3GRevision.cell_id_ref == cell_id_ref
    ).scalar()
    return (result or 0) + 1


def _next_rev_no_cell4g(db: Session, cell_id_ref: int) -> int:
    result = db.query(func.max(Cell4GRevision.revision_no)).filter(
        Cell4GRevision.cell_id_ref == cell_id_ref
    ).scalar()
    return (result or 0) + 1


def _next_rev_no_cell5g(db: Session, cell_id_ref: int) -> int:
    result = db.query(func.max(Cell5GRevision.revision_no)).filter(
        Cell5GRevision.cell_id_ref == cell_id_ref
    ).scalar()
    return (result or 0) + 1


def _site_snapshot(site: Site) -> Dict[str, Any]:
    return {
        "mien":                  site.mien,
        "tinh":                  site.tinh,
        "phuong_xa":             site.phuong_xa,
        "site_name_cu":          site.site_name_cu,
        "site_vip":              site.site_vip,
        "lat":                   site.lat,
        "long":                  site.long,
        "tram_2g":               site.tram_2g,
        "tram_3g":               site.tram_3g,
        "tram_4g":               site.tram_4g,
        "tram_5g":               site.tram_5g,
        "repeater":              site.repeater,
        "booster":               site.booster,
        "node_truyen_dan_only":  site.node_truyen_dan_only,
        "tram_phu_song_tsca":    site.tram_phu_song_tsca,
        "phan_loai_tram":        site.phan_loai_tram,
        "moran_3g":              site.moran_3g,
        "moran_4g":              site.moran_4g,
        "moran_5g":              site.moran_5g,
        "ma_ptm":                site.ma_ptm,
        "do_cao_dinh_cot_anten": site.do_cao_dinh_cot_anten,
        "do_cao_cot_anten":      site.do_cao_cot_anten,
        "dia_chi":               site.dia_chi,
        "ghi_chu":               site.ghi_chu,
        "site_name":             site.site_name,
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
        "m_tilt": cell.m_tilt, "e_tilt": cell.e_tilt, "total_tilt": cell.total_tilt,
        "loai_anten": cell.loai_anten, "chung_anten": cell.chung_anten,
        "baseband": cell.baseband, "rf": cell.rf, "cell_id": cell.cell_id,
        "arfcn": cell.arfcn, "psc": cell.psc, "mimo": cell.mimo,
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
        "m_tilt": cell.m_tilt, "e_tilt": cell.e_tilt, "total_tilt": cell.total_tilt,
        "loai_anten": cell.loai_anten, "chung_anten": cell.chung_anten,
        "baseband": cell.baseband, "rf": cell.rf, "cell_id": cell.cell_id,
        "earfcn": cell.earfcn, "pci": cell.pci,
        "root_sequence_id": cell.root_sequence_id, "mimo": cell.mimo,
    }


def _cell5g_snapshot(cell: Cell5G) -> Dict[str, Any]:
    return {
        "site_name": cell.site_name, "site_name_old": cell.site_name_old,
        "cell_name": cell.cell_name, "cell_name_old": cell.cell_name_old,
        "mien": cell.mien, "tinh": cell.tinh, "phuong_xa": cell.phuong_xa,
        "cell_vip": cell.cell_vip, "moran": cell.moran,
        "lat": cell.lat, "long": cell.long,
        "vung_phu_song": cell.vung_phu_song, "vendor": cell.vendor,
        "do_cao_anten": cell.do_cao_anten, "azimuth": cell.azimuth,
        "m_tilt": cell.m_tilt, "e_tilt": cell.e_tilt, "total_tilt": cell.total_tilt,
        "loai_anten": cell.loai_anten,
        "baseband": cell.baseband, "rf": cell.rf, "cell_id": cell.cell_id,
        "nr_arfcn": cell.nr_arfcn, "pci": cell.pci,
        "root_sequence_id": cell.root_sequence_id, "mimo": cell.mimo,
    }


# ── Public API ────────────────────────────────────────────────────────────────

def record_site_revision(
    db: Session,
    site: Site,
    old_snapshot: Optional[Dict],
    changed_by_id: Optional[int],
    changed_by_name: Optional[str],
    change_source: str = "form",
    change_note: Optional[str] = None,
    site_name_old_ref: Optional[str] = None,   # previous name when renamed
) -> SiteRevision:
    """
    Save a revision snapshot for a site.
    old_snapshot: None for CREATE, dict for UPDATE.
    """
    new_snap = _site_snapshot(site)
    diff = _diff(old_snapshot, new_snap) if old_snapshot else {}

    rev = SiteRevision(
        site_id         = site.id,
        site_name       = site.site_name,
        revision_no     = _next_rev_no_site(db, site.id),
        changed_by      = changed_by_id,
        changed_by_name = changed_by_name,
        change_source   = change_source,
        change_note     = change_note,
        site_name_old_ref = site_name_old_ref,

        mien                    = site.mien,
        tinh                    = site.tinh,
        phuong_xa               = site.phuong_xa,
        site_name_cu            = site.site_name_cu,
        site_vip                = site.site_vip,
        lat                     = site.lat,
        long                    = site.long,
        tram_2g                 = site.tram_2g,
        tram_3g                 = site.tram_3g,
        tram_4g                 = site.tram_4g,
        tram_5g                 = site.tram_5g,
        repeater                = site.repeater,
        booster                 = site.booster,
        node_truyen_dan_only    = site.node_truyen_dan_only,
        tram_phu_song_tsca      = site.tram_phu_song_tsca,
        phan_loai_tram          = site.phan_loai_tram,
        moran_3g                = site.moran_3g,
        moran_4g                = site.moran_4g,
        moran_5g                = site.moran_5g,
        ma_ptm                  = site.ma_ptm,
        do_cao_dinh_cot_anten   = site.do_cao_dinh_cot_anten,
        do_cao_cot_anten        = site.do_cao_cot_anten,
        dia_chi                 = site.dia_chi,
        ghi_chu                 = site.ghi_chu,
        changed_fields          = json.dumps(diff, ensure_ascii=False, default=str),
    )
    db.add(rev)
    # Don't commit here – caller commits
    return rev


def record_cell3g_revision(
    db: Session,
    cell: Cell3G,
    old_snapshot: Optional[Dict],
    changed_by_id: Optional[int],
    changed_by_name: Optional[str],
    change_source: str = "form",
    change_note: Optional[str] = None,
) -> Cell3GRevision:
    new_snap = _cell3g_snapshot(cell)
    diff = _diff(old_snapshot, new_snap) if old_snapshot else {}

    rev = Cell3GRevision(
        cell_id_ref     = cell.id,
        site_id         = cell.site_id,
        site_name       = cell.site_name,
        cell_name       = cell.cell_name,
        revision_no     = _next_rev_no_cell3g(db, cell.id),
        changed_by      = changed_by_id,
        changed_by_name = changed_by_name,
        change_source   = change_source,
        change_note     = change_note,

        mien          = cell.mien,
        tinh          = cell.tinh,
        phuong_xa     = cell.phuong_xa,
        site_name_old = cell.site_name_old,
        cell_name_old = cell.cell_name_old,
        cell_vip      = cell.cell_vip,
        moran         = cell.moran,
        lat           = cell.lat,
        long          = cell.long,
        vung_phu_song = cell.vung_phu_song,
        vendor        = cell.vendor,
        do_cao_anten  = cell.do_cao_anten,
        azimuth       = cell.azimuth,
        m_tilt        = cell.m_tilt,
        e_tilt        = cell.e_tilt,
        total_tilt    = cell.total_tilt,
        loai_anten    = cell.loai_anten,
        chung_anten   = cell.chung_anten,
        baseband      = cell.baseband,
        rf            = cell.rf,
        cell_id       = cell.cell_id,
        arfcn         = cell.arfcn,
        psc           = cell.psc,
        mimo          = cell.mimo,
        changed_fields = json.dumps(diff, ensure_ascii=False, default=str),
    )
    db.add(rev)
    return rev


def record_cell4g_revision(
    db: Session,
    cell: Cell4G,
    old_snapshot: Optional[Dict],
    changed_by_id: Optional[int],
    changed_by_name: Optional[str],
    change_source: str = "form",
    change_note: Optional[str] = None,
) -> Cell4GRevision:
    new_snap = _cell4g_snapshot(cell)
    diff = _diff(old_snapshot, new_snap) if old_snapshot else {}

    rev = Cell4GRevision(
        cell_id_ref     = cell.id,
        site_id         = cell.site_id,
        site_name       = cell.site_name,
        cell_name       = cell.cell_name,
        revision_no     = _next_rev_no_cell4g(db, cell.id),
        changed_by      = changed_by_id,
        changed_by_name = changed_by_name,
        change_source   = change_source,
        change_note     = change_note,

        mien             = cell.mien,
        tinh             = cell.tinh,
        phuong_xa        = cell.phuong_xa,
        site_name_old    = cell.site_name_old,
        cell_name_old    = cell.cell_name_old,
        cell_vip         = cell.cell_vip,
        moran            = cell.moran,
        lat              = cell.lat,
        long             = cell.long,
        vung_phu_song    = cell.vung_phu_song,
        vendor           = cell.vendor,
        do_cao_anten     = cell.do_cao_anten,
        azimuth          = cell.azimuth,
        m_tilt           = cell.m_tilt,
        e_tilt           = cell.e_tilt,
        total_tilt       = cell.total_tilt,
        loai_anten       = cell.loai_anten,
        chung_anten      = cell.chung_anten,
        baseband         = cell.baseband,
        rf               = cell.rf,
        cell_id          = cell.cell_id,
        earfcn           = cell.earfcn,
        pci              = cell.pci,
        root_sequence_id = cell.root_sequence_id,
        mimo             = cell.mimo,
        changed_fields   = json.dumps(diff, ensure_ascii=False, default=str),
    )
    db.add(rev)
    return rev


def record_cell5g_revision(
    db: Session,
    cell: Cell5G,
    old_snapshot: Optional[Dict],
    changed_by_id: Optional[int],
    changed_by_name: Optional[str],
    change_source: str = "form",
    change_note: Optional[str] = None,
) -> Cell5GRevision:
    new_snap = _cell5g_snapshot(cell)
    diff = _diff(old_snapshot, new_snap) if old_snapshot else {}

    rev = Cell5GRevision(
        cell_id_ref     = cell.id,
        site_id         = cell.site_id,
        site_name       = cell.site_name,
        cell_name       = cell.cell_name,
        revision_no     = _next_rev_no_cell5g(db, cell.id),
        changed_by      = changed_by_id,
        changed_by_name = changed_by_name,
        change_source   = change_source,
        change_note     = change_note,

        mien             = cell.mien,
        tinh             = cell.tinh,
        phuong_xa        = cell.phuong_xa,
        site_name_old    = cell.site_name_old,
        cell_name_old    = cell.cell_name_old,
        cell_vip         = cell.cell_vip,
        moran            = cell.moran,
        lat              = cell.lat,
        long             = cell.long,
        vung_phu_song    = cell.vung_phu_song,
        vendor           = cell.vendor,
        do_cao_anten     = cell.do_cao_anten,
        azimuth          = cell.azimuth,
        m_tilt           = cell.m_tilt,
        e_tilt           = cell.e_tilt,
        total_tilt       = cell.total_tilt,
        loai_anten       = cell.loai_anten,
        baseband         = cell.baseband,
        rf               = cell.rf,
        cell_id          = cell.cell_id,
        nr_arfcn         = cell.nr_arfcn,
        pci              = cell.pci,
        root_sequence_id = cell.root_sequence_id,
        mimo             = cell.mimo,
        changed_fields   = json.dumps(diff, ensure_ascii=False, default=str),
    )
    db.add(rev)
    return rev
