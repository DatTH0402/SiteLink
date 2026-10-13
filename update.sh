#!/usr/bin/env bash
# =============================================================================
#  harden_sitelink.sh  -  production hardening for SiteLink (40+ concurrent users)
#
#  Usage (from the project root, or pass --dir):
#      bash harden_sitelink.sh                 # patch + rebuild + restart + smoke test
#      bash harden_sitelink.sh --no-deploy     # only patch the source tree
#      bash harden_sitelink.sh --loadtest      # also run a 40-thread load check
#      bash harden_sitelink.sh --dir /path/to/SiteLink
#
#  What stays UNCHANGED (so the domain nginx keeps working):
#      * edge nginx still listens on host port 8081
#      * /api/...  ->  FastAPI   and   /sitelink/...  ->  SPA   (same paths)
#      * API prefix /api/v1, Vite base /sitelink/, SSO callback URLs
#
#  Safety: every file touched is copied to  .sitelink_backup_<timestamp>/  first,
#  a pg_dump is taken (if the DB container is running), patches are all-or-nothing
#  per file, and python syntax is checked before anything is rebuilt.
# =============================================================================
set -Eeuo pipefail

DEPLOY=1; LOADTEST=0; ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-deploy) DEPLOY=0 ;;
    --loadtest)  LOADTEST=1 ;;
    --dir)       ROOT="${2:?--dir needs a path}"; shift ;;
    -h|--help)   sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

c_b=$'\033[1;34m'; c_y=$'\033[1;33m'; c_r=$'\033[1;31m'; c_g=$'\033[1;32m'; c_0=$'\033[0m'
log()  { printf '%s[+]%s %s\n' "$c_b" "$c_0" "$*"; }
ok()   { printf '%s[ok]%s %s\n' "$c_g" "$c_0" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_y" "$c_0" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$c_r" "$c_0" "$*" >&2; exit 1; }

if [[ -z "$ROOT" ]]; then
  if [[ -f docker-compose.yml && -d backend && -d frontend ]]; then ROOT="$PWD"
  else ROOT="/home/mlmt/work/src/SiteLink"; fi
fi
[[ -f "$ROOT/docker-compose.yml" && -d "$ROOT/backend/app" && -d "$ROOT/frontend/src" ]] \
  || die "'$ROOT' does not look like the SiteLink project (docker-compose.yml / backend/app / frontend/src)"
cd "$ROOT"

command -v python3  >/dev/null || die "python3 is required"
command -v openssl  >/dev/null || die "openssl is required"
DC=""
if [[ $DEPLOY -eq 1 ]]; then
  command -v docker >/dev/null || die "docker is required (or use --no-deploy)"
  if docker compose version >/dev/null 2>&1; then DC="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then DC="docker-compose"
  else die "docker compose is required (or use --no-deploy)"; fi
fi

TS="$(date +%Y%m%d_%H%M%S)"
BK="$ROOT/.sitelink_backup_$TS"
mkdir -p "$BK"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
trap 'printf "%s[x]%s failed at line %s - originals are in %s\n" "$c_r" "$c_0" "$LINENO" "$BK" >&2' ERR
export BK ROOT
export PYTHONPATH="$TMP"
CHANGED=()

backup() {                       # backup <relative path>   (first copy wins)
  local f="$1"
  if [[ -f "$f" && ! -f "$BK/$f" ]]; then mkdir -p "$BK/$(dirname "$f")"; cp -a "$f" "$BK/$f"; fi
  return 0
}
write_file() {                   # write_file <relative path>   (content on stdin)
  local f="$1"; backup "$f"; mkdir -p "$(dirname "$f")"; cat > "$f"; CHANGED+=("$f")
}
http_ok() { python3 -c 'import sys,urllib.request as u; u.urlopen(sys.argv[1], timeout=4).read()' "$1" >/dev/null 2>&1; }

log "Project : $ROOT"
log "Backup  : $BK"

# -----------------------------------------------------------------------------
# 0. Database safety dump (best effort)
# -----------------------------------------------------------------------------
if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx sitelink_postgres; then
  mkdir -p backups
  if docker exec sitelink_postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' \
        > "backups/pre_hardening_$TS.dump" 2>/dev/null; then
    ok "database dump -> backups/pre_hardening_$TS.dump"
  else
    rm -f "backups/pre_hardening_$TS.dump"; warn "could not dump the database (continuing)"
  fi
else
  warn "postgres container not running - skipping DB dump"
fi

# -----------------------------------------------------------------------------
# 1. Patch helper (all-or-nothing edits, idempotent, CRLF-safe)
# -----------------------------------------------------------------------------
cat > "$TMP/patchlib.py" <<'__PATCHLIB__'
import os, re, shutil

BK = os.environ.get("BK", "")
RESULTS = {"done": 0, "ok": 0, "skip": 0}


def _backup(rel):
    if not BK:
        return
    dst = os.path.join(BK, rel)
    if os.path.isfile(rel) and not os.path.exists(dst):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(rel, dst)


def apply(rel, edits, forbid=None):
    """edits: list of dicts
         {"old": str, "new": str, "multi": bool}              literal replace
         {"re": pat, "to": str, "marker": str|None,
          "flags": int, "count": int, "expand": bool}          regex replace
         {"fn": callable, "marker": str}                       custom transform
         {"append": str, "marker": str}                        append to file
       The file is only written if EVERY edit applies (or is already applied)."""
    if not os.path.isfile(rel):
        print(f"  [skip] {rel}: file not found"); RESULTS["skip"] += 1; return False
    with open(rel, encoding="utf-8", newline="") as f:
        s = f.read()
    crlf = "\r\n" in s
    if crlf:
        s = s.replace("\r\n", "\n")
    orig = s
    for e in edits:
        if "append" in e:
            if e["marker"] in s:
                continue
            s = s.rstrip("\n") + "\n\n\n" + e["append"].strip("\n") + "\n"
        elif "fn" in e:
            if e["marker"] in s:
                continue
            try:
                s = e["fn"](s)
            except Exception as exc:
                print(f"  [skip] {rel}: {exc}"); RESULTS["skip"] += 1; return False
        elif "re" in e:
            marker = e.get("marker")
            if marker and marker in s:
                continue
            repl = (lambda m, t=e["to"]: m.expand(t)) if e.get("expand") else (lambda m, t=e["to"]: t)
            s2, n = re.subn(e["re"], repl, s, count=e.get("count", 1), flags=e.get("flags", re.M))
            if n == 0:
                if marker is None:
                    continue
                print(f"  [skip] {rel}: pattern not found {e['re'][:70]!r} - file left untouched")
                RESULTS["skip"] += 1; return False
            s = s2
        else:
            old, new = e["old"], e["new"]
            if new and new in s:
                continue
            if old not in s:
                if new == "":
                    continue
                print(f"  [skip] {rel}: text not found {old[:70]!r} - file left untouched")
                RESULTS["skip"] += 1; return False
            if s.count(old) != 1 and not e.get("multi"):
                print(f"  [skip] {rel}: text not unique {old[:70]!r} - file left untouched")
                RESULTS["skip"] += 1; return False
            s = s.replace(old, new)
    if forbid and re.search(forbid, s):
        print(f"  [skip] {rel}: result still matches /{forbid}/ - file left untouched")
        RESULTS["skip"] += 1; return False
    if s == orig:
        print(f"  [ok]   {rel}: already up to date"); RESULTS["ok"] += 1; return True
    if crlf:
        s = s.replace("\n", "\r\n")
    _backup(rel)
    with open(rel, "w", encoding="utf-8", newline="") as f:
        f.write(s)
    print(f"  [done] {rel}"); RESULTS["done"] += 1
    return True
