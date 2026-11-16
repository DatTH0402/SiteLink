"""
revision.py  –  Revision history API (server-side listing + CSV export).

Per layer (sites | cells-3g | cells-4g | cells-5g):
  GET  /<layer>                  paged list  (skip, limit, sort_by, sort_dir, filters + top-bar params)
                                 total in the X-Total-Count header
  GET  /<layer>/ids              ids of every row matching top-bar + column filters
  GET  /<layer>/distinct/{col}   values + counts for the Excel-style header filter
  POST /<layer>/export-csv       CSV of the selected ids, or of everything the filters match
  GET  /sites/{site_id}          revisions of one site (kept for compatibility)

Top-bar params
  sites : site_id, site_name (current OR old name), tinh
  cells : cell_id (=cell_id_ref), site_name (current OR old), cell_name (current OR old),
          subcell_id, tinh

Column filters use the same JSON as the Site module (app.services.list_query):
  {"tinh": {"in": [...]}, "vendor": {"not_in": [...]}, "cell_name": {"contains": "abc"}}
Two virtual columns are handled here because they are not real table columns:
  created_at  -> filtered by DAY (timezone REVISION_TZ, default Asia/Ho_Chi_Minh)
  diff_count  -> number of keys in changed_fields
"""
import csv
import io
import json
import os
import threading
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, Query, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy import Integer, false, func, literal_column, not_, or_
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.site_revision import SiteRevision
from app.models.cell_revision import Cell3GRevision, Cell4GRevision, Cell5GRevision
from app.services.list_query import (
    EMPTY, apply_column_filters, apply_sort, parse_filters,
    _check, _fold_py, _fold_sql, _norm,
)
from app.utils.deps import get_current_user

router = APIRouter()

_TZ_NAME = os.environ.get("REVISION_TZ", "Asia/Ho_Chi_Minh")
try:
    from zoneinfo import ZoneInfo
    _TZ = ZoneInfo(_TZ_NAME)
except Exception:                      # tzdata missing in the image -> UTC+7
    _TZ = timezone(timedelta(hours=7))

_EXPORT_SLOTS = threading.BoundedSemaphore(
    int(os.environ.get("EXPORT_MAX_CONCURRENT", "3")))
_EXPOSE = "X-Row-Count, Content-Disposition"
_RESERVED = {"skip", "limit", "sort_by", "sort_dir", "filters", "q", "token"}
VIRTUAL = ("created_at", "diff_count")


# ── generic helpers ───────────────────────────────────────────────────────────
def _changed(r) -> dict:
    cf = getattr(r, "changed_fields", None)
    if not cf:
        return {}
    try:
        d = json.loads(cf)
    except ValueError:
        return {}
    return d if isinstance(d, dict) else {}


def _row(r) -> dict:
    """Every column of the revision row + parsed diff (new columns appear automatically)."""
    d = {c.name: getattr(r, c.name) for c in r.__table__.columns}
    d["changed_fields"] = _changed(r)
    d["changed_by_name"] = d.get("changed_by_name") or ""
    ca = d.get("created_at")
    d["created_at"] = ca.isoformat() if ca else None
    return d


def _first(params, name):
    v = params.get(name)
    if isinstance(v, (list, tuple)):
        v = v[0] if v else None
    return None if v is None or v == "" else v


def _many(params, name):
    v = params.get(name)
    if v is None:
        return []
    if not isinstance(v, (list, tuple)):
        v = [v]
    return [str(x) for x in v if x is not None and x != ""]


def _req_params(request: Request) -> Dict[str, list]:
    qp = request.query_params
    return {k: qp.getlist(k) for k in qp.keys() if k not in _RESERVED}


# ── virtual columns ───────────────────────────────────────────────────────────
def _virtual_expr(model, name: str):
    if name == "created_at":
        return func.to_char(func.timezone(_TZ_NAME, model.created_at), "YYYY-MM-DD")
    col = f'"{model.__tablename__}".changed_fields'          # diff_count
    return literal_column(
        f"(CASE WHEN {col} IS NULL OR {col} !~ '^[[:space:]]*[{{]' THEN 0 "
        f"ELSE (SELECT count(*) FROM json_object_keys({col}::json)) END)",
        type_=Integer,
    )


def _virtual_filter(q, expr, is_int: bool, spec: dict):
    contains = spec.get("contains")
    if isinstance(contains, str) and contains.strip():
        q = q.filter(_fold_sql(expr).contains(_fold_py(contains.strip()), autoescape=True))

    def member(vals):
        real = [v for v in vals if v != EMPTY]
        if is_int:
            real = [int(v) for v in real if v.lstrip("-").isdigit()]
        conds = []
        if real:
            conds.append(func.coalesce(expr.in_(real), false()))
        if EMPTY in vals:
            conds.append(expr.is_(None))
        return or_(*conds) if conds else false()

    if isinstance(spec.get("in"), list):
        q = q.filter(member([str(x) for x in spec["in"]]))
    if isinstance(spec.get("not_in"), list) and spec["not_in"]:
        q = q.filter(not_(member([str(x) for x in spec["not_in"]])))
    return q


