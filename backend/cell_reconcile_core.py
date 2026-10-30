"""
cell_reconcile_core.py
----------------------
Reconciliation of the cells known to the web app (DB) against the cells found in the
vendor "dump" CSV files (same sources / builders as cell_sync_core.py).

For every technology (3G / 4G / 5G) two directions are reported:

  missing_in_web   cell is in the dump with an ACTIVE status (UNLOCKED, UNBLOCKED,
                   CELL_UNBLOCK, Active ...) but does NOT exist in the web DB.
  missing_in_dump  cell exists in the web DB but is NOT in any dump file.

Matching key = cell_name only (same rule as the sync): all web cells that share a
cell_name (different subcell_id) match the dump cell of that name.

Safety nets (a bad download must never produce a flood of false alarms):
  * a vendor file that can not be downloaded while the web holds cells of that vendor
    -> the technology is NOT reconciled (run stored with status 'error')
  * dump row count < RECONCILE_MIN_RATIO (default 0.5) x previous successful run -> 'error'
  * web cells of vendors that have no dump source at all (ZTE, Samsung, ...) are kept
    but flagged dump_covered='N' and left out of the headline numbers.

Environment:
  RECONCILE_ACTIVE_STATUSES  extra status values counted as active (comma separated)
  RECONCILE_KEEP_RUNS        successful runs per tech whose detail rows are kept (default 7)
  RECONCILE_KEEP_DAYS        run summaries older than this are deleted (default 400)
  RECONCILE_MIN_RATIO        sanity ratio described above (default 0.5)
  RECONCILE_WEBHOOK_URL      optional: POST {"text": "..."} (Teams / Slack style) after a run
"""
from __future__ import annotations

import json
import logging
import os
import re
import uuid
from collections import Counter
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

import pandas as pd
import requests
from sqlalchemy import inspect, text

import cell_sync_core as core

log = logging.getLogger(__name__)

TECHS = ("3g", "4g", "5g")
TABLES = {"3g": "cells_3g", "4g": "cells_4g", "5g": "cells_5g"}
DUMP_VENDORS = tuple(sorted(core.ALL_VENDORS))

KEEP_RUNS = int(os.environ.get("RECONCILE_KEEP_RUNS", "7"))
KEEP_DAYS = int(os.environ.get("RECONCILE_KEEP_DAYS", "400"))
MIN_RATIO = float(os.environ.get("RECONCILE_MIN_RATIO", "0.5"))
WEBHOOK_URL = os.environ.get("RECONCILE_WEBHOOK_URL", "").strip()
INSERT_BATCH = 2000


# ── status classification ────────────────────────────────────────────────────
def status_key(v: Any) -> str:
    return re.sub(r"[^a-z0-9]", "", str(v or "").lower())


_DEFAULT_ACTIVE = {
    "unblocked", "unblock", "unlocked", "unlock", "cellunblock", "cellunblocked",
    "cellunlock", "active", "enabled", "enable", "inservice",
}
ACTIVE_KEYS = _DEFAULT_ACTIVE | {
    status_key(x) for x in os.environ.get("RECONCILE_ACTIVE_STATUSES", "").split(",") if status_key(x)
}


def is_active_status(v: Any) -> bool:
    return status_key(v) in ACTIVE_KEYS


# ── schema ───────────────────────────────────────────────────────────────────
INT_RUN_COLS = [
    "dump_total", "dump_active", "dump_inactive", "web_total", "matched",
    "missing_in_web", "missing_in_dump", "missing_in_dump_uncovered", "dump_inactive_not_in_web",
    "new_missing_in_web", "new_missing_in_dump", "resolved_missing_in_web", "resolved_missing_in_dump",
]
RUN_COLS = (["batch_id", "tech", "run_date", "started_at", "finished_at", "status", "error", "prev_run_id"]
            + INT_RUN_COLS + ["vendor_status", "status_stats"])