__PATCHLIB__

# -----------------------------------------------------------------------------
# 2. .env  (secret key, permissions, tuning knobs)
# -----------------------------------------------------------------------------
log ".env"
if [[ -f .env ]]; then
  backup .env
  chmod 600 .env
  if grep -Eq '^SECRET_KEY=(change_this.*|change_me.*|)$' .env; then
    sed -i "s|^SECRET_KEY=.*|SECRET_KEY=$(openssl rand -hex 48)|" .env
    ok "SECRET_KEY was a placeholder (JWTs were forgeable) -> random key generated; everyone must log in again"
  fi
  if ! grep -q '^# --- SiteLink tuning' .env; then
    cat >> .env <<'__ENVTUNE__'

# --- SiteLink tuning (added by harden_sitelink.sh) - uncomment to override -----
#WEB_CONCURRENCY=4              # gunicorn workers (default: min(4, CPU cores), at least 2)
#DB_POOL_SIZE=8                 # DB connections kept per worker
#DB_MAX_OVERFLOW=12             # extra burst connections per worker
#DB_STATEMENT_TIMEOUT_MS=300000 # 0 disables
#SYNC_MAX_JOBS=2                # concurrent OSS sync jobs per worker
#EXPORT_MAX_CONCURRENT=3        # concurrent Excel/KMZ exports per worker (RAM guard)
#CELL_SYNC_CACHE_TTL=300        # seconds a downloaded vendor CSV is reused
#ADMIN_INITIAL_PASSWORD=        # only used when the admin user is first created
#CORS_ORIGINS=https://mlmt.mobifone.vn,http://10.24.15.169:8081
__ENVTUNE__
  fi
else
  warn ".env not found - skipped"
fi

# -----------------------------------------------------------------------------
# 3. Backend: runtime, DB pool, startup, sync
# -----------------------------------------------------------------------------
log "backend runtime (gunicorn + uvicorn workers, no --reload, no source bind-mount)"

if [[ -f backend/requirements.txt ]] && ! grep -qi '^gunicorn' backend/requirements.txt; then
  backup backend/requirements.txt
  printf '\ngunicorn==22.0.0\n' >> backend/requirements.txt
fi

write_file backend/Dockerfile <<'__EOF__'
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

EXPOSE 8000
CMD ["gunicorn", "-c", "gunicorn_conf.py", "app.main:app"]
__EOF__

[[ -f backend/.dockerignore ]] || write_file backend/.dockerignore <<'__EOF__'
__pycache__/
*.pyc
.git
uploads/
__EOF__

write_file backend/gunicorn_conf.py <<'__EOF__'
"""gunicorn settings for SiteLink (uvicorn workers)."""
import multiprocessing
import os
import uuid

bind = "0.0.0.0:8000"
worker_class = "uvicorn.workers.UvicornWorker"
workers = int(os.environ.get("WEB_CONCURRENCY") or max(2, min(4, multiprocessing.cpu_count())))
timeout = int(os.environ.get("GUNICORN_TIMEOUT", "300"))      # imports / exports can be long
graceful_timeout = 60
keepalive = 75
worker_tmp_dir = "/dev/shm"
forwarded_allow_ips = "*"          # trust X-Forwarded-* from the nginx in front
accesslog = None                   # nginx already logs every request
errorlog = "-"
loglevel = os.environ.get("LOG_LEVEL", "info")


def on_starting(server):
    # one id per container boot, inherited by every worker (used to run
    # "once per boot" jobs such as template regeneration in a single worker)
    os.environ["SITELINK_BOOT_ID"] = uuid.uuid4().hex
__EOF__

write_file backend/app/db/session.py <<'__EOF__'
import os

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.core.config import settings

_stmt_timeout = int(os.environ.get("DB_STATEMENT_TIMEOUT_MS", "300000"))

# Pool is per gunicorn worker:  workers x (pool_size + max_overflow)  must stay
# below postgres max_connections (200 in docker-compose.yml).
engine = create_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,
    pool_size=int(os.environ.get("DB_POOL_SIZE", "8")),
    max_overflow=int(os.environ.get("DB_MAX_OVERFLOW", "12")),
    pool_timeout=int(os.environ.get("DB_POOL_TIMEOUT", "30")),
    pool_recycle=int(os.environ.get("DB_POOL_RECYCLE", "1800")),
    connect_args={"options": f"-c statement_timeout={_stmt_timeout}"} if _stmt_timeout > 0 else {},
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
__EOF__

write_file backend/app/db/perf_indexes.py <<'__EOF__'
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
__EOF__

write_file backend/app/startup_tasks.py <<'__EOF__'
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
__EOF__

log "backend sync endpoints (multi-worker safe job store, shared DB pool, bounded threads)"
write_file backend/app/api/routes/sync.py <<'__EOF__'
"""
sync.py
-------
Cell sync endpoints.

POST /api/v1/sync/cells         ASYNC: returns a job id immediately (used by the web UI,
                                 which polls GET /sync/status/{job_id}). Safe behind a
                                 reverse proxy with a 120 s read timeout.
GET  /api/v1/sync/status/{id}   job state. Jobs live in small JSON files so every
                                 gunicorn worker sees the same state.
POST /api/v1/sync/cells/wait    synchronous (<= 2 000 cells)  - kept for scripts / curl
POST /api/v1/sync/cells/batch   synchronous (<= 10 000 cells) - kept for scripts / curl
GET  /api/v1/sync/recent        cell names created/updated recently
"""
from __future__ import annotations

import json
import logging
import os
import re
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Set

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import text as sa_text
from sqlalchemy.orm import Session

from app.db.session import engine, get_db
from app.models.user import User, UserRole
from app.utils.deps import get_current_user

log    = logging.getLogger(__name__)
router = APIRouter()

MAX_CELLS_SYNC = 10_000     # async endpoint
MAX_CELLS_WAIT = 2_000      # synchronous /wait
WAIT_TIMEOUT_S = 600

