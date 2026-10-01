#!/usr/bin/env bash
# update_server_side.sh — server-side paging / sort / column filters / selection
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run with bash:  bash update_server_side.sh [ROOT]"; exit 1
fi
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
is_root() { [ -d "$1/backend/app" ] && [ -d "$1/frontend/src" ]; }
ROOT=""
if [ -n "${1:-}" ]; then
  ROOT="$(cd "$1" 2>/dev/null && pwd)" || { echo "ERROR: cannot cd to '$1'"; exit 1; }
elif is_root "$SCRIPT_DIR"; then ROOT="$SCRIPT_DIR"
elif TOP="$(git rev-parse --show-toplevel 2>/dev/null)" && is_root "$TOP"; then ROOT="$TOP"
fi
if [ -z "$ROOT" ] || ! is_root "$ROOT"; then
  echo "ERROR: could not find the SiteLink root (needs backend/app and frontend/src)."
  echo "Usage: bash update_server_side.sh /path/to/SiteLink"; exit 1
fi
command -v python3 >/dev/null || { echo "ERROR: python3 required"; exit 1; }

IS_GIT=0
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 && IS_GIT=1
echo "==> Project root : $ROOT"
echo "==> Git repo     : $([ $IS_GIT -eq 1 ] && git -C "$ROOT" rev-parse --show-toplevel || echo 'NO')"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$HOME/.sitelink_patch_backups/serverside_$STAMP"

# ═════════════════════════════════════════════════════════════════════════════
# 1) BACKEND helper module
# ═════════════════════════════════════════════════════════════════════════════
mkdir -p "$ROOT/backend/app/services"
cat > "$ROOT/backend/app/services/list_query.py" <<'PYEOF'
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
PYEOF
echo "    wrote backend/app/services/list_query.py"

# ═════════════════════════════════════════════════════════════════════════════
# 2) FRONTEND new files
# ═════════════════════════════════════════════════════════════════════════════
mkdir -p "$ROOT/frontend/src/api" "$ROOT/frontend/src/hooks" "$ROOT/frontend/src/components/shared"

cat > "$ROOT/frontend/src/api/listing.ts" <<'TSEOF'
import api from './client'

export interface DistinctItem {
  value: string | number | boolean | null
  count: number
}
export interface DistinctResult {
  values: DistinctItem[]
  total_distinct: number
}
export interface Paged<T> {
  items: T[]
  total: number
}

/** GET a list endpoint and read the total from the X-Total-Count header. */
export async function pagedGet<T>(
  url: string, params?: Record<string, unknown>,
): Promise<Paged<T>> {
  const r = await api.get<T[]>(url, { params })
  const h = Number((r.headers as any)['x-total-count'])
  return { items: r.data, total: Number.isFinite(h) ? h : r.data.length }
}

export const distinctGet = (
  base: string, column: string, params?: Record<string, unknown>,
) =>
  api.get<DistinctResult>(`${base}/distinct/${encodeURIComponent(column)}`, { params })
     .then((r) => r.data)

export const idsGet = (base: string, params?: Record<string, unknown>) =>
  api.get<{ ids: number[]; total: number }>(`${base}/ids`, { params })
     .then((r) => r.data.ids)
TSEOF
echo "    wrote frontend/src/api/listing.ts"

cat > "$ROOT/frontend/src/components/shared/SiteSelect.tsx" <<'TSEOF'
/**
 * SiteSelect – searchable site picker (server-side search, 30 results at a time).
 * Replaces loading every site into the cell form.
 * Works as a controlled antd <Form.Item> child (value / onChange).
 */
import React, { useEffect, useMemo, useRef, useState } from 'react'
import { Select, Spin } from 'antd'
import { getSites, getSite } from '@/api/sites'
import type { Site } from '@/types'

interface Props {
  value?: number
  onChange?: (value: number | undefined) => void
  onSiteChange?: (site: Site | undefined) => void
  disabled?: boolean
  placeholder?: string
}

export default function SiteSelect({
  value, onChange, onSiteChange, disabled,
  placeholder = 'Gõ tên site để tìm...',
}: Props) {
  const [options,  setOptions]  = useState<Site[]>([])
  const [selected, setSelected] = useState<Site | undefined>()
  const [loading,  setLoading]  = useState(false)
  const reqRef   = useRef(0)
  const timerRef = useRef<number | undefined>(undefined)

  const search = (text: string, delay = 250) => {
    window.clearTimeout(timerRef.current)
    timerRef.current = window.setTimeout(async () => {
      const id = ++reqRef.current
      setLoading(true)
      try {
        const rows = await getSites({
          search: text.trim() || undefined, limit: 30,
          sort_by: 'site_name', sort_dir: 'asc',
        })
        if (id === reqRef.current) setOptions(rows)
      } catch { /* keep old options */ }
      finally { if (id === reqRef.current) setLoading(false) }
    }, delay)
  }

  useEffect(() => { search('', 0); return () => window.clearTimeout(timerRef.current) }, [])

  // make sure the current value can be displayed (edit mode)
  useEffect(() => {
    if (!value) { setSelected(undefined); return }
    if (selected?.id === value) return
    getSite(value).then(setSelected).catch(() => {})
  }, [value])

  const list = useMemo(() => {
    const m = new Map<number, Site>()
    if (selected) m.set(selected.id, selected)
    options.forEach((s) => m.set(s.id, s))
    return [...m.values()]
  }, [options, selected])

  return (
    <Select
      showSearch allowClear filterOption={false}
      disabled={disabled} placeholder={placeholder}
      value={value} loading={loading}
      onSearch={(t) => search(t)}
      notFoundContent={loading ? <Spin size="small" /> : 'Không tìm thấy site'}
      onChange={(v: number | undefined) => {
        const s = list.find((x) => x.id === v)
        setSelected(s)
        onChange?.(v)
        onSiteChange?.(s)
      }}
      options={list.map((s) => ({ value: s.id, label: s.site_name }))}
    />
  )
}
TSEOF
echo "    wrote frontend/src/components/shared/SiteSelect.tsx"

