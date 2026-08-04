# update_cells_with_revision.py
"""
Daily cell data update script with revision history tracking.
Connects directly to the SiteLink DB, reads current cell values,
computes diffs, updates cells, and writes Cell*Revision records
— exactly like the FastAPI revision service does.
"""
import io
import json
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List

import numpy as np
import pandas as pd
import requests
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

# ── Configuration ─────────────────────────────────────────────────────
DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "database": "sitelink_db",
    "user": "sitelink",
    "password": "sitelink_pass",
}

DATABASE_URL = (
    f"postgresql://{DB_CONFIG['user']}:{DB_CONFIG['password']}"
    f"@{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['database']}"
)
engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)

# System actor (shown in revision history as "Script tự động")
SCRIPT_USER_ID   = None   # set to actual user.id if you want FK, or leave None
SCRIPT_USER_NAME = "Script tự động"
CHANGE_SOURCE    = "script"

# ── CSV Export URLs ───────────────────────────────────────────────────
URLS = {
    "ericsson_3g": "http://10.6.70.138/freework/ericsson_sitecell_umts_data.php?export=csv&token=c0b0575ce350303e9192335a9fa52ebac6bd33dc10a7ea47fe04b8bd1fbde71c",
    "huawei_3g":   "http://10.6.70.138/freework/huawei_sitecell_umts_data.php?export=csv&token=096b07429cbb8a83918ce713a3646c061ab1f13043037abaa683373c9c9b756b",
    "nokia_3g":    "http://10.6.70.138/freework/nokia_sitecell_3g_data.php?export=csv&token=3723ede0f68a6e08f7eb96d7a8d77835b8e1cc6c9b70ccfa8f86103077967dba",
    "ericsson_4g": "http://10.6.70.138/freework/ericsson_sitecell_lte_data.php?export=csv&token=c0b0575ce350303e9192335a9fa52ebac6bd33dc10a7ea47fe04b8bd1fbde71c",
    "huawei_4g":   "http://10.6.70.138/freework/huawei_sitecell_lte_data.php?export=csv&token=096b07429cbb8a83918ce713a3646c061ab1f13043037abaa683373c9c9b756b",
    "nokia_4g":    "http://10.6.70.138/freework/nokia_sitecell_4g_data.php?export=csv&token=3723ede0f68a6e08f7eb96d7a8d77835b8e1cc6c9b70ccfa8f86103077967dba",
    "ericsson_5g": "http://10.6.70.138/freework/ericsson_sitecell_nr_data.php?export=csv&token=c0b0575ce350303e9192335a9fa52ebac6bd33dc10a7ea47fe04b8bd1fbde71c",
    "huawei_5g":   "http://10.6.70.138/freework/huawei_sitecell_nr_data.php?export=csv&token=096b07429cbb8a83918ce713a3646c061ab1f13043037abaa683373c9c9b756b",
    "nokia_5g":    "http://10.6.70.138/freework/nokia_sitecell_5g_data.php?export=csv&token=3723ede0f68a6e08f7eb96d7a8d77835b8e1cc6c9b70ccfa8f86103077967dba",
}

# ── Revision diff helpers (mirrors app/services/revision.py) ──────────
def _normalize_for_diff(v: Any) -> Any:
    if v is None or v == "" or (isinstance(v, float) and np.isnan(v)):
        return None
    if isinstance(v, bool):
        return v
    if isinstance(v, (int, float)):
        # Round floats to avoid floating-point noise
        if isinstance(v, float):
            return round(v, 6)
        return v
    if isinstance(v, str):
        s = v.strip()
        if s == "" or s.lower() in ("none", "nan", "null"):
            return None
        # Normalize bool-like strings
        if s.lower() in ("true",):
            return True
        if s.lower() in ("false",):
            return False
        return s
    return v


def _diff(old: Dict, new: Dict) -> Dict:
    """Return {field: [old_val, new_val]} for every field that actually changed."""
    result = {}
    for k in set(old) | set(new):
        ov = _normalize_for_diff(old.get(k))
        nv = _normalize_for_diff(new.get(k))
        if ov != nv:
            result[k] = [old.get(k), new.get(k)]
    return result


def _safe(val) -> Optional[str]:
    """Convert a pandas/numpy value to Python str or None."""
    if val is None:
        return None
    if isinstance(val, float) and np.isnan(val):
        return None
    s = str(val).strip()
    if s in ("", "nan", "None", "NaN", "null"):
        return None
    return s