ITEM_LEN = {
    "direction": 20, "cell_name": 200, "subcell_id": 50, "site_name": 200, "vendor": 50,
    "mien": 10, "tinh": 100, "phuong_xa": 150, "cell_status": 100, "bbu_name": 200, "rf": 200,
    "oss": 50, "dump_date": 50, "cell_id": 50, "node_id": 50, "freq": 50, "pci": 50, "tac": 50,
    "bandwidth": 50, "mimo": 100, "web_updated_at": 30, "first_seen": 10, "dump_covered": 1,
}
ITEM_COLS = [
    "direction", "cell_name", "subcell_id", "web_id", "site_name", "vendor", "mien", "tinh",
    "phuong_xa", "cell_status", "bbu_name", "rf", "oss", "dump_date", "cell_id", "node_id",
    "freq", "pci", "tac", "bandwidth", "mimo", "web_updated_at", "first_seen", "dump_covered",
]

INSERT_RUN_SQL = ("INSERT INTO cell_reconcile_runs (%s) VALUES (%s) RETURNING id"
                  % (", ".join(RUN_COLS), ", ".join(":" + c for c in RUN_COLS)))
INSERT_ITEM_SQL = ("INSERT INTO cell_reconcile_items (run_id, tech, %s) VALUES (:run_id, :tech, %s)"
                   % (", ".join(ITEM_COLS), ", ".join(":" + c for c in ITEM_COLS)))

DDL = [
    """CREATE TABLE IF NOT EXISTS cell_reconcile_runs (
        id SERIAL PRIMARY KEY,
        batch_id VARCHAR(40),
        tech VARCHAR(5) NOT NULL,
        run_date VARCHAR(10),
        started_at TIMESTAMPTZ,
        finished_at TIMESTAMPTZ,
        status VARCHAR(20) NOT NULL DEFAULT 'ok',
        error TEXT,
        prev_run_id INTEGER,
        dump_total INTEGER DEFAULT 0,
        dump_active INTEGER DEFAULT 0,
        dump_inactive INTEGER DEFAULT 0,
        web_total INTEGER DEFAULT 0,
        matched INTEGER DEFAULT 0,
        missing_in_web INTEGER DEFAULT 0,
        missing_in_dump INTEGER DEFAULT 0,
        missing_in_dump_uncovered INTEGER DEFAULT 0,
        dump_inactive_not_in_web INTEGER DEFAULT 0,
        new_missing_in_web INTEGER DEFAULT 0,
        new_missing_in_dump INTEGER DEFAULT 0,
        resolved_missing_in_web INTEGER DEFAULT 0,
        resolved_missing_in_dump INTEGER DEFAULT 0,
        vendor_status TEXT,
        status_stats TEXT
    )""",
    "CREATE INDEX IF NOT EXISTS ix_cell_reconcile_runs_tech_id ON cell_reconcile_runs (tech, id)",
    """CREATE TABLE IF NOT EXISTS cell_reconcile_items (
        id SERIAL PRIMARY KEY,
        run_id INTEGER NOT NULL,
        tech VARCHAR(5) NOT NULL,
        direction VARCHAR(20) NOT NULL,
        cell_name VARCHAR(200),
        subcell_id VARCHAR(50),
        web_id INTEGER,
        site_name VARCHAR(200),
        vendor VARCHAR(50),
        mien VARCHAR(10),
        tinh VARCHAR(100),
        phuong_xa VARCHAR(150),
        cell_status VARCHAR(100),
        bbu_name VARCHAR(200),
        rf VARCHAR(200),
        oss VARCHAR(50),
        dump_date VARCHAR(50),
        cell_id VARCHAR(50),
        node_id VARCHAR(50),
        freq VARCHAR(50),
        pci VARCHAR(50),
        tac VARCHAR(50),
        bandwidth VARCHAR(50),
        mimo VARCHAR(100),
        web_updated_at VARCHAR(30),
        first_seen VARCHAR(10),
        dump_covered VARCHAR(1)
    )""",
    "CREATE INDEX IF NOT EXISTS ix_cell_reconcile_items_run_dir ON cell_reconcile_items (run_id, direction)",
]


def ensure_tables(engine) -> None:
    with engine.begin() as conn:
        for ddl in DDL:
            conn.execute(text(ddl))


