"""
light_migrations.py
-------------------
Idempotent, startup-time schema/data fixes (the project uses
Base.metadata.create_all, which never alters existing tables).

  1. cells_5g.chung_anten column (new)
  2. widen mimo / mu_mimo to VARCHAR(100) (drop-list removed -> free text)
  3. remap legacy "chung_anten" values to the new drop-list values
"""
from __future__ import annotations

import logging

from sqlalchemy import bindparam, text

from app.db.session import engine

logger = logging.getLogger(__name__)

CHUNG_ANTEN_VALID = {
    "cells_3g": ["3G only", "3G4G", "2G3G", "2G3G4G", "3G5G", "3G4G5G"],
    "cells_4g": ["4G only", "3G4G", "2G3G4G", "4G5G", "3G4G5G"],
    "cells_5g": ["5G only", "3G5G", "4G5G", "3G4G5G"],
}

# legacy -> new. (Legacy "2G/4G" has no equivalent in the new 4G list: left as is.)
CHUNG_ANTEN_REMAP = {
    "cells_3g": {
        "3G": "3G only", "3G/4G": "3G4G", "2G/3G/4G": "2G3G4G",
        "3G/4G/5G": "3G4G5G", "3G/5G": "3G5G",
    },
    "cells_4g": {
        "4G": "4G only", "3G/4G": "3G4G", "2G/3G/4G": "2G3G4G",
        "4G/5G": "4G5G", "3G/4G/5G": "3G4G5G",
    },
    "cells_5g": {},
}


def _widen(conn, table: str, column: str, length: int) -> None:
    cur = conn.execute(
        text(
            "SELECT character_maximum_length FROM information_schema.columns "
            "WHERE table_schema = current_schema() "
            "AND table_name = :t AND column_name = :c"
        ),
        {"t": table, "c": column},
    ).scalar()
    if cur is not None and cur < length:
        conn.execute(text(f"ALTER TABLE {table} ALTER COLUMN {column} TYPE VARCHAR({length})"))
        logger.info("[migrate] %s.%s widened %s -> %s", table, column, cur, length)


def run_light_migrations() -> None:
    try:
        with engine.begin() as conn:
            # 1. new column
            conn.execute(text(
                "ALTER TABLE cells_5g ADD COLUMN IF NOT EXISTS chung_anten VARCHAR(100)"
            ))

            # 2. free-text MIMO / MU-MIMO
            _widen(conn, "cells_3g", "mimo", 100)
            _widen(conn, "cells_4g", "mimo", 100)
            _widen(conn, "cells_5g", "mimo", 100)
            _widen(conn, "cells_5g", "mu_mimo", 100)

            # 3. legacy value remap
            for table, mapping in CHUNG_ANTEN_REMAP.items():
                for old, new in mapping.items():
                    conn.execute(
                        text(f"UPDATE {table} SET chung_anten = :new WHERE chung_anten = :old"),
                        {"new": new, "old": old},
                    )
                stmt = text(
                    f"SELECT COUNT(*) FROM {table} "
                    "WHERE chung_anten IS NOT NULL AND chung_anten <> '' "
                    "AND chung_anten NOT IN :vals"
                ).bindparams(bindparam("vals", expanding=True))
                n = conn.execute(stmt, {"vals": CHUNG_ANTEN_VALID[table]}).scalar()
                if n:
                    logger.warning(
                        "[migrate] %s: %s row(s) have a 'chung_anten' value outside the new list "
                        "(e.g. legacy '2G/4G') – please review manually.", table, n)
    except Exception:
        logger.exception("[migrate] light migration failed (app will continue)")