def _safe_float(val) -> Optional[float]:
    if val is None:
        return None
    try:
        f = float(val)
        return None if np.isnan(f) else f
    except (ValueError, TypeError):
        return None


# ── ORM-lite: read current cell rows directly via SQL ─────────────────
def fetch_current_cells(conn, table: str, cell_names: List[str]) -> Dict[str, Dict]:
    """
    Returns {cell_name: {col: val, ...}} for all matching rows.
    Uses raw SQL to avoid importing the full FastAPI app.
    """
    if not cell_names:
        return {}
    placeholders = ", ".join(f":n{i}" for i in range(len(cell_names)))
    params = {f"n{i}": n for i, n in enumerate(cell_names)}
    result = conn.execute(
        text(f"SELECT * FROM {table} WHERE cell_name IN ({placeholders})"),
        params,
    )
    rows = result.mappings().all()
    return {row["cell_name"]: dict(row) for row in rows}


def get_next_revision_no(conn, revision_table: str, cell_id_ref: int) -> int:
    result = conn.execute(
        text(f"SELECT COALESCE(MAX(revision_no), 0) FROM {revision_table} WHERE cell_id_ref = :id"),
        {"id": cell_id_ref},
    )
    return result.scalar() + 1


# ── Revision writers (one per technology) ────────────────────────────
def write_cell3g_revision(conn, cell_row: Dict, diff: Dict, rev_no: int, note: str = None):
    conn.execute(text("""
        INSERT INTO cell_3g_revisions (
            cell_id_ref, site_id, site_name, cell_name, revision_no,
            changed_by, changed_by_name, change_source, change_note,
            mien, tinh, phuong_xa, site_name_old, cell_name_old,
            cell_vip, moran, lat, long, vung_phu_song, vendor,
            do_cao_anten, azimuth, m_tilt, e_tilt, total_tilt,
            loai_anten, chung_anten, baseband, rf, cell_id,
            arfcn, uarfcn, lac, rac, psc, ura_id, mimo,
            cell_max_power, cpich_power, bbu_name, cell_status,
            changed_fields, created_at
        ) VALUES (
            :cell_id_ref, :site_id, :site_name, :cell_name, :revision_no,
            :changed_by, :changed_by_name, :change_source, :change_note,
            :mien, :tinh, :phuong_xa, :site_name_old, :cell_name_old,
            :cell_vip, :moran, :lat, :long, :vung_phu_song, :vendor,
            :do_cao_anten, :azimuth, :m_tilt, :e_tilt, :total_tilt,
            :loai_anten, :chung_anten, :baseband, :rf, :cell_id,
            :arfcn, :uarfcn, :lac, :rac, :psc, :ura_id, :mimo,
            :cell_max_power, :cpich_power, :bbu_name, :cell_status,
            :changed_fields, :created_at
        )
    """), {
        "cell_id_ref":   cell_row["id"],
        "site_id":       cell_row.get("site_id"),
        "site_name":     cell_row.get("site_name"),
        "cell_name":     cell_row.get("cell_name"),
        "revision_no":   rev_no,
        "changed_by":    SCRIPT_USER_ID,
        "changed_by_name": SCRIPT_USER_NAME,
        "change_source": CHANGE_SOURCE,
        "change_note":   note,
        "mien":          cell_row.get("mien"),
        "tinh":          cell_row.get("tinh"),
        "phuong_xa":     cell_row.get("phuong_xa"),
        "site_name_old": cell_row.get("site_name_old"),
        "cell_name_old": cell_row.get("cell_name_old"),
        "cell_vip":      cell_row.get("cell_vip"),
        "moran":         cell_row.get("moran"),
        "lat":           cell_row.get("lat"),
        "long":          cell_row.get("long"),
        "vung_phu_song": cell_row.get("vung_phu_song"),
        "vendor":        cell_row.get("vendor"),
        "do_cao_anten":  cell_row.get("do_cao_anten"),
        "azimuth":       cell_row.get("azimuth"),
        "m_tilt":        cell_row.get("m_tilt"),
        "e_tilt":        cell_row.get("e_tilt"),
        "total_tilt":    cell_row.get("total_tilt"),
        "loai_anten":    cell_row.get("loai_anten"),
        "chung_anten":   cell_row.get("chung_anten"),
        "baseband":      cell_row.get("baseband"),
        "rf":            cell_row.get("rf"),
        "cell_id":       cell_row.get("cell_id"),
        "arfcn":         cell_row.get("arfcn"),
        "uarfcn":        cell_row.get("uarfcn"),
        "lac":           cell_row.get("lac"),
        "rac":           cell_row.get("rac"),
        "psc":           cell_row.get("psc"),
        "ura_id":        cell_row.get("ura_id"),
        "mimo":          cell_row.get("mimo"),
        "cell_max_power": cell_row.get("cell_max_power"),
        "cpich_power":   cell_row.get("cpich_power"),
        "bbu_name":      cell_row.get("bbu_name"),
        "cell_status":   cell_row.get("cell_status"),
        "changed_fields": json.dumps(diff, ensure_ascii=False, default=str),
        "created_at":    datetime.now(timezone.utc),
    })


