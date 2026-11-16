#!/usr/bin/env bash
# update_revision_server_side.sh
# Revision page: server-side column filters + sorting + paging + CSV export (all 4 tabs).
set -euo pipefail

ROOT="${1:-.}"
BE_REV="$ROOT/backend/app/api/routes/revision.py"
FE_PAGE="$ROOT/frontend/src/pages/revision/RevisionPage.tsx"
FE_OLD_TOOLS="$ROOT/frontend/src/pages/revision/revisionTableTools.tsx"
FE_API="$ROOT/frontend/src/api/revisionListing.ts"

for f in "$BE_REV" "$FE_PAGE" \
         "$ROOT/backend/app/services/list_query.py" \
         "$ROOT/frontend/src/hooks/useServerTable.tsx" \
         "$ROOT/frontend/src/api/listing.ts"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: $f not found. Run from the SiteLink root or pass the root path as argument 1." >&2
    exit 1
  fi
done

TS="$(date +%Y%m%d_%H%M%S)"
BK="$ROOT/.revision_backup_$TS"
mkdir -p "$BK"
cp "$BE_REV" "$BK/revision.py"
cp "$FE_PAGE" "$BK/RevisionPage.tsx"
[ -f "$FE_API" ] && cp "$FE_API" "$BK/revisionListing.ts" || true
if [ -f "$FE_OLD_TOOLS" ]; then
  mv "$FE_OLD_TOOLS" "$BK/revisionTableTools.tsx"
  echo "Moved superseded revisionTableTools.tsx into the backup"
fi
echo "Backup saved in $BK"

# ─────────────────────────────────────────────────────────────────────────────
# 1) BACKEND: backend/app/api/routes/revision.py
# ─────────────────────────────────────────────────────────────────────────────
cat > "$BE_REV" <<'EOF_REV_PY'
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
EOF_REV_PY

# ─────────────────────────────────────────────────────────────────────────────
# 2) FRONTEND API: frontend/src/api/revisionListing.ts
# ─────────────────────────────────────────────────────────────────────────────
cat > "$FE_API" <<'EOF_FE_API'
/**
 * revisionListing.ts
 * ------------------
 * Server-side listing (paging / column filters / select-all) and CSV export
 * for the revision endpoints. Same pattern as api/sites.ts.
 */
import api from './client'
import { pagedGet, idsGet, distinctGet } from './listing'

export type RevisionLayer = 'sites' | 'cells-3g' | 'cells-4g' | 'cells-5g'

const base = (layer: RevisionLayer) => `/api/v1/revisions/${layer}`

export const getRevisionsPaged = <T>(layer: RevisionLayer, params?: Record<string, unknown>) =>
  pagedGet<T>(base(layer), params)

export const getRevisionIds = (layer: RevisionLayer, params?: Record<string, unknown>) =>
  idsGet(base(layer), params)

export const getRevisionDistinct = (
  layer: RevisionLayer, column: string, params?: Record<string, unknown>,
) => distinctGet(base(layer), column, params)

// ── CSV export ───────────────────────────────────────────────────────────────
export interface RevisionCsvColumn { field: string; title: string }

export interface RevisionCsvRequest {
  ids?:      number[]
  filters?:  string
  params?:   Record<string, unknown>
  sort_by?:  string
  sort_dir?: 'asc' | 'desc'
  columns:   RevisionCsvColumn[]
}

async function errorText(err: any): Promise<string> {
  const data = err?.response?.data
  if (data instanceof Blob) {
    try {
      const txt = await data.text()
      try {
        const j = JSON.parse(txt)
        return typeof j?.detail === 'string' ? j.detail : txt
      } catch { return txt }
    } catch { /* ignore */ }
  }
  return err?.response?.data?.detail || err?.message || 'Xuất CSV thất bại'
}

export async function exportRevisionCsv(
  layer: RevisionLayer, body: RevisionCsvRequest,
): Promise<{ rows?: number; filename: string }> {
  let res
  try {
    res = await api.post(`${base(layer)}/export-csv`, body, { responseType: 'blob' })
  } catch (err: any) {
    throw new Error(await errorText(err))
  }
  const h = res.headers as any
  const cd: string = h?.['content-disposition'] || ''
  const m = /filename="?([^";]+)"?/i.exec(cd)
  const filename = m ? m[1] : `Revision_${layer}.csv`
  const rawRows = Number(h?.['x-row-count'])

  const blob = new Blob([res.data], { type: 'text/csv;charset=utf-8' })
  const link = document.createElement('a')
  link.href     = URL.createObjectURL(blob)
  link.download = filename
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(link.href)
  return { rows: Number.isFinite(rawRows) ? rawRows : undefined, filename }
}
EOF_FE_API

# ─────────────────────────────────────────────────────────────────────────────
# 3) FRONTEND PAGE: frontend/src/pages/revision/RevisionPage.tsx
# ─────────────────────────────────────────────────────────────────────────────
cat > "$FE_PAGE" <<'EOF_FE_PAGE'
/**
 * RevisionPage.tsx – Revision History Viewer
 *
 * Server-side, exactly like the Site module:
 *  - Excel-style column filters + sorting on every column header (useServerColumns)
 *  - server paging, "select all N results"
 *  - "Xuất CSV" on every tab: selected rows win, otherwise everything the
 *    top-bar + column filters match (current sort order)
 * Rename banners only appear when the name is in the changed_fields diff.
 */