cat > "$ROOT/frontend/src/hooks/useServerTable.tsx" <<'TSEOF'
/**
 * useServerTable.tsx
 *
 * Server-side paging / sorting / Excel-style column filters for <Table>.
 *
 *   const sq = useServerQuery([...top-bar filter values])      // before `load`
 *   ...load() merges sq.params, calls api.listPaged, then sq.onLoaded(total, params)
 *   const { columns, dataSource, onChange, filterBar, clearAll } =
 *     useServerColumns(columns, data, sq, { fetchDistinct, fetchIds, selectedIds, setSelectedIds })
 *   <Table pagination={sq.pagination('cells')} ... />
 */
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Button, Checkbox, Divider, Input, Select, Space, Spin, Tag, Typography } from 'antd'
import {
  FilterFilled, SearchOutlined, SortAscendingOutlined, SortDescendingOutlined,
} from '@ant-design/icons'
import type { ColumnsType, ColumnType, TablePaginationConfig } from 'antd/es/table'
import type {
  FilterDropdownProps, FilterValue, SorterResult, SortOrder, TableCurrentDataSource,
} from 'antd/es/table/interface'
import type { DistinctResult } from '@/api/listing'

export const EMPTY = '__SL_EMPTY__'
export const PAGE_SIZE_ALL = 0
export const ALL_LIMIT = 5000            // "Tất cả" = up to this many rows per page
const PAGE_SIZES = [10, 20, 50, 100, 200, 500]
const MAX_VALUES = 200
const PAGING_KEYS = ['skip', 'limit', 'sort_by', 'sort_dir', 'filters']
const collator = new Intl.Collator('vi', { numeric: true, sensitivity: 'base' })

export interface ColumnFilter { contains?: string; in?: string[]; not_in?: string[] }
type FilterMap = Record<string, ColumnFilter>
type SortState = { field: string; order: 'ascend' | 'descend' } | null

// ─────────────────────────────────────────────────────────────────────────────
// query state
// ─────────────────────────────────────────────────────────────────────────────
export function useServerQuery(resetDeps: unknown[] = [], defaultPageSize = 50) {
  const [filters,  setFilters]   = useState<FilterMap>({})
  const [sort,     setSortState] = useState<SortState>(null)
  const [page,     setPage]      = useState(1)
  const [pageSize, setPageSize]  = useState(defaultPageSize)
  const [total,    setTotal]     = useState(0)
  const ticketRef = useRef(0)
  const baseRef   = useRef<Record<string, unknown>>({})

  const limit = pageSize === PAGE_SIZE_ALL ? ALL_LIMIT : pageSize
  const filtersJson = useMemo(
    () => (Object.keys(filters).length ? JSON.stringify(filters) : undefined),
    [filters],
  )

  const params = useMemo(() => {
    const p: Record<string, unknown> = { skip: (page - 1) * limit, limit }
    if (sort) { p.sort_by = sort.field; p.sort_dir = sort.order === 'ascend' ? 'asc' : 'desc' }
    if (filtersJson) p.filters = filtersJson
    return p
  }, [page, limit, sort, filtersJson])

  // top-bar filter changed => back to page 1
  const depsKey = JSON.stringify(resetDeps)
  const mounted = useRef(false)
  useEffect(() => {
    if (!mounted.current) { mounted.current = true; return }
    setPage(1)
  }, [depsKey])

  // stale-response guard
  const nextTicket = useCallback(() => ++ticketRef.current, [])
  const isCurrent  = useCallback((t: number) => t === ticketRef.current, [])

  const onLoaded = useCallback((t: number, used: Record<string, unknown>) => {
    setTotal(t)
    const rest: Record<string, unknown> = {}
    Object.keys(used).forEach((k) => { if (!PAGING_KEYS.includes(k)) rest[k] = used[k] })
    baseRef.current = rest                                    // top-bar params only
    setPage((p) => Math.min(p, Math.max(1, Math.ceil(t / limit))))   // page vanished
  }, [limit])

  const setFilter = useCallback((field: string, spec: ColumnFilter | null) => {
    setFilters((prev) => {
      const n = { ...prev }
      if (spec) n[field] = spec; else delete n[field]
      return n
    })
    setPage(1)
  }, [])
  const clearFilters = useCallback(() => { setFilters({}); setPage(1) }, [])
  const setSort = useCallback((s: SortState) => { setSortState(s); setPage(1) }, [])

  const pagination = (unit = 'bản ghi'): TablePaginationConfig => ({
    current: page,
    pageSize: limit,
    total,
    showSizeChanger: false,
    onChange: (p) => setPage(p),
    showTotal: (t) => (
      <Space size={12}>
        <span>{t.toLocaleString('vi-VN')} {unit}</span>
        <Select
          size="small" value={pageSize} style={{ width: 190 }}
          onChange={(s: number) => { setPageSize(s); setPage(1) }}
          options={[
            ...PAGE_SIZES.map((n) => ({ value: n, label: `${n} / trang` })),
            { value: PAGE_SIZE_ALL, label: `Tất cả (tối đa ${ALL_LIMIT})` },
          ]}
        />
      </Space>
    ),
  })

  return {
    params, filters, filtersJson, sort, total, baseRef,
    nextTicket, isCurrent, onLoaded,
    setFilter, clearFilters, setSort, pagination,
  }
}
export type ServerQuery = ReturnType<typeof useServerQuery>