# a few concurrent jobs per worker: each one downloads / transforms vendor CSVs (RAM heavy)
_executor = ThreadPoolExecutor(
    max_workers=int(os.environ.get("SYNC_MAX_JOBS", "2")),
    thread_name_prefix="cell-sync",
)

# ── job store (file based: shared by all gunicorn workers) ────────────────────
_JOB_DIR   = os.environ.get("SYNC_JOB_DIR", "/tmp/sitelink_sync_jobs")
_JOB_TTL_S = 6 * 3600
_STALE_S   = 45 * 60
_JOB_ID_RE = re.compile(r"^[0-9a-f]{32}$")
os.makedirs(_JOB_DIR, exist_ok=True)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _job_path(job_id: str) -> str:
    return os.path.join(_JOB_DIR, f"{job_id}.json")


def _job_write(job_id: str, data: Dict[str, Any]) -> None:
    data["updated_at"] = time.time()
    tmp = os.path.join(_JOB_DIR, f".{job_id}.{os.getpid()}.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, default=str)
    os.replace(tmp, _job_path(job_id))


def _job_read(job_id: str) -> Optional[Dict[str, Any]]:
    try:
        with open(_job_path(job_id), encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, ValueError):
        return None


def _job_cleanup() -> None:
    now = time.time()
    try:
        for name in os.listdir(_JOB_DIR):
            p = os.path.join(_JOB_DIR, name)
            try:
                if now - os.path.getmtime(p) > _JOB_TTL_S:
                    os.remove(p)
            except OSError:
                pass
    except OSError:
        pass


# ── cell_sync_core loader ─────────────────────────────────────────────────────
def _find_backend_dir() -> str:
    env = os.environ.get("CELL_SYNC_CORE_DIR", "")
    if env and os.path.isfile(os.path.join(env, "cell_sync_core.py")):
        return env
    candidate = os.path.dirname(os.path.abspath(__file__))
    for _ in range(10):
        if os.path.isfile(os.path.join(candidate, "cell_sync_core.py")):
            return candidate
        parent = os.path.dirname(candidate)
        if parent == candidate:
            break
        candidate = parent
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


_BACKEND_DIR = _find_backend_dir()


def _import_core():
    if _BACKEND_DIR not in sys.path:
        sys.path.insert(0, _BACKEND_DIR)
    import cell_sync_core as core  # noqa
    return core


def _do_sync(table: str, names: List[str], vendors: Optional[Set[str]]) -> Dict[str, Any]:
    # shared SQLAlchemy engine (no new pool per call); vendor CSVs are cached in the core
    return _import_core().sync_cells(engine, table, names, vendors)


# ── schemas ───────────────────────────────────────────────────────────────────
class SyncRequest(BaseModel):
    tech:       str
    cell_names: List[str]
    vendors:    Optional[List[str]] = None


class SyncResult(BaseModel):
    updated:       int = 0
    skipped:       int = 0
    not_in_db:     int = 0
    not_in_csv:    int = 0
    errors:        int = 0
    meta_only:     int = 0
    error_details: List[str] = []


class SyncWaitResponse(BaseModel):
    table_name: str
    cell_count: int
    result:     SyncResult
    duration_s: float


class SyncJobResponse(BaseModel):
    job_id:     str
    status:     str
    cell_count: int
    message:    str


class SyncStatusResponse(BaseModel):
    job_id:      str
    status:      str
    started_at:  Optional[str] = None
    finished_at: Optional[str] = None
    result:      Optional[Dict[str, Any]] = None
    error:       Optional[str] = None


def _to_result(stats: Dict[str, Any]) -> SyncResult:
    return SyncResult(
        updated=stats.get("updated", 0), skipped=stats.get("skipped", 0),
        not_in_db=stats.get("not_in_db", 0), not_in_csv=stats.get("not_in_csv", 0),
        errors=stats.get("errors", 0), meta_only=stats.get("meta_only", 0),
        error_details=list(stats.get("error_details", []))[:50],
    )


def _parse_request(payload: SyncRequest):
    tech = payload.tech.lower()
    if tech not in ("3g", "4g", "5g"):
        raise HTTPException(400, "tech must be 3g, 4g or 5g")
    names = [n.strip() for n in payload.cell_names if n and n.strip()]
    if not names:
        raise HTTPException(400, "cell_names is empty")
    vendors: Optional[Set[str]] = (
        {v.lower() for v in payload.vendors if v} if payload.vendors else None
    )
    return f"cells_{tech}", names, vendors


# ── synchronous endpoints (scripts / curl) ────────────────────────────────────
def _run_blocking(payload: SyncRequest, user: User, max_cells: int, timeout_s: int, label: str):
    table, names, vendors = _parse_request(payload)
    if len(names) > max_cells:
        raise HTTPException(400, f"Too many cells ({len(names)} > {max_cells}). Use POST /cells instead.")
    t0 = time.time()
    log.info("sync/%s: %s %d cells user=%s", label, table, len(names), user.username)
    try:
        stats = _executor.submit(_do_sync, table, names, vendors).result(timeout=timeout_s)
    except FutureTimeout:
        raise HTTPException(504, "Sync timed out - use the async endpoint (POST /cells).")
    except Exception as exc:
        log.exception("sync/%s failed", label)
        raise HTTPException(500, f"Sync failed: {exc}")
    duration = time.time() - t0
    log.info("sync/%s done in %.1fs: %s", label, duration, stats)
    return SyncWaitResponse(table_name=table, cell_count=len(names),
                            result=_to_result(stats), duration_s=round(duration, 2))


@router.post("/cells/wait", response_model=SyncWaitResponse)
def sync_cells_wait(payload: SyncRequest, current_user: User = Depends(get_current_user)):
    return _run_blocking(payload, current_user, MAX_CELLS_WAIT, WAIT_TIMEOUT_S, "wait")


@router.post("/cells/batch", response_model=SyncWaitResponse)
def sync_cells_batch(payload: SyncRequest, current_user: User = Depends(get_current_user)):
    return _run_blocking(payload, current_user, MAX_CELLS_SYNC, WAIT_TIMEOUT_S, "batch")


# ── asynchronous endpoint (used by the web UI) ────────────────────────────────
def _run_async_job(job_id: str, table: str, names: List[str], vendors: Optional[Set[str]]) -> None:
    job = _job_read(job_id) or {"job_id": job_id}
    job.update(status="running", started_at=_now_iso())
    _job_write(job_id, job)
    try:
        stats = dict(_do_sync(table, names, vendors))
        stats["error_details"] = list(stats.get("error_details", []))[:50]
        job.update(status="done", result=stats, finished_at=_now_iso())
    except Exception as exc:
        log.exception("async sync job %s failed", job_id)
        job.update(status="error", error=str(exc)[:500], finished_at=_now_iso())
    try:
        _job_write(job_id, job)
    except Exception:
        log.exception("could not persist job %s", job_id)


@router.post("/cells", response_model=SyncJobResponse, status_code=202)
def sync_cells_async(payload: SyncRequest, current_user: User = Depends(get_current_user)):
    table, names, vendors = _parse_request(payload)
    if len(names) > MAX_CELLS_SYNC:
        raise HTTPException(400, f"Too many cells (max {MAX_CELLS_SYNC})")
    _job_cleanup()
    job_id = uuid.uuid4().hex
    _job_write(job_id, {
        "job_id": job_id, "status": "queued", "started_at": None, "finished_at": None,
        "result": None, "error": None, "tech": payload.tech.lower(),
        "cell_count": len(names), "requested_by": current_user.username,
    })
    _executor.submit(_run_async_job, job_id, table, names, vendors)
    return SyncJobResponse(
        job_id=job_id, status="queued", cell_count=len(names),
        message=f"Đồng bộ {len(names)} cell {payload.tech.upper()} đã được khởi động.",
    )


@router.get("/status/{job_id}", response_model=SyncStatusResponse)
def get_sync_status(job_id: str, current_user: User = Depends(get_current_user)):
    job = _job_read(job_id) if _JOB_ID_RE.match(job_id) else None
    if not job:
        raise HTTPException(404, "Job not found")
    if job.get("requested_by") != current_user.username and current_user.role != UserRole.admin:
        raise HTTPException(403, "Not your job")
    status, error = job.get("status", "error"), job.get("error")
    if status in ("queued", "running") and time.time() - job.get("updated_at", time.time()) > _STALE_S:
        status, error = "error", "Job was lost (the server restarted while it was running)."
    return SyncStatusResponse(
        job_id=job_id, status=status, started_at=job.get("started_at"),
        finished_at=job.get("finished_at"), result=job.get("result"), error=error)


# ── recently touched cells ────────────────────────────────────────────────────
@router.get("/recent")
def get_recent_cells(
    table:   str,
    minutes: int = 60,
    since:   str = "",
    _: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """cell_names created/updated after `since` (ISO 8601) or in the last `minutes`."""
    if table not in {"cells_3g", "cells_4g", "cells_5g"}:
        raise HTTPException(400, "table must be cells_3g, cells_4g or cells_5g")
    try:
        if since:
            rows = db.execute(sa_text(
                f"SELECT cell_name FROM {table} WHERE cell_name IS NOT NULL "
                f"AND (created_at >= :since OR updated_at >= :since) "
                f"ORDER BY COALESCE(created_at, updated_at) DESC LIMIT 50000"),
                {"since": since}).fetchall()
        else:
            rows = db.execute(sa_text(
                f"SELECT cell_name FROM {table} WHERE cell_name IS NOT NULL "
                f"AND (created_at >= NOW() - make_interval(mins => :m) "
                f"OR updated_at >= NOW() - make_interval(mins => :m)) "
                f"ORDER BY COALESCE(created_at, updated_at) DESC LIMIT 50000"),
                {"m": max(1, int(minutes))}).fetchall()
        names = [r[0] for r in rows if r[0]]
        return {"cell_names": names, "count": len(names)}
    except Exception as exc:
        log.error("get_recent_cells: %s", exc, exc_info=True)
        raise HTTPException(500, str(exc))
__EOF__

# -----------------------------------------------------------------------------
# 4. Backend patches to existing files
# -----------------------------------------------------------------------------
log "patching existing backend files"
python3 - <<'PY'
import re
import patchlib as P
A = P.apply

STARTUP = '''@app.on_event("startup")
def on_startup():
    # several gunicorn workers boot together: startup_tasks serialises schema/seed
    # work with an advisory lock and runs template regeneration in one worker only
    from app.startup_tasks import run_startup_tasks
    run_startup_tasks(_seed_initial_data, regen_now)
'''
CORS = ('allow_origins=[o.strip() for o in os.environ.get("CORS_ORIGINS", '
        '"https://mlmt.mobifone.vn,http://10.24.15.169:8081,http://localhost:8081,http://localhost:5173")'
        '.split(",") if o.strip()],')

print("main.py")
A("backend/app/main.py", [
    {"re": r"^Base\.metadata\.create_all\(bind=engine\)[ \t]*\n", "to": "", "marker": None},
    {"re": r'@app\.on_event\("startup"\)\s*\ndef on_startup\(\):.*?regen_now\(\)[^\n]*\n',
     "to": STARTUP, "flags": re.S, "marker": "run_startup_tasks"},
    {"re": r'allow_origins=\[\s*"\*"\s*\],', "to": CORS, "marker": 'os.environ.get("CORS_ORIGINS"'},
    {"re": r'get_password_hash\("admin"\)',
     "to": 'get_password_hash(os.environ.get("ADMIN_INITIAL_PASSWORD") or "admin")',
     "marker": "ADMIN_INITIAL_PASSWORD"},
])

print("async upload endpoints -> threadpool (they block on pandas / DB for a long time)")
ASYNC = [
    {"old": "await file.read()", "new": "file.file.read()", "multi": True},
    {"re": r"^async def ", "to": "def ", "count": 0, "marker": None},
]
RET_RE = (r'return \{"created": created, "updated": updated,\s*'
          r'"skipped_no_change": skipped, "sites_auto_created": sites_auto_created,\s*'
          r'"errors": errors\}')
RET_TO = '''touched_names = [r.get("cell_name") for r in result["to_create"]] + [
        (u.get("changes") or {}).get("cell_name") for u in result["to_update"]]
    touched_names = [n for n in dict.fromkeys(touched_names) if isinstance(n, str) and n.strip()]
    return {"created": created, "updated": updated,
            "skipped_no_change": skipped, "sites_auto_created": sites_auto_created,
            "errors": errors, "cell_names": touched_names}'''
for t in ("3g", "4g", "5g"):
    A(f"backend/app/api/routes/cells_{t}.py", ASYNC + [
        # bug: a local import made HTTPException a local name -> UnboundLocalError (HTTP 500)
        {"re": r"^[ \t]+from fastapi import HTTPException[ \t]*\n", "to": "", "count": 0, "marker": None},
        # return the touched cell names so the UI syncs exactly those cells (no clock-based guessing)
        {"re": RET_RE, "to": RET_TO, "marker": '"cell_names": touched_names'},
    ], forbid=r"\bawait\b")
A("backend/app/api/routes/sites.py",   ASYNC, forbid=r"\bawait\b")
A("backend/app/api/routes/antenna.py", ASYNC, forbid=r"\bawait\b")

print("export.py (cap concurrent big exports -> protects RAM)")
A("backend/app/api/routes/export.py", [
    {"re": r"^def _excel\(",
     "to": '''import threading as _threading

_EXPORT_SLOTS = _threading.BoundedSemaphore(int(__import__("os").environ.get("EXPORT_MAX_CONCURRENT", "3")))


def _excel(*args, **kwargs):
    """Cap simultaneous big exports so a few huge files cannot exhaust RAM."""
    with _EXPORT_SLOTS:
        return _excel_impl(*args, **kwargs)


def _excel_impl(''', "marker": "def _excel_impl("},
    {"re": r"^def _kmz_response\(",
     "to": '''def _kmz_response(*args, **kwargs):
    with _EXPORT_SLOTS:
        return _kmz_response_impl(*args, **kwargs)


def _kmz_response_impl(''', "marker": "def _kmz_response_impl("},
])

print("revision.py (5G chung_anten changes were never recorded)")
A("backend/app/services/revision.py", [
    {"append": '''# --- chung_anten is editable on 5G cells but was missing from the snapshot, so a change
# --- to that field alone produced no revision. Wrap the snapshot to include it.
_orig_cell5g_snapshot = _cell5g_snapshot


def _cell5g_snapshot(cell):  # noqa: F811
    snap = _orig_cell5g_snapshot(cell)
    snap["chung_anten"] = getattr(cell, "chung_anten", None)
    return snap''', "marker": "_orig_cell5g_snapshot"},
])

print("cell_sync_core.py (vendor CSV cache + single-flight download)")
NEW_LOADER = '''_VENDOR_CACHE_TTL = int(os.environ.get("CELL_SYNC_CACHE_TTL", "300"))   # seconds
_vendor_cache: Dict[tuple, tuple] = {}              # (tech, vendor) -> (timestamp, DataFrame)
_vendor_locks: Dict[tuple, threading.Lock] = {}
_vendor_guard = threading.Lock()


def _vendor_frame(tech_l: str, vendor: str) -> Optional[pd.DataFrame]:
    """Download + transform ONE vendor CSV. Cached for a few minutes and concurrent
    callers share a single download (40 users must not hammer the OSS server)."""
    key = (tech_l, vendor)
    with _vendor_guard:
        lock = _vendor_locks.setdefault(key, threading.Lock())
    with lock:
        hit = _vendor_cache.get(key)
        if hit and _VENDOR_CACHE_TTL > 0 and time.time() - hit[0] < _VENDOR_CACHE_TTL:
            return hit[1]
        src_key = VENDOR_KEYS.get(tech_l, {}).get(vendor)
        builder = _BUILDERS.get((tech_l, vendor))
        if not src_key or not builder:
            return None
        raw = fetch_csv(URLS[src_key], f"{vendor.title()} {tech_l.upper()}")
        if raw is None or raw.empty:
            log.warning("Empty/failed CSV for %s/%s", vendor, tech_l)
            return None
        try:
            built = builder(raw)
        except Exception as exc:
            log.error("Builder %s/%s failed: %s", vendor, tech_l, exc, exc_info=True)
            return None
        built = built[built["cell_name"].notna()]
        _vendor_cache[key] = (time.time(), built)
        log.info("Loaded %d valid rows from %s/%s", len(built), vendor, tech_l)
        return built


def load_vendor_data(tech: str, vendors: Optional[Set[str]] = None) -> pd.DataFrame:
    """Transformed cells of the requested vendors (deduplicated by cell_name)."""
    tech_l = tech.lower()
    eff = ({v.lower() for v in vendors if v} if vendors else set()) or ALL_VENDORS
    frames: List[pd.DataFrame] = []
    for vendor in sorted(eff):
        frame = _vendor_frame(tech_l, vendor)
        if frame is not None:
            frames.append(frame)
    if not frames:
        log.error("No vendor data loaded for tech=%s", tech)
        return pd.DataFrame()
    combined = pd.concat(frames, ignore_index=True).drop_duplicates(subset=["cell_name"], keep="first")
    log.info("load_vendor_data %s: %d unique cells", tech, len(combined))
    return combined'''


def swap_loader(s):
    a = s.find("def load_vendor_data(")
    b = s.find("#  DB helpers")
    if a < 0 or b < 0 or b < a:
        raise ValueError("load_vendor_data / 'DB helpers' anchors not found")
    b = s.rfind("\n", 0, b - 1) + 1            # start of the banner line above '#  DB helpers'
    return s[:a] + NEW_LOADER + "\n\n\n" + s[b:]


A("backend/cell_sync_core.py", [
    {"re": r"^import io\nimport json\n", "to": "import io\nimport json\nimport os\nimport threading\nimport time\n",
     "marker": "import threading"},
    {"fn": swap_loader, "marker": "_vendor_frame"},
])

import json, sys
print("RESULT", json.dumps(P.RESULTS))
PY

# multi-worker is only safe when the startup patch is in place
if ! grep -q run_startup_tasks backend/app/main.py 2>/dev/null; then
  warn "main.py startup patch NOT applied -> forcing a single worker (WEB_CONCURRENCY=1) to avoid startup races"
  backup .env
  grep -q '^WEB_CONCURRENCY=' .env 2>/dev/null || echo 'WEB_CONCURRENCY=1' >> .env
fi

# -----------------------------------------------------------------------------
# 5. Frontend
# -----------------------------------------------------------------------------
log "frontend (nginx gzip + cache rules, 401 redirect, async sync polling, debounced search)"

write_file frontend/Dockerfile <<'__EOF__'
FROM node:20-alpine AS builder
WORKDIR /app
ENV NODE_OPTIONS=--max-old-space-size=3072
COPY package*.json ./
RUN (npm ci --no-audit --no-fund || npm install --no-audit --no-fund)
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
__EOF__

[[ -f frontend/.dockerignore ]] || write_file frontend/.dockerignore <<'__EOF__'
node_modules
dist
.git
__EOF__

write_file frontend/nginx.conf <<'__EOF__'
server {
    listen 80;
    root /usr/share/nginx/html;
    index index.html;

    gzip on;
    gzip_comp_level 5;
    gzip_min_length 1024;
    gzip_vary on;
    gzip_types text/plain text/css application/javascript application/json image/svg+xml;

    location = / {
        return 301 /sitelink/;
    }

    # Vite emits content-hashed file names -> safe to cache for a year
    location /sitelink/assets/ {
        alias /usr/share/nginx/html/assets/;
        expires 1y;
        access_log off;
        add_header Cache-Control "public, immutable";
    }

    # SPA - handles /sitelink/ and /sitelink/sso/callback
    location /sitelink/ {
        try_files $uri @spa;
    }

    # index.html must never be cached, otherwise users keep an old bundle after a deploy
    location @spa {
        root /usr/share/nginx/html;
        add_header Cache-Control "no-cache, must-revalidate";
        try_files /index.html =404;
    }
}
__EOF__

write_file frontend/src/hooks/useDebouncedValue.ts <<'__EOF__'
import { useEffect, useState } from 'react'

/** Returns `value` only after it stopped changing for `delay` ms (search boxes). */
export function useDebouncedValue<T>(value: T, delay = 400): T {
  const [debounced, setDebounced] = useState<T>(value)
  useEffect(() => {
    const t = setTimeout(() => setDebounced(value), delay)
    return () => clearTimeout(t)
  }, [value, delay])
  return debounced
}
__EOF__

write_file frontend/src/api/client.ts <<'__EOF__'
import axios from 'axios'

const api = axios.create({
  baseURL: window.location.origin,
  paramsSerializer: {
    // Serialize arrays as repeated params: tinh=HN&tinh=HCM
    // (not tinh[]=HN&tinh[]=HCM which FastAPI rejects)
    serialize: (params) => {
      const parts: string[] = []
      Object.entries(params).forEach(([key, value]) => {
        if (value === undefined || value === null) return
        if (Array.isArray(value)) {
          value.forEach((v) => {
            if (v !== undefined && v !== null && v !== '')
              parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(v)}`)
          })
        } else {
          parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`)
        }
      })
      return parts.join('&')
    },
  },
})

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('sl_token')
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

// The app is served under /sitelink/ (Vite base + BrowserRouter basename).
const LOGIN_PATH = '/sitelink/login'

api.interceptors.response.use(
  (r) => r,
  (err) => {
    const url: string = err?.config?.url ?? ''
    const isAuthCall = url.includes('/auth/login') || url.includes('/auth/sso')
    // Expired / invalid token -> back to the login page (but never for the login calls themselves)
    if (err?.response?.status === 401 && !isAuthCall) {
      localStorage.removeItem('sl_token')
      localStorage.removeItem('sl_id_token')
      if (!window.location.pathname.startsWith(LOGIN_PATH)) {
        window.location.href = LOGIN_PATH
      }
    }
    return Promise.reject(err)
  },
)

export default api
__EOF__

write_file frontend/src/api/sync.ts <<'__EOF__'
/**
 * sync.ts - Cell sync API
 *
 * syncCellsWait / syncCellsBatch keep their old signatures, but they now start a
 * background job (POST /sync/cells) and poll it. Nothing holds an HTTP request
 * open for minutes, so the reverse proxy's 120 s timeout can no longer cut a sync.
 */
import api from './client'

export interface SyncRequest {
  tech:       '3g' | '4g' | '5g'
  cell_names: string[]
  vendors?:   string[]
}

export interface SyncResult {
  updated:       number
  skipped:       number
  not_in_db:     number
  not_in_csv:    number
  errors:        number
  error_details: string[]
  meta_only?:    number
}

export interface SyncWaitResponse {
  table_name: string
  cell_count: number
  result:     SyncResult
  duration_s: number
}

interface JobStart {
  job_id:     string
  status:     string
  cell_count: number
  message:    string
}

interface JobStatus {
  job_id:       string
  status:       string
  started_at?:  string | null
  finished_at?: string | null
  result?:      Record<string, unknown> | null
  error?:       string | null
}

const POLL_MS     = 2000
const MAX_WAIT_MS = 30 * 60 * 1000

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms))
const num   = (v: unknown): number => (typeof v === 'number' ? v : 0)