# ── field mapping (dump builders and web tables share the DB column names) ───
FIELD_MAP = {
    "3g": {"node_id": None,        "freq": "uarfcn",    "pci": "psc", "tac": "lac", "bandwidth": None},
    "4g": {"node_id": "enodeb_id", "freq": "earfcn",    "pci": "pci", "tac": "tac", "bandwidth": "bandwidth"},
    "5g": {"node_id": "gnodeb_id", "freq": "ssb_arfcn", "pci": "pci", "tac": "tac", "bandwidth": "bandwidth"},
}
WEB_COLS_WANTED = [
    "id", "cell_name", "subcell_id", "site_id", "site_name", "vendor", "mien", "tinh", "phuong_xa",
    "cell_status", "bbu_name", "rf", "oss", "dump_date", "cell_id", "enodeb_id", "gnodeb_id",
    "earfcn", "uarfcn", "ssb_arfcn", "psc", "pci", "lac", "tac", "bandwidth", "mimo",
    "updated_at", "created_at",
]


def _pick(src: Dict[str, Any], key: Optional[str]) -> Optional[str]:
    if not key:
        return None
    v = core._clean(src.get(key))
    return None if v is None or v == core._KEEP else v


def _tech_fields(tech: str, src: Dict[str, Any]) -> Dict[str, Any]:
    m = FIELD_MAP[tech]
    return {
        "cell_status": _pick(src, "cell_status"), "bbu_name": _pick(src, "bbu_name"),
        "rf": _pick(src, "rf"), "oss": _pick(src, "oss"), "dump_date": _pick(src, "dump_date"),
        "cell_id": _pick(src, "cell_id"), "node_id": _pick(src, m["node_id"]),
        "freq": _pick(src, m["freq"]), "pci": _pick(src, m["pci"]), "tac": _pick(src, m["tac"]),
        "bandwidth": _pick(src, m["bandwidth"]), "mimo": _pick(src, "mimo"),
    }


def _cut(col: str, v: Any) -> Any:
    if isinstance(v, str):
        v = v.replace("\x00", "")
        n = ITEM_LEN.get(col)
        if n and len(v) > n:
            v = v[:n]
    return v


# ── loading ──────────────────────────────────────────────────────────────────
def load_geo(engine) -> Dict[str, Tuple[Optional[str], str, Optional[str]]]:
    """first 6 characters of a cell name -> (mien, tinh, phuong_xa)  (dropdown_tinh_xa_phuong)."""
    try:
        with engine.connect() as conn:
            rows = conn.execute(text(
                "SELECT ky_tu_1_6, ma_tinh, ma_phuong_xa, ten_tinh, ten_phuong_xa, mien "
                "FROM dropdown_tinh_xa_phuong ORDER BY id")).fetchall()
    except Exception as exc:
        log.warning("geo lookup unavailable (%s) - province of dump-only cells will be empty", exc)
        return {}
    out: Dict[str, Tuple[Optional[str], str, Optional[str]]] = {}
    for ky, mt, mx, tinh, xa, mien in rows:
        code = (ky or "").strip().upper() or ("%s%s" % (mt or "", mx or "")).strip().upper()
        if code and tinh and code not in out:
            out[code] = (mien or None, tinh, xa or None)
    return out


def load_web(engine, table: str) -> List[Dict[str, Any]]:
    have = {c["name"] for c in inspect(engine).get_columns(table)}
    cols = [c for c in WEB_COLS_WANTED if c in have]
    with engine.connect() as conn:
        rows = conn.execute(text("SELECT %s FROM %s" % (", ".join(cols), table))).mappings().all()
    return [dict(r) for r in rows]


def _prev_ok_run(engine, tech: str) -> Tuple[Optional[int], int]:
    try:
        with engine.connect() as conn:
            r = conn.execute(text(
                "SELECT id, dump_total FROM cell_reconcile_runs "
                "WHERE tech = :t AND status = 'ok' ORDER BY id DESC LIMIT 1"), {"t": tech}).first()
        return (int(r[0]), int(r[1] or 0)) if r else (None, 0)
    except Exception:
        return None, 0


def _prev_items(engine, run_id: int) -> Dict[tuple, Tuple[Optional[str], str]]:
    with engine.connect() as conn:
        rows = conn.execute(text(
            "SELECT direction, cell_name, COALESCE(subcell_id, ''), COALESCE(web_id, 0), first_seen, "
            "COALESCE(dump_covered, 'Y') FROM cell_reconcile_items WHERE run_id = :r"), {"r": run_id}).fetchall()
    return {(d, n, s, w): (fs, cov) for d, n, s, w, fs, cov in rows}


