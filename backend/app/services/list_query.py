"""
services/list_query.py

Server-side helpers for the list screens:
  * apply_column_filters : Excel-style per-column filters (JSON in ?filters=)
  * apply_sort           : whitelisted, blank-last, numeric-aware sorting
  * register_listing_routes : adds GET /ids and GET /distinct/{column}

Column filter JSON:  {"tinh": {"in": [...]}, "vendor": {"not_in": [...]},
                      "cell_name": {"contains": "abc"}}
The three keys are ANDed. The value "__SL_EMPTY__" stands for blank/NULL.
"""
import json
import unicodedata
from typing import Dict, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import (
    Boolean, Numeric, String, case, cast, false, func, literal_column,
    not_, or_,
)
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.utils.deps import get_current_user

EMPTY = "__SL_EMPTY__"
_NUM_RE = r"^-?[0-9]+([.][0-9]+)?$"

# ── accent folding (works without the unaccent extension) ────────────────────
_VN = {
    "a": "àáạảãâầấậẩẫăằắặẳẵ",
    "e": "èéẹẻẽêềếệểễ",
    "i": "ìíịỉĩ",
    "o": "òóọỏõôồốộổỗơờớợởỡ",
    "u": "ùúụủũưừứựửữ",
    "y": "ỳýỵỷỹ",
    "d": "đ",
}
_FROM = "".join(v + v.upper() for v in _VN.values())
_TO = "".join(k * (2 * len(v)) for k, v in _VN.items())
_TABLE = str.maketrans(_FROM, _TO)


def _fold_py(s: str) -> str:
    return unicodedata.normalize("NFC", s).translate(_TABLE).lower()


def _fold_sql(col):
    return func.translate(func.lower(cast(col, String)), _FROM, _TO, type_=String)


# ── column helpers ───────────────────────────────────────────────────────────
def _check(model, name: str) -> None:
    if name not in model.__table__.columns:
        raise HTTPException(status_code=400, detail=f"Unknown column '{name}'")


def _kind(model, name: str) -> str:
    t = model.__table__.columns[name].type
    if isinstance(t, Boolean):
        return "bool"
    if isinstance(t, String):          # String and Text
        return "str"
    return "num"


def _norm(model, name: str):
    """Expression used for filtering / grouping / sorting (blank -> NULL)."""
    col = getattr(model, name)
    k = _kind(model, name)
    if k == "str":
        return func.nullif(func.trim(col), literal_column("''"), type_=String)
    if k == "bool":
        return func.coalesce(col, false())
    return col


def _coerce(kind: str, vals):
    if kind == "bool":
        return [v.lower() in ("true", "1", "yes") for v in vals]
    if kind == "num":
        out = []
        for v in vals:
            try:
                out.append(float(v))
            except ValueError:
                pass
        return out
    return list(vals)


def _member(model, name: str, vals):
    """Boolean expression that is never NULL."""
    expr = _norm(model, name)
    real = [v for v in vals if v != EMPTY]
    conds = []
    real = _coerce(_kind(model, name), real)
    if real:
        conds.append(func.coalesce(expr.in_(real), false()))
    if EMPTY in vals and _kind(model, name) != "bool":
        conds.append(expr.is_(None))
    return or_(*conds) if conds else false()


# ── public: filters ──────────────────────────────────────────────────────────
def parse_filters(raw: Optional[str]) -> Dict[str, dict]:
    if not raw:
        return {}
    try:
        data = json.loads(raw)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid 'filters' JSON")
    if not isinstance(data, dict):
        raise HTTPException(status_code=400, detail="'filters' must be an object")
    return data


def apply_column_filters(q, model, raw: Optional[str], exclude: Optional[str] = None):
    for name, spec in parse_filters(raw).items():
        if name == exclude or not isinstance(spec, dict):
            continue
        _check(model, name)
        contains = spec.get("contains")
        if isinstance(contains, str) and contains.strip():
            q = q.filter(_fold_sql(getattr(model, name)).contains(
                _fold_py(contains.strip()), autoescape=True))
        if isinstance(spec.get("in"), list):
            q = q.filter(_member(model, name, [str(x) for x in spec["in"]]))
        if isinstance(spec.get("not_in"), list) and spec["not_in"]:
            q = q.filter(not_(_member(model, name, [str(x) for x in spec["not_in"]])))
    return q


