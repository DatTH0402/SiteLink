#!/usr/bin/env bash
# =============================================================================
# SiteLink – Full feature update script
# Run from the SiteLink project root:  bash update.sh
# =============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "================================================================"
echo " SiteLink – applying all feature updates"
echo "================================================================"

# ─────────────────────────────────────────────────────────────────────────────
# 1. BACKEND FILES
# ─────────────────────────────────────────────────────────────────────────────

# ── 1-A  New Antenna model ───────────────────────────────────────────────────
cat > backend/app/models/antenna.py << 'PYEOF'
from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Float, DateTime, Text
from app.db.base import Base


class Antenna(Base):
    __tablename__ = "antennas"

    id             = Column(Integer, primary_key=True, index=True)
    name           = Column(String(300), nullable=False, unique=True, index=True)
    no_of_ports    = Column(Integer,     nullable=True)
    band           = Column(String(100), nullable=True)
    no_of_beam     = Column(Integer,     nullable=True)
    horizontal_bw  = Column(String(50),  nullable=True)
    vertical_bw    = Column(String(50),  nullable=True)
    gain           = Column(String(50),  nullable=True)
    etilt          = Column(String(50),  nullable=True)
    h              = Column(String(50),  nullable=True)   # height mm
    w              = Column(String(50),  nullable=True)   # width  mm
    d              = Column(String(50),  nullable=True)   # depth  mm
    weight         = Column(String(50),  nullable=True)
    connector_type = Column(String(100), nullable=True)
    ghi_chu        = Column(Text,        nullable=True)
    created_at     = Column(DateTime(timezone=True),
                            default=lambda: datetime.now(timezone.utc))
    updated_at     = Column(DateTime(timezone=True),
                            default=lambda: datetime.now(timezone.utc),
                            onupdate=lambda: datetime.now(timezone.utc))
PYEOF

# ── 1-B  Antenna schema ──────────────────────────────────────────────────────
cat > backend/app/schemas/antenna.py << 'PYEOF'
from typing import Optional
from pydantic import BaseModel


class AntennaBase(BaseModel):
    name:           str
    no_of_ports:    Optional[int]   = None
    band:           Optional[str]   = None
    no_of_beam:     Optional[int]   = None
    horizontal_bw:  Optional[str]   = None
    vertical_bw:    Optional[str]   = None
    gain:           Optional[str]   = None
    etilt:          Optional[str]   = None
    h:              Optional[str]   = None
    w:              Optional[str]   = None
    d:              Optional[str]   = None
    weight:         Optional[str]   = None
    connector_type: Optional[str]   = None
    ghi_chu:        Optional[str]   = None


class AntennaCreate(AntennaBase):
    pass


class AntennaUpdate(BaseModel):
    name:           Optional[str]   = None
    no_of_ports:    Optional[int]   = None
    band:           Optional[str]   = None
    no_of_beam:     Optional[int]   = None
    horizontal_bw:  Optional[str]   = None
    vertical_bw:    Optional[str]   = None
    gain:           Optional[str]   = None
    etilt:          Optional[str]   = None
    h:              Optional[str]   = None
    w:              Optional[str]   = None
    d:              Optional[str]   = None
    weight:         Optional[str]   = None
    connector_type: Optional[str]   = None
    ghi_chu:        Optional[str]   = None


class AntennaRead(AntennaBase):
    id: int

    class Config:
        from_attributes = True
PYEOF

# ── 1-C  Antenna route ───────────────────────────────────────────────────────
mkdir -p backend/app/api/routes
cat > backend/app/api/routes/antenna.py << 'PYEOF'
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from sqlalchemy.orm import Session
import io, pandas as pd

from app.db.session import get_db
from app.models.antenna import Antenna
from app.schemas.antenna import AntennaCreate, AntennaUpdate, AntennaRead
from app.utils.deps import get_current_user, require_admin
from app.utils.audit import log_action
from app.models.user import User

router = APIRouter()


def _or_404(db: Session, antenna_id: int) -> Antenna:
    obj = db.query(Antenna).filter(Antenna.id == antenna_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail="Antenna not found")
    return obj


