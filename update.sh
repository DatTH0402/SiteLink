#!/usr/bin/env bash
# =============================================================================
#  apply_cell_update.sh  -  SiteLink: new 3G / 4G / 5G cell transformation rules
#
#  Usage:   ./apply_cell_update.sh [PROJECT_ROOT] [--no-migrate] [--no-test]
#           (PROJECT_ROOT = folder that contains backend/, frontend/ and the
#            root-level update_cells_with_revision.py; default = current dir)
#
#  What it does (idempotent - safe to run twice):
#    1. Backs up every file it touches to  <root>/.backup_cell_update_<time>/
#    2. Rewrites   backend/cell_sync_core.py              (new rules, shared by web + script)
#    3. Rewrites   backend/update_cells_with_revision.py  (manual/daily script, --dry-run, --tech)
#       Rewrites   update_cells_with_revision.py          (root file -> thin wrapper of the above)
#    4. Patches    models, revision models, schemas, revision service/route
#                  (new columns dump_date + oss)
#    5. Patches    frontend: hides Baseband, shows "Ngay du lieu dump" + OSS, types
#    6. Adds the 2 DB columns to the 6 tables (ALTER TABLE ... IF NOT EXISTS)
#    7. Compiles the python files and runs a built-in self-test of every rule
# =============================================================================
set -euo pipefail

ROOT=""; MIGRATE=1; RUN_TESTS=1
for a in "$@"; do
  case "$a" in
    --no-migrate) MIGRATE=0 ;;
    --no-test)    RUN_TESTS=0 ;;
    -h|--help)    sed -n '2,20p' "$0"; exit 0 ;;
    *)            ROOT="$a" ;;
  esac
done
ROOT="$(cd "${ROOT:-.}" && pwd)"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$ROOT/backend/app" ] || die "'$ROOT' does not look like the SiteLink root (backend/app not found)."
[ -d "$ROOT/frontend/src" ] || warn "frontend/src not found - frontend patches will be reported as problems."
command -v python3 >/dev/null || die "python3 is required."

# ── Python with the backend dependencies (for migration + self-test) ─────────
APP_PY=""
for cand in "${PYTHON:-}" "$ROOT/backend/.venv/bin/python" "$ROOT/backend/venv/bin/python" \
            "$ROOT/.venv/bin/python" "$ROOT/venv/bin/python" python3; do
  [ -n "$cand" ] || continue
  if command -v "$cand" >/dev/null 2>&1 && \
     "$cand" -c "import sqlalchemy, pandas, requests" >/dev/null 2>&1; then
    APP_PY="$cand"; break
  fi
done
[ -n "$APP_PY" ] && echo "Using python with deps: $APP_PY" \
                 || warn "No python with sqlalchemy+pandas+requests found: migration and self-test will be skipped (set PYTHON=/path/to/venv/python to enable)."

# ── 1. Backup ────────────────────────────────────────────────────────────────
say "1/7  Backup"
BK="$ROOT/.backup_cell_update_$(date +%Y%m%d_%H%M%S)"
FILES=(
  backend/cell_sync_core.py
  backend/update_cells_with_revision.py
  update_cells_with_revision.py
  backend/app/models/cell_3g.py
  backend/app/models/cell_4g.py
  backend/app/models/cell_5g.py
  backend/app/models/cell_revision.py
  backend/app/schemas/cell.py
  backend/app/services/revision.py
  backend/app/api/routes/revision.py
  frontend/src/types/index.ts
  frontend/src/api/revision.ts
  frontend/src/pages/cells/Cells3GPage.tsx
  frontend/src/pages/cells/Cells4GPage.tsx
  frontend/src/pages/cells/Cells5GPage.tsx
  frontend/src/pages/revision/RevisionPage.tsx
)
for f in "${FILES[@]}"; do
  if [ -f "$ROOT/$f" ]; then
    mkdir -p "$BK/$(dirname "$f")"; cp -p "$ROOT/$f" "$BK/$f"
  fi
done
echo "Backup in: $BK"

# ── 2. backend/cell_sync_core.py ─────────────────────────────────────────────
say "2/7  Writing backend/cell_sync_core.py"
cat > "$ROOT/backend/cell_sync_core.py" <<'PYEOF'
"""
cell_sync_core.py
-----------------
Shared cell-sync logic (used by the web API *and* by update_cells_with_revision.py).

Rules implemented (see the transformation spec):
  * every ID-like value is converted to an integer string (no trailing ".0")
  * composite ids are "{node}-{local cell}", ECI = eNB*256 + cell, NCI (Huawei) = gNB*2^(36-len)+cell
  * dBm values are formatted with DBM_DECIMALS decimals ("33.0", "55.1", ...)
  * ANY error in a calculation  ->  the result is empty (None), never an exception
  * dump_date ("Ngay cap nhat") and oss (ENM / OSS / oss) are META columns:
      they are refreshed on every run but do NOT create a revision on their own
  * a column that a vendor can not supply is marked _KEEP: the DB value is left untouched
"""
from __future__ import annotations

import io
import json
import logging
import math
import re
import unicodedata
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Set

import pandas as pd
import requests
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Connection

log = logging.getLogger(__name__)

# ── Tunables ──────────────────────────────────────────────────────────────────
DBM_DECIMALS     = 1            # 33.0 / 34.7 / 55.1
DBM_MIN, DBM_MAX = -30.0, 100.0  # sanity window for every dBm result (outside -> empty)
BW_4G_WITH_UNIT  = True         # 4G bandwidth as "20MHz" (False -> "20")

# ── Source URLs ───────────────────────────────────────────────────────────────
URLS: Dict[str, str] = {
    "ericsson_3g": "http://10.50.87.168/freework/ericsson_sitecell_umts_data.php?export=csv&token=c0b0575ce350303e9192335a9fa52ebac6bd33dc10a7ea47fe04b8bd1fbde71c",
    "huawei_3g":   "http://10.50.87.168/freework/huawei_sitecell_umts_data.php?export=csv&token=096b07429cbb8a83918ce713a3646c061ab1f13043037abaa683373c9c9b756b",
    "nokia_3g":    "http://10.50.87.168/freework/nokia_sitecell_3g_data.php?export=csv&token=3723ede0f68a6e08f7eb96d7a8d77835b8e1cc6c9b70ccfa8f86103077967dba",
    "ericsson_4g": "http://10.50.87.168/freework/ericsson_sitecell_lte_data.php?export=csv&token=c0b0575ce350303e9192335a9fa52ebac6bd33dc10a7ea47fe04b8bd1fbde71c",
    "huawei_4g":   "http://10.50.87.168/freework/huawei_sitecell_lte_data.php?export=csv&token=096b07429cbb8a83918ce713a3646c061ab1f13043037abaa683373c9c9b756b",
    "nokia_4g":    "http://10.50.87.168/freework/nokia_sitecell_4g_data.php?export=csv&token=3723ede0f68a6e08f7eb96d7a8d77835b8e1cc6c9b70ccfa8f86103077967dba",
    "ericsson_5g": "http://10.50.87.168/freework/ericsson_sitecell_nr_data.php?export=csv&token=c0b0575ce350303e9192335a9fa52ebac6bd33dc10a7ea47fe04b8bd1fbde71c",
    "huawei_5g":   "http://10.50.87.168/freework/huawei_sitecell_nr_data.php?export=csv&token=096b07429cbb8a83918ce713a3646c061ab1f13043037abaa683373c9c9b756b",
    "nokia_5g":    "http://10.50.87.168/freework/nokia_sitecell_5g_data.php?export=csv&token=3723ede0f68a6e08f7eb96d7a8d77835b8e1cc6c9b70ccfa8f86103077967dba",
}

VENDOR_KEYS: Dict[str, Dict[str, str]] = {
    "3g": {"ericsson": "ericsson_3g", "nokia": "nokia_3g", "huawei": "huawei_3g"},
    "4g": {"ericsson": "ericsson_4g", "nokia": "nokia_4g", "huawei": "huawei_4g"},
    "5g": {"ericsson": "ericsson_5g", "nokia": "nokia_5g", "huawei": "huawei_5g"},
}

REVISION_TABLES = {
    "cells_3g": "cell_3g_revisions",
    "cells_4g": "cell_4g_revisions",
    "cells_5g": "cell_5g_revisions",
}

# Columns owned by the sync. (baseband is obsolete -> no longer touched.)
COLUMNS_TO_UPDATE = {
    "cells_3g": ["cell_id", "uarfcn", "psc", "mimo", "lac", "rac", "ura_id",
                 "cell_max_power", "cpich_power", "rf", "bbu_name", "cell_status"],
    "cells_4g": ["enodeb_id", "cell_id", "earfcn", "tac", "pci", "root_sequence_id",
                 "mimo", "bandwidth", "cell_max_power", "eci",
                 "rf", "bbu_name", "cell_status"],
    "cells_5g": ["gnodeb_id", "cell_id", "tac", "pci", "root_sequence_id", "mimo",
                 "ssb_arfcn", "center_arfcn", "gscn", "bandwidth", "cell_max_power",
                 "nci", "rf", "bbu_name", "mu_mimo", "cell_status"],
}
META_COLUMNS = ["dump_date", "oss"]     # refreshed always, never a revision on their own

