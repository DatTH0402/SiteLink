"""
sync.py
-------
Cell sync endpoints.

POST /api/v1/sync/cells/wait  — SYNCHRONOUS, waits for completion.
  Use this for small batches (single-cell form create, small imports).
  Returns the sync result directly. Frontend doesn't need to poll.
  Timeout: 120s (CSV downloads take ~5-30s total).

POST /api/v1/sync/cells       — ASYNC background task + polling.
  Use this for large batches (bulk operations).

GET  /api/v1/sync/status/{job_id}  — poll async job status.
"""
from __future__ import annotations

import logging
import os
import sys
import uuid
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Set

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.utils.deps import get_current_user
from app.models.user import User
from app.core.config import settings

log    = logging.getLogger(__name__)
router = APIRouter()

_jobs: Dict[str, Dict[str, Any]] = {}
MAX_CELLS_SYNC  = 10_000   # async limit
MAX_CELLS_WAIT  = 2_000     # sync/wait limit (keeps HTTP timeout reasonable)
WAIT_TIMEOUT_S  = 600     # 3 min max for synchronous endpoint

_executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="cell-sync")


# ── Find cell_sync_core.py ────────────────────────────────────────────────────

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
    # fallback: two levels up from app/api/routes/ = backend/
    return os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


_BACKEND_DIR = _find_backend_dir()
log.info("cell_sync_core dir: %s (exists=%s)",
         _BACKEND_DIR,
         os.path.isfile(os.path.join(_BACKEND_DIR, "cell_sync_core.py")))


def _import_core():
    if _BACKEND_DIR not in sys.path:
        sys.path.insert(0, _BACKEND_DIR)
    import cell_sync_core as core  # noqa
    return core


def _do_sync(
    table:     str,
    names:     List[str],
    vendors:   Optional[Set[str]],
    source_df  = None,   # pre-loaded DataFrame — avoids repeated CSV downloads
) -> Dict:
    core   = _import_core()
    from sqlalchemy import create_engine  # noqa
    engine = create_engine(settings.DATABASE_URL, pool_pre_ping=True)
    return core.sync_cells(engine, table, names, vendors, source_df=source_df)


def _do_sync_with_preload(table: str, names: List[str], vendors: Optional[Set[str]]) -> Dict:
    """Download CSVs once, then sync all cells. Used by /batch endpoint."""
    core = _import_core()
    from sqlalchemy import create_engine  # noqa
    engine = create_engine(settings.DATABASE_URL, pool_pre_ping=True)
    # Download vendor CSVs once
    source_df = core.load_vendor_data(table.replace("cells_", ""), vendors)
    log.info("Pre-loaded %d rows from vendor CSVs for %s", len(source_df), table)
    return core.sync_cells(engine, table, names, vendors, source_df=source_df)


# ── Schemas ───────────────────────────────────────────────────────────────────

class SyncRequest(BaseModel):
    tech:       str
    cell_names: List[str]
    vendors:    Optional[List[str]] = None


class SyncResult(BaseModel):
    updated:      int = 0
    skipped:      int = 0
    not_in_db:    int = 0
    not_in_csv:   int = 0
    errors:       int = 0
    error_details: List[str] = []


class SyncWaitResponse(BaseModel):
    """Returned by the synchronous /wait endpoint."""
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


# ── Helpers ───────────────────────────────────────────────────────────────────

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


# ── Synchronous endpoint ──────────────────────────────────────────────────────

@router.post("/cells/wait", response_model=SyncWaitResponse)
def sync_cells_wait(
    payload:      SyncRequest,
    db:           Session = Depends(get_db),
    current_user: User    = Depends(get_current_user),
):
    """
    Synchronous sync — waits until CSV download + DB update are done,
    then returns the result in a single response.

    The frontend does NOT need to poll; it just awaits this HTTP call.
    Use for small batches (≤ 500 cells).
    """
    table, names, vendors = _parse_request(payload)
    if len(names) > MAX_CELLS_WAIT:
        raise HTTPException(
            400,
            f"Too many cells for /wait ({len(names)} > {MAX_CELLS_WAIT}). "
            "Use POST /cells for large batches."
        )

    t0 = datetime.now(timezone.utc)
    log.info("sync/wait: %s %d cells user=%s", table, len(names), current_user.username)

    try:
        future = _executor.submit(_do_sync, table, names, vendors)
        stats  = future.result(timeout=WAIT_TIMEOUT_S)
    except FutureTimeout:
        raise HTTPException(504, "Sync timed out — source CSV download too slow. Try again.")
    except Exception as exc:
        log.exception("sync/wait failed")
        raise HTTPException(500, f"Sync failed: {exc}")

    duration = (datetime.now(timezone.utc) - t0).total_seconds()
    log.info("sync/wait done in %.1fs: %s", duration, stats)

    return SyncWaitResponse(
        table_name=table,
        cell_count=len(names),
        result=SyncResult(**{k: stats.get(k, 0) if k != "error_details"
                             else stats.get(k, [])
                             for k in SyncResult.model_fields}),
        duration_s=round(duration, 2),
    )


# ── Async endpoint ────────────────────────────────────────────────────────────


