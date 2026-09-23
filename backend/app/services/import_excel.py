"""
import_excel.py – Excel → DB record conversion for Sites, Cell3G, Cell4G, Cell5G.

Key design decisions:
  1. Column PRESENT in Excel + blank value → intentional clear → set field to None/False
  2. Column ABSENT from Excel → do not touch that field
  3. Required fields are validated and errors collected (not raised).
  4. do_cao_dinh_cot_anten, do_cao_cot_anten (sites) and
     do_cao_anten, azimuth, m_tilt, e_tilt, total_tilt (cells)
     are now STRING fields – they accept any non-empty string value
     (numeric like "35.5" or special like "IBC").
"""
from __future__ import annotations

import io
import re
import unicodedata
from typing import Any, Dict, List, Optional, Set, Tuple

import pandas as pd

VN_LAT_MIN, VN_LAT_MAX = 8.33,   23.39
VN_LON_MIN, VN_LON_MAX = 102.14, 109.47

# Sentinel: column exists in Excel but is blank → intentional clear
_CLEAR = object()

# ── Required fields ────────────────────────────────────────────────────────────
SITE_REQUIRED_FIELDS = {
    "site_name":             "Site name",
    "lat":                   "Lat",
    "long":                  "Long",
    "dia_chi":               "Địa chỉ",
    "do_cao_dinh_cot_anten": "Độ cao đỉnh cột anten tới mặt đất",
}

CELL_REQUIRED_FIELDS = {
    "site_name":    "Site name",
    "cell_name":    "Cell name",
    "vendor":       "Vendor",
    "lat":          "Lat",
    "long":         "Long",
    "azimuth":      "Azimuth",
    "do_cao_anten": "Độ cao anten",
    "m_tilt":       "M-tilt",
    "e_tilt":       "E-Tilt",
}

# ── Allowed dropdown values ────────────────────────────────────────────────────
ALLOWED_VENDORS   = {"Ericsson", "Nokia", "Huawei", "ZTE", "Samsung"}
ALLOWED_MIEN      = {"MB", "MT", "MN"}
ALLOWED_VUNG      = {"Indoor", "Outdoor"}
ALLOWED_MIMO      = {"2x2", "4x4", "8x8"}
ALLOWED_MORAN     = {"VNPT HOST", "MBF HOST"}
ALLOWED_SITE_VIP  = {"VIP", "VVIP"}
ALLOWED_CELL_VIP  = {"VIP", "VVIP"}
ALLOWED_CHUNG_3G  = {"3G", "3G/4G", "2G/3G/4G", "3G/4G/5G", "3G/5G"}
ALLOWED_CHUNG_4G  = {"4G", "2G/4G", "3G/4G", "2G/3G/4G", "4G/5G"}
ALLOWED_MU_MIMO   = {"Yes", "No"}


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


def _v(row: Dict, *keys) -> Optional[str]:
    for key in keys:
        val = row.get(key)
        if val is not None and str(val).strip() not in ("", "nan", "None"):
            return str(val).strip()
    return None


def _v_aware(row: Dict, excel_cols: Set[str], *keys) -> Any:
    col_found = False
    for key in keys:
        if key in excel_cols:
            col_found = True
            val = row.get(key)
            if val is not None and str(val).strip() not in ("", "nan", "None"):
                return str(val).strip()
            return None
    if not col_found:
        return _CLEAR


def _float_aware(row: Dict, excel_cols: Set[str], *keys) -> Any:
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
            return None
    if not col_found:
        return _CLEAR


def _str_aware(row: Dict, excel_cols: Set[str], *keys) -> Any:
    """
    Like _v_aware but for fields that were previously float (now string).
    Returns the raw string value if present, None if blank, _CLEAR if column absent.
    """
    col_found = False
    for key in keys:
        if key in excel_cols:
            col_found = True
            val = row.get(key)
            if val is not None and str(val).strip() not in ("", "nan", "None"):
                # Normalise: if it looks like an integer float (e.g. "35.0"), strip ".0"
                s = str(val).strip()
                try:
                    f = float(s)
                    if f == int(f):
                        s = str(int(f))
                except (ValueError, TypeError):
                    pass
                return s
            return None
    if not col_found:
        return _CLEAR


