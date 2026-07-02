"""
import_excel.py
==============
Handles Excel → DB record conversion for Sites, Cell3G, Cell4G, Cell5G.

Validation rules:
  - Lat: 8.33 ≤ lat ≤ 23.39  (Vietnam bounding box)
  - Long: 102.14 ≤ long ≤ 109.47
  - Azimuth: 0 ≤ azimuth ≤ 359
"""

from __future__ import annotations

import io
import re
import unicodedata
from typing import Any, Dict, List, Optional, Tuple

import pandas as pd

# ── Vietnam bounding box ──────────────────────────────────────────────────────
VN_LAT_MIN, VN_LAT_MAX   =  8.33,  23.39
VN_LON_MIN, VN_LON_MAX   = 102.14, 109.47
AZI_MIN,    AZI_MAX       = 0,      359


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _strip_accents(text: str) -> str:
    _CHAR_MAP = str.maketrans({"Đ": "D", "đ": "d"})
    text = text.translate(_CHAR_MAP)
    nfkd = unicodedata.normalize("NFKD", text)
    return "".join(c for c in nfkd if not unicodedata.combining(c))


_PREFIX_RE = re.compile(
    r"^(tp\.?|thanh\s+pho|thi\s+tran|thi\s+xa|phuong|huyen|tinh|quan|xa)\s+",
    re.IGNORECASE,
)


def _normalize(text: str) -> str:
    t = _strip_accents(text).lower().strip()
    t = _PREFIX_RE.sub("", t)
    t = re.sub(r"[\s\-_\.]+", "", t)
    return t


# ─────────────────────────────────────────────────────────────────────────────
# Geo cache
# ─────────────────────────────────────────────────────────────────────────────

class GeoCache:
    def __init__(self, db) -> None:
        from app.models.dropdown import DropdownTinhXaPhuong
        rows = db.query(DropdownTinhXaPhuong).all()

        self.tinh_map:  Dict[str, str] = {}
        self.xa_map:    Dict[Tuple[str, str], str] = {}
        self.tinh_mien: Dict[str, str] = {}

        for r in rows:
            if r.ten_tinh:
                k_tinh = _normalize(r.ten_tinh)
                self.tinh_map[k_tinh]      = r.ten_tinh
                self.tinh_mien[r.ten_tinh] = r.mien or ""
            if r.ten_tinh and r.ten_phuong_xa:
                k_tinh = _normalize(r.ten_tinh)
                k_xa   = _normalize(r.ten_phuong_xa)
                self.xa_map[(k_tinh, k_xa)] = r.ten_phuong_xa

    def resolve_tinh(self, raw: Optional[str]) -> Optional[str]:
        if not raw:
            return None
        return self.tinh_map.get(_normalize(raw))

    def resolve_xa(self, tinh_official: str, raw_xa: Optional[str]) -> Optional[str]:
        if not raw_xa or not tinh_official:
            return None
        return self.xa_map.get((_normalize(tinh_official), _normalize(raw_xa)))

    def mien_for(self, tinh_official: str) -> str:
        return self.tinh_mien.get(tinh_official, "")


# ─────────────────────────────────────────────────────────────────────────────
# Low-level readers
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
# Validation helpers
# ─────────────────────────────────────────────────────────────────────────────

def _validate_lat(
    lat: Optional[float],
    row_num: int,
    label: str,
    errors: List[str],
) -> Optional[float]:
    if lat is None:
        return None
    if not (VN_LAT_MIN <= lat <= VN_LAT_MAX):
        errors.append(
            f"Row {row_num} ({label}): Latitude {lat} ngoai pham vi Viet Nam "
            f"({VN_LAT_MIN}–{VN_LAT_MAX}) – giu nguyen gia tri nhung canh bao"
        )
    return lat


def _validate_lon(
    lon: Optional[float],
    row_num: int,
    label: str,
    errors: List[str],
) -> Optional[float]:
    if lon is None:
        return None
    if not (VN_LON_MIN <= lon <= VN_LON_MAX):
        errors.append(
            f"Row {row_num} ({label}): Longitude {lon} ngoai pham vi Viet Nam "
            f"({VN_LON_MIN}–{VN_LON_MAX}) – giu nguyen gia tri nhung canh bao"
        )
    return lon