def write_cell4g_revision(conn, cell_row: Dict, diff: Dict, rev_no: int, note: str = None):
    conn.execute(text("""
        INSERT INTO cell_4g_revisions (
            cell_id_ref, site_id, site_name, cell_name, revision_no,
            changed_by, changed_by_name, change_source, change_note,
            mien, tinh, phuong_xa, site_name_old, cell_name_old,
            cell_vip, moran, lat, long, vung_phu_song, vendor,
            do_cao_anten, azimuth, m_tilt, e_tilt, total_tilt,
            loai_anten, chung_anten, baseband, rf,
            enodeb_id, cell_id, earfcn, tac, pci, root_sequence_id,
            mimo, bandwidth, cell_max_power, eci,
            bbu_name, cell_status,
            changed_fields, created_at
        ) VALUES (
            :cell_id_ref, :site_id, :site_name, :cell_name, :revision_no,
            :changed_by, :changed_by_name, :change_source, :change_note,
            :mien, :tinh, :phuong_xa, :site_name_old, :cell_name_old,
            :cell_vip, :moran, :lat, :long, :vung_phu_song, :vendor,
            :do_cao_anten, :azimuth, :m_tilt, :e_tilt, :total_tilt,
            :loai_anten, :chung_anten, :baseband, :rf,
            :enodeb_id, :cell_id, :earfcn, :tac, :pci, :root_sequence_id,
            :mimo, :bandwidth, :cell_max_power, :eci,
            :bbu_name, :cell_status,
            :changed_fields, :created_at
        )
    """), {
        "cell_id_ref":      cell_row["id"],
        "site_id":          cell_row.get("site_id"),
        "site_name":        cell_row.get("site_name"),
        "cell_name":        cell_row.get("cell_name"),
        "revision_no":      rev_no,
        "changed_by":       SCRIPT_USER_ID,
        "changed_by_name":  SCRIPT_USER_NAME,
        "change_source":    CHANGE_SOURCE,
        "change_note":      note,
        "mien":             cell_row.get("mien"),
        "tinh":             cell_row.get("tinh"),
        "phuong_xa":        cell_row.get("phuong_xa"),
        "site_name_old":    cell_row.get("site_name_old"),
        "cell_name_old":    cell_row.get("cell_name_old"),
        "cell_vip":         cell_row.get("cell_vip"),
        "moran":            cell_row.get("moran"),
        "lat":              cell_row.get("lat"),
        "long":             cell_row.get("long"),
        "vung_phu_song":    cell_row.get("vung_phu_song"),
        "vendor":           cell_row.get("vendor"),
        "do_cao_anten":     cell_row.get("do_cao_anten"),
        "azimuth":          cell_row.get("azimuth"),
        "m_tilt":           cell_row.get("m_tilt"),
        "e_tilt":           cell_row.get("e_tilt"),
        "total_tilt":       cell_row.get("total_tilt"),
        "loai_anten":       cell_row.get("loai_anten"),
        "chung_anten":      cell_row.get("chung_anten"),
        "baseband":         cell_row.get("baseband"),
        "rf":               cell_row.get("rf"),
        "enodeb_id":        cell_row.get("enodeb_id"),
        "cell_id":          cell_row.get("cell_id"),
        "earfcn":           cell_row.get("earfcn"),
        "tac":              cell_row.get("tac"),
        "pci":              cell_row.get("pci"),
        "root_sequence_id": cell_row.get("root_sequence_id"),
        "mimo":             cell_row.get("mimo"),
        "bandwidth":        cell_row.get("bandwidth"),
        "cell_max_power":   cell_row.get("cell_max_power"),
        "eci":              cell_row.get("eci"),
        "bbu_name":         cell_row.get("bbu_name"),
        "cell_status":      cell_row.get("cell_status"),
        "changed_fields":   json.dumps(diff, ensure_ascii=False, default=str),
        "created_at":       datetime.now(timezone.utc),
    })


