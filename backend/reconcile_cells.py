"""
reconcile_cells.py  -  daily batch (NOT part of the web app).

    python reconcile_cells.py                 # all techs, results stored in the DB
    python reconcile_cells.py --dry-run       # compute + print, write nothing
    python reconcile_cells.py --tech 4g,5g
    python reconcile_cells.py --init-db       # only create the tables

Compares ALL cells of the vendor dump CSVs with ALL cells of the web DB:
  * active (UNLOCKED / UNBLOCKED / CELL_UNBLOCK / Active ...) in dump but missing on web
  * present on web but missing from every dump file
The web page "Đối soát Cell" reads the stored result.

Normally scheduled once a day, e.g.
    python update_cells_with_revision.py --reconcile     # sync first, then reconcile (CSV downloaded once)
or  python reconcile_cells.py                            # stand-alone
DB url: env DATABASE_URL, else the default below.
"""
import argparse
import logging
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from datetime import datetime
from sqlalchemy import create_engine
import cell_reconcile_core as recon

DATABASE_URL = os.environ.get("DATABASE_URL",
                              "postgresql://sitelink:sitelink_pass@localhost:5432/sitelink_db")


def main() -> int:
    ap = argparse.ArgumentParser(description="SiteLink dump <-> web cell reconciliation")
    ap.add_argument("--dry-run", action="store_true", help="compute only, write nothing")
    ap.add_argument("--tech", default="3g,4g,5g", help="comma list, e.g. 4g,5g")
    ap.add_argument("--init-db", action="store_true", help="only create the tables and exit")
    ap.add_argument("--keep-runs", type=int, default=None,
                    help="successful runs per tech whose detail rows are kept (default env RECONCILE_KEEP_RUNS=7)")
    args = ap.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    eng = create_engine(DATABASE_URL, pool_pre_ping=True)
    try:
        if args.init_db:
            recon.ensure_tables(eng)
            print("✅ tables cell_reconcile_runs / cell_reconcile_items are ready")
            return 0
        techs = [t.strip().lower() for t in args.tech.split(",") if t.strip()]
        bad = [t for t in techs if t not in recon.TECHS]
        if bad:
            print("unknown tech %s (use 3g,4g,5g)" % bad)
            return 2
        print("=" * 60)
        print("SiteLink Cell Reconcile%s - %s" % (" (DRY RUN)" if args.dry_run else "",
                                                  datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
        print("=" * 60)
        rc = recon.run_reconcile(eng, techs, dry_run=args.dry_run, keep_runs=args.keep_runs)
        print("\n✅ Done." if rc == 0 else "\n⚠️ Finished with problems (see above).")
        return rc
    finally:
        eng.dispose()


if __name__ == "__main__":
    sys.exit(main())