async function runSyncJob(req: SyncRequest): Promise<SyncWaitResponse> {
  const t0 = Date.now()
  const start = await api
    .post<JobStart>('/api/v1/sync/cells', req, { timeout: 60_000 })
    .then((r) => r.data)

  let failures = 0
  while (Date.now() - t0 < MAX_WAIT_MS) {
    await sleep(POLL_MS)
    let st: JobStatus
    try {
      st = await api
        .get<JobStatus>(`/api/v1/sync/status/${start.job_id}`, { timeout: 30_000 })
        .then((r) => r.data)
      failures = 0
    } catch (e) {
      failures += 1
      if (failures >= 5) throw e      // tolerate a few transient network errors
      continue
    }

    if (st.status === 'done') {
      const r = st.result ?? {}
      return {
        table_name: `cells_${req.tech}`,
        cell_count: req.cell_names.length,
        result: {
          updated:       num(r.updated),
          skipped:       num(r.skipped),
          not_in_db:     num(r.not_in_db),
          not_in_csv:    num(r.not_in_csv),
          errors:        num(r.errors),
          meta_only:     num(r.meta_only),
          error_details: Array.isArray(r.error_details) ? (r.error_details as string[]) : [],
        },
        duration_s: (Date.now() - t0) / 1000,
      }
    }
    if (st.status === 'error') throw new Error(st.error || 'Sync failed')
  }
  throw new Error('Sync is still running after 30 minutes - it will finish in the background.')
}