// ─────────────────────────────────────────────────────────────────────────────
// the header dropdown
// ─────────────────────────────────────────────────────────────────────────────
interface PanelProps {
  field: string
  filter?: ColumnFilter
  sortOrder: SortOrder
  onSort: (o: 'ascend' | 'descend' | null) => void
  onApply: (f: ColumnFilter | null) => void
  fetchDistinct: (field: string, params: Record<string, unknown>) => Promise<DistinctResult>
  getParams: () => Record<string, unknown>
  dd: FilterDropdownProps
}

function ServerFilterPanel({
  field, filter, sortOrder, onSort, onApply, fetchDistinct, getParams, dd,
}: PanelProps) {
  const { confirm, visible } = dd
  const [search,  setSearch]  = useState('')
  const [base,    setBase]    = useState<'all' | 'none'>('all')
  const [toggled, setToggled] = useState<Set<string>>(new Set())
  const [res,     setRes]     = useState<DistinctResult | null>(null)
  const [loading, setLoading] = useState(false)
  const reqRef = useRef(0)

  // (re)initialise from the active filter every time the panel opens
  useEffect(() => {
    if (!visible) return
    if (filter?.in) {
      setBase('none'); setToggled(new Set(filter.in)); setSearch('')
    } else {
      setBase('all'); setToggled(new Set(filter?.not_in ?? [])); setSearch(filter?.contains ?? '')
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible])

  // values + counts from the server (other columns' filters applied)
  useEffect(() => {
    if (!visible) return
    const id = ++reqRef.current
    setLoading(true)
    const t = window.setTimeout(() => {
      fetchDistinct(field, { ...getParams(), q: search.trim() || undefined, limit: MAX_VALUES })
        .then((r) => { if (id === reqRef.current) setRes(r) })
        .catch(() => { if (id === reqRef.current) setRes({ values: [], total_distinct: 0 }) })
        .finally(() => { if (id === reqRef.current) setLoading(false) })
    }, search ? 250 : 0)
    return () => window.clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible, search])

  const items = useMemo(() => {
    const list = (res?.values ?? []).map((v) => {
      const empty = v.value === null || v.value === undefined || v.value === ''
      return {
        key: empty ? EMPTY : String(v.value),
        label: empty ? '(Trống)'
          : typeof v.value === 'boolean' ? (v.value ? 'x (Có)' : '- (Không)')
          : String(v.value),
        count: v.count,
      }
    })
    return list.sort((a, b) =>
      a.key === EMPTY ? 1 : b.key === EMPTY ? -1 : collator.compare(a.label, b.label))
  }, [res])

  const isChecked = (k: string) => (base === 'all' ? !toggled.has(k) : toggled.has(k))
  const allChecked  = items.length > 0 && items.every((i) => isChecked(i.key))
  const someChecked = items.some((i) => isChecked(i.key))
  const searching   = search.trim() !== ''

  const toggleOne = (k: string, on: boolean) => {
    if (isChecked(k) === on) return
    setToggled((prev) => {
      const n = new Set(prev)
      if (n.has(k)) n.delete(k); else n.add(k)
      return n
    })
  }
  const toggleAll = (on: boolean) => { setBase(on ? 'all' : 'none'); setToggled(new Set()) }
  const onSearch  = (v: string)   => { setSearch(v); setBase('all'); setToggled(new Set()) }

  const apply = () => {
    if (base === 'all') {
      const spec: ColumnFilter = {}
      if (searching) spec.contains = search.trim()
      if (toggled.size) spec.not_in = [...toggled]
      onApply(Object.keys(spec).length ? spec : null)
    } else {
      onApply({ in: [...toggled] })
    }
    confirm({ closeDropdown: true })
  }
  const reset  = () => { onApply(null); confirm({ closeDropdown: true }) }
  const sortBy = (o: 'ascend' | 'descend') => {
    onSort(sortOrder === o ? null : o)
    confirm({ closeDropdown: true })
  }

  return (
    <div style={{ padding: 8, width: 290 }} onKeyDown={(e) => e.stopPropagation()}>
      <Button block size="small" icon={<SortAscendingOutlined />}
              type={sortOrder === 'ascend' ? 'primary' : 'text'}
              style={{ textAlign: 'left' }} onClick={() => sortBy('ascend')}>
        Sắp xếp A → Z (tăng dần)
      </Button>
      <Button block size="small" icon={<SortDescendingOutlined />}
              type={sortOrder === 'descend' ? 'primary' : 'text'}
              style={{ textAlign: 'left' }} onClick={() => sortBy('descend')}>
        Sắp xếp Z → A (giảm dần)
      </Button>
      <Divider style={{ margin: '6px 0' }} />

      <Input size="small" allowClear prefix={<SearchOutlined />} placeholder="Tìm kiếm..."
             value={search} onChange={(e) => onSearch(e.target.value)} />

      <div style={{ marginTop: 8, border: '1px solid #f0f0f0', borderRadius: 4 }}>
        <div style={{ padding: '4px 8px', borderBottom: '1px solid #f0f0f0', background: '#fafafa' }}>
          <Checkbox checked={allChecked} indeterminate={!allChecked && someChecked}
                    disabled={items.length === 0}
                    onChange={(e) => toggleAll(e.target.checked)}>
            {searching ? 'Chọn tất cả kết quả tìm kiếm' : '(Chọn tất cả)'}
          </Checkbox>
        </div>
        <div style={{ maxHeight: 240, overflowY: 'auto', padding: '4px 8px', minHeight: 40 }}>
          {loading && <div style={{ textAlign: 'center', padding: 8 }}><Spin size="small" /></div>}
          {!loading && items.map((i) => (
            <div key={i.key} style={{ padding: '2px 0' }}>
              <Checkbox checked={isChecked(i.key)} onChange={(e) => toggleOne(i.key, e.target.checked)}>
                <span style={{ whiteSpace: 'normal', wordBreak: 'break-word' }}>{i.label}</span>
                <span style={{ color: '#999', fontSize: 11, marginLeft: 4 }}>({i.count})</span>
              </Checkbox>
            </div>
          ))}
          {!loading && items.length === 0 && (
            <div style={{ color: '#999', padding: 8, textAlign: 'center' }}>Không có giá trị</div>
          )}
          {!loading && res && res.total_distinct > items.length && (
            <div style={{ color: '#999', fontSize: 11, padding: '4px 0' }}>
              Hiển thị {items.length}/{res.total_distinct} giá trị – nhập từ khóa rồi bấm OK để lọc "chứa"
            </div>
          )}
        </div>
      </div>

      <div style={{ marginTop: 8, display: 'flex', justifyContent: 'flex-end', gap: 8 }}>
        <Button size="small" onClick={reset}>Xóa lọc</Button>
        <Button size="small" type="primary" onClick={apply}
                disabled={base === 'none' && toggled.size === 0}>OK</Button>
      </div>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// columns decorator
// ─────────────────────────────────────────────────────────────────────────────
export interface ServerColumnsOptions {
  fetchDistinct: (field: string, params: Record<string, unknown>) => Promise<DistinctResult>
  fetchIds: (params: Record<string, unknown>) => Promise<number[]>
  selectedIds: number[]
  setSelectedIds: (ids: number[]) => void
  unit?: string
}

function fieldOf<T>(c: ColumnsType<T>[number]): string | null {
  if ((c as any).children) return null
  const d = (c as ColumnType<T>).dataIndex
  return typeof d === 'string' ? d : null
}

const describe = (f: ColumnFilter) => {
  const parts: string[] = []
  if (f.contains) parts.push(`chứa "${f.contains}"`)
  if (f.in) parts.push(`${f.in.length} giá trị`)
  if (f.not_in?.length) parts.push(`bỏ ${f.not_in.length}`)
  return parts.join(', ')
}

export function useServerColumns<T extends object>(
  columns: ColumnsType<T>,
  data: T[],
  sq: ServerQuery,
  opts: ServerColumnsOptions,
) {
  const [busy, setBusy] = useState(false)
  const unit = opts.unit ?? 'dòng'

  const getParams = () => ({
    ...sq.baseRef.current,
    ...(sq.filtersJson ? { filters: sq.filtersJson } : {}),
  })

  const titleByField: Record<string, string> = {}

  const mapped = columns.map((c) => {
    const field = fieldOf(c)
    if (!field) return c
    const col  = c as ColumnType<T>
    const spec = sq.filters[field]
    const sortOrder: SortOrder = sq.sort && sq.sort.field === field ? sq.sort.order : null
    const title = typeof col.title === 'string' ? col.title : field
    titleByField[field] = title.length > 30 ? title.slice(0, 30) + '…' : title
    const minW = typeof col.title === 'string' ? Math.min(col.title.length * 8 + 64, 180) : 0
    return {
      ...col,
      key: field,
      width: typeof col.width === 'number' ? Math.max(col.width, minW) : col.width,
      sorter: true,
      sortOrder,
      sortDirections: ['ascend', 'descend'] as SortOrder[],
      filteredValue: spec ? ['1'] : null,
      onFilter: undefined,
      defaultSortOrder: undefined,
      defaultFilteredValue: undefined,
      filterDropdown: (dd: FilterDropdownProps) => (
        <ServerFilterPanel
          field={field} filter={spec} sortOrder={sortOrder} dd={dd}
          onSort={(o) => sq.setSort(o ? { field, order: o } : null)}
          onApply={(f) => sq.setFilter(field, f)}
          fetchDistinct={opts.fetchDistinct}
          getParams={getParams}
        />
      ),
    } as ColumnType<T>
  })

  // <Table onChange>: only header-click sorting needs handling
  const onChange = (
    _p: TablePaginationConfig,
    _f: Record<string, FilterValue | null>,
    s: SorterResult<T> | SorterResult<T>[],
    extra: TableCurrentDataSource<T>,
  ) => {
    if (extra.action !== 'sort') return
    const one = Array.isArray(s) ? s[0] : s
    const f = one && one.order ? String(one.columnKey ?? one.field ?? '') : ''
    sq.setSort(f ? { field: f, order: one.order as 'ascend' | 'descend' } : null)
  }

  const selectAllMatching = async () => {
    setBusy(true)
    try {
      const ids = await opts.fetchIds(getParams())
      opts.setSelectedIds(Array.from(new Set([...opts.selectedIds, ...ids])))
    } finally { setBusy(false) }
  }

  const active = Object.entries(sq.filters)

  const filterBar = (
    <div style={{
      background: active.length ? '#fffbe6' : '#fafafa',
      border: `1px solid ${active.length ? '#ffe58f' : '#f0f0f0'}`,
      borderRadius: 6, padding: '6px 12px', marginBottom: 12,
      display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap',
    }}>
      <Typography.Text strong>{sq.total.toLocaleString('vi-VN')} {unit} khớp</Typography.Text>
      <Button size="small" loading={busy} disabled={sq.total === 0} onClick={selectAllMatching}>
        Chọn tất cả {sq.total.toLocaleString('vi-VN')} kết quả
      </Button>
      {opts.selectedIds.length > 0 && (
        <>
          <Typography.Text type="secondary">· Đã chọn {opts.selectedIds.length.toLocaleString('vi-VN')}</Typography.Text>
          <Button size="small" type="link" onClick={() => opts.setSelectedIds([])}>Bỏ chọn tất cả</Button>
        </>
      )}
      {active.length > 0 && (
        <>
          <FilterFilled style={{ color: '#faad14' }} />
          {active.map(([k, f]) => (
            <Tag key={k} closable style={{ margin: 0 }}
                 onClose={(e) => { e.preventDefault(); sq.setFilter(k, null) }}>
              {titleByField[k] ?? k}: {describe(f)}
            </Tag>
          ))}
          <Button size="small" type="link" onClick={sq.clearFilters}>Xóa bộ lọc cột</Button>
        </>
      )}
      <Typography.Text type="secondary" style={{ fontSize: 12 }}>
        (Xuất file chưa áp dụng bộ lọc cột)
      </Typography.Text>
    </div>
  )

  return {
    columns: mapped as ColumnsType<T>,
    dataSource: data,
    onChange,
    filterBar,
    clearAll: sq.clearFilters,
    activeCount: active.length,
  }
}
TSEOF
echo "    wrote frontend/src/hooks/useServerTable.tsx"

# ═════════════════════════════════════════════════════════════════════════════
# 3) PATCH existing files (each file all-or-nothing)
# ═════════════════════════════════════════════════════════════════════════════
python3 - "$ROOT" "$BACKUP_DIR" <<'PYEOF'
import re, sys, shutil
from pathlib import Path

root = Path(sys.argv[1])
bak  = Path(sys.argv[2])
total_fail = 0


class Patch:
    def __init__(self, rel):
        self.rel, self.fail = rel, 0
        p = root / rel
        print(f"--- {rel}")
        if not p.is_file():
            print("  FAIL file not found")
            self.text = self.orig = None
            return
        self.text = self.orig = p.read_text(encoding="utf-8")

    @property
    def ok(self):
        return self.text is not None

    def sub(self, label, pattern, make, flags=0, skip=None, optional=False):
        if skip and skip in self.text:
            print(f"  skip {label} (already applied)")
            return
        ms = list(re.finditer(pattern, self.text, flags))
        if not ms and optional:
            print(f"  skip {label} (not present)")
            return
        if len(ms) != 1:
            self.fail += 1
            print(f"  FAIL {label}: expected 1 match, found {len(ms)}")
            return
        m = ms[0]
        self.text = self.text[:m.start()] + make(m) + self.text[m.end():]
        print(f"  ok   {label}")

    def save(self):
        global total_fail
        total_fail += self.fail
        if self.fail:
            print("  => NOT saved (a patch failed; file left untouched)")
            return
        if self.text != self.orig:
            dst = bak / self.rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(root / self.rel, dst)
            (root / self.rel).write_text(self.text, encoding="utf-8")
            print("  => SAVED (backup made)")
        else:
            print("  => no change")


# ═════════ BACKEND routers ═════════
BACKEND = [
    ("backend/app/api/routes/cells_3g.py", "Cell3G", "cell"),
    ("backend/app/api/routes/cells_4g.py", "Cell4G", "cell"),
    ("backend/app/api/routes/cells_5g.py", "Cell5G", "cell"),
    ("backend/app/api/routes/sites.py",    "Site",   "site"),
]
for rel, model, kind in BACKEND:
    p = Patch(rel)
    if not p.ok:
        total_fail += 1
        continue

    p.sub("import Response",
          r"^from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File[ \t]*$",
          lambda m: m.group(0) + ", Response", re.M,
          skip="UploadFile, File, Response")

    p.sub("import list_query helpers",
          r"^from app\.models\.site import Site[ \t]*$",
          lambda m: m.group(0) + "\nfrom app.services.list_query import "
                    "apply_column_filters, apply_sort, register_listing_routes",
          re.M, skip="from app.services.list_query")

    p.sub("register /ids and /distinct routes",
          r"^router = APIRouter\(\)[ \t]*$",
          lambda m, model=model, kind=kind: m.group(0) +
              '\nregister_listing_routes(router, %s, "%s")  # GET /ids, GET /distinct/{column}' % (model, kind),
          re.M, skip="register_listing_routes(router")

    p.sub("list: sort_by / sort_dir / filters params",
          r"(def list_(?:cells|sites)\(.*?)(\n[ \t]*db: Session = Depends\(get_db\))",
          lambda m: m.group(1) +
              '\n    sort_by:  Optional[str] = Query(None),'
              '\n    sort_dir: str           = Query("asc"),'
              '\n    filters:  Optional[str] = Query(None),' + m.group(2),
          re.S, skip="filters:  Optional[str] = Query(None)")

    p.sub("list: response param",
          r"(def list_(?:cells|sites)\()(\s*)",
          lambda m: m.group(1) + m.group(2) + "response: Response," + m.group(2),
          skip="response: Response,")

    p.sub("list: column filters + total header + sort",
          r"^([ \t]*)return q\.offset\(skip\)\.limit\(limit\)\.all\(\)[ \t]*$",
          lambda m, model=model: (
              f"{m.group(1)}q = apply_column_filters(q, {model}, filters)\n"
              f"{m.group(1)}response.headers[\"X-Total-Count\"] = str(q.count())\n"
              f"{m.group(1)}q = apply_sort(q, {model}, sort_by, sort_dir)\n"
              f"{m.group(1)}return q.offset(skip).limit(limit).all()"),
          re.M, skip="X-Total-Count")
    p.save()

# ═════════ FRONTEND api layer ═════════
p = Patch("frontend/src/api/cells.ts")
if p.ok:
    p.sub("import listing helpers",
          r"^import api from './client'[ \t]*$",
          lambda m: m.group(0) + "\nimport { pagedGet, idsGet, distinctGet } from './listing'",
          re.M, skip="from './listing'")
    p.sub("listPaged / ids / distinct",
          r"^([ \t]*)get: \(id: number\) =>",
          lambda m: (
              f"{m.group(1)}listPaged: (params?: Record<string, unknown>) =>\n"
              f"{m.group(1)}  pagedGet<T>(`/api/v1/cells-${{tech}}/`, params),\n\n"
              f"{m.group(1)}ids: (params?: Record<string, unknown>) =>\n"
              f"{m.group(1)}  idsGet(`/api/v1/cells-${{tech}}`, params),\n\n"
              f"{m.group(1)}distinct: (column: string, params?: Record<string, unknown>) =>\n"
              f"{m.group(1)}  distinctGet(`/api/v1/cells-${{tech}}`, column, params),\n\n"
              f"{m.group(0)}"),
          re.M, skip="listPaged:")
    p.save()
else:
    total_fail += 1

p = Patch("frontend/src/api/sites.ts")
if p.ok:
    p.sub("import listing helpers",
          r"^import api from './client'[ \t]*$",
          lambda m: m.group(0) + "\nimport { pagedGet, idsGet, distinctGet } from './listing'",
          re.M, skip="from './listing'")
    if "getSitesPaged" not in p.text:
        p.text = p.text.rstrip("\n") + """

// ── server-side listing (paging / column filters / select-all) ───────────────
export const getSitesPaged = (params?: Record<string, unknown>) =>
  pagedGet<Site>('/api/v1/sites/', params)

export const getSiteIds = (params?: Record<string, unknown>) =>
  idsGet('/api/v1/sites', params)

export const getSiteDistinct = (column: string, params?: Record<string, unknown>) =>
  distinctGet('/api/v1/sites', column, params)
"""
        print("  ok   append getSitesPaged / getSiteIds / getSiteDistinct")
    else:
        print("  skip append sites helpers (already applied)")
    p.save()
else:
    total_fail += 1

# ═════════ FRONTEND: shared edits ═════════
def common_edits(p, topbar_deps, call_tmpl):
    # hook import swap
    p.sub("swap hook import",
          r"^import \{ useExcelColumns \} from '@/hooks/useExcelColumns'[ \t]*$",
          lambda m: "import { useServerQuery, useServerColumns } from '@/hooks/useServerTable'"
                    + p.extra_import,
          re.M, skip="@/hooks/useServerTable")
    p.sub("drop old pagination import",
          r"^import \{ useTablePagination \} from '@/hooks/useTablePagination'[ \t]*\n",
          lambda m: "", re.M, optional=True)

    # query state (before load)
    p.sub("useServerQuery",
          r"^([ \t]*)const load = useCallback\(",
          lambda m: f"{m.group(1)}const sq = useServerQuery({topbar_deps})\n\n{m.group(0)}",
          re.M, skip="useServerQuery(")

    # load(): params
    p.sub("load: use server params",
          r"const params: Record<string, unknown> = \{ limit: (?:1000|500) \}",
          lambda m: "const params: Record<string, unknown> = { ...sq.params }",
          skip="{ ...sq.params }")

    # pagination object
    p.sub("pagination from server query",
          r"^([ \t]*)const \{ pagination \} = useTablePagination\([^\n]*\)[ \t]*$",
          lambda m: f"{m.group(1)}const pagination = sq.pagination('{p.unit_plural}')",
          re.M, skip="sq.pagination(")

    # excel columns -> server columns
    p.sub("useServerColumns",
          r"useExcelColumns\(columns, (\w+), \{ onFilterChange: \(\) => setSelectedIds\(\[\]\) \}\)",
          lambda m: call_tmpl.replace("__VAR__", m.group(1)),
          skip="useServerColumns(columns")

    # selection across pages
    p.sub("rowSelection keeps keys across pages",
          r"selectedRowKeys: selectedIds,",
          lambda m: "selectedRowKeys: selectedIds,\n    preserveSelectedRowKeys: true,",
          skip="preserveSelectedRowKeys")


# ═════════ Cell pages ═════════
CELL_CALL = """useServerColumns(columns, __VAR__, sq, {
      fetchDistinct: (field, p) => __API__.distinct(field, p),
      fetchIds:      (p) => __API__.ids(p),
      selectedIds, setSelectedIds, unit: 'cell',
    })"""

VENDOR_TMPL = """__I__const [vendorOptions, setVendorOptions] = useState<string[]>([])
__I__useEffect(() => {
__I__  __API__.distinct('vendor', { limit: 200 })
__I__    .then((r) => setVendorOptions(
__I__      r.values.map((v) => v.value)
__I__       .filter((v): v is string => typeof v === 'string' && v !== '')))
__I__    .catch(() => {})
__I__}, [])"""

SITE_ITEM = """<Form.Item name="site_id" label="Site" rules={[{ required: !editing }]}>
                <SiteSelect
                  disabled={Boolean(editing)}
                  onSiteChange={(s) => { if (s) form.setFieldValue('site_name', s.site_name) }}
                />
              </Form.Item>"""

for t in ("3", "4", "5"):
    api = f"cells{t}gApi"
    p = Patch(f"frontend/src/pages/cells/Cells{t}GPage.tsx")
    if not p.ok:
        total_fail += 1
        continue
    p.extra_import = "\nimport SiteSelect from '@/components/shared/SiteSelect'"
    p.unit_plural = "cells"

    common_edits(p, "[search, cellNameOld, mien, tinh, phuongXa, vendor]",
                 CELL_CALL.replace("__API__", api))

    p.sub("load: fetch page + total",
          r"setData\(await %s\.list\(params\)\)" % api,
          lambda m, api=api: (
              "const ticket = sq.nextTicket()\n"
              f"      const res = await {api}.listPaged(params)\n"
              "      if (!sq.isCurrent(ticket)) return\n"
              "      setData(res.items)\n"
              "      sq.onLoaded(res.total, params)"),
          skip=".listPaged(params)")

    p.sub("load: depends on server params",
          r"\}, \[search, cellNameOld, mien, tinh, phuongXa, vendor\]\)",
          lambda m: "}, [search, cellNameOld, mien, tinh, phuongXa, vendor, sq.params])",
          skip="vendor, sq.params])")

    p.sub("vendor options from server",
          r"^([ \t]*)const vendorOptions =[^\n]*$",
          lambda m, api=api: VENDOR_TMPL.replace("__I__", m.group(1)).replace("__API__", api),
          re.M, skip="setVendorOptions")

    p.sub("stop loading every site (limit 100000)",
          r"^[ \t]*getSites\(\{ limit: 100000 \}\)\.then\(setSites\)[ \t]*\n",
          lambda m: "", re.M, optional=True)

    # lookups must not reload on every page/sort/filter change
    p.sub("split data-load effect from one-time lookups",
          r"(useEffect\(\(\) => \{)(\s*)load\(\)(.*?)\}, \[load\]\)",
          lambda m: ("useEffect(() => { load() }, [load])\n\n  useEffect(() => {"
                     + m.group(3) + "}, [])"),
          re.S, skip="useEffect(() => { load() }, [load])")

    p.sub("site picker (server-side search)",
          r'<Form\.Item\s+name="site_id".*?</Form\.Item>',
          lambda m: SITE_ITEM, re.S, skip="<SiteSelect")

    p.sub("export button label", r"Xuất Excel \(\{data\.length\}\)",
          lambda m: "Xuất Excel", optional=True)
    p.sub("export toast", r"Xuất Excel thành công \(\$\{data\.length\} cells\)",
          lambda m: "Xuất Excel thành công", optional=True)
    p.save()

# ═════════ Sites page ═════════
SITE_CALL = """useServerColumns(columns, __VAR__, sq, {
      fetchDistinct: (field, p) => getSiteDistinct(field, p),
      fetchIds:      (p) => getSiteIds(p),
      selectedIds, setSelectedIds, unit: 'site',
    })"""

p = Patch("frontend/src/pages/sites/SitesPage.tsx")
if p.ok:
    p.extra_import = ""
    p.unit_plural = "sites"
    common_edits(p, "[search, siteNameCu, mien, tinh, phuongXa]", SITE_CALL)

    p.sub("import paged helpers",
          r"getSites, deleteSite,",
          lambda m: "getSites, getSitesPaged, getSiteIds, getSiteDistinct, deleteSite,",
          skip="getSitesPaged")

    p.sub("load: fetch page + total",
          r"^([ \t]*)getSites\(params\)\s*\n[ \t]*\.then\(setSites\)",
          lambda m: (
              f"{m.group(1)}const ticket = sq.nextTicket()\n"
              f"{m.group(1)}getSitesPaged(params)\n"
              f"{m.group(1)}  .then((res) => {{\n"
              f"{m.group(1)}    if (!sq.isCurrent(ticket)) return\n"
              f"{m.group(1)}    setSites(res.items)\n"
              f"{m.group(1)}    sq.onLoaded(res.total, params)\n"
              f"{m.group(1)}  }})"),
          re.M, skip="getSitesPaged(params)")

    p.sub("load: depends on server params",
          r"\}, \[search, siteNameCu, mien, tinh, phuongXa\]\)",
          lambda m: "}, [search, siteNameCu, mien, tinh, phuongXa, sq.params])",
          skip="phuongXa, sq.params])")

    p.sub("KMZ label",   r"Xuất KMZ \(\{sites\.length\}\)",   lambda m: "Xuất KMZ",   optional=True)
    p.sub("Excel label", r"Xuất Excel \(\{sites\.length\}\)", lambda m: "Xuất Excel", optional=True)
    p.sub("Excel toast", r"Xuất Excel thành công \(\$\{sites\.length\} sites\)",
          lambda m: "Xuất Excel thành công", optional=True)
    p.sub("KMZ toast",   r"Xuất KMZ thành công \(\$\{sites\.length\} sites\)",
          lambda m: "Xuất KMZ thành công", optional=True)
    p.save()
else:
    total_fail += 1

print()
print(f"Summary: {total_fail} failed edit(s)." if total_fail else "Summary: all edits OK.")
sys.exit(1 if total_fail else 0)
PYEOF
PY_RC=$?

# ═════════════════════════════════════════════════════════════════════════════
# 4) Verification
# ═════════════════════════════════════════════════════════════════════════════
echo "==> Python syntax check"
python3 -m py_compile \
  "$ROOT/backend/app/services/list_query.py" \
  "$ROOT/backend/app/api/routes/cells_3g.py" \
  "$ROOT/backend/app/api/routes/cells_4g.py" \
  "$ROOT/backend/app/api/routes/cells_5g.py" \
  "$ROOT/backend/app/api/routes/sites.py" && echo "    OK"

echo "==> Verification (each count should be 1, 'old limit' should be 0)"
printf "    %-44s %s\n" "file" "query / columns / pagination / paged-fetch / old-limit"
for f in frontend/src/pages/cells/Cells3GPage.tsx frontend/src/pages/cells/Cells4GPage.tsx \
         frontend/src/pages/cells/Cells5GPage.tsx frontend/src/pages/sites/SitesPage.tsx; do
  a=$(grep -c "useServerQuery(" "$ROOT/$f")
  b=$(grep -c "useServerColumns(columns" "$ROOT/$f")
  c=$(grep -c "sq.pagination(" "$ROOT/$f")
  d=$(grep -cE "listPaged\(params\)|getSitesPaged\(params\)" "$ROOT/$f")
  e=$(grep -cE "limit: (1000|500|100000)" "$ROOT/$f")
  printf "    %-44s %s / %s / %s / %s / %s\n" "$f" "$a" "$b" "$c" "$d" "$e"
done
echo "==> Backend routes patched (expect 1 each):"
grep -c "X-Total-Count" "$ROOT"/backend/app/api/routes/{cells_3g,cells_4g,cells_5g,sites}.py

echo "==> Hard-coded caps still in the frontend (not touched by this script):"
grep -rnE --include=*.ts --include=*.tsx "limit:\s*[0-9]{3,}" "$ROOT/frontend/src" 2>/dev/null \
  | sed "s#$ROOT/##" | sed 's/^/    /'
echo "    (send me the export backend + these pages if you want them handled too)"

if [ "${CHECK_TS:-0}" = "1" ] && [ -d "$ROOT/frontend/node_modules" ]; then
  echo "==> TypeScript check"
  (cd "$ROOT/frontend" && npx --no-install tsc --noEmit) || echo "    tsc reported issues (see above)"
fi

echo "==> git status of $ROOT"
if [ $IS_GIT -eq 1 ]; then
  git -C "$ROOT" status --short
  git -C "$ROOT" diff --stat
fi
echo "    backups (if any): $BACKUP_DIR"

if [ "$PY_RC" -ne 0 ]; then
  echo; echo "!! Some edits FAILED (see FAIL lines). Send me those lines."
  exit 1
fi

cat <<EOF

==> Done. Rebuild BOTH backend and frontend, then hard-refresh (Ctrl+F5):
      docker compose up -d --build
    No database migration is needed.
    Optional type check first:
      CHECK_TS=1 bash update_server_side.sh
EOF