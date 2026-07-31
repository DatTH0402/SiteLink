"""
import_excel.py – Excel → DB record conversion for Sites, Cell3G, Cell4G, Cell5G.

Key design decisions:
  1. Column PRESENT in Excel + blank value → intentional clear → set field to None/False
  2. Column ABSENT from Excel → do not touch that field
  3. This requires tracking which columns exist in the sheet (excel_columns set)
  4. For boolean fields: blank = False (not None), "x" = True
  5. For text/number fields: blank = None (clear the field)

This fixes:
  - Spurious bool updates: blank bool col → False; DB has False → no diff
  - Blank text col in update: previously ignored, now sets to None (clears field)
"""
from __future__ import annotations

import io
import re
import unicodedata
from typing import Any, Dict, List, Optional, Set, Tuple

import pandas as pd

VN_LAT_MIN, VN_LAT_MAX = 8.33,   23.39
VN_LON_MIN, VN_LON_MAX = 102.14, 109.47
AZI_MIN,    AZI_MAX    = 0,       359

# Sentinel: column exists in Excel but is blank → intentional clear
_CLEAR = object()


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


class GeoCache:
    def __init__(self, db) -> None:
        from app.models.dropdown import DropdownTinhXaPhuong
        rows = db.query(DropdownTinhXaPhuong).all()
        self.tinh_map:  Dict[str, str] = {}
        self.xa_map:    Dict[Tuple[str, str], str] = {}
        self.tinh_mien: Dict[str, str] = {}
        for r in rows:
            if r.ten_tinh:
                k = _normalize(r.ten_tinh)
                self.tinh_map[k]           = r.ten_tinh
                self.tinh_mien[r.ten_tinh] = r.mien or ""
            if r.ten_tinh and r.ten_phuong_xa:
                self.xa_map[
                    (_normalize(r.ten_tinh), _normalize(r.ten_phuong_xa))
                ] = r.ten_phuong_xa

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


def _read_excel(file_bytes: bytes) -> pd.DataFrame:
    df = pd.read_excel(io.BytesIO(file_bytes), dtype=str)
    df = df.where(pd.notna(df), None)
    df.columns = [str(c).strip() for c in df.columns]
    return df


def _col_present(row: Dict, excel_cols: Set[str], *keys) -> bool:
    """Return True if any of the keys exist as a column in the Excel sheet."""
    for key in keys:
        if key in excel_cols:
            return True
    return False


def _v(row: Dict, *keys) -> Optional[str]:
    """
    Return the string value for the first matching key.
    Returns None if key not found OR if cell is blank.
    """
    for key in keys:
        val = row.get(key)
        if val is not None and str(val).strip() not in ("", "nan", "None"):
            return str(val).strip()
    return None


def _v_aware(row: Dict, excel_cols: Set[str], *keys) -> Any:
    """
    Column-presence-aware value extractor.
    - Column absent from Excel: returns _CLEAR sentinel (meaning: skip this field)
      Wait, actually we want: absent = don't include in rec at all.
      So we return a special sentinel only when col IS present but blank.
    - Column present + blank: return None (intentional clear)
    - Column present + has value: return the value string
    - Column absent: return _CLEAR (caller should skip this field)
    """
    col_found = False
    for key in keys:
        if key in excel_cols:
            col_found = True
            val = row.get(key)
            if val is not None and str(val).strip() not in ("", "nan", "None"):
                return str(val).strip()
            # Column exists but blank → intentional clear
            return None
    if not col_found:
        return _CLEAR  # column not in this Excel file → don't touch


def _float_aware(row: Dict, excel_cols: Set[str], *keys) -> Any:
    """Float version of _v_aware."""
    col_found = False
    for key in keys:
        if key in excel_cols:
            col_found = True
            val = row.get(key)
            if val is not None and str(val).strip() not in ("", "nan", "None"):
                try:
                    return float(str(val).strip())
                except (ValueError, TypeError):
                    return None
            return None  # blank → clear
    if not col_found:
        return _CLEAR