/** Sync small batches (form create). */
export const syncCellsWait = (req: SyncRequest): Promise<SyncWaitResponse> => runSyncJob(req)

/** Sync large batches (import). CSVs are downloaded once (and cached server-side). */
export const syncCellsBatch = (req: SyncRequest): Promise<SyncWaitResponse> => runSyncJob(req)

/**
 * Get cell_names created/updated after a specific timestamp.
 * (Fallback only: the import endpoints now return the touched cell names directly.)
 */
export const getRecentCellNames = (
  table:   string,
  options: { since?: string; minutes?: number } = {},
): Promise<string[]> => {
  const params = new URLSearchParams({ table })
  if (options.since)   params.set('since', options.since)
  if (options.minutes) params.set('minutes', String(options.minutes))
  return api.get<{ cell_names: string[]; count: number }>(
    `/api/v1/sync/recent?${params}`
  ).then(r => r.data.cell_names ?? [])
}
__EOF__

log "patching existing frontend files"
python3 - <<'PY'
import patchlib as P
A = P.apply

print("App.tsx (admin pages bounced to /login on a hard refresh)")
A("frontend/src/App.tsx", [
    {"re": r'const user = useAuthStore\(\(s\) => s\.user\)\s*\n(\s*)if \(!user\) return <Navigate to="/login" replace />',
     "to": 'const user = useAuthStore((s) => s.user)\n  const token = useAuthStore((s) => s.token)\n\\1if (!user) return token ? null : <Navigate to="/login" replace />',
     "expand": True, "marker": "return token ? null :"},
])