def _apply_filters(q, model, raw: Optional[str], exclude: Optional[str] = None):
    specs = parse_filters(raw)
    real = {k: v for k, v in specs.items() if k not in VIRTUAL}
    q = apply_column_filters(q, model, json.dumps(real) if real else None, exclude=exclude)
    for name in VIRTUAL:
        spec = specs.get(name)
        if name == exclude or not isinstance(spec, dict):
            continue
        q = _virtual_filter(q, _virtual_expr(model, name), name == "diff_count", spec)
    return q


def _sort(q, model, sort_by: Optional[str], sort_dir: str):
    if not sort_by:
        return q.order_by(model.created_at.desc(), model.id.desc())      # newest first
    if sort_by == "diff_count":
        e = _virtual_expr(model, "diff_count")
        return q.order_by(e.desc() if str(sort_dir).lower() == "desc" else e.asc(),
                          model.id.asc())
    return apply_sort(q, model, sort_by, sort_dir)


# ── top-bar filters ───────────────────────────────────────────────────────────
def _topbar(db: Session, model, kind: str, params):
    q = db.query(model)
    if kind == "site":
        sid = _first(params, "site_id")
        if sid is not None and str(sid).isdigit():
            q = q.filter(model.site_id == int(sid))
        name = _first(params, "site_name")
        if name:
            like = f"%{name}%"
            q = q.filter(model.site_name.ilike(like) | model.site_name_old_ref.ilike(like))
    else:
        cid = _first(params, "cell_id")
        if cid is not None and str(cid).isdigit():
            q = q.filter(model.cell_id_ref == int(cid))
        name = _first(params, "site_name")
        if name:
            like = f"%{name}%"
            q = q.filter(model.site_name.ilike(like) | model.site_name_old.ilike(like))
        cname = _first(params, "cell_name")
        if cname:
            like = f"%{cname}%"
            q = q.filter(model.cell_name.ilike(like) | model.cell_name_old.ilike(like))
        sub = _first(params, "subcell_id")
        if sub:
            q = q.filter(model.subcell_id.ilike(f"%{sub}%"))
    tinh = _many(params, "tinh")
    if tinh:
        q = q.filter(model.tinh.in_(tinh))
    return q


def _scoped(db, model, kind, params, filters):
    return _apply_filters(_topbar(db, model, kind, params), model, filters)


# ── CSV helpers ───────────────────────────────────────────────────────────────
class CsvColumn(BaseModel):
    field: str
    title: Optional[str] = None


class CsvExportRequest(BaseModel):
    ids:      Optional[List[int]] = None          # selected rows -> exact export
    filters:  Optional[str] = None                # column filters JSON (same as ?filters=)
    params:   Dict[str, Any] = Field(default_factory=dict)   # top-bar filters
    sort_by:  Optional[str] = None
    sort_dir: str = "asc"
    columns:  Optional[List[CsvColumn]] = None    # same columns/titles as the table


def _csv_columns(model, req: Optional[List[CsvColumn]]):
    names = [c.name for c in model.__table__.columns]
    valid = set(names) | {"diff_count"}
    out, seen = [], set()
    for c in (req or []):
        if c.field in valid and c.field not in seen:
            out.append((c.field, c.title or c.field))
            seen.add(c.field)
    if not out:
        out = [(n, n) for n in names if n != "changed_fields"] + [("diff_count", "diff_count")]
    return out


def _s(x) -> str:
    return "" if x is None else str(x)


def _guard(s: str) -> str:
    """Neutralise CSV/Excel formula injection."""
    if s and s[0] in "=+@\t\r":
        try:
            float(s)
        except ValueError:
            return "'" + s
    return s


def _fmt_dt(v) -> str:
    if not isinstance(v, datetime):
        return _s(v)
    if v.tzinfo is None:
        v = v.replace(tzinfo=timezone.utc)
    return v.astimezone(_TZ).strftime("%Y-%m-%d %H:%M:%S")


def _csv_val(r, field: str, cf: dict):
    if field == "diff_count":
        return len(cf)
    v = getattr(r, field, None)
    if v is None:
        return ""
    if field == "created_at":
        return _fmt_dt(v)
    if isinstance(v, bool):
        return "x" if v else ""
    return _guard(str(v))


def _diff_text(cf: dict) -> str:
    parts = []
    for k, pair in cf.items():
        if isinstance(pair, (list, tuple)) and len(pair) == 2:
            parts.append(f"{k}: {_s(pair[0])} -> {_s(pair[1])}")
        else:
            parts.append(f"{k}: {_s(pair)}")
    return " | ".join(parts)


