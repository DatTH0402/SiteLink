"""
services/site_info.py

Site <-> Cell relationship helpers.

* Cells denormalise a few columns from their parent Site (SITE_INHERITED_FIELDS).
  - apply_site_info / apply_site_to_cell : copy Site -> cell data on create / import
  - changed_site_fields / sync_site_info_to_cells : push a Site edit down to all its cells
* Sites carry tram_3g / tram_4g / tram_5g flags that the report module counts.
  - get_or_create_site_for_cell : Excel cell import (auto-creates the Site with the flag set)
  - ensure_site_tech_flag       : turn the flag on when a cell of that technology exists

None of the functions here commit, except get_or_create_site_for_cell
(it commits only when it has to create a new Site, as the old _ensure_site did).
"""
from typing import Any, Dict, Optional, Set, Tuple

from sqlalchemy.orm import Session

from app.models.site import Site
from app.models.cell_3g import Cell3G
from app.models.cell_4g import Cell4G
from app.models.cell_5g import Cell5G
from app.services.revision import (
    _safe_bool, _site_snapshot, record_site_revision,
    _cell3g_snapshot, _cell4g_snapshot, _cell5g_snapshot,
    record_cell3g_revision, record_cell4g_revision, record_cell5g_revision,
)

SITE_INHERITED_FIELDS = ("site_name", "mien", "tinh", "phuong_xa")

TECH_FLAG = {"3g": "tram_3g", "4g": "tram_4g", "5g": "tram_5g"}

_CELL_TECH = {
    "3g": (Cell3G, _cell3g_snapshot, record_cell3g_revision),
    "4g": (Cell4G, _cell4g_snapshot, record_cell4g_revision),
    "5g": (Cell5G, _cell5g_snapshot, record_cell5g_revision),
}


def _blank(v: Any) -> bool:
    return v is None or str(v).strip() == ""


def _norm(v: Any) -> Optional[str]:
    return None if _blank(v) else str(v).strip()


# ── Site -> cell data copy (create / import) ─────────────────────────────────

def apply_site_info(data: Dict[str, Any], site: Site) -> Dict[str, Any]:
    out = dict(data)
    out["site_id"] = site.id
    for field in SITE_INHERITED_FIELDS:
        value = getattr(site, field, None)
        if value is not None and str(value).strip() != "":
            out[field] = value
    return out


def apply_site_to_cell(cell: Any, site: Site) -> None:
    """Copy the Site's non-empty inherited fields onto an existing cell object."""
    for field in SITE_INHERITED_FIELDS:
        value = getattr(site, field, None)
        if not _blank(value) and getattr(cell, field, None) != value:
            setattr(cell, field, value)


# ── Issue 1: Site edit -> all cells of the Site ──────────────────────────────

def changed_site_fields(old_snapshot: Dict[str, Any], site: Site) -> Set[str]:
    """Which inherited fields differ between the pre-edit snapshot and the Site now."""
    return {
        f for f in SITE_INHERITED_FIELDS
        if _norm(old_snapshot.get(f)) != _norm(getattr(site, f, None))
    }


def sync_site_info_to_cells(
    db: Session, site: Site, changed_fields: Optional[Set[str]] = None, *,
    changed_by_id: Optional[int] = None, changed_by_name: Optional[str] = None,
    change_source: str = "form", change_note: str = "Đồng bộ thông tin từ Site",
) -> int:
    """
    Push the Site's site_name / mien / tinh / phuong_xa to every 3G/4G/5G cell of
    the Site and record a cell revision per modified cell. Does NOT commit.

    A blank Site value only clears the cell's value when that field is in
    `changed_fields` (i.e. the user just cleared it on the Site).
    """
    changed = set(changed_fields or ())
    updates: Dict[str, Any] = {}
    for f in SITE_INHERITED_FIELDS:
        v = getattr(site, f, None)
        if _blank(v) and (f == "site_name" or f not in changed):
            continue
        updates[f] = None if _blank(v) else v
    if not updates:
        return 0

    touched = 0
    for _tech, (Model, snap_fn, rec_fn) in _CELL_TECH.items():
        for cell in db.query(Model).filter(Model.site_id == site.id).all():
            diff = {f: v for f, v in updates.items()
                    if _norm(getattr(cell, f, None)) != _norm(v)}
            if not diff:
                continue
            old_snap = snap_fn(cell)
            for f, v in diff.items():
                setattr(cell, f, v)
            db.flush()
            rec_fn(
                db, cell, old_snapshot=old_snap,
                changed_by_id=changed_by_id, changed_by_name=changed_by_name,
                change_source=change_source, change_note=change_note,
            )
            touched += 1
    return touched


# ── Issue 2: tram_3g / tram_4g / tram_5g mapping ─────────────────────────────

def ensure_site_tech_flag(
    db: Session, site: Site, tech: str, *,
    changed_by_id: Optional[int] = None, changed_by_name: Optional[str] = None,
    change_source: str = "form", change_note: Optional[str] = None,
) -> bool:
    """Turn site.tram_<tech> on if it is off (+ Site revision). No commit. True if changed."""
    flag = TECH_FLAG[tech]
    if _safe_bool(getattr(site, flag, None)):
        return False
    old_snap = _site_snapshot(site)
    setattr(site, flag, True)
    db.flush()
    record_site_revision(
        db, site, old_snapshot=old_snap,
        changed_by_id=changed_by_id, changed_by_name=changed_by_name,
        change_source=change_source, change_note=change_note,
    )
    return True


def get_or_create_site_for_cell(
    db: Session, rec: Dict[str, Any], tech: str, current_user: Any,
) -> Tuple[Site, bool]:
    """
    Find the Site by site_name; create it when missing (with tram_<tech> = True and
    a Site revision). Returns (site, created). Commits only when it creates a Site.
    """
    site_name = (rec.get("site_name") or "").strip()
    site = db.query(Site).filter(Site.site_name == site_name).first()
    if site is not None:
        return site, False

    new_site = Site(
        site_name=site_name,
        mien=rec.get("mien") or "",
        tinh=rec.get("tinh") or "",
        phuong_xa=rec.get("phuong_xa"),
        lat=rec.get("lat"),
        long=rec.get("long"),
        created_by=current_user.id,
        **{TECH_FLAG[tech]: True},
    )
    db.add(new_site)
    db.flush()
    record_site_revision(
        db, new_site, old_snapshot=None,
        changed_by_id=current_user.id,
        changed_by_name=current_user.full_name or current_user.username,
        change_source="excel",
        change_note=f"Tự động tạo khi import Cell {tech.upper()}",
    )
    db.commit()
    db.refresh(new_site)
    return new_site, True