def _bool_aware(row: Dict, excel_cols: Set[str], *keys) -> Any:
    """
    Bool version: column present + blank → False (not None, because False is
    the explicit "off" state for checkbox fields).
    Column absent → _CLEAR (skip).
    """
    col_found = False
    for key in keys:
        if key in excel_cols:
            col_found = True
            val = row.get(key)
            if val is not None and str(val).strip() not in ("", "nan", "None"):
                return bool(str(val).strip().lower() in ("x", "true", "yes", "1", "co", "có"))
            return False  # blank → False
    if not col_found:
        return _CLEAR


def _float(row: Dict, *keys) -> Optional[float]:
    v = _v(row, *keys)
    if v is None:
        return None
    try:
        return float(v)
    except (ValueError, TypeError):
        return None


def _bool(row: Dict, *keys) -> bool:
    v = _v(row, *keys)
    if v is None:
        return False
    return str(v).strip().lower() in ("x", "true", "yes", "1", "co", "có")


def _validate_lat(lat, row_num, label, errors):
    if lat is None:
        return None
    if not (VN_LAT_MIN <= lat <= VN_LAT_MAX):
        errors.append(
            f"Row {row_num} ({label}): Latitude {lat} ngoai pham vi Viet Nam "
            f"({VN_LAT_MIN}–{VN_LAT_MAX}) – giu nguyen gia tri nhung canh bao"
        )
    return lat


def _validate_lon(lon, row_num, label, errors):
    if lon is None:
        return None
    if not (VN_LON_MIN <= lon <= VN_LON_MAX):
        errors.append(
            f"Row {row_num} ({label}): Longitude {lon} ngoai pham vi Viet Nam "
            f"({VN_LON_MIN}–{VN_LON_MAX}) – giu nguyen gia tri nhung canh bao"
        )
    return lon


def _validate_azimuth(azi, row_num, label, errors):
    if azi is None:
        return None
    if not (AZI_MIN <= azi <= AZI_MAX):
        errors.append(
            f"Row {row_num} ({label}): Azimuth {azi} phai trong khoang "
            f"{AZI_MIN}–{AZI_MAX} – dong bi bo qua"
        )
        return None
    return azi


def _apply_changes_to_obj(obj: Any, changes: Dict[str, Any],
                           skip_keys: Set[str] = None,
                           bool_fields: Set[str] = None) -> bool:
    """
    Apply changes dict to an ORM object.
    - Skips _CLEAR sentinel values (column not in Excel → don't touch)
    - Applies None values (intentional clear)
    - Applies False values for bool fields (intentional uncheck)
    - Returns True if any field was actually changed
    """
    if skip_keys is None:
        skip_keys = set()
    if bool_fields is None:
        bool_fields = set()
    changed = False
    for k, v in changes.items():
        if k in skip_keys:
            continue
        if k.startswith("_"):
            continue
        if v is _CLEAR:
            continue  # column absent from Excel → don't touch
        if not hasattr(obj, k):
            continue
        old_val = getattr(obj, k)
        # Normalize for comparison
        old_norm = _norm_compare(old_val, k in bool_fields)
        new_norm = _norm_compare(v, k in bool_fields)
        if old_norm != new_norm:
            setattr(obj, k, v)
            changed = True
    return changed


def _norm_compare(v: Any, is_bool: bool = False) -> Any:
    """Normalize value for change comparison."""
    if is_bool:
        if v is None:
            return False
        if isinstance(v, bool):
            return v
        if isinstance(v, int):
            return v != 0
        if isinstance(v, str):
            return v.strip().lower() not in ("false", "0", "no", "off", "")
        return bool(v)
    if v is None or (isinstance(v, str) and v.strip() == ""):
        return None
    if isinstance(v, float):
        return v
    return str(v).strip() if isinstance(v, str) else v


# ── Site import ───────────────────────────────────────────────────────────────

_SITE_BOOL_FIELDS = {
    'tram_2g', 'tram_3g', 'tram_4g', 'tram_5g',
    'repeater', 'booster', 'node_truyen_dan_only', 'tram_phu_song_tsca',
}