import React, { useState, useCallback, useEffect, useMemo, useRef } from 'react'
import { useDebouncedValue } from '@/hooks/useDebouncedValue'
import { useServerQuery, useServerColumns } from '@/hooks/useServerTable'
import {
  Typography, Tabs, Input, Button, Table, Tag, Space,
  Row, Col, Badge, Alert, Select, Tooltip, message,
} from 'antd'
import type { ColumnsType, ColumnType } from 'antd/es/table'
import type { TableRowSelection } from 'antd/es/table/interface'
import {
  SearchOutlined, ReloadOutlined, HistoryOutlined,
  FileExcelOutlined, FormOutlined, RobotOutlined, DownloadOutlined,
} from '@ant-design/icons'
import type { SiteRevision, CellRevisionBase } from '@/api/revision'
import {
  getRevisionsPaged, getRevisionIds, getRevisionDistinct, exportRevisionCsv,
} from '@/api/revisionListing'
import type { RevisionLayer, RevisionCsvColumn } from '@/api/revisionListing'
import { buildExportScope } from '@/api/export'
import { getTinhList } from '@/api/report'
import type { TinhItem } from '@/types'

// ── constants ─────────────────────────────────────────────────────────────────
const SOURCE_TAG: Record<string, React.ReactNode> = {
  form:   <Tag icon={<FormOutlined />}      color="blue">Form</Tag>,
  excel:  <Tag icon={<FileExcelOutlined />} color="green">Excel</Tag>,
  script: <Tag icon={<RobotOutlined />}     color="purple">Script</Tag>,
}

const boolTag = (v: unknown) =>
  v ? <Tag color="green">x</Tag> : <Tag color="default">-</Tag>

const fmtTime = (v: string) => (v ? new Date(v).toLocaleString('vi-VN') : '-')

const diffCountCell = (_: unknown, r: { changed_fields?: Record<string, unknown> }) => {
  const n = Object.keys(r.changed_fields || {}).length
  return n ? <Tag color="orange">{n} trường</Tag> : <Tag color="default">Tạo mới</Tag>
}

/** drop empty values so the params object (and its JSON key) stays minimal */
function cleanParams(p: Record<string, string | undefined>): Record<string, string> {
  const out: Record<string, string> = {}
  Object.entries(p).forEach(([k, v]) => {
    const t = (v ?? '').trim()
    if (t) out[k] = t
  })
  return out
}