def _validate_azimuth(
    azi: Optional[float],
    row_num: int,
    label: str,
    errors: List[str],
) -> Optional[float]:
    if azi is None:
        return None
    if not (AZI_MIN <= azi <= AZI_MAX):
        errors.append(
            f"Row {row_num} ({label}): Azimuth {azi} phai trong khoang "
            f"{AZI_MIN}–{AZI_MAX} – dong bi bo qua"
        )
        return None   # invalid azimuth → reject the value
    return azi


# ─────────────────────────────────────────────────────────────────────────────
# Site import
# ─────────────────────────────────────────────────────────────────────────────

def parse_site_excel(
    file_bytes: bytes,
    db=None,
    dry_run: bool = False,
) -> Dict[str, Any]:
    df  = _read_excel(file_bytes)
    geo = GeoCache(db) if db else None

    to_create: List[Dict] = []
    to_update: List[Dict] = []
    errors:    List[str]  = []

    from app.models.site import Site

    for i, row in df.iterrows():
        row_num   = int(str(i)) + 2
        site_name = _v(row, "Site name", "Site Name", "site_name", "SITE NAME")

        if not site_name:
            errors.append(f"Row {row_num}: 'Site name' column is empty – skipped")
            continue

        raw_tinh   = _v(row, "Tỉnh", "Tinh", "TINH", "tinh", "Province")
        raw_phuong = _v(row, "Phường xã", "Phuong xa", "Phường Xã", "phuong_xa", "Ward")
        raw_mien   = _v(row, "Miền", "Mien", "MIEN", "mien")

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

        # ── Lat / Long validation ────────────────────────────────────────
        raw_lat  = _float(row, "Lat", "LAT", "lat", "Latitude")
        raw_long = _float(row, "Long", "LONG", "long", "Longitude")
        lat  = _validate_lat(raw_lat,  row_num, site_name, errors)
        long = _validate_lon(raw_long, row_num, site_name, errors)

        rec: Dict[str, Any] = {
            "mien":         mien,
            "tinh":         tinh_official,
            "phuong_xa":    phuong_xa_official,
            "site_name_cu": _v(row, "Site name (cũ)", "Site name (cu)", "Site Name (cũ)"),
            "site_name":    site_name,
            "site_vip":     _v(row, "Site VIP", "site_vip"),
            "lat":          lat,
            "long":         long,
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
            "moran_3g": _v(row, "TRẠM MORAN 3G (VNPT HOST, MBF HOST)",
                           "MORAN 3G", "moran_3g"),
            "moran_4g": _v(row, "TRẠM MORAN 4G (VNPT HOST, MBF HOST)",
                           "MORAN 4G", "moran_4g"),
            "moran_5g": _v(row, "TRẠM MORAN 5G (VNPT HOST, MBF HOST)",
                           "MORAN 5G", "moran_5g"),
            "ma_ptm":   _v(row, "Mã PTM", "Ma PTM", "ma_ptm", "MaPTM", "PTM") or "",
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
            existing = db.query(Site).filter(Site.site_name == site_name).first()
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

    return {"to_create": to_create, "to_update": to_update,
            "errors": errors, "dry_run": dry_run}


# ─────────────────────────────────────────────────────────────────────────────
# Cell common
# ─────────────────────────────────────────────────────────────────────────────

def _cell_common(
    row,
    geo: Optional[GeoCache] = None,
    errors_out: Optional[List] = None,
    row_num: int = 0,
) -> Dict[str, Any]:
    raw_tinh   = _v(row, "Tỉnh", "Tinh", "tinh")
    raw_phuong = _v(row, "Phường xã", "Phuong xa", "phuong_xa")
    raw_mien   = _v(row, "Miền", "Mien", "mien")

    if geo and raw_tinh:
        tinh_official = geo.resolve_tinh(raw_tinh)
        if not tinh_official:
            if errors_out is not None:
                errors_out.append(
                    f"Row {row_num}: Province '{raw_tinh}' not found in DB – stored as-is"
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

    cell_name = _v(row, "Cell Name", "Cell name", "cell_name") or ""
    label     = cell_name or f"row {row_num}"

    # Validated fields
    raw_lat  = _float(row, "Lat", "LAT", "lat")
    raw_long = _float(row, "Long", "LONG", "long")
    raw_azi  = _float(row, "Azimuth", "azimuth")

    lat  = _validate_lat(raw_lat,  row_num, label, errors_out or [])
    lon  = _validate_lon(raw_long, row_num, label, errors_out or [])
    azi  = _validate_azimuth(raw_azi, row_num, label, errors_out or [])

    return {
        "mien":          mien,
        "tinh":          tinh_official,
        "phuong_xa":     phuong_xa_official,
        "site_name":     _v(row, "Site Name", "Site name", "site_name") or "",
        "cell_name":     cell_name,
        "cell_vip":      _v(row, "Cell VIP", "cell_vip"),
        "moran":         _v(row, "MORAN", "Moran", "moran"),
        "lat":           lat,
        "long":          lon,
        "vung_phu_song": _v(row, "Vùng phủ sóng", "Vung phu song", "vung_phu_song"),
        "vendor":        _v(row, "Vendor", "vendor"),
        "do_cao_anten":  _float(row, "Độ cao anten", "Do cao anten", "do_cao_anten"),
        "azimuth":       azi,
        "m_tilt":        _float(row, "M-tilt", "M-Tilt", "m_tilt"),
        "e_tilt":        _float(row, "E-Tilt", "E-tilt", "e_tilt"),
        "total_tilt":    _float(row, "Total Tilt", "Total tilt", "total_tilt"),
        "loai_anten":    _v(row, "Loại Anten", "Loai Anten", "loai_anten"),
        "baseband":      _v(row, "Baseband", "baseband"),
        "rf":            _v(row, "RF", "rf"),
        "cell_id":       _v(row, "Cell ID", "cell_id"),
        "mimo":          _v(row, "MIMO", "mimo"),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Generic cell parser
# ─────────────────────────────────────────────────────────────────────────────

def _parse_cell_excel(
    file_bytes: bytes,
    Model,
    extra_fields_fn,
    db=None,
    dry_run: bool = False,
) -> Dict[str, Any]:
    df  = _read_excel(file_bytes)
    geo = GeoCache(db) if db else None

    to_create:       List[Dict] = []
    to_update:       List[Dict] = []
    sites_to_create: List[Dict] = []
    errors:          List[str]  = []
    pending_new_sites: Dict[str, Dict] = {}

    from app.models.site import Site

    for i, row in df.iterrows():
        row_num    = int(str(i)) + 2
        row_errors: List[str] = []

        common    = _cell_common(row, geo=geo, errors_out=row_errors, row_num=row_num)
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

        site_obj = None
        if db:
            site_obj = db.query(Site).filter(Site.site_name == site_name).first()

        if site_obj:
            site_id = site_obj.id
        elif site_name in pending_new_sites:
            site_id = None
        else:
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

        rec["site_id"] = site_id

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

    return {
        "to_create":       to_create,
        "to_update":       to_update,
        "sites_to_create": sites_to_create,
        "errors":          errors,
        "dry_run":         dry_run,
    }


def parse_site_excel_simple(file_bytes: bytes) -> List[Dict[str, Any]]:
    result  = parse_site_excel(file_bytes, db=None, dry_run=False)
    records: List[Dict] = []
    for rec in result["to_create"]:
        records.append(rec)
    for upd in result["to_update"]:
        records.append(upd["changes"])
    return records


def parse_cell3g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_3g import Cell3G
    def extra(row):
        return {
            "chung_anten": _v(row, "Chung anten", "chung_anten"),
            "arfcn":       _v(row, "ARFCN", "arfcn"),
            "psc":         _v(row, "PSC",   "psc"),
        }
    return _parse_cell_excel(file_bytes, Cell3G, extra, db=db, dry_run=dry_run)


def parse_cell4g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_4g import Cell4G
    def extra(row):
        return {
            "chung_anten":      _v(row, "Chung anten",     "chung_anten"),
            "earfcn":           _v(row, "EARFCN",           "earfcn"),
            "pci":              _v(row, "PCI",              "pci"),
            "root_sequence_id": _v(row, "Root Sequence ID", "root_sequence_id"),
        }
    return _parse_cell_excel(file_bytes, Cell4G, extra, db=db, dry_run=dry_run)


def parse_cell5g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_5g import Cell5G
    def extra(row):
        return {
            "nr_arfcn":         _v(row, "NR-ARFCN",        "nr_arfcn"),
            "pci":              _v(row, "PCI",              "pci"),
            "root_sequence_id": _v(row, "Root Sequence ID", "root_sequence_id"),
        }
    return _parse_cell_excel(file_bytes, Cell5G, extra, db=db, dry_run=dry_run)