def _build_csv(q, cols):
    buf = io.StringIO(newline="")
    w = csv.writer(buf, lineterminator="\r\n")
    w.writerow([t for _f, t in cols] + ["Chi tiết thay đổi"])
    n = 0
    for r in q.yield_per(2000):
        cf = _changed(r)
        w.writerow([_csv_val(r, f, cf) for f, _t in cols] + [_diff_text(cf)])
        n += 1
    return ("\ufeff" + buf.getvalue()).encode("utf-8"), n     # BOM: Excel opens UTF-8 correctly


# ── route factory ─────────────────────────────────────────────────────────────
def _register(layer: str, model, kind: str, file_prefix: str) -> None:
    key = layer.replace("-", "_")

    def list_rows(
        request: Request,
        response: Response,
        skip: int = Query(0, ge=0),
        limit: int = Query(200, ge=1, le=50000),
        sort_by: Optional[str] = Query(None),
        sort_dir: str = Query("asc"),
        filters: Optional[str] = Query(None),
        db: Session = Depends(get_db),
        _=Depends(get_current_user),
    ):
        q = _scoped(db, model, kind, _req_params(request), filters)
        response.headers["X-Total-Count"] = str(q.count())
        q = _sort(q, model, sort_by, sort_dir)
        return [_row(r) for r in q.offset(skip).limit(limit).all()]

    def list_ids(
        request: Request,
        filters: Optional[str] = Query(None),
        db: Session = Depends(get_db),
        _=Depends(get_current_user),
    ):
        q = _scoped(db, model, kind, _req_params(request), filters)
        ids = [r[0] for r in q.with_entities(model.id).order_by(model.id).all()]
        return {"ids": ids, "total": len(ids)}

    def distinct_values(
        column: str,
        request: Request,
        filters: Optional[str] = Query(None),
        q: Optional[str] = Query(None),
        limit: int = Query(200, ge=1, le=1000),
        db: Session = Depends(get_db),
        _=Depends(get_current_user),
    ):
        if column in VIRTUAL:
            expr = _virtual_expr(model, column)
        else:
            _check(model, column)
            expr = _norm(model, column)
        base = _topbar(db, model, kind, _req_params(request))
        base = _apply_filters(base, model, filters, exclude=column)   # Excel-like
        if q and q.strip():
            base = base.filter(_fold_sql(expr).contains(_fold_py(q.strip()), autoescape=True))
        sub = base.with_entities(expr.label("v")).select_from(model).subquery()
        grouped = db.query(sub.c.v.label("v"), func.count().label("n")).group_by(sub.c.v)
        rows = grouped.order_by(sub.c.v.asc().nulls_last()).limit(limit).all()
        total = (db.query(func.count())
                   .select_from(grouped.order_by(None).subquery()).scalar() or 0)
        return {
            "values": [{"value": r.v, "count": r.n} for r in rows],
            "total_distinct": total,
        }

    def export_csv(
        body: CsvExportRequest,
        db: Session = Depends(get_db),
        _=Depends(get_current_user),
    ):
        if body.ids:
            q = db.query(model).filter(model.id.in_(list(body.ids)))
        else:
            q = _scoped(db, model, kind, body.params or {}, body.filters)
        q = _sort(q, model, body.sort_by, body.sort_dir)
        cols = _csv_columns(model, body.columns)
        with _EXPORT_SLOTS:
            data, n = _build_csv(q, cols)
        fname = f"{file_prefix}_{datetime.now(_TZ).strftime('%Y%m%d_%H%M%S')}.csv"
        return Response(
            content=data,
            media_type="text/csv; charset=utf-8",
            headers={
                "Content-Disposition": f'attachment; filename="{fname}"',
                "X-Row-Count": str(n),
                "Access-Control-Expose-Headers": _EXPOSE,
            },
        )

    router.add_api_route(f"/{layer}", list_rows, methods=["GET"], name=f"revisions_{key}_list")
    router.add_api_route(f"/{layer}/ids", list_ids, methods=["GET"], name=f"revisions_{key}_ids")
    router.add_api_route(f"/{layer}/distinct/{{column}}", distinct_values,
                         methods=["GET"], name=f"revisions_{key}_distinct")
    router.add_api_route(f"/{layer}/export-csv", export_csv,
                         methods=["POST"], name=f"revisions_{key}_export_csv")


# Registered BEFORE /sites/{site_id} so that /sites/ids is not read as a site id.
_register("sites",    SiteRevision,    "site", "Revision_Site")
_register("cells-3g", Cell3GRevision, "cell", "Revision_Cell_3G")
_register("cells-4g", Cell4GRevision, "cell", "Revision_Cell_4G")
_register("cells-5g", Cell5GRevision, "cell", "Revision_Cell_5G")


@router.get("/sites/{site_id}")
def get_site_revisions(
    site_id: int,
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    q = (db.query(SiteRevision)
           .filter(SiteRevision.site_id == site_id)
           .order_by(SiteRevision.created_at.desc(), SiteRevision.id.desc()))
    return [_row(r) for r in q.limit(500).all()]
