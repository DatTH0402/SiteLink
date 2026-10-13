"""Idempotent indexes for the columns the app filters / joins on."""
import logging

from sqlalchemy import text

from app.db.session import engine

log = logging.getLogger("sitelink.indexes")

_TARGETS = [
    ("sites", "site_name"), ("sites", "tinh"),
    ("cells_3g", "site_id"), ("cells_3g", "cell_name"), ("cells_3g", "tinh"),
    ("cells_4g", "site_id"), ("cells_4g", "cell_name"), ("cells_4g", "tinh"),
    ("cells_5g", "site_id"), ("cells_5g", "cell_name"), ("cells_5g", "tinh"),
    ("cell_3g_revisions", "cell_id_ref"), ("cell_3g_revisions", "created_at"),
    ("cell_4g_revisions", "cell_id_ref"), ("cell_4g_revisions", "created_at"),
    ("cell_5g_revisions", "cell_id_ref"), ("cell_5g_revisions", "created_at"),
    ("site_revisions", "site_id"), ("site_revisions", "created_at"),
]


def _has_index(conn, table: str, col: str) -> bool:
    row = conn.execute(
        text("SELECT 1 FROM pg_indexes WHERE schemaname = current_schema() AND tablename = :t "
             "AND (indexdef LIKE :a OR indexdef LIKE :b) LIMIT 1"),
        {"t": table, "a": f"%({col})%", "b": f"%({col},%"},
    ).first()
    return row is not None


def ensure_indexes() -> None:
    for table, col in _TARGETS:
        name = f"ix_sl_{table}_{col}"
        try:
            with engine.begin() as conn:
                if not conn.execute(text("SELECT to_regclass(:t)"), {"t": table}).scalar():
                    continue                       # table does not exist (different name)
                if _has_index(conn, table, col):
                    continue                       # already indexed (pk / unique / earlier run)
                conn.execute(text(f'CREATE INDEX IF NOT EXISTS "{name}" ON "{table}" ("{col}")'))
                log.info("[index] created %s", name)
        except Exception as exc:                   # never block startup because of an index
            log.warning("[index] skipped %s.%s: %s", table, col, exc)