# ── item builders ────────────────────────────────────────────────────────────
def _dump_item(tech: str, rec: Dict[str, Any], geo) -> Dict[str, Any]:
    name = rec["cell_name"]
    mien = tinh = xa = None
    if len(name) >= 6:
        hit = geo.get(name.upper()[:6])
        if hit:
            mien, tinh, xa = hit
    return {
        "direction": "missing_in_web", "cell_name": name, "subcell_id": None, "web_id": None,
        "site_name": None, "vendor": rec.get("_vendor"), "mien": mien, "tinh": tinh, "phuong_xa": xa,
        "dump_covered": "Y", "web_updated_at": None, **_tech_fields(tech, rec),
    }


def _web_item(tech: str, r: Dict[str, Any], name: str) -> Dict[str, Any]:
    vendor = core._clean(r.get("vendor"))
    covered = "Y" if (not vendor or vendor.lower() in core.ALL_VENDORS) else "N"
    upd = r.get("updated_at") or r.get("created_at")
    if hasattr(upd, "strftime"):
        upd_s = upd.strftime("%Y-%m-%d %H:%M")
    else:
        upd_s = str(upd)[:16] if upd else None
    return {
        "direction": "missing_in_dump", "cell_name": name, "subcell_id": core._clean(r.get("subcell_id")),
        "web_id": r.get("id"), "site_name": core._clean(r.get("site_name")), "vendor": vendor,
        "mien": core._clean(r.get("mien")), "tinh": core._clean(r.get("tinh")),
        "phuong_xa": core._clean(r.get("phuong_xa")), "dump_covered": covered,
        "web_updated_at": upd_s, **_tech_fields(tech, r),
    }


def _key(it: Dict[str, Any]) -> tuple:
    return (it["direction"], it["cell_name"], it.get("subcell_id") or "", it.get("web_id") or 0)


