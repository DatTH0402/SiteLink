#!/usr/bin/env bash
# =============================================================================
#  add_reconcile.sh  -  Reconciliation of cells: DUMP (vendor CSV) <-> WEB (DB)
#
#  Usage:  bash add_reconcile.sh [PROJECT_ROOT] [options]
#    --migrate      create the 2 tables (python backend/reconcile_cells.py --init-db)
#    --dry-run-now  run the reconciliation once WITHOUT writing anything
#    --run-now      run the reconciliation once for real (downloads all vendor CSVs)
#    --force        re-apply even if already applied (existing files are backed up)
#
#  - Modified / overwritten files are backed up to <root>/.reconcile_backup_<ts>/
#  - Hard anchors are verified in memory first; nothing is written if one fails.
#  - Route / menu / router registration use "soft" patches: if the layout of your
#    App.tsx / menu / main.py is not recognised, the script tells you what to add.
# =============================================================================
set -euo pipefail

usage() { sed -n '2,16p' "$0"; }

ROOT="."; DO_MIGRATE=0; RUN_NOW=0; DRY_NOW=0; FORCE=0
for arg in "$@"; do
  case "$arg" in
    --migrate) DO_MIGRATE=1 ;;
    --run-now) RUN_NOW=1 ;;
    --dry-run-now) DRY_NOW=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $arg" >&2; usage; exit 2 ;;
    *) ROOT="$arg" ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
