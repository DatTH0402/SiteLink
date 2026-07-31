#!/usr/bin/env python3
"""
fix_bool_data.py
────────────────
One-time database repair script.

Converts any non-boolean values in the eight boolean Site columns to proper
PostgreSQL booleans.  Run this ONCE after deploying the code fix.

Usage:
    cd backend
    python fix_bool_data.py
"""
import sys
import os
sys.path.insert(0, os.path.dirname(__file__))

from app.db.session import SessionLocal
from sqlalchemy import text

BOOL_COLUMNS = [
    "tram_2g", "tram_3g", "tram_4g", "tram_5g",
    "repeater", "booster", "node_truyen_dan_only", "tram_phu_song_tsca",
]

def fix():
    db = SessionLocal()
    try:
        for col in BOOL_COLUMNS:
            # Cast the column to proper boolean in-place.
            # This handles: NULL → false, '0'/'false'/'no'/'off' → false,
            #               '1'/'true'/'yes'/'on'/'x' → true,
            #               integer 0 → false, integer 1 → true.
            sql = f"""
                UPDATE sites
                SET {col} = CASE
                    WHEN {col}::text IN ('true',  '1', 'yes', 'on',  't') THEN TRUE
                    WHEN {col}::text IN ('false', '0', 'no',  'off', 'f') THEN FALSE
                    WHEN {col} IS NULL THEN FALSE
                    ELSE {col}::boolean
                END
                WHERE {col}::text NOT IN ('true', 'false')
                   OR {col} IS NULL;
            """
            result = db.execute(text(sql))
            db.commit()
            print(f"  {col}: {result.rowcount} rows fixed")

        # Also repair the SiteRevision boolean columns
        for col in BOOL_COLUMNS:
            sql = f"""
                UPDATE site_revisions
                SET {col} = CASE
                    WHEN {col}::text IN ('true',  '1', 'yes', 'on',  't') THEN TRUE
                    WHEN {col}::text IN ('false', '0', 'no',  'off', 'f') THEN FALSE
                    WHEN {col} IS NULL THEN FALSE
                    ELSE {col}::boolean
                END
                WHERE {col}::text NOT IN ('true', 'false')
                   OR {col} IS NULL;
            """
            result = db.execute(text(sql))
            db.commit()
            print(f"  site_revisions.{col}: {result.rowcount} rows fixed")

        print("\nDatabase repair complete.")
    except Exception as e:
        db.rollback()
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        db.close()

if __name__ == "__main__":
    fix()