IMPORT = "import { useServerQuery, useServerColumns } from '@/hooks/useServerTable'"
IMPORT_NEW = IMPORT + "\nimport { useDebouncedValue } from '@/hooks/useDebouncedValue'"
SEARCH = {"re": r"if \(search\)(\s+)params\.search(\s+)= search\b",
          "to": r"if (dSearch)\1params.search\2= dSearch", "expand": True, "marker": "= dSearch"}

print("search boxes -> debounced (one request per pause, not per keystroke)")
for t in ("3g", "4g", "5g"):
    A(f"frontend/src/pages/cells/Cells{t.upper()}Page.tsx", [
        {"old": IMPORT, "new": IMPORT_NEW},
        {"old": "const sq = useServerQuery([search, cellNameOld, mien, tinh, phuongXa, vendor])",
         "new": ("const dSearch      = useDebouncedValue(search, 400)\n"
                 "  const dCellNameOld = useDebouncedValue(cellNameOld, 400)\n"
                 "  const sq = useServerQuery([dSearch, dCellNameOld, mien, tinh, phuongXa, vendor])")},
        SEARCH,
        {"re": r"if \(cellNameOld\)(\s+)params\.cell_name_old(\s+)= cellNameOld\b",
         "to": r"if (dCellNameOld)\1params.cell_name_old\2= dCellNameOld", "expand": True, "marker": "= dCellNameOld"},
        {"old": "}, [search, cellNameOld, mien, tinh, phuongXa, vendor, sq.params])",
         "new": "}, [dSearch, dCellNameOld, mien, tinh, phuongXa, vendor, sq.params])"},
    ])