SCRIPT_USER_ID   = None
SCRIPT_USER_NAME = "Script tự động"
CHANGE_SOURCE    = "script"
ALL_VENDORS      = {"ericsson", "huawei", "nokia"}

_KEEP = "\x00KEEP\x00"      # "this vendor can not supply the column -> do not touch the DB value"
_DUMP_COLS = ("Ngày cập nhật", "Ngay cap nhat", "Ngày dữ liệu dump")

# ═════════════════════════════════════════════════════════════════════════════
#  Low-level value helpers  (every helper returns None on any problem)
# ═════════════════════════════════════════════════════════════════════════════
_NULL_TEXT = {"", "nan", "none", "null", "<na>", "nat", "n/a"}


def _clean(v: Any) -> Optional[str]:
    """Raw cell -> stripped string, or None for empty / NaN / 'nan' / '<NA>' ..."""
    if v is None:
        return None
    if isinstance(v, float) and math.isnan(v):
        return None
    s = str(v).strip()
    return None if s.lower() in _NULL_TEXT else s


def _canon(v: Any) -> Optional[str]:
    """Canonical form used to compare DB values with new values (garbage like '<NA>' stays garbage)."""
    if v is None:
        return None
    s = str(v).strip()
    return s or None


def _num(v: Any) -> Optional[float]:
    s = _clean(v)
    if s is None:
        return None
    try:
        f = float(s)
    except ValueError:
        return None
    return f if math.isfinite(f) else None


def _int(v: Any) -> Optional[int]:
    s = _clean(v)
    if s is None:
        return None
    if re.fullmatch(r"[+-]?\d+", s):
        return int(s)
    f = _num(s)
    if f is None:
        return None
    r = round(f)
    return int(r) if abs(f - r) < 1e-9 else None


def _int_str(v: Any) -> Optional[str]:
    i = _int(v)
    return None if i is None else str(i)


def _scaled(v: Any, div: float) -> Optional[float]:
    f = _num(v)
    return None if f is None else f / div


def _dbm_str(f: Optional[float]) -> Optional[str]:
    if f is None or not math.isfinite(f) or not (DBM_MIN <= f <= DBM_MAX):
        return None
    return f"{f:.{DBM_DECIMALS}f}"


def _div10_dbm(v: Any) -> Optional[str]:
    return _dbm_str(_scaled(v, 10))


def _mhz_str(f: Optional[float]) -> Optional[str]:
    if f is None or not math.isfinite(f) or f <= 0:
        return None
    return f"{f:.2f}".rstrip("0").rstrip(".")


def _bw_out(mhz: Optional[float]) -> Optional[str]:      # 4G bandwidth
    s = _mhz_str(mhz)
    if s is None:
        return None
    return s + "MHz" if BW_4G_WITH_UNIT else s


def _digits_mhz(v: Any) -> Optional[str]:                  # "CELL_BW_100M" / "100MHz" -> "100"
    s = _clean(v)
    m = re.search(r"(\d+(?:\.\d+)?)", s) if s else None
    return _mhz_str(float(m.group(1))) if m else None


def _first_token(v: Any) -> Optional[str]:                 # "RRU3971a,WD5...,KUNLUN" -> "RRU3971a"
    s = _clean(v)
    if not s:
        return None
    return s.split(",")[0].strip() or None


def _compose(a: Any, b: Any) -> Optional[str]:
    ia, ib = _int(a), _int(b)
    return None if ia is None or ib is None else f"{ia}-{ib}"


def _from_dist(pattern: str):
    rx = re.compile(pattern)

    def f(v: Any) -> Optional[str]:
        s = _clean(v)
        m = rx.search(s) if s else None
        return m.group(1) if m else None
    return f


_LNBTS = _from_dist(r"(?:^|/)LNBTS-(\d+)")
_LNCEL = _from_dist(r"(?:^|/)LNCEL-(\d+)")
_NRBTS = _from_dist(r"(?:^|/)NRBTS-(\d+)")
_NRCEL = _from_dist(r"(?:^|/)NRCELL-(\d+)")


def _eci(enb: Any, cid: Any) -> Optional[str]:
    ie, ic = _int(enb), _int(cid)
    if ie is None or ic is None or not (0 <= ic <= 255):
        return None
    return str(ie * 256 + ic)


def _nci_huawei(gnb: Any, gnb_len: Any, cid: Any) -> Optional[str]:
    ig, il, ic = _int(gnb), _int(gnb_len), _int(cid)
    if None in (ig, il, ic) or not (0 < il <= 36):
        return None
    shift = 36 - il
    if not (0 <= ic < (1 << shift)):
        return None
    return str(ig * (1 << shift) + ic)


# ── MIMO ─────────────────────────────────────────────────────────────────────
_TRX_RX = re.compile(r"\s*(\d+)\s*T\s*(\d+)\s*R\s*", re.I)


def _norm_mimo(v: Any) -> Optional[str]:                   # "2t2r " -> "2T2R"
    s = _clean(v)
    m = _TRX_RX.fullmatch(s) if s else None
    return f"{int(m.group(1))}T{int(m.group(2))}R" if m else None


def _trx_mimo(tx: Any, rx: Any) -> Optional[str]:
    a, b = _int(tx), _int(rx)
    return f"{a}T{b}R" if a and b and a > 0 and b > 0 else None


def _sym_mimo(tx: Any) -> Optional[str]:                   # Ericsson 4G: {x}T{x}R
    return _trx_mimo(tx, tx)


def _mimo_from_array(v: Any) -> Optional[str]:             # "Full 64TRX Array (4x8x2)" -> "64T64R"
    s = _clean(v)
    m = re.search(r"(\d+)\s*TRX", s, re.I) if s else None
    return f"{int(m.group(1))}T{int(m.group(1))}R" if m else None


def _parse_t(mimo: Any) -> Optional[int]:
    s = _clean(mimo)
    m = _TRX_RX.fullmatch(s) if s else None
    t = int(m.group(1)) if m else None
    return t if t and t > 0 else None


def _power_plus_antennas(base_dbm: Optional[float], mimo: Any) -> Optional[str]:
    """Power(dBm) = base + 10*log10(T)   with T taken from the {T}T{R}R MIMO value."""
    t = _parse_t(mimo)
    if base_dbm is None or t is None:
        return None
    return _dbm_str(base_dbm + 10 * math.log10(t))


def _per_antenna_dbm(v: Any) -> Optional[float]:           # Huawei / Nokia: raw is 0.1 dBm per antenna
    return _scaled(v, 10)


def _ericsson_nr_power(mw: Any, mimo: Any) -> Optional[str]:
    """
    Ericsson NR ConfiguredMaxTxPower is the TOTAL power in mW (320000 mW = 320 W).
    base (per Tx branch) = 10*log10(mW / T)  -> 320000/32 = 10 W = 40 dBm
    result               = base + 10*log10(T) -> 40 + 15.05 = 55.05 dBm
    """
    p, t = _num(mw), _parse_t(mimo)
    if p is None or p <= 0 or t is None:
        return None
    base = 10 * math.log10(p / t)
    return _dbm_str(base + 10 * math.log10(t))


def _mumimo_pair(dl: Any, ul: Any) -> Optional[str]:       # "{DL}DL{UL}UL"
    a, b = _int(dl), _int(ul)
    return f"{a}DL{b}UL" if a is not None and b is not None and a >= 0 and b >= 0 else None


# ── GSCN (3GPP TS 38.104 sync raster) ────────────────────────────────────────
def _nrarfcn_to_khz(n: int) -> Optional[int]:
    if n < 0:
        return None
    if n < 600000:
        return 5 * n
    if n < 2016667:
        return 3_000_000 + 15 * (n - 600000)
    return None