# ── core computation (one technology) ────────────────────────────────────────
def _compute(engine, tech: str, geo, run: Dict[str, Any]) -> List[Dict[str, Any]]:
    run_date = run["run_date"]
    web_rows = load_web(engine, TABLES[tech])
    web_vendor_cnt = Counter((core._clean(r.get("vendor")) or "").lower() for r in web_rows)

    frames: List[pd.DataFrame] = []
    files: Dict[str, Dict[str, Any]] = {}
    for vendor in DUMP_VENDORS:
        try:
            df = core._vendor_frame(tech, vendor)
        except Exception as exc:
            log.warning("dump %s/%s failed: %s", vendor, tech, exc)
            df = None
        if df is None or df.empty:
            files[vendor] = {"ok": False, "rows": 0}
        else:
            f = df.copy()
            f["_vendor"] = vendor.title()
            frames.append(f)
            files[vendor] = {"ok": True, "rows": int(len(f))}
    notes: List[str] = []
    run["vendor_status"] = {"files": files, "notes": notes, "duplicate_names": 0}

    failed = [v for v, s in files.items() if not s["ok"]]
    blocking = [v for v in failed if web_vendor_cnt.get(v, 0) > 0]
    if not frames:
        raise RuntimeError("Không tải được bất kỳ file dump %s nào." % tech.upper())
    if blocking:
        raise RuntimeError(
            "File dump %s của vendor %s không tải được nhưng web đang có cell của vendor này "
            "-> bỏ qua đối soát để tránh báo sai." % (tech.upper(), ", ".join(blocking)))
    for v in failed:
        notes.append("File dump %s %s trống/không tải được; web không có cell của vendor này nên bỏ qua." % (v, tech.upper()))

    dump = pd.concat(frames, ignore_index=True)
    dump["cell_name"] = dump["cell_name"].map(lambda v: core._clean(v) or "")
    dump = dump[dump["cell_name"] != ""].copy()
    if "cell_status" in dump.columns:
        dump["_active"] = dump["cell_status"].map(is_active_status).astype(bool)
    else:
        dump["_active"] = False
    before = len(dump)
    dump = dump.sort_values("_active", ascending=False, kind="stable").drop_duplicates("cell_name", keep="first")
    run["vendor_status"]["duplicate_names"] = int(before - len(dump))

    prev_id, prev_total = _prev_ok_run(engine, tech)
    run["prev_run_id"] = prev_id
    if prev_total and len(dump) < MIN_RATIO * prev_total:
        raise RuntimeError(
            "Dữ liệu dump %s giảm bất thường (%d cell, lần trước %d) -> bỏ qua đối soát; "
            "kiểm tra các file CSV nguồn." % (tech.upper(), len(dump), prev_total))

    stat_counter = Counter((core._clean(v) or "") for v in dump["cell_status"]) if "cell_status" in dump.columns else Counter()
    run["status_stats"] = [
        {"status": s or "(Trống)", "active": is_active_status(s), "count": c}
        for s, c in stat_counter.most_common(60)
    ]

    web_names = {(core._clean(r.get("cell_name")) or "") for r in web_rows}
    web_names.discard("")
    dump_names = set(dump["cell_name"])

    items: List[Dict[str, Any]] = []
    matched = inactive_not_in_web = 0
    for rec in dump.to_dict("records"):
        if rec["cell_name"] in web_names:
            matched += 1
            continue
        if not rec["_active"]:
            inactive_not_in_web += 1
            continue
        items.append(_dump_item(tech, rec, geo))
    for r in web_rows:
        name = core._clean(r.get("cell_name")) or ""
        if not name or name in dump_names:
            continue
        items.append(_web_item(tech, r, name))

    # first_seen / new / resolved vs the previous successful run
    prev: Dict[tuple, Tuple[Optional[str], str]] = {}
    if prev_id:
        try:
            prev = _prev_items(engine, prev_id)
        except Exception as exc:
            log.warning("previous run items unavailable: %s", exc)
    cur_keys = set()
    new_web = new_dump = 0
    for it in items:
        k = _key(it)
        cur_keys.add(k)
        hit = prev.get(k)
        it["first_seen"] = (hit[0] if hit and hit[0] else run_date)
        if prev_id and hit is None:
            if it["direction"] == "missing_in_web":
                new_web += 1
            elif it["dump_covered"] != "N":
                new_dump += 1
    res_web = sum(1 for k in prev if k[0] == "missing_in_web" and k not in cur_keys)
    res_dump = sum(1 for k, v in prev.items() if k[0] == "missing_in_dump" and v[1] != "N" and k not in cur_keys)

    n_web = sum(1 for it in items if it["direction"] == "missing_in_web")
    n_dump = sum(1 for it in items if it["direction"] == "missing_in_dump" and it["dump_covered"] != "N")
    n_unc = sum(1 for it in items if it["direction"] == "missing_in_dump" and it["dump_covered"] == "N")
    active = int(dump["_active"].sum())
    run.update(
        dump_total=int(len(dump)), dump_active=active, dump_inactive=int(len(dump)) - active,
        web_total=int(len(web_rows)), matched=int(matched),
        missing_in_web=n_web, missing_in_dump=n_dump, missing_in_dump_uncovered=n_unc,
        dump_inactive_not_in_web=int(inactive_not_in_web),
        new_missing_in_web=new_web, new_missing_in_dump=new_dump,
        resolved_missing_in_web=res_web, resolved_missing_in_dump=res_dump,
    )
    return items


def compute_tech(engine, tech: str, geo, batch_id: str) -> Dict[str, Any]:
    run: Dict[str, Any] = {c: 0 for c in INT_RUN_COLS}
    run.update(batch_id=batch_id, tech=tech, run_date=datetime.now().strftime("%Y-%m-%d"),
               started_at=datetime.now(timezone.utc), finished_at=None, status="ok", error=None,
               prev_run_id=None, vendor_status=None, status_stats=None)
    items: List[Dict[str, Any]] = []
    try:
        items = _compute(engine, tech, geo, run)
    except Exception as exc:
        log.error("reconcile %s failed: %s", tech, exc, exc_info=True)
        run.update(status="error", error=str(exc)[:500])
        items = []
    run["finished_at"] = datetime.now(timezone.utc)
    return {"run": run, "items": items}