def parse_site_excel(file_bytes: bytes, db=None, dry_run: bool = False) -> Dict[str, Any]:
    df  = _read_excel(file_bytes)
    geo = GeoCache(db) if db else None
    excel_cols: Set[str] = set(df.columns)
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
                        f"Ward '{raw_phuong}' not found under '{tinh_official}' – field left blank"
                    )
        else:
            tinh_official      = raw_tinh or ""
            mien               = raw_mien or ""
            phuong_xa_official = raw_phuong

        if not tinh_official:
            errors.append(f"Row {row_num} (site '{site_name}'): 'Tinh' is empty – skipped")
            continue

        raw_lat  = _float(row, "Lat", "LAT", "lat", "Latitude")
        raw_long = _float(row, "Long", "LONG", "long", "Longitude")
        lat  = _validate_lat(raw_lat,  row_num, site_name, errors)
        long = _validate_lon(raw_long, row_num, site_name, errors)

        file_site_name_old = _v(row, "Site name (cũ)", "Site name (cu)", "Site Name (cũ)",
                                 "Site Name Old", "site_name_old")

        # Build rec with column-aware values
        # For CREATE: use _bool/_v (blank = False/None as before)
        # For UPDATE: use _bool_aware/_v_aware (blank = intentional clear)
        rec: Dict[str, Any] = {
            "mien": mien, "tinh": tinh_official, "phuong_xa": phuong_xa_official,
            "site_name_cu": file_site_name_old, "site_name": site_name,
            # Use aware versions for update-sensitive fields:
            "site_vip":    _v_aware(row, excel_cols, "Site VIP", "site_vip"),
            "lat": lat, "long": long,
            # Boolean fields – aware version: blank → False, absent → _CLEAR
            "tram_2g":    _bool_aware(row, excel_cols, "Trạm 2G", "Tram 2G", "tram_2g"),
            "tram_3g":    _bool_aware(row, excel_cols, "Trạm 3G", "Tram 3G", "tram_3g"),
            "tram_4g":    _bool_aware(row, excel_cols, "Trạm 4G", "Tram 4G", "tram_4g"),
            "tram_5g":    _bool_aware(row, excel_cols, "Trạm 5G", "Tram 5G", "tram_5g"),
            "repeater":   _bool_aware(row, excel_cols, "Repeater", "repeater"),
            "booster":    _bool_aware(row, excel_cols, "Booster",  "booster"),
            "node_truyen_dan_only": _bool_aware(row, excel_cols,
                "Node truyền dẫn only", "Node truyen dan only", "node_truyen_dan_only"),
            "tram_phu_song_tsca": _bool_aware(row, excel_cols,
                "Trạm phủ sóng TSCA", "Tram phu song TSCA", "tram_phu_song_tsca"),
            "phan_loai_tram": _v_aware(row, excel_cols,
                "IBC/ Macro outdoor / IBC + Outdoor / miniDAS / Smallcell",
                "Phan loai tram", "phan_loai_tram"),
            "moran_3g": _v_aware(row, excel_cols,
                "TRẠM MORAN 3G (VNPT HOST, MBF HOST)", "MORAN 3G", "moran_3g"),
            "moran_4g": _v_aware(row, excel_cols,
                "TRẠM MORAN 4G (VNPT HOST, MBF HOST)", "MORAN 4G", "moran_4g"),
            "moran_5g": _v_aware(row, excel_cols,
                "TRẠM MORAN 5G (VNPT HOST, MBF HOST)", "MORAN 5G", "moran_5g"),
            "ma_ptm": _v_aware(row, excel_cols, "Mã PTM", "Ma PTM", "ma_ptm", "MaPTM", "PTM"),
            "do_cao_dinh_cot_anten": _float_aware(row, excel_cols,
                "Độ cao đỉnh cột anten (m) đến mặt đất",
                "Do cao dinh cot anten", "do_cao_dinh_cot_anten"),
            "do_cao_cot_anten": _float_aware(row, excel_cols,
                "Độ cao cột anten", "Do cao cot anten", "do_cao_cot_anten"),
            "dia_chi": _v_aware(row, excel_cols, "Địa chỉ", "Dia chi", "dia_chi"),
            "ghi_chu":  _v_aware(row, excel_cols, "Ghi chú", "Ghi chu", "ghi_chu"),
        }

        if db:
            existing = db.query(Site).filter(Site.site_name == site_name).first()
            if not existing and file_site_name_old:
                existing_by_old = db.query(Site).filter(
                    Site.site_name == file_site_name_old).first()
                if existing_by_old:
                    rec["_site_name_old_ref"] = file_site_name_old
                    to_update.append({
                        "existing_id": existing_by_old.id,
                        "anchor": file_site_name_old,
                        "changes": rec, "is_rename": True,
                    })
                    continue
            if existing:
                to_update.append({
                    "existing_id": existing.id, "anchor": site_name,
                    "changes": rec, "is_rename": False,
                })
            else:
                # For CREATE: replace _CLEAR with defaults
                create_rec = _resolve_create_rec(rec)
                to_create.append(create_rec)
        else:
            create_rec = _resolve_create_rec(rec)
            to_create.append(create_rec)

    return {
        "to_create": to_create, "to_update": to_update,
        "errors": errors, "dry_run": dry_run,
    }


