"""
test_script_revision.py
-----------------------
Test script for revision tracking feature.

Simulates what update_cells_with_revision.py does, but with
CONTROLLED test data instead of live CSV downloads.

Test case:
  - Cell: QNHASH27DM3EA (Ericsson 3G)
  - Field changed: uarfcn → 123456
  - Expected: revision record written with diff {uarfcn: [old_val, 123456]}
"""
import json
import numpy as np
import pandas as pd
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

# ── Configuration (same as main script) ───────────────────────────────
DB_CONFIG = {
    "host":     "localhost",
    "port":     5432,
    "database": "sitelink_db",
    "user":     "sitelink",
    "password": "sitelink_pass",
}

DATABASE_URL = (
    f"postgresql://{DB_CONFIG['user']}:{DB_CONFIG['password']}"
    f"@{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['database']}"
)

engine = create_engine(DATABASE_URL, pool_pre_ping=True)

SCRIPT_USER_ID   = None
SCRIPT_USER_NAME = "Script tự động [TEST]"
CHANGE_SOURCE    = "script"

TARGET_CELL_NAME = "QNHASH27DM3EA"
TEST_UARFCN      = "12345"

# ── Diff helpers (copied from main script) ────────────────────────────
def _normalize_for_diff(v: Any) -> Any:
    if v is None or (isinstance(v, float) and np.isnan(v)):
        return None
    if isinstance(v, bool):
        return v
    if isinstance(v, float):
        return round(v, 6)
    if isinstance(v, int):
        return v
    if isinstance(v, str):
        s = v.strip()
        if s in ("", "none", "nan", "null", "None", "NaN"):
            return None
        return s
    return v


def _diff(old: Dict, new: Dict) -> Dict:
    result = {}
    for k in set(old) | set(new):
        ov = _normalize_for_diff(old.get(k))
        nv = _normalize_for_diff(new.get(k))
        if ov != nv:
            result[k] = [old.get(k), new.get(k)]
    return result


# ── Fetch current cell from DB ────────────────────────────────────────
def fetch_cell(conn, cell_name: str) -> Optional[Dict]:
    result = conn.execute(
        text("SELECT * FROM cells_3g WHERE cell_name = :name"),
        {"name": cell_name},
    )
    row = result.mappings().first()
    return dict(row) if row else None


def get_next_revision_no(conn, cell_id_ref: int) -> int:
    result = conn.execute(
        text(
            "SELECT COALESCE(MAX(revision_no), 0) "
            "FROM cell_3g_revisions WHERE cell_id_ref = :id"
        ),
        {"id": cell_id_ref},
    )
    return result.scalar() + 1


# ── Write 3G revision ─────────────────────────────────────────────────
def write_cell3g_revision(conn, cell_row: Dict, diff: Dict,
                           rev_no: int, note: str = None):
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
        "cell_id_ref":    cell_row["id"],
        "site_id":        cell_row.get("site_id"),
        "site_name":      cell_row.get("site_name"),
        "cell_name":      cell_row.get("cell_name"),
        "revision_no":    rev_no,
        "changed_by":     SCRIPT_USER_ID,
        "changed_by_name": SCRIPT_USER_NAME,
        "change_source":  CHANGE_SOURCE,
        "change_note":    note,
        "mien":           cell_row.get("mien"),
        "tinh":           cell_row.get("tinh"),
        "phuong_xa":      cell_row.get("phuong_xa"),
        "site_name_old":  cell_row.get("site_name_old"),
        "cell_name_old":  cell_row.get("cell_name_old"),
        "cell_vip":       cell_row.get("cell_vip"),
        "moran":          cell_row.get("moran"),
        "lat":            cell_row.get("lat"),
        "long":           cell_row.get("long"),
        "vung_phu_song":  cell_row.get("vung_phu_song"),
        "vendor":         cell_row.get("vendor"),
        "do_cao_anten":   cell_row.get("do_cao_anten"),
        "azimuth":        cell_row.get("azimuth"),
        "m_tilt":         cell_row.get("m_tilt"),
        "e_tilt":         cell_row.get("e_tilt"),
        "total_tilt":     cell_row.get("total_tilt"),
        "loai_anten":     cell_row.get("loai_anten"),
        "chung_anten":    cell_row.get("chung_anten"),
        "baseband":       cell_row.get("baseband"),
        "rf":             cell_row.get("rf"),
        "cell_id":        cell_row.get("cell_id"),
        "arfcn":          cell_row.get("arfcn"),
        "uarfcn":         cell_row.get("uarfcn"),
        "lac":            cell_row.get("lac"),
        "rac":            cell_row.get("rac"),
        "psc":            cell_row.get("psc"),
        "ura_id":         cell_row.get("ura_id"),
        "mimo":           cell_row.get("mimo"),
        "cell_max_power": cell_row.get("cell_max_power"),
        "cpich_power":    cell_row.get("cpich_power"),
        "bbu_name":       cell_row.get("bbu_name"),
        "cell_status":    cell_row.get("cell_status"),
        "changed_fields": json.dumps(diff, ensure_ascii=False, default=str),
        "created_at":     datetime.now(timezone.utc),
    })


# ── Columns the script is responsible for updating ────────────────────
COLS_3G = [
    "cell_id", "uarfcn", "psc", "mimo", "baseband",
    "lac", "rac", "ura_id", "cell_max_power", "cpich_power",
    "rf", "bbu_name", "cell_status",
]


