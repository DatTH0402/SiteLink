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