def _resolve_create_rec(rec: Dict) -> Dict:
    """For CREATE operations, replace _CLEAR sentinels with None/False defaults."""
    result = {}
    for k, v in rec.items():
        if v is _CLEAR:
            # Default: booleans → False, others → None
            if k in _SITE_BOOL_FIELDS:
                result[k] = False
            else:
                result[k] = None
        else:
            result[k] = v
    return result


# ── Cell common field extractor ───────────────────────────────────────────────

_CELL_BOOL_FIELDS: Set[str] = set()  # cells have no boolean fields currently


def _cell_common_aware(row: Dict, excel_cols: Set[str],
                        geo=None, errors_out=None, row_num=0) -> Dict[str, Any]:
    """Column-aware version of _cell_common."""
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

    raw_lat  = _float(row, "Lat", "LAT", "lat")
    raw_long = _float(row, "Long", "LONG", "long")
    raw_azi  = _float(row, "Azimuth", "azimuth")

    lat = _validate_lat(raw_lat,  row_num, label, errors_out or [])
    lon = _validate_lon(raw_long, row_num, label, errors_out or [])
    azi = _validate_azimuth(raw_azi, row_num, label, errors_out or [])

    return {
        "mien": mien, "tinh": tinh_official, "phuong_xa": phuong_xa_official,
        "site_name":     _v(row, "Site Name", "Site name", "site_name") or "",
        "site_name_old": _v_aware(row, excel_cols, "Site Name Old", "Site name old",
                                   "site_name_old", "Site Name (cũ)", "Site name (cu)"),
        "cell_name":     cell_name,
        "cell_name_old": _v_aware(row, excel_cols, "Cell Name Old", "Cell name old",
                                   "cell_name_old", "Cell Name (cũ)"),
        "cell_vip":      _v_aware(row, excel_cols, "Cell VIP", "cell_vip"),
        "moran":         _v_aware(row, excel_cols, "MORAN", "Moran", "moran"),
        "lat": lat, "long": lon,
        "vung_phu_song": _v_aware(row, excel_cols, "Vùng phủ sóng",
                                   "Vung phu song", "vung_phu_song"),
        "vendor":        _v_aware(row, excel_cols, "Vendor", "vendor"),
        "do_cao_anten":  _float_aware(row, excel_cols, "Độ cao anten",
                                       "Do cao anten", "do_cao_anten"),
        "azimuth": azi,
        "m_tilt":        _float_aware(row, excel_cols, "M-tilt", "M-Tilt", "m_tilt"),
        "e_tilt":        _float_aware(row, excel_cols, "E-Tilt", "E-tilt", "e_tilt"),
        "total_tilt":    _float_aware(row, excel_cols, "Total Tilt", "Total tilt", "total_tilt"),
        "loai_anten":    _v_aware(row, excel_cols, "Loại Anten", "Loai Anten", "loai_anten"),
        "baseband":      _v_aware(row, excel_cols, "Baseband", "baseband"),
        "rf":            _v_aware(row, excel_cols, "RF", "rf"),
        "cell_id":       _v_aware(row, excel_cols, "Cell ID", "cell_id"),
        "mimo":          _v_aware(row, excel_cols, "MIMO", "mimo"),
        "bbu_name":      _v_aware(row, excel_cols, "BBUname", "BBU Name", "bbu_name"),
        "cell_status":   _v_aware(row, excel_cols, "Cell status (at dump time)",
                                   "Cell status", "cell_status"),
        "cell_max_power": _v_aware(row, excel_cols, "Cell max power (dBm)",
                                    "Cell max power", "cell_max_power"),
    }