def write_cell5g_revision(conn, cell_row: Dict, diff: Dict, rev_no: int, note: str = None):
    conn.execute(text("""
        INSERT INTO cell_5g_revisions (
            cell_id_ref, site_id, site_name, cell_name, revision_no,
            changed_by, changed_by_name, change_source, change_note,
            mien, tinh, phuong_xa, site_name_old, cell_name_old,
            cell_vip, moran, lat, long, vung_phu_song, vendor,
            do_cao_anten, azimuth, m_tilt, e_tilt, total_tilt,
            loai_anten, baseband, rf,
            gnodeb_id, cell_id, tac, pci, root_sequence_id, mimo,
            ssb_arfcn, center_arfcn, gscn, bandwidth,
            cell_max_power, nci, bbu_name, mu_mimo, cell_status,
            changed_fields, created_at
        ) VALUES (
            :cell_id_ref, :site_id, :site_name, :cell_name, :revision_no,
            :changed_by, :changed_by_name, :change_source, :change_note,
            :mien, :tinh, :phuong_xa, :site_name_old, :cell_name_old,
            :cell_vip, :moran, :lat, :long, :vung_phu_song, :vendor,
            :do_cao_anten, :azimuth, :m_tilt, :e_tilt, :total_tilt,
            :loai_anten, :baseband, :rf,
            :gnodeb_id, :cell_id, :tac, :pci, :root_sequence_id, :mimo,
            :ssb_arfcn, :center_arfcn, :gscn, :bandwidth,
            :cell_max_power, :nci, :bbu_name, :mu_mimo, :cell_status,
            :changed_fields, :created_at
        )
    """), {
        "cell_id_ref":      cell_row["id"],
        "site_id":          cell_row.get("site_id"),
        "site_name":        cell_row.get("site_name"),
        "cell_name":        cell_row.get("cell_name"),
        "revision_no":      rev_no,
        "changed_by":       SCRIPT_USER_ID,
        "changed_by_name":  SCRIPT_USER_NAME,
        "change_source":    CHANGE_SOURCE,
        "change_note":      note,
        "mien":             cell_row.get("mien"),
        "tinh":             cell_row.get("tinh"),
        "phuong_xa":        cell_row.get("phuong_xa"),
        "site_name_old":    cell_row.get("site_name_old"),
        "cell_name_old":    cell_row.get("cell_name_old"),
        "cell_vip":         cell_row.get("cell_vip"),
        "moran":            cell_row.get("moran"),
        "lat":              cell_row.get("lat"),
        "long":             cell_row.get("long"),
        "vung_phu_song":    cell_row.get("vung_phu_song"),
        "vendor":           cell_row.get("vendor"),
        "do_cao_anten":     cell_row.get("do_cao_anten"),
        "azimuth":          cell_row.get("azimuth"),
        "m_tilt":           cell_row.get("m_tilt"),
        "e_tilt":           cell_row.get("e_tilt"),
        "total_tilt":       cell_row.get("total_tilt"),
        "loai_anten":       cell_row.get("loai_anten"),
        "baseband":         cell_row.get("baseband"),
        "rf":               cell_row.get("rf"),
        "gnodeb_id":        cell_row.get("gnodeb_id"),
        "cell_id":          cell_row.get("cell_id"),
        "tac":              cell_row.get("tac"),
        "pci":              cell_row.get("pci"),
        "root_sequence_id": cell_row.get("root_sequence_id"),
        "mimo":             cell_row.get("mimo"),
        "ssb_arfcn":        cell_row.get("ssb_arfcn"),
        "center_arfcn":     cell_row.get("center_arfcn"),
        "gscn":             cell_row.get("gscn"),
        "bandwidth":        cell_row.get("bandwidth"),
        "cell_max_power":   cell_row.get("cell_max_power"),
        "nci":              cell_row.get("nci"),
        "bbu_name":         cell_row.get("bbu_name"),
        "mu_mimo":          cell_row.get("mu_mimo"),
        "cell_status":      cell_row.get("cell_status"),
        "changed_fields":   json.dumps(diff, ensure_ascii=False, default=str),
        "created_at":       datetime.now(timezone.utc),
    })