A("frontend/src/pages/sites/SitesPage.tsx", [
    {"old": IMPORT, "new": IMPORT_NEW},
    {"old": "const sq = useServerQuery([search, siteNameCu, mien, tinh, phuongXa])",
     "new": ("const dSearch     = useDebouncedValue(search, 400)\n"
             "  const dSiteNameCu = useDebouncedValue(siteNameCu, 400)\n"
             "  const sq = useServerQuery([dSearch, dSiteNameCu, mien, tinh, phuongXa])")},
    SEARCH,
    {"re": r"if \(siteNameCu\)(\s+)params\.site_name_cu(\s+)= siteNameCu\b",
     "to": r"if (dSiteNameCu)\1params.site_name_cu\2= dSiteNameCu", "expand": True, "marker": "= dSiteNameCu"},
    {"old": "}, [search, siteNameCu, mien, tinh, phuongXa, sq.params])",
     "new": "}, [dSearch, dSiteNameCu, mien, tinh, phuongXa, sq.params])"},
])
import json
print("RESULT", json.dumps(P.RESULTS))
PY

# -----------------------------------------------------------------------------
# 6. Edge nginx (port 8081 unchanged), docker-compose, ops helpers
# -----------------------------------------------------------------------------
log "edge nginx + docker-compose"

write_file nginx/nginx.conf <<'__EOF__'
# Edge nginx inside docker-compose. Host port 8081 -> here.  The domain nginx
# (https://mlmt.mobifone.vn) keeps proxying to 10.24.15.169:8081 exactly as before:
#     /api/      -> FastAPI          /sitelink/ -> SPA
worker_processes  auto;
worker_rlimit_nofile 16384;

events {
    worker_connections 4096;
    multi_accept on;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    sendfile           on;
    tcp_nopush         on;
    tcp_nodelay        on;
    keepalive_timeout  65;
    keepalive_requests 1000;
    server_tokens      off;
    client_max_body_size 100M;

    # Docker's embedded DNS: container names are re-resolved every 10 s, so a
    # restarted backend / frontend (new IP) never leaves nginx pointing at a dead address.
    resolver 127.0.0.11 valid=10s ipv6=off;
    resolver_timeout 5s;

    gzip            on;
    gzip_comp_level 5;
    gzip_min_length 1024;
    gzip_vary       on;
    gzip_proxied    any;
    gzip_types      application/json application/javascript text/css text/plain text/xml application/xml image/svg+xml;

    log_format main_t '$remote_addr "$request" $status $body_bytes_sent '
                      'rt=$request_time urt=$upstream_response_time xff="$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main_t;

    map $http_x_forwarded_proto $fwd_proto {
        default $http_x_forwarded_proto;
        ""      $scheme;
    }

    server {
        listen 80 default_server;
        server_name _;

        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $fwd_proto;
        proxy_redirect   off;
        proxy_connect_timeout 5s;

        # liveness probe for scripts / monitoring
        location = /health {
            set $be http://backend:8000;
            proxy_pass $be;
            access_log off;
        }

        # ── API -> FastAPI (path is passed through unchanged) ───────────────
        location /api/ {
            set $be http://backend:8000;
            proxy_pass $be;
            proxy_send_timeout 300s;
            proxy_read_timeout 300s;
            proxy_buffer_size       16k;
            proxy_buffers           32 32k;
            proxy_busy_buffers_size 64k;
            add_header Cache-Control "no-store, no-cache, must-revalidate" always;
            add_header Pragma        "no-cache" always;
        }

        location /docs {
            set $be http://backend:8000;
            proxy_pass $be;
        }

        location /openapi.json {
            set $be http://backend:8000;
            proxy_pass $be;
        }

        location = / {
            return 301 /sitelink/;
        }

        # ── Frontend SPA ─────────────────────────────────────────────────────
        location /sitelink/ {
            set $fe http://frontend:80;
            proxy_pass $fe;
            proxy_read_timeout 60s;
        }
    }
}
__EOF__

write_file docker-compose.yml <<'__EOF__'
services:
  postgres:
    image: postgres:15-alpine
    container_name: sitelink_postgres
    restart: unless-stopped
    env_file: .env
    shm_size: 256mb
    command: >
      postgres
      -c max_connections=200
      -c shared_buffers=256MB
      -c effective_cache_size=1GB
      -c work_mem=8MB
      -c maintenance_work_mem=128MB
      -c random_page_cost=1.1
      -c checkpoint_completion_target=0.9
      -c max_wal_size=2GB
      -c log_min_duration_statement=1000
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./postgres/init:/docker-entrypoint-initdb.d
    ports:
      - "127.0.0.1:5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"

  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: sitelink_backend
    restart: unless-stopped
    env_file: .env
    environment:
      FORWARDED_ALLOW_IPS: "*"
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      # only the data that must survive a rebuild (source code lives in the image)
      - ./backend/uploads:/app/uploads
      - ./backend/templates:/app/templates
    ports:
      - "127.0.0.1:8000:8000"
    stop_grace_period: 60s
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3)"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 90s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    container_name: sitelink_frontend
    restart: unless-stopped
    depends_on:
      - backend
    ports:
      - "127.0.0.1:5173:80"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1/sitelink/ >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"

  nginx:
    image: nginx:alpine
    container_name: sitelink_nginx
    restart: unless-stopped
    depends_on:
      backend:
        condition: service_healthy
      frontend:
        condition: service_started
    ports:
      - "8081:80"          # <- the domain nginx proxies to this port: DO NOT CHANGE
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"

volumes:
  postgres_data:
__EOF__

mkdir -p backend/uploads backend/templates ops backups

write_file ops/backup_db.sh <<'__EOF__'
#!/usr/bin/env bash
# Nightly PostgreSQL backup.  Cron example (every day 02:30):
#   30 2 * * *  /home/mlmt/work/src/SiteLink/ops/backup_db.sh >> /var/log/sitelink_backup.log 2>&1
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p backups
out="backups/sitelink_$(date +%F_%H%M).dump"
docker exec sitelink_postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$out"
find backups -name 'sitelink_*.dump' -mtime +14 -delete
echo "backup written: $out"
__EOF__
chmod +x ops/backup_db.sh

