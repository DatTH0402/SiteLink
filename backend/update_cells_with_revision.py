"""
update_cells_with_revision.py  -  daily / manual bulk sync (NOT part of the web app).

    python update_cells_with_revision.py                 # all techs, writes to DB
    python update_cells_with_revision.py --dry-run       # show what WOULD change, write nothing
    python update_cells_with_revision.py --tech 4g,5g    # only some technologies

All transformation rules live in cell_sync_core.py (shared with the web "sync" button),
so this script and the web app always behave identically.
DB url: env DATABASE_URL, else the default below.
"""
import argparse
import logging
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from datetime import datetime
from sqlalchemy import create_engine, text
import cell_sync_core as core

DATABASE_URL = os.environ.get("DATABASE_URL",
                              "postgresql://sitelink:sitelink_pass@localhost:5432/sitelink_db")
TECHS = {"3g": "cells_3g", "4g": "cells_4g", "5g": "cells_5g"}


def run_bulk(eng, table: str, tech: str, dry_run: bool) -> int:
    with eng.connect() as conn:
        names = [r["cell_name"] for r in
                 conn.execute(text(f"SELECT cell_name FROM {table}")).mappings().all() if r["cell_name"]]
    if not names:
        print(f"\n--- {tech.upper()}: no cells in DB ---")
        return 0

    print(f"\n--- {tech.upper()} ({len(names)} cells in DB) ---")
    print(f"   Downloading {tech.upper()} vendor CSVs...")
    source_df = core.load_vendor_data(tech, vendors=None)
    if source_df.empty:
        print("   ❌ No source data downloaded - skipped (nothing written).")
        return 1
    print(f"   Loaded {len(source_df)} source rows")

    s = core.sync_cells(eng, table, names, vendors=None, source_df=source_df, dry_run=dry_run)
    tag = "WOULD update" if dry_run else "updated"
    print(f"   {tag}={s['updated']}  meta_only(dump_date/oss)={s['meta_only']}  "
          f"unchanged_total={s['skipped']}  not_in_csv={s['not_in_csv']}  "
          f"not_in_db={s['not_in_db']}  errors={s['errors']}")
    for d in s.get("error_details", [])[:20]:
        print(f"   ❌ {d}")
    return 1 if s["errors"] else 0


def main() -> int:
    ap = argparse.ArgumentParser(description="SiteLink daily cell sync")
    ap.add_argument("--dry-run", action="store_true", help="compute only, write nothing")
    ap.add_argument("--tech", default="3g,4g,5g", help="comma list, e.g. 4g,5g")
    args = ap.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    print("=" * 60)
    print(f"SiteLink Cell Sync{' (DRY RUN)' if args.dry_run else ''} - {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("=" * 60)

    eng = create_engine(DATABASE_URL, pool_pre_ping=True)
    rc = 0
    try:
        for tech in [t.strip().lower() for t in args.tech.split(",") if t.strip()]:
            if tech not in TECHS:
                print(f"unknown tech '{tech}' (use 3g,4g,5g)")
                rc = 1
                continue
            rc |= run_bulk(eng, TECHS[tech], tech, args.dry_run)
    finally:
        eng.dispose()
    print("\n✅ Done." if rc == 0 else "\n⚠️ Finished with problems (see above).")
    return rc


if __name__ == "__main__":
    sys.exit(main())