# ── Core update + revision logic ──────────────────────────────────────
REVISION_WRITERS = {
    "cells_3g": write_cell3g_revision,
    "cells_4g": write_cell4g_revision,
    "cells_5g": write_cell5g_revision,
}

REVISION_TABLES = {
    "cells_3g": "cell_3g_revisions",
    "cells_4g": "cell_4g_revisions",
    "cells_5g": "cell_5g_revisions",
}


def update_db_with_revision(table_name: str, df: pd.DataFrame, columns_to_update: List[str]):
    """
    For each row in df:
      1. Read current DB values
      2. Compute diff against new values
      3. If diff exists → UPDATE cell row + INSERT revision record
      4. If no diff → skip (no spurious revisions)
    All done in a single transaction per cell for atomicity.
    """
    if df.empty:
        print(f"⏩ No data to update {table_name}.")
        return

    print(f"\n🚀 Processing {table_name} ({len(df)} rows from source)...")

    revision_table  = REVISION_TABLES[table_name]
    revision_writer = REVISION_WRITERS[table_name]

    # Collect all cell names from incoming data
    valid_rows = df[df["cell_name"].notna()].copy()
    cell_names = valid_rows["cell_name"].astype(str).str.strip().tolist()

    stats = {"updated": 0, "skipped": 0, "not_found": 0, "errors": 0}

    with engine.begin() as conn:
        # Bulk fetch all current rows in one query
        current_map = fetch_current_cells(conn, table_name, cell_names)
        print(f"   Found {len(current_map)}/{len(cell_names)} cells in DB")

        for _, row in valid_rows.iterrows():
            cell_name = str(row["cell_name"]).strip()
            current = current_map.get(cell_name)

            if not current:
                stats["not_found"] += 1
                continue

            # Build new values dict (only tracked columns)
            new_vals: Dict[str, Any] = {}
            for col in columns_to_update:
                raw = row.get(col)
                if raw is None or (isinstance(raw, float) and np.isnan(raw)):
                    new_vals[col] = None
                else:
                    s = str(raw).strip()
                    new_vals[col] = None if s in ("", "nan", "None", "NaN") else s

            # Build old values dict (same columns from current DB row)
            old_vals: Dict[str, Any] = {}
            for col in columns_to_update:
                old_vals[col] = current.get(col)

            # Compute diff
            diff = _diff(old_vals, new_vals)

            if not diff:
                stats["skipped"] += 1
                continue  # No change — skip revision

            try:
                # 1. Update the cell row
                set_parts = [f"{col} = :{col}" for col in columns_to_update]
                set_parts.append("updated_at = NOW()")
                params = dict(new_vals)
                params["cell_name"] = cell_name

                conn.execute(
                    text(f"UPDATE {table_name} SET {', '.join(set_parts)} WHERE cell_name = :cell_name"),
                    params,
                )

                # 2. Build post-update snapshot for revision
                # Merge current row with new values for the full snapshot
                updated_row = dict(current)
                updated_row.update(new_vals)

                # 3. Get next revision number
                rev_no = get_next_revision_no(conn, revision_table, current["id"])

                # 4. Write revision record
                change_note = f"Script tự động cập nhật {len(diff)} trường: {', '.join(diff.keys())}"
                revision_writer(conn, updated_row, diff, rev_no, note=change_note)

                stats["updated"] += 1

            except Exception as e:
                stats["errors"] += 1
                print(f"   ❌ Error updating {cell_name}: {e}")

    print(f"   ✅ Done: {stats['updated']} updated, {stats['skipped']} unchanged, "
          f"{stats['not_found']} not found, {stats['errors']} errors")
    return stats


# ── Helper functions (unchanged from original) ────────────────────────
def fetch_csv(url, name):
    print(f"📥 Downloading {name}...")
    try:
        response = requests.get(url, timeout=120)
        response.raise_for_status()
        print(f"   ✅ Downloaded {name}")
        return pd.read_csv(io.BytesIO(response.content), low_memory=False)
    except Exception as e:
        print(f"   ❌ Failed {name}: {e}")
        return None


def clean_data(df):
    if df is None or df.empty:
        return pd.DataFrame()
    if "cell_name" in df.columns:
        df["cell_name"] = df["cell_name"].astype(str).str.strip()
    return df


