"""
migrate_add_subcell_id.py
-------------------------
Adds the optional `subcell_id` column used to tell apart cells that share one cell_name.

    python migrate_add_subcell_id.py                            # add the columns (idempotent)
    python migrate_add_subcell_id.py --drop-conflicting-unique

* cells_3g / cells_4g / cells_5g and cell_3g_revisions / cell_4g_revisions / cell_5g_revisions
  get   subcell_id VARCHAR(50) NULL
* A UNIQUE index / constraint on a cells_* table that involves cell_name but NOT subcell_id
  would stop two cells from sharing a name. They are only REPORTED unless
  --drop-conflicting-unique is given; then they are dropped and replaced by
      UNIQUE (site_id, cell_name, COALESCE(subcell_id, ''))
DB url: env DATABASE_URL, else the default below.
"""
import argparse
import os
import sys

from sqlalchemy import create_engine, text

DATABASE_URL = os.environ.get("DATABASE_URL",
                              "postgresql://sitelink:sitelink_pass@localhost:5432/sitelink_db")
CELL_TABLES = ["cells_3g", "cells_4g", "cells_5g"]
REVISION_TABLES = ["cell_3g_revisions", "cell_4g_revisions", "cell_5g_revisions"]


def main() -> int:
    ap = argparse.ArgumentParser(description="Add subcell_id to SiteLink cell tables")
    ap.add_argument("--drop-conflicting-unique", action="store_true",
                    help="drop UNIQUE indexes on cell_name and replace them with (site_id, cell_name, subcell_id)")
    args = ap.parse_args()

    eng = create_engine(DATABASE_URL, pool_pre_ping=True)
    rc = 0
    try:
        with eng.begin() as conn:
            for t in CELL_TABLES + REVISION_TABLES:
                conn.execute(text("ALTER TABLE %s ADD COLUMN IF NOT EXISTS subcell_id VARCHAR(50)" % t))
                print("  ok   %s.subcell_id" % t)

        for t in CELL_TABLES:
            with eng.connect() as conn:
                rows = conn.execute(text(
                    "SELECT indexname, indexdef FROM pg_indexes "
                    "WHERE schemaname = current_schema() AND tablename = :t "
                    "AND indexdef LIKE 'CREATE UNIQUE INDEX%'"), {"t": t}).fetchall()
            conflicts = [(n, d) for n, d in rows if "cell_name" in d and "subcell_id" not in d]
            for name, ddl in conflicts:
                if not args.drop_conflicting_unique:
                    print("  WARNING %s: unique index '%s' prevents cells from sharing a name:\n"
                          "          %s\n          re-run with --drop-conflicting-unique to replace it" % (t, name, ddl))
                    rc = 1
                    continue
                with eng.begin() as conn:
                    is_con = conn.execute(
                        text("SELECT 1 FROM pg_constraint WHERE conname = :n AND conrelid = CAST(:t AS regclass)"),
                        {"n": name, "t": t}).first()
                    if is_con:
                        conn.execute(text('ALTER TABLE %s DROP CONSTRAINT "%s"' % (t, name)))
                    else:
                        conn.execute(text('DROP INDEX IF EXISTS "%s"' % name))
                print("  dropped %s on %s" % (name, t))
            if args.drop_conflicting_unique and conflicts:
                try:
                    with eng.begin() as conn:
                        conn.execute(text(
                            "CREATE UNIQUE INDEX IF NOT EXISTS uq_%s_site_cell_subcell "
                            "ON %s (site_id, cell_name, COALESCE(subcell_id, ''))" % (t, t)))
                    print("  created uq_%s_site_cell_subcell" % t)
                except Exception as exc:
                    print("  WARNING could not create the replacement unique index on %s "
                          "(duplicate rows already exist?): %s" % (t, exc))
                    rc = 1
    finally:
        eng.dispose()
    print("\nDone." if rc == 0 else "\nFinished with warnings (see above).")
    return rc


if __name__ == "__main__":
    sys.exit(main())