# ── public: sorting ──────────────────────────────────────────────────────────
def apply_sort(q, model, sort_by: Optional[str], sort_dir: str = "asc"):
    if not sort_by:
        return q.order_by(model.id.desc())          # newest first
    _check(model, sort_by)
    desc_ = str(sort_dir).lower() == "desc"
    d = (lambda e: e.desc()) if desc_ else (lambda e: e.asc())
    expr = _norm(model, sort_by)
    if _kind(model, sort_by) == "str":
        is_num = expr.op("~")(_NUM_RE)
        keys = [
            case((expr.is_(None), 1), else_=0).asc(),     # blanks always last
            d(case((is_num, 0), else_=1)),                # numbers first (asc)
            d(case((is_num, cast(expr, Numeric)))),       # numeric order
            d(expr),                                      # text order
        ]
    else:
        keys = [d(expr).nulls_last()]
    keys.append(model.id.asc())                           # stable paging
    return q.order_by(*keys)


# ── top-bar filters (same semantics as the list endpoints) ───────────────────
def _base_query(db: Session, model, kind: str, request: Request):
    qp = request.query_params

    def many(name):
        return [v for v in qp.getlist(name) if v != ""]

    q = db.query(model)
    search = qp.get("search")
    if kind == "cell":
        if search:
            q = q.filter(model.cell_name.ilike(f"%{search}%")
                         | model.site_name.ilike(f"%{search}%"))
        if qp.get("cell_name_old"):
            q = q.filter(model.cell_name_old.ilike(f"%{qp.get('cell_name_old')}%"))
        names = ("mien", "tinh", "phuong_xa", "vendor", "mimo", "vung_phu_song")
    else:
        if search:
            q = q.filter(model.site_name.ilike(f"%{search}%"))
        if qp.get("site_name_cu"):
            q = q.filter(model.site_name_cu.ilike(f"%{qp.get('site_name_cu')}%"))
        for n in ("tram_3g", "tram_4g", "tram_5g"):
            v = qp.get(n)
            if v is not None:
                q = q.filter(getattr(model, n) == (v.lower() in ("true", "1", "yes")))
        names = ("mien", "tinh", "phuong_xa")
    for n in names:
        vals = many(n)
        if vals:
            q = q.filter(getattr(model, n).in_(vals))
    return q


# ── public: extra routes ─────────────────────────────────────────────────────
def register_listing_routes(router: APIRouter, model, kind: str) -> None:
    """Call right after `router = APIRouter()` so these win over /{id}."""

    @router.get("/ids")
    def list_ids(
        request: Request,
        filters: Optional[str] = Query(None),
        db: Session = Depends(get_db),
        _=Depends(get_current_user),
    ):
        q = _base_query(db, model, kind, request)
        q = apply_column_filters(q, model, filters)
        ids = [r[0] for r in q.with_entities(model.id).order_by(model.id).all()]
        return {"ids": ids, "total": len(ids)}

    @router.get("/distinct/{column}")
    def distinct_values(
        column: str,
        request: Request,
        filters: Optional[str] = Query(None),
        q: Optional[str] = Query(None),
        limit: int = Query(200, ge=1, le=1000),
        db: Session = Depends(get_db),
        _=Depends(get_current_user),
    ):
        _check(model, column)
        expr = _norm(model, column)
        base = _base_query(db, model, kind, request)
        # like Excel: this column's own filter is ignored for its own list
        base = apply_column_filters(base, model, filters, exclude=column)
        if q and q.strip():
            base = base.filter(_fold_sql(getattr(model, column)).contains(
                _fold_py(q.strip()), autoescape=True))
        grouped = (base.with_entities(expr.label("v"), func.count().label("n"))
                       .group_by(expr))
        rows = grouped.order_by(expr.asc().nulls_last()).limit(limit).all()
        total = (db.query(func.count())
                   .select_from(grouped.order_by(None).subquery()).scalar() or 0)
        return {
            "values": [{"value": r.v, "count": r.n} for r in rows],
            "total_distinct": total,
        }
