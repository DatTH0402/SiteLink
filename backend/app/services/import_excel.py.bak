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