@router.get("/", response_model=List[AntennaRead])
def list_antennas(
    skip: int = 0,
    limit: int = 1000,
    search: Optional[str] = Query(None),
    band:   Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    q = db.query(Antenna)
    if search:
        q = q.filter(Antenna.name.ilike(f"%{search}%"))
    if band:
        q = q.filter(Antenna.band.ilike(f"%{band}%"))
    return q.order_by(Antenna.name).offset(skip).limit(limit).all()


@router.get("/count")
def count_antennas(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return {"count": db.query(Antenna).count()}


@router.post("/import-excel")
async def import_antenna_excel(
    file: UploadFile = File(...),
    dry_run: bool = Query(False),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Import antennas from Excel.
    Expected columns (flexible naming):
    Name | No_of_ports | Band | No_of_beam | Horizontal BW | Vertical BW |
    Gain | Etilt | H | W | D | Weight | Connector type | Ghi chú
    """
    content = await file.read()
    try:
        df = pd.read_excel(io.BytesIO(content), dtype=str)
        df = df.where(pd.notna(df), None)
        df.columns = [str(c).strip() for c in df.columns]
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Cannot read Excel: {e}")

    def _v(row, *keys):
        for k in keys:
            val = row.get(k)
            if val is not None and str(val).strip() not in ("", "nan", "None"):
                return str(val).strip()
        return None

    def _i(row, *keys):
        v = _v(row, *keys)
        if v is None:
            return None
        try:
            return int(float(v))
        except Exception:
            return None

    to_create, to_update, errors = [], [], []

    for i, row in df.iterrows():
        row_num = int(str(i)) + 2  # type: ignore[arg-type]
        name = _v(row, "Name", "name", "NAME",
                  "Ten anten", "Ten Anten", "Antenna Name")
        if not name:
            errors.append(f"Row {row_num}: 'Name' is empty")
            continue

        rec = {
            "name":           name,
            "no_of_ports":    _i(row, "No_of_ports", "No of ports", "Ports", "no_of_ports"),
            "band":           _v(row, "Band", "band", "BAND"),
            "no_of_beam":     _i(row, "No_of_beam", "No of beam", "no_of_beam"),
            "horizontal_bw":  _v(row, "Horizontal BW", "Horizontal_BW", "HBW", "horizontal_bw"),
            "vertical_bw":    _v(row, "Vertical BW",   "Vertical_BW",   "VBW", "vertical_bw"),
            "gain":           _v(row, "Gain", "gain"),
            "etilt":          _v(row, "Etilt", "ETilt", "E-tilt", "etilt"),
            "h":              _v(row, "H", "h", "Height"),
            "w":              _v(row, "W", "w", "Width"),
            "d":              _v(row, "D", "d", "Depth"),
            "weight":         _v(row, "Weight", "weight"),
            "connector_type": _v(row, "Connector type", "Connector Type",
                                  "connector_type", "Connector"),
            "ghi_chu":        _v(row, "Ghi chú", "Ghi chu", "ghi_chu", "Note"),
        }

        existing = db.query(Antenna).filter(Antenna.name == name).first()
        if existing:
            to_update.append((existing, rec, row_num))
        else:
            to_create.append((rec, row_num))

    summary = {
        "to_create": len(to_create),
        "to_update": len(to_update),
        "errors":    errors,
        "dry_run":   dry_run,
    }

    if dry_run:
        preview_create = [r["name"] for r, _ in to_create[:5]]
        preview_update = [obj.name for obj, _, _ in to_update[:5]]
        summary["preview_create"] = preview_create
        summary["preview_update"] = preview_update
        return summary

    # ── Commit ──────────────────────────────────────────────────────────────
    created, updated = 0, 0
    for rec, row_num in to_create:
        try:
            db.add(Antenna(**rec))
            db.commit()
            created += 1
        except Exception as e:
            db.rollback()
            errors.append(f"Row {row_num}: {e}")

    for existing, rec, row_num in to_update:
        try:
            for k, v in rec.items():
                if v is not None and k != "name":
                    setattr(existing, k, v)
            db.commit()
            updated += 1
        except Exception as e:
            db.rollback()
            errors.append(f"Row {row_num}: {e}")

    log_action(db, current_user, "IMPORT", "antennas", 0,
               new_value={"created": created, "updated": updated})
    return {"created": created, "updated": updated, "errors": errors, "dry_run": False}


@router.get("/{antenna_id}", response_model=AntennaRead)
def get_antenna(
    antenna_id: int,
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    return _or_404(db, antenna_id)


@router.post("/", response_model=AntennaRead, status_code=201)
def create_antenna(
    payload: AntennaCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    existing = db.query(Antenna).filter(Antenna.name == payload.name).first()
    if existing:
        raise HTTPException(status_code=400,
                            detail=f"Antenna '{payload.name}' already exists")
    obj = Antenna(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    log_action(db, current_user, "CREATE", "antennas", obj.id,
               new_value=payload.model_dump())
    return obj


@router.put("/{antenna_id}", response_model=AntennaRead)
def update_antenna(
    antenna_id: int,
    payload: AntennaUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    obj = _or_404(db, antenna_id)
    old = {c.name: getattr(obj, c.name) for c in obj.__table__.columns}
    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(obj, k, v)
    db.commit()
    db.refresh(obj)
    log_action(db, current_user, "UPDATE", "antennas", obj.id,
               old_value=old, new_value=payload.model_dump(exclude_unset=True))
    return obj


@router.delete("/{antenna_id}")
def delete_antenna(
    antenna_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    obj = _or_404(db, antenna_id)
    db.delete(obj)
    db.commit()
    log_action(db, current_user, "DELETE", "antennas", antenna_id)
    return {"message": "Deleted"}
PYEOF

# ── 1-D  Updated db/base.py – register Antenna model ────────────────────────
cat > backend/app/db/base.py << 'PYEOF'
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass


# Import all models so SQLAlchemy registers them
from app.models import (  # noqa
    user, site, cell_3g, cell_4g, cell_5g,
    dropdown, audit_log, antenna,
)
PYEOF

# ── 1-E  Fuzzy-mapping + dry-run import_excel.py ────────────────────────────
cat > backend/app/services/import_excel.py << 'PYEOF'
"""
import_excel.py
==============
Handles Excel → DB record conversion for Sites, Cell3G, Cell4G, Cell5G.

New capabilities
----------------
* Fuzzy province/ward mapping  – strips accents & common prefixes so
  "Ha Noi", "hà nội", "Tp.Hà Nội" all resolve to "Thành phố Hà Nội".
* Dry-run mode                 – returns a preview dict without touching DB.
* Auto-create missing sites    – when importing cells, if the site referenced
  by site_name does not exist, create it from columns in the cell file.
* Anchor-based upsert          – site_name is the anchor for sites;
  (site_name, cell_name) is the anchor for cells.
"""

from __future__ import annotations

import io
import re
import unicodedata
from typing import Any, Dict, List, Optional, Tuple

import pandas as pd


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _strip_accents(text: str) -> str:
    """Remove diacritics (accents) from a Unicode string."""
    nfkd = unicodedata.normalize("NFKD", text)
    return "".join(c for c in nfkd if not unicodedata.combining(c))


# Prefixes to remove before fuzzy-matching province / ward names
_PREFIX_RE = re.compile(
    r"^(tp\.?|tinh|tỉnh|thanh\s*pho|thành\s*phố|"
    r"quan|quận|huyen|huyện|thi\s*xa|thị\s*xã|"
    r"xa|xã|phuong|phường|thi\s*tran|thị\s*trấn)\s*",
    re.IGNORECASE,
)


def _normalize(text: str) -> str:
    """Canonical key used for fuzzy lookup."""
    t = _strip_accents(text).lower().strip()
    t = _PREFIX_RE.sub("", t)
    t = re.sub(r"[\s\-_\.]+", "", t)   # collapse whitespace / punctuation
    return t


# ─────────────────────────────────────────────────────────────────────────────
# Fuzzy-mapping cache
# ─────────────────────────────────────────────────────────────────────────────

class GeoCache:
    """
    Loaded once per import call.
    Provides O(1) lookup:
        tinh_map  : normalised_key  → official ten_tinh
        xa_map    : (normalised_tinh, normalised_xa_key) → official ten_phuong_xa
        tinh_mien : official ten_tinh → mien code (MB / MT / MN)
    """

    def __init__(self, db) -> None:  # db: SQLAlchemy Session
        from app.models.dropdown import DropdownTinhXaPhuong
        rows = db.query(DropdownTinhXaPhuong).all()

        self.tinh_map:  Dict[str, str] = {}
        self.xa_map:    Dict[Tuple[str, str], str] = {}
        self.tinh_mien: Dict[str, str] = {}

        for r in rows:
            if r.ten_tinh:
                k_tinh = _normalize(r.ten_tinh)
                self.tinh_map[k_tinh]   = r.ten_tinh
                self.tinh_mien[r.ten_tinh] = r.mien or ""
            if r.ten_tinh and r.ten_phuong_xa:
                k_tinh = _normalize(r.ten_tinh)
                k_xa   = _normalize(r.ten_phuong_xa)
                self.xa_map[(k_tinh, k_xa)] = r.ten_phuong_xa

    def resolve_tinh(self, raw: Optional[str]) -> Optional[str]:
        if not raw:
            return None
        return self.tinh_map.get(_normalize(raw))

    def resolve_xa(self, tinh_official: str,
                   raw_xa: Optional[str]) -> Optional[str]:
        if not raw_xa or not tinh_official:
            return None
        k_tinh = _normalize(tinh_official)
        k_xa   = _normalize(raw_xa)
        return self.xa_map.get((k_tinh, k_xa))

    def mien_for(self, tinh_official: str) -> str:
        return self.tinh_mien.get(tinh_official, "")


# ─────────────────────────────────────────────────────────────────────────────
# Low-level column readers
# ─────────────────────────────────────────────────────────────────────────────

def _read_excel(file_bytes: bytes) -> pd.DataFrame:
    df = pd.read_excel(io.BytesIO(file_bytes), dtype=str)
    df = df.where(pd.notna(df), None)
    df.columns = [str(c).strip() for c in df.columns]
    return df


def _v(row, *keys) -> Optional[str]:
    for key in keys:
        val = row.get(key)
        if val is not None and str(val).strip() not in ("", "nan", "None"):
            return str(val).strip()
    return None


def _bool(row, *keys) -> bool:
    v = _v(row, *keys)
    if v is None:
        return False
    return str(v).strip().lower() in ("x", "true", "yes", "1", "co", "có")


def _float(row, *keys) -> Optional[float]:
    v = _v(row, *keys)
    if v is None:
        return None
    try:
        return float(v)
    except (ValueError, TypeError):
        return None


# ─────────────────────────────────────────────────────────────────────────────
# Site import  (with dry-run + fuzzy mapping)
# ─────────────────────────────────────────────────────────────────────────────

def parse_site_excel(
    file_bytes: bytes,
    db=None,
    dry_run: bool = False,
) -> Dict[str, Any]:
    """
    Returns:
    {
        "to_create": [ { site_name, mien, tinh, ... }, ... ],
        "to_update": [ { "existing_id": int, "anchor": str, "changes": {...} }, ... ],
        "errors":    [ "Row N: ..." ],
        "dry_run":   bool,
    }
    When dry_run=True the caller should NOT write anything to the DB.
    """
    df  = _read_excel(file_bytes)
    geo = GeoCache(db) if db else None

    to_create: List[Dict] = []
    to_update: List[Dict] = []
    errors:    List[str]  = []

    from app.models.site import Site  # lazy import to avoid circular

    for i, row in df.iterrows():
        row_num = int(str(i)) + 2  # type: ignore[arg-type]
        site_name = _v(row, "Site name", "Site Name", "site_name", "SITE NAME")

        if not site_name:
            errors.append(f"Row {row_num}: 'Site name' column is empty – skipped")
            continue

        # ── raw province / ward ──────────────────────────────────────────
        raw_tinh     = _v(row, "Tỉnh", "Tinh", "TINH", "tinh", "Province")
        raw_phuong   = _v(row, "Phường xã", "Phuong xa", "Phường Xã",
                          "phuong_xa", "Ward")
        raw_mien     = _v(row, "Miền", "Mien", "MIEN", "mien")

        # ── fuzzy-resolve province / ward ────────────────────────────────
        if geo and raw_tinh:
            tinh_official = geo.resolve_tinh(raw_tinh)
            if not tinh_official:
                errors.append(
                    f"Row {row_num} (site '{site_name}'): "
                    f"Province '{raw_tinh}' not found in DB – skipped"
                )
                continue
            mien = geo.mien_for(tinh_official) or raw_mien or ""
            phuong_xa_official: Optional[str] = None
            if raw_phuong:
                phuong_xa_official = geo.resolve_xa(tinh_official, raw_phuong)
                # ward mismatch is a warning, not a hard error
                if not phuong_xa_official:
                    errors.append(
                        f"Row {row_num} (site '{site_name}'): "
                        f"Ward '{raw_phuong}' not found under '{tinh_official}' – "
                        f"field left blank"
                    )
        else:
            tinh_official      = raw_tinh or ""
            mien               = raw_mien or ""
            phuong_xa_official = raw_phuong

        if not tinh_official:
            errors.append(
                f"Row {row_num} (site '{site_name}'): 'Tinh' is empty – skipped"
            )
            continue

        rec: Dict[str, Any] = {
            "mien":         mien,
            "tinh":         tinh_official,
            "phuong_xa":    phuong_xa_official,
            "site_name_cu": _v(row, "Site name (cũ)", "Site name (cu)",
                               "Site Name (cũ)"),
            "site_name":    site_name,
            "site_vip":     _v(row, "Site VIP", "site_vip"),
            "lat":          _float(row, "Lat", "LAT", "lat", "Latitude"),
            "long":         _float(row, "Long", "LONG", "long", "Longitude"),
            "tram_2g":      _bool(row, "Trạm 2G", "Tram 2G", "tram_2g"),
            "tram_3g":      _bool(row, "Trạm 3G", "Tram 3G", "tram_3g"),
            "tram_4g":      _bool(row, "Trạm 4G", "Tram 4G", "tram_4g"),
            "tram_5g":      _bool(row, "Trạm 5G", "Tram 5G", "tram_5g"),
            "repeater":     _bool(row, "Repeater", "repeater"),
            "booster":      _bool(row, "Booster",  "booster"),
            "node_truyen_dan_only": _bool(
                row,
                "Node truyền dẫn only (không có điểm phát sóng)",
                "Node truyen dan only", "node_truyen_dan_only",
            ),
            "tram_phu_song_tsca": _bool(
                row,
                "Trạm phủ sóng TSCA (x)", "Tram phu song TSCA",
                "tram_phu_song_tsca", "TSCA",
            ),
            "phan_loai_tram": _v(
                row,
                "IBC/ Macro outdoor / IBC + Outdoor / miniDAS / Smallcell",
                "IBC/Macro outdoor/IBC + Outdoor/miniDAS/Smallcell",
                "Phan loai tram", "phan_loai_tram",
            ),
            "moran_3g": _v(row,
                "TRẠM MORAN 3G (VNPT HOST, MBF HOST)", "MORAN 3G", "moran_3g"),
            "moran_4g": _v(row,
                "TRẠM MORAN 4G (VNPT HOST, MBF HOST)", "MORAN 4G", "moran_4g"),
            "moran_5g": _v(row,
                "TRẠM MORAN 5G (VNPT HOST, MBF HOST)", "MORAN 5G", "moran_5g"),
            "ma_ptm": _v(row, "Mã PTM", "Ma PTM", "ma_ptm", "MaPTM", "PTM") or "",
            "do_cao_dinh_cot_anten": _float(
                row,
                "Độ cao đỉnh cột anten (m) đến mặt đất",
                "Do cao dinh cot anten (m) den mat dat",
                "Do cao dinh cot anten", "do_cao_dinh_cot_anten",
            ),
            "do_cao_cot_anten": _float(
                row,
                "Độ cao cột anten (đỉnh cột anten (m) đến mặt sàn)",
                "Do cao cot anten (dinh cot anten (m) den mat san)",
                "Do cao cot anten", "do_cao_cot_anten",
            ),
            "dia_chi": _v(row, "Địa chỉ", "Dia chi", "dia_chi"),
            "ghi_chu": _v(row, "Ghi chú", "Ghi chu", "ghi_chu"),
        }

        if db:
            existing = db.query(Site).filter(
                Site.site_name == site_name
            ).first()
            if existing:
                to_update.append({
                    "existing_id": existing.id,
                    "anchor":      site_name,
                    "changes":     rec,
                })
            else:
                to_create.append(rec)
        else:
            to_create.append(rec)

    return {
        "to_create": to_create,
        "to_update": to_update,
        "errors":    errors,
        "dry_run":   dry_run,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Cell-common helpers
# ─────────────────────────────────────────────────────────────────────────────

def _cell_common(row, geo: Optional[GeoCache] = None,
                 errors_out: Optional[List] = None,
                 row_num: int = 0) -> Dict[str, Any]:
    raw_tinh   = _v(row, "Tỉnh", "Tinh", "tinh")
    raw_phuong = _v(row, "Phường xã", "Phuong xa", "phuong_xa")
    raw_mien   = _v(row, "Miền", "Mien", "mien")

    if geo and raw_tinh:
        tinh_official = geo.resolve_tinh(raw_tinh)
        if not tinh_official:
            if errors_out is not None:
                errors_out.append(
                    f"Row {row_num}: Province '{raw_tinh}' not found in DB – "
                    f"stored as-is"
                )
            tinh_official = raw_tinh
        mien = geo.mien_for(tinh_official) or raw_mien or ""
        phuong_xa_official: Optional[str] = None
        if raw_phuong:
            phuong_xa_official = geo.resolve_xa(tinh_official, raw_phuong)
    else:
        tinh_official      = raw_tinh
        mien               = raw_mien
        phuong_xa_official = raw_phuong

    return {
        "mien":      mien,
        "tinh":      tinh_official,
        "phuong_xa": phuong_xa_official,
        "site_name": _v(row, "Site Name", "Site name", "site_name") or "",
        "cell_name": _v(row, "Cell Name", "Cell name", "cell_name") or "",
        "cell_vip":  _v(row, "Cell VIP",  "cell_vip"),
        "moran":     _v(row, "MORAN", "Moran", "moran"),
        "lat":       _float(row, "Lat", "LAT", "lat"),
        "long":      _float(row, "Long", "LONG", "long"),
        "vung_phu_song": _v(row, "Vùng phủ sóng", "Vung phu song",
                             "vung_phu_song"),
        "vendor":    _v(row, "Vendor", "vendor"),
        "do_cao_anten": _float(row, "Độ cao anten", "Do cao anten",
                                "do_cao_anten"),
        "azimuth":   _float(row, "Azimuth", "azimuth"),
        "m_tilt":    _float(row, "M-tilt",  "M-Tilt",  "m_tilt"),
        "e_tilt":    _float(row, "E-Tilt",  "E-tilt",  "e_tilt"),
        "total_tilt": _float(row, "Total Tilt", "Total tilt", "total_tilt"),
        "loai_anten": _v(row, "Loại Anten", "Loai Anten", "loai_anten"),
        "baseband":  _v(row, "Baseband", "baseband"),
        "rf":        _v(row, "RF", "rf"),
        "cell_id":   _v(row, "Cell ID", "cell_id"),
        "mimo":      _v(row, "MIMO", "mimo"),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Cell import parsers  (dry-run + auto-create-site + fuzzy)
# ─────────────────────────────────────────────────────────────────────────────

def _parse_cell_excel(
    file_bytes: bytes,
    Model,
    extra_fields_fn,           # (row) -> dict of tech-specific fields
    db=None,
    dry_run: bool = False,
) -> Dict[str, Any]:
    """
    Generic cell import that supports:
    * dry_run     – preview without touching DB
    * auto-create – creates missing Site records from cell file data
    * fuzzy-map   – resolves province/ward to official DB names
    """
    df  = _read_excel(file_bytes)
    geo = GeoCache(db) if db else None

    to_create:      List[Dict] = []
    to_update:      List[Dict] = []
    sites_to_create: List[Dict] = []   # new sites that will be auto-created
    errors:         List[str]  = []

    # Track sites we will auto-create during this import (name → rec)
    # so we don't schedule the same new site twice
    pending_new_sites: Dict[str, Dict] = {}

    from app.models.site import Site  # lazy

    for i, row in df.iterrows():
        row_num   = int(str(i)) + 2  # type: ignore[arg-type]
        row_errors: List[str] = []

        common = _cell_common(row, geo=geo, errors_out=row_errors,
                              row_num=row_num)
        errors.extend(row_errors)

        cell_name = common.get("cell_name", "")
        site_name = common.get("site_name", "")

        if not cell_name:
            errors.append(f"Row {row_num}: 'Cell Name' is empty – skipped")
            continue
        if not site_name:
            errors.append(f"Row {row_num}: 'Site Name' is empty – skipped")
            continue

        extra = extra_fields_fn(row)
        rec   = {**common, **extra}

        # ── resolve site ─────────────────────────────────────────────────
        site_obj = None
        if db:
            site_obj = db.query(Site).filter(
                Site.site_name == site_name
            ).first()

        if site_obj:
            site_id = site_obj.id
        elif site_name in pending_new_sites:
            site_id = None   # will be resolved after site creation
        else:
            # Schedule auto-create of the site
            new_site_rec = {
                "site_name": site_name,
                "mien":      common.get("mien") or "",
                "tinh":      common.get("tinh") or "",
                "phuong_xa": common.get("phuong_xa"),
                "lat":       common.get("lat"),
                "long":      common.get("long"),
            }
            pending_new_sites[site_name] = new_site_rec
            sites_to_create.append(new_site_rec)
            site_id = None

        rec["site_id"] = site_id  # None for pending; resolved on commit

        # ── check existing cell ──────────────────────────────────────────
        existing_cell = None
        if db and site_obj:
            existing_cell = db.query(Model).filter(
                Model.site_id == site_obj.id,
                Model.cell_name == cell_name,
            ).first()

        if existing_cell:
            to_update.append({
                "existing_id": existing_cell.id,
                "anchor":      f"{site_name}/{cell_name}",
                "changes":     rec,
            })
        else:
            to_create.append(rec)

    result: Dict[str, Any] = {
        "to_create":      to_create,
        "to_update":      to_update,
        "sites_to_create": sites_to_create,
        "errors":          errors,
        "dry_run":         dry_run,
    }
    return result


def parse_site_excel_simple(file_bytes: bytes) -> List[Dict[str, Any]]:
    """
    Legacy list-based return kept for backward compatibility.
    Used internally when db is not available.
    """
    result = parse_site_excel(file_bytes, db=None, dry_run=False)
    records: List[Dict] = []
    for rec in result["to_create"]:
        records.append(rec)
    for upd in result["to_update"]:
        records.append(upd["changes"])
    return records


# ── Public parsers ────────────────────────────────────────────────────────────

def parse_cell3g_excel(
    file_bytes: bytes,
    db=None,
    dry_run: bool = False,
) -> Dict[str, Any]:
    from app.models.cell_3g import Cell3G

    def extra(row):
        return {
            "chung_anten": _v(row, "Chung anten", "chung_anten"),
            "arfcn":       _v(row, "ARFCN", "arfcn"),
            "psc":         _v(row, "PSC",   "psc"),
        }

    return _parse_cell_excel(file_bytes, Cell3G, extra, db=db, dry_run=dry_run)


def parse_cell4g_excel(
    file_bytes: bytes,
    db=None,
    dry_run: bool = False,
) -> Dict[str, Any]:
    from app.models.cell_4g import Cell4G

    def extra(row):
        return {
            "chung_anten":      _v(row, "Chung anten",     "chung_anten"),
            "earfcn":           _v(row, "EARFCN",           "earfcn"),
            "pci":              _v(row, "PCI",              "pci"),
            "root_sequence_id": _v(row, "Root Sequence ID", "root_sequence_id"),
        }

    return _parse_cell_excel(file_bytes, Cell4G, extra, db=db, dry_run=dry_run)


def parse_cell5g_excel(
    file_bytes: bytes,
    db=None,
    dry_run: bool = False,
) -> Dict[str, Any]:
    from app.models.cell_5g import Cell5G

    def extra(row):
        return {
            "nr_arfcn":         _v(row, "NR-ARFCN",        "nr_arfcn"),
            "pci":              _v(row, "PCI",              "pci"),
            "root_sequence_id": _v(row, "Root Sequence ID", "root_sequence_id"),
        }

    return _parse_cell_excel(file_bytes, Cell5G, extra, db=db, dry_run=dry_run)
PYEOF

# ── 1-F  Updated sites.py  ───────────────────────────────────────────────────
cat > backend/app/api/routes/sites.py << 'PYEOF'
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

router = APIRouter()


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
    """
    Preview what would happen if this file were imported.
    Returns counts + first few names in each bucket.  Nothing is written.
    """
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
    errors    = list(result["errors"])   # copy – we may add runtime errors
    created, updated = 0, 0

    # ── Create new sites ──────────────────────────────────────────────────
    for rec in to_create:
        try:
            site = Site(**rec, created_by=current_user.id)
            db.add(site)
            db.commit()
            log_action(db, current_user, "CREATE", "sites", site.id,
                       new_value=rec)
            created += 1
        except Exception as e:
            db.rollback()
            errors.append(f"Create '{rec.get('site_name')}': {e}")

    # ── Update existing sites ─────────────────────────────────────────────
    for upd in to_update:
        try:
            existing = db.query(Site).filter(
                Site.id == upd["existing_id"]
            ).first()
            if not existing:
                errors.append(f"Site '{upd['anchor']}' disappeared during import")
                continue
            old = {c.name: getattr(existing, c.name)
                   for c in existing.__table__.columns}
            changes = upd["changes"]
            for k, v in changes.items():
                if k == "site_name":
                    continue          # anchor – never overwrite
                if v is not None:
                    setattr(existing, k, v)
            db.commit()
            log_action(db, current_user, "UPDATE", "sites",
                       existing.id, old_value=old, new_value=changes)
            updated += 1
        except Exception as e:
            db.rollback()
            errors.append(f"Update '{upd['anchor']}': {e}")

    return {"created": created, "updated": updated, "errors": errors}


@router.get("/", response_model=List[SiteRead])
def list_sites(
    skip: int = 0,
    limit: int = 500,
    search:  Optional[str]  = Query(None),
    mien:    Optional[str]  = Query(None),
    tinh:    Optional[str]  = Query(None),
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


@router.post("/", response_model=SiteRead, status_code=201)
def create_site(
    payload: SiteCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    existing = db.query(Site).filter(
        Site.site_name == payload.site_name
    ).first()
    if existing:
        raise HTTPException(
            status_code=400,
            detail=f"Site '{payload.site_name}' already exists",
        )
    site = Site(**payload.model_dump(), created_by=current_user.id)
    db.add(site)
    db.commit()
    db.refresh(site)
    log_action(db, current_user, "CREATE", "sites", site.id,
               new_value=payload.model_dump())
    return site


# ── Dynamic routes LAST ───────────────────────────────────────────────────────

@router.get("/{site_id}", response_model=SiteRead)
def get_site(
    site_id: int,
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    return _site_or_404(db, site_id)


@router.put("/{site_id}", response_model=SiteRead)
def update_site(
    site_id: int,
    payload: SiteUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    site = _site_or_404(db, site_id)
    old  = {c.name: getattr(site, c.name) for c in site.__table__.columns}
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

    # ── Restriction: refuse if cells exist ───────────────────────────────
    cell_count = (
        db.query(Cell3G).filter(Cell3G.site_id == site_id).count()
        + db.query(Cell4G).filter(Cell4G.site_id == site_id).count()
        + db.query(Cell5G).filter(Cell5G.site_id == site_id).count()
    )
    if cell_count > 0:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Cannot delete. This site contains {cell_count} cell(s). "
                f"Please delete the cells first or move them to another site."
            ),
        )

    db.delete(site)
    db.commit()
    log_action(db, current_user, "DELETE", "sites", site_id)
    return {"message": "Deleted"}
PYEOF

# ── 1-G  Updated cells_3g.py ─────────────────────────────────────────────────
cat > backend/app/api/routes/cells_3g.py << 'PYEOF'
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
PYEOF

# ── 1-H  Updated cells_4g.py ─────────────────────────────────────────────────
cat > backend/app/api/routes/cells_4g.py << 'PYEOF'
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.cell_4g import Cell4G
from app.models.site import Site
from app.schemas.cell import Cell4GCreate, Cell4GUpdate, Cell4GRead
from app.utils.deps import get_current_user
from app.utils.audit import log_action
from app.models.user import User
from app.services.import_excel import parse_cell4g_excel

router = APIRouter()


def _or_404(db: Session, record_id: int) -> Cell4G:
    obj = db.query(Cell4G).filter(Cell4G.id == record_id).first()
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
    site_name = rec.get("site_name", "").strip()
    site = db.query(Site).filter(Site.site_name == site_name).first()
    if site:
        return site.id
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


@router.get("/", response_model=List[Cell4GRead])
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
    q = db.query(Cell4G)
    if search:
        q = q.filter(
            Cell4G.cell_name.ilike(f"%{search}%") |
            Cell4G.site_name.ilike(f"%{search}%")
        )
    if mien:          q = q.filter(Cell4G.mien == mien)
    if tinh:          q = q.filter(Cell4G.tinh == tinh)
    if vendor:        q = q.filter(Cell4G.vendor == vendor)
    if mimo:          q = q.filter(Cell4G.mimo == mimo)
    if vung_phu_song: q = q.filter(Cell4G.vung_phu_song == vung_phu_song)
    return q.offset(skip).limit(limit).all()


@router.get("/count")
def count_cells(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return {"count": db.query(Cell4G).count()}


@router.post("/import-excel/dry-run")
async def dry_run_excel(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    content = await file.read()
    try:
        result = parse_cell4g_excel(content, db=db, dry_run=True)
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


@router.post("/import-excel")
async def import_excel(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    content = await file.read()
    try:
        result = parse_cell4g_excel(content, db=db, dry_run=False)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Cannot read Excel: {e}")

    errors  = list(result["errors"])
    created, updated, sites_auto_created = 0, 0, 0

    for rec in result["to_create"]:
        try:
            site_id = _ensure_site(db, rec, current_user)
            if site_id != rec.get("site_id"):
                sites_auto_created += 1
            rec["site_id"] = site_id
            cell = Cell4G(**{k: v for k, v in rec.items()
                             if hasattr(Cell4G, k)},
                          created_by=current_user.id)
            db.add(cell)
            db.commit()
            created += 1
        except Exception as e:
            db.rollback()
            errors.append(f"Create cell '{rec.get('cell_name')}': {e}")

    for upd in result["to_update"]:
        try:
            existing = db.query(Cell4G).filter(
                Cell4G.id == upd["existing_id"]
            ).first()
            if not existing:
                errors.append(f"Cell '{upd['anchor']}' disappeared during import")
                continue
            changes = upd["changes"]
            for k, v in changes.items():
                if k in ("cell_name", "site_id"):
                    continue
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


@router.get("/{cell_id}", response_model=Cell4GRead)
def get_cell(cell_id: int,
             db: Session = Depends(get_db),
             _=Depends(get_current_user)):
    return _or_404(db, cell_id)


@router.post("/", response_model=Cell4GRead, status_code=201)
def create_cell(
    payload: Cell4GCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_site(db, payload.site_id)
    cell = Cell4G(**payload.model_dump(), created_by=current_user.id)
    db.add(cell)
    db.commit()
    db.refresh(cell)
    log_action(db, current_user, "CREATE", "cells_4g", cell.id,
               new_value=payload.model_dump())
    return cell


@router.put("/{cell_id}", response_model=Cell4GRead)
def update_cell(
    cell_id: int,
    payload: Cell4GUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    cell = _or_404(db, cell_id)
    old  = {c.name: getattr(cell, c.name) for c in cell.__table__.columns}
    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(cell, k, v)
    db.commit()
    db.refresh(cell)
    log_action(db, current_user, "UPDATE", "cells_4g", cell.id,
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
    log_action(db, current_user, "DELETE", "cells_4g", cell_id)
    return {"message": "Deleted"}
PYEOF

# ── 1-I  Updated cells_5g.py ─────────────────────────────────────────────────
cat > backend/app/api/routes/cells_5g.py << 'PYEOF'
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
from app.services.import_excel import parse_cell5g_excel

router = APIRouter()


def _or_404(db: Session, record_id: int) -> Cell5G:
    obj = db.query(Cell5G).filter(Cell5G.id == record_id).first()
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
    site_name = rec.get("site_name", "").strip()
    site = db.query(Site).filter(Site.site_name == site_name).first()
    if site:
        return site.id
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


@router.get("/", response_model=List[Cell5GRead])
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
    q = db.query(Cell5G)
    if search:
        q = q.filter(
            Cell5G.cell_name.ilike(f"%{search}%") |
            Cell5G.site_name.ilike(f"%{search}%")
        )
    if mien:          q = q.filter(Cell5G.mien == mien)
    if tinh:          q = q.filter(Cell5G.tinh == tinh)
    if vendor:        q = q.filter(Cell5G.vendor == vendor)
    if mimo:          q = q.filter(Cell5G.mimo == mimo)
    if vung_phu_song: q = q.filter(Cell5G.vung_phu_song == vung_phu_song)
    return q.offset(skip).limit(limit).all()


@router.get("/count")
def count_cells(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return {"count": db.query(Cell5G).count()}


@router.post("/import-excel/dry-run")
async def dry_run_excel(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    content = await file.read()
    try:
        result = parse_cell5g_excel(content, db=db, dry_run=True)
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


@router.post("/import-excel")
async def import_excel(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    content = await file.read()
    try:
        result = parse_cell5g_excel(content, db=db, dry_run=False)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Cannot read Excel: {e}")

    errors  = list(result["errors"])
    created, updated, sites_auto_created = 0, 0, 0

    for rec in result["to_create"]:
        try:
            site_id = _ensure_site(db, rec, current_user)
            if site_id != rec.get("site_id"):
                sites_auto_created += 1
            rec["site_id"] = site_id
            cell = Cell5G(**{k: v for k, v in rec.items()
                             if hasattr(Cell5G, k)},
                          created_by=current_user.id)
            db.add(cell)
            db.commit()
            created += 1
        except Exception as e:
            db.rollback()
            errors.append(f"Create cell '{rec.get('cell_name')}': {e}")

    for upd in result["to_update"]:
        try:
            existing = db.query(Cell5G).filter(
                Cell5G.id == upd["existing_id"]
            ).first()
            if not existing:
                errors.append(f"Cell '{upd['anchor']}' disappeared during import")
                continue
            changes = upd["changes"]
            for k, v in changes.items():
                if k in ("cell_name", "site_id"):
                    continue
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


@router.get("/{cell_id}", response_model=Cell5GRead)
def get_cell(cell_id: int,
             db: Session = Depends(get_db),
             _=Depends(get_current_user)):
    return _or_404(db, cell_id)


@router.post("/", response_model=Cell5GRead, status_code=201)
def create_cell(
    payload: Cell5GCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_site(db, payload.site_id)
    cell = Cell5G(**payload.model_dump(), created_by=current_user.id)
    db.add(cell)
    db.commit()
    db.refresh(cell)
    log_action(db, current_user, "CREATE", "cells_5g", cell.id,
               new_value=payload.model_dump())
    return cell


@router.put("/{cell_id}", response_model=Cell5GRead)
def update_cell(
    cell_id: int,
    payload: Cell5GUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    cell = _or_404(db, cell_id)
    old  = {c.name: getattr(cell, c.name) for c in cell.__table__.columns}
    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(cell, k, v)
    db.commit()
    db.refresh(cell)
    log_action(db, current_user, "UPDATE", "cells_5g", cell.id,
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
    log_action(db, current_user, "DELETE", "cells_5g", cell_id)
    return {"message": "Deleted"}
PYEOF

# ── 1-J  Updated main.py – register antenna router ───────────────────────────
cat > backend/app/main.py << 'PYEOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.db.session import engine, SessionLocal
from app.db import base  # noqa – registers all models
from app.db.base import Base
from app.api.routes import (
    auth, users, sites, cells_3g, cells_4g, cells_5g,
    dropdowns, report, audit,
)
from app.api.routes import antenna as antenna_router

Base.metadata.create_all(bind=engine)


def _seed_initial_data():
    db = SessionLocal()
    try:
        from app.models.user import User, UserRole
        from app.core.security import get_password_hash
        from app.models.dropdown import DropdownGeneral, DropdownVendor

        if not db.query(User).filter(User.username == "admin").first():
            db.add(User(
                email="admin@sitelink.com",
                username="admin",
                full_name="Administrator",
                hashed_password=get_password_hash("admin"),
                role=UserRole.admin,
            ))
            db.commit()

        def seed_cat(cat, values):
            if db.query(DropdownGeneral).filter(
                    DropdownGeneral.category == cat).count() == 0:
                for v in values:
                    db.add(DropdownGeneral(category=cat, value=v, label=v))
                db.commit()

        seed_cat("moran",          ["VNPT HOST", "MBF HOST"])
        seed_cat("phan_loai_tram", ["IBC", "Macro outdoor", "IBC + Outdoor",
                                     "Smallcell", "miniDAS"])
        seed_cat("mien",           ["MB", "MT", "MN"])
        seed_cat("vung_phu_song",  ["Indoor", "Outdoor"])
        seed_cat("mimo",           ["2x2", "4x4", "8x8"])
        seed_cat("site_vip",       ["VIP", "VVIP"])
        seed_cat("csht", [
            "VNPT", "MOBIFONE", "XA HOI HOA", "VIETTEL",
            "LIEN KET", "HA TANG CO SAN", "GTEL", "IBC", "VIETNAMMOBILE",
        ])

        if db.query(DropdownVendor).count() == 0:
            for row in [
                ("Alcatel",  "Alcatel",  "Nokia",    "Nokia"),
                ("Nokia",    "Nokia",    "Ericsson", "Ericsson"),
                ("Ericsson", "Ericsson", "Huawei",   "Huawei"),
                ("Huawei",   "Huawei",   "ZTE",      "ZTE"),
                ("ZTE",      "ZTE",      "Samsung",  "Samsung"),
            ]:
                db.add(DropdownVendor(
                    vendor_2g=row[0], vendor_3g=row[1],
                    vendor_4g=row[2], vendor_5g=row[3],
                ))
            db.commit()
    finally:
        db.close()


app = FastAPI(
    title="SiteLink API",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def on_startup():
    _seed_initial_data()


PREFIX = "/api/v1"
app.include_router(auth.router,            prefix=f"{PREFIX}/auth",      tags=["Auth"])
app.include_router(users.router,           prefix=f"{PREFIX}/users",     tags=["Users"])
app.include_router(sites.router,           prefix=f"{PREFIX}/sites",     tags=["Sites"])
app.include_router(cells_3g.router,        prefix=f"{PREFIX}/cells-3g",  tags=["Cells-3G"])
app.include_router(cells_4g.router,        prefix=f"{PREFIX}/cells-4g",  tags=["Cells-4G"])
app.include_router(cells_5g.router,        prefix=f"{PREFIX}/cells-5g",  tags=["Cells-5G"])
app.include_router(dropdowns.router,       prefix=f"{PREFIX}/dropdowns", tags=["Dropdowns"])
app.include_router(report.router,          prefix=f"{PREFIX}/report",    tags=["Report"])
app.include_router(audit.router,           prefix=f"{PREFIX}/audit",     tags=["Audit"])
app.include_router(antenna_router.router,  prefix=f"{PREFIX}/antennas",  tags=["Antennas"])


@app.get("/health")
def health():
    return {"status": "ok"}
PYEOF

# ── 1-K  Updated dropdowns.py – expose new antennas table ────────────────────
cat > backend/app/api/routes/dropdowns.py << 'PYEOF'
from typing import Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.dropdown import (
    DropdownTinhXaPhuong, DropdownAntenna, DropdownVendor, DropdownGeneral,
)
from app.models.antenna import Antenna
from app.utils.deps import get_current_user

router = APIRouter()


@router.get("/tinh-xa-phuong")
def get_tinh_xa_phuong(
    tinh: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    q = db.query(DropdownTinhXaPhuong)
    if tinh:
        q = q.filter(DropdownTinhXaPhuong.ten_tinh == tinh)
    rows = q.order_by(
        DropdownTinhXaPhuong.ten_tinh,
        DropdownTinhXaPhuong.ten_phuong_xa,
    ).all()
    return [
        {
            "id": r.id, "mien": r.mien, "ten_tinh": r.ten_tinh,
            "ten_phuong_xa": r.ten_phuong_xa, "ma_tinh": r.ma_tinh,
            "ma_phuong_xa": r.ma_phuong_xa, "ky_tu_1_6": r.ky_tu_1_6,
        }
        for r in rows
    ]


@router.get("/tinh-list")
def get_tinh_list(
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    rows = (
        db.query(
            DropdownTinhXaPhuong.ten_tinh,
            DropdownTinhXaPhuong.mien,
        )
        .distinct()
        .order_by(DropdownTinhXaPhuong.ten_tinh)
        .all()
    )
    return [{"ten_tinh": r.ten_tinh, "mien": r.mien} for r in rows]


@router.get("/antenna")
def get_antenna(db: Session = Depends(get_db), _=Depends(get_current_user)):
    """
    Returns from the new 'antennas' managed table (full detail).
    Falls back to legacy dropdown_antenna if antennas table is empty.
    """
    rows = db.query(Antenna).order_by(Antenna.name).all()
    if rows:
        return [
            {
                "id":             r.id,
                "name":           r.name,
                "band":           r.band,
                "no_of_ports":    r.no_of_ports,
                "no_of_beam":     r.no_of_beam,
                "horizontal_bw":  r.horizontal_bw,
                "vertical_bw":    r.vertical_bw,
                "gain":           r.gain,
                "etilt":          r.etilt,
                "h":              r.h,
                "w":              r.w,
                "d":              r.d,
                "weight":         r.weight,
                "connector_type": r.connector_type,
                "ghi_chu":        r.ghi_chu,
            }
            for r in rows
        ]
    # Legacy fallback
    legacy = db.query(DropdownAntenna).order_by(DropdownAntenna.name).all()
    return [
        {
            "id": r.id, "name": r.name, "band": r.band,
            "no_of_ports": r.no_of_ports, "gain": r.gain,
            "no_of_beam": None, "horizontal_bw": None, "vertical_bw": None,
            "etilt": None, "h": None, "w": None, "d": None,
            "weight": None, "connector_type": None, "ghi_chu": None,
        }
        for r in legacy
    ]


@router.get("/vendor")
def get_vendor(db: Session = Depends(get_db), _=Depends(get_current_user)):
    rows = db.query(DropdownVendor).all()
    return [
        {
            "id": r.id, "vendor_2g": r.vendor_2g, "vendor_3g": r.vendor_3g,
            "vendor_4g": r.vendor_4g, "vendor_5g": r.vendor_5g,
        }
        for r in rows
    ]


@router.get("/general/{category}")
def get_general(
    category: str,
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    rows = db.query(DropdownGeneral).filter(
        DropdownGeneral.category == category
    ).all()
    return [{"id": r.id, "value": r.value, "label": r.label} for r in rows]
PYEOF

echo "✓ Backend files written"

# ─────────────────────────────────────────────────────────────────────────────
# 2. FRONTEND FILES
# ─────────────────────────────────────────────────────────────────────────────

# ── 2-A  types/index.ts – add AntennaItem full detail + DryRun types ─────────
cat > frontend/src/types/index.ts << 'TSEOF'
export interface User {
  id: number
  email: string
  username: string
  full_name?: string
  role: 'admin' | 'user'
  is_active: boolean
  auth_provider: 'local' | 'sso'
}

export interface Site {
  id: number
  mien: string
  tinh: string
  phuong_xa?: string
  site_name_cu?: string
  site_name: string
  site_vip?: string
  lat: number
  long: number
  tram_2g: boolean
  tram_3g: boolean
  tram_4g: boolean
  tram_5g: boolean
  repeater: boolean
  booster: boolean
  node_truyen_dan_only: boolean
  tram_phu_song_tsca: boolean
  phan_loai_tram?: string
  moran_3g?: string
  moran_4g?: string
  moran_5g?: string
  ma_ptm: string
  do_cao_dinh_cot_anten?: number
  do_cao_cot_anten?: number
  dia_chi?: string
  ghi_chu?: string
}

export interface CellBase {
  id: number
  site_id: number
  mien?: string
  tinh?: string
  phuong_xa?: string
  site_name: string
  cell_name: string
  cell_vip?: string
  moran?: string
  lat?: number
  long?: number
  vung_phu_song?: string
  vendor?: string
  do_cao_anten?: number
  azimuth?: number
  m_tilt?: number
  e_tilt?: number
  total_tilt?: number
  loai_anten?: string
  baseband?: string
  rf?: string
  cell_id?: string
  mimo?: string
}

export interface Cell3G extends CellBase {
  chung_anten?: string
  arfcn?: string
  psc?: string
}

export interface Cell4G extends CellBase {
  chung_anten?: string
  earfcn?: string
  pci?: string
  root_sequence_id?: string
}

export interface Cell5G extends CellBase {
  nr_arfcn?: string
  pci?: string
  root_sequence_id?: string
}

export interface ReportRow {
  mien?: string
  tinh?: string
  site_count: number
  site_2g: number
  site_3g: number
  site_4g: number
  site_5g: number
  cell_3g: number
  cell_4g: number
  cell_5g: number
}

export interface AuditLog {
  id: number
  username: string
  action: string
  table_name: string
  record_id: number
  old_value?: string
  new_value?: string
  timestamp: string
}

export interface TinhItem {
  ten_tinh: string
  mien: string
}

export interface PhuongXaItem {
  id: number
  mien: string
  ten_tinh: string
  ten_phuong_xa: string
  ma_tinh: string
  ma_phuong_xa: string
  ky_tu_1_6: string
}

export interface AntennaItem {
  id: number
  name: string
  band?: string
  no_of_ports?: number
  no_of_beam?: number
  horizontal_bw?: string
  vertical_bw?: string
  gain?: string
  etilt?: string
  h?: string
  w?: string
  d?: string
  weight?: string
  connector_type?: string
  ghi_chu?: string
}

export interface ProvinceChartItem {
  tinh: string
  site_count: number
}

export interface CellProvinceChartItem {
  tinh: string
  cell_count: number
}

// ── Dry-run previews ─────────────────────────────────────────────────────────

export interface SiteDryRunResult {
  to_create: number
  to_update: number
  errors: number
  error_details: string[]
  preview_create: string[]
  preview_update: string[]
  dry_run: true
}

export interface CellDryRunResult {
  to_create: number
  to_update: number
  sites_to_create: number
  errors: number
  error_details: string[]
  preview_create: string[]
  preview_update: string[]
  preview_new_sites: string[]
  dry_run: true
}

export interface ImportResult {
  created: number
  updated: number
  sites_auto_created?: number
  errors: string[]
}

export interface AntennaFull {
  id: number
  name: string
  no_of_ports?: number
  band?: string
  no_of_beam?: number
  horizontal_bw?: string
  vertical_bw?: string
  gain?: string
  etilt?: string
  h?: string
  w?: string
  d?: string
  weight?: string
  connector_type?: string
  ghi_chu?: string
}
TSEOF

# ── 2-B  api/cells.ts – add dry-run calls ────────────────────────────────────
cat > frontend/src/api/cells.ts << 'TSEOF'
import api from './client'
import type { Cell3G, Cell4G, Cell5G, CellDryRunResult, ImportResult } from '@/types'

export type { CellDryRunResult, ImportResult }

export interface SiteImportResult {
  created: number
  updated: number
  errors: string[]
}

function makeCellApi<T>(tech: string) {
  return {
    list: (params?: Record<string, unknown>) =>
      api.get<T[]>(`/api/v1/cells-${tech}/`, { params }).then((r) => r.data),

    get: (id: number) =>
      api.get<T>(`/api/v1/cells-${tech}/${id}`).then((r) => r.data),

    create: (data: Partial<T>) =>
      api.post<T>(`/api/v1/cells-${tech}/`, data).then((r) => r.data),

    update: (id: number, data: Partial<T>) =>
      api.put<T>(`/api/v1/cells-${tech}/${id}`, data).then((r) => r.data),

    remove: (id: number) =>
      api.delete(`/api/v1/cells-${tech}/${id}`),

    /** Step-1: preview – nothing written to DB */
    dryRunExcel: (file: File) => {
      const form = new FormData()
      form.append('file', file)
      return api
        .post<CellDryRunResult>(`/api/v1/cells-${tech}/import-excel/dry-run`, form)
        .then((r) => r.data)
    },

    /** Step-2: actual import */
    importExcel: (file: File) => {
      const form = new FormData()
      form.append('file', file)
      return api
        .post<ImportResult>(`/api/v1/cells-${tech}/import-excel`, form)
        .then((r) => r.data)
    },
  }
}

export const cells3gApi = makeCellApi<Cell3G>('3g')
export const cells4gApi = makeCellApi<Cell4G>('4g')
export const cells5gApi = makeCellApi<Cell5G>('5g')
TSEOF

# ── 2-C  api/sites.ts – add dry-run call ─────────────────────────────────────
cat > frontend/src/api/sites.ts << 'TSEOF'
import api from './client'
import type { Site, SiteDryRunResult, ImportResult } from '@/types'

export const getSites = (params?: Record<string, unknown>) =>
  api.get<Site[]>('/api/v1/sites/', { params }).then((r) => r.data)

export const getSite = (id: number) =>
  api.get<Site>(`/api/v1/sites/${id}`).then((r) => r.data)

export const createSite = (data: Partial<Site>) =>
  api.post<Site>('/api/v1/sites/', data).then((r) => r.data)

export const updateSite = (id: number, data: Partial<Site>) =>
  api.put<Site>(`/api/v1/sites/${id}`, data).then((r) => r.data)

export const deleteSite = (id: number) =>
  api.delete(`/api/v1/sites/${id}`)

/** Step-1: preview – nothing written to DB */
export const dryRunSitesExcel = (file: File) => {
  const form = new FormData()
  form.append('file', file)
  return api
    .post<SiteDryRunResult>('/api/v1/sites/import-excel/dry-run', form)
    .then((r) => r.data)
}

/** Step-2: actual import */
export const importSitesExcel = (file: File) => {
  const form = new FormData()
  form.append('file', file)
  return api
    .post<ImportResult>('/api/v1/sites/import-excel', form)
    .then((r) => r.data)
}
TSEOF

# ── 2-D  api/antenna.ts – new ────────────────────────────────────────────────
cat > frontend/src/api/antenna.ts << 'TSEOF'
import api from './client'
import type { AntennaFull, CellDryRunResult } from '@/types'

export const getAntennas = (params?: Record<string, unknown>) =>
  api.get<AntennaFull[]>('/api/v1/antennas/', { params }).then((r) => r.data)

export const getAntenna = (id: number) =>
  api.get<AntennaFull>(`/api/v1/antennas/${id}`).then((r) => r.data)

export const createAntenna = (data: Partial<AntennaFull>) =>
  api.post<AntennaFull>('/api/v1/antennas/', data).then((r) => r.data)

export const updateAntenna = (id: number, data: Partial<AntennaFull>) =>
  api.put<AntennaFull>(`/api/v1/antennas/${id}`, data).then((r) => r.data)

export const deleteAntenna = (id: number) =>
  api.delete(`/api/v1/antennas/${id}`)

export const dryRunAntennaExcel = (file: File) => {
  const form = new FormData()
  form.append('file', file)
  return api
    .post('/api/v1/antennas/import-excel?dry_run=true', form)
    .then((r) => r.data)
}

export const importAntennaExcel = (file: File) => {
  const form = new FormData()
  form.append('file', file)
  return api
    .post('/api/v1/antennas/import-excel', form)
    .then((r) => r.data)
}
TSEOF

# ── 2-E  Shared DryRunModal component ────────────────────────────────────────
mkdir -p frontend/src/components/shared
cat > frontend/src/components/shared/DryRunModal.tsx << 'TSEOF'
/**
 * DryRunModal
 * -----------
 * Generic 2-step import wizard:
 *   Step 1 – upload file  → call dryRunFn  → show preview
 *   Step 2 – user confirms → call importFn → show result
 */
import React, { useState } from 'react'
import {
  Modal, Upload, Button, Steps, Descriptions, Tag,
  List, Alert, Space, Typography, Spin,
} from 'antd'
import {
  UploadOutlined, CheckCircleOutlined,
  ExclamationCircleOutlined, LoadingOutlined,
} from '@ant-design/icons'

export interface DryRunPreview {
  to_create: number
  to_update: number
  sites_to_create?: number   // cells only
  errors: number
  error_details: string[]
  preview_create: string[]
  preview_update: string[]
  preview_new_sites?: string[]
}

export interface ImportResultData {
  created: number
  updated: number
  sites_auto_created?: number
  errors: string[]
}

interface Props {
  open: boolean
  onClose: () => void
  title: string
  dryRunFn:  (file: File) => Promise<DryRunPreview>
  importFn:  (file: File) => Promise<ImportResultData>
  onSuccess: () => void
}

export default function DryRunModal({
  open, onClose, title, dryRunFn, importFn, onSuccess,
}: Props) {
  const [step,     setStep]     = useState(0)       // 0=upload 1=preview 2=done
  const [busy,     setBusy]     = useState(false)
  const [file,     setFile]     = useState<File | null>(null)
  const [preview,  setPreview]  = useState<DryRunPreview | null>(null)
  const [result,   setResult]   = useState<ImportResultData | null>(null)
  const [fatalErr, setFatalErr] = useState('')

  const reset = () => {
    setStep(0); setFile(null); setPreview(null)
    setResult(null); setFatalErr('')
  }

  const handleClose = () => { reset(); onClose() }

  // Step 0 → 1 : dry-run
  const handleDryRun = async () => {
    if (!file) return
    setBusy(true)
    setFatalErr('')
    try {
      const prev = await dryRunFn(file)
      setPreview(prev)
      setStep(1)
    } catch (e: any) {
      setFatalErr(e?.response?.data?.detail || 'Cannot read file')
    } finally {
      setBusy(false)
    }
  }

  // Step 1 → 2 : commit
  const handleConfirm = async () => {
    if (!file) return
    setBusy(true)
    try {
      const res = await importFn(file)
      setResult(res)
      setStep(2)
      onSuccess()
    } catch (e: any) {
      setFatalErr(e?.response?.data?.detail || 'Import failed')
    } finally {
      setBusy(false)
    }
  }

  const footer = () => {
    if (step === 0) return (
      <Space>
        <Button onClick={handleClose}>Huy</Button>
        <Button type="primary" disabled={!file} loading={busy}
                onClick={handleDryRun}>
          Kiem tra file
        </Button>
      </Space>
    )
    if (step === 1) return (
      <Space>
        <Button onClick={reset}>Chon lai file</Button>
        <Button onClick={handleClose}>Huy</Button>
        <Button type="primary" loading={busy} onClick={handleConfirm}
                disabled={(preview?.to_create ?? 0) + (preview?.to_update ?? 0) === 0}>
          Xac nhan import
        </Button>
      </Space>
    )
    return <Button type="primary" onClick={handleClose}>Dong</Button>
  }

  return (
    <Modal
      title={title}
      open={open}
      onCancel={handleClose}
      footer={footer()}
      width={700}
      destroyOnClose
    >
      <Steps
        current={step}
        size="small"
        style={{ marginBottom: 24 }}
        items={[
          { title: 'Chon file' },
          { title: 'Xem truoc' },
          { title: 'Hoan thanh' },
        ]}
      />

      {/* ── Step 0 : file picker ──────────────────────────────────────── */}
      {step === 0 && (
        <div>
          {fatalErr && (
            <Alert message={fatalErr} type="error" showIcon
                   style={{ marginBottom: 12 }} />
          )}
          <Upload
            accept=".xlsx,.xls"
            showUploadList={Boolean(file)}
            maxCount={1}
            beforeUpload={(f) => { setFile(f); return false }}
            onRemove={() => setFile(null)}
          >
            <Button icon={<UploadOutlined />}>Chon file Excel</Button>
          </Upload>
          {file && (
            <Typography.Text type="secondary" style={{ marginTop: 8, display: 'block' }}>
              Da chon: <strong>{file.name}</strong>
            </Typography.Text>
          )}
          {busy && (
            <div style={{ textAlign: 'center', marginTop: 16 }}>
              <Spin indicator={<LoadingOutlined spin />} />
              <div>Dang kiem tra file...</div>
            </div>
          )}
        </div>
      )}

      {/* ── Step 1 : preview ─────────────────────────────────────────── */}
      {step === 1 && preview && (
        <div>
          <Descriptions bordered size="small" column={2}
                        style={{ marginBottom: 16 }}>
            <Descriptions.Item label="Se tao moi">
              <Tag color="green">{preview.to_create}</Tag>
            </Descriptions.Item>
            <Descriptions.Item label="Se cap nhat">
              <Tag color="blue">{preview.to_update}</Tag>
            </Descriptions.Item>
            {preview.sites_to_create !== undefined && (
              <Descriptions.Item label="Site se tu dong tao">
                <Tag color="purple">{preview.sites_to_create}</Tag>
              </Descriptions.Item>
            )}
            <Descriptions.Item label="Dong co loi">
              <Tag color={preview.errors > 0 ? 'red' : 'default'}>
                {preview.errors}
              </Tag>
            </Descriptions.Item>
          </Descriptions>

          {preview.preview_create.length > 0 && (
            <div style={{ marginBottom: 12 }}>
              <Typography.Text strong>
                <CheckCircleOutlined style={{ color: '#52c41a' }} /> Se tao moi (mau):
              </Typography.Text>
              <List size="small" dataSource={preview.preview_create}
                    renderItem={(item) => <List.Item>{item}</List.Item>} />
              {preview.to_create > 5 && (
                <Typography.Text type="secondary">
                  ... va {preview.to_create - 5} ban ghi khac
                </Typography.Text>
              )}
            </div>
          )}

          {preview.preview_update.length > 0 && (
            <div style={{ marginBottom: 12 }}>
              <Typography.Text strong>
                <CheckCircleOutlined style={{ color: '#1890ff' }} /> Se cap nhat (mau):
              </Typography.Text>
              <List size="small" dataSource={preview.preview_update}
                    renderItem={(item) => <List.Item>{item}</List.Item>} />
            </div>
          )}

          {(preview.preview_new_sites?.length ?? 0) > 0 && (
            <div style={{ marginBottom: 12 }}>
              <Typography.Text strong>
                Site se duoc tu dong tao (mau):
              </Typography.Text>
              <List size="small" dataSource={preview.preview_new_sites}
                    renderItem={(item) => <List.Item>{item}</List.Item>} />
            </div>
          )}

          {preview.error_details.length > 0 && (
            <Alert
              type="warning"
              showIcon
              icon={<ExclamationCircleOutlined />}
              message={`${preview.errors} dong co loi (se bi bo qua)`}
              description={
                <div style={{ maxHeight: 150, overflowY: 'auto' }}>
                  {preview.error_details.slice(0, 20).map((e, i) => (
                    <div key={i} style={{ fontSize: 12, fontFamily: 'monospace' }}>
                      {e}
                    </div>
                  ))}
                  {preview.error_details.length > 20 && (
                    <div style={{ color: '#999' }}>
                      ... va {preview.error_details.length - 20} loi khac
                    </div>
                  )}
                </div>
              }
            />
          )}
        </div>
      )}

      {/* ── Step 2 : result ───────────────────────────────────────────── */}
      {step === 2 && result && (
        <div>
          <Alert
            type="success"
            showIcon
            message="Import hoan thanh"
            description={
              <div>
                <div>Da tao moi: <strong>{result.created}</strong></div>
                <div>Da cap nhat: <strong>{result.updated}</strong></div>
                {(result.sites_auto_created ?? 0) > 0 && (
                  <div>
                    Site tu dong tao:{' '}
                    <strong>{result.sites_auto_created}</strong>
                  </div>
                )}
                {result.errors.length > 0 && (
                  <div style={{ marginTop: 8 }}>
                    <Typography.Text type="danger">
                      {result.errors.length} loi:
                    </Typography.Text>
                    <div style={{ maxHeight: 120, overflowY: 'auto' }}>
                      {result.errors.slice(0, 10).map((e, i) => (
                        <div key={i} style={{ fontSize: 12, fontFamily: 'monospace' }}>
                          {e}
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            }
          />
        </div>
      )}
    </Modal>
  )
}
TSEOF

# ── 2-F  SitesPage.tsx – integrate DryRunModal ───────────────────────────────
cat > frontend/src/pages/sites/SitesPage.tsx << 'TSEOF'
import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, message, Row, Col, Alert,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, UploadOutlined, SearchOutlined,
  EditOutlined, DeleteOutlined,
} from '@ant-design/icons'
import { useNavigate } from 'react-router-dom'
import { getSites, deleteSite, dryRunSitesExcel, importSitesExcel } from '@/api/sites'
import type { Site } from '@/types'
import DryRunModal from '@/components/shared/DryRunModal'

const boolCell = (v: boolean) =>
  v ? <Tag color="green">x</Tag> : <Tag color="default">-</Tag>

export default function SitesPage() {
  const navigate    = useNavigate()
  const [sites,     setSites]     = useState<Site[]>([])
  const [loading,   setLoading]   = useState(false)
  const [search,    setSearch]    = useState('')
  const [mien,      setMien]      = useState<string | undefined>()
  const [tinh,      setTinh]      = useState<string | undefined>()
  const [loadError, setLoadError] = useState<string | null>(null)
  const [dryRunOpen, setDryRunOpen] = useState(false)

  const tinhOptions = [
    ...new Set(sites.map((s) => s.tinh).filter((t): t is string => Boolean(t))),
  ].sort()

  const load = () => {
    setLoading(true)
    setLoadError(null)
    getSites({ search: search || undefined, mien: mien || undefined,
               tinh: tinh || undefined, limit: 500 })
      .then(setSites)
      .catch((err) => {
        const detail = err?.response?.data?.detail || err?.message || 'Unknown error'
        setLoadError(`Cannot load sites: ${detail}`)
      })
      .finally(() => setLoading(false))
  }

  useEffect(() => { load() }, [search, mien, tinh])

  const handleDelete = async (id: number) => {
    try {
      await deleteSite(id)
      message.success('Da xoa site')
      load()
    } catch (err: any) {
      const detail = err?.response?.data?.detail || 'Xoa that bai'
      message.error(detail)
    }
  }

  const columns: ColumnsType<Site> = [
    {
      title: 'Hanh dong', key: 'action', fixed: 'left', width: 80,
      render: (_: unknown, r: Site) => (
        <Space>
          <Button size="small" icon={<EditOutlined />}
                  onClick={() => navigate(`/sites/${r.id}/edit`)} />
          <Popconfirm
            title="Xoa site nay?"
            description="Neu site con cell, thao tac se bi tu choi."
            onConfirm={() => handleDelete(r.id)}
          >
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    { title: 'Mien', dataIndex: 'mien', fixed: 'left', width: 70,
      sorter: (a, b) => (a.mien||'').localeCompare(b.mien||'') },
    { title: 'Tinh', dataIndex: 'tinh', fixed: 'left', width: 160,
      sorter: (a, b) => (a.tinh||'').localeCompare(b.tinh||'') },
    { title: 'Phuong xa',      dataIndex: 'phuong_xa',    width: 160 },
    { title: 'Site name (cu)', dataIndex: 'site_name_cu', width: 130 },
    { title: 'Site name', dataIndex: 'site_name', fixed: 'left', width: 160,
      sorter: (a, b) => (a.site_name||'').localeCompare(b.site_name||''),
      render: (v: string) => <strong>{v}</strong> },
    { title: 'Site VIP', dataIndex: 'site_vip', width: 90,
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-' },
    { title: 'Lat',  dataIndex: 'lat',  width: 110 },
    { title: 'Long', dataIndex: 'long', width: 110 },
    { title: 'Tram 2G', dataIndex: 'tram_2g', width: 80, render: boolCell },
    { title: 'Tram 3G', dataIndex: 'tram_3g', width: 80, render: boolCell },
    { title: 'Tram 4G', dataIndex: 'tram_4g', width: 80, render: boolCell },
    { title: 'Tram 5G', dataIndex: 'tram_5g', width: 80, render: boolCell },
    { title: 'Repeater', dataIndex: 'repeater', width: 90, render: boolCell },
    { title: 'Booster',  dataIndex: 'booster',  width: 85, render: boolCell },
    { title: 'Node truyen dan only',
      dataIndex: 'node_truyen_dan_only', width: 160, render: boolCell },
    { title: 'Tram phu song TSCA',
      dataIndex: 'tram_phu_song_tsca',   width: 160, render: boolCell },
    { title: 'Phan loai tram', dataIndex: 'phan_loai_tram', width: 180 },
    { title: 'MORAN 3G', dataIndex: 'moran_3g', width: 120 },
    { title: 'MORAN 4G', dataIndex: 'moran_4g', width: 120 },
    { title: 'MORAN 5G', dataIndex: 'moran_5g', width: 120 },
    { title: 'Ma PTM',   dataIndex: 'ma_ptm',   width: 120 },
    { title: 'Do cao dinh cot anten (m)',
      dataIndex: 'do_cao_dinh_cot_anten', width: 190 },
    { title: 'Do cao cot anten mat san (m)',
      dataIndex: 'do_cao_cot_anten', width: 210 },
    { title: 'Dia chi', dataIndex: 'dia_chi', width: 200 },
    { title: 'Ghi chu', dataIndex: 'ghi_chu', width: 200 },
  ]

  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Quan ly Site</Typography.Title>
        <Space>
          <Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>
            Import Excel
          </Button>
          <Button type="primary" icon={<PlusOutlined />}
                  onClick={() => navigate('/sites/new')}>
            Them moi
          </Button>
        </Space>
      </Row>

      {loadError && (
        <Alert message={loadError} type="error" showIcon closable
               style={{ marginBottom: 12 }} onClose={() => setLoadError(null)} />
      )}

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} placeholder="Tim site name..."
                 value={search} onChange={(e) => setSearch(e.target.value)} allowClear />
        </Col>
        <Col>
          <Select placeholder="Mien" allowClear style={{ width: 90 }}
                  value={mien} onChange={setMien}>
            {['MB','MT','MN'].map((m) =>
              <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="200px">
          <Select placeholder="Tinh" allowClear showSearch style={{ width: '100%' }}
                  value={tinh} onChange={setTinh}
                  filterOption={(input, opt) =>
                    String(opt?.children ?? '').toLowerCase().includes(input.toLowerCase())}>
            {tinhOptions.map((t) =>
              <Select.Option key={t} value={t}>{t}</Select.Option>)}
          </Select>
        </Col>
        <Col>
          <Button onClick={() => { setSearch(''); setMien(undefined); setTinh(undefined) }}>
            Xoa loc
          </Button>
        </Col>
        <Col>
          <Button onClick={load} loading={loading}>Lam moi</Button>
        </Col>
      </Row>

      <Table columns={columns} dataSource={sites} rowKey="id"
             loading={loading} size="small"
             scroll={{ x: scrollX, y: 600 }} bordered
             pagination={{ pageSize: 50, showTotal: (t) => `${t} sites`,
                           showSizeChanger: true }} />

      <DryRunModal
        open={dryRunOpen}
        onClose={() => setDryRunOpen(false)}
        title="Import Site tu Excel"
        dryRunFn={dryRunSitesExcel}
        importFn={importSitesExcel}
        onSuccess={load}
      />
    </div>
  )
}
TSEOF

# ── 2-G  Reusable CellPage factory (shared logic for 3G/4G/5G) ───────────────
# We write each cell page individually to keep tech-specific columns clean.

# helper function used in all 3 cell pages
write_cell_page() {
local TECH="$1"          # 3g | 4g | 5g
local TECH_UP="$2"       # 3G | 4G | 5G
local TYPE="$3"          # Cell3G | Cell4G | Cell5G
local API="$4"           # cells3gApi | cells4gApi | cells5gApi
local FILE="$5"          # destination file path
local EXTRA_COLS="$6"    # JSON-like shell var for extra table columns
local EXTRA_FORM="$7"    # JSX for extra form items

cat > "$FILE" << TSEOF
import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, message, Row, Col,
  Modal, Form, InputNumber,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, SearchOutlined,
  EditOutlined, DeleteOutlined,
} from '@ant-design/icons'
import { ${API} } from '@/api/cells'
import type { ${TYPE}, Site, AntennaItem } from '@/types'
import { getSites } from '@/api/sites'
import { getAntennaList } from '@/api/report'
import DryRunModal from '@/components/shared/DryRunModal'

export default function Cells${TECH_UP}Page() {
  const [data,        setData]        = useState<${TYPE}[]>([])
  const [loading,     setLoading]     = useState(false)
  const [search,      setSearch]      = useState('')
  const [mien,        setMien]        = useState<string | undefined>()
  const [tinh,        setTinh]        = useState<string | undefined>()
  const [vendor,      setVendor]      = useState<string | undefined>()
  const [sites,       setSites]       = useState<Site[]>([])
  const [antennaList, setAntennaList] = useState<AntennaItem[]>([])
  const [modalOpen,   setModalOpen]   = useState(false)
  const [editing,     setEditing]     = useState<${TYPE} | null>(null)
  const [dryRunOpen,  setDryRunOpen]  = useState(false)
  const [form] = Form.useForm()

  const tinhOptions   = [...new Set(data.map((c) => c.tinh).filter(Boolean))].sort() as string[]
  const vendorOptions = [...new Set(data.map((c) => c.vendor).filter(Boolean))].sort() as string[]

  const load = async () => {
    setLoading(true)
    try {
      setData(await ${API}.list({
        search: search || undefined,
        mien:   mien   || undefined,
        tinh:   tinh   || undefined,
        vendor: vendor || undefined,
        limit: 1000,
      }))
    } finally { setLoading(false) }
  }

  useEffect(() => {
    load()
    getSites({ limit: 2000 }).then(setSites)
    getAntennaList().then(setAntennaList)
  }, [search, mien, tinh, vendor])

  const handleSiteSelect = (siteId: number) => {
    const site = sites.find((s) => s.id === siteId)
    if (site) form.setFieldValue('site_name', site.site_name)
  }

  /** When user picks an antenna, auto-fill related fields */
  const handleAntennaSelect = (antennaName: string) => {
    const ant = antennaList.find((a) => a.name === antennaName)
    if (!ant) return
    form.setFieldsValue({
      loai_anten: ant.name,
    })
  }

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (r: ${TYPE}) => { setEditing(r); form.setFieldsValue(r); setModalOpen(true) }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) {
        await ${API}.update(editing.id, values)
        message.success('Cap nhat thanh cong')
      } else {
        await ${API}.create(values)
        message.success('Tao cell thanh cong')
      }
      setModalOpen(false)
      load()
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Loi')
    }
  }

  const handleDelete = async (id: number) => {
    await ${API}.remove(id)
    message.success('Da xoa')
    load()
  }

TSEOF

# Append columns + JSX – written inline per-tech (see individual pages below)
}

# ─── Cells3GPage ─────────────────────────────────────────────────────────────
cat > frontend/src/pages/cells/Cells3GPage.tsx << 'TSEOF'
import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, message, Row, Col,
  Modal, Form, InputNumber,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, SearchOutlined, UploadOutlined,
  EditOutlined, DeleteOutlined,
} from '@ant-design/icons'
import { cells3gApi } from '@/api/cells'
import type { Cell3G, Site, AntennaItem } from '@/types'
import { getSites } from '@/api/sites'
import { getAntennaList } from '@/api/report'
import DryRunModal from '@/components/shared/DryRunModal'

export default function Cells3GPage() {
  const [data,        setData]        = useState<Cell3G[]>([])
  const [loading,     setLoading]     = useState(false)
  const [search,      setSearch]      = useState('')
  const [mien,        setMien]        = useState<string | undefined>()
  const [tinh,        setTinh]        = useState<string | undefined>()
  const [vendor,      setVendor]      = useState<string | undefined>()
  const [sites,       setSites]       = useState<Site[]>([])
  const [antennaList, setAntennaList] = useState<AntennaItem[]>([])
  const [modalOpen,   setModalOpen]   = useState(false)
  const [editing,     setEditing]     = useState<Cell3G | null>(null)
  const [dryRunOpen,  setDryRunOpen]  = useState(false)
  const [form] = Form.useForm()

  const tinhOptions   = [...new Set(data.map((c) => c.tinh).filter(Boolean))].sort() as string[]
  const vendorOptions = [...new Set(data.map((c) => c.vendor).filter(Boolean))].sort() as string[]

  const load = async () => {
    setLoading(true)
    try {
      setData(await cells3gApi.list({
        search: search || undefined, mien: mien || undefined,
        tinh: tinh || undefined, vendor: vendor || undefined, limit: 1000,
      }))
    } finally { setLoading(false) }
  }

  useEffect(() => {
    load()
    getSites({ limit: 2000 }).then(setSites)
    getAntennaList().then(setAntennaList)
  }, [search, mien, tinh, vendor])

  const handleSiteSelect = (siteId: number) => {
    const site = sites.find((s) => s.id === siteId)
    if (site) form.setFieldValue('site_name', site.site_name)
  }

  const handleAntennaSelect = (antennaName: string) => {
    const ant = antennaList.find((a) => a.name === antennaName)
    if (!ant) return
    // Auto-fill antenna-related fields
    form.setFieldsValue({ loai_anten: ant.name })
  }

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (r: Cell3G) => { setEditing(r); form.setFieldsValue(r); setModalOpen(true) }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) {
        await cells3gApi.update(editing.id, values)
        message.success('Cap nhat thanh cong')
      } else {
        await cells3gApi.create(values)
        message.success('Tao cell thanh cong')
      }
      setModalOpen(false); load()
    } catch (e: any) { message.error(e.response?.data?.detail || 'Loi') }
  }

  const handleDelete = async (id: number) => {
    await cells3gApi.remove(id); message.success('Da xoa'); load()
  }

  const columns: ColumnsType<Cell3G> = [
    {
      title: 'Hanh dong', key: 'action', fixed: 'left', width: 80,
      render: (_: unknown, r: Cell3G) => (
        <Space>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xoa cell nay?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    { title: 'Mien',      dataIndex: 'mien',      fixed: 'left', width: 70  },
    { title: 'Tinh',      dataIndex: 'tinh',      fixed: 'left', width: 160 },
    { title: 'Phuong xa', dataIndex: 'phuong_xa',               width: 160 },
    { title: 'Site Name', dataIndex: 'site_name', fixed: 'left', width: 200,
      render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell Name', dataIndex: 'cell_name', fixed: 'left', width: 200,
      render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell VIP', dataIndex: 'cell_vip', width: 90,
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-' },
    { title: 'MORAN',         dataIndex: 'moran',         width: 120 },
    { title: 'Lat',           dataIndex: 'lat',           width: 110 },
    { title: 'Long',          dataIndex: 'long',          width: 110 },
    { title: 'Vung phu song', dataIndex: 'vung_phu_song', width: 120 },
    { title: 'Vendor',        dataIndex: 'vendor',        width: 100 },
    { title: 'Do cao anten',  dataIndex: 'do_cao_anten',  width: 120 },
    { title: 'Azimuth',       dataIndex: 'azimuth',       width: 90  },
    { title: 'M-tilt',        dataIndex: 'm_tilt',        width: 80  },
    { title: 'E-Tilt',        dataIndex: 'e_tilt',        width: 80  },
    { title: 'Total Tilt',    dataIndex: 'total_tilt',    width: 100 },
    { title: 'Loai Anten',    dataIndex: 'loai_anten',    width: 200 },
    { title: 'Chung anten',   dataIndex: 'chung_anten',   width: 120 },
    { title: 'Baseband',      dataIndex: 'baseband',      width: 120 },
    { title: 'RF',            dataIndex: 'rf',            width: 100 },
    { title: 'Cell ID',       dataIndex: 'cell_id',       width: 100 },
    { title: 'ARFCN',         dataIndex: 'arfcn',         width: 90  },
    { title: 'PSC',           dataIndex: 'psc',           width: 80  },
    { title: 'MIMO', dataIndex: 'mimo', width: 80,
      render: (v: string) => v ? <Tag color="blue">{v}</Tag> : '-' },
  ]
  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Cell 3G</Typography.Title>
        <Space>
          <Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>
            Import Excel
          </Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>Them moi</Button>
        </Space>
      </Row>

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} placeholder="Tim cell / site name..."
                 value={search} onChange={(e) => setSearch(e.target.value)} allowClear />
        </Col>
        <Col>
          <Select placeholder="Mien" allowClear style={{ width: 90 }}
                  value={mien} onChange={setMien}>
            {['MB','MT','MN'].map((m) => <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="180px">
          <Select placeholder="Tinh" allowClear showSearch style={{ width: '100%' }}
                  value={tinh} onChange={setTinh}
                  filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
            {tinhOptions.map((t) => <Select.Option key={t} value={t}>{t}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="160px">
          <Select placeholder="Vendor" allowClear style={{ width: '100%' }}
                  value={vendor} onChange={setVendor}>
            {vendorOptions.map((v) => <Select.Option key={v} value={v}>{v}</Select.Option>)}
          </Select>
        </Col>
        <Col>
          <Button onClick={() => { setSearch(''); setMien(undefined); setTinh(undefined); setVendor(undefined) }}>
            Xoa loc
          </Button>
        </Col>
      </Row>

      <Table columns={columns} dataSource={data} rowKey="id" loading={loading} size="small"
             scroll={{ x: scrollX, y: 600 }} bordered
             pagination={{ pageSize: 50, showTotal: (t) => `${t} cells`, showSizeChanger: true }} />

      {/* ── Add/Edit Modal ── */}
      <Modal title={editing ? 'Chinh sua Cell 3G' : 'Them Cell 3G moi'}
             open={modalOpen} onOk={handleSave} onCancel={() => setModalOpen(false)}
             width={800} okText="Luu" destroyOnClose>
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={12}>
              <Form.Item name="site_id" label="Site" rules={[{ required: true }]}>
                <Select showSearch optionFilterProp="children" allowClear
                        placeholder="Chon site..." onChange={handleSiteSelect}
                        filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                  {sites.map((s) => <Select.Option key={s.id} value={s.id}>{s.site_name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="site_name" label="Site Name (tu dong dien)">
                <Input readOnly style={{ background: '#f5f5f5' }} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="cell_name" label="Cell Name" rules={[{ required: true }]}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="cell_vip" label="Cell VIP">
                <Select allowClear>
                  <Select.Option value="VIP">VIP</Select.Option>
                  <Select.Option value="VVIP">VVIP</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="moran" label="MORAN">
                <Select allowClear>
                  <Select.Option value="VNPT HOST">VNPT HOST</Select.Option>
                  <Select.Option value="MBF HOST">MBF HOST</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="lat" label="Lat">
                <InputNumber style={{ width: '100%' }} precision={5} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="long" label="Long">
                <InputNumber style={{ width: '100%' }} precision={5} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="vung_phu_song" label="Vung phu song">
                <Select allowClear>
                  <Select.Option value="Indoor">Indoor</Select.Option>
                  <Select.Option value="Outdoor">Outdoor</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="vendor" label="Vendor">
                <Select allowClear>
                  {['Ericsson','Nokia','Huawei','ZTE','Samsung'].map((v) =>
                    <Select.Option key={v} value={v}>{v}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="do_cao_anten" label="Do cao anten (m)">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="azimuth" label="Azimuth">
                <InputNumber style={{ width: '100%' }} min={0} max={359} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="m_tilt" label="M-tilt">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="e_tilt" label="E-Tilt">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="total_tilt" label="Total Tilt">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={24}>
              <Form.Item name="loai_anten" label="Loai Anten">
                <Select showSearch allowClear placeholder="Chon loai anten..."
                        onChange={handleAntennaSelect}
                        filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                  {antennaList.map((a) =>
                    <Select.Option key={a.id} value={a.name}>{a.name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="chung_anten" label="Chung anten"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="baseband" label="Baseband"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="rf" label="RF"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="cell_id" label="Cell ID"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="arfcn" label="ARFCN"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="psc" label="PSC"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="mimo" label="MIMO">
                <Select allowClear>
                  {['2x2','4x4','8x8'].map((m) => <Select.Option key={m} value={m}>{m}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
          </Row>
        </Form>
      </Modal>

      <DryRunModal
        open={dryRunOpen}
        onClose={() => setDryRunOpen(false)}
        title="Import Cell 3G tu Excel"
        dryRunFn={cells3gApi.dryRunExcel}
        importFn={cells3gApi.importExcel}
        onSuccess={load}
      />
    </div>
  )
}
TSEOF

# ─── Cells4GPage ─────────────────────────────────────────────────────────────
cat > frontend/src/pages/cells/Cells4GPage.tsx << 'TSEOF'
import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, message, Row, Col,
  Modal, Form, InputNumber,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, SearchOutlined, UploadOutlined,
  EditOutlined, DeleteOutlined,
} from '@ant-design/icons'
import { cells4gApi } from '@/api/cells'
import type { Cell4G, Site, AntennaItem } from '@/types'
import { getSites } from '@/api/sites'
import { getAntennaList } from '@/api/report'
import DryRunModal from '@/components/shared/DryRunModal'

export default function Cells4GPage() {
  const [data,        setData]        = useState<Cell4G[]>([])
  const [loading,     setLoading]     = useState(false)
  const [search,      setSearch]      = useState('')
  const [mien,        setMien]        = useState<string | undefined>()
  const [tinh,        setTinh]        = useState<string | undefined>()
  const [vendor,      setVendor]      = useState<string | undefined>()
  const [sites,       setSites]       = useState<Site[]>([])
  const [antennaList, setAntennaList] = useState<AntennaItem[]>([])
  const [modalOpen,   setModalOpen]   = useState(false)
  const [editing,     setEditing]     = useState<Cell4G | null>(null)
  const [dryRunOpen,  setDryRunOpen]  = useState(false)
  const [form] = Form.useForm()

  const tinhOptions   = [...new Set(data.map((c) => c.tinh).filter(Boolean))].sort() as string[]
  const vendorOptions = [...new Set(data.map((c) => c.vendor).filter(Boolean))].sort() as string[]

  const load = async () => {
    setLoading(true)
    try {
      setData(await cells4gApi.list({
        search: search || undefined, mien: mien || undefined,
        tinh: tinh || undefined, vendor: vendor || undefined, limit: 1000,
      }))
    } finally { setLoading(false) }
  }

  useEffect(() => {
    load()
    getSites({ limit: 2000 }).then(setSites)
    getAntennaList().then(setAntennaList)
  }, [search, mien, tinh, vendor])

  const handleSiteSelect = (siteId: number) => {
    const site = sites.find((s) => s.id === siteId)
    if (site) form.setFieldValue('site_name', site.site_name)
  }

  const handleAntennaSelect = (antennaName: string) => {
    const ant = antennaList.find((a) => a.name === antennaName)
    if (!ant) return
    form.setFieldsValue({ loai_anten: ant.name })
  }

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (r: Cell4G) => { setEditing(r); form.setFieldsValue(r); setModalOpen(true) }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) {
        await cells4gApi.update(editing.id, values)
        message.success('Cap nhat thanh cong')
      } else {
        await cells4gApi.create(values)
        message.success('Tao cell thanh cong')
      }
      setModalOpen(false); load()
    } catch (e: any) { message.error(e.response?.data?.detail || 'Loi') }
  }

  const handleDelete = async (id: number) => {
    await cells4gApi.remove(id); message.success('Da xoa'); load()
  }

  const columns: ColumnsType<Cell4G> = [
    {
      title: 'Hanh dong', key: 'action', fixed: 'left', width: 80,
      render: (_: unknown, r: Cell4G) => (
        <Space>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xoa cell nay?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    { title: 'Mien',      dataIndex: 'mien',      fixed: 'left', width: 70  },
    { title: 'Tinh',      dataIndex: 'tinh',      fixed: 'left', width: 160 },
    { title: 'Phuong xa', dataIndex: 'phuong_xa',               width: 160 },
    { title: 'Site Name', dataIndex: 'site_name', fixed: 'left', width: 200,
      render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell Name', dataIndex: 'cell_name', fixed: 'left', width: 200,
      render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell VIP', dataIndex: 'cell_vip', width: 90,
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-' },
    { title: 'MORAN',            dataIndex: 'moran',            width: 120 },
    { title: 'Lat',              dataIndex: 'lat',              width: 110 },
    { title: 'Long',             dataIndex: 'long',             width: 110 },
    { title: 'Vung phu song',    dataIndex: 'vung_phu_song',    width: 120 },
    { title: 'Vendor',           dataIndex: 'vendor',           width: 100 },
    { title: 'Do cao anten',     dataIndex: 'do_cao_anten',     width: 120 },
    { title: 'Azimuth',          dataIndex: 'azimuth',          width: 90  },
    { title: 'M-tilt',           dataIndex: 'm_tilt',           width: 80  },
    { title: 'E-Tilt',           dataIndex: 'e_tilt',           width: 80  },
    { title: 'Total Tilt',       dataIndex: 'total_tilt',       width: 100 },
    { title: 'Loai Anten',       dataIndex: 'loai_anten',       width: 200 },
    { title: 'Chung anten',      dataIndex: 'chung_anten',      width: 120 },
    { title: 'Baseband',         dataIndex: 'baseband',         width: 120 },
    { title: 'RF',               dataIndex: 'rf',               width: 100 },
    { title: 'Cell ID',          dataIndex: 'cell_id',          width: 100 },
    { title: 'EARFCN',           dataIndex: 'earfcn',           width: 90  },
    { title: 'PCI',              dataIndex: 'pci',              width: 80  },
    { title: 'Root Sequence ID', dataIndex: 'root_sequence_id', width: 150 },
    { title: 'MIMO', dataIndex: 'mimo', width: 80,
      render: (v: string) => v ? <Tag color="blue">{v}</Tag> : '-' },
  ]
  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Cell 4G</Typography.Title>
        <Space>
          <Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>
            Import Excel
          </Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>Them moi</Button>
        </Space>
      </Row>

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} placeholder="Tim cell / site name..."
                 value={search} onChange={(e) => setSearch(e.target.value)} allowClear />
        </Col>
        <Col>
          <Select placeholder="Mien" allowClear style={{ width: 90 }}
                  value={mien} onChange={setMien}>
            {['MB','MT','MN'].map((m) => <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="180px">
          <Select placeholder="Tinh" allowClear showSearch style={{ width: '100%' }}
                  value={tinh} onChange={setTinh}
                  filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
            {tinhOptions.map((t) => <Select.Option key={t} value={t}>{t}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="160px">
          <Select placeholder="Vendor" allowClear style={{ width: '100%' }}
                  value={vendor} onChange={setVendor}>
            {vendorOptions.map((v) => <Select.Option key={v} value={v}>{v}</Select.Option>)}
          </Select>
        </Col>
        <Col>
          <Button onClick={() => { setSearch(''); setMien(undefined); setTinh(undefined); setVendor(undefined) }}>
            Xoa loc
          </Button>
        </Col>
      </Row>

      <Table columns={columns} dataSource={data} rowKey="id" loading={loading} size="small"
             scroll={{ x: scrollX, y: 600 }} bordered
             pagination={{ pageSize: 50, showTotal: (t) => `${t} cells`, showSizeChanger: true }} />

      <Modal title={editing ? 'Chinh sua Cell 4G' : 'Them Cell 4G moi'}
             open={modalOpen} onOk={handleSave} onCancel={() => setModalOpen(false)}
             width={800} okText="Luu" destroyOnClose>
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={12}>
              <Form.Item name="site_id" label="Site" rules={[{ required: true }]}>
                <Select showSearch optionFilterProp="children" allowClear
                        placeholder="Chon site..." onChange={handleSiteSelect}
                        filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                  {sites.map((s) => <Select.Option key={s.id} value={s.id}>{s.site_name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="site_name" label="Site Name (tu dong dien)">
                <Input readOnly style={{ background: '#f5f5f5' }} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="cell_name" label="Cell Name" rules={[{ required: true }]}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="cell_vip" label="Cell VIP">
                <Select allowClear>
                  <Select.Option value="VIP">VIP</Select.Option>
                  <Select.Option value="VVIP">VVIP</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="moran" label="MORAN">
                <Select allowClear>
                  <Select.Option value="VNPT HOST">VNPT HOST</Select.Option>
                  <Select.Option value="MBF HOST">MBF HOST</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}><Form.Item name="lat" label="Lat"><InputNumber style={{ width: '100%' }} precision={5} /></Form.Item></Col>
            <Col span={8}><Form.Item name="long" label="Long"><InputNumber style={{ width: '100%' }} precision={5} /></Form.Item></Col>
            <Col span={8}>
              <Form.Item name="vung_phu_song" label="Vung phu song">
                <Select allowClear>
                  <Select.Option value="Indoor">Indoor</Select.Option>
                  <Select.Option value="Outdoor">Outdoor</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="vendor" label="Vendor">
                <Select allowClear>
                  {['Ericsson','Nokia','Huawei','ZTE','Samsung'].map((v) =>
                    <Select.Option key={v} value={v}>{v}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}><Form.Item name="do_cao_anten" label="Do cao anten (m)"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={8}><Form.Item name="azimuth" label="Azimuth"><InputNumber style={{ width: '100%' }} min={0} max={359} /></Form.Item></Col>
            <Col span={8}><Form.Item name="m_tilt" label="M-tilt"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={8}><Form.Item name="e_tilt" label="E-Tilt"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={8}><Form.Item name="total_tilt" label="Total Tilt"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={24}>
              <Form.Item name="loai_anten" label="Loai Anten">
                <Select showSearch allowClear placeholder="Chon loai anten..."
                        onChange={handleAntennaSelect}
                        filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                  {antennaList.map((a) => <Select.Option key={a.id} value={a.name}>{a.name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={12}><Form.Item name="chung_anten" label="Chung anten"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="baseband" label="Baseband"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="rf" label="RF"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="cell_id" label="Cell ID"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="earfcn" label="EARFCN"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="pci" label="PCI"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="root_sequence_id" label="Root Sequence ID"><Input /></Form.Item></Col>
            <Col span={8}>
              <Form.Item name="mimo" label="MIMO">
                <Select allowClear>
                  {['2x2','4x4','8x8'].map((m) => <Select.Option key={m} value={m}>{m}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
          </Row>
        </Form>
      </Modal>

      <DryRunModal
        open={dryRunOpen}
        onClose={() => setDryRunOpen(false)}
        title="Import Cell 4G tu Excel"
        dryRunFn={cells4gApi.dryRunExcel}
        importFn={cells4gApi.importExcel}
        onSuccess={load}
      />
    </div>
  )
}
TSEOF

# ─── Cells5GPage ─────────────────────────────────────────────────────────────
cat > frontend/src/pages/cells/Cells5GPage.tsx << 'TSEOF'
import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, message, Row, Col,
  Modal, Form, InputNumber,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, SearchOutlined, UploadOutlined,
  EditOutlined, DeleteOutlined,
} from '@ant-design/icons'
import { cells5gApi } from '@/api/cells'
import type { Cell5G, Site, AntennaItem } from '@/types'
import { getSites } from '@/api/sites'
import { getAntennaList } from '@/api/report'
import DryRunModal from '@/components/shared/DryRunModal'

export default function Cells5GPage() {
  const [data,        setData]        = useState<Cell5G[]>([])
  const [loading,     setLoading]     = useState(false)
  const [search,      setSearch]      = useState('')
  const [mien,        setMien]        = useState<string | undefined>()
  const [tinh,        setTinh]        = useState<string | undefined>()
  const [vendor,      setVendor]      = useState<string | undefined>()
  const [sites,       setSites]       = useState<Site[]>([])
  const [antennaList, setAntennaList] = useState<AntennaItem[]>([])
  const [modalOpen,   setModalOpen]   = useState(false)
  const [editing,     setEditing]     = useState<Cell5G | null>(null)
  const [dryRunOpen,  setDryRunOpen]  = useState(false)
  const [form] = Form.useForm()

  const tinhOptions   = [...new Set(data.map((c) => c.tinh).filter(Boolean))].sort() as string[]
  const vendorOptions = [...new Set(data.map((c) => c.vendor).filter(Boolean))].sort() as string[]

  const load = async () => {
    setLoading(true)
    try {
      setData(await cells5gApi.list({
        search: search || undefined, mien: mien || undefined,
        tinh: tinh || undefined, vendor: vendor || undefined, limit: 1000,
      }))
    } finally { setLoading(false) }
  }

  useEffect(() => {
    load()
    getSites({ limit: 2000 }).then(setSites)
    getAntennaList().then(setAntennaList)
  }, [search, mien, tinh, vendor])

  const handleSiteSelect = (siteId: number) => {
    const site = sites.find((s) => s.id === siteId)
    if (site) form.setFieldValue('site_name', site.site_name)
  }

  const handleAntennaSelect = (antennaName: string) => {
    const ant = antennaList.find((a) => a.name === antennaName)
    if (!ant) return
    form.setFieldsValue({ loai_anten: ant.name })
  }

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (r: Cell5G) => { setEditing(r); form.setFieldsValue(r); setModalOpen(true) }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) {
        await cells5gApi.update(editing.id, values)
        message.success('Cap nhat thanh cong')
      } else {
        await cells5gApi.create(values)
        message.success('Tao cell thanh cong')
      }
      setModalOpen(false); load()
    } catch (e: any) { message.error(e.response?.data?.detail || 'Loi') }
  }

  const handleDelete = async (id: number) => {
    await cells5gApi.remove(id); message.success('Da xoa'); load()
  }

  const columns: ColumnsType<Cell5G> = [
    {
      title: 'Hanh dong', key: 'action', fixed: 'left', width: 80,
      render: (_: unknown, r: Cell5G) => (
        <Space>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xoa cell nay?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    { title: 'Mien',      dataIndex: 'mien',      fixed: 'left', width: 70  },
    { title: 'Tinh',      dataIndex: 'tinh',      fixed: 'left', width: 160 },
    { title: 'Phuong xa', dataIndex: 'phuong_xa',               width: 160 },
    { title: 'Site Name', dataIndex: 'site_name', fixed: 'left', width: 200,
      render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell Name', dataIndex: 'cell_name', fixed: 'left', width: 200,
      render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell VIP', dataIndex: 'cell_vip', width: 90,
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-' },
    { title: 'MORAN',            dataIndex: 'moran',            width: 120 },
    { title: 'Lat',              dataIndex: 'lat',              width: 110 },
    { title: 'Long',             dataIndex: 'long',             width: 110 },
    { title: 'Vung phu song',    dataIndex: 'vung_phu_song',    width: 120 },
    { title: 'Vendor',           dataIndex: 'vendor',           width: 100 },
    { title: 'Do cao anten',     dataIndex: 'do_cao_anten',     width: 120 },
    { title: 'Azimuth',          dataIndex: 'azimuth',          width: 90  },
    { title: 'M-tilt',           dataIndex: 'm_tilt',           width: 80  },
    { title: 'E-Tilt',           dataIndex: 'e_tilt',           width: 80  },
    { title: 'Total Tilt',       dataIndex: 'total_tilt',       width: 100 },
    { title: 'Loai Anten',       dataIndex: 'loai_anten',       width: 200 },
    { title: 'Baseband',         dataIndex: 'baseband',         width: 120 },
    { title: 'RF',               dataIndex: 'rf',               width: 100 },
    { title: 'Cell ID',          dataIndex: 'cell_id',          width: 100 },
    { title: 'NR-ARFCN',         dataIndex: 'nr_arfcn',         width: 100 },
    { title: 'PCI',              dataIndex: 'pci',              width: 80  },
    { title: 'Root Sequence ID', dataIndex: 'root_sequence_id', width: 150 },
    { title: 'MIMO', dataIndex: 'mimo', width: 80,
      render: (v: string) => v ? <Tag color="blue">{v}</Tag> : '-' },
  ]
  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Cell 5G</Typography.Title>
        <Space>
          <Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>
            Import Excel
          </Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>Them moi</Button>
        </Space>
      </Row>

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} placeholder="Tim cell / site name..."
                 value={search} onChange={(e) => setSearch(e.target.value)} allowClear />
        </Col>
        <Col>
          <Select placeholder="Mien" allowClear style={{ width: 90 }}
                  value={mien} onChange={setMien}>
            {['MB','MT','MN'].map((m) => <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="180px">
          <Select placeholder="Tinh" allowClear showSearch style={{ width: '100%' }}
                  value={tinh} onChange={setTinh}
                  filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
            {tinhOptions.map((t) => <Select.Option key={t} value={t}>{t}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="160px">
          <Select placeholder="Vendor" allowClear style={{ width: '100%' }}
                  value={vendor} onChange={setVendor}>
            {vendorOptions.map((v) => <Select.Option key={v} value={v}>{v}</Select.Option>)}
          </Select>
        </Col>
        <Col>
          <Button onClick={() => { setSearch(''); setMien(undefined); setTinh(undefined); setVendor(undefined) }}>
            Xoa loc
          </Button>
        </Col>
      </Row>

      <Table columns={columns} dataSource={data} rowKey="id" loading={loading} size="small"
             scroll={{ x: scrollX, y: 600 }} bordered
             pagination={{ pageSize: 50, showTotal: (t) => `${t} cells`, showSizeChanger: true }} />

      <Modal title={editing ? 'Chinh sua Cell 5G' : 'Them Cell 5G moi'}
             open={modalOpen} onOk={handleSave} onCancel={() => setModalOpen(false)}
             width={800} okText="Luu" destroyOnClose>
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={12}>
              <Form.Item name="site_id" label="Site" rules={[{ required: true }]}>
                <Select showSearch optionFilterProp="children" allowClear
                        placeholder="Chon site..." onChange={handleSiteSelect}
                        filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                  {sites.map((s) => <Select.Option key={s.id} value={s.id}>{s.site_name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="site_name" label="Site Name (tu dong dien)">
                <Input readOnly style={{ background: '#f5f5f5' }} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="cell_name" label="Cell Name" rules={[{ required: true }]}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="cell_vip" label="Cell VIP">
                <Select allowClear>
                  <Select.Option value="VIP">VIP</Select.Option>
                  <Select.Option value="VVIP">VVIP</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="moran" label="MORAN">
                <Select allowClear>
                  <Select.Option value="VNPT HOST">VNPT HOST</Select.Option>
                  <Select.Option value="MBF HOST">MBF HOST</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}><Form.Item name="lat" label="Lat"><InputNumber style={{ width: '100%' }} precision={5} /></Form.Item></Col>
            <Col span={8}><Form.Item name="long" label="Long"><InputNumber style={{ width: '100%' }} precision={5} /></Form.Item></Col>
            <Col span={8}>
              <Form.Item name="vung_phu_song" label="Vung phu song">
                <Select allowClear>
                  <Select.Option value="Indoor">Indoor</Select.Option>
                  <Select.Option value="Outdoor">Outdoor</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="vendor" label="Vendor">
                <Select allowClear>
                  {['Ericsson','Nokia','Huawei','ZTE','Samsung'].map((v) =>
                    <Select.Option key={v} value={v}>{v}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}><Form.Item name="do_cao_anten" label="Do cao anten (m)"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={8}><Form.Item name="azimuth" label="Azimuth"><InputNumber style={{ width: '100%' }} min={0} max={359} /></Form.Item></Col>
            <Col span={8}><Form.Item name="m_tilt" label="M-tilt"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={8}><Form.Item name="e_tilt" label="E-Tilt"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={8}><Form.Item name="total_tilt" label="Total Tilt"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={24}>
              <Form.Item name="loai_anten" label="Loai Anten">
                <Select showSearch allowClear placeholder="Chon loai anten..."
                        onChange={handleAntennaSelect}
                        filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                  {antennaList.map((a) => <Select.Option key={a.id} value={a.name}>{a.name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}><Form.Item name="baseband" label="Baseband"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="rf" label="RF"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="cell_id" label="Cell ID"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="nr_arfcn" label="NR-ARFCN"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="pci" label="PCI"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="root_sequence_id" label="Root Sequence ID"><Input /></Form.Item></Col>
            <Col span={8}>
              <Form.Item name="mimo" label="MIMO">
                <Select allowClear>
                  {['2x2','4x4','8x8'].map((m) => <Select.Option key={m} value={m}>{m}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
          </Row>
        </Form>
      </Modal>

      <DryRunModal
        open={dryRunOpen}
        onClose={() => setDryRunOpen(false)}
        title="Import Cell 5G tu Excel"
        dryRunFn={cells5gApi.dryRunExcel}
        importFn={cells5gApi.importExcel}
        onSuccess={load}
      />
    </div>
  )
}
TSEOF

# ── 2-H  AntennaPage ─────────────────────────────────────────────────────────
mkdir -p frontend/src/pages/antenna
cat > frontend/src/pages/antenna/AntennaPage.tsx << 'TSEOF'
import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Popconfirm,
  message, Row, Col, Modal, Form, InputNumber,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, SearchOutlined, UploadOutlined,
  EditOutlined, DeleteOutlined,
} from '@ant-design/icons'
import {
  getAntennas, createAntenna, updateAntenna,
  deleteAntenna, dryRunAntennaExcel, importAntennaExcel,
} from '@/api/antenna'
import type { AntennaFull } from '@/types'
import DryRunModal from '@/components/shared/DryRunModal'

export default function AntennaPage() {
  const [data,       setData]       = useState<AntennaFull[]>([])
  const [loading,    setLoading]    = useState(false)
  const [search,     setSearch]     = useState('')
  const [modalOpen,  setModalOpen]  = useState(false)
  const [editing,    setEditing]    = useState<AntennaFull | null>(null)
  const [dryRunOpen, setDryRunOpen] = useState(false)
  const [detailOpen, setDetailOpen] = useState(false)
  const [selected,   setSelected]   = useState<AntennaFull | null>(null)
  const [form] = Form.useForm()

  const load = async () => {
    setLoading(true)
    try {
      setData(await getAntennas({ search: search || undefined, limit: 2000 }))
    } finally { setLoading(false) }
  }

  useEffect(() => { load() }, [search])

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (r: AntennaFull) => {
    setEditing(r); form.setFieldsValue(r); setModalOpen(true)
  }
  const openDetail = (r: AntennaFull) => { setSelected(r); setDetailOpen(true) }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) {
        await updateAntenna(editing.id, values)
        message.success('Cap nhat thanh cong')
      } else {
        await createAntenna(values)
        message.success('Tao antenna thanh cong')
      }
      setModalOpen(false); load()
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Loi')
    }
  }

  const handleDelete = async (id: number) => {
    await deleteAntenna(id); message.success('Da xoa'); load()
  }

  const columns: ColumnsType<AntennaFull> = [
    {
      title: 'Hanh dong', key: 'action', fixed: 'left', width: 100,
      render: (_: unknown, r: AntennaFull) => (
        <Space>
          <Button size="small" onClick={() => openDetail(r)}>Chi tiet</Button>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xoa antenna nay?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    { title: 'Name',           dataIndex: 'name',           fixed: 'left', width: 280,
      render: (v: string) => <strong>{v}</strong> },
    { title: 'Band',           dataIndex: 'band',           width: 150 },
    { title: 'No of Ports',    dataIndex: 'no_of_ports',    width: 110 },
    { title: 'No of Beam',     dataIndex: 'no_of_beam',     width: 110 },
    { title: 'Horizontal BW',  dataIndex: 'horizontal_bw',  width: 120 },
    { title: 'Vertical BW',    dataIndex: 'vertical_bw',    width: 110 },
    { title: 'Gain',           dataIndex: 'gain',           width: 80  },
    { title: 'Etilt',          dataIndex: 'etilt',          width: 90  },
    { title: 'H (mm)',         dataIndex: 'h',              width: 90  },
    { title: 'W (mm)',         dataIndex: 'w',              width: 90  },
    { title: 'D (mm)',         dataIndex: 'd',              width: 90  },
    { title: 'Weight',         dataIndex: 'weight',         width: 90  },
    { title: 'Connector type', dataIndex: 'connector_type', width: 160 },
    { title: 'Ghi chu',        dataIndex: 'ghi_chu',        width: 200 },
  ]
  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Quan ly Antenna</Typography.Title>
        <Space>
          <Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>
            Import Excel
          </Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
            Them moi
          </Button>
        </Space>
      </Row>

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="320px">
          <Input prefix={<SearchOutlined />} placeholder="Tim ten antenna..."
                 value={search} onChange={(e) => setSearch(e.target.value)} allowClear />
        </Col>
        <Col>
          <Button onClick={() => setSearch('')}>Xoa loc</Button>
        </Col>
        <Col>
          <Button onClick={load} loading={loading}>Lam moi</Button>
        </Col>
      </Row>

      <Table columns={columns} dataSource={data} rowKey="id" loading={loading} size="small"
             scroll={{ x: scrollX, y: 600 }} bordered
             pagination={{ pageSize: 50, showTotal: (t) => `${t} antennas`,
                           showSizeChanger: true }} />

      {/* ── Detail modal ── */}
      <Modal title={selected?.name} open={detailOpen}
             onCancel={() => setDetailOpen(false)} footer={null} width={600}>
        {selected && (
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            {([
              ['Band',           selected.band],
              ['No of Ports',    selected.no_of_ports],
              ['No of Beam',     selected.no_of_beam],
              ['Horizontal BW',  selected.horizontal_bw],
              ['Vertical BW',    selected.vertical_bw],
              ['Gain',           selected.gain],
              ['Etilt',          selected.etilt],
              ['H (mm)',         selected.h],
              ['W (mm)',         selected.w],
              ['D (mm)',         selected.d],
              ['Weight',         selected.weight],
              ['Connector type', selected.connector_type],
              ['Ghi chu',        selected.ghi_chu],
            ] as [string, unknown][]).map(([label, val]) => (
              <tr key={label} style={{ borderBottom: '1px solid #f0f0f0' }}>
                <td style={{ padding: '6px 12px', fontWeight: 600,
                             width: 160, color: '#666' }}>{label}</td>
                <td style={{ padding: '6px 12px' }}>{String(val ?? '-')}</td>
              </tr>
            ))}
          </table>
        )}
      </Modal>

      {/* ── Create / Edit modal ── */}
      <Modal title={editing ? 'Chinh sua Antenna' : 'Them Antenna moi'}
             open={modalOpen} onOk={handleSave} onCancel={() => setModalOpen(false)}
             width={700} okText="Luu" destroyOnClose>
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={24}>
              <Form.Item name="name" label="Name (dinh danh duy nhat)"
                         rules={[{ required: true, message: 'Vui long nhap ten antenna' }]}>
                <Input disabled={Boolean(editing)} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="band" label="Band">
                <Input placeholder="vd: 900-1800-2100" />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="no_of_ports" label="No of Ports">
                <InputNumber style={{ width: '100%' }} min={1} />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="no_of_beam" label="No of Beam">
                <InputNumber style={{ width: '100%' }} min={1} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="horizontal_bw" label="Horizontal BW">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="vertical_bw" label="Vertical BW">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="gain" label="Gain (dBi)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="etilt" label="Etilt range">
                <Input placeholder="vd: 0-10" />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="h" label="H – Height (mm)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="w" label="W – Width (mm)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="d" label="D – Depth (mm)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="weight" label="Weight (kg)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="connector_type" label="Connector type">
                <Input />
              </Form.Item>
            </Col>
            <Col span={24}>
              <Form.Item name="ghi_chu" label="Ghi chu">
                <Input.TextArea rows={2} />
              </Form.Item>
            </Col>
          </Row>
        </Form>
      </Modal>

      <DryRunModal
        open={dryRunOpen}
        onClose={() => setDryRunOpen(false)}
        title="Import Antenna tu Excel"
        dryRunFn={dryRunAntennaExcel}
        importFn={importAntennaExcel}
        onSuccess={load}
      />
    </div>
  )
}
TSEOF

# ── 2-I  MainLayout.tsx – add Antenna menu item ──────────────────────────────
cat > frontend/src/components/layout/MainLayout.tsx << 'TSEOF'
import React, { useState } from 'react'
import { Layout, Menu, Avatar, Dropdown, Space, Typography } from 'antd'
import {
  DashboardOutlined, DatabaseOutlined, TableOutlined,
  BarChartOutlined, UserOutlined, AuditOutlined,
  LogoutOutlined, MenuFoldOutlined, MenuUnfoldOutlined,
  WifiOutlined,
} from '@ant-design/icons'
import { Outlet, useNavigate, useLocation } from 'react-router-dom'
import { useAuthStore } from '@/store/auth'

const { Sider, Header, Content } = Layout

export default function MainLayout() {
  const [collapsed, setCollapsed] = useState(false)
  const navigate   = useNavigate()
  const location   = useLocation()
  const { user, logout } = useAuthStore()

  const menuItems = [
    { key: '/',        icon: <DashboardOutlined />, label: 'Dashboard' },
    { key: '/report',  icon: <BarChartOutlined />,  label: 'Bao cao tong hop' },
    { key: '/sites',   icon: <DatabaseOutlined />,  label: 'Quan ly Site' },
    {
      key: 'cells',
      icon: <TableOutlined />,
      label: 'Quan ly Cell',
      children: [
        { key: '/cells/3g', label: 'Cell 3G' },
        { key: '/cells/4g', label: 'Cell 4G' },
        { key: '/cells/5g', label: 'Cell 5G' },
      ],
    },
    { key: '/antenna', icon: <WifiOutlined />, label: 'Quan ly Antenna' },
    ...(user?.role === 'admin'
      ? [{
          key: 'admin',
          icon: <AuditOutlined />,
          label: 'Quan tri',
          children: [
            { key: '/admin/users', label: 'Nguoi dung' },
            { key: '/admin/audit', label: 'Audit Log' },
          ],
        }]
      : []),
  ]

  const userMenu = {
    items: [{
      key: 'logout',
      icon: <LogoutOutlined />,
      label: 'Dang xuat',
      onClick: () => { logout(); navigate('/login') },
    }],
  }

  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Sider collapsible collapsed={collapsed} onCollapse={setCollapsed}
             theme="dark" width={220}>
        <div style={{
          height: 48, display: 'flex', alignItems: 'center',
          justifyContent: 'center', color: '#fff',
          fontWeight: 700, fontSize: collapsed ? 14 : 18,
          borderBottom: '1px solid #333',
        }}>
          {collapsed ? 'SL' : 'SiteLink'}
        </div>
        <Menu
          theme="dark"
          mode="inline"
          selectedKeys={[location.pathname]}
          defaultOpenKeys={['cells', 'admin']}
          items={menuItems}
          onClick={({ key }) => {
            if (!['cells', 'admin'].includes(key)) navigate(key)
          }}
        />
      </Sider>

      <Layout>
        <Header style={{
          background: '#fff', padding: '0 24px',
          display: 'flex', alignItems: 'center',
          justifyContent: 'space-between',
          borderBottom: '1px solid #f0f0f0',
        }}>
          <Space>
            {collapsed
              ? <MenuUnfoldOutlined onClick={() => setCollapsed(false)}
                                    style={{ fontSize: 18, cursor: 'pointer' }} />
              : <MenuFoldOutlined   onClick={() => setCollapsed(true)}
                                    style={{ fontSize: 18, cursor: 'pointer' }} />}
            <Typography.Text strong style={{ fontSize: 16 }}>
              He thong quan ly du lieu toi uu
            </Typography.Text>
          </Space>
          <Dropdown menu={userMenu}>
            <Space style={{ cursor: 'pointer' }}>
              <Avatar icon={<UserOutlined />} style={{ backgroundColor: '#1890ff' }} />
              <span>{user?.full_name || user?.username}</span>
            </Space>
          </Dropdown>
        </Header>

        <Content style={{
          margin: 16, padding: 16,
          background: '#fff', borderRadius: 8,
          minHeight: 'calc(100vh - 112px)',
          overflowY: 'auto',
        }}>
          <Outlet />
        </Content>
      </Layout>
    </Layout>
  )
}
TSEOF

# ── 2-J  App.tsx – add /antenna route ────────────────────────────────────────
cat > frontend/src/App.tsx << 'TSEOF'
import React, { useEffect } from 'react'
import { Routes, Route, Navigate } from 'react-router-dom'
import { Toaster } from 'react-hot-toast'
import { useAuthStore } from '@/store/auth'
import { getMe } from '@/api/auth'

import LoginPage    from '@/pages/auth/LoginPage'
import MainLayout   from '@/components/layout/MainLayout'
import DashboardPage from '@/pages/dashboard/DashboardPage'
import ReportPage   from '@/pages/dashboard/ReportPage'
import SitesPage    from '@/pages/sites/SitesPage'
import SiteFormPage from '@/pages/sites/SiteFormPage'
import Cells3GPage  from '@/pages/cells/Cells3GPage'
import Cells4GPage  from '@/pages/cells/Cells4GPage'
import Cells5GPage  from '@/pages/cells/Cells5GPage'
import AntennaPage  from '@/pages/antenna/AntennaPage'
import UsersPage    from '@/pages/admin/UsersPage'
import AuditPage    from '@/pages/admin/AuditPage'

function PrivateRoute({ children }: { children: React.ReactNode }) {
  const token = useAuthStore((s) => s.token)
  return token ? <>{children}</> : <Navigate to="/login" replace />
}

function AdminRoute({ children }: { children: React.ReactNode }) {
  const user = useAuthStore((s) => s.user)
  if (!user) return <Navigate to="/login" replace />
  if (user.role !== 'admin') return <Navigate to="/" replace />
  return <>{children}</>
}

export default function App() {
  const { token, setAuth, logout } = useAuthStore()

  useEffect(() => {
    if (token) {
      getMe().then((u) => setAuth(u, token)).catch(() => logout())
    }
  }, [])

  return (
    <>
      <Toaster position="top-right" />
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route
          path="/"
          element={
            <PrivateRoute>
              <MainLayout />
            </PrivateRoute>
          }
        >
          <Route index         element={<DashboardPage />} />
          <Route path="report"         element={<ReportPage />} />
          <Route path="sites"          element={<SitesPage />} />
          <Route path="sites/new"      element={<SiteFormPage />} />
          <Route path="sites/:id/edit" element={<SiteFormPage />} />
          <Route path="cells/3g"       element={<Cells3GPage />} />
          <Route path="cells/4g"       element={<Cells4GPage />} />
          <Route path="cells/5g"       element={<Cells5GPage />} />
          <Route path="antenna"        element={<AntennaPage />} />
          <Route path="admin/users"    element={<AdminRoute><UsersPage /></AdminRoute>} />
          <Route path="admin/audit"    element={<AdminRoute><AuditPage /></AdminRoute>} />
        </Route>
      </Routes>
    </>
  )
}
TSEOF

echo "✓ Frontend files written"

# ─────────────────────────────────────────────────────────────────────────────
# 3. REBUILD & RESTART
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo " Rebuilding Docker containers (this may take a few minutes)..."
echo "================================================================"
sudo docker compose down
sudo docker compose up -d --build

echo ""
echo "================================================================"
echo " All done!"
echo "  Frontend : http://localhost:8081"
echo "  API docs : http://localhost:8081/api/docs"
echo "  Login    : admin / admin"
echo ""
echo " New features:"
echo "  ✓ Dry-run import (Sites, Cells, Antennas)"
echo "  ✓ Fuzzy province/ward mapping"
echo "  ✓ Auto-create missing sites when importing cells"
echo "  ✓ Site delete restriction (blocked if cells exist)"
echo "  ✓ Anchor-based upsert (site_name / cell_name never overwritten)"
echo "  ✓ Antenna management module (CRUD + Excel import)"
echo "  ✓ Antenna auto-fill in cell forms"
echo "================================================================"