def _bool_aware(row: Dict, excel_cols: Set[str], *keys) -> Any:
    col_found = False
    for key in keys:
        if key in excel_cols:
            col_found = True
            val = row.get(key)
            if val is not None and str(val).strip() not in ("", "nan", "None"):
                return bool(str(val).strip().lower() in ("x", "true", "yes", "1", "co", "có"))
            return False
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


# ── Validation helpers ─────────────────────────────────────────────────────────

def _check_required(value: Any, field_label: str, row_num: int,
                    record_label: str, errors: List[str]) -> bool:
    is_missing = (
        value is None
        or value is _CLEAR
        or (isinstance(value, str) and value.strip() == "")
    )
    if is_missing:
        errors.append(
            f"Row {row_num} ({record_label}): Trường bắt buộc '{field_label}' bị để trống."
        )
        return False
    return True


def _check_dropdown(value: Any, field_label: str, allowed: Set[str],
                    row_num: int, record_label: str, errors: List[str],
                    required: bool = False) -> bool:
    if value is None or value is _CLEAR or (isinstance(value, str) and value.strip() == ""):
        if required:
            errors.append(
                f"Row {row_num} ({record_label}): Trường bắt buộc '{field_label}' bị để trống."
            )
            return False
        return True
    if str(value) not in allowed:
        errors.append(
            f"Row {row_num} ({record_label}): Giá trị '{value}' không hợp lệ cho trường "
            f"'{field_label}'. Các giá trị cho phép: {sorted(allowed)}. "
            f"Nếu cần thêm giá trị mới, vui lòng liên hệ quản trị viên."
        )
        return False
    return True


def _check_db_dropdown(value: Any, field_label: str, allowed_set: Set[str],
                       row_num: int, record_label: str, errors: List[str],
                       required: bool = False) -> bool:
    if value is None or value is _CLEAR or (isinstance(value, str) and value.strip() == ""):
        if required:
            errors.append(
                f"Row {row_num} ({record_label}): Trường bắt buộc '{field_label}' bị để trống."
            )
            return False
        return True
    if str(value) not in allowed_set:
        errors.append(
            f"Row {row_num} ({record_label}): Giá trị '{value}' không tồn tại trong hệ thống "
            f"cho trường '{field_label}'. Vui lòng liên hệ quản trị viên để thêm giá trị này."
        )
        return False
    return True


def _validate_lat(lat: Any, row_num: int, label: str, errors: List[str],
                  required: bool = False) -> Optional[float]:
    if lat is None:
        if required:
            errors.append(f"Row {row_num} ({label}): Trường bắt buộc 'Lat' bị để trống.")
        return None
    try:
        lat_f = float(lat)
    except (ValueError, TypeError):
        errors.append(f"Row {row_num} ({label}): Giá trị Lat '{lat}' không phải số hợp lệ.")
        return None
    if not (VN_LAT_MIN <= lat_f <= VN_LAT_MAX):
        errors.append(
            f"Row {row_num} ({label}): Latitude {lat_f} nằm ngoài phạm vi Việt Nam "
            f"({VN_LAT_MIN}–{VN_LAT_MAX}). Vui lòng kiểm tra lại toạ độ."
        )
        return None
    return lat_f


def _validate_lon(lon: Any, row_num: int, label: str, errors: List[str],
                  required: bool = False) -> Optional[float]:
    if lon is None:
        if required:
            errors.append(f"Row {row_num} ({label}): Trường bắt buộc 'Long' bị để trống.")
        return None
    try:
        lon_f = float(lon)
    except (ValueError, TypeError):
        errors.append(f"Row {row_num} ({label}): Giá trị Long '{lon}' không phải số hợp lệ.")
        return None
    if not (VN_LON_MIN <= lon_f <= VN_LON_MAX):
        errors.append(
            f"Row {row_num} ({label}): Longitude {lon_f} nằm ngoài phạm vi Việt Nam "
            f"({VN_LON_MIN}–{VN_LON_MAX}). Vui lòng kiểm tra lại toạ độ."
        )
        return None
    return lon_f