# ── Core cell Excel parser ────────────────────────────────────────────────────

def _parse_cell_excel(
    file_bytes, Model, extra_fields_fn, db=None, dry_run=False
) -> Dict[str, Any]:
    df  = _read_excel(file_bytes)
    excel_cols: Set[str] = set(df.columns)
    geo = GeoCache(db) if db else None

    to_create:         List[Dict] = []
    to_update:         List[Dict] = []
    sites_to_create:   List[Dict] = []
    errors:            List[str]  = []
    pending_new_sites: Dict[str, Dict] = {}

    from app.models.site import Site

    for i, row in df.iterrows():
        row_num    = int(str(i)) + 2
        row_errors: List[str] = []

        common       = _cell_common_aware(row, excel_cols, geo=geo,
                                           errors_out=row_errors, row_num=row_num)
        errors.extend(row_errors)

        cell_name     = common.get("cell_name", "")
        cell_name_old_val = common.get("cell_name_old", _CLEAR)
        cell_name_old = cell_name_old_val if cell_name_old_val is not _CLEAR else None
        site_name     = common.get("site_name", "")
        site_name_old_val = common.get("site_name_old", _CLEAR)
        site_name_old = site_name_old_val if site_name_old_val is not _CLEAR else None

        if not cell_name:
            errors.append(f"Row {row_num}: 'Cell Name' is empty – skipped")
            continue
        if not site_name:
            errors.append(f"Row {row_num}: 'Site Name' is empty – skipped")
            continue

        extra = extra_fields_fn(row, excel_cols)
        rec   = {**common, **extra}

        # ── Site resolution ───────────────────────────────────────────────────
        site_obj = None
        if db:
            site_obj = db.query(Site).filter(Site.site_name == site_name).first()
            if not site_obj and site_name_old:
                site_obj = db.query(Site).filter(
                    Site.site_name == site_name_old).first()

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

        # ── Cell resolution ───────────────────────────────────────────────────
        existing_cell = None

        if db:
            if site_obj:
                existing_cell = db.query(Model).filter(
                    Model.site_id == site_obj.id,
                    Model.cell_name == cell_name,
                ).first()

                if not existing_cell and cell_name_old:
                    existing_by_old = db.query(Model).filter(
                        Model.site_id == site_obj.id,
                        Model.cell_name == cell_name_old,
                    ).first()
                    if existing_by_old:
                        to_update.append({
                            "existing_id": existing_by_old.id,
                            "anchor":      f"{site_name}/{cell_name_old}",
                            "changes":     rec,
                            "is_rename":   True,
                        })
                        continue

            else:
                existing_cell = db.query(Model).filter(
                    Model.cell_name == cell_name,
                ).first()

                if not existing_cell and cell_name_old:
                    existing_cell = db.query(Model).filter(
                        Model.cell_name == cell_name_old,
                    ).first()

                if existing_cell:
                    rec["site_id"] = existing_cell.site_id

        if existing_cell:
            to_update.append({
                "existing_id": existing_cell.id,
                "anchor":      f"{site_name}/{cell_name}",
                "changes":     rec,
                "is_rename":   False,
            })
        else:
            # Resolve _CLEAR sentinels for CREATE
            create_rec = _resolve_cell_create_rec(rec)
            to_create.append(create_rec)

    return {
        "to_create":       to_create,
        "to_update":       to_update,
        "sites_to_create": sites_to_create,
        "errors":          errors,
        "dry_run":         dry_run,
    }