def huawei_4g_bw_map(val):
    mapping = {"CELL_BW_N100": 20, "CELL_BW_N75": 15, "CELL_BW_N50": 10, "CELL_BW_N25": 5}
    return mapping.get(str(val).strip(), None)


# ── Load functions (unchanged from original) ──────────────────────────
def load_3g():
    frames = []

    df = fetch_csv(URLS["ericsson_3g"], "Ericsson 3G")
    if df is not None and not df.empty:
        t = pd.DataFrame()
        t["cell_name"]     = df.get("rnc_UtranCellId")
        t["cell_id"]       = df.get("rnc_cId")
        t["uarfcn"]        = df.get("rnc_uarfcnDl")
        t["psc"]           = df.get("rnc_primaryScrCode")
        t["mimo"]          = None
        t["baseband"]      = df.get("rnc_name")
        t["lac"]           = df.get("rnc_lac")
        t["rac"]           = df.get("rnc_rac")
        t["ura_id"]        = df.get("rnc_ura_id")
        t["cell_max_power"]= pd.to_numeric(df.get("maximumTransmissionPower"), errors="coerce") / 10
        t["cpich_power"]   = df.get("primaryCpichPower")
        t["rf"]            = df.get("hw_productName")
        t["bbu_name"]      = df.get("node_name")
        t["cell_status"]   = df.get("rnc_adminState")
        frames.append(t)

    df = fetch_csv(URLS["huawei_3g"], "Huawei 3G")
    if df is not None and not df.empty:
        t = pd.DataFrame()
        t["cell_name"]     = df.get("CELLNAME")
        t["cell_id"]       = df.get("CELLID")
        t["uarfcn"]        = df.get("UARFCN DOWNLINK")
        t["psc"]           = df.get("PSCRAMBCODE")
        t["mimo"]          = None
        t["baseband"]      = df.get("RNCname")
        t["lac"]           = df.get("LAC")
        t["rac"]           = df.get("RAC")
        t["ura_id"]        = None
        t["cell_max_power"]= pd.to_numeric(df.get("RNC UCELL MAXTXPOWER"), errors="coerce") / 10
        t["cpich_power"]   = None
        t["rf"]            = df.get("RRU ManufacturerData", pd.Series(dtype=str)).astype(str).str.split(",").str[0]
        t["bbu_name"]      = df.get("NEname")
        t["cell_status"]   = df.get("BLKSTATUS")
        frames.append(t)

    df = fetch_csv(URLS["nokia_3g"], "Nokia 3G")
    if df is not None and not df.empty:
        t = pd.DataFrame()
        t["cell_name"]     = df.get("name")
        t["cell_id"]       = df.get("CId")
        t["uarfcn"]        = df.get("UARFCN")
        t["psc"]           = df.get("PriScrCode")
        t["mimo"]          = None
        t["baseband"]      = df.get("RNCName")
        t["lac"]           = df.get("LAC")
        t["rac"]           = df.get("RAC")
        t["ura_id"]        = df.get("URAId")
        t["cell_max_power"]= pd.to_numeric(df.get("PtxCellMax"), errors="coerce") / 10
        t["cpich_power"]   = df.get("PtxPrimaryCPICH")
        t["rf"]            = df.get("RRU productName")
        t["bbu_name"]      = df.get("WBTS_name")
        t["cell_status"]   = df.get("AdminCellState")
        frames.append(t)

    return clean_data(
        pd.concat(frames).drop_duplicates("cell_name") if frames else pd.DataFrame()
    )