def _gscn_from_arfcn(v: Any) -> Optional[str]:
    n = _int(v)
    f = _nrarfcn_to_khz(n) if n is not None else None
    if f is None:
        return None
    if f < 3_000_000:
        N, rem = divmod(f, 1200)
        if N < 1 or rem not in (50, 150, 250):
            return None
        return str(3 * N + (rem // 50 - 3) // 2)
    if f < 24_250_000:
        N, rem = divmod(f - 3_000_000, 1440)
        return str(7499 + N) if rem == 0 else None
    return None


def _ericsson_gscn(ssb_freq: Any, arfcn_cell: Any) -> Optional[str]:
    n = _int(ssb_freq)
    if n is not None and 2 <= n <= 26639:          # already a GSCN
        return str(n)
    return _gscn_from_arfcn(n if n is not None else arfcn_cell)   # ARFCN -> GSCN


# ── 4G Huawei bandwidth ──────────────────────────────────────────────────────
_BW4G_HUAWEI = {"CELL_BW_N100": 20.0, "CELL_BW_N75": 15.0, "CELL_BW_N50": 10.0,
                "CELL_BW_N25": 5.0, "CELL_BW_N15": 3.0, "CELL_BW_N6": 1.4}


def _bw4g_huawei(v: Any) -> Optional[str]:
    s = _clean(v)
    return _bw_out(_BW4G_HUAWEI.get(s.upper())) if s else None


# ═════════════════════════════════════════════════════════════════════════════
#  DataFrame helpers
# ═════════════════════════════════════════════════════════════════════════════
def _norm_key(s: Any) -> str:
    s = unicodedata.normalize("NFKD", str(s)).replace("đ", "d").replace("Đ", "D")
    s = "".join(ch for ch in s if not unicodedata.combining(ch))
    return re.sub(r"[^0-9a-z]", "", s.lower())


def _col(df: pd.DataFrame, *names: str, warn: bool = True) -> pd.Series:
    """
    Cleaned string Series (None where empty).  Several candidate names are
    coalesced in order; names match exactly or ignoring case/space/accents.
    Missing column -> all None (and a warning).
    """
    lookup: Dict[str, str] = {}
    for col in df.columns:
        lookup.setdefault(_norm_key(col), col)
    used: List[str] = []
    for n in names:
        col = n if n in df.columns else lookup.get(_norm_key(n))
        if col is not None and col not in used:
            used.append(col)
    if not used:
        if warn:
            log.warning("source column not found: %s", " | ".join(names))
        return pd.Series([None] * len(df), index=df.index, dtype=object)
    vals: List[Optional[str]] = [None] * len(df)
    for col in used:
        s = df[col]
        if isinstance(s, pd.DataFrame):
            s = s.iloc[:, 0]
        for i, x in enumerate(s.tolist()):
            if vals[i] is None:
                vals[i] = _clean(x)
    return pd.Series(vals, index=df.index, dtype=object)


def _rows(fn, *series: pd.Series, index) -> pd.Series:
    """Apply fn row-wise; ANY exception -> None (empty result)."""
    out = []
    for args in zip(*series):
        try:
            out.append(fn(*args))
        except Exception:
            out.append(None)
    return pd.Series(out, index=index, dtype=object)


def _ctx(r: pd.DataFrame):
    def c(*names, warn=True):
        return _col(r, *names, warn=warn)

    def m(fn, *series):
        return _rows(fn, *series, index=r.index)
    return c, m


def _coalesce(*series: pd.Series, index) -> pd.Series:
    out = []
    for vals in zip(*series):
        out.append(next((v for v in vals if v is not None), None))
    return pd.Series(out, index=index, dtype=object)


def _mimo_5g(r: pd.DataFrame) -> pd.Series:
    """
    5G MIMO as {T}T{R}R.  The spec lists the sources under different vendors than the
    real files use, so every vendor tries all three sources in turn:
      TXRXMODE ("32T32R")  ->  NoOfUsedTx/RxAntennas  ->  mMimoAntArrayMode ("Full 64TRX Array")
    """
    c, m = _ctx(r)
    return _coalesce(
        m(_norm_mimo,       c("TXRXMODE", warn=False)),
        m(_trx_mimo,        c("NoOfUsedTxAntennas", warn=False), c("NoOfUsedRxAntennas", warn=False)),
        m(_mimo_from_array, c("mMimoAntArrayMode", warn=False)),
        index=r.index)


# ═════════════════════════════════════════════════════════════════════════════
#  Builders  (one per tech x vendor)  ->  DataFrame with the DB column names
# ═════════════════════════════════════════════════════════════════════════════
# ── 3G ───────────────────────────────────────────────────────────────────────
def _b3g_ericsson(r: pd.DataFrame) -> pd.DataFrame:
    c, m = _ctx(r)
    return pd.DataFrame({
        "cell_name":      c("rnc_UtranCellId"),
        "cell_id":        m(_int_str, c("rnc_cId")),
        "uarfcn":         m(_int_str, c("rnc_uarfcnDl")),
        "psc":            m(_int_str, c("rnc_primaryScrCode")),
        "mimo":           _KEEP,                                    # NULL in source -> keep DB value
        "lac":            m(_int_str, c("rnc_lac")),
        "rac":            m(_int_str, c("rnc_rac")),
        "ura_id":         m(_int_str, c("rnc_ura_id")),
        "cell_max_power": m(_div10_dbm, c("maximumTransmissionPower")),
        "cpich_power":    m(_div10_dbm, c("primaryCpichPower")),
        "rf":             c("hw_productName"),
        "bbu_name":       c("node_name"),
        "cell_status":    c("rnc_adminState"),
        "dump_date":      c(*_DUMP_COLS, warn=False),
        "oss":            "ENM",
    }, index=r.index)


def _b3g_huawei(r: pd.DataFrame) -> pd.DataFrame:
    c, m = _ctx(r)
    return pd.DataFrame({
        "cell_name":      c("CELLNAME"),
        "cell_id":        m(_int_str, c("CELLID")),
        "uarfcn":         m(_int_str, c("UARFCN DOWNLINK")),
        "psc":            m(_int_str, c("PSCRAMBCODE")),
        "mimo":           m(lambda v: v if v else _KEEP, c("TXRXMODE")),
        "lac":            m(_int_str, c("LAC")),
        "rac":            m(_int_str, c("RAC")),
        "ura_id":         m(_int_str, c("URAID", "URAId")),
        "cell_max_power": m(_div10_dbm, c("RNC UCELL MAXTXPOWER")),
        "cpich_power":    m(_div10_dbm, c("PCPICHPOWER (0.1dBm)")),
        "rf":             m(_first_token, c("RRU ManufacturerData")),
        "bbu_name":       c("NEname"),
        "cell_status":    c("BLKSTATUS"),
        "dump_date":      c(*_DUMP_COLS, warn=False),
        "oss":            "OSS",
    }, index=r.index)


def _b3g_nokia(r: pd.DataFrame) -> pd.DataFrame:
    c, m = _ctx(r)
    return pd.DataFrame({
        "cell_name":      c("name"),
        "cell_id":        m(_int_str, c("CId")),
        "uarfcn":         m(_int_str, c("UARFCN")),
        "psc":            m(_int_str, c("PriScrCode")),
        "mimo":           _KEEP,
        "lac":            m(_int_str, c("LAC")),
        "rac":            m(_int_str, c("RAC")),
        "ura_id":         m(_int_str, c("URAID", "URAId")),
        "cell_max_power": m(_div10_dbm, c("PtxCellMax")),
        "cpich_power":    m(_div10_dbm, c("PtxPrimaryCPICH")),
        "rf":             c("RRU productName"),
        "bbu_name":       c("WBTS_name"),
        "cell_status":    c("AdminCellState"),
        "dump_date":      c(*_DUMP_COLS, warn=False),
        "oss":            "oss",
    }, index=r.index)


# ── 4G ───────────────────────────────────────────────────────────────────────
def _b4g_ericsson(r: pd.DataFrame) -> pd.DataFrame:
    c, m = _ctx(r)
    enb, cid = c("eNBId"), c("cellId")
    return pd.DataFrame({
        "cell_name":        c("eUtranCellFDDId"),
        "enodeb_id":        m(_int_str, enb),
        "cell_id":          m(_compose, enb, cid),
        "earfcn":           m(_int_str, c("earfcndl")),
        "tac":              m(_int_str, c("tac")),
        "pci":              m(_int_str, c("physicalLayerCellId")),
        "root_sequence_id": m(_int_str, c("rachRootSequence")),
        "mimo":             m(_sym_mimo, c("noOfUsedTxAntennas")),
        "bandwidth":        m(lambda v: _bw_out(_scaled(v, 1000)), c("dlChannelBandwidth")),
        "cell_max_power":   m(_div10_dbm, c("maximumTransmissionPower")),
        "eci":              m(_eci, enb, cid),
        "rf":               c("hw_productName"),
        "bbu_name":         c("node"),
        "cell_status":      c("administrativeState"),
        "dump_date":        c(*_DUMP_COLS, warn=False),
        "oss":              "ENM",
    }, index=r.index)


def _b4g_huawei(r: pd.DataFrame) -> pd.DataFrame:
    c, m = _ctx(r)
    enb, cid = c("ENODEBID"), c("CELLID")
    return pd.DataFrame({
        "cell_name":        c("CELLNAME"),
        "enodeb_id":        m(_int_str, enb),
        "cell_id":          m(_compose, enb, cid),
        "earfcn":           m(_int_str, c("DLEARFCN")),
        "tac":              m(_int_str, c("TAC")),
        "pci":              m(_int_str, c("Physical cell ID")),
        "root_sequence_id": m(_int_str, c("Root sequence index")),
        "mimo":             m(_norm_mimo, c("TXRXMODE")),
        "bandwidth":        m(_bw4g_huawei, c("DLBANDWIDTH")),
        "cell_max_power":   m(_div10_dbm, c("Maximum transmit power (0.1dBm)")),
        "eci":              m(_eci, enb, cid),
        "rf":               m(_first_token, c("RRU ManufacturerData")),
        "bbu_name":         c("NE"),
        "cell_status":      c("Cell admin state"),
        "dump_date":        c(*_DUMP_COLS, warn=False),
        "oss":              "OSS",
    }, index=r.index)


def _b4g_nokia(r: pd.DataFrame) -> pd.DataFrame:
    c, m = _ctx(r)
    dist = c("distName")
    enb, cid = m(_LNBTS, dist), m(_LNCEL, dist)
    return pd.DataFrame({
        "cell_name":        c("name", "cellName"),
        "enodeb_id":        m(_int_str, enb),
        "cell_id":          m(_compose, enb, cid),
        "earfcn":           m(_int_str, c("earfcnDL")),
        "tac":              m(_int_str, c("tac")),
        "pci":              m(_int_str, c("phyCellId")),
        "root_sequence_id": m(_int_str, c("rootSeqIndex")),
        "mimo":             m(_trx_mimo, c("Cell nTX"), c("Cell nRX")),
        "bandwidth":        m(lambda v: _bw_out(_scaled(v, 10)), c("dlChBw")),
        "cell_max_power":   m(_div10_dbm, c("pMax_0_1dBm")),
        "eci":              m(_eci, enb, cid),
        "rf":               c("RRU productName"),
        "bbu_name":         c("MRBTS_btsname"),
        "cell_status":      c("blockingState"),
        "dump_date":        c(*_DUMP_COLS, warn=False),
        "oss":              "oss",
    }, index=r.index)


# ── 5G ───────────────────────────────────────────────────────────────────────
def _b5g_ericsson(r: pd.DataFrame) -> pd.DataFrame:
    c, m = _ctx(r)
    gnb, cid = c("gNodeBId"), c("NRCellCU_LocalCellId")
    mimo = _mimo_5g(r)
    return pd.DataFrame({
        "cell_name":        c("NRCellCUId"),
        "gnodeb_id":        m(_int_str, gnb),
        "cell_id":          m(_compose, gnb, cid),
        "tac":              m(_int_str, c("TAC")),
        "pci":              m(_int_str, c("PCI")),
        "root_sequence_id": m(_int_str, c("rachRootSequence")),
        "mimo":             mimo,
        "ssb_arfcn":        m(_int_str, c("ARFCN_DL_Cell")),
        "center_arfcn":     m(_int_str, c("ARFCN_DL_SC")),
        "gscn":             m(_ericsson_gscn, c("ssbFrequency"), c("ARFCN_DL_Cell", warn=False)),
        "bandwidth":        m(lambda v: _mhz_str(_num(v)), c("BSChannelBwDL")),
        "cell_max_power":   m(_ericsson_nr_power, c("ConfiguredMaxTxPower"), mimo),
        "nci":              m(_int_str, c("NRCellCU_nCI")),
        "rf":               c("RF_ProductNames"),
        "bbu_name":         c("Node"),
        "mu_mimo":          m(_mumimo_pair,
                              c("dlMaxMuMimoLayers", "NRCellDU_dlMaxMuMimoLayers"),
                              c("ulMaxMuMimoLayers", "NRCellDU_ulMaxMuMimoLayers")),
        "cell_status":      c("AdministrativeState_SC"),
        "dump_date":        c(*_DUMP_COLS, warn=False),
        "oss":              "ENM",
    }, index=r.index)


def _b5g_huawei(r: pd.DataFrame) -> pd.DataFrame:
    c, m = _ctx(r)
    gnb, cid = c("GNBID"), c("CELLID")
    mimo = _mimo_5g(r)
    return pd.DataFrame({
        "cell_name":        c("CELLNAME"),
        "gnodeb_id":        m(_int_str, gnb),
        "cell_id":          m(_compose, gnb, cid),
        "tac":              m(_int_str, c("TAC")),
        "pci":              m(_int_str, c("Physical cell ID")),
        "root_sequence_id": m(_int_str, c("Logical Root sequence index")),
        "mimo":             mimo,
        "ssb_arfcn":        m(_int_str, c("SSB-ARFCN")),
        "center_arfcn":     m(_int_str, c("DLNARFCN")),
        "gscn":             m(_int_str, c("SSB GSCN")),
        "bandwidth":        m(_digits_mhz, c("DLBANDWIDTH")),
        "cell_max_power":   m(lambda v, mi: _power_plus_antennas(_per_antenna_dbm(v), mi),
                              c("MAXTRANSMITPOWER"), mimo),
        "nci":              m(_nci_huawei, gnb, c("GNBIDLENGTH"), cid),
        "rf":               m(_first_token, c("RRU ManufacturerData")),
        "bbu_name":         c("NE"),
        "mu_mimo":          m(_mumimo_pair,
                              c("MAXMIMOLAYERNUM", "DL MIMO layers (PDSCH)"),
                              c("MAXMIMOLAYERCNT", "UL MIMO layers (PUSCH)")),
        "cell_status":      c("Cell admin state"),
        "dump_date":        c(*_DUMP_COLS, warn=False),
        "oss":              "OSS",
    }, index=r.index)


def _b5g_nokia(r: pd.DataFrame) -> pd.DataFrame:
    c, m = _ctx(r)
    dist = c("distName")
    gnb, cid = m(_NRBTS, dist), m(_NRCEL, dist)
    mimo = _mimo_5g(r)
    return pd.DataFrame({
        "cell_name":        c("NRCELL_cellName"),
        "gnodeb_id":        m(_int_str, gnb),
        "cell_id":          m(_compose, gnb, cid),
        "tac":              m(_int_str, c("configuredEpsTac")),
        "pci":              m(_int_str, c("physCellId")),
        "root_sequence_id": m(_int_str, c("prachRootSequenceIndex")),
        "mimo":             mimo,
        "ssb_arfcn":        m(_int_str, c("arfcnSsbPbch")),
        "center_arfcn":     m(_int_str, c("nrarfcn")),
        "gscn":             m(_int_str, c("gscnOrSsPbchArfcn")),
        "bandwidth":        m(_digits_mhz, c("chBw")),
        "cell_max_power":   m(lambda v, mi: _power_plus_antennas(_per_antenna_dbm(v), mi),
                              c("pMax_0_1dBm"), mimo),
        "nci":              m(_int_str, c("nrCellIdentity")),
        "rf":               c("RRU productName"),
        "bbu_name":         c("MRBTS_btsname"),
        "mu_mimo":          c("nrCellType"),
        "cell_status":      c("administrativeState"),
        "dump_date":        c(*_DUMP_COLS, warn=False),
        "oss":              "oss",
    }, index=r.index)


_BUILDERS = {
    ("3g", "ericsson"): _b3g_ericsson, ("3g", "huawei"): _b3g_huawei, ("3g", "nokia"): _b3g_nokia,
    ("4g", "ericsson"): _b4g_ericsson, ("4g", "huawei"): _b4g_huawei, ("4g", "nokia"): _b4g_nokia,
    ("5g", "ericsson"): _b5g_ericsson, ("5g", "huawei"): _b5g_huawei, ("5g", "nokia"): _b5g_nokia,
}


# ═════════════════════════════════════════════════════════════════════════════
#  Download + merge
# ═════════════════════════════════════════════════════════════════════════════
def fetch_csv(url: str, label: str) -> Optional[pd.DataFrame]:
    try:
        r = requests.get(url, timeout=120)
        r.raise_for_status()
        try:
            df = pd.read_csv(io.BytesIO(r.content), dtype=str, encoding="utf-8-sig", low_memory=False)
        except UnicodeDecodeError:
            df = pd.read_csv(io.BytesIO(r.content), dtype=str, encoding="cp1252", low_memory=False)
        df.columns = [str(c).strip() for c in df.columns]
        log.info("✓ %s (%d rows)", label, len(df))
        return df
    except Exception as e:
        log.warning("✗ %s: %s", label, e)
        return None


def load_vendor_data(tech: str, vendors: Optional[Set[str]] = None) -> pd.DataFrame:
    """Download each vendor CSV once, transform it, return all cells (deduplicated by cell_name)."""
    tech_l = tech.lower()
    eff = ({v.lower() for v in vendors if v} if vendors else set()) or ALL_VENDORS

    frames: List[pd.DataFrame] = []
    for vendor in sorted(eff):
        key = VENDOR_KEYS.get(tech_l, {}).get(vendor)
        builder = _BUILDERS.get((tech_l, vendor))
        if not key or not builder:
            continue
        raw = fetch_csv(URLS[key], f"{vendor.title()} {tech.upper()}")
        if raw is None or raw.empty:
            log.warning("Empty/failed CSV for %s/%s", vendor, tech)
            continue
        try:
            built = builder(raw)
        except Exception as exc:
            log.error("Builder %s/%s failed: %s", vendor, tech, exc, exc_info=True)
            continue
        built = built[built["cell_name"].notna()]
        frames.append(built)
        log.info("Loaded %d valid rows from %s/%s", len(built), vendor, tech)

    if not frames:
        log.error("No vendor data loaded for tech=%s", tech)
        return pd.DataFrame()

    combined = pd.concat(frames, ignore_index=True)
    combined = combined.drop_duplicates(subset=["cell_name"], keep="first")
    log.info("load_vendor_data %s: %d unique cells", tech, len(combined))
    return combined


# ═════════════════════════════════════════════════════════════════════════════
#  DB helpers
# ═════════════════════════════════════════════════════════════════════════════
def fetch_current_cells(conn: Connection, table: str, cell_names: List[str]) -> Dict[str, Dict]:
    result: Dict[str, Dict] = {}
    for i in range(0, len(cell_names), 500):
        batch = cell_names[i:i + 500]
        ph = ", ".join(f":n{j}" for j in range(len(batch)))
        params = {f"n{j}": n for j, n in enumerate(batch)}
        rows = conn.execute(text(f"SELECT * FROM {table} WHERE cell_name IN ({ph})"), params).mappings().all()
        result.update({row["cell_name"]: dict(row) for row in rows})
    log.info("fetch_current_cells %s: requested=%d found=%d", table, len(cell_names), len(result))
    return result


def fetch_max_revision_nos(conn: Connection, rev_table: str, cell_ids: List[int]) -> Dict[int, int]:
    result: Dict[int, int] = {}
    for i in range(0, len(cell_ids), 500):
        batch = cell_ids[i:i + 500]
        ph = ", ".join(f":id{j}" for j in range(len(batch)))
        params = {f"id{j}": cid for j, cid in enumerate(batch)}
        rows = conn.execute(text(
            f"SELECT cell_id_ref, COALESCE(MAX(revision_no), 0) FROM {rev_table} "
            f"WHERE cell_id_ref IN ({ph}) GROUP BY cell_id_ref"), params).fetchall()
        result.update({row[0]: row[1] for row in rows})
    return result


def _diff(old: Dict, new: Dict) -> Dict:
    return {k: [old.get(k), new.get(k)] for k in new if _canon(old.get(k)) != _canon(new.get(k))}


# ── revision writer (one generic INSERT per tech) ────────────────────────────
_REV_BASE_COLS = [
    "site_id", "site_name", "cell_name", "mien", "tinh", "phuong_xa",
    "site_name_old", "cell_name_old", "cell_vip", "moran", "lat", "long",
    "vung_phu_song", "vendor", "do_cao_anten", "azimuth", "m_tilt", "e_tilt",
    "total_tilt", "loai_anten",
]
_REV_EXTRA_COLS = {
    "cells_3g": ["rnc_name", "chung_anten", "baseband", "rf", "cell_id", "arfcn", "uarfcn",
                 "lac", "rac", "psc", "ura_id", "mimo", "cell_max_power", "cpich_power",
                 "bbu_name", "cell_status", "dump_date", "oss"],
    "cells_4g": ["chung_anten", "baseband", "rf", "enodeb_id", "cell_id", "earfcn", "tac", "pci",
                 "root_sequence_id", "mimo", "bandwidth", "cell_max_power", "eci",
                 "bbu_name", "cell_status", "dump_date", "oss"],
    "cells_5g": ["baseband", "rf", "gnodeb_id", "cell_id", "tac", "pci", "root_sequence_id", "mimo",
                 "ssb_arfcn", "center_arfcn", "gscn", "bandwidth", "cell_max_power", "nci",
                 "bbu_name", "mu_mimo", "cell_status", "dump_date", "oss"],
}


def _write_rev(conn: Connection, table_name: str, row: Dict, diff: Dict, rev_no: int, note: str) -> None:
    cols = _REV_BASE_COLS + _REV_EXTRA_COLS[table_name]
    p = {c: row.get(c) for c in cols}
    p.update({
        "cell_id_ref":     row["id"],
        "revision_no":     rev_no,
        "changed_by":      SCRIPT_USER_ID,
        "changed_by_name": SCRIPT_USER_NAME,
        "change_source":   CHANGE_SOURCE,
        "change_note":     note,
        "changed_fields":  json.dumps(diff, ensure_ascii=False, default=str),
        "created_at":      datetime.now(timezone.utc),
    })
    all_cols = ["cell_id_ref", "revision_no", "changed_by", "changed_by_name", "change_source",
                "change_note", "changed_fields", "created_at"] + cols
    sql = (f"INSERT INTO {REVISION_TABLES[table_name]} ({', '.join(all_cols)}) "
           f"VALUES ({', '.join(':' + c for c in all_cols)})")
    conn.execute(text(sql), p)


def _apply_one(conn: Connection, table_name: str, p: Dict) -> None:
    if p["kind"] == "full":
        sets = {**p["new_vals"], **p["meta_vals"]}
        clause = ", ".join(f"{c}=:{c}" for c in sets) + ", updated_at=NOW()"
    else:                                   # meta only: no revision, updated_at untouched
        sets = dict(p["meta_vals"])
        clause = ", ".join(f"{c}=:{c}" for c in sets)
    conn.execute(text(f"UPDATE {table_name} SET {clause} WHERE id=:_id"), {**sets, "_id": p["cur"]["id"]})
    if p["kind"] == "full":
        note = f"Đồng bộ tức thì – {len(p['diff'])} trường: {', '.join(p['diff'].keys())}"
        _write_rev(conn, table_name, {**p["cur"], **sets}, p["diff"], p["rev_no"], note)


# ═════════════════════════════════════════════════════════════════════════════
#  Public API
# ═════════════════════════════════════════════════════════════════════════════
def sync_cells(
    engine_or_url,
    table_name: str,
    cell_names: List[str],
    vendors:    Optional[Set[str]] = None,
    source_df:  Optional[pd.DataFrame] = None,
    dry_run:    bool = False,
) -> Dict[str, Any]:
    """
    Sync cells from the vendor CSVs into the DB.
      * diff only the COLUMNS_TO_UPDATE columns -> UPDATE + revision (change_source='script')
      * dump_date / oss are refreshed without creating a revision
      * batches of 100 cells per commit; a failed batch is retried cell-by-cell so one
        bad cell never blocks the others
      * dry_run=True -> compute everything, write nothing
    """
    stats: Dict[str, Any] = {"updated": 0, "skipped": 0, "not_in_db": 0, "not_in_csv": 0,
                             "errors": 0, "meta_only": 0, "error_details": []}
    cell_names = list(dict.fromkeys(n for n in cell_names if n))
    if not cell_names:
        return stats

    tech    = table_name.replace("cells_", "")
    cols    = COLUMNS_TO_UPDATE[table_name]
    rev_tbl = REVISION_TABLES[table_name]

    if source_df is None:
        source_df = load_vendor_data(tech, vendors)

    if not source_df.empty and "cell_name" in source_df.columns:
        filtered   = source_df[source_df["cell_name"].isin(set(cell_names))]
        source_map = filtered.set_index("cell_name").to_dict(orient="index")
    else:
        source_map = {}
    log.info("sync_cells %s: requested=%d in_source=%d", table_name, len(cell_names), len(source_map))

    own_engine = isinstance(engine_or_url, str)
    eng = create_engine(engine_or_url, pool_pre_ping=True) if own_engine else engine_or_url
    try:
        # Phase 1: read
        with eng.connect() as conn:
            current_map = fetch_current_cells(conn, table_name, cell_names)
            rev_no_map  = fetch_max_revision_nos(conn, rev_tbl, [r["id"] for r in current_map.values()])

        # Phase 2: plan (in memory)
        plans: List[Dict[str, Any]] = []
        for name in cell_names:
            cur = current_map.get(name)
            if not cur:
                stats["not_in_db"] += 1
                continue
            src = source_map.get(name)
            if src is None:
                stats["not_in_csv"] += 1
                continue

            eff_cols  = [c for c in cols if src.get(c) != _KEEP]
            new_vals  = {c: _clean(src.get(c)) for c in eff_cols}
            meta_vals = {c: _clean(src.get(c)) for c in META_COLUMNS}
            diff      = _diff({c: cur.get(c) for c in eff_cols}, new_vals)
            meta_changed = any(_canon(cur.get(k)) != _canon(v) for k, v in meta_vals.items())

            if diff:
                rev_no = rev_no_map.get(cur["id"], 0) + 1
                rev_no_map[cur["id"]] = rev_no
                plans.append({"kind": "full", "name": name, "cur": cur, "new_vals": new_vals,
                              "meta_vals": meta_vals, "diff": diff, "rev_no": rev_no})
            elif meta_changed:
                plans.append({"kind": "meta", "name": name, "cur": cur, "meta_vals": meta_vals})
            else:
                stats["skipped"] += 1

        n_full = sum(p["kind"] == "full" for p in plans)
        n_meta = len(plans) - n_full
        log.info("sync_cells %s: %d with changes, %d meta-only, %d unchanged, %d not_in_source",
                 table_name, n_full, n_meta, stats["skipped"], stats["not_in_csv"])

        if dry_run:
            stats.update(updated=n_full, meta_only=n_meta, dry_run=True)
            stats["skipped"] += n_meta
            return stats

        # Phase 3: apply
        def _count(p: Dict) -> None:
            if p["kind"] == "full":
                stats["updated"] += 1
            else:
                stats["meta_only"] += 1
                stats["skipped"] += 1

        BATCH = 100
        for i in range(0, len(plans), BATCH):
            batch = plans[i:i + BATCH]
            try:
                with eng.begin() as conn:
                    for p in batch:
                        _apply_one(conn, table_name, p)
                for p in batch:
                    _count(p)
            except Exception as exc:
                log.warning("Batch %d-%d failed (%s) -> retrying cell by cell", i, i + len(batch) - 1, exc)
                for p in batch:
                    try:
                        with eng.begin() as conn:
                            _apply_one(conn, table_name, p)
                        _count(p)
                    except Exception as exc2:
                        stats["errors"] += 1
                        stats["error_details"].append(f"{p['name']}: {exc2}")
            log.info("Committed batch %d/%d", i // BATCH + 1, (len(plans) + BATCH - 1) // BATCH)

        log.info("sync_cells %s DONE: updated=%d meta_only=%d skipped=%d not_in_csv=%d not_in_db=%d errors=%d",
                 table_name, stats["updated"], stats["meta_only"], stats["skipped"],
                 stats["not_in_csv"], stats["not_in_db"], stats["errors"])
        return stats
    finally:
        if own_engine:
            eng.dispose()
PYEOF

# ── 3. Daily/manual scripts ──────────────────────────────────────────────────
say "3/7  Writing update_cells_with_revision.py (backend + root)"
cat > "$ROOT/backend/update_cells_with_revision.py" <<'PYEOF'
"""
update_cells_with_revision.py  -  daily / manual bulk sync (NOT part of the web app).

    python update_cells_with_revision.py                 # all techs, writes to DB
    python update_cells_with_revision.py --dry-run       # show what WOULD change, write nothing
    python update_cells_with_revision.py --tech 4g,5g    # only some technologies

All transformation rules live in cell_sync_core.py (shared with the web "sync" button),
so this script and the web app always behave identically.
DB url: env DATABASE_URL, else the default below.
"""
import argparse
import logging
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from datetime import datetime
from sqlalchemy import create_engine, text
import cell_sync_core as core

DATABASE_URL = os.environ.get("DATABASE_URL",
                              "postgresql://sitelink:sitelink_pass@localhost:5432/sitelink_db")
TECHS = {"3g": "cells_3g", "4g": "cells_4g", "5g": "cells_5g"}


def run_bulk(eng, table: str, tech: str, dry_run: bool) -> int:
    with eng.connect() as conn:
        names = [r["cell_name"] for r in
                 conn.execute(text(f"SELECT cell_name FROM {table}")).mappings().all() if r["cell_name"]]
    if not names:
        print(f"\n--- {tech.upper()}: no cells in DB ---")
        return 0

    print(f"\n--- {tech.upper()} ({len(names)} cells in DB) ---")
    print(f"   Downloading {tech.upper()} vendor CSVs...")
    source_df = core.load_vendor_data(tech, vendors=None)
    if source_df.empty:
        print("   ❌ No source data downloaded - skipped (nothing written).")
        return 1
    print(f"   Loaded {len(source_df)} source rows")

    s = core.sync_cells(eng, table, names, vendors=None, source_df=source_df, dry_run=dry_run)
    tag = "WOULD update" if dry_run else "updated"
    print(f"   {tag}={s['updated']}  meta_only(dump_date/oss)={s['meta_only']}  "
          f"unchanged_total={s['skipped']}  not_in_csv={s['not_in_csv']}  "
          f"not_in_db={s['not_in_db']}  errors={s['errors']}")
    for d in s.get("error_details", [])[:20]:
        print(f"   ❌ {d}")
    return 1 if s["errors"] else 0


def main() -> int:
    ap = argparse.ArgumentParser(description="SiteLink daily cell sync")
    ap.add_argument("--dry-run", action="store_true", help="compute only, write nothing")
    ap.add_argument("--tech", default="3g,4g,5g", help="comma list, e.g. 4g,5g")
    args = ap.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    print("=" * 60)
    print(f"SiteLink Cell Sync{' (DRY RUN)' if args.dry_run else ''} - {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("=" * 60)

    eng = create_engine(DATABASE_URL, pool_pre_ping=True)
    rc = 0
    try:
        for tech in [t.strip().lower() for t in args.tech.split(",") if t.strip()]:
            if tech not in TECHS:
                print(f"unknown tech '{tech}' (use 3g,4g,5g)")
                rc = 1
                continue
            rc |= run_bulk(eng, TECHS[tech], tech, args.dry_run)
    finally:
        eng.dispose()
    print("\n✅ Done." if rc == 0 else "\n⚠️ Finished with problems (see above).")
    return rc


if __name__ == "__main__":
    sys.exit(main())
PYEOF

cat > "$ROOT/update_cells_with_revision.py" <<'PYEOF'
"""
update_cells_with_revision.py (project root) - thin wrapper.

The real logic lives in backend/update_cells_with_revision.py + backend/cell_sync_core.py
so the manual daily run and the web app can never drift apart.

    python update_cells_with_revision.py [--dry-run] [--tech 3g,4g,5g]
"""
import os
import runpy
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.join(HERE, "backend")
sys.path.insert(0, BACKEND)
runpy.run_path(os.path.join(BACKEND, "update_cells_with_revision.py"), run_name="__main__")
PYEOF

# ── 4+5. Patch models / schemas / revision / frontend ───────────────────────
say "4-5/7  Patching backend models, schemas, revision API and frontend"
PATCH_RC=0
python3 - "$ROOT" <<'PYEOF' || PATCH_RC=$?
import re, sys
from pathlib import Path

ROOT = Path(sys.argv[1])
problems = []


def patch(rel, pattern, repl, expect=1, marker=None, optional=False):
    p = ROOT / rel
    if not p.exists():
        problems.append(f"{rel}: file not found")
        return
    s = p.read_text(encoding="utf-8")
    if marker and marker in s:
        print(f"  =  {rel}  (already patched)")
        return
    new, n = re.subn(pattern, repl, s)
    if n == 0 and optional:
        print(f"  =  {rel}  (nothing to change)")
        return
    if n != expect:
        problems.append(f"{rel}: expected {expect} match(es), found {n}  for /{pattern[:60]}/")
        return
    p.write_text(new, encoding="utf-8")
    print(f"  ✔  {rel}  ({n} change{'s' if n > 1 else ''})")


# --- backend models: 2 new columns (Baseband column stays in the DB/model) ---
COL = r"(\n    cell_status\s*=\s*Column\(String\(100\)\)[^\n]*)"
ADD = r"\g<1>\n    dump_date      = Column(String(50), nullable=True)   # data dump date\n    oss            = Column(String(50), nullable=True)   # OSS source"
for g in ("3g", "4g", "5g"):
    patch(f"backend/app/models/cell_{g}.py", COL, ADD, 1, marker="dump_date")
patch("backend/app/models/cell_revision.py", COL, ADD, 3, marker="dump_date")

# --- schemas (CellBase + CellUpdate) ---
patch("backend/app/schemas/cell.py",
      r"(\n    cell_max_power:\s*Optional\[str\]\s*=\s*None[^\n]*)",
      r"\g<1>\n    dump_date:      Optional[str]   = None\n    oss:            Optional[str]   = None",
      2, marker="dump_date")

# --- revision service: store dump_date/oss in every cell revision row ---
patch("backend/app/services/revision.py",
      r"(cell_status=cell\.cell_status,\n)(\s+)(changed_fields=)",
      r"\g<1>\g<2>dump_date=cell.dump_date, oss=cell.oss,\n\g<2>\g<3>",
      3, marker="dump_date=cell.dump_date")

# --- revision API: expose them ---
patch("backend/app/api/routes/revision.py",
      r'(\n\s+)("cell_status":\s*r\.cell_status,)',
      r'\g<1>\g<2>\g<1>"dump_date":      r.dump_date,\g<1>"oss":            r.oss,',
      3, marker="r.dump_date")

# --- frontend types ---
patch("frontend/src/types/index.ts",
      r"(\n  cell_max_power\?: string)",
      r"\g<1>\n  dump_date?: string\n  oss?: string",
      1, marker="dump_date")
patch("frontend/src/api/revision.ts", r"change_source: 'form' \| 'excel'",
      lambda m: "change_source: 'form' | 'excel' | 'script'", 2, marker="'script'")
patch("frontend/src/api/revision.ts", r"azimuth\?: number", lambda m: "azimuth?: string", 1, optional=True)

# --- frontend cell pages: hide Baseband, add 'Ngày dữ liệu dump' + OSS ---
NEW_COLS = ("{ title: 'Cell status (at dump time)', dataIndex: 'cell_status', width: 190 },\n"
            "    { title: 'Ngày dữ liệu dump', dataIndex: 'dump_date', width: 160 },\n"
            "    { title: 'OSS', dataIndex: 'oss', width: 90 },")
for t in ("3G", "4G", "5G"):
    f = f"frontend/src/pages/cells/Cells{t}Page.tsx"
    patch(f, r"[ \t]*\{ title: 'Baseband'[^\n]*\},[ \t]*\n", "", optional=True)
    patch(f, r'[ \t]*<Col span=\{8\}><Form\.Item name="baseband" label="Baseband"><Input /></Form\.Item></Col>\n',
          "", optional=True)
    patch(f, r"\{ title: 'Cell status',\s*dataIndex: 'cell_status',\s*width: 140 \},",
          lambda m: NEW_COLS, 1, marker="dump_date")

# --- frontend revision page ---
f = "frontend/src/pages/revision/RevisionPage.tsx"
patch(f, r"[ \t]*\{ title: 'Baseband', key: 'baseband',[^\n]*\n[ \t]*render:[^\n]*\},[ \t]*\n", "", optional=True)
patch(f, r"(\{ title: 'Cell status', key: 'cell_status', width: 140,\n[ \t]*render:[^\n]*\},)",
      r"\g<1>\n    { title: 'Ngày dữ liệu dump', key: 'dump_date', width: 160,\n"
      r"      render: (_: unknown, r: CellRevisionBase) => String(r['dump_date'] ?? '-') },\n"
      r"    { title: 'OSS', key: 'oss', width: 90,\n"
      r"      render: (_: unknown, r: CellRevisionBase) => String(r['oss'] ?? '-') },",
      1, marker="dump_date")

if problems:
    print("\n  PROBLEMS (these files were NOT changed - patch them by hand):")
    for p in problems:
        print("   -", p)
    sys.exit(2)
PYEOF
[ "$PATCH_RC" -eq 0 ] || warn "Some patches did not apply (see PROBLEMS above)."

# ── 6. DB migration ──────────────────────────────────────────────────────────
say "6/7  Database migration (dump_date + oss on 6 tables)"
if [ "$MIGRATE" -eq 0 ]; then
  echo "skipped (--no-migrate). Run manually:"
  for t in cells_3g cells_4g cells_5g cell_3g_revisions cell_4g_revisions cell_5g_revisions; do
    echo "  ALTER TABLE $t ADD COLUMN IF NOT EXISTS dump_date VARCHAR(50), ADD COLUMN IF NOT EXISTS oss VARCHAR(50);"
  done
elif [ -z "$APP_PY" ]; then
  warn "no python with sqlalchemy -> migration skipped. Re-run with PYTHON=/path/to/venv/python or run the SQL above by hand."
else
  DB_URL="${DATABASE_URL:-}"
  if [ -z "$DB_URL" ]; then
    DB_URL="$(cd "$ROOT/backend" && "$APP_PY" -c 'from app.core.config import settings; print(settings.DATABASE_URL)' 2>/dev/null || true)"
  fi
  [ -n "$DB_URL" ] || DB_URL="postgresql://sitelink:sitelink_pass@localhost:5432/sitelink_db"
  DATABASE_URL="$DB_URL" "$APP_PY" - <<'PYEOF' || warn "Migration failed - apply the ALTER TABLE statements by hand (see docs above)."
import os
from sqlalchemy import create_engine, text
eng = create_engine(os.environ["DATABASE_URL"])
tables = ["cells_3g", "cells_4g", "cells_5g",
          "cell_3g_revisions", "cell_4g_revisions", "cell_5g_revisions"]
with eng.begin() as c:
    for t in tables:
        c.execute(text(f"ALTER TABLE {t} ADD COLUMN IF NOT EXISTS dump_date VARCHAR(50)"))
        c.execute(text(f"ALTER TABLE {t} ADD COLUMN IF NOT EXISTS oss VARCHAR(50)"))
        print(f"  ✔ {t}")
eng.dispose()
PYEOF
fi

# ── 7. Compile + self-test ───────────────────────────────────────────────────
say "7/7  Compile + self-test"
COMPILE_RC=0
for f in backend/cell_sync_core.py backend/update_cells_with_revision.py update_cells_with_revision.py \
         backend/app/models/cell_3g.py backend/app/models/cell_4g.py backend/app/models/cell_5g.py \
         backend/app/models/cell_revision.py backend/app/schemas/cell.py \
         backend/app/services/revision.py backend/app/api/routes/revision.py; do
  [ -f "$ROOT/$f" ] || continue
  python3 -m py_compile "$ROOT/$f" 2>/dev/null && echo "  ✔ compiles: $f" || { echo "  ✘ SYNTAX ERROR: $f"; COMPILE_RC=1; }
done

TEST_RC=0
if [ "$RUN_TESTS" -eq 1 ] && [ -n "$APP_PY" ]; then
  (cd "$ROOT/backend" && "$APP_PY" - <<'PYEOF') || TEST_RC=$?
import logging, sys
import pandas as pd
logging.disable(logging.CRITICAL)
import cell_sync_core as core

B, fails, n = core._BUILDERS, [], 0
D = "Ngày cập nhật"

def run(tech, vendor, d):
    df = B[(tech, vendor)](pd.DataFrame([d]))
    return {k: (None if (v is None or (isinstance(v, float) and v != v)) else v)
            for k, v in df.iloc[0].to_dict().items()}

def chk(label, got, exp):
    global n
    n += 1
    if got != exp:
        fails.append(f"{label}: got {got!r}, expected {exp!r}")

# ---- 3G ----
r = run("3g", "ericsson", {"rnc_UtranCellId": "LDGBLO07BM3GB", "rnc_cId": "42428.0", "rnc_uarfcnDl": "10612.0",
        "rnc_primaryScrCode": "254", "rnc_lac": "64411", "rnc_rac": "44", "rnc_ura_id": "64404.0",
        "primaryCpichPower": "360", "maximumTransmissionPower": "460", "hw_productName": "RRUS 01 B1",
        "node_name": "LDGBLO07", "rnc_adminState": "UNLOCKED", D: "2026-09-23"})
chk("3G E cell_id", r["cell_id"], "42428"); chk("3G E uarfcn", r["uarfcn"], "10612")
chk("3G E ura", r["ura_id"], "64404"); chk("3G E cpich", r["cpich_power"], "36.0")
chk("3G E pmax", r["cell_max_power"], "46.0"); chk("3G E mimo keep", r["mimo"], core._KEEP)
chk("3G E oss", r["oss"], "ENM"); chk("3G E dump", r["dump_date"], "2026-09-23")

r = run("3g", "huawei", {"CELLNAME": "HNITPG26CM3EA", "CELLID": "29781.0", "UARFCN DOWNLINK": "10562",
        "PSCRAMBCODE": "8.0", "LAC": "10021", "RAC": "117", "URAID": "10021", "PCPICHPOWER (0.1dBm)": "330",
        "RNC UCELL MAXTXPOWER": "430", "TXRXMODE": None, "RRU ManufacturerData": "RRU3971a,xx,yy",
        "NEname": "HNITPG26", "BLKSTATUS": "UNBLOCKED"})
chk("3G H cell_id", r["cell_id"], "29781"); chk("3G H psc", r["psc"], "8"); chk("3G H ura", r["ura_id"], "10021")
chk("3G H cpich", r["cpich_power"], "33.0"); chk("3G H rf", r["rf"], "RRU3971a")
chk("3G H mimo keep", r["mimo"], core._KEEP); chk("3G H oss", r["oss"], "OSS"); chk("3G H dump empty", r["dump_date"], None)

r = run("3g", "nokia", {"name": "DNGVAN13DM3GA", "CId": "15771", "UARFCN": "10612", "PriScrCode": "467",
        "LAC": "34903", "RAC": "104", "URAId": "104", "PtxPrimaryCPICH": "330", "PtxCellMax": "430",
        "WBTS_name": "DNGVAN13", "AdminCellState": "Unlocked"})
chk("3G N ura", r["ura_id"], "104"); chk("3G N cpich", r["cpich_power"], "33.0")
chk("3G N pmax", r["cell_max_power"], "43.0"); chk("3G N oss", r["oss"], "oss")

# ---- 4G ----
r = run("4g", "ericsson", {"eUtranCellFDDId": "TNICGC80CM4CA", "eNBId": "601230", "cellId": "11", "earfcndl": "1501",
        "tac": "62621", "physicalLayerCellId": "266", "rachRootSequence": "264", "noOfUsedTxAntennas": "4",
        "dlChannelBandwidth": "20000", "maximumTransmissionPower": "520", "hw_productName": "Radio 4451HP",
        "node": "TNICGC80UL", "administrativeState": "UNLOCKED"})
chk("4G E enb", r["enodeb_id"], "601230"); chk("4G E cell_id", r["cell_id"], "601230-11")
chk("4G E mimo", r["mimo"], "4T4R"); chk("4G E bw", r["bandwidth"], "20MHz")
chk("4G E pmax", r["cell_max_power"], "52.0"); chk("4G E eci", r["eci"], "153914891")

r = run("4g", "huawei", {"CELLNAME": "BNHBDG01DM4CA", "ENODEBID": "310105", "CELLID": "11", "DLEARFCN": "1501",
        "TAC": "57201", "Physical cell ID": "264", "Root sequence index": "20", "TXRXMODE": "2T2R",
        "DLBANDWIDTH": "CELL_BW_N100", "Maximum transmit power (0.1dBm)": "460",
        "RRU ManufacturerData": "RRU3971a,WD5MERUMG30A", "NE": "BNHBDG01_4G", "Cell admin state": "CELL_UNBLOCK"})
chk("4G H cell_id", r["cell_id"], "310105-11"); chk("4G H mimo", r["mimo"], "2T2R")
chk("4G H bw", r["bandwidth"], "20MHz"); chk("4G H pmax", r["cell_max_power"], "46.0")
chk("4G H eci", r["eci"], "79386891"); chk("4G H rf", r["rf"], "RRU3971a")
chk("4G H bad bw -> empty", run("4g", "huawei", {"CELLNAME": "x", "DLBANDWIDTH": "CELL_BW_X"})["bandwidth"], None)

r = run("4g", "nokia", {"distName": "PLMN-PLMN/MRBTS-190147/LNBTS-190147/LNCEL-11", "name": "DBNXDG02BM4CA",
        "cellName": "DBNXDG02BM4CA", "tac": "18012", "phyCellId": "376", "earfcnDL": "1501", "rootSeqIndex": "20",
        "Cell nTX": "2", "Cell nRX": "2", "dlChBw": "200", "pMax_0_1dBm": "430", "RRU productName": "AHEB",
        "MRBTS_btsname": "DBNXDG02", "blockingState": "Unblocked"})
chk("4G N enb", r["enodeb_id"], "190147"); chk("4G N cell_id", r["cell_id"], "190147-11")
chk("4G N mimo", r["mimo"], "2T2R"); chk("4G N bw", r["bandwidth"], "20MHz")
chk("4G N pmax", r["cell_max_power"], "43.0"); chk("4G N eci", r["eci"], "48677643")

# ---- 5G ----
r = run("5g", "ericsson", {"NRCellCUId": "TNIDMC36CM5LB", "gNodeBId": "150343", "NRCellCU_LocalCellId": "412",
        "ARFCN_DL_Cell": "523470", "ARFCN_DL_SC": "528996", "PCI": "766", "TAC": "62840", "rachRootSequence": "357",
        "NoOfUsedTxAntennas": "32", "NoOfUsedRxAntennas": "32", "ConfiguredMaxTxPower": "320000",
        "NRCellCU_nCI": "2463232412", "BSChannelBwDL": "90", "RF_ProductNames": "AIR 3265 B41",
        "Node": "TNIDMC36N", "AdministrativeState_SC": "UNLOCKED"})
chk("5G E gnb", r["gnodeb_id"], "150343"); chk("5G E cell_id", r["cell_id"], "150343-412")
chk("5G E mimo", r["mimo"], "32T32R"); chk("5G E pmax", r["cell_max_power"], "55.1")
chk("5G E gscn (derived)", r["gscn"], "6543"); chk("5G E bw", r["bandwidth"], "90")
chk("5G E nci", r["nci"], "2463232412")
chk("5G E mumimo", run("5g", "ericsson", {"NRCellCUId": "x", "dlMaxMuMimoLayers": "16", "ulMaxMuMimoLayers": "4"})["mu_mimo"], "16DL4UL")

r = run("5g", "huawei", {"CELLNAME": "TNNBKN04DM5SA", "GNBID": "872188", "GNBIDLENGTH": "24", "CELLID": "71",
        "SSB-ARFCN": "656544", "DLNARFCN": "656666", "SSB GSCN": "8088", "Physical cell ID": "331", "TAC": "57100",
        "Logical Root sequence index": "530", "TXRXMODE": "32T32R", "MAXTRANSMITPOWER": "400",
        "DLBANDWIDTH": "CELL_BW_100M", "RRU ManufacturerData": "AAU5336v,WD7MQ", "NE": "BCN_X",
        "Cell admin state": "CELL_UNBLOCK"})
chk("5G H cell_id", r["cell_id"], "872188-71"); chk("5G H nci", r["nci"], "3572482119")
chk("5G H mimo", r["mimo"], "32T32R"); chk("5G H pmax", r["cell_max_power"], "55.1")
chk("5G H bw", r["bandwidth"], "100"); chk("5G H gscn", r["gscn"], "8088"); chk("5G H rf", r["rf"], "AAU5336v")
r = run("5g", "huawei", {"CELLNAME": "x", "TXRXMODE": "abc", "MAXTRANSMITPOWER": "400"})
chk("5G H bad mimo -> mimo empty", r["mimo"], None); chk("5G H bad mimo -> power empty", r["cell_max_power"], None)

r = run("5g", "nokia", {"distName": "PLMN-PLMN/MRBTS-1050254/NRBTS-1050254/NRCELL-51", "NRCELL_cellName": "HDD018M5SA",
        "physCellId": "168", "nrCellIdentity": "4301840435", "prachRootSequenceIndex": "42", "nrCellType": "16DL4UL",
        "mMimoAntArrayMode": "Full 64TRX Array (4x8x2)", "chBw": "100MHz", "pMax_0_1dBm": "369",
        "nrarfcn": "656666", "gscnOrSsPbchArfcn": "8088", "RRU productName": "AVQG",
        "MRBTS_btsname": "HDD018NR77", "administrativeState": "Unlocked"})
chk("5G N gnb", r["gnodeb_id"], "1050254"); chk("5G N cell_id", r["cell_id"], "1050254-51")
chk("5G N mimo", r["mimo"], "64T64R"); chk("5G N pmax", r["cell_max_power"], "55.0")
chk("5G N bw", r["bandwidth"], "100"); chk("5G N mu", r["mu_mimo"], "16DL4UL")
chk("5G N nci", r["nci"], "4301840435"); chk("5G N tac (col missing)", r["tac"], None)

# ---- helpers ----
chk("gscn 656544", core._gscn_from_arfcn("656544"), "8088")
chk("diff garbage '<NA>' is detected", bool(core._diff({"pci": "<NA>"}, {"pci": None})), True)
chk("diff '46.0' == '46.0'", core._diff({"x": "46.0"}, {"x": "46.0"}), {})
chk("diff '42428.0' -> '42428'", bool(core._diff({"x": "42428.0"}, {"x": "42428"})), True)

print(f"self-test: {n - len(fails)}/{n} checks passed")
for f in fails:
    print("  ✘", f)
sys.exit(1 if fails else 0)
PYEOF
elif [ "$RUN_TESTS" -eq 1 ]; then
  warn "self-test skipped (no python with pandas/sqlalchemy/requests found)."
fi

# ── Summary ──────────────────────────────────────────────────────────────────
say "Summary"
[ "$PATCH_RC"   -eq 0 ] && echo "  patches : OK"        || echo "  patches : SOME FAILED (see above)"
[ "$COMPILE_RC" -eq 0 ] && echo "  compile : OK"        || echo "  compile : ERRORS"
[ "$TEST_RC"    -eq 0 ] && echo "  self-test: OK"       || echo "  self-test: FAILED"
cat <<EOF

Next steps
  1. Restart the backend (uvicorn/gunicorn) so the new models + sync rules load.
  2. Dry run first - the first real run rewrites most cells (".0" removal, new formats):
        cd "$ROOT" && python update_cells_with_revision.py --dry-run
  3. Then the real run:   python update_cells_with_revision.py
  4. Frontend: rebuild / let Vite hot-reload.
  Roll back anything:  cp -a "$BK"/. "$ROOT"/
EOF
[ "$PATCH_RC" -eq 0 ] && [ "$COMPILE_RC" -eq 0 ] && [ "$TEST_RC" -eq 0 ]