[ -f "$ROOT/backend/cell_sync_core.py" ] || { echo "ERROR: $ROOT is not the SiteLink root (backend/cell_sync_core.py not found)" >&2; exit 1; }
[ -f "$ROOT/backend/update_cells_with_revision.py" ] || { echo "ERROR: backend/update_cells_with_revision.py not found" >&2; exit 1; }
[ -f "$ROOT/frontend/src/hooks/useServerTable.tsx" ] || { echo "ERROR: frontend/src/hooks/useServerTable.tsx not found" >&2; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 is required" >&2; exit 1; }

export SL_ROOT="$ROOT" SL_FORCE="$FORCE" PYTHONIOENCODING=utf-8

python3 - <<'PYEOF'
import datetime
import os
import re
import sys
from pathlib import Path

ROOT = Path(os.environ["SL_ROOT"])
FORCE = os.environ.get("SL_FORCE") == "1"


class Patcher:
    def __init__(self, root):
        self.root = root
        self.texts, self.orig, self.crlf = {}, {}, {}
        self.new_files = {}
        self.errors, self.manual, self.notes = [], [], []

    def _load(self, rel):
        if rel not in self.texts:
            p = self.root / rel
            if not p.is_file():
                self.errors.append("missing file: " + rel)
                return None
            raw = p.read_bytes().decode("utf-8")
            self.crlf[rel] = "\r\n" in raw
            t = raw.replace("\r\n", "\n")
            self.orig[rel] = t
            self.texts[rel] = t
        return self.texts[rel]

    def replace(self, rel, old, new, count=1, skip_if=None):
        t = self._load(rel)
        if t is None:
            return
        if skip_if and skip_if in t:
            self.notes.append("%s: already patched (%s) - skipped" % (rel, skip_if))
            return
        n = t.count(old)
        if n != count:
            self.errors.append("%s: anchor found %dx (expected %d): %r" % (rel, n, count, old[:80]))
            return
        self.texts[rel] = t.replace(old, new)

    def set_text(self, rel, new):
        if self._load(rel) is not None:
            self.texts[rel] = new

    def create(self, rel, content):
        self.new_files[rel] = content

    def commit(self):
        for rel, t in list(self.texts.items()) + list(self.new_files.items()):
            if rel.endswith(".py"):
                try:
                    compile(t, rel, "exec")
                except SyntaxError as e:
                    self.errors.append("%s: patched file has a syntax error: %s" % (rel, e))
        if self.errors:
            print("\nPATCH ABORTED - nothing was written. Problems:")
            for e in self.errors:
                print("  - " + e)
            sys.exit(1)
        stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        bdir = self.root / (".reconcile_backup_" + stamp)

        def backup(rel):
            src = self.root / rel
            if src.exists():
                dst = bdir / rel
                dst.parent.mkdir(parents=True, exist_ok=True)
                dst.write_bytes(src.read_bytes())

        changed = []
        for rel, t in self.texts.items():
            if t == self.orig[rel]:
                continue
            backup(rel)
            out = t.replace("\n", "\r\n") if self.crlf[rel] else t
            (self.root / rel).write_bytes(out.encode("utf-8"))
            changed.append(rel)
        created = []
        for rel, t in self.new_files.items():
            backup(rel)
            p = self.root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(t.encode("utf-8"))
            created.append(rel)
        if changed or created:
            print("Backup of original files: " + str(bdir))
        print("\nModified files (%d):" % len(changed))
        for r in changed:
            print("  ~ " + r)
        print("\nCreated files (%d):" % len(created))
        for r in created:
            print("  + " + r)
        for n in self.notes:
            print("  note: " + n)
        if self.manual:
            print("\n" + "=" * 70)
            print("MANUAL STEPS NEEDED (could not patch automatically):")
            for m in self.manual:
                print("\n  * " + m.replace("\n", "\n    "))
            print("=" * 70)


if (ROOT / "backend/cell_reconcile_core.py").exists() and not FORCE:
    print("Reconcile feature seems to be applied already (backend/cell_reconcile_core.py exists). Use --force to re-apply.")
    sys.exit(0)

P = Patcher(ROOT)

# =============================================================================
# 1. BACKEND - batch core (shared by the CLI script) 
# =============================================================================
P.create("backend/cell_reconcile_core.py", r'''"""
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
''')

P.create("backend/reconcile_cells.py", r'''"""
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
''')

P.create("backend/migrations/add_cell_reconcile.sql", '''-- Plain-SQL alternative to: python reconcile_cells.py --init-db
CREATE TABLE IF NOT EXISTS cell_reconcile_runs (
    id SERIAL PRIMARY KEY, batch_id VARCHAR(40), tech VARCHAR(5) NOT NULL, run_date VARCHAR(10),
    started_at TIMESTAMPTZ, finished_at TIMESTAMPTZ, status VARCHAR(20) NOT NULL DEFAULT 'ok',
    error TEXT, prev_run_id INTEGER,
    dump_total INTEGER DEFAULT 0, dump_active INTEGER DEFAULT 0, dump_inactive INTEGER DEFAULT 0,
    web_total INTEGER DEFAULT 0, matched INTEGER DEFAULT 0,
    missing_in_web INTEGER DEFAULT 0, missing_in_dump INTEGER DEFAULT 0,
    missing_in_dump_uncovered INTEGER DEFAULT 0, dump_inactive_not_in_web INTEGER DEFAULT 0,
    new_missing_in_web INTEGER DEFAULT 0, new_missing_in_dump INTEGER DEFAULT 0,
    resolved_missing_in_web INTEGER DEFAULT 0, resolved_missing_in_dump INTEGER DEFAULT 0,
    vendor_status TEXT, status_stats TEXT
);
CREATE INDEX IF NOT EXISTS ix_cell_reconcile_runs_tech_id ON cell_reconcile_runs (tech, id);
CREATE TABLE IF NOT EXISTS cell_reconcile_items (
    id SERIAL PRIMARY KEY, run_id INTEGER NOT NULL, tech VARCHAR(5) NOT NULL, direction VARCHAR(20) NOT NULL,
    cell_name VARCHAR(200), subcell_id VARCHAR(50), web_id INTEGER, site_name VARCHAR(200), vendor VARCHAR(50),
    mien VARCHAR(10), tinh VARCHAR(100), phuong_xa VARCHAR(150), cell_status VARCHAR(100),
    bbu_name VARCHAR(200), rf VARCHAR(200), oss VARCHAR(50), dump_date VARCHAR(50), cell_id VARCHAR(50),
    node_id VARCHAR(50), freq VARCHAR(50), pci VARCHAR(50), tac VARCHAR(50), bandwidth VARCHAR(50),
    mimo VARCHAR(100), web_updated_at VARCHAR(30), first_seen VARCHAR(10), dump_covered VARCHAR(1)
);
CREATE INDEX IF NOT EXISTS ix_cell_reconcile_items_run_dir ON cell_reconcile_items (run_id, direction);
''')

# =============================================================================
# 2. BACKEND - app model + API
# =============================================================================
P.create("backend/app/models/cell_reconcile.py", r'''"""
Tables written by backend/reconcile_cells.py (daily batch) and read by /api/v1/reconcile.
Keep in sync with the DDL in backend/cell_reconcile_core.py.
"""
from sqlalchemy import Column, DateTime, Index, Integer, String, Text

from app.db.base import Base


class CellReconcileRun(Base):
    """One row per (batch execution, technology). status: ok | error."""
    __tablename__ = "cell_reconcile_runs"

    id          = Column(Integer, primary_key=True)
    batch_id    = Column(String(40))
    tech        = Column(String(5), nullable=False)
    run_date    = Column(String(10))
    started_at  = Column(DateTime(timezone=True))
    finished_at = Column(DateTime(timezone=True))
    status      = Column(String(20), nullable=False, default="ok")
    error       = Column(Text)
    prev_run_id = Column(Integer)

    dump_total                = Column(Integer, default=0)
    dump_active               = Column(Integer, default=0)
    dump_inactive             = Column(Integer, default=0)
    web_total                 = Column(Integer, default=0)
    matched                   = Column(Integer, default=0)
    missing_in_web            = Column(Integer, default=0)
    missing_in_dump           = Column(Integer, default=0)
    missing_in_dump_uncovered = Column(Integer, default=0)
    dump_inactive_not_in_web  = Column(Integer, default=0)
    new_missing_in_web        = Column(Integer, default=0)
    new_missing_in_dump       = Column(Integer, default=0)
    resolved_missing_in_web   = Column(Integer, default=0)
    resolved_missing_in_dump  = Column(Integer, default=0)

    vendor_status = Column(Text)    # JSON
    status_stats  = Column(Text)    # JSON

    __table_args__ = (Index("ix_cell_reconcile_runs_tech_id", "tech", "id"),)


class CellReconcileItem(Base):
    """One row per difference. direction: missing_in_web | missing_in_dump."""
    __tablename__ = "cell_reconcile_items"

    id             = Column(Integer, primary_key=True)
    run_id         = Column(Integer, nullable=False)
    tech           = Column(String(5), nullable=False)
    direction      = Column(String(20), nullable=False)
    cell_name      = Column(String(200))
    subcell_id     = Column(String(50))
    web_id         = Column(Integer)
    site_name      = Column(String(200))
    vendor         = Column(String(50))
    mien           = Column(String(10))
    tinh           = Column(String(100))
    phuong_xa      = Column(String(150))
    cell_status    = Column(String(100))
    bbu_name       = Column(String(200))
    rf             = Column(String(200))
    oss            = Column(String(50))
    dump_date      = Column(String(50))
    cell_id        = Column(String(50))
    node_id        = Column(String(50))
    freq           = Column(String(50))
    pci            = Column(String(50))
    tac            = Column(String(50))
    bandwidth      = Column(String(50))
    mimo           = Column(String(100))
    web_updated_at = Column(String(30))
    first_seen     = Column(String(10))
    dump_covered   = Column(String(1))

    __table_args__ = (Index("ix_cell_reconcile_items_run_dir", "run_id", "direction"),)
''')

P.create("backend/app/api/routes/reconcile.py", r'''"""
reconcile.py - read-only API of the dump <-> web cell reconciliation dashboard.

The data is produced once a day by backend/reconcile_cells.py. For every technology
the LATEST SUCCESSFUL run is served.

  GET  /summary                 KPI cards, vendor / province breakdown, history
  GET  /items                   paged detail rows (server-side filter / sort)
  GET  /items/ids               ids of every row matching the filters (select-all)
  GET  /items/distinct/{col}    distinct values + counts (Excel-style header filter)
  POST /export                  Excel of the filtered rows (or of the selected ids)
  GET  /export-all              one workbook: summary + 6 sheets
"""
from __future__ import annotations

import io
import json
import re
import threading
from datetime import date, datetime
from typing import Any, Dict, List, Optional

import openpyxl
from fastapi import APIRouter, Depends, HTTPException, Query, Response
from fastapi.responses import StreamingResponse
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter
from pydantic import BaseModel, Field
from sqlalchemy import false, func, or_
from sqlalchemy.orm import Session

from app.db.session import engine, get_db
from app.models.cell_reconcile import CellReconcileItem as Item, CellReconcileRun as Run
from app.services.list_query import (
    _check, _fold_py, _fold_sql, _norm, apply_column_filters, apply_sort,
)
from app.utils.deps import get_current_user

TECHS = ("3g", "4g", "5g")
DIRECTIONS = ("missing_in_web", "missing_in_dump")

_tables_ready = False
_tables_lock = threading.Lock()


def _ensure_tables() -> None:
    """The batch script creates the tables; this makes the API work even before its first run."""
    global _tables_ready
    if _tables_ready:
        return
    with _tables_lock:
        if _tables_ready:
            return
        from app.db.base import Base
        Base.metadata.create_all(bind=engine, tables=[Run.__table__, Item.__table__])
        _tables_ready = True


router = APIRouter(dependencies=[Depends(_ensure_tables)])

_EXPORT_SLOTS = threading.BoundedSemaphore(2)
_XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
_EXPOSE = "X-Row-Count, Content-Disposition"

RUN_INT_FIELDS = [
    "dump_total", "dump_active", "dump_inactive", "web_total", "matched", "missing_in_web",
    "missing_in_dump", "missing_in_dump_uncovered", "dump_inactive_not_in_web",
    "new_missing_in_web", "new_missing_in_dump", "resolved_missing_in_web", "resolved_missing_in_dump",
]
ITEM_FIELDS = [
    "id", "tech", "direction", "cell_name", "subcell_id", "web_id", "site_name", "vendor", "mien",
    "tinh", "phuong_xa", "cell_status", "bbu_name", "rf", "oss", "dump_date", "cell_id", "node_id",
    "freq", "pci", "tac", "bandwidth", "mimo", "web_updated_at", "first_seen", "dump_covered",
]
TECH_LABELS = {
    "3g": {"node": None,        "freq": "UARFCN",    "pci": "PSC", "tac": "LAC", "bw": False},
    "4g": {"node": "EnodeB ID", "freq": "EARFCN",    "pci": "PCI", "tac": "TAC", "bw": True},
    "5g": {"node": "gNodeB ID", "freq": "SSB-ARFCN", "pci": "PCI", "tac": "TAC", "bw": True},
}
DIR_TITLE = {
    "missing_in_web":  "Chưa có trên Web",
    "missing_in_dump": "Không có trong Dump",
}


# ── helpers ──────────────────────────────────────────────────────────────────
def _tech(t: str) -> str:
    t = (t or "").lower()
    if t not in TECHS:
        raise HTTPException(400, "tech must be 3g, 4g or 5g")
    return t


def _direction(d: str) -> str:
    if d not in DIRECTIONS:
        raise HTTPException(400, "direction must be missing_in_web or missing_in_dump")
    return d


def _iso(dt) -> Optional[str]:
    return dt.isoformat() if dt else None


def _loads(s: Optional[str]):
    if not s:
        return None
    try:
        return json.loads(s)
    except ValueError:
        return None


def _latest_ok_run(db: Session, tech: str) -> Optional[Run]:
    return (db.query(Run).filter(Run.tech == tech, Run.status == "ok")
              .order_by(Run.id.desc()).first())


def _run_dict(r: Run, heavy: bool = True) -> Dict[str, Any]:
    d: Dict[str, Any] = {
        "id": r.id, "tech": r.tech, "batch_id": r.batch_id, "run_date": r.run_date,
        "started_at": _iso(r.started_at), "finished_at": _iso(r.finished_at),
        "status": r.status, "error": r.error, "prev_run_id": r.prev_run_id,
    }
    for f in RUN_INT_FIELDS:
        d[f] = int(getattr(r, f) or 0)
    if heavy:
        d["vendor_status"] = _loads(r.vendor_status)
        d["status_stats"] = _loads(r.status_stats)
    return d


def _age(first_seen: Optional[str], run_date: Optional[str]) -> Optional[int]:
    try:
        return (date.fromisoformat(run_date) - date.fromisoformat(first_seen)).days
    except Exception:
        return None


def _row(o: Item, run_date: Optional[str]) -> Dict[str, Any]:
    d = {f: getattr(o, f) for f in ITEM_FIELDS}
    d["age_days"] = _age(o.first_seen, run_date)
    return d


def _scoped(db: Session, tech: str, direction: str, search=None, vendor=None, mien=None,
            tinh=None, covered_only: bool = False, new_only: bool = False):
    """Rows of the latest successful run of `tech` / `direction` + the top-bar filters."""
    tech, direction = _tech(tech), _direction(direction)
    run = _latest_ok_run(db, tech)
    q = db.query(Item)
    if run is None:
        return q.filter(false()), None
    q = q.filter(Item.run_id == run.id, Item.direction == direction)
    if search and search.strip():
        like = "%" + search.strip() + "%"
        q = q.filter(or_(Item.cell_name.ilike(like), Item.site_name.ilike(like)))
    if vendor:
        q = q.filter(Item.vendor.in_(vendor))
    if mien:
        q = q.filter(Item.mien.in_(mien))
    if tinh:
        q = q.filter(Item.tinh.in_(tinh))
    if covered_only and direction == "missing_in_dump":
        q = q.filter(or_(Item.dump_covered.is_(None), Item.dump_covered != "N"))
    if new_only:
        q = q.filter(Item.first_seen == run.run_date)
    return q, run


def _sorted(q, sort_by: Optional[str], sort_dir: str):
    if sort_by:
        return apply_sort(q, Item, sort_by, sort_dir)
    return q.order_by(Item.cell_name.asc(), Item.id.asc())


# ── summary ──────────────────────────────────────────────────────────────────
@router.get("/summary")
def summary(db: Session = Depends(get_db), _=Depends(get_current_user)):
    techs: Dict[str, Any] = {}
    history: Dict[str, Any] = {}
    for tech in TECHS:
        run = _latest_ok_run(db, tech)
        last = db.query(Run).filter(Run.tech == tech).order_by(Run.id.desc()).first()
        entry: Dict[str, Any] = {
            "run": _run_dict(run) if run else None,
            "last_run": _run_dict(last, heavy=False) if last else None,
            "vendors": [], "provinces": [],
        }
        if run:
            vend = (db.query(Item.direction, Item.vendor, Item.dump_covered, func.count())
                      .filter(Item.run_id == run.id)
                      .group_by(Item.direction, Item.vendor, Item.dump_covered).all())
            entry["vendors"] = [
                {"direction": d, "vendor": v or "(Không rõ)", "covered": c != "N", "count": int(n)}
                for d, v, c, n in vend
            ]
            prov = (db.query(Item.direction, Item.tinh, func.count())
                      .filter(Item.run_id == run.id,
                              or_(Item.dump_covered.is_(None), Item.dump_covered != "N"))
                      .group_by(Item.direction, Item.tinh).all())
            agg: Dict[tuple, int] = {}
            for d, t, n in prov:
                key = (d, t or "(Chưa xác định)")
                agg[key] = agg.get(key, 0) + int(n)
            entry["provinces"] = [{"direction": d, "tinh": t, "count": n} for (d, t), n in agg.items()]
        techs[tech] = entry
        hist = (db.query(Run).filter(Run.tech == tech, Run.status == "ok")
                  .order_by(Run.id.desc()).limit(30).all())
        history[tech] = [
            {"run_date": h.run_date, "missing_in_web": int(h.missing_in_web or 0),
             "missing_in_dump": int(h.missing_in_dump or 0), "dump_active": int(h.dump_active or 0),
             "web_total": int(h.web_total or 0)}
            for h in reversed(hist)
        ]
    return {"techs": techs, "history": history, "generated_at": datetime.utcnow().isoformat() + "Z"}


# ── detail rows ──────────────────────────────────────────────────────────────
@router.get("/items")
def list_items(
    response: Response,
    tech: str,
    direction: str,
    skip: int = 0,
    limit: int = Query(500, ge=1, le=20000),
    search: Optional[str] = Query(None),
    vendor: Optional[List[str]] = Query(None),
    mien: Optional[List[str]] = Query(None),
    tinh: Optional[List[str]] = Query(None),
    covered_only: bool = False,
    new_only: bool = False,
    sort_by: Optional[str] = Query(None),
    sort_dir: str = Query("asc"),
    filters: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    q, run = _scoped(db, tech, direction, search, vendor, mien, tinh, covered_only, new_only)
    q = apply_column_filters(q, Item, filters)
    response.headers["X-Total-Count"] = str(q.count())
    q = _sorted(q, sort_by, sort_dir)
    rd = run.run_date if run else None
    return [_row(r, rd) for r in q.offset(skip).limit(limit).all()]


@router.get("/items/ids")
def list_ids(
    tech: str,
    direction: str,
    search: Optional[str] = Query(None),
    vendor: Optional[List[str]] = Query(None),
    mien: Optional[List[str]] = Query(None),
    tinh: Optional[List[str]] = Query(None),
    covered_only: bool = False,
    new_only: bool = False,
    filters: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    q, _run = _scoped(db, tech, direction, search, vendor, mien, tinh, covered_only, new_only)
    q = apply_column_filters(q, Item, filters)
    ids = [r[0] for r in q.with_entities(Item.id).order_by(Item.id).all()]
    return {"ids": ids, "total": len(ids)}


@router.get("/items/distinct/{column}")
def distinct_values(
    column: str,
    tech: str,
    direction: str,
    search: Optional[str] = Query(None),
    vendor: Optional[List[str]] = Query(None),
    mien: Optional[List[str]] = Query(None),
    tinh: Optional[List[str]] = Query(None),
    covered_only: bool = False,
    new_only: bool = False,
    filters: Optional[str] = Query(None),
    q: Optional[str] = Query(None),
    limit: int = Query(200, ge=1, le=1000),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    _check(Item, column)
    expr = _norm(Item, column)
    base, _run = _scoped(db, tech, direction, search, vendor, mien, tinh, covered_only, new_only)
    base = apply_column_filters(base, Item, filters, exclude=column)   # like Excel
    if q and q.strip():
        base = base.filter(_fold_sql(getattr(Item, column)).contains(_fold_py(q.strip()), autoescape=True))
    grouped = base.with_entities(expr.label("v"), func.count().label("n")).group_by(expr)
    rows = grouped.order_by(expr.asc().nulls_last()).limit(limit).all()
    total = db.query(func.count()).select_from(grouped.order_by(None).subquery()).scalar() or 0
    return {"values": [{"value": r.v, "count": r.n} for r in rows], "total_distinct": total}


# ── Excel export ─────────────────────────────────────────────────────────────
_ILLEGAL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]")


def _xl(v: Any) -> Any:
    return _ILLEGAL.sub("", v) if isinstance(v, str) else v


def _export_columns(tech: str, direction: str):
    L = TECH_LABELS[tech]
    cols = [("Cell Name", 30, "cell_name")]
    if direction == "missing_in_dump":
        cols += [("Subcell-ID", 14, "subcell_id"), ("Miền", 8, "mien"), ("Tỉnh", 22, "tinh"),
                 ("Phường/Xã", 24, "phuong_xa"), ("Site Name", 28, "site_name"),
                 ("Vendor", 12, "vendor"), ("Cell status (web)", 20, "cell_status")]
    else:
        cols += [("Vendor", 12, "vendor"), ("Trạng thái (dump)", 20, "cell_status"),
                 ("Miền (suy từ mã cell)", 12, "mien"), ("Tỉnh (suy từ mã cell)", 22, "tinh"),
                 ("Phường/Xã (suy từ mã cell)", 24, "phuong_xa")]
    cols += [("BBUname", 20, "bbu_name"), ("RF", 18, "rf"), ("OSS", 10, "oss"),
             ("Ngày dump", 14, "dump_date"), ("Cell ID", 14, "cell_id")]
    if L["node"]:
        cols.append((L["node"], 14, "node_id"))
    cols += [(L["freq"], 12, "freq"), (L["pci"], 10, "pci"), (L["tac"], 10, "tac")]
    if L["bw"]:
        cols.append(("Bandwidth", 12, "bandwidth"))
    cols.append(("MIMO", 10, "mimo"))
    if direction == "missing_in_dump":
        cols += [("Có nguồn dump", 18, "dump_covered_label"), ("Cập nhật web lần cuối", 20, "web_updated_at")]
    cols += [("Phát hiện lần đầu", 16, "first_seen"), ("Số ngày tồn tại", 14, "age_days")]
    return cols


def _val(o: Item, key: str, run_date: Optional[str]):
    if key == "dump_covered_label":
        return "Không (vendor chưa có nguồn dump)" if o.dump_covered == "N" else "Có"
    if key == "age_days":
        return _age(o.first_seen, run_date)
    return getattr(o, key, None)


def _fill_sheet(ws, cols, rows, run_date: Optional[str]) -> None:
    fill = PatternFill("solid", fgColor="1F4E79")
    font = Font(color="FFFFFF", bold=True, size=10)
    ws.row_dimensions[1].height = 30
    ws.freeze_panes = "B2"
    for i, (title, width, _k) in enumerate(cols, start=1):
        c = ws.cell(row=1, column=i, value=title)
        c.fill, c.font = fill, font
        c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        ws.column_dimensions[get_column_letter(i)].width = width
    for o in rows:
        ws.append([_xl(_val(o, k, run_date)) for _t, _w, k in cols])
    ws.auto_filter.ref = "A1:%s1" % get_column_letter(len(cols))


def _stream(wb, filename: str, count: int) -> StreamingResponse:
    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    return StreamingResponse(
        iter([buf.read()]), media_type=_XLSX,
        headers={"Content-Disposition": 'attachment; filename="%s"' % filename,
                 "X-Row-Count": str(count), "Access-Control-Expose-Headers": _EXPOSE})


def _pf(p: Dict[str, Any], k: str) -> Optional[str]:
    v = p.get(k)
    if isinstance(v, (list, tuple)):
        v = v[0] if v else None
    return str(v) if v not in (None, "") else None


def _pm(p: Dict[str, Any], k: str) -> List[str]:
    v = p.get(k)
    if v is None:
        return []
    if not isinstance(v, (list, tuple)):
        v = [v]
    return [str(x) for x in v if x not in (None, "")]


def _pb(p: Dict[str, Any], k: str) -> bool:
    v = p.get(k)
    if isinstance(v, (list, tuple)):
        v = v[0] if v else None
    return str(v).lower() in ("true", "1", "yes")


class ExportRequest(BaseModel):
    tech: str
    direction: str
    ids: Optional[List[int]] = None
    params: Dict[str, Any] = Field(default_factory=dict)
    filters: Optional[str] = None
    sort_by: Optional[str] = None
    sort_dir: str = "asc"


@router.post("/export")
def export_items(body: ExportRequest, db: Session = Depends(get_db), _=Depends(get_current_user)):
    tech, direction = _tech(body.tech), _direction(body.direction)
    with _EXPORT_SLOTS:
        p = body.params or {}
        if body.ids:
            run = _latest_ok_run(db, tech)
            q = db.query(Item).filter(Item.id.in_(list(body.ids)))
            q = q.filter(Item.run_id == run.id, Item.direction == direction) if run else q.filter(false())
        else:
            q, run = _scoped(db, tech, direction, _pf(p, "search"), _pm(p, "vendor"), _pm(p, "mien"),
                             _pm(p, "tinh"), _pb(p, "covered_only"), _pb(p, "new_only"))
            q = apply_column_filters(q, Item, body.filters)
        rows = _sorted(q, body.sort_by, body.sort_dir).all()
        rd = run.run_date if run else None
        wb = openpyxl.Workbook()
        ws = wb.active
        ws.title = ("%s - %s" % (tech.upper(), DIR_TITLE[direction]))[:31]
        _fill_sheet(ws, _export_columns(tech, direction), rows, rd)
        name = "Doi_soat_%s_%s_%s.xlsx" % (
            tech.upper(), "chua_co_tren_web" if direction == "missing_in_web" else "khong_co_trong_dump",
            rd or datetime.now().strftime("%Y-%m-%d"))
        return _stream(wb, name, len(rows))


@router.get("/export-all")
def export_all(db: Session = Depends(get_db), _=Depends(get_current_user)):
    with _EXPORT_SLOTS:
        wb = openpyxl.Workbook()
        ws = wb.active
        ws.title = "Tổng hợp"
        head = ["Công nghệ", "Ngày đối soát", "Cell trong dump", "Cell active trong dump", "Cell trên web",
                "Active trong dump - chưa có trên web", "(mới)", "(đã xử lý)",
                "Có trên web - không có trong dump", "(mới)", "(đã xử lý)",
                "Web: vendor chưa có nguồn dump"]
        ws.append(head)
        fill = PatternFill("solid", fgColor="1F4E79")
        for i in range(1, len(head) + 1):
            c = ws.cell(row=1, column=i)
            c.fill, c.font = fill, Font(color="FFFFFF", bold=True)
            c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
            ws.column_dimensions[get_column_letter(i)].width = 24
        ws.column_dimensions["A"].width = 12
        ws.row_dimensions[1].height = 42
        total = 0
        runs = {}
        for tech in TECHS:
            r = _latest_ok_run(db, tech)
            runs[tech] = r
            if r:
                ws.append([tech.upper(), r.run_date, r.dump_total, r.dump_active, r.web_total,
                           r.missing_in_web, r.new_missing_in_web, r.resolved_missing_in_web,
                           r.missing_in_dump, r.new_missing_in_dump, r.resolved_missing_in_dump,
                           r.missing_in_dump_uncovered])
        for tech in TECHS:
            run = runs[tech]
            if not run:
                continue
            for direction in DIRECTIONS:
                rows = (db.query(Item).filter(Item.run_id == run.id, Item.direction == direction)
                          .order_by(Item.tinh.asc().nulls_last(), Item.cell_name.asc()).all())
                total += len(rows)
                sheet = wb.create_sheet(("%s - %s" % (tech.upper(), DIR_TITLE[direction]))[:31])
                _fill_sheet(sheet, _export_columns(tech, direction), rows, run.run_date)
        return _stream(wb, "Doi_soat_cell_tong_hop_%s.xlsx" % datetime.now().strftime("%Y-%m-%d"), total)
''')

# --- register the router in the FastAPI app (soft patch: the file is not in the upload) ---
def find_call_end(t, start):
    i = t.index("(", start)
    depth = 0
    for j in range(i, len(t)):
        c = t[j]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return j + 1
    return -1


def py_files(base):
    for p in sorted(base.rglob("*.py")):
        rel = p.relative_to(ROOT)
        if any(part.startswith(".") or part in ("node_modules", "__pycache__") for part in rel.parts):
            continue
        yield p, str(rel).replace(os.sep, "/")


def patch_backend_router():
    manual = ('Register the API in your FastAPI app (where the other routers are included):\n'
              '    from app.api.routes.reconcile import router as reconcile_router\n'
              '    app.include_router(reconcile_router, prefix="/api/v1/reconcile", tags=["reconcile"])')
    cands = []
    for p, rel in py_files(ROOT / "backend"):
        t = p.read_text(encoding="utf-8")
        if "reconcile_router" in t:
            P.notes.append("%s: reconcile router already registered" % rel)
            return
        if re.search(r"\.include_router\(\s*[\w\.]*revision", t):
            cands.append((p, rel, t))
    if len(cands) != 1:
        P.manual.append(manual)
        return
    p, rel, t = cands[0]
    t = t.replace("\r\n", "\n")
    m = re.search(r"^([ \t]*)([\w\.]+)\.include_router\(\s*[\w\.]*revision", t, re.M)
    end = find_call_end(t, m.start())
    if end < 0:
        P.manual.append(manual)
        return
    call = t[m.start():end]
    pm = re.search(r"prefix\s*=\s*([\"'])(.*?)\1", call)
    prefix = "/api/v1/reconcile"
    if pm:
        cand = re.sub(r"revisions?/?$", "reconcile", pm.group(2))
        if cand != pm.group(2):
            prefix = cand
    nl = t.find("\n", end)
    nl = len(t) if nl < 0 else nl
    ind, obj = m.group(1), m.group(2)
    ins = ("\n%sfrom app.api.routes.reconcile import router as reconcile_router  # noqa: E402\n"
           "%s%s.include_router(reconcile_router, prefix=\"%s\", tags=[\"reconcile\"])"
           % (ind, ind, obj, prefix))
    P.set_text(rel, t[:nl] + ins + t[nl:])
    P.notes.append("%s: reconcile router registered with prefix %s (the page calls /api/v1/reconcile)" % (rel, prefix))


patch_backend_router()

# --- hook the batch into the existing daily script (--reconcile) -------------
UPD = "backend/update_cells_with_revision.py"
P.replace(UPD, "import cell_sync_core as core\n",
          'os.environ.setdefault("CELL_SYNC_CACHE_TTL", "7200")   # one download per vendor CSV for sync + --reconcile\n'
          "import cell_sync_core as core\n", skip_if="CELL_SYNC_CACHE_TTL")
P.replace(UPD, '    ap.add_argument("--tech", default="3g,4g,5g", help="comma list, e.g. 4g,5g")\n',
          '    ap.add_argument("--tech", default="3g,4g,5g", help="comma list, e.g. 4g,5g")\n'
          '    ap.add_argument("--reconcile", action="store_true",\n'
          '                    help="after the sync, reconcile ALL dump cells against the web DB (page: Đối soát Cell)")\n',
          skip_if='"--reconcile"')
P.replace(UPD, "    finally:\n        eng.dispose()\n",
'''        if args.reconcile:
            print("\\n=== Reconcile dump <-> web ===")
            try:
                import cell_reconcile_core as recon
                rtechs = [t.strip().lower() for t in args.tech.split(",") if t.strip().lower() in TECHS]
                rc |= recon.run_reconcile(eng, rtechs, dry_run=args.dry_run)
            except Exception as exc:
                print(f"   ❌ reconcile failed: {exc}")
                rc |= 1
    finally:
        eng.dispose()
''', skip_if="cell_reconcile_core")

# =============================================================================
# 3. FRONTEND
# =============================================================================
P.create("frontend/src/api/reconcile.ts", r'''/**
 * reconcile.ts - API client of the dump <-> web cell reconciliation dashboard.
 */
import api from './client'
import { pagedGet, idsGet, distinctGet } from './listing'
import type { ExportScope } from './export'

export type ReconTech = '3g' | '4g' | '5g'
export type ReconDirection = 'missing_in_web' | 'missing_in_dump'

export interface ReconRun {
  id: number
  tech: ReconTech
  batch_id?: string | null
  run_date?: string | null
  started_at?: string | null
  finished_at?: string | null
  status: string
  error?: string | null
  prev_run_id?: number | null
  dump_total: number
  dump_active: number
  dump_inactive: number
  web_total: number
  matched: number
  missing_in_web: number
  missing_in_dump: number
  missing_in_dump_uncovered: number
  dump_inactive_not_in_web: number
  new_missing_in_web: number
  new_missing_in_dump: number
  resolved_missing_in_web: number
  resolved_missing_in_dump: number
  vendor_status?: {
    files?: Record<string, { ok: boolean; rows: number }>
    notes?: string[]
    duplicate_names?: number
  } | null
  status_stats?: { status: string; active: boolean; count: number }[] | null
}

export interface ReconTechSummary {
  run: ReconRun | null
  last_run: ReconRun | null
  vendors: { direction: ReconDirection; vendor: string; covered: boolean; count: number }[]
  provinces: { direction: ReconDirection; tinh: string; count: number }[]
}

export interface ReconHistoryPoint {
  run_date: string
  missing_in_web: number
  missing_in_dump: number
  dump_active: number
  web_total: number
}

export interface ReconSummary {
  techs: Record<ReconTech, ReconTechSummary>
  history: Record<ReconTech, ReconHistoryPoint[]>
  generated_at: string
}

export interface ReconItem {
  id: number
  tech: ReconTech
  direction: ReconDirection
  cell_name: string
  subcell_id?: string | null
  web_id?: number | null
  site_name?: string | null
  vendor?: string | null
  mien?: string | null
  tinh?: string | null
  phuong_xa?: string | null
  cell_status?: string | null
  bbu_name?: string | null
  rf?: string | null
  oss?: string | null
  dump_date?: string | null
  cell_id?: string | null
  node_id?: string | null
  freq?: string | null
  pci?: string | null
  tac?: string | null
  bandwidth?: string | null
  mimo?: string | null
  web_updated_at?: string | null
  first_seen?: string | null
  dump_covered?: string | null
  age_days?: number | null
}

const BASE = '/api/v1/reconcile'

export const reconcileApi = {
  summary: () => api.get<ReconSummary>(`${BASE}/summary`).then((r) => r.data),
  list: (params?: Record<string, unknown>) => pagedGet<ReconItem>(`${BASE}/items`, params),
  ids: (params?: Record<string, unknown>) => idsGet(`${BASE}/items`, params),
  distinct: (column: string, params?: Record<string, unknown>) =>
    distinctGet(`${BASE}/items`, column, params),
}

// ── downloads ────────────────────────────────────────────────────────────────
const token = () => localStorage.getItem('sl_token') || ''

async function saveResponse(res: Response, fallback: string): Promise<{ filename: string; rows?: number }> {
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`Export failed (${res.status}): ${text}`)
  }
  const cd = res.headers.get('Content-Disposition') || ''
  const m = /filename="?([^";]+)"?/i.exec(cd)
  const filename = m ? m[1] : fallback
  const blob = await res.blob()
  const link = document.createElement('a')
  link.href = URL.createObjectURL(blob)
  link.download = filename
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(link.href)
  const raw = res.headers.get('X-Row-Count')
  const n = raw === null || raw === '' ? NaN : Number(raw)
  return { filename, rows: Number.isFinite(n) ? n : undefined }
}

function cleanParams(params: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {}
  Object.entries(params).forEach(([k, v]) => {
    if (v === undefined || v === null || v === '' || v === false) return
    if (Array.isArray(v) && v.length === 0) return
    out[k] = v
  })
  return out
}

/** Selected ids win; otherwise top-bar params + column filters (+ sort). */
export async function exportReconcile(
  tech: ReconTech,
  direction: ReconDirection,
  params: Record<string, unknown>,
  scope?: ExportScope,
) {
  const hasIds = Boolean(scope?.ids && scope.ids.length > 0)
  const body = {
    tech,
    direction,
    params: hasIds ? {} : cleanParams(params),
    ids: hasIds ? scope!.ids : undefined,
    filters: hasIds ? undefined : scope?.filters,
    sort_by: scope?.sort_by,
    sort_dir: scope?.sort_dir ?? 'asc',
  }
  const res = await fetch(`${BASE}/export`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  return saveResponse(res, `Doi_soat_${tech}_${direction}.xlsx`)
}

export async function exportReconcileAll() {
  const res = await fetch(`${BASE}/export-all`, { headers: { Authorization: `Bearer ${token()}` } })
  return saveResponse(res, 'Doi_soat_cell_tong_hop.xlsx')
}
''')

P.create("frontend/src/pages/reconcile/ReconcilePage.tsx", r'''/**
 * ReconcilePage.tsx - "Đối soát Cell": dump (vendor CSV) <-> web (DB)
 *
 *  Direction 1  missing_in_web   active (unlock / unblock) in dump but not entered on the web
 *  Direction 2  missing_in_dump  on the web but absent from every dump file
 *  for every technology (3G / 4G / 5G). Data is produced once a day by reconcile_cells.py.
 */
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  Alert, Badge, Button, Card, Col, Collapse, Empty, Input, Progress, Row, Segmented,
  Select, Skeleton, Space, Switch, Table, Tabs, Tag, Tooltip, Typography, message,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import type { TableRowSelection } from 'antd/es/table/interface'
import {
  ArrowDownOutlined, ArrowUpOutlined, AuditOutlined, DownloadOutlined,
  ExclamationCircleOutlined, FileExcelOutlined, ReloadOutlined, SearchOutlined,
} from '@ant-design/icons'
import { useServerQuery, useServerColumns } from '@/hooks/useServerTable'
import { useDebouncedValue } from '@/hooks/useDebouncedValue'
import { buildExportScope } from '@/api/export'
import { reconcileApi, exportReconcile, exportReconcileAll } from '@/api/reconcile'
import type {
  ReconDirection, ReconItem, ReconRun, ReconSummary, ReconTech, ReconTechSummary,
} from '@/api/reconcile'

const TECHS: ReconTech[] = ['3g', '4g', '5g']
const TECH_COLOR: Record<ReconTech, string> = { '3g': '#1677ff', '4g': '#52c41a', '5g': '#722ed1' }

const DIR: Record<ReconDirection, { label: string; short: string; color: string; bg: string; desc: string }> = {
  missing_in_web: {
    label: 'Active trong dump – chưa có trên web',
    short: 'Chưa nhập lên web',
    color: '#cf1322',
    bg: '#fff1f0',
    desc: 'Cell có trạng thái unlock / unblock / active trong dữ liệu dump nhưng chưa được nhập lên web. '
        + 'Miền / Tỉnh / Phường được suy ra từ 6 ký tự đầu của tên cell.',
  },
  missing_in_dump: {
    label: 'Có trên web – không có trong dump',
    short: 'Không có trong dump',
    color: '#d46b08',
    bg: '#fff7e6',
    desc: 'Cell đang có trên web nhưng không xuất hiện trong bất kỳ file dump nào. '
        + '"Ngày dump" là lần gần nhất cell còn xuất hiện trong dump. '
        + 'Vendor chưa có nguồn dump (ZTE, Samsung…) có thể được ẩn bằng công tắc bên dưới.',
  },
}

const TECH_LABELS: Record<ReconTech, { node: string | null; freq: string; pci: string; tac: string; bw: boolean }> = {
  '3g': { node: null, freq: 'UARFCN', pci: 'PSC', tac: 'LAC', bw: false },
  '4g': { node: 'EnodeB ID', freq: 'EARFCN', pci: 'PCI', tac: 'TAC', bw: true },
  '5g': { node: 'gNodeB ID', freq: 'SSB-ARFCN', pci: 'PCI', tac: 'TAC', bw: true },
}

const ACTIVE = new Set(['unblocked', 'unblock', 'unlocked', 'unlock', 'cellunblock', 'cellunblocked',
  'cellunlock', 'active', 'enabled', 'enable', 'inservice'])
const isActive = (s?: string | null) => ACTIVE.has((s || '').toLowerCase().replace(/[^a-z0-9]/g, ''))

const fmt = (n?: number | null) => (n ?? 0).toLocaleString('vi-VN')
const fdt = (s?: string | null) => (s ? new Date(s).toLocaleString('vi-VN') : '-')
const STALE_MS = 36 * 3600 * 1000

// ═════════════════════════════════════════════════════════════════════════════
// small visual components (no chart library needed)
// ═════════════════════════════════════════════════════════════════════════════
function StatBlock(props: {
  label: string; value: number; color: string; bg: string
  newCount: number; resolved: number; hasPrev: boolean; note?: string; onClick: () => void
}) {
  const { label, value, color, bg, newCount, resolved, hasPrev, note, onClick } = props
  return (
    <div onClick={onClick}
         style={{ cursor: 'pointer', background: bg, borderLeft: `4px solid ${color}`,
                  borderRadius: 6, padding: '10px 14px', marginBottom: 10 }}>
      <div style={{ fontSize: 12, color: '#595959' }}>{label}</div>
      <div style={{ fontSize: 30, fontWeight: 700, color, lineHeight: 1.2 }}>{fmt(value)}</div>
      <div style={{ fontSize: 12, color: '#8c8c8c' }}>
        {hasPrev ? (
          <>
            <span style={{ color: newCount > 0 ? '#cf1322' : '#8c8c8c' }}><ArrowUpOutlined /> {fmt(newCount)} mới</span>
            {' · '}
            <span style={{ color: resolved > 0 ? '#389e0d' : '#8c8c8c' }}><ArrowDownOutlined /> {fmt(resolved)} đã xử lý</span>
          </>
        ) : 'Chưa có lần chạy trước để so sánh'}
        {note ? <div>{note}</div> : null}
      </div>
    </div>
  )
}

function TechCard({ tech, s, onGo }: {
  tech: ReconTech; s?: ReconTechSummary; onGo: (t: ReconTech, d: ReconDirection) => void
}) {
  const run = s?.run
  const lastErr = s?.last_run && s.last_run.status !== 'ok' ? s.last_run : null
  const title = (
    <Space>
      <Tag color={TECH_COLOR[tech]} style={{ fontSize: 14, padding: '0 10px' }}>{tech.toUpperCase()}</Tag>
      <span style={{ fontSize: 12, color: '#8c8c8c' }}>{run ? `Dữ liệu ngày ${run.run_date}` : ''}</span>
    </Space>
  )
  if (!run) {
    return (
      <Card title={title} size="small" style={{ height: '100%' }}>
        {lastErr
          ? <Alert type="error" showIcon message="Lần đối soát gần nhất bị lỗi" description={lastErr.error} />
          : <Empty image={Empty.PRESENTED_IMAGE_SIMPLE}
                   description="Chưa có dữ liệu đối soát – chạy backend/reconcile_cells.py" />}
      </Card>
    )
  }
  const hasPrev = !!run.prev_run_id
  const coverage = run.dump_active > 0
    ? Math.round(((run.dump_active - run.missing_in_web) / run.dump_active) * 1000) / 10 : 100
  return (
    <Card title={title} size="small" style={{ height: '100%' }}>
      {lastErr && (
        <Alert type="error" showIcon style={{ marginBottom: 8 }}
               message={`Lần chạy gần nhất (${fdt(lastErr.started_at)}) bị lỗi – đang hiển thị dữ liệu cũ`}
               description={lastErr.error} />
      )}
      <StatBlock label={DIR.missing_in_web.label} value={run.missing_in_web}
                 color={DIR.missing_in_web.color} bg={DIR.missing_in_web.bg}
                 newCount={run.new_missing_in_web} resolved={run.resolved_missing_in_web} hasPrev={hasPrev}
                 note={run.dump_inactive_not_in_web > 0
                   ? `Bỏ qua ${fmt(run.dump_inactive_not_in_web)} cell không active trong dump` : undefined}
                 onClick={() => onGo(tech, 'missing_in_web')} />
      <StatBlock label={DIR.missing_in_dump.label} value={run.missing_in_dump}
                 color={DIR.missing_in_dump.color} bg={DIR.missing_in_dump.bg}
                 newCount={run.new_missing_in_dump} resolved={run.resolved_missing_in_dump} hasPrev={hasPrev}
                 note={run.missing_in_dump_uncovered > 0
                   ? `+ ${fmt(run.missing_in_dump_uncovered)} cell vendor chưa có nguồn dump (không tính)` : undefined}
                 onClick={() => onGo(tech, 'missing_in_dump')} />
      <Tooltip title="Tỉ lệ cell active trong dump đã có trên web">
        <div style={{ fontSize: 12, color: '#595959' }}>Độ phủ dữ liệu web so với dump (active)</div>
        <Progress percent={coverage} size="small"
                  strokeColor={coverage >= 99 ? '#52c41a' : coverage >= 95 ? '#faad14' : '#ff4d4f'} />
      </Tooltip>
      <Row gutter={8} style={{ fontSize: 12, color: '#595959', textAlign: 'center' }}>
        <Col span={6}><div style={{ fontWeight: 600 }}>{fmt(run.dump_total)}</div>Dump</Col>
        <Col span={6}><div style={{ fontWeight: 600 }}>{fmt(run.dump_active)}</div>Dump active</Col>
        <Col span={6}><div style={{ fontWeight: 600 }}>{fmt(run.web_total)}</div>Web</Col>
        <Col span={6}><div style={{ fontWeight: 600 }}>{fmt(run.matched)}</div>Khớp tên</Col>
      </Row>
    </Card>
  )
}

function LineChart({ labels, series }: {
  labels: string[]; series: { name: string; color: string; values: (number | null)[] }[]
}) {
  const W = 560, H = 200, pl = 46, pr = 14, pt = 14, pb = 28
  const n = labels.length
  if (n === 0) return <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="Chưa có lịch sử" />
  const maxV = Math.max(1, ...series.flatMap((s) => s.values.filter((v): v is number => v !== null)))
  const p10 = Math.pow(10, Math.floor(Math.log10(maxV)))
  const top = Math.max(2, Math.ceil(maxV / p10) * p10)
  const x = (i: number) => (n === 1 ? pl + (W - pl - pr) / 2 : pl + (i * (W - pl - pr)) / (n - 1))
  const y = (v: number) => pt + (H - pt - pb) * (1 - v / top)
  const ticks = [0, top / 2, top]
  const xl = [0, Math.floor((n - 1) / 2), n - 1].filter((v, i, a) => a.indexOf(v) === i)
  return (
    <div>
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: 'auto' }}>
        {ticks.map((t) => (
          <g key={t}>
            <line x1={pl} x2={W - pr} y1={y(t)} y2={y(t)} stroke="#f0f0f0" />
            <text x={pl - 6} y={y(t) + 4} fontSize="10" textAnchor="end" fill="#8c8c8c">{fmt(Math.round(t))}</text>
          </g>
        ))}
        {series.map((s) => {
          const pts = s.values
            .map((v, i) => (v === null ? null : ([x(i), y(v)] as [number, number])))
            .filter((p): p is [number, number] => p !== null)
          return (
            <g key={s.name}>
              <polyline fill="none" stroke={s.color} strokeWidth={2} points={pts.map((p) => p.join(',')).join(' ')} />
              {pts.map((p, i) => <circle key={i} cx={p[0]} cy={p[1]} r={2.5} fill={s.color} />)}
            </g>
          )
        })}
        {xl.map((i) => (
          <text key={i} x={x(i)} y={H - 8} fontSize="10" textAnchor="middle" fill="#8c8c8c">{labels[i]}</text>
        ))}
      </svg>
      <Space size={14} style={{ fontSize: 12 }}>
        {series.map((s) => (
          <span key={s.name}>
            <span style={{ display: 'inline-block', width: 10, height: 10, background: s.color, borderRadius: 2, marginRight: 4 }} />
            {s.name}
          </span>
        ))}
      </Space>
    </div>
  )
}

function ProvinceBars({ rows }: { rows: { tinh: string; v: Record<ReconTech, number>; total: number }[] }) {
  if (rows.length === 0) return <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="Không có chênh lệch" />
  const max = Math.max(1, ...rows.map((r) => r.total))
  return (
    <div>
      {rows.map((r) => (
        <Tooltip key={r.tinh}
                 title={`${r.tinh}: 3G ${fmt(r.v['3g'])} · 4G ${fmt(r.v['4g'])} · 5G ${fmt(r.v['5g'])}`}>
          <div style={{ display: 'flex', alignItems: 'center', marginBottom: 6, fontSize: 12 }}>
            <div style={{ width: 150, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{r.tinh}</div>
            <div style={{ flex: 1, display: 'flex', height: 14, background: '#fafafa', borderRadius: 3, overflow: 'hidden' }}>
              {TECHS.map((t) => (
                <div key={t} style={{ width: `${(r.v[t] / max) * 100}%`, background: TECH_COLOR[t] }} />
              ))}
            </div>
            <div style={{ width: 60, textAlign: 'right', fontWeight: 600 }}>{fmt(r.total)}</div>
          </div>
        </Tooltip>
      ))}
      <Space size={14} style={{ fontSize: 12, marginTop: 4 }}>
        {TECHS.map((t) => (
          <span key={t}>
            <span style={{ display: 'inline-block', width: 10, height: 10, background: TECH_COLOR[t], borderRadius: 2, marginRight: 4 }} />
            {t.toUpperCase()}
          </span>
        ))}
      </Space>
    </div>
  )
}

// ═════════════════════════════════════════════════════════════════════════════
// detail table (one tech x one direction)
// ═════════════════════════════════════════════════════════════════════════════
function buildColumns(tech: ReconTech, direction: ReconDirection): ColumnsType<ReconItem> {
  const L = TECH_LABELS[tech]
  const dumpSide = direction === 'missing_in_web'
  const cols: ColumnsType<ReconItem> = [
    { title: 'Cell Name', dataIndex: 'cell_name', fixed: 'left', width: 240, ellipsis: { showTitle: true },
      render: (v: string) => <strong>{v}</strong> },
  ]
  if (!dumpSide) cols.push({ title: 'Subcell-ID', dataIndex: 'subcell_id', width: 110 })
  cols.push(
    { title: dumpSide ? 'Miền (suy từ mã cell)' : 'Miền', dataIndex: 'mien', width: dumpSide ? 120 : 70 },
    { title: dumpSide ? 'Tỉnh (suy từ mã cell)' : 'Tỉnh', dataIndex: 'tinh', width: 170 },
    { title: dumpSide ? 'Phường/Xã (suy từ mã cell)' : 'Phường/Xã', dataIndex: 'phuong_xa', width: 170, ellipsis: { showTitle: true } },
  )
  if (!dumpSide) cols.push({ title: 'Site Name', dataIndex: 'site_name', width: 220, ellipsis: { showTitle: true } })
  cols.push(
    { title: 'Vendor', dataIndex: 'vendor', width: 100,
      render: (v: string, r: ReconItem) => (
        <Space size={4}>{v || '-'}{r.dump_covered === 'N' && <Tooltip title="Vendor chưa có nguồn dump"><ExclamationCircleOutlined style={{ color: '#faad14' }} /></Tooltip>}</Space>
      ) },
    { title: dumpSide ? 'Trạng thái (dump)' : 'Cell status (web)', dataIndex: 'cell_status', width: 150,
      render: (v?: string) => (v ? <Tag color={isActive(v) ? 'green' : 'red'}>{v}</Tag> : '-') },
    { title: 'Phát hiện lần đầu', dataIndex: 'first_seen', width: 160,
      render: (v: string | undefined, r: ReconItem) => {
        const d = r.age_days
        const tag = d === 0 || d === null || d === undefined
          ? <Tag color="blue">Mới</Tag>
          : <Tag color={d >= 7 ? 'red' : d >= 3 ? 'orange' : 'default'}>{d} ngày</Tag>
        return <Space size={4}>{v || '-'}{tag}</Space>
      } },
    { title: 'BBUname', dataIndex: 'bbu_name', width: 150, ellipsis: { showTitle: true } },
    { title: 'RF', dataIndex: 'rf', width: 120, ellipsis: { showTitle: true } },
    { title: 'OSS', dataIndex: 'oss', width: 80 },
    { title: dumpSide ? 'Ngày dump' : 'Ngày dump gần nhất', dataIndex: 'dump_date', width: 140 },
    { title: 'Cell ID', dataIndex: 'cell_id', width: 100 },
  )
  if (L.node) cols.push({ title: L.node, dataIndex: 'node_id', width: 110 })
  cols.push(
    { title: L.freq, dataIndex: 'freq', width: 100 },
    { title: L.pci, dataIndex: 'pci', width: 80 },
    { title: L.tac, dataIndex: 'tac', width: 80 },
  )
  if (L.bw) cols.push({ title: 'Bandwidth', dataIndex: 'bandwidth', width: 100 })
  cols.push({ title: 'MIMO', dataIndex: 'mimo', width: 80, render: (v?: string) => (v ? <Tag color="blue">{v}</Tag> : '-') })
  if (!dumpSide) cols.push({ title: 'Cập nhật web lần cuối', dataIndex: 'web_updated_at', width: 160 })
  return cols
}

function ReconcileTable({ tech, direction, tinhOptions, vendorOptions }: {
  tech: ReconTech; direction: ReconDirection; tinhOptions: string[]; vendorOptions: string[]
}) {
  const [data, setData] = useState<ReconItem[]>([])
  const [loading, setLoading] = useState(false)
  const [exporting, setExporting] = useState(false)
  const [search, setSearch] = useState('')
  const [vendor, setVendor] = useState<string[]>([])
  const [tinh, setTinh] = useState<string[]>([])
  const [coveredOnly, setCoveredOnly] = useState(true)
  const [newOnly, setNewOnly] = useState(false)
  const [selectedIds, setSelectedIds] = useState<number[]>([])

  const dSearch = useDebouncedValue(search, 400)
  const sq = useServerQuery([tech, direction, dSearch, vendor, tinh, coveredOnly, newOnly])

  const topParams = useCallback((): Record<string, unknown> => {
    const p: Record<string, unknown> = {}
    if (dSearch) p.search = dSearch
    if (vendor.length) p.vendor = vendor
    if (tinh.length) p.tinh = tinh
    if (coveredOnly && direction === 'missing_in_dump') p.covered_only = true
    if (newOnly) p.new_only = true
    return p
  }, [dSearch, vendor, tinh, coveredOnly, newOnly, direction])

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const params: Record<string, unknown> = { ...sq.params, tech, direction, ...topParams() }
      const ticket = sq.nextTicket()
      const res = await reconcileApi.list(params)
      if (!sq.isCurrent(ticket)) return
      setData(res.items)
      sq.onLoaded(res.total, params)
    } catch (e: any) {
      message.error(e?.response?.data?.detail || e?.message || 'Không tải được dữ liệu')
    } finally { setLoading(false) }
  }, [tech, direction, topParams, sq.params])

  useEffect(() => { load() }, [load])

  const columns = useMemo(() => buildColumns(tech, direction), [tech, direction])
  const { columns: tableColumns, dataSource, onChange, filterBar, clearAll: clearColumnFilters } =
    useServerColumns(columns, data, sq, {
      fetchDistinct: (field, p) => reconcileApi.distinct(field, p),
      fetchIds: (p) => reconcileApi.ids(p),
      selectedIds, setSelectedIds, unit: 'cell',
    })
  const scrollX = tableColumns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  const rowSelection: TableRowSelection<ReconItem> = {
    selectedRowKeys: selectedIds,
    preserveSelectedRowKeys: true,
    onChange: (keys) => setSelectedIds(keys as number[]),
    selections: [Table.SELECTION_ALL, Table.SELECTION_INVERT, Table.SELECTION_NONE],
  }

  const clearFilters = () => {
    clearColumnFilters()
    setSearch(''); setVendor([]); setTinh([]); setNewOnly(false); setCoveredOnly(true)
  }

  const handleExport = async () => {
    setExporting(true)
    try {
      const res = await exportReconcile(tech, direction, topParams(), buildExportScope(sq, selectedIds))
      message.success(`Xuất Excel thành công${res.rows != null ? ` (${res.rows.toLocaleString('vi-VN')} dòng)` : ''}`)
    } catch (e: any) { message.error(e?.message || 'Xuất thất bại')
    } finally { setExporting(false) }
  }

  return (
    <div>
      <Row gutter={[8, 8]} style={{ marginBottom: 12 }} align="middle">
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} allowClear placeholder="Tìm cell / site name..."
                 value={search} onChange={(e) => setSearch(e.target.value)} />
        </Col>
        <Col flex="200px">
          <Select mode="multiple" allowClear maxTagCount={2} placeholder="Vendor" style={{ width: '100%' }}
                  value={vendor} onChange={setVendor} options={vendorOptions.map((v) => ({ value: v, label: v }))} />
        </Col>
        <Col flex="260px">
          <Select mode="multiple" allowClear showSearch maxTagCount={2} placeholder="Tỉnh" style={{ width: '100%' }}
                  value={tinh} onChange={setTinh} options={tinhOptions.map((v) => ({ value: v, label: v }))}
                  filterOption={(i, o) => String(o?.label ?? '').toLowerCase().includes(i.toLowerCase())} />
        </Col>
        <Col>
          <Space size={6}><Switch size="small" checked={newOnly} onChange={setNewOnly} />Chỉ cell mới phát sinh</Space>
        </Col>
        {direction === 'missing_in_dump' && (
          <Col>
            <Tooltip title="Ẩn cell của vendor không có nguồn dump (ZTE, Samsung…) vì luôn xuất hiện ở hướng này">
              <Space size={6}><Switch size="small" checked={coveredOnly} onChange={setCoveredOnly} />Ẩn vendor chưa có nguồn dump</Space>
            </Tooltip>
          </Col>
        )}
        <Col><Button onClick={clearFilters}>Xóa lọc</Button></Col>
        <Col flex="auto" style={{ textAlign: 'right' }}>
          <Tooltip title={selectedIds.length > 0
            ? `Xuất ${selectedIds.length} dòng đã chọn ra Excel`
            : 'Xuất các dòng đang lọc (gồm cả bộ lọc cột) ra Excel'}>
            <Button icon={<DownloadOutlined />} loading={exporting} onClick={handleExport}
                    style={{ borderColor: '#52c41a', color: '#52c41a' }}>
              Xuất Excel{selectedIds.length > 0 ? ` (${selectedIds.length} đã chọn)` : ''}
            </Button>
          </Tooltip>
        </Col>
      </Row>
      {filterBar}
      <Table<ReconItem> rowSelection={rowSelection} columns={tableColumns} dataSource={dataSource}
             onChange={onChange} rowKey="id" loading={loading} size="small" bordered
             scroll={{ x: scrollX, y: 560 }} pagination={sq.pagination('cell')} />
    </div>
  )
}

// ═════════════════════════════════════════════════════════════════════════════
// page
// ═════════════════════════════════════════════════════════════════════════════
export default function ReconcilePage() {
  const [summary, setSummary] = useState<ReconSummary | null>(null)
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [exportingAll, setExportingAll] = useState(false)
  const [direction, setDirection] = useState<ReconDirection>('missing_in_web')
  const [tech, setTech] = useState<ReconTech>('4g')
  const [chartDir, setChartDir] = useState<ReconDirection>('missing_in_web')
  const tableRef = useRef<HTMLDivElement>(null)

  const loadSummary = useCallback(async () => {
    setLoading(true)
    setLoadError(null)
    try { setSummary(await reconcileApi.summary()) }
    catch (e: any) { setLoadError(e?.response?.data?.detail || e?.message || 'Không tải được dữ liệu đối soát') }
    finally { setLoading(false) }
  }, [])
  useEffect(() => { loadSummary() }, [loadSummary])

  const goTo = (t: ReconTech, d: ReconDirection) => {
    setTech(t); setDirection(d)
    setTimeout(() => tableRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' }), 50)
  }

  const handleExportAll = async () => {
    setExportingAll(true)
    try {
      const res = await exportReconcileAll()
      message.success(`Xuất báo cáo tổng hợp thành công${res.rows != null ? ` (${res.rows.toLocaleString('vi-VN')} dòng)` : ''}`)
    } catch (e: any) { message.error(e?.message || 'Xuất thất bại')
    } finally { setExportingAll(false) }
  }

  const runs = TECHS.map((t) => summary?.techs?.[t]?.run).filter((r): r is ReconRun => !!r)
  const totalWeb = runs.reduce((s, r) => s + r.missing_in_web, 0)
  const totalDump = runs.reduce((s, r) => s + r.missing_in_dump, 0)
  const newWeb = runs.reduce((s, r) => s + r.new_missing_in_web, 0)
  const newDump = runs.reduce((s, r) => s + r.new_missing_in_dump, 0)
  const lastFinished = runs.map((r) => r.finished_at).filter(Boolean).sort().slice(-1)[0] as string | undefined
  const oldestFinished = runs.map((r) => r.finished_at).filter(Boolean).sort()[0] as string | undefined
  const stale = oldestFinished ? Date.now() - new Date(oldestFinished).getTime() > STALE_MS : false
  const errors = TECHS.map((t) => summary?.techs?.[t]?.last_run)
    .filter((r): r is ReconRun => !!r && r.status !== 'ok')

  const trend = useMemo(() => {
    const dates = new Set<string>()
    TECHS.forEach((t) => (summary?.history?.[t] ?? []).forEach((p) => dates.add(p.run_date)))
    const labels = [...dates].sort()
    const series = TECHS.map((t) => {
      const m = new Map<string, number>()
      ;(summary?.history?.[t] ?? []).forEach((p) =>
        m.set(p.run_date, chartDir === 'missing_in_web' ? p.missing_in_web : p.missing_in_dump))
      return { name: t.toUpperCase(), color: TECH_COLOR[t],
               values: labels.map((d) => (m.has(d) ? (m.get(d) as number) : null)) }
    })
    return { labels: labels.map((d) => d.slice(5)), series }
  }, [summary, chartDir])

  const provRows = useMemo(() => {
    const m = new Map<string, Record<ReconTech, number>>()
    TECHS.forEach((t) => (summary?.techs?.[t]?.provinces ?? [])
      .filter((p) => p.direction === chartDir)
      .forEach((p) => {
        const e = m.get(p.tinh) ?? { '3g': 0, '4g': 0, '5g': 0 }
        e[t] += p.count
        m.set(p.tinh, e)
      }))
    return [...m.entries()]
      .map(([tinh, v]) => ({ tinh, v, total: v['3g'] + v['4g'] + v['5g'] }))
      .sort((a, b) => b.total - a.total).slice(0, 12)
  }, [summary, chartDir])

  const vendorRows = useMemo(() => {
    const m = new Map<string, { vendor: string; covered: boolean } & Record<ReconTech, number>>()
    TECHS.forEach((t) => (summary?.techs?.[t]?.vendors ?? [])
      .filter((v) => v.direction === chartDir)
      .forEach((v) => {
        const e = m.get(v.vendor) ?? { vendor: v.vendor, covered: v.covered, '3g': 0, '4g': 0, '5g': 0 }
        e[t] += v.count
        m.set(v.vendor, e)
      }))
    return [...m.values()]
  }, [summary, chartDir])

  const countOf = (t: ReconTech, d: ReconDirection) => {
    const r = summary?.techs?.[t]?.run
    return r ? (d === 'missing_in_web' ? r.missing_in_web : r.missing_in_dump) : 0
  }

  const tinhOptions = useMemo(() => [...new Set((summary?.techs?.[tech]?.provinces ?? [])
    .filter((p) => p.direction === direction && p.tinh !== '(Chưa xác định)').map((p) => p.tinh))].sort(),
  [summary, tech, direction])
  const vendorOptions = useMemo(() => [...new Set((summary?.techs?.[tech]?.vendors ?? [])
    .filter((v) => v.direction === direction).map((v) => v.vendor))].sort(),
  [summary, tech, direction])

  const hasData = runs.length > 0

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 12 }} gutter={[8, 8]}>
        <Col>
          <Space align="center">
            <AuditOutlined style={{ fontSize: 22, color: '#597ef7' }} />
            <Typography.Title level={3} style={{ margin: 0 }}>Đối soát Cell: Dump ↔ Web</Typography.Title>
          </Space>
          <div style={{ color: '#8c8c8c', fontSize: 12 }}>
            {lastFinished ? `Cập nhật lần cuối: ${fdt(lastFinished)} · chạy tự động mỗi ngày` : 'Chưa có dữ liệu'}
          </div>
        </Col>
        <Col>
          <Space>
            <Button icon={<ReloadOutlined />} onClick={loadSummary} loading={loading}>Làm mới</Button>
            <Button icon={<FileExcelOutlined />} loading={exportingAll} disabled={!hasData} onClick={handleExportAll}
                    style={{ borderColor: '#52c41a', color: '#52c41a' }}>
              Xuất báo cáo tổng hợp
            </Button>
          </Space>
        </Col>
      </Row>

      {loadError && <Alert type="error" showIcon style={{ marginBottom: 12 }} message={loadError} />}
      {errors.map((r) => (
        <Alert key={r.id} type="error" showIcon style={{ marginBottom: 8 }}
               message={`Đối soát ${r.tech.toUpperCase()} thất bại (${fdt(r.started_at)})`} description={r.error} />
      ))}
      {stale && (
        <Alert type="warning" showIcon style={{ marginBottom: 8 }}
               message="Dữ liệu đối soát đã cũ hơn 36 giờ"
               description="Kiểm tra job chạy hằng ngày (reconcile_cells.py hoặc update_cells_with_revision.py --reconcile)." />
      )}
      {hasData && (totalWeb > 0 || totalDump > 0) && (
        <Alert type="warning" showIcon style={{ marginBottom: 12 }}
               message={
                 <span>
                   <strong>{fmt(totalWeb)}</strong> cell active trong dump chưa nhập lên web
                   {newWeb > 0 && <Tag color="red" style={{ marginLeft: 6 }}>+{fmt(newWeb)} mới</Tag>}
                   {' · '}
                   <strong>{fmt(totalDump)}</strong> cell có trên web nhưng không có trong dump
                   {newDump > 0 && <Tag color="orange" style={{ marginLeft: 6 }}>+{fmt(newDump)} mới</Tag>}
                 </span>
               } />
      )}
      {hasData && totalWeb === 0 && totalDump === 0 && (
        <Alert type="success" showIcon style={{ marginBottom: 12 }} message="Dữ liệu web và dump đang khớp hoàn toàn." />
      )}

      {/* ── KPI cards ── */}
      <Row gutter={[12, 12]} style={{ marginBottom: 16 }}>
        {TECHS.map((t) => (
          <Col xs={24} lg={8} key={t}>
            {loading && !summary ? <Card size="small"><Skeleton active /></Card>
              : <TechCard tech={t} s={summary?.techs?.[t]} onGo={goTo} />}
          </Col>
        ))}
      </Row>

      {/* ── analysis ── */}
      {hasData && (
        <Card size="small" style={{ marginBottom: 16 }}
              title="Phân tích chênh lệch"
              extra={
                <Segmented value={chartDir} onChange={(v) => setChartDir(v as ReconDirection)}
                           options={[{ label: DIR.missing_in_web.short, value: 'missing_in_web' },
                                     { label: DIR.missing_in_dump.short, value: 'missing_in_dump' }]} />
              }>
          <Row gutter={[16, 16]}>
            <Col xs={24} lg={12}>
              <Typography.Text strong>Xu hướng theo ngày</Typography.Text>
              <LineChart labels={trend.labels} series={trend.series} />
            </Col>
            <Col xs={24} lg={12}>
              <Typography.Text strong>Top tỉnh có nhiều chênh lệch nhất</Typography.Text>
              <div style={{ marginTop: 8 }}><ProvinceBars rows={provRows} /></div>
            </Col>
            <Col xs={24}>
              <Typography.Text strong>Theo vendor</Typography.Text>
              <Table size="small" pagination={false} style={{ marginTop: 8 }} rowKey="vendor" dataSource={vendorRows}
                     columns={[
                       { title: 'Vendor', dataIndex: 'vendor',
                         render: (v: string, r: any) => <span>{v}{!r.covered && <Tag style={{ marginLeft: 6 }}>chưa có nguồn dump</Tag>}</span> },
                       ...TECHS.map((t) => ({ title: t.toUpperCase(), dataIndex: t, align: 'right' as const,
                                              render: (v: number) => fmt(v) })),
                       { title: 'Tổng', key: 'sum', align: 'right' as const,
                         render: (_: unknown, r: any) => <strong>{fmt(r['3g'] + r['4g'] + r['5g'])}</strong> },
                     ]} />
            </Col>
          </Row>
        </Card>
      )}

      {/* ── detail tables ── */}
      <div ref={tableRef}>
        <Card size="small" style={{ marginBottom: 16 }} title="Chi tiết cell chênh lệch">
          <Segmented block value={direction} onChange={(v) => setDirection(v as ReconDirection)}
                     style={{ marginBottom: 8 }}
                     options={(['missing_in_web', 'missing_in_dump'] as ReconDirection[]).map((d) => ({
                       value: d,
                       label: (
                         <span style={{ color: DIR[d].color, fontWeight: 600 }}>
                           {DIR[d].label}{' '}
                           <Badge overflowCount={9999999} showZero style={{ backgroundColor: DIR[d].color }}
                                  count={TECHS.reduce((s, t) => s + countOf(t, d), 0)} />
                         </span>
                       ),
                     }))} />
          <Tabs activeKey={tech} onChange={(k) => setTech(k as ReconTech)}
                items={TECHS.map((t) => ({
                  key: t,
                  label: (
                    <span>
                      {t.toUpperCase()}{' '}
                      <Badge overflowCount={9999999} showZero style={{ backgroundColor: TECH_COLOR[t] }}
                             count={countOf(t, direction)} />
                    </span>
                  ),
                }))} />
          <Typography.Paragraph type="secondary" style={{ fontSize: 12 }}>{DIR[direction].desc}</Typography.Paragraph>
          {summary?.techs?.[tech]?.run
            ? <ReconcileTable key={`${tech}-${direction}`} tech={tech} direction={direction}
                              tinhOptions={tinhOptions} vendorOptions={vendorOptions} />
            : <Empty description={`Chưa có dữ liệu đối soát ${tech.toUpperCase()}`} />}
        </Card>
      </div>

      {/* ── run details ── */}
      {hasData && (
        <Collapse style={{ marginBottom: 16 }}>
          <Collapse.Panel key="run" header="Chi tiết lần chạy & phân loại trạng thái dump">
            <Row gutter={[16, 16]}>
              {TECHS.map((t) => {
                const run = summary?.techs?.[t]?.run
                if (!run) return null
                const files = run.vendor_status?.files ?? {}
                return (
                  <Col xs={24} lg={8} key={t}>
                    <Typography.Text strong>
                      <Tag color={TECH_COLOR[t]}>{t.toUpperCase()}</Tag>chạy lúc {fdt(run.finished_at)}
                    </Typography.Text>
                    <div style={{ margin: '8px 0' }}>
                      {Object.entries(files).map(([v, s]) => (
                        <Tag key={v} color={s.ok ? 'green' : 'red'}>{v}: {s.ok ? `${fmt(s.rows)} dòng` : 'lỗi/trống'}</Tag>
                      ))}
                    </div>
                    {(run.vendor_status?.duplicate_names ?? 0) > 0 && (
                      <div style={{ fontSize: 12, color: '#8c8c8c' }}>
                        {fmt(run.vendor_status?.duplicate_names)} tên cell trùng trong dump (đã gộp)
                      </div>
                    )}
                    {(run.vendor_status?.notes ?? []).map((n, i) => (
                      <div key={i} style={{ fontSize: 12, color: '#d48806' }}>{n}</div>
                    ))}
                    <Table size="small" pagination={false} style={{ marginTop: 8 }} rowKey="status"
                           scroll={{ y: 240 }} dataSource={run.status_stats ?? []}
                           columns={[
                             { title: 'Trạng thái trong dump', dataIndex: 'status' },
                             { title: 'Active?', dataIndex: 'active', width: 80,
                               render: (v: boolean) => (v ? <Tag color="green">Active</Tag> : <Tag>Không</Tag>) },
                             { title: 'Số cell', dataIndex: 'count', width: 90, align: 'right' as const,
                               render: (v: number) => fmt(v) },
                           ]} />
                  </Col>
                )
              })}
            </Row>
            <Typography.Paragraph type="secondary" style={{ fontSize: 12, marginTop: 12, marginBottom: 0 }}>
              Cell được coi là "active" khi trạng thái là UNLOCKED / UNBLOCKED / CELL_UNBLOCK / Active… (không phân biệt hoa thường).
              Thêm giá trị khác bằng biến môi trường RECONCILE_ACTIVE_STATUSES.
            </Typography.Paragraph>
          </Collapse.Panel>
        </Collapse>
      )}
    </div>
  )
}
''')

# --- route + menu (soft patches: App.tsx / layout are not in the upload) ------
FRONT = ROOT / "frontend" / "src"


def tsx_files():
    for p in sorted(FRONT.rglob("*.tsx")):
        yield p, str(p.relative_to(ROOT)).replace(os.sep, "/")


def patch_frontend_route():
    manual = ("Add the page route next to the RevisionPage route (App.tsx / router file):\n"
              "    import ReconcilePage from '@/pages/reconcile/ReconcilePage'\n"
              "    <Route path=\"reconcile\" element={<ReconcilePage />} />")
    cands = []
    for p, rel in tsx_files():
        if rel.endswith("pages/revision/RevisionPage.tsx"):
            continue
        t = p.read_text(encoding="utf-8")
        if "ReconcilePage" in t:
            P.notes.append("%s: ReconcilePage route already present" % rel)
            return
        if "<RevisionPage" in t:
            cands.append((rel, t.replace("\r\n", "\n")))
    if len(cands) != 1:
        P.manual.append(manual)
        return
    rel, t = cands[0]
    # import
    m = re.search(r"^(import\s+RevisionPage\s+from\s+['\"][^'\"]*['\"]\s*(;?)[ \t]*)$", t, re.M)
    if m:
        semi = m.group(2)
        imp = "import ReconcilePage from '@/pages/reconcile/ReconcilePage'" + semi
    else:
        m = re.search(r"^(const\s+RevisionPage\s*=\s*((?:React\.)?lazy)\(.*\)\s*(;?)[ \t]*)$", t, re.M)
        if not m:
            P.manual.append(manual)
            return
        imp = "const ReconcilePage = %s(() => import('@/pages/reconcile/ReconcilePage'))%s" % (m.group(2), m.group(3))
    # route line
    lines = t.split("\n")
    idx = [i for i, ln in enumerate(lines) if "<RevisionPage" in ln and "<Route" in ln]
    if len(idx) != 1:
        P.manual.append(manual)
        return
    ln = lines[idx[0]]
    pm = re.search(r'path=(["\'])(.*?)\1', ln)
    if not pm:
        P.manual.append(manual)
        return
    newpath = re.sub(r"revisions?/?$", "reconcile", pm.group(2))
    if newpath == pm.group(2):
        newpath = "reconcile"
    new_ln = ln.replace("RevisionPage", "ReconcilePage").replace(pm.group(0), "path=%s%s%s" % (pm.group(1), newpath, pm.group(1)))
    lines.insert(idx[0] + 1, new_ln)
    t2 = "\n".join(lines)
    t2 = t2.replace(m.group(1), m.group(1) + "\n" + imp, 1)
    P.set_text(rel, t2)
    P.notes.append("%s: route '%s' -> ReconcilePage added (menu key must match this path)" % (rel, newpath))


def patch_frontend_menu():
    manual = ("Add a menu entry next to 'Lịch sử thay đổi' (the layout / sider file):\n"
              "    { key: '/reconcile', icon: <AuditOutlined />, label: 'Đối soát Cell' }\n"
              "(use the same key/path style as the revision entry)")
    pat = re.compile(r"^[ \t]*\{[^\n]*['\"][^'\"]*revision[^'\"]*['\"][^\n]*\},?[ \t]*$", re.M | re.I)
    hits = []
    for p, rel in tsx_files():
        if "pages/revision/" in rel or "pages/reconcile/" in rel:
            continue
        t = p.read_text(encoding="utf-8").replace("\r\n", "\n")
        if "reconcile" in t.lower() and "ReconcilePage" not in t:
            P.notes.append("%s: menu already has a reconcile entry" % rel)
            return
        for m in pat.finditer(t):
            if re.search(r"key\s*:|path\s*:|to\s*[=:]", m.group(0)):
                hits.append((rel, t, m))
    if len(hits) != 1:
        P.manual.append(manual)
        return
    rel, t, m = hits[0]
    line = m.group(0)
    nl = line.replace("revisions", "reconcile").replace("revision", "reconcile").replace("Revisions", "reconcile")
    nl2 = re.sub(r"(label\s*:\s*)(['\"])(.*?)\2", lambda mm: "%s%sĐối soát Cell%s" % (mm.group(1), mm.group(2), mm.group(2)), nl)
    if nl2 == nl:
        nl2 = re.sub(r"(>)([^<>{}\n]+)(</)", r"\1Đối soát Cell\3", nl)
    icon_ok = False
    im = re.search(r"import\s*\{([^}]*)\}\s*from\s*(['\"])@ant-design/icons\2", t)
    if im and re.search(r"<\w+Outlined\s*/>", nl2):
        nl2 = re.sub(r"<\w+Outlined\s*/>", "<AuditOutlined />", nl2)
        icon_ok = True
    out = t[:m.end()] + "\n" + nl2 + t[m.end():]
    if icon_ok and "AuditOutlined" not in im.group(1):
        names = im.group(1).rstrip()
        sep = "" if names.endswith(",") else ","
        out = out.replace(im.group(0), im.group(0).replace(im.group(1), names + sep + " AuditOutlined "), 1)
    P.set_text(rel, out)
    P.notes.append("%s: menu entry 'Đối soát Cell' added" % rel)


patch_frontend_route()
patch_frontend_menu()

# =============================================================================
P.commit()
PYEOF

echo
BACKEND="$ROOT/backend"
if [ "$DO_MIGRATE" = "1" ]; then
  echo ">> Creating tables ..."
  (cd "$BACKEND" && python3 reconcile_cells.py --init-db)
fi
if [ "$DRY_NOW" = "1" ]; then
  echo ">> Dry run (downloads all vendor CSVs, writes nothing) ..."
  (cd "$BACKEND" && python3 reconcile_cells.py --dry-run) || true
fi
if [ "$RUN_NOW" = "1" ]; then
  echo ">> Running the reconciliation ..."
  (cd "$BACKEND" && python3 reconcile_cells.py) || true
fi

cat <<'EOF'

=============================== NEXT STEPS ===================================
1. Create the tables once (or let the API create them on first request):
     python backend/reconcile_cells.py --init-db
   Docker:  docker compose exec backend python reconcile_cells.py --init-db
   Plain SQL alternative: backend/migrations/add_cell_reconcile.sql
2. Try it without writing anything:
     python backend/reconcile_cells.py --dry-run
3. Schedule it once a day (pick ONE):
     # sync first, then reconcile - the vendor CSVs are downloaded only once
     0 2 * * *  cd /path/to/backend && python3 update_cells_with_revision.py --reconcile
     # or stand-alone
     0 3 * * *  cd /path/to/backend && python3 reconcile_cells.py
4. Restart the backend and rebuild the frontend. New menu page: "Đối soát Cell".

Optional environment variables (see cell_reconcile_core.py header):
  RECONCILE_ACTIVE_STATUSES  extra status values counted as active, e.g. "1,enable"
  RECONCILE_WEBHOOK_URL      Teams/Slack-style webhook that receives a daily summary
  RECONCILE_KEEP_RUNS / RECONCILE_KEEP_DAYS / RECONCILE_MIN_RATIO
==============================================================================
EOF