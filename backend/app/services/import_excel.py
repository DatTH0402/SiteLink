import io
from typing import List, Dict, Any

import pandas as pd


def parse_site_excel(file_bytes: bytes) -> List[Dict[str, Any]]:
    df = pd.read_excel(io.BytesIO(file_bytes), dtype=str)
    df = df.where(pd.notna(df), None)
    records = []
    for _, row in df.iterrows():
        def f(col):
            v = row.get(col)
            return None if v is None or str(v).strip() == "" else v

        records.append({
            "mien":         f("Mien") or f("Mien"),
            "tinh":         f("Tinh"),
            "phuong_xa":    f("Phuong xa"),
            "site_name_cu": f("Site name (cu)"),
            "site_name":    f("Site name"),
            "site_vip":     f("Site VIP"),
            "lat":          float(f("Lat")) if f("Lat") else None,
            "long":         float(f("Long")) if f("Long") else None,
            "tram_2g":      str(f("Tram 2G")).strip().lower() == "x",
            "tram_3g":      str(f("Tram 3G")).strip().lower() == "x",
            "tram_4g":      str(f("Tram 4G")).strip().lower() == "x",
            "tram_5g":      str(f("Tram 5G")).strip().lower() == "x",
            "repeater":     str(f("Repeater")).strip().lower() == "x",
            "booster":      str(f("Booster")).strip().lower() == "x",
            "node_truyen_dan_only": str(f("Node truyen dan only")).strip().lower() == "x",
            "phan_loai_tram":   f("Phan loai tram"),
            "tram_phu_song_tsca": f("Tram phu song TSCA"),
            "moran_3g":     f("MORAN 3G"),
            "moran_4g":     f("MORAN 4G"),
            "moran_5g":     f("MORAN 5G"),
            "ma_ptm":       f("Ma PTM") or "",
            "do_cao_dinh_cot_anten": float(f("Do cao dinh cot anten")) if f("Do cao dinh cot anten") else None,
            "do_cao_cot_anten":      float(f("Do cao cot anten")) if f("Do cao cot anten") else None,
            "dia_chi":      f("Dia chi"),
            "ghi_chu":      f("Ghi chu"),
        })
    return records


def _cell_common(row) -> Dict[str, Any]:
    def f(col):
        v = row.get(col)
        return None if v is None or str(v).strip() == "" else v

    return {
        "mien":         f("Mien"),
        "tinh":         f("Tinh"),
        "phuong_xa":    f("Phuong xa"),
        "site_name":    f("Site Name") or f("Site name") or "",
        "cell_name":    f("Cell Name") or f("Cell name") or "",
        "cell_vip":     f("Cell VIP"),
        "moran":        f("MORAN"),
        "lat":          float(f("Lat")) if f("Lat") else None,
        "long":         float(f("Long")) if f("Long") else None,
        "vung_phu_song": f("Vung phu song"),
        "vendor":       f("Vendor"),
        "do_cao_anten": float(f("Do cao anten")) if f("Do cao anten") else None,
        "azimuth":      float(f("Azimuth")) if f("Azimuth") else None,
        "m_tilt":       float(f("M-tilt")) if f("M-tilt") else None,
        "e_tilt":       float(f("E-Tilt")) if f("E-Tilt") else None,
        "total_tilt":   float(f("Total Tilt")) if f("Total Tilt") else None,
        "loai_anten":   f("Loai Anten"),
        "baseband":     f("Baseband"),
        "rf":           f("RF"),
        "cell_id":      f("Cell ID"),
        "mimo":         f("MIMO"),
    }


def parse_cell3g_excel(file_bytes: bytes) -> List[Dict[str, Any]]:
    df = pd.read_excel(io.BytesIO(file_bytes), dtype=str)
    df = df.where(pd.notna(df), None)
    records = []
    for _, row in df.iterrows():
        def f(col):
            v = row.get(col)
            return None if v is None or str(v).strip() == "" else v
        rec = _cell_common(row)
        rec.update({
            "chung_anten": f("Chung anten"),
            "arfcn":       f("ARFCN"),
            "psc":         f("PSC"),
        })
        records.append(rec)
    return records


def parse_cell4g_excel(file_bytes: bytes) -> List[Dict[str, Any]]:
    df = pd.read_excel(io.BytesIO(file_bytes), dtype=str)
    df = df.where(pd.notna(df), None)
    records = []
    for _, row in df.iterrows():
        def f(col):
            v = row.get(col)
            return None if v is None or str(v).strip() == "" else v
        rec = _cell_common(row)
        rec.update({
            "chung_anten":     f("Chung anten"),
            "earfcn":          f("EARFCN"),
            "pci":             f("PCI"),
            "root_sequence_id": f("Root Sequence ID"),
        })
        records.append(rec)
    return records


def parse_cell5g_excel(file_bytes: bytes) -> List[Dict[str, Any]]:
    df = pd.read_excel(io.BytesIO(file_bytes), dtype=str)
    df = df.where(pd.notna(df), None)
    records = []
    for _, row in df.iterrows():
        def f(col):
            v = row.get(col)
            return None if v is None or str(v).strip() == "" else v
        rec = _cell_common(row)
        rec.update({
            "nr_arfcn":        f("NR-ARFCN"),
            "pci":             f("PCI"),
            "root_sequence_id": f("Root Sequence ID"),
        })
        records.append(rec)
    return records