def _norm_compare(v: Any, is_bool: bool = False) -> Any:
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


# ── Site import ────────────────────────────────────────────────────────────────

_SITE_BOOL_FIELDS = {
    'tram_2g', 'tram_3g', 'tram_4g', 'tram_5g',
    'repeater', 'booster', 'node_truyen_dan_only', 'tram_phu_song_tsca',
}


def _get_phan_loai_opts(db) -> Set[str]:
    if db is None:
        return set()
    try:
        from app.models.dropdown import DropdownGeneral
        rows = db.query(DropdownGeneral).filter(
            DropdownGeneral.category == "phan_loai_tram"
        ).all()
        return {r.value for r in rows}
    except Exception:
        return set()


def _get_antenna_names(db) -> Set[str]:
    if db is None:
        return set()
    try:
        from app.models.antenna import Antenna
        rows = db.query(Antenna.name).all()
        return {r[0] for r in rows if r[0]}
    except Exception:
        return set()


def _get_rnc_names(db) -> Set[str]:
    if db is None:
        return set()
    try:
        from app.models.rnc import RncName
        rows = db.query(RncName.name).all()
        return {r[0] for r in rows if r[0]}
    except Exception:
        return set()


def parse_site_excel(file_bytes: bytes, db=None, dry_run: bool = False) -> Dict[str, Any]:
    df  = _read_excel(file_bytes)
    geo = GeoCache(db) if db else None
    excel_cols: Set[str] = set(df.columns)
    phan_loai_opts = _get_phan_loai_opts(db)

    to_create: List[Dict] = []
    to_update: List[Dict] = []
    errors:    List[str]  = []
    fatal_rows: Set[int]  = set()

    from app.models.site import Site

    for i, row in df.iterrows():
        row_num   = int(str(i)) + 2
        row_errors: List[str] = []

        site_name = _v(row, "Site name", "Site Name", "site_name", "SITE NAME")
        if not site_name:
            errors.append(f"Row {row_num}: Trường bắt buộc 'Site name' bị để trống – bỏ qua dòng này.")
            fatal_rows.add(row_num)
            continue

        label = f"site '{site_name}'"

        raw_tinh   = _v(row, "Tỉnh", "Tinh", "TINH", "tinh", "Province")
        raw_phuong = _v(row, "Phường xã", "Phuong xa", "Phường Xã", "phuong_xa", "Ward")
        raw_mien   = _v(row, "Miền", "Mien", "MIEN", "mien")

        if geo and raw_tinh:
            tinh_official = geo.resolve_tinh(raw_tinh)
            if not tinh_official:
                row_errors.append(
                    f"Row {row_num} ({label}): Tỉnh/TP '{raw_tinh}' không tìm thấy trong hệ thống."
                )
                fatal_rows.add(row_num)
                errors.extend(row_errors)
                continue
            mien = geo.mien_for(tinh_official) or raw_mien or ""
            phuong_xa_official: Optional[str] = None
            if raw_phuong:
                phuong_xa_official = geo.resolve_xa(tinh_official, raw_phuong)
                if not phuong_xa_official:
                    row_errors.append(
                        f"Row {row_num} ({label}): Phường/Xã '{raw_phuong}' không tìm thấy "
                        f"trong '{tinh_official}'."
                    )
        else:
            tinh_official      = raw_tinh or ""
            mien               = raw_mien or ""
            phuong_xa_official = raw_phuong

        if not tinh_official:
            row_errors.append(f"Row {row_num} ({label}): Trường 'Tỉnh' bị để trống.")

        # ── Lat / Long (required, must be numeric) ───────────────────────────
        raw_lat  = _float(row, "Lat", "LAT", "lat", "Latitude")
        raw_long = _float(row, "Long", "LONG", "long", "Longitude")
        lat  = _validate_lat(raw_lat,  row_num, label, row_errors, required=True)
        long = _validate_lon(raw_long, row_num, label, row_errors, required=True)

        # ── Địa chỉ (required) ────────────────────────────────────────────────
        dia_chi_val = _v_aware(row, excel_cols, "Địa chỉ", "Dia chi", "dia_chi")
        if dia_chi_val is None or dia_chi_val is _CLEAR:
            row_errors.append(
                f"Row {row_num} ({label}): Trường bắt buộc 'Địa chỉ' bị để trống."
            )

        # ── Độ cao đỉnh cột anten (required, now STRING) ──────────────────────
        raw_dcant = _str_aware(row, excel_cols,
            "Độ cao đỉnh cột anten (m) đến mặt đất",
            "Do cao dinh cot anten", "do_cao_dinh_cot_anten")
        if raw_dcant is None or raw_dcant is _CLEAR:
            row_errors.append(
                f"Row {row_num} ({label}): Trường bắt buộc "
                f"'Độ cao đỉnh cột anten tới mặt đất' bị để trống."
            )
        # No numeric range validation – accepts any non-empty string

        # ── Optional dropdown validations ─────────────────────────────────────
        site_vip_val = _v_aware(row, excel_cols, "Site VIP", "site_vip")
        if site_vip_val and site_vip_val is not _CLEAR:
            _check_dropdown(site_vip_val, "Site VIP", ALLOWED_SITE_VIP,
                            row_num, label, row_errors)

        mien_val = mien if mien else None
        if mien_val:
            _check_dropdown(mien_val, "Miền", ALLOWED_MIEN,
                            row_num, label, row_errors)

        phan_loai_val = _v_aware(row, excel_cols,
            "IBC/ Macro outdoor / IBC + Outdoor / miniDAS / Smallcell",
            "Phan loai tram", "phan_loai_tram")
        if (phan_loai_val and phan_loai_val is not _CLEAR and phan_loai_opts):
            _check_db_dropdown(phan_loai_val, "Phân loại trạm", phan_loai_opts,
                               row_num, label, row_errors)

        moran_fields = [
            (_v_aware(row, excel_cols,
                "TRẠM MORAN 3G (VNPT HOST, MBF HOST)", "MORAN 3G", "moran_3g"),
             "MORAN 3G"),
            (_v_aware(row, excel_cols,
                "TRẠM MORAN 4G (VNPT HOST, MBF HOST)", "MORAN 4G", "moran_4g"),
             "MORAN 4G"),
            (_v_aware(row, excel_cols,
                "TRẠM MORAN 5G (VNPT HOST, MBF HOST)", "MORAN 5G", "moran_5g"),
             "MORAN 5G"),
        ]
        for moran_val, moran_label in moran_fields:
            if moran_val and moran_val is not _CLEAR:
                _check_dropdown(moran_val, moran_label, ALLOWED_MORAN,
                                row_num, label, row_errors)

        if row_errors:
            errors.extend(row_errors)
            fatal_rows.add(row_num)
            continue

        file_site_name_old = _v(row, "Site name (cũ)", "Site name (cu)",
                                 "Site Name (cũ)", "Site Name Old", "site_name_old")

        rec: Dict[str, Any] = {
            "mien": mien, "tinh": tinh_official, "phuong_xa": phuong_xa_official,
            "site_name_cu": file_site_name_old, "site_name": site_name,
            "site_vip":    _v_aware(row, excel_cols, "Site VIP", "site_vip"),
            "lat": lat, "long": long,
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
            "phan_loai_tram": phan_loai_val if (phan_loai_val and phan_loai_val is not _CLEAR)
                              else _v_aware(row, excel_cols,
                                  "IBC/ Macro outdoor / IBC + Outdoor / miniDAS / Smallcell",
                                  "Phan loai tram", "phan_loai_tram"),
            "moran_3g": _v_aware(row, excel_cols,
                "TRẠM MORAN 3G (VNPT HOST, MBF HOST)", "MORAN 3G", "moran_3g"),
            "moran_4g": _v_aware(row, excel_cols,
                "TRẠM MORAN 4G (VNPT HOST, MBF HOST)", "MORAN 4G", "moran_4g"),
            "moran_5g": _v_aware(row, excel_cols,
                "TRẠM MORAN 5G (VNPT HOST, MBF HOST)", "MORAN 5G", "moran_5g"),
            "ma_ptm": _v_aware(row, excel_cols, "Mã PTM", "Ma PTM", "ma_ptm", "MaPTM", "PTM"),
            # Now string fields:
            "do_cao_dinh_cot_anten": raw_dcant if (raw_dcant and raw_dcant is not _CLEAR) else raw_dcant,
            "do_cao_cot_anten": _str_aware(row, excel_cols,
                "Độ cao cột anten", "Do cao cot anten", "do_cao_cot_anten",
                "Độ cao cột anten (đỉnh cột anten đến chân cột anten, không tính độ cao công trình)"),
            "dia_chi": dia_chi_val,
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
                to_create.append(_resolve_create_rec(rec))
        else:
            to_create.append(_resolve_create_rec(rec))

    return {
        "to_create": to_create, "to_update": to_update,
        "errors": errors, "dry_run": dry_run,
        "fatal_count": len(fatal_rows),
    }


def _resolve_create_rec(rec: Dict) -> Dict:
    result = {}
    for k, v in rec.items():
        if v is _CLEAR:
            if k in _SITE_BOOL_FIELDS:
                result[k] = False
            else:
                result[k] = None
        else:
            result[k] = v
    return result


# ── Cell common field extractor ────────────────────────────────────────────────

def _cell_common_aware(row: Dict, excel_cols: Set[str],
                        geo=None, errors_out=None, row_num=0,
                        antenna_names: Set[str] = None,
                        rnc_names: Set[str] = None) -> Dict[str, Any]:
    if errors_out is None:
        errors_out = []

    raw_tinh   = _v(row, "Tỉnh", "Tinh", "tinh")
    raw_phuong = _v(row, "Phường xã", "Phuong xa", "phuong_xa")
    raw_mien   = _v(row, "Miền", "Mien", "mien")

    if geo and raw_tinh:
        tinh_official = geo.resolve_tinh(raw_tinh)
        if not tinh_official:
            errors_out.append(
                f"Row {row_num}: Tỉnh/TP '{raw_tinh}' không tìm thấy trong hệ thống."
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

    # ── Required: Lat, Long (must be numeric) ────────────────────────────────
    raw_lat  = _float(row, "Lat", "LAT", "lat")
    raw_long = _float(row, "Long", "LONG", "long")
    lat  = _validate_lat(raw_lat,  row_num, label, errors_out, required=True)
    lon  = _validate_lon(raw_long, row_num, label, errors_out, required=True)

    # ── Required: Azimuth (now STRING – any non-empty value accepted) ─────────
    azimuth_val = _str_aware(row, excel_cols, "Azimuth", "azimuth")
    if azimuth_val is None or azimuth_val is _CLEAR:
        errors_out.append(
            f"Row {row_num} ({label}): Trường bắt buộc 'Azimuth' bị để trống."
        )
        azimuth_val = None
    # No numeric range check – accepts "IBC" or "120" equally

    # ── Required: Độ cao anten (now STRING) ───────────────────────────────────
    dca_val = _str_aware(row, excel_cols, "Độ cao anten", "Do cao anten", "do_cao_anten")
    if dca_val is None or dca_val is _CLEAR:
        errors_out.append(
            f"Row {row_num} ({label}): Trường bắt buộc 'Độ cao anten' bị để trống."
        )
        dca_val = None

    # ── Required: M-tilt (now STRING) ─────────────────────────────────────────
    mtilt_val = _str_aware(row, excel_cols, "M-tilt", "M-Tilt", "m_tilt")
    if mtilt_val is None or mtilt_val is _CLEAR:
        errors_out.append(
            f"Row {row_num} ({label}): Trường bắt buộc 'M-tilt' bị để trống."
        )
        mtilt_val = None

    # ── Required: E-Tilt (now STRING) ─────────────────────────────────────────
    etilt_val = _str_aware(row, excel_cols, "E-Tilt", "E-tilt", "e_tilt")
    if etilt_val is None or etilt_val is _CLEAR:
        errors_out.append(
            f"Row {row_num} ({label}): Trường bắt buộc 'E-Tilt' bị để trống."
        )
        etilt_val = None

    # ── Required: Vendor ─────────────────────────────────────────────────────
    vendor_val = _v_aware(row, excel_cols, "Vendor", "vendor")
    _check_dropdown(vendor_val, "Vendor", ALLOWED_VENDORS,
                    row_num, label, errors_out, required=True)

    # ── Optional dropdowns ────────────────────────────────────────────────────
    vung_val = _v_aware(row, excel_cols, "Vùng phủ sóng", "Vung phu song", "vung_phu_song")
    if vung_val and vung_val is not _CLEAR:
        _check_dropdown(vung_val, "Vùng phủ sóng", ALLOWED_VUNG,
                        row_num, label, errors_out)

    mimo_val = _v_aware(row, excel_cols, "MIMO", "mimo")
    if mimo_val and mimo_val is not _CLEAR:
        _check_dropdown(mimo_val, "MIMO", ALLOWED_MIMO,
                        row_num, label, errors_out)

    moran_val = _v_aware(row, excel_cols, "MORAN", "Moran", "moran")
    if moran_val and moran_val is not _CLEAR:
        _check_dropdown(moran_val, "MORAN", ALLOWED_MORAN,
                        row_num, label, errors_out)

    cell_vip_val = _v_aware(row, excel_cols, "Cell VIP", "cell_vip")
    if cell_vip_val and cell_vip_val is not _CLEAR:
        _check_dropdown(cell_vip_val, "Cell VIP", ALLOWED_CELL_VIP,
                        row_num, label, errors_out)

    loai_anten_val = _v_aware(row, excel_cols, "Loại Anten", "Loai Anten", "loai_anten")
    if (loai_anten_val and loai_anten_val is not _CLEAR and antenna_names):
        _check_db_dropdown(loai_anten_val, "Loại Anten", antenna_names,
                           row_num, label, errors_out)

    # ── Total Tilt (optional, now STRING) ─────────────────────────────────────
    total_tilt_val = _str_aware(row, excel_cols, "Total Tilt", "Total tilt", "total_tilt")

    return {
        "mien": mien, "tinh": tinh_official, "phuong_xa": phuong_xa_official,
        "site_name":     _v(row, "Site Name", "Site name", "site_name") or "",
        "site_name_old": _v_aware(row, excel_cols, "Site Name Old", "Site name old",
                                   "site_name_old", "Site Name (cũ)", "Site name (cu)"),
        "cell_name":     cell_name,
        "cell_name_old": _v_aware(row, excel_cols, "Cell Name Old", "Cell name old",
                                   "cell_name_old", "Cell Name (cũ)"),
        "cell_vip":      cell_vip_val,
        "moran":         moran_val,
        "lat": lat, "long": lon,
        "vung_phu_song": vung_val,
        "vendor":        vendor_val,
        "do_cao_anten":  dca_val,       # string now
        "azimuth":       azimuth_val,   # string now
        "m_tilt":        mtilt_val,     # string now
        "e_tilt":        etilt_val,     # string now
        "total_tilt":    total_tilt_val, # string now
        "loai_anten":    loai_anten_val,
        "baseband":      _v_aware(row, excel_cols, "Baseband", "baseband"),
        "rf":            _v_aware(row, excel_cols, "RF", "rf"),
        "cell_id":       _v_aware(row, excel_cols, "Cell ID", "cell_id"),
        "mimo":          mimo_val,
        "bbu_name":      _v_aware(row, excel_cols, "BBUname", "BBU Name", "bbu_name"),
        "cell_status":   _v_aware(row, excel_cols, "Cell status (at dump time)",
                                   "Cell status", "cell_status"),
        "cell_max_power": _v_aware(row, excel_cols, "Cell max power (dBm)",
                                    "Cell max power", "cell_max_power"),
    }


# ── Core cell Excel parser ─────────────────────────────────────────────────────

def _parse_cell_excel(
    file_bytes, Model, extra_fields_fn, db=None, dry_run=False
) -> Dict[str, Any]:
    df  = _read_excel(file_bytes)
    excel_cols: Set[str] = set(df.columns)
    geo = GeoCache(db) if db else None
    antenna_names = _get_antenna_names(db)
    rnc_names     = _get_rnc_names(db)

    to_create:         List[Dict] = []
    to_update:         List[Dict] = []
    sites_to_create:   List[Dict] = []
    errors:            List[str]  = []
    fatal_rows:        Set[int]   = set()
    pending_new_sites: Dict[str, Dict] = {}

    from app.models.site import Site

    for i, row in df.iterrows():
        row_num    = int(str(i)) + 2
        row_errors: List[str] = []

        cell_name_raw = _v(row, "Cell Name", "Cell name", "cell_name")
        site_name_raw = _v(row, "Site Name", "Site name", "site_name")

        if not cell_name_raw:
            errors.append(
                f"Row {row_num}: Trường bắt buộc 'Cell Name' bị để trống – bỏ qua dòng này."
            )
            fatal_rows.add(row_num)
            continue
        if not site_name_raw:
            errors.append(
                f"Row {row_num}: Trường bắt buộc 'Site Name' bị để trống – bỏ qua dòng này."
            )
            fatal_rows.add(row_num)
            continue

        common = _cell_common_aware(
            row, excel_cols, geo=geo,
            errors_out=row_errors, row_num=row_num,
            antenna_names=antenna_names,
            rnc_names=rnc_names,
        )

        if row_errors:
            errors.extend(row_errors)
            fatal_rows.add(row_num)
            continue

        cell_name     = common.get("cell_name", "")
        cell_name_old_val = common.get("cell_name_old", _CLEAR)
        cell_name_old = cell_name_old_val if cell_name_old_val is not _CLEAR else None
        site_name     = common.get("site_name", "")
        site_name_old_val = common.get("site_name_old", _CLEAR)
        site_name_old = site_name_old_val if site_name_old_val is not _CLEAR else None

        extra = extra_fields_fn(row, excel_cols, row_num, errors, rnc_names, antenna_names)
        if extra is None:
            fatal_rows.add(row_num)
            continue

        rec = {**common, **extra}

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
                    Model.cell_name == cell_name).first()
                if not existing_cell and cell_name_old:
                    existing_cell = db.query(Model).filter(
                        Model.cell_name == cell_name_old).first()
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
            to_create.append(_resolve_cell_create_rec(rec))

    return {
        "to_create":       to_create,
        "to_update":       to_update,
        "sites_to_create": sites_to_create,
        "errors":          errors,
        "dry_run":         dry_run,
        "fatal_count":     len(fatal_rows),
    }


def _resolve_cell_create_rec(rec: Dict) -> Dict:
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
    rnc_names = _get_rnc_names(db)

    def extra(row, excel_cols, row_num=0, errors=None, rnc_names_inner=None, antenna_names=None):
        if errors is None:
            errors = []
        row_errors: List[str] = []
        label = _v(row, "Cell Name", "Cell name", "cell_name") or f"row {row_num}"

        rnc_val = _v_aware(row, excel_cols, "RNC Name", "RNC name", "RNCNAME", "rnc_name")
        effective_rnc = rnc_names_inner or rnc_names
        if rnc_val and rnc_val is not _CLEAR and effective_rnc:
            _check_db_dropdown(rnc_val, "RNC Name", effective_rnc,
                               row_num, label, row_errors)

        chung_val = _v_aware(row, excel_cols, "Chung anten", "chung_anten")
        if chung_val and chung_val is not _CLEAR:
            _check_dropdown(chung_val, "Chung anten", ALLOWED_CHUNG_3G,
                            row_num, label, row_errors)

        if row_errors:
            errors.extend(row_errors)
            return None

        return {
            "chung_anten": chung_val,
            "arfcn":       _v_aware(row, excel_cols, "ARFCN", "arfcn"),
            "uarfcn":      _v_aware(row, excel_cols, "UARFCN", "uarfcn"),
            "lac":         _v_aware(row, excel_cols, "LAC", "lac"),
            "rac":         _v_aware(row, excel_cols, "RAC", "rac"),
            "psc":         _v_aware(row, excel_cols, "PSC", "psc"),
            "ura_id":      _v_aware(row, excel_cols, "URAId", "URA ID", "ura_id"),
            "cpich_power": _v_aware(row, excel_cols, "CPICH power (dBm)",
                                     "CPICH power", "cpich_power"),
            "rnc_name":    rnc_val,
        }
    return _parse_cell_excel(file_bytes, Cell3G, extra, db=db, dry_run=dry_run)


def parse_cell4g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_4g import Cell4G

    def extra(row, excel_cols, row_num=0, errors=None, rnc_names=None, antenna_names=None):
        if errors is None:
            errors = []
        row_errors: List[str] = []
        label = _v(row, "Cell Name", "Cell name", "cell_name") or f"row {row_num}"

        chung_val = _v_aware(row, excel_cols, "Chung anten", "chung_anten")
        if chung_val and chung_val is not _CLEAR:
            _check_dropdown(chung_val, "Chung anten", ALLOWED_CHUNG_4G,
                            row_num, label, row_errors)

        if row_errors:
            errors.extend(row_errors)
            return None

        return {
            "chung_anten":      chung_val,
            "enodeb_id":        _v_aware(row, excel_cols, "EnodeB ID", "enodeb_id"),
            "earfcn":           _v_aware(row, excel_cols, "EARFCN", "earfcn"),
            "tac":              _v_aware(row, excel_cols, "TAC", "tac"),
            "pci":              _v_aware(row, excel_cols, "PCI", "pci"),
            "root_sequence_id": _v_aware(row, excel_cols, "Root Sequence ID", "root_sequence_id"),
            "bandwidth":        _v_aware(row, excel_cols, "Bandwitdh", "Bandwidth", "bandwidth"),
            "eci":              _v_aware(row, excel_cols, "ECI", "eci"),
        }
    return _parse_cell_excel(file_bytes, Cell4G, extra, db=db, dry_run=dry_run)


def parse_cell5g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_5g import Cell5G

    def extra(row, excel_cols, row_num=0, errors=None, rnc_names=None, antenna_names=None):
        if errors is None:
            errors = []
        row_errors: List[str] = []
        label = _v(row, "Cell Name", "Cell name", "cell_name") or f"row {row_num}"

        mu_mimo_val = _v_aware(row, excel_cols, "MU-MIMO", "mu_mimo")
        if mu_mimo_val and mu_mimo_val is not _CLEAR:
            _check_dropdown(mu_mimo_val, "MU-MIMO", ALLOWED_MU_MIMO,
                            row_num, label, row_errors)

        if row_errors:
            errors.extend(row_errors)
            return None

        return {
            "gnodeb_id":        _v_aware(row, excel_cols, "gNodeB ID", "gnodeb_id"),
            "tac":              _v_aware(row, excel_cols, "TAC", "tac"),
            "pci":              _v_aware(row, excel_cols, "PCI", "pci"),
            "root_sequence_id": _v_aware(row, excel_cols, "Root Sequence ID", "root_sequence_id"),
            "ssb_arfcn":        _v_aware(row, excel_cols, "SSB-ARFCN", "ssb_arfcn"),
            "center_arfcn":     _v_aware(row, excel_cols, "Center-ARFCN", "center_arfcn"),
            "gscn":             _v_aware(row, excel_cols, "GSCN", "gscn"),
            "bandwidth":        _v_aware(row, excel_cols, "Bandwidth (MHz)", "Bandwidth", "bandwidth"),
            "nci":              _v_aware(row, excel_cols, "NCI", "nci"),
            "mu_mimo":          mu_mimo_val,
        }
    return _parse_cell_excel(file_bytes, Cell5G, extra, db=db, dry_run=dry_run)