def _resolve_cell_create_rec(rec: Dict) -> Dict:
    """For CREATE: replace _CLEAR sentinels with None."""
    return {k: (None if v is _CLEAR else v) for k, v in rec.items()}


def parse_site_excel_simple(file_bytes: bytes) -> List[Dict[str, Any]]:
    result = parse_site_excel(file_bytes, db=None, dry_run=False)
    records: List[Dict] = []
    for rec in result["to_create"]:
        records.append(rec)
    for upd in result["to_update"]:
        records.append(_resolve_create_rec(upd["changes"]))
    return records


def parse_cell3g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_3g import Cell3G
    def extra(row, excel_cols):
        return {
            "chung_anten": _v_aware(row, excel_cols, "Chung anten", "chung_anten"),
            "arfcn":       _v_aware(row, excel_cols, "ARFCN", "arfcn"),
            "uarfcn":      _v_aware(row, excel_cols, "UARFCN", "uarfcn"),
            "lac":         _v_aware(row, excel_cols, "LAC", "lac"),
            "rac":         _v_aware(row, excel_cols, "RAC", "rac"),
            "psc":         _v_aware(row, excel_cols, "PSC", "psc"),
            "ura_id":      _v_aware(row, excel_cols, "URAId", "URA ID", "ura_id"),
            "cpich_power": _v_aware(row, excel_cols, "CPICH power (dBm)",
                                     "CPICH power", "cpich_power"),
        }
    return _parse_cell_excel(file_bytes, Cell3G, extra, db=db, dry_run=dry_run)


def parse_cell4g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_4g import Cell4G
    def extra(row, excel_cols):
        return {
            "chung_anten":      _v_aware(row, excel_cols, "Chung anten", "chung_anten"),
            "enodeb_id":        _v_aware(row, excel_cols, "EnodeB ID", "enodeb_id"),
            "earfcn":           _v_aware(row, excel_cols, "EARFCN", "earfcn"),
            "tac":              _v_aware(row, excel_cols, "TAC", "tac"),
            "pci":              _v_aware(row, excel_cols, "PCI", "pci"),
            "root_sequence_id": _v_aware(row, excel_cols, "Root Sequence ID",
                                          "root_sequence_id"),
            "bandwidth":        _v_aware(row, excel_cols, "Bandwitdh", "Bandwidth",
                                          "bandwidth"),
            "eci":              _v_aware(row, excel_cols, "ECI", "eci"),
        }
    return _parse_cell_excel(file_bytes, Cell4G, extra, db=db, dry_run=dry_run)


def parse_cell5g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_5g import Cell5G
    def extra(row, excel_cols):
        return {
            "gnodeb_id":        _v_aware(row, excel_cols, "gNodeB ID", "gnodeb_id"),
            "tac":              _v_aware(row, excel_cols, "TAC", "tac"),
            "pci":              _v_aware(row, excel_cols, "PCI", "pci"),
            "root_sequence_id": _v_aware(row, excel_cols, "Root Sequence ID",
                                          "root_sequence_id"),
            "ssb_arfcn":        _v_aware(row, excel_cols, "SSB-ARFCN", "ssb_arfcn"),
            "center_arfcn":     _v_aware(row, excel_cols, "Center-ARFCN", "center_arfcn"),
            "gscn":             _v_aware(row, excel_cols, "GSCN", "gscn"),
            "bandwidth":        _v_aware(row, excel_cols, "Bandwidth (MHz)", "Bandwidth",
                                          "bandwidth"),
            "nci":              _v_aware(row, excel_cols, "NCI", "nci"),
            "mu_mimo":          _v_aware(row, excel_cols, "MU-MIMO", "mu_mimo"),
        }
    return _parse_cell_excel(file_bytes, Cell5G, extra, db=db, dry_run=dry_run)