// ── DiffTable: shows changed_fields {field:[old,new]} ─────────────────────────
function DiffTable({ diff }: { diff: Record<string, [unknown, unknown]> }) {
  const entries = Object.entries(diff)
  if (!entries.length)
    return <span style={{ color: '#999', fontSize: 12 }}>Bản ghi tạo mới – không có diff</span>

  const isNameField = (k: string) =>
    ['site_name', 'cell_name', 'site_name_old', 'cell_name_old', 'site_name_old_ref'].includes(k)

  return (
    <table style={{ borderCollapse: 'collapse', fontSize: 12, width: '100%' }}>
      <thead>
        <tr style={{ background: '#fafafa' }}>
          <th style={{ padding: '4px 8px', border: '1px solid #f0f0f0', width: 210 }}>Trường</th>
          <th style={{ padding: '4px 8px', border: '1px solid #f0f0f0' }}>Giá trị cũ</th>
          <th style={{ padding: '4px 8px', border: '1px solid #f0f0f0' }}>Giá trị mới</th>
        </tr>
      </thead>
      <tbody>
        {entries.map(([key, [ov, nv]]) => (
          <tr key={key} style={{ background: isNameField(key) ? '#fff7e6' : 'white' }}>
            <td style={{
              padding: '3px 8px', border: '1px solid #f0f0f0',
              fontWeight: isNameField(key) ? 700 : 400,
              color: isNameField(key) ? '#d46b08' : '#333',
            }}>
              {key}
              {isNameField(key) && <Tag color="orange" style={{ marginLeft: 4, fontSize: 10 }}>tên</Tag>}
            </td>
            <td style={{
              padding: '3px 8px', border: '1px solid #f0f0f0',
              color: '#cf1322', textDecoration: 'line-through', fontFamily: 'monospace',
            }}>
              {ov === null || ov === undefined ? <em style={{ color: '#ccc' }}>null</em> : String(ov)}
            </td>
            <td style={{
              padding: '3px 8px', border: '1px solid #f0f0f0',
              color: '#237804', fontFamily: 'monospace',
            }}>
              {nv === null || nv === undefined ? <em style={{ color: '#ccc' }}>null</em> : String(nv)}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

// ── Shared: province filter select ────────────────────────────────────────────
function TinhFilter({
  tinhList, value, onChange,
}: {
  tinhList: TinhItem[]
  value: string | undefined
  onChange: (v: string | undefined) => void
}) {
  return (
    <Select
      showSearch allowClear
      placeholder="Lọc theo Tỉnh..."
      style={{ width: 220 }}
      value={value}
      onChange={onChange}
      filterOption={(input, opt) =>
        String(opt?.children ?? '').toLowerCase().includes(input.toLowerCase())
      }
    >
      {tinhList.map(t => (
        <Select.Option key={t.ten_tinh} value={t.ten_tinh}>{t.ten_tinh}</Select.Option>
      ))}
    </Select>
  )
}

// ═════════════════════════════════════════════════════════════════════════════
// COLUMN DEFINITIONS  (every column needs a string dataIndex = DB column name)
// ═════════════════════════════════════════════════════════════════════════════

// ── Site ──────────────────────────────────────────────────────────────────────
const SITE_COLUMNS: ColumnsType<SiteRevision> = [
  {
    title: 'Rev#', dataIndex: 'revision_no', width: 60, fixed: 'left',
    render: (v: number) => <Badge count={v} color="#597ef7" />,
  },
  { title: 'Thời gian', dataIndex: 'created_at', width: 155, fixed: 'left', render: fmtTime },
  {
    title: 'Site Name', dataIndex: 'site_name', width: 220, fixed: 'left',
    ellipsis: { showTitle: true },
    render: (v: string, r: SiteRevision) => (
      <Space direction="vertical" size={0}>
        <strong>{v}</strong>
        {r.site_name_old_ref && (
          <span style={{ fontSize: 11, color: '#d46b08' }}>
            ← đổi từ: <em>{r.site_name_old_ref}</em>
          </span>
        )}
      </Space>
    ),
  },
  { title: 'Site name (cũ)', dataIndex: 'site_name_cu', width: 180, ellipsis: { showTitle: true } },
  { title: 'Miền',    dataIndex: 'mien',     width: 70  },
  { title: 'Tỉnh',    dataIndex: 'tinh',     width: 160 },
  { title: 'Phường xã', dataIndex: 'phuong_xa', width: 160, ellipsis: { showTitle: true } },
  { title: 'Site VIP', dataIndex: 'site_vip', width: 90,
    render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-' },
  { title: 'Lat',  dataIndex: 'lat',  width: 110 },
  { title: 'Long', dataIndex: 'long', width: 110 },
  { title: 'Trạm 2G', dataIndex: 'tram_2g', width: 80, render: boolTag },
  { title: 'Trạm 3G', dataIndex: 'tram_3g', width: 80, render: boolTag },
  { title: 'Trạm 4G', dataIndex: 'tram_4g', width: 80, render: boolTag },
  { title: 'Trạm 5G', dataIndex: 'tram_5g', width: 80, render: boolTag },
  { title: 'Repeater', dataIndex: 'repeater', width: 90, render: boolTag },
  { title: 'Booster',  dataIndex: 'booster',  width: 85, render: boolTag },
  { title: 'Node truyền dẫn only', dataIndex: 'node_truyen_dan_only', width: 175, render: boolTag },
  { title: 'TSCA', dataIndex: 'tram_phu_song_tsca', width: 75, render: boolTag },
  { title: 'Phân loại trạm', dataIndex: 'phan_loai_tram', width: 160 },
  { title: 'MORAN 3G', dataIndex: 'moran_3g', width: 110 },
  { title: 'MORAN 4G', dataIndex: 'moran_4g', width: 110 },
  { title: 'MORAN 5G', dataIndex: 'moran_5g', width: 110 },
  { title: 'Mã PTM',   dataIndex: 'ma_ptm',   width: 110 },
  { title: 'Độ cao đỉnh cột anten đến mặt đất (m)', dataIndex: 'do_cao_dinh_cot_anten', width: 150 },
  { title: 'Độ cao cột anten (đỉnh cột anten đến chân cột anten, không tính độ cao công trình) (m)',
    dataIndex: 'do_cao_cot_anten', width: 120 },
  { title: 'Địa chỉ', dataIndex: 'dia_chi', width: 200, ellipsis: { showTitle: true } },
  { title: 'Ghi chú', dataIndex: 'ghi_chu', width: 160, ellipsis: { showTitle: true } },
  {
    title: 'Nguồn', dataIndex: 'change_source', width: 90,
    render: (v: string) => SOURCE_TAG[v] || <Tag>{v}</Tag>,
  },
  {
    title: 'Người thay đổi', dataIndex: 'changed_by_name', width: 160,
    render: (v: string) => v || <span style={{ color: '#ccc' }}>–</span>,
  },
  { title: 'Số trường TĐ', dataIndex: 'diff_count', width: 120, render: diffCountCell },
  { title: 'Ghi chú TĐ', dataIndex: 'change_note', width: 160, ellipsis: { showTitle: true } },
]

// ── Cells ─────────────────────────────────────────────────────────────────────
type CellCol = ColumnType<CellRevisionBase>

/** Plain text column read from r[key] ('-' when empty). */
function txtCol(title: string, key: string, width: number, extra: Partial<CellCol> = {}): CellCol {
  return {
    title, dataIndex: key, width,
    render: (_: unknown, r: CellRevisionBase) => String(r[key] ?? '-'),
    ...extra,
  }
}

const dashOr = (v: string) => v || <span style={{ color: '#ccc' }}>-</span>

function commonCellColumns(): CellCol[] {
  return [
    {
      title: 'Rev#', dataIndex: 'revision_no', width: 60, fixed: 'left',
      render: (v: number) => <Badge count={v} color="#597ef7" />,
    },
    { title: 'Thời gian', dataIndex: 'created_at', width: 155, fixed: 'left', render: fmtTime },
    {
      title: 'Site Name', dataIndex: 'site_name', width: 200, fixed: 'left',
      ellipsis: { showTitle: true },
      render: (v: string, r: CellRevisionBase) => (
        <Space direction="vertical" size={0}>
          <span>{v}</span>
          {r.site_name_old && (
            <span style={{ fontSize: 11, color: '#d46b08' }}>← {r.site_name_old}</span>
          )}
        </Space>
      ),
    },
    {
      title: 'Cell Name', dataIndex: 'cell_name', width: 220, fixed: 'left',
      ellipsis: { showTitle: true },
      render: (v: string, r: CellRevisionBase) => (
        <Space direction="vertical" size={0}>
          <strong>{v}</strong>
          {r.cell_name_old && (
            <span style={{ fontSize: 11, color: '#d46b08' }}>
              ← đổi từ: <em>{r.cell_name_old}</em>
            </span>
          )}
        </Space>
      ),
    },
    { title: 'Subcell-ID', dataIndex: 'subcell_id', width: 100, fixed: 'left', render: dashOr },
    { title: 'Site Name Old', dataIndex: 'site_name_old', width: 200,
      ellipsis: { showTitle: true }, render: dashOr },
    { title: 'Cell Name Old', dataIndex: 'cell_name_old', width: 200,
      ellipsis: { showTitle: true }, render: dashOr },
    { title: 'Miền', dataIndex: 'mien', width: 70 },
    { title: 'Tỉnh', dataIndex: 'tinh', width: 160 },
    txtCol('Phường xã', 'phuong_xa', 160),
    txtCol('Cell VIP', 'cell_vip', 90, {
      render: (_: unknown, r: CellRevisionBase) =>
        r['cell_vip'] ? <Tag color="gold">{String(r['cell_vip'])}</Tag> : <span>-</span>,
    }),
    txtCol('MORAN', 'moran', 120),
    { title: 'Lat',  dataIndex: 'lat',  width: 110 },
    { title: 'Long', dataIndex: 'long', width: 110 },
    txtCol('Vùng phủ sóng', 'vung_phu_song', 130),
    { title: 'Vendor', dataIndex: 'vendor', width: 100 },
    txtCol('Cao anten (m)', 'do_cao_anten', 115),
    { title: 'Azimuth', dataIndex: 'azimuth', width: 90 },
    txtCol('M-tilt', 'm_tilt', 80),
    txtCol('E-Tilt', 'e_tilt', 80),
    txtCol('Total Tilt', 'total_tilt', 95),
    txtCol('Loại Anten', 'loai_anten', 220, { ellipsis: { showTitle: true } }),
    txtCol('RF', 'rf', 90),
    txtCol('Cell ID', 'cell_id', 90),
    txtCol('MIMO', 'mimo', 80, {
      render: (_: unknown, r: CellRevisionBase) =>
        r['mimo'] ? <Tag color="blue">{String(r['mimo'])}</Tag> : <span>-</span>,
    }),
    txtCol('Cell max power (dBm)', 'cell_max_power', 175),
    txtCol('BBUname', 'bbu_name', 130),
    txtCol('Cell status', 'cell_status', 140),
    txtCol('Ngày dữ liệu dump', 'dump_date', 160),
    txtCol('OSS', 'oss', 90),
  ]
}

function metaCellColumns(): CellCol[] {
  return [
    { title: 'Nguồn', dataIndex: 'change_source', width: 90,
      render: (v: string) => SOURCE_TAG[v] || <Tag>{v}</Tag> },
    { title: 'Người thay đổi', dataIndex: 'changed_by_name', width: 160,
      render: (v: string) => v || <span style={{ color: '#ccc' }}>–</span> },
    { title: 'Số trường TĐ', dataIndex: 'diff_count', width: 120, render: diffCountCell },
  ]
}

function techCellColumns(tech: '3G' | '4G' | '5G'): ColumnsType<CellRevisionBase> {
  let specific: CellCol[] = []
  if (tech === '3G') {
    specific = [
      txtCol('Chung anten', 'chung_anten', 120),
      txtCol('ARFCN', 'arfcn', 90),
      txtCol('UARFCN', 'uarfcn', 95),
      txtCol('LAC', 'lac', 80),
      txtCol('RAC', 'rac', 80),
      txtCol('PSC', 'psc', 80),
      txtCol('URAId', 'ura_id', 80),
      txtCol('RNC Name', 'rnc_name', 130, {
        render: (_: unknown, r: CellRevisionBase) =>
          r['rnc_name'] ? <Tag color="cyan">{String(r['rnc_name'])}</Tag> : <span>-</span>,
      }),
      txtCol('CPICH power (dBm)', 'cpich_power', 155),
    ]
  } else if (tech === '4G') {
    specific = [
      txtCol('Chung anten', 'chung_anten', 120),
      txtCol('EnodeB ID', 'enodeb_id', 110),
      txtCol('EARFCN', 'earfcn', 90),
      txtCol('TAC', 'tac', 80),
      txtCol('PCI', 'pci', 80),
      txtCol('Root Sequence ID', 'root_sequence_id', 155),
      txtCol('Bandwidth (MHz)', 'bandwidth', 130),
      txtCol('ECI', 'eci', 110),
    ]
  } else {
    specific = [
      txtCol('gNodeB ID', 'gnodeb_id', 110),
      txtCol('TAC', 'tac', 80),
      txtCol('PCI', 'pci', 80),
      txtCol('Root Sequence ID', 'root_sequence_id', 155),
      txtCol('SSB-ARFCN', 'ssb_arfcn', 110),
      txtCol('Center-ARFCN', 'center_arfcn', 125),
      txtCol('GSCN', 'gscn', 85),
      txtCol('Bandwidth (MHz)', 'bandwidth', 130),
      txtCol('NCI', 'nci', 110),
      txtCol('MU-MIMO', 'mu_mimo', 95),
    ]
  }
  return [...commonCellColumns(), ...specific, ...metaCellColumns()]
}

const CELL_COLUMNS: Record<'3G' | '4G' | '5G', ColumnsType<CellRevisionBase>> = {
  '3G': techCellColumns('3G'),
  '4G': techCellColumns('4G'),
  '5G': techCellColumns('5G'),
}

// extra fields added to the CSV on top of the visible columns
const SITE_EXTRAS: RevisionCsvColumn[] = [
  { field: 'site_id',           title: 'Site ID (DB)' },
  { field: 'site_name_old_ref', title: 'Site name cũ (đổi từ)' },
  { field: 'change_note',       title: 'Ghi chú thay đổi' },
]
const CELL_EXTRAS: RevisionCsvColumn[] = [
  { field: 'site_id',     title: 'Site ID (DB)' },
  { field: 'cell_id_ref', title: 'Cell ID (DB)' },
  { field: 'baseband',    title: 'Baseband' },
  { field: 'change_note', title: 'Ghi chú thay đổi' },
]

/** CSV columns = the table's columns (same titles / order) + extras */
function csvColumnsOf<T>(cols: ColumnsType<T>, extras: RevisionCsvColumn[]): RevisionCsvColumn[] {
  const out: RevisionCsvColumn[] = []
  const seen = new Set<string>()
  ;(cols as ColumnType<T>[]).forEach(c => {
    const f = typeof c.dataIndex === 'string' ? c.dataIndex : undefined
    if (!f || seen.has(f)) return
    seen.add(f)
    out.push({ field: f, title: typeof c.title === 'string' ? c.title : f })
  })
  extras.forEach(e => { if (!seen.has(e.field)) { seen.add(e.field); out.push(e) } })
  return out
}

// ═════════════════════════════════════════════════════════════════════════════
// EXPANDED ROW RENDERERS
// ═════════════════════════════════════════════════════════════════════════════
const renderSiteExpanded = (r: SiteRevision) => {
  const diff    = r.changed_fields || {}
  const nDiff   = Object.keys(diff).length
  const renamed = 'site_name' in diff          // banner only when site_name is in the diff
  return (
    <div style={{ padding: '12px 16px' }}>
      {renamed && (
        <Alert type="warning" showIcon style={{ marginBottom: 12 }}
          message={
            <span>Đổi tên site:&nbsp;
              <strong style={{ color: '#cf1322' }}>{String(diff['site_name']?.[0] ?? '')}</strong>
              &nbsp;→&nbsp;
              <strong style={{ color: '#237804' }}>{String(diff['site_name']?.[1] ?? '')}</strong>
            </span>
          }
        />
      )}
      <Typography.Text strong style={{ fontSize: 13 }}>
        🔄 Các trường thay đổi ({nDiff}) – Revision #{r.revision_no}
      </Typography.Text>
      <div style={{ marginTop: 8, marginBottom: 16 }}>
        <DiffTable diff={diff} />
      </div>
    </div>
  )
}

const renderCellExpanded = (r: CellRevisionBase) => {
  const diff  = r.changed_fields || {}
  const nDiff = Object.keys(diff).length
  const cellRenamed = 'cell_name' in diff
  const siteRenamed = 'site_name' in diff
  return (
    <div style={{ padding: '12px 16px' }}>
      {cellRenamed && (
        <Alert type="warning" showIcon style={{ marginBottom: 8 }}
          message={
            <span>Đổi tên cell:&nbsp;
              <strong style={{ color: '#cf1322' }}>{String(diff['cell_name']?.[0] ?? '')}</strong>
              &nbsp;→&nbsp;
              <strong style={{ color: '#237804' }}>{String(diff['cell_name']?.[1] ?? '')}</strong>
            </span>
          }
        />
      )}
      {siteRenamed && (
        <Alert type="warning" showIcon style={{ marginBottom: 12 }}
          message={
            <span>Đổi tên site:&nbsp;
              <strong style={{ color: '#cf1322' }}>{String(diff['site_name']?.[0] ?? '')}</strong>
              &nbsp;→&nbsp;
              <strong style={{ color: '#237804' }}>{String(diff['site_name']?.[1] ?? '')}</strong>
            </span>
          }
        />
      )}
      <Typography.Text strong style={{ fontSize: 13 }}>
        🔄 Các trường thay đổi ({nDiff}) – Revision #{r.revision_no}
      </Typography.Text>
      <div style={{ marginTop: 8 }}>
        <DiffTable diff={diff} />
      </div>
    </div>
  )
}

// ═════════════════════════════════════════════════════════════════════════════
// SHARED GRID  (server paging + column filters + sort + selection + CSV export)
// ═════════════════════════════════════════════════════════════════════════════
interface RevRow {
  id: number
  revision_no: number
  changed_fields: Record<string, [unknown, unknown]>
}

function RevisionGrid<T extends RevRow>({
  layer, topParams, reloadKey, resetKey, columns, renderExpanded, extraFields, unit,
}: {
  layer: RevisionLayer
  topParams: Record<string, string>      // already debounced + cleaned
  reloadKey: number                      // bump => reload
  resetKey: number                       // bump => clear column filters + selection
  columns: ColumnsType<T>
  renderExpanded: (r: T) => React.ReactNode
  extraFields: RevisionCsvColumn[]
  unit: string
}) {
  const paramsKey = JSON.stringify(topParams)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const stableParams = useMemo(() => topParams, [paramsKey])

  const sq = useServerQuery([paramsKey])
  const [rows,        setRows]        = useState<T[]>([])
  const [loading,     setLoading]     = useState(false)
  const [loadError,   setLoadError]   = useState<string | null>(null)
  const [selectedIds, setSelectedIds] = useState<number[]>([])
  const [exporting,   setExporting]   = useState(false)

  const load = useCallback(() => {
    setLoading(true)
    setLoadError(null)
    const params: Record<string, unknown> = { ...sq.params, ...stableParams }
    const ticket = sq.nextTicket()
    getRevisionsPaged<T>(layer, params)
      .then(res => {
        if (!sq.isCurrent(ticket)) return
        setRows(res.items)
        sq.onLoaded(res.total, params)
      })
      .catch(err => {
        if (!sq.isCurrent(ticket)) return
        const detail = err?.response?.data?.detail || err?.message || 'Unknown error'
        setLoadError(`Không tải được lịch sử thay đổi: ${typeof detail === 'string' ? detail : JSON.stringify(detail)}`)
      })
      .finally(() => { if (sq.isCurrent(ticket)) setLoading(false) })
    // reloadKey: explicit "Tìm kiếm" button
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [layer, stableParams, reloadKey, sq.params])

  useEffect(() => { load() }, [load])

  const {
    columns: excelColumns, dataSource, onChange, filterBar,
  } = useServerColumns<T>(columns, rows, sq, {
    fetchDistinct: (field, p) => getRevisionDistinct(layer, field, p),
    fetchIds:      (p) => getRevisionIds(layer, p),
    selectedIds, setSelectedIds, unit,
  })

  // toolbar "Xóa lọc" => also clear column filters + selection
  const firstReset = useRef(true)
  useEffect(() => {
    if (firstReset.current) { firstReset.current = false; return }
    sq.clearFilters()
    setSelectedIds([])
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [resetKey])

  const exportCols = useMemo(() => csvColumnsOf(columns, extraFields), [columns, extraFields])

  const handleExport = async () => {
    setExporting(true)
    try {
      // selected rows -> exactly those; otherwise everything the filters match
      const scope  = buildExportScope(sq, selectedIds)
      const hasIds = Boolean(scope.ids && scope.ids.length > 0)
      const res = await exportRevisionCsv(layer, {
        ids:      scope.ids,
        params:   hasIds ? {} : stableParams,
        filters:  scope.filters,
        sort_by:  scope.sort_by,
        sort_dir: scope.sort_dir ?? 'asc',
        columns:  exportCols,
      })
      message.success(
        `Xuất CSV thành công${res.rows != null ? ` (${res.rows.toLocaleString('vi-VN')} dòng)` : ''}`)
    } catch (e: unknown) {
      message.error(e instanceof Error ? e.message : 'Xuất CSV thất bại')
    } finally {
      setExporting(false)
    }
  }

  const rowSelection: TableRowSelection<T> = {
    selectedRowKeys: selectedIds,
    preserveSelectedRowKeys: true,
    fixed: true,
    columnWidth: 48,
    onChange: keys => setSelectedIds(keys as number[]),
    selections: [Table.SELECTION_ALL, Table.SELECTION_INVERT, Table.SELECTION_NONE],
  }

  const scrollX = excelColumns.reduce((s, c) => s + ((c.width as number) || 100), 0) + 100

  return (
    <div>
      {loadError && (
        <Alert message={loadError} type="error" showIcon closable
               style={{ marginBottom: 12 }} onClose={() => setLoadError(null)} />
      )}

      <Row justify="space-between" align="middle" gutter={[8, 8]} style={{ marginBottom: 8 }}>
        <Col>
          <Typography.Text type="secondary" style={{ fontSize: 12 }}>
            Nhấn ▶ để xem chi tiết các trường thay đổi; nhấn biểu tượng lọc ở tiêu đề cột để lọc / sắp xếp.
          </Typography.Text>
        </Col>
        <Col>
          <Tooltip
            title={selectedIds.length > 0
              ? `Xuất ${selectedIds.length} dòng đã chọn ra CSV`
              : 'Xuất các dòng đang lọc (gồm cả bộ lọc cột) ra CSV'}
          >
            <Button
              icon={<DownloadOutlined />}
              loading={exporting}
              disabled={loading || sq.total === 0}
              onClick={handleExport}
              style={{ borderColor: '#52c41a', color: '#52c41a' }}
            >
              Xuất CSV{selectedIds.length > 0
                ? ` (${selectedIds.length.toLocaleString('vi-VN')} đã chọn)`
                : ` (${sq.total.toLocaleString('vi-VN')} dòng)`}
            </Button>
          </Tooltip>
        </Col>
      </Row>

      {filterBar}

      <Table<T>
        rowSelection={rowSelection}
        columns={excelColumns}
        onChange={onChange}
        dataSource={dataSource}
        rowKey="id"
        loading={loading}
        size="small"
        scroll={{ x: scrollX, y: 500 }}
        bordered
        pagination={sq.pagination(unit)}
        expandable={{
          expandedRowRender: renderExpanded,
          rowExpandable: () => true,
        }}
      />
    </div>
  )
}

// ═════════════════════════════════════════════════════════════════════════════
// SITE REVISION TAB
// ═════════════════════════════════════════════════════════════════════════════
function SiteRevisionTab({ tinhList }: { tinhList: TinhItem[] }) {
  const [search,    setSearch]    = useState('')
  const [tinh,      setTinh]      = useState<string | undefined>()
  const [reloadKey, setReloadKey] = useState(0)
  const [resetKey,  setResetKey]  = useState(0)
  const dSearch = useDebouncedValue(search, 400)

  const topParams = useMemo(
    () => cleanParams({ site_name: dSearch, tinh }),
    [dSearch, tinh],
  )
  const reload = () => setReloadKey(k => k + 1)

  return (
    <div>
      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="300px">
          <Input prefix={<SearchOutlined />}
            placeholder="Tìm site name (hiện tại hoặc tên cũ)..."
            value={search} onChange={e => setSearch(e.target.value)}
            onPressEnter={reload} allowClear />
        </Col>
        <Col>
          <TinhFilter tinhList={tinhList} value={tinh} onChange={setTinh} />
        </Col>
        <Col>
          <Button type="primary" icon={<SearchOutlined />} onClick={reload}>
            Tìm kiếm
          </Button>
        </Col>
        <Col>
          <Button icon={<ReloadOutlined />}
            onClick={() => { setSearch(''); setTinh(undefined); setResetKey(k => k + 1) }}>
            Xóa lọc
          </Button>
        </Col>
      </Row>
      <RevisionGrid<SiteRevision>
        layer="sites"
        topParams={topParams}
        reloadKey={reloadKey}
        resetKey={resetKey}
        columns={SITE_COLUMNS}
        renderExpanded={renderSiteExpanded}
        extraFields={SITE_EXTRAS}
        unit="phiên bản"
      />
    </div>
  )
}

// ═════════════════════════════════════════════════════════════════════════════
// CELL REVISION TAB (3G / 4G / 5G)
// ═════════════════════════════════════════════════════════════════════════════
const CELL_LAYER: Record<'3G' | '4G' | '5G', RevisionLayer> = {
  '3G': 'cells-3g', '4G': 'cells-4g', '5G': 'cells-5g',
}

function CellRevisionTab({
  tech, tinhList,
}: {
  tech: '3G' | '4G' | '5G'
  tinhList: TinhItem[]
}) {
  const [siteName,  setSiteName]  = useState('')
  const [cellName,  setCellName]  = useState('')
  const [subcellId, setSubcellId] = useState('')
  const [tinh,      setTinh]      = useState<string | undefined>()
  const [reloadKey, setReloadKey] = useState(0)
  const [resetKey,  setResetKey]  = useState(0)
  const dSite    = useDebouncedValue(siteName, 400)
  const dCell    = useDebouncedValue(cellName, 400)
  const dSubcell = useDebouncedValue(subcellId, 400)

  const topParams = useMemo(
    () => cleanParams({ site_name: dSite, cell_name: dCell, subcell_id: dSubcell, tinh }),
    [dSite, dCell, dSubcell, tinh],
  )
  const reload = () => setReloadKey(k => k + 1)

  return (
    <div>
      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="250px">
          <Input prefix={<SearchOutlined />}
            placeholder="Site name (hiện tại hoặc cũ)..."
            value={siteName} onChange={e => setSiteName(e.target.value)}
            onPressEnter={reload} allowClear />
        </Col>
        <Col flex="250px">
          <Input prefix={<SearchOutlined />}
            placeholder="Cell name (hiện tại hoặc cũ)..."
            value={cellName} onChange={e => setCellName(e.target.value)}
            onPressEnter={reload} allowClear />
        </Col>
        <Col flex="170px">
          <Input prefix={<SearchOutlined />}
            placeholder="Subcell-ID..."
            value={subcellId} onChange={e => setSubcellId(e.target.value)}
            onPressEnter={reload} allowClear />
        </Col>
        <Col>
          <TinhFilter tinhList={tinhList} value={tinh} onChange={setTinh} />
        </Col>
        <Col>
          <Button type="primary" icon={<SearchOutlined />} onClick={reload}>
            Tìm kiếm
          </Button>
        </Col>
        <Col>
          <Button icon={<ReloadOutlined />}
            onClick={() => {
              setSiteName(''); setCellName(''); setSubcellId(''); setTinh(undefined)
              setResetKey(k => k + 1)
            }}>
            Xóa lọc
          </Button>
        </Col>
      </Row>
      <RevisionGrid<CellRevisionBase>
        layer={CELL_LAYER[tech]}
        topParams={topParams}
        reloadKey={reloadKey}
        resetKey={resetKey}
        columns={CELL_COLUMNS[tech]}
        renderExpanded={renderCellExpanded}
        extraFields={CELL_EXTRAS}
        unit={`phiên bản Cell ${tech}`}
      />
    </div>
  )
}

// ═════════════════════════════════════════════════════════════════════════════
// MAIN PAGE
// ═════════════════════════════════════════════════════════════════════════════
export default function RevisionPage() {
  const [tinhList, setTinhList] = useState<TinhItem[]>([])
  useEffect(() => { getTinhList().then(setTinhList) }, [])

  return (
    <div>
      <Row align="middle" style={{ marginBottom: 16 }}>
        <HistoryOutlined style={{ fontSize: 22, color: '#597ef7', marginRight: 10 }} />
        <Typography.Title level={3} style={{ margin: 0 }}>
          Lịch sử thay đổi (Revision History)
        </Typography.Title>
      </Row>
      <Alert type="info" showIcon style={{ marginBottom: 16 }}
        message="Hệ thống lưu toàn bộ lịch sử thay đổi"
        description={
          <ul style={{ margin: 0, paddingLeft: 20, fontSize: 13 }}>
            <li>Dữ liệu tự động tải khi mở trang – bộ lọc trống hiển thị tất cả thay đổi gần nhất.</li>
            <li>Mỗi lần tạo mới hoặc cập nhật đều tạo một bản ghi revision.</li>
            <li>Tìm kiếm theo tên hiện tại <strong>hoặc</strong> tên cũ đều ra kết quả.</li>
            <li>Nhấn ▶ để xem diff chi tiết các trường thay đổi trong revision đó.</li>
            <li>Banner "Đổi tên" chỉ xuất hiện khi tên <strong>thực sự thay đổi</strong> trong revision đó.</li>
            <li>Nhấn biểu tượng lọc ở tiêu đề cột để <strong>lọc kiểu Excel</strong> và <strong>sắp xếp</strong> (xử lý trên server, toàn bộ lịch sử).</li>
            <li><strong>Xuất CSV</strong>: xuất các dòng đã chọn, hoặc toàn bộ kết quả đang lọc (gồm cả bộ lọc cột).</li>
          </ul>
        }
      />
      <Tabs defaultActiveKey="sites" items={[
        { key: 'sites',   label: '🏗️ Site',    children: <SiteRevisionTab tinhList={tinhList} /> },
        { key: 'cells3g', label: '📡 Cell 3G', children: <CellRevisionTab tech="3G" tinhList={tinhList} /> },
        { key: 'cells4g', label: '📡 Cell 4G', children: <CellRevisionTab tech="4G" tinhList={tinhList} /> },
        { key: 'cells5g', label: '📡 Cell 5G', children: <CellRevisionTab tech="5G" tinhList={tinhList} /> },
      ]} />
    </div>
  )
}
EOF_FE_PAGE

echo
echo "Files written:"
echo "  $BE_REV"
echo "  $FE_API"
echo "  $FE_PAGE"
echo "Originals saved in $BK"

# ── sanity checks ─────────────────────────────────────────────────────────────
if command -v python3 >/dev/null 2>&1; then
  python3 -c "import ast,sys; ast.parse(open(sys.argv[1], encoding='utf-8').read())" "$BE_REV" \
    && echo "Python syntax OK (revision.py)" \
    || echo "WARNING: revision.py has a syntax error"
fi

if [ -d "$ROOT/frontend/node_modules" ]; then
  echo "Running TypeScript check (frontend)..."
  ( cd "$ROOT/frontend" && npx --no-install tsc --noEmit ) \
    && echo "TypeScript OK" \
    || echo "WARNING: tsc reported errors - please send them to me."
fi

echo
echo "Next: rebuild BOTH images (backend changed + VITE_* is baked at build time), e.g."
echo "  docker compose build backend frontend && docker compose up -d"