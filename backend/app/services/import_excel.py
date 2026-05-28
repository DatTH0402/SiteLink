import io
from typing import List, Dict, Any

import pandas as pd


def _read_excel(file_bytes: bytes) -> pd.DataFrame:
    df = pd.read_excel(io.BytesIO(file_bytes), dtype=str)
    df = df.where(pd.notna(df), None)
    # Strip whitespace from column names
    df.columns = [str(c).strip() for c in df.columns]
    return df


def _v(row, *keys):
    """Try multiple possible column name variants, return first match."""
    for key in keys:
        val = row.get(key)
        if val is not None and str(val).strip() not in ("", "nan", "None"):
            return str(val).strip()
    return None


def _bool(row, *keys):
    v = _v(row, *keys)
    return str(v).strip().lower() == "x" if v else False


def _float(row, *keys):
    v = _v(row, *keys)
    if v is None:
        return None
    try:
        return float(v)
    except (ValueError, TypeError):
        return None


def parse_site_excel(file_bytes: bytes) -> List[Dict[str, Any]]:
    df = _read_excel(file_bytes)
    records = []
    for _, row in df.iterrows():
        site_name = _v(row, "Site name", "Site Name", "site_name", "SITE NAME")
        ma_ptm    = _v(row, "Mã PTM", "Ma PTM", "ma_ptm", "MaPTM", "PTM")
        mien      = _v(row, "Miền", "Mien", "MIEN", "mien")
        tinh      = _v(row, "Tỉnh", "Tinh", "TINH", "tinh")

        if not site_name:
            records.append({"__error__": "Missing 'Site name' column value"})
            continue
        if not mien:
            records.append({"__error__": f"Row site '{site_name}': Missing 'Mien' value"})
            continue
        if not tinh:
            records.append({"__error__": f"Row site '{site_name}': Missing 'Tinh' value"})
            continue

        records.append({
            "mien":         mien,
            "tinh":         tinh,
            "phuong_xa":    _v(row, "Phường xã", "Phuong xa", "Phường Xã", "phuong_xa"),
            "site_name_cu": _v(row, "Site name (cũ)", "Site name (cu)", "Site Name (cũ)"),
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
                "Node truyen dan only",
                "node_truyen_dan_only",
            ),
            "phan_loai_tram": _v(
                row,
                "IBC/ Macro outdoor / IBC + Outdoor / miniDAS / Smallcell",
                "IBC/Macro outdoor/IBC + Outdoor/miniDAS/Smallcell",
                "Phan loai tram",
                "phan_loai_tram",
            ),
            "tram_phu_song_tsca": _v(
                row,
                "Trạm phủ sóng TSCA (x)",
                "Tram phu song TSCA",
                "tram_phu_song_tsca",
            ),
            "moran_3g": _v(
                row,
                "TRẠM MORAN 3G (VNPT HOST, MBF HOST)",
                "MORAN 3G", "moran_3g",
            ),
            "moran_4g": _v(
                row,
                "TRẠM MORAN 4G (VNPT HOST, MBF HOST)",
                "MORAN 4G", "moran_4g",
            ),
            "moran_5g": _v(
                row,
                "TRẠM MORAN 5G (VNPT HOST, MBF HOST)",
                "MORAN 5G", "moran_5g",
            ),
            "ma_ptm": ma_ptm or "",
            "do_cao_dinh_cot_anten": _float(
                row,
                "Độ cao đỉnh cột anten (m) đến mặt đất",
                "Do cao dinh cot anten (m) den mat dat",
                "Do cao dinh cot anten",
                "do_cao_dinh_cot_anten",
            ),
            "do_cao_cot_anten": _float(
                row,
                "Độ cao cột anten (đỉnh cột anten (m) đến mặt sàn)",
                "Do cao cot anten (dinh cot anten (m) den mat san)",
                "Do cao cot anten",
                "do_cao_cot_anten",
            ),
            "dia_chi": _v(row, "Địa chỉ", "Dia chi", "dia_chi"),
            "ghi_chu": _v(row, "Ghi chú", "Ghi chu", "ghi_chu"),
        })
    return records


def _cell_common(row) -> Dict[str, Any]:
    return {
        "mien":     _v(row, "Miền", "Mien", "mien"),
        "tinh":     _v(row, "Tỉnh", "Tinh", "tinh"),
        "phuong_xa": _v(row, "Phường xã", "Phuong xa", "phuong_xa"),
        "site_name": _v(row, "Site Name", "Site name", "site_name") or "",
        "cell_name": _v(row, "Cell Name", "Cell name", "cell_name") or "",
        "cell_vip":  _v(row, "Cell VIP",  "cell_vip"),
        "moran":     _v(row, "MORAN", "Moran", "moran"),
        "lat":       _float(row, "Lat", "LAT", "lat"),
        "long":      _float(row, "Long", "LONG", "long"),
        "vung_phu_song": _v(row, "Vùng phủ sóng", "Vung phu song", "vung_phu_song"),
        "vendor":    _v(row, "Vendor", "vendor"),
        "do_cao_anten": _float(row, "Độ cao anten", "Do cao anten", "do_cao_anten"),
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


def parse_cell3g_excel(file_bytes: bytes) -> List[Dict[str, Any]]:
    df = _read_excel(file_bytes)
    records = []
    for _, row in df.iterrows():
        rec = _cell_common(row)
        rec.update({
            "chung_anten": _v(row, "Chung anten", "chung_anten"),
            "arfcn":       _v(row, "ARFCN", "arfcn"),
            "psc":         _v(row, "PSC",   "psc"),
        })
        records.append(rec)
    return records


def parse_cell4g_excel(file_bytes: bytes) -> List[Dict[str, Any]]:
    df = _read_excel(file_bytes)
    records = []
    for _, row in df.iterrows():
        rec = _cell_common(row)
        rec.update({
            "chung_anten":     _v(row, "Chung anten",      "chung_anten"),
            "earfcn":          _v(row, "EARFCN",            "earfcn"),
            "pci":             _v(row, "PCI",               "pci"),
            "root_sequence_id": _v(row, "Root Sequence ID", "root_sequence_id"),
        })
        records.append(rec)
    return records


def parse_cell5g_excel(file_bytes: bytes) -> List[Dict[str, Any]]:
    df = _read_excel(file_bytes)
    records = []
    for _, row in df.iterrows():
        rec = _cell_common(row)
        rec.update({
            "nr_arfcn":        _v(row, "NR-ARFCN",         "nr_arfcn"),
            "pci":             _v(row, "PCI",               "pci"),
            "root_sequence_id": _v(row, "Root Sequence ID", "root_sequence_id"),
        })
        records.append(rec)
    return records