def load_4g():
    frames = []

    df = fetch_csv(URLS["ericsson_4g"], "Ericsson 4G")
    if df is not None and not df.empty:
        t = pd.DataFrame()
        t["cell_name"]       = df.get("eUtranCellFDDId")
        t["cell_id"]         = df.get("eNBId").astype(str) + "-" + df.get("cellId").astype(str)
        t["earfcn"]          = df.get("earfcndl")
        t["pci"]             = df.get("physicalLayerCellId")
        t["root_sequence_id"]= df.get("rachRootSequence")
        tx = pd.to_numeric(df.get("noOfUsedTxAntennas"), errors="coerce").fillna(0)
        t["mimo"]            = (tx * tx).astype(int).astype(str)
        t["tac"]             = df.get("tac")
        t["bandwidth"]       = pd.to_numeric(df.get("dlChannelBandwidth"), errors="coerce") / 1000
        t["cell_max_power"]  = pd.to_numeric(df.get("maximumTransmissionPower"), errors="coerce") / 10
        t["eci"]             = (pd.to_numeric(df.get("eNBId"), errors="coerce") * 256
                                + pd.to_numeric(df.get("cellId"), errors="coerce"))
        t["rf"]              = df.get("hw_productName")
        t["bbu_name"]        = df.get("node")
        t["cell_status"]     = df.get("administrativeState")
        frames.append(t)

    df = fetch_csv(URLS["huawei_4g"], "Huawei 4G")
    if df is not None and not df.empty:
        t = pd.DataFrame()
        t["cell_name"]       = df.get("CELLNAME")
        t["cell_id"]         = df.get("ENODEBID").astype(str) + "-" + df.get("CELLID").astype(str)
        t["earfcn"]          = df.get("DLEARFCN")
        t["pci"]             = df.get("Physical cell ID")
        t["root_sequence_id"]= df.get("Root sequence index")
        t["mimo"]            = df.get("TXRXMODE")
        t["tac"]             = df.get("TAC")
        t["bandwidth"]       = df.get("DLBANDWIDTH").apply(huawei_4g_bw_map)
        t["cell_max_power"]  = pd.to_numeric(df.get("Maximum transmit power (0.1dBm)"), errors="coerce") / 10
        t["eci"]             = (pd.to_numeric(df.get("ENODEBID"), errors="coerce") * 256
                                + pd.to_numeric(df.get("CELLID"), errors="coerce"))
        t["rf"]              = df.get("RRU ManufacturerData", pd.Series(dtype=str)).astype(str).str.split(",").str[0]
        t["bbu_name"]        = df.get("NE")
        t["cell_status"]     = df.get("Cell admin state")
        frames.append(t)

    df = fetch_csv(URLS["nokia_4g"], "Nokia 4G")
    if df is not None and not df.empty:
        t = pd.DataFrame()
        t["cell_name"]       = df.get("name", df.get("cellName"))
        t["cell_id"]         = df.get("enodebid").astype(str) + "-" + df.get("lcrId").astype(str)
        t["earfcn"]          = df.get("earfcnDL")
        t["pci"]             = df.get("phyCellId")
        t["root_sequence_id"]= df.get("rootSeqIndex")
        t["mimo"]            = df.get("Cell nTX").astype(str) + "*" + df.get("Cell nRX").astype(str)
        t["tac"]             = df.get("tac")
        t["bandwidth"]       = pd.to_numeric(df.get("dlChBw"), errors="coerce") / 10
        t["cell_max_power"]  = pd.to_numeric(df.get("pMax_0_1dBm"), errors="coerce") / 10
        t["eci"]             = (pd.to_numeric(df.get("enodebid"), errors="coerce") * 256
                                + pd.to_numeric(df.get("lcrId"), errors="coerce"))
        t["rf"]              = df.get("RRU productName")
        t["bbu_name"]        = df.get("MRBTS_btsname")
        t["cell_status"]     = df.get("blockingState")
        frames.append(t)

    return clean_data(
        pd.concat(frames).drop_duplicates("cell_name") if frames else pd.DataFrame()
    )


