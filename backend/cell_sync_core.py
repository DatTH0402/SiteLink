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
DBM_DECIMALS     = 2            # 33.0 / 34.7 / 55.1
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
        "dump_date":      datetime.now().strftime("%Y-%m-%d"),
        "oss":            c("ENM"),
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
        "dump_date":      datetime.now().strftime("%Y-%m-%d"),
        "oss":            c("OSS"),
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
        "dump_date":      datetime.now().strftime("%Y-%m-%d"),
        "oss":            c("oss"),
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
        "dump_date":        datetime.now().strftime("%Y-%m-%d"),
        "oss":              c("ENM"),
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
        "dump_date":        datetime.now().strftime("%Y-%m-%d"),
        "oss":              c("OSS"),
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
        "dump_date":        datetime.now().strftime("%Y-%m-%d"),
        "oss":              c("oss"),
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
        "dump_date":        datetime.now().strftime("%Y-%m-%d"),
        "oss":              c("ENM"),
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
        "dump_date":        datetime.now().strftime("%Y-%m-%d"),
        "oss":              c("OSS"),
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
        "dump_date":        datetime.now().strftime("%Y-%m-%d"),
        "oss":              c("oss"),
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