# ── persistence ──────────────────────────────────────────────────────────────
def save_result(engine, res: Dict[str, Any], keep_runs: int) -> int:
    run, items = res["run"], res["items"]
    params = {c: run.get(c) for c in RUN_COLS}
    for c in ("vendor_status", "status_stats"):
        params[c] = json.dumps(run[c], ensure_ascii=False) if run.get(c) is not None else None
    with engine.begin() as conn:
        run_id = int(conn.execute(text(INSERT_RUN_SQL), params).scalar())
        sql = text(INSERT_ITEM_SQL)
        for i in range(0, len(items), INSERT_BATCH):
            batch = []
            for it in items[i:i + INSERT_BATCH]:
                row = {c: _cut(c, it.get(c)) for c in ITEM_COLS}
                row["run_id"], row["tech"] = run_id, run["tech"]
                batch.append(row)
            conn.execute(sql, batch)
        if run["status"] == "ok":
            conn.execute(text(
                "DELETE FROM cell_reconcile_items WHERE tech = :t AND run_id NOT IN ("
                "SELECT id FROM cell_reconcile_runs WHERE tech = :t AND status = 'ok' "
                "ORDER BY id DESC LIMIT :k)"), {"t": run["tech"], "k": keep_runs})
            conn.execute(text(
                "DELETE FROM cell_reconcile_runs WHERE started_at < NOW() - make_interval(days => :d)"),
                {"d": KEEP_DAYS})
    return run_id


def _print_run(run: Dict[str, Any], n_items: int) -> None:
    if run["status"] != "ok":
        print("   ❌ %s: %s" % (run["tech"].upper(), run.get("error")))
        return
    print("   dump: %d cells (%d active) | web: %d cells | matched: %d"
          % (run["dump_total"], run["dump_active"], run["web_total"], run["matched"]))
    print("   ▶ active in dump, NOT on web : %d   (new %d, resolved %d)"
          % (run["missing_in_web"], run["new_missing_in_web"], run["resolved_missing_in_web"]))
    print("   ▶ on web, NOT in dump        : %d   (new %d, resolved %d)   [+%d vendors without dump source]"
          % (run["missing_in_dump"], run["new_missing_in_dump"], run["resolved_missing_in_dump"],
             run["missing_in_dump_uncovered"]))
    print("   (not-active dump cells missing on web, ignored: %d)  detail rows: %d"
          % (run["dump_inactive_not_in_web"], n_items))
    for note in (run.get("vendor_status") or {}).get("notes", []):
        print("   ℹ " + note)


def _notify(results: List[Dict[str, Any]]) -> None:
    if not WEBHOOK_URL:
        return
    lines = ["[SiteLink] Đối soát cell dump ↔ web - %s" % datetime.now().strftime("%Y-%m-%d")]
    for res in results:
        r = res["run"]
        if r["status"] != "ok":
            lines.append("%s: LỖI - %s" % (r["tech"].upper(), r.get("error")))
        else:
            lines.append("%s: %d cell active trong dump chưa có trên web (+%d mới); %d cell có trên web không có trong dump (+%d mới)"
                         % (r["tech"].upper(), r["missing_in_web"], r["new_missing_in_web"],
                            r["missing_in_dump"], r["new_missing_in_dump"]))
    try:
        requests.post(WEBHOOK_URL, json={"text": "\n".join(lines)}, timeout=15)
    except Exception as exc:
        log.warning("webhook failed: %s", exc)


def run_reconcile(engine, techs=TECHS, dry_run: bool = False, keep_runs: Optional[int] = None) -> int:
    """Reconcile the requested technologies. Returns 0 when every tech succeeded, else 1."""
    keep = max(2, keep_runs or KEEP_RUNS)
    if not dry_run:
        ensure_tables(engine)
    geo = load_geo(engine)
    batch_id = uuid.uuid4().hex
    rc = 0
    results: List[Dict[str, Any]] = []
    for tech in techs:
        print("\n--- %s reconcile%s ---" % (tech.upper(), " (DRY RUN)" if dry_run else ""))
        res = compute_tech(engine, tech, geo, batch_id)
        _print_run(res["run"], len(res["items"]))
        if res["run"]["status"] != "ok":
            rc = 1
        if not dry_run:
            try:
                rid = save_result(engine, res, keep)
                print("   saved as run #%d" % rid)
            except Exception as exc:
                print("   ❌ could not save results: %s" % exc)
                log.exception("save_result failed")
                rc = 1
        results.append(res)
    if not dry_run:
        _notify(results)
    return rc