def load_5g():
    frames = []

    df = fetch_csv(URLS["ericsson_5g"], "Ericsson 5G")
    if df is not None and not df.empty:
        t = pd.DataFrame()
        t["cell_name"]       = df.get("NRCellCUId")
        t["cell_id"]         = df.get("gNodeBId").astype(str) + "-" + df.get("NRCellCU_LocalCellId").astype(str)
        t["ssb_arfcn"]       = df.get("ARFCN_DL_Cell")
        t["center_arfcn"]    = df.get("ARFCN_DL_SC")
        t["pci"]             = df.get("PCI")
        t["root_sequence_id"]= df.get("rachRootSequence")
        tx = pd.to_numeric(df.get("NoOfUsedTxAntennas"), errors="coerce").fillna(0)
        t["mimo"]            = (tx * tx).astype(int).astype(str)
        t["gscn"]            = None
        t["tac"]             = df.get("TAC")
        t["bandwidth"]       = pd.to_numeric(df.get("BSChannelBwDL"), errors="coerce")
        t["cell_max_power"]  = pd.to_numeric(df.get("ConfiguredMaxTxPower"), errors="coerce")
        t["nci"]             = df.get("NRCellCU_nCI")
        t["rf"]              = df.get("RF_ProductNames")
        t["bbu_name"]        = df.get("Node")
        t["mu_mimo"]         = None
        t["cell_status"]     = df.get("AdministrativeState_SC")
        frames.append(t)

    df = fetch_csv(URLS["huawei_5g"], "Huawei 5G")
    if df is not None and not df.empty:
        t = pd.DataFrame()
        t["cell_name"]       = df.get("CELLNAME")
        t["cell_id"]         = df.get("GNBID").astype(str) + "-" + df.get("CELLID").astype(str)
        t["ssb_arfcn"]       = None
        t["center_arfcn"]    = df.get("DLNARFCN")
        t["pci"]             = df.get("Physical cell ID")
        t["root_sequence_id"]= df.get("Logical Root sequence index")
        t["mimo"]            = df.get("TXRXMODE")
        t["gscn"]            = df.get("SSB GSCN")
        t["tac"]             = df.get("TAC")
        t["bandwidth"]       = df.get("DLBANDWIDTH").astype(str).str.extract(r"(\d+)").astype(float)
        t["cell_max_power"]  = None
        gnb     = pd.to_numeric(df.get("GNBID"),       errors="coerce")
        gnb_len = pd.to_numeric(df.get("GNBIDLENGTH"),  errors="coerce")
        cid     = pd.to_numeric(df.get("CELLID"),       errors="coerce")
        t["nci"]             = gnb * (2 ** (36 - gnb_len)) + cid
        t["rf"]              = df.get("RRU ManufacturerData", pd.Series(dtype=str)).astype(str).str.split(",").str[0]
        t["bbu_name"]        = df.get("NE")
        t["mu_mimo"]         = None
        t["cell_status"]     = df.get("Cell admin state")
        frames.append(t)

    df = fetch_csv(URLS["nokia_5g"], "Nokia 5G")
    if df is not None and not df.empty:
        t = pd.DataFrame()
        t["cell_name"]       = df.get("NRCELL_cellName")
        t["cell_id"]         = df.get("btsid").astype(str) + "-" + df.get("lcrId").astype(str)
        t["ssb_arfcn"]       = None
        t["center_arfcn"]    = df.get("nrarfcn")
        t["pci"]             = df.get("physCellId")
        t["root_sequence_id"]= df.get("prachRootSequenceIndex")
        t["mimo"]            = df.get("mMimoAntArrayMode")
        t["gscn"]            = df.get("gscnOrSsPbchArfcn")
        t["tac"]             = None
        t["bandwidth"]       = df.get("chBw").astype(str).str.extract(r"(\d+)").astype(float)
        tx_count = df.get("mMimoAntArrayMode").astype(str).str.extract(r"(\d+)TRX").astype(float).fillna(1)[0]
        t["cell_max_power"]  = (pd.to_numeric(df.get("pMax_0_1dBm"), errors="coerce") / 10) * tx_count
        t["nci"]             = df.get("nrCellIdentity")
        t["rf"]              = df.get("RRU productName")
        t["bbu_name"]        = df.get("MRBTS_btsname")
        t["mu_mimo"]         = df.get("nrCellType")
        t["cell_status"]     = df.get("administrativeState")
        frames.append(t)

    return clean_data(
        pd.concat(frames).drop_duplicates("cell_name") if frames else pd.DataFrame()
    )


# ── Main ──────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("=" * 60)
    print(f"SiteLink Cell Update Script — {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 60)

    cols_3g = [
        "cell_id", "uarfcn", "psc", "mimo", "baseband",
        "lac", "rac", "ura_id", "cell_max_power", "cpich_power",
        "rf", "bbu_name", "cell_status",
    ]
    cols_4g = [
        "cell_id", "earfcn", "pci", "root_sequence_id", "mimo",
        "tac", "bandwidth", "cell_max_power", "eci",
        "rf", "bbu_name", "cell_status",
    ]
    cols_5g = [
        "cell_id", "ssb_arfcn", "center_arfcn", "pci", "root_sequence_id",
        "mimo", "gscn", "tac", "bandwidth", "cell_max_power",
        "nci", "rf", "bbu_name", "mu_mimo", "cell_status",
    ]

    print("\n--- 3G ---")
    update_db_with_revision("cells_3g", load_3g(), cols_3g)

    print("\n--- 4G ---")
    update_db_with_revision("cells_4g", load_4g(), cols_4g)

    print("\n--- 5G ---")
    update_db_with_revision("cells_5g", load_5g(), cols_5g)

    print("\n✅ All done.")