write_file ops/domain-nginx-suggestions.conf <<'__EOF__'
# =============================================================================
#  Suggested changes for the DOMAIN nginx (mlmt.mobifone.vn).  NOT applied by the
#  hardening script (it lives on another server).  All keep the same upstream
#  (10.24.15.169:8081) and the same /api/ + /sitelink/ paths.
# =============================================================================

# 1) server { listen 443 ... }   limit_conn addr 10;   is too low.
#    With HTTP/2 every concurrent request counts, and users behind one NAT share one IP.
#    A single SPA page load opens 10+ requests -> 503s for everybody behind that IP.
limit_conn addr 100;

# 2) In BOTH  location /api/  and  location /sitelink/  add this line.
#    Without it nginx sends "Connection: close" and the `keepalive 64;` pool of
#    upstream sitelink_up / sitelink_api_up is never used (new TCP connection per request).
proxy_set_header Connection "";

# 3) Excel/KMZ export and Excel import can run longer than the 120 s read timeout.
#    Put this block BEFORE the  location /api/  block.  Regex locations win over the
#    plain /api/ prefix; proxy_pass has NO URI part so the original URI is passed through.
location ~ ^/api/v1/(export/.*|[^/]+/import-excel(/dry-run)?)$ {
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Connection "";
    proxy_connect_timeout 3s;
    proxy_send_timeout 600s;
    proxy_read_timeout 600s;
    client_max_body_size 100M;
    proxy_pass http://sitelink_api_up;
}

# 4) Cheap hardening (server block)
add_header Strict-Transport-Security "max-age=31536000" always;
# ssl_protocols TLSv1.2 TLSv1.3;  ssl_session_cache shared:SSL:10m;  (if not already set in http{})
__EOF__

# -----------------------------------------------------------------------------
# 7. Syntax check of everything python we touched (abort + hint on failure)
# -----------------------------------------------------------------------------
log "checking python syntax"
PYFILES=(backend/gunicorn_conf.py backend/cell_sync_core.py backend/app/main.py backend/app/startup_tasks.py
         backend/app/db/session.py backend/app/db/perf_indexes.py backend/app/api/routes/sync.py
         backend/app/api/routes/cells_3g.py backend/app/api/routes/cells_4g.py backend/app/api/routes/cells_5g.py
         backend/app/api/routes/sites.py backend/app/api/routes/antenna.py backend/app/api/routes/export.py
         backend/app/services/revision.py)
bad=0
for f in "${PYFILES[@]}"; do
  [[ -f "$f" ]] || continue
  if ! python3 -c 'import ast,sys; ast.parse(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1])' "$f"; then
    warn "syntax error in $f"; bad=1
  fi
done
if [[ $bad -ne 0 ]]; then
  die "syntax check failed - NOTHING was deployed. Restore with:  cp -a '$BK/.' '$ROOT/'"
fi
ok "python syntax OK"

if [[ $DEPLOY -eq 0 ]]; then
  ok "patched only (--no-deploy). Deploy with:  $ROOT/harden_sitelink.sh  (or: docker compose build && docker compose up -d)"
  exit 0
fi

# -----------------------------------------------------------------------------
# 8. Deploy + smoke test
# -----------------------------------------------------------------------------
log "validating docker-compose.yml"
$DC config -q || die "docker-compose.yml is invalid - restore with: cp -a '$BK/.' '$ROOT/'"

log "building images (the frontend build takes a few minutes; the running site is not touched yet)"
$DC build

log "restarting the stack (about a minute of interruption)"
$DC up -d --remove-orphans
if docker exec sitelink_nginx nginx -t >/dev/null 2>&1; then
  docker exec sitelink_nginx nginx -s reload >/dev/null 2>&1 || true
fi

log "waiting for the application (up to 3 minutes)"
UP=0
for _ in $(seq 1 60); do
  if http_ok http://127.0.0.1:8081/health; then UP=1; break; fi
  sleep 3
done
if [[ $UP -ne 1 ]]; then
  $DC ps || true
  $DC logs --tail=60 backend || true
  die "backend did not become healthy. Roll back with:  cp -a '$BK/.' '$ROOT/' && $DC build && $DC up -d"
fi

pass=0; fail=0
for u in /health /api/v1/auth/sso/config /sitelink/; do
  if http_ok "http://127.0.0.1:8081$u"; then ok "GET $u"; pass=$((pass+1)); else warn "GET $u FAILED"; fail=$((fail+1)); fi
done
$DC ps

if [[ $LOADTEST -eq 1 ]]; then
  log "load check: 40 parallel users x 40 requests (edge nginx + gunicorn, no DB-heavy endpoints)"
  python3 - <<'PY'
import statistics, threading, time, urllib.request
URLS = ["http://127.0.0.1:8081/api/v1/auth/sso/config", "http://127.0.0.1:8081/sitelink/"]
THREADS, REQS = 40, 40
lat, errs, lock = [], [0], threading.Lock()

def worker(i):
    for k in range(REQS):
        t = time.time()
        try:
            with urllib.request.urlopen(URLS[(i + k) % len(URLS)], timeout=20) as r:
                r.read()
            with lock:
                lat.append(time.time() - t)
        except Exception:
            with lock:
                errs[0] += 1

t0 = time.time()
ts = [threading.Thread(target=worker, args=(i,)) for i in range(THREADS)]
[t.start() for t in ts]
[t.join() for t in ts]
el = time.time() - t0
lat.sort()
if lat:
    print(f"requests={len(lat)} errors={errs[0]} time={el:.1f}s rps={len(lat)/el:.0f} "
          f"p50={statistics.median(lat)*1000:.0f}ms p95={lat[int(len(lat)*0.95)-1]*1000:.0f}ms max={lat[-1]*1000:.0f}ms")
else:
    print("no successful requests", errs[0])
PY
fi

# -----------------------------------------------------------------------------
# 9. Summary
# -----------------------------------------------------------------------------
echo
ok "done - smoke checks passed: $pass, failed: $fail"
cat <<__SUMMARY__

  Backup of every replaced file : $BK
  Roll back                     : cp -a '$BK/.' '$ROOT/' && $DC build && $DC up -d

  TODO (manual)
   1. Domain nginx : apply ops/domain-nginx-suggestions.conf (limit_conn 10 is the main risk)
   2. Log in as admin and CHANGE the default admin/admin password
   3. Rotate the SSO client secret + vendor CSV tokens (they are hard-coded in the repo)
   4. Schedule backups   : crontab -e  ->  30 2 * * *  $ROOT/ops/backup_db.sh
   5. Make sure Docker starts at boot : sudo systemctl enable docker
   6. Port 5432/8000/5173 are now bound to 127.0.0.1 only (edge nginx on 8081 is unchanged)

__SUMMARY__
[[ $fail -eq 0 ]]