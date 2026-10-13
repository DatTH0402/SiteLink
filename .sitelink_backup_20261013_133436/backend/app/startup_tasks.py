"""
Startup work that must run ONCE even though gunicorn starts several workers
at the same time (schema creation, migrations, seeding, template regeneration).
A PostgreSQL advisory lock serialises the workers; template regeneration is
claimed by exactly one worker per container boot.
"""
import logging
import os

from sqlalchemy import text

from app.db.base import Base
from app.db.light_migrations import run_light_migrations
from app.db.perf_indexes import ensure_indexes
from app.db.session import engine

log = logging.getLogger("sitelink.startup")
_LOCK_KEY = 727101


def _claim_once(tag: str) -> bool:
    boot = os.environ.get("SITELINK_BOOT_ID") or str(os.getppid())
    flag = f"/tmp/sitelink_{tag}_{boot}.flag"
    try:
        os.close(os.open(flag, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
        return True
    except FileExistsError:
        return False
    except OSError:
        return True


def run_startup_tasks(seed_fn, regen_fn) -> None:
    with engine.connect() as lock_conn:
        lock_conn.execute(text("SET LOCAL statement_timeout = 0"))
        lock_conn.execute(text("SELECT pg_advisory_lock(:k)"), {"k": _LOCK_KEY})
        try:
            Base.metadata.create_all(bind=engine)
            run_light_migrations()
            ensure_indexes()
            seed_fn()
        finally:
            try:
                lock_conn.execute(text("SELECT pg_advisory_unlock(:k)"), {"k": _LOCK_KEY})
                lock_conn.commit()
            except Exception:
                log.exception("could not release the startup advisory lock")
    if _claim_once("templates"):
        try:
            regen_fn()
        except Exception:
            log.exception("template regeneration failed")