# ── Main test logic ───────────────────────────────────────────────────
def main():
    print("=" * 60)
    print(f" TEST: Script Revision Tracking")
    print(f" Cell : {TARGET_CELL_NAME}")
    print(f" Field: uarfcn → {TEST_UARFCN}")
    print(f" Time : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 60)

    with engine.begin() as conn:
        # ── Step 1: Read current DB state ────────────────────────────
        print(f"\n[1] Reading current state of '{TARGET_CELL_NAME}' from DB...")
        current = fetch_cell(conn, TARGET_CELL_NAME)

        if not current:
            print(f"\n❌ Cell '{TARGET_CELL_NAME}' not found in cells_3g table.")
            print("   Verify the cell name is correct and exists in the DB.")
            return

        print(f"   ✓ Found cell id={current['id']}")
        print(f"   Current uarfcn = {current.get('uarfcn')!r}")
        print(f"   Current bbu_name = {current.get('bbu_name')!r}")
        print(f"   Current cell_status = {current.get('cell_status')!r}")

        # ── Step 2: Build new values (same as script would produce) ──
        # We keep all COLS_3G values the same as current DB,
        # but override uarfcn with our test value.
        new_vals: Dict[str, Any] = {}
        for col in COLS_3G:
            # Copy current value as-is (simulates "no change" for other cols)
            val = current.get(col)
            if val is None:
                new_vals[col] = None
            else:
                s = str(val).strip()
                new_vals[col] = None if s in ("", "nan", "None", "NaN") else s

        # Override just uarfcn for the test
        new_vals["uarfcn"] = TEST_UARFCN

        print(f"\n[2] New values to apply:")
        print(f"   uarfcn: {current.get('uarfcn')!r} → {TEST_UARFCN!r}")

        # ── Step 3: Compute diff ──────────────────────────────────────
        old_vals = {col: current.get(col) for col in COLS_3G}
        diff = _diff(old_vals, new_vals)

        print(f"\n[3] Diff computed: {len(diff)} field(s) changed")
        for field, (old_v, new_v) in diff.items():
            print(f"   {field}: {old_v!r} → {new_v!r}")

        if not diff:
            print("\n⚠️  No difference detected.")
            print(f"   The cell already has uarfcn={TEST_UARFCN}.")
            print("   Try a different test value.")
            return

        # ── Step 4: UPDATE cell row ───────────────────────────────────
        print(f"\n[4] Updating cells_3g...")
        set_parts = [f"{col} = :{col}" for col in COLS_3G]
        set_parts.append("updated_at = NOW()")
        params = dict(new_vals)
        params["cell_name"] = TARGET_CELL_NAME

        result = conn.execute(
            text(f"UPDATE cells_3g SET {', '.join(set_parts)} WHERE cell_name = :cell_name"),
            params,
        )
        print(f"   ✓ Updated {result.rowcount} row(s)")

        # ── Step 5: Build post-update snapshot for revision ───────────
        updated_row = dict(current)
        updated_row.update(new_vals)

        # ── Step 6: Get next revision number ──────────────────────────
        rev_no = get_next_revision_no(conn, current["id"])
        print(f"\n[5] Next revision number: #{rev_no}")

        # ── Step 7: Write revision record ─────────────────────────────
        note = (
            f"[TEST] Script tự động cập nhật {len(diff)} trường: "
            + ", ".join(diff.keys())
        )
        write_cell3g_revision(conn, updated_row, diff, rev_no, note=note)
        print(f"\n[6] Revision record written:")
        print(f"   cell_id_ref  = {current['id']}")
        print(f"   revision_no  = {rev_no}")
        print(f"   change_source= {CHANGE_SOURCE!r}")
        print(f"   changed_by_name = {SCRIPT_USER_NAME!r}")
        print(f"   change_note  = {note!r}")
        print(f"   changed_fields = {json.dumps(diff, ensure_ascii=False)}")

    # ── Step 8: Verify ────────────────────────────────────────────────
    print(f"\n[7] Verifying changes in DB...")
    with engine.connect() as conn:
        cell_check = conn.execute(
            text("SELECT uarfcn, updated_at FROM cells_3g WHERE cell_name = :name"),
            {"name": TARGET_CELL_NAME},
        ).mappings().first()

        rev_check = conn.execute(
            text(
                "SELECT revision_no, changed_by_name, change_source, "
                "change_note, changed_fields, created_at "
                "FROM cell_3g_revisions "
                "WHERE cell_id_ref = :id "
                "ORDER BY revision_no DESC LIMIT 1"
            ),
            {"id": current["id"]},
        ).mappings().first()

    print(f"\n   cells_3g row:")
    print(f"     uarfcn     = {cell_check['uarfcn']!r}  ← should be {TEST_UARFCN!r}")
    print(f"     updated_at = {cell_check['updated_at']}")

    print(f"\n   Latest revision:")
    print(f"     revision_no     = {rev_check['revision_no']}")
    print(f"     changed_by_name = {rev_check['changed_by_name']!r}")
    print(f"     change_source   = {rev_check['change_source']!r}")
    print(f"     change_note     = {rev_check['change_note']!r}")
    print(f"     changed_fields  = {rev_check['changed_fields']}")
    print(f"     created_at      = {rev_check['created_at']}")

    print(f"""
{'='*60}
✅ TEST COMPLETE

What to check in the web app:
  1. Go to Cell 3G page
     → Search for '{TARGET_CELL_NAME}'
     → UARFCN column should show: {TEST_UARFCN}

  2. Go to Lịch sử thay đổi → Cell 3G tab
     → Search site/cell name: '{TARGET_CELL_NAME}'
     → Should see a new revision with purple 🤖 'Script' tag
     → Expand the row → Diff shows:
          uarfcn: [old_value] → {TEST_UARFCN}
     → change_note: '[TEST] Script tự động cập nhật 1 trường: uarfcn'
{'='*60}
""")


if __name__ == "__main__":
    main()