@router.post("/cells/batch", response_model=SyncWaitResponse)
def sync_cells_batch(
    payload:      SyncRequest,
    db:           Session = Depends(get_db),
    current_user: User    = Depends(get_current_user),
):
    """
    Batch sync — downloads vendor CSVs ONCE then processes ALL cell names.

    Unlike /wait (which also downloads once per call), /batch is designed
    for large imports: no chunking, no repeated CSV downloads, single
    DB transaction pass.  Handles up to 10 000 cells.

    Synchronous — waits for completion and returns result directly.
    Timeout: 10 minutes.
    """
    table, names, vendors = _parse_request(payload)
    if len(names) > 10_000:
        raise HTTPException(400, f"Too many cells ({len(names)} > 10 000)")

    t0 = datetime.now(timezone.utc)
    log.info("sync/batch: %s %d cells user=%s", table, len(names), current_user.username)

    try:
        future = _executor.submit(_do_sync_with_preload, table, names, vendors)
        stats  = future.result(timeout=600)
    except FutureTimeout:
        raise HTTPException(504, "Sync timed out after 10 minutes")
    except Exception as exc:
        log.exception("sync/batch failed")
        raise HTTPException(500, f"Sync failed: {exc}")

    duration = (datetime.now(timezone.utc) - t0).total_seconds()
    log.info("sync/batch done in %.1fs: %s", duration, stats)

    return SyncWaitResponse(
        table_name=table,
        cell_count=len(names),
        result=SyncResult(**{
            k: stats.get(k, 0) if k != "error_details" else stats.get(k, [])
            for k in SyncResult.model_fields
        }),
        duration_s=round(duration, 2),
    )

@router.post("/cells", response_model=SyncJobResponse, status_code=202)
def sync_cells_async(
    payload:          SyncRequest,
    background_tasks: BackgroundTasks,
    db:               Session = Depends(get_db),
    current_user:     User    = Depends(get_current_user),
):
    """Async sync — returns job_id immediately, use /status/{job_id} to poll."""
    table, names, vendors = _parse_request(payload)
    if len(names) > MAX_CELLS_SYNC:
        raise HTTPException(400, f"Too many cells (max {MAX_CELLS_SYNC})")

    job_id = str(uuid.uuid4())
    _jobs[job_id] = {
        "status": "queued", "started_at": None, "finished_at": None,
        "result": None, "error": None, "tech": payload.tech.lower(),
        "cell_count": len(names), "requested_by": current_user.username,
    }
    background_tasks.add_task(_run_async_job, job_id, table, names, vendors)
    return SyncJobResponse(
        job_id=job_id, status="queued", cell_count=len(names),
        message=f"Đồng bộ {len(names)} cell {payload.tech.upper()} đã được khởi động.",
    )


def _run_async_job(job_id, table, names, vendors):
    _jobs[job_id]["status"]     = "running"
    _jobs[job_id]["started_at"] = datetime.now(timezone.utc).isoformat()
    try:
        stats = _do_sync(table, names, vendors)
        _jobs[job_id].update(
            status="done", result=stats,
            finished_at=datetime.now(timezone.utc).isoformat())
    except Exception as exc:
        _jobs[job_id].update(
            status="error", error=str(exc),
            finished_at=datetime.now(timezone.utc).isoformat())
        log.exception("async job %s failed", job_id)


@router.get("/status/{job_id}", response_model=SyncStatusResponse)
def get_sync_status(job_id: str, _: User = Depends(get_current_user)):
    job = _jobs.get(job_id)
    if not job:
        raise HTTPException(404, "Job not found")
    return SyncStatusResponse(
        job_id=job_id, status=job["status"],
        started_at=job.get("started_at"), finished_at=job.get("finished_at"),
        result=job.get("result"), error=job.get("error"))




@router.get("/recent")
def get_recent_cells(
    table:   str,
    minutes: int = 60,
    since:   str = "",
    _: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Return cell_names created/updated recently.

    Parameters
    ----------
    table   : cells_3g | cells_4g | cells_5g
    minutes : look back N minutes from now (used if `since` not provided)
    since   : ISO 8601 timestamp — return cells created/updated after this
              exact moment.  More reliable than `minutes` for large imports
              because it uses the timestamp captured BEFORE import started.

    Returns up to 50000 names — enough for any realistic import.
    """
    from sqlalchemy import text as sa_text

    valid_tables = {"cells_3g", "cells_4g", "cells_5g"}
    if table not in valid_tables:
        raise HTTPException(400, f"table must be one of {valid_tables}")

    try:
        if since:
            # Use exact timestamp — most reliable
            rows = db.execute(sa_text(f"""
                SELECT cell_name FROM {table}
                WHERE cell_name IS NOT NULL
                  AND (
                    created_at >= :since
                    OR updated_at >= :since
                  )
                ORDER BY COALESCE(created_at, updated_at) DESC
                LIMIT 50000
            """), {"since": since}).fetchall()
        else:
            # Fallback: time window from now
            rows = db.execute(sa_text(f"""
                SELECT cell_name FROM {table}
                WHERE cell_name IS NOT NULL
                  AND (
                    created_at >= NOW() - INTERVAL '{minutes} minutes'
                    OR updated_at >= NOW() - INTERVAL '{minutes} minutes'
                  )
                ORDER BY COALESCE(created_at, updated_at) DESC
                LIMIT 50000
            """)).fetchall()

        names = [r[0] for r in rows if r[0]]
        log.info("/recent %s: %d names (since=%r minutes=%d)",
                 table, len(names), since, minutes)
        return {"cell_names": names, "count": len(names)}

    except Exception as exc:
        log.error("get_recent_cells: %s", exc, exc_info=True)
        raise HTTPException(500, str(exc))

