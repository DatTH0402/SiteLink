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
