"""
update_cells_with_revision.py — Scheduled bulk sync.
Downloads each vendor CSV exactly once per technology.
Uses per-batch commits (100 cells per commit) for reliability.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from datetime import datetime
from sqlalchemy import create_engine, text
import cell_sync_core as core

DATABASE_URL = "postgresql://sitelink:sitelink_pass@localhost:5432/sitelink_db"


def run_bulk(table: str, tech: str) -> None:
    eng = create_engine(DATABASE_URL, pool_pre_ping=True)

    with eng.connect() as conn:
        rows  = conn.execute(text(f"SELECT cell_name FROM {table}")).mappings().all()
        names = [r["cell_name"] for r in rows if r["cell_name"]]

    if not names:
        print(f"\n--- {tech.upper()}: no cells ---")
        return

    print(f"\n--- {tech.upper()} ({len(names)} cells) ---")
    print(f"   Downloading {tech.upper()} vendor CSVs...")
    source_df = core.load_vendor_data(tech, vendors=None)
    print(f"   Loaded {len(source_df)} rows from vendor CSVs")

    s = core.sync_cells(eng, table, names, vendors=None, source_df=source_df)

    print(f"   updated={s['updated']}  skipped={s['skipped']}  "
          f"not_in_csv={s['not_in_csv']}  not_in_db={s['not_in_db']}  "
          f"errors={s['errors']}")
    for d in s.get("error_details", []):
        print(f"   ❌ {d}")


if __name__ == "__main__":
    print("=" * 60)
    print(f"Bulk Sync — {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("=" * 60)
    run_bulk("cells_3g", "3g")
    run_bulk("cells_4g", "4g")
    run_bulk("cells_5g", "5g")
    print("\n✅ Done.")
