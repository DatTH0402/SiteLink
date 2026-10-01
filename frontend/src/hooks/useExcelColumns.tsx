/**
 * useExcelColumns.tsx
 *
 * Excel-like column filter + sort for an Ant Design <Table> (client-side data).
 *
 *   const { columns: excelColumns, dataSource, onChange, filterBar, clearAll } =
 *     useExcelColumns(columns, data, { onFilterChange: () => setSelectedIds([]) })
 *
 *   {filterBar}
 *   <Table columns={excelColumns} dataSource={dataSource} onChange={onChange} ... />
 *
 * - Every column with a string `dataIndex` gets a header dropdown:
 *   sort A→Z / Z→A, search box, "select all", checklist of distinct values.
 * - Filtering and sorting are done here (not by antd), so we know the filtered
 *   row count, can cascade value lists like Excel, and keep blanks last.
 */
import React, { useEffect, useMemo, useRef, useState } from 'react'
import { Button, Checkbox, Divider, Input, Tag, Typography } from 'antd'
import {
  FilterFilled, SearchOutlined,
  SortAscendingOutlined, SortDescendingOutlined,
} from '@ant-design/icons'
import type { ColumnsType, ColumnType, TablePaginationConfig } from 'antd/es/table'
import type {
  FilterDropdownProps, FilterValue, SorterResult, SortOrder,
  TableCurrentDataSource,
} from 'antd/es/table/interface'

// ── helpers ───────────────────────────────────────────────────────────────────
const EMPTY      = '\u0000__EMPTY__'
const MAX_RENDER = 300
const collator   = new Intl.Collator('vi', { numeric: true, sensitivity: 'base' })

const isBlank = (v: unknown) =>
  v === null || v === undefined || (typeof v === 'string' && v.trim() === '')

const keyOf = (v: unknown): string => {
  if (isBlank(v)) return EMPTY
  if (typeof v === 'boolean') return v ? 'true' : 'false'
  return String(v).trim()
}

/** lower-case, strip Vietnamese accents (so "ha noi" matches "Hà Nội") */
const fold = (s: string) =>
  s.normalize('NFD').replace(/[\u0300-\u036f]/g, '')
   .replace(/đ/g, 'd').replace(/Đ/g, 'D').toLowerCase()

function compareValues(a: unknown, b: unknown): number {
  if (typeof a === 'number' && typeof b === 'number') return a - b
  if (typeof a === 'boolean' && typeof b === 'boolean') return Number(a) - Number(b)
  return collator.compare(String(a), String(b))
}

interface Item { key: string; label: string; count: number; raw: unknown }

function buildItems<T>(rows: T[], field: string): Item[] {
  const map = new Map<string, Item>()
  for (const r of rows) {
    const raw = (r as any)[field]
    const key = keyOf(raw)
    const hit = map.get(key)
    if (hit) { hit.count++; continue }
    map.set(key, {
      key, raw, count: 1,
      label: key === EMPTY ? '(Trống)'
        : typeof raw === 'boolean' ? (raw ? 'x (Có)' : '- (Không)')
        : String(raw).trim(),
    })
  }
  return [...map.values()].sort((a, b) => {
    if (a.key === EMPTY) return 1
    if (b.key === EMPTY) return -1
    return compareValues(a.raw, b.raw)
  })
}

interface FilterSpec { key: string; field: string; set: Set<string> }
type Filters = Record<string, string[] | null>

function applyFilters<T>(rows: T[], specs: FilterSpec[], skipKey?: string): T[] {
  const active = skipKey ? specs.filter((s) => s.key !== skipKey) : specs
  if (!active.length) return rows
  return rows.filter((r) => active.every((s) => s.set.has(keyOf((r as any)[s.field]))))
}

function fieldOf<T>(c: ColumnsType<T>[number]): string | null {
  if ((c as any).children) return null
  const d = (c as ColumnType<T>).dataIndex
  return typeof d === 'string' ? d : null
}
const colKeyOf = <T,>(c: ColumnsType<T>[number], field: string) =>
  String((c as any).key ?? field)

// ── the dropdown panel ───────────────────────────────────────────────────────
interface PanelProps<T> {
  data: T[]
  specs: FilterSpec[]
  colKey: string
  field: string
  sortOrder: SortOrder
  onSort: (o: SortOrder) => void
  dd: FilterDropdownProps
}

function ExcelFilterPanel<T>({ data, specs, colKey, field, sortOrder, onSort, dd }: PanelProps<T>) {
  const { selectedKeys, setSelectedKeys, confirm, visible } = dd

  // values come from rows that pass every OTHER column's filter (like Excel)
  const rows     = useMemo(() => applyFilters(data, specs, colKey), [data, specs, colKey])
  const items    = useMemo(() => buildItems(rows, field), [rows, field])
  const allKeys  = useMemo(() => items.map((i) => i.key), [items])
  const selSig   = (selectedKeys as React.Key[]).join('\u0001')

  const initChecked = () =>
    new Set<string>(selectedKeys.length ? (selectedKeys as React.Key[]).map(String) : allKeys)

  const [checked, setChecked] = useState<Set<string>>(initChecked)
  const [search,  setSearch]  = useState('')

  // reopen / external change (e.g. "clear all") => discard unsaved edits
  useEffect(() => {
    setChecked(initChecked())
    setSearch('')
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible, selSig, allKeys])

  const q     = fold(search.trim())
  const shown = useMemo(
    () => (q ? items.filter((i) => fold(i.label).includes(q)) : items),
    [items, q],
  )
  const rendered   = shown.slice(0, MAX_RENDER)
  const allChecked = shown.length > 0 && shown.every((i) => checked.has(i.key))
  const someChecked = shown.some((i) => checked.has(i.key))
  const validCount = allKeys.filter((k) => checked.has(k)).length

  const onSearch = (v: string) => {
    setSearch(v)
    const qq = fold(v.trim())
    // like Excel: typing selects the matching results
    setChecked(new Set(qq ? items.filter((i) => fold(i.label).includes(qq)).map((i) => i.key) : allKeys))
  }

  const toggleAll = (on: boolean) => {
    const next = new Set(checked)
    shown.forEach((i) => (on ? next.add(i.key) : next.delete(i.key)))
    setChecked(next)
  }
  const toggleOne = (k: string, on: boolean) => {
    const next = new Set(checked)
    on ? next.add(k) : next.delete(k)
    setChecked(next)
  }

  const apply = () => {
    const keys = allKeys.filter((k) => checked.has(k))
    setSelectedKeys(keys.length === allKeys.length ? [] : keys)   // everything ticked = no filter
    confirm({ closeDropdown: true })
  }
  const reset = () => {
    setSelectedKeys([])
    confirm({ closeDropdown: true })
  }
  const sortBy = (o: 'ascend' | 'descend') => {
    onSort(sortOrder === o ? null : o)
    ;(dd as any).close?.()
  }

  return (
    <div style={{ padding: 8, width: 280 }} onKeyDown={(e) => e.stopPropagation()}>
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
                    disabled={shown.length === 0}
                    onChange={(e) => toggleAll(e.target.checked)}>
            {q ? 'Chọn tất cả kết quả tìm kiếm' : '(Chọn tất cả)'}
          </Checkbox>
        </div>
        <div style={{ maxHeight: 240, overflowY: 'auto', padding: '4px 8px' }}>
          {rendered.map((i) => (
            <div key={i.key} style={{ padding: '2px 0' }}>
              <Checkbox checked={checked.has(i.key)}
                        onChange={(e) => toggleOne(i.key, e.target.checked)}>
                <span style={{ whiteSpace: 'normal', wordBreak: 'break-word' }}>{i.label}</span>
                <span style={{ color: '#999', fontSize: 11, marginLeft: 4 }}>({i.count})</span>
              </Checkbox>
            </div>
          ))}
          {shown.length === 0 && (
            <div style={{ color: '#999', padding: 8, textAlign: 'center' }}>Không có giá trị</div>
          )}
          {shown.length > MAX_RENDER && (
            <div style={{ color: '#999', fontSize: 11, padding: '4px 0' }}>
              Hiển thị {MAX_RENDER}/{shown.length} giá trị – nhập từ khóa để thu hẹp
            </div>
          )}
        </div>
      </div>

      <div style={{ marginTop: 8, display: 'flex', justifyContent: 'flex-end', gap: 8 }}>
        <Button size="small" onClick={reset}>Xóa lọc</Button>
        <Button size="small" type="primary" onClick={apply} disabled={validCount === 0}>OK</Button>
      </div>
    </div>
  )
}

// ── the hook ─────────────────────────────────────────────────────────────────
export interface ExcelColumnsOptions {
  /** called when the user changes a column filter (use it to clear row selection) */
  onFilterChange?: () => void
}

export function useExcelColumns<T extends object>(
  columns: ColumnsType<T>,
  data: T[],
  opts: ExcelColumnsOptions = {},
) {
  const [filters, setFilters] = useState<Filters>({})
  const [sort, setSort] = useState<{ key: string; order: Exclude<SortOrder, null> } | null>(null)
  const optsRef = useRef(opts)
  optsRef.current = opts

  // stable signature so memo hooks don't depend on the (always new) columns array
  const fieldSig = columns
    .map((c) => { const f = fieldOf(c); return f ? `${colKeyOf(c, f)}:${f}` : '' })
    .join('|')

  const fieldByKey = useMemo(() => {
    const m: Record<string, string> = {}
    columns.forEach((c) => { const f = fieldOf(c); if (f) m[colKeyOf(c, f)] = f })
    return m
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fieldSig])

  const specs = useMemo<FilterSpec[]>(
    () => Object.entries(filters)
      .filter(([k, v]) => v && v.length && fieldByKey[k])
      .map(([k, v]) => ({ key: k, field: fieldByKey[k], set: new Set(v as string[]) })),
    [filters, fieldByKey],
  )

  const filtered = useMemo(() => applyFilters(data, specs), [data, specs])

  const dataSource = useMemo(() => {
    if (!sort || !fieldByKey[sort.key]) return filtered
    const f   = fieldByKey[sort.key]
    const dir = sort.order === 'ascend' ? 1 : -1
    return [...filtered].sort((a, b) => {
      const va = (a as any)[f], vb = (b as any)[f]
      const ba = isBlank(va),   bb = isBlank(vb)
      if (ba && bb) return 0
      if (ba) return 1            // blanks always last (like Excel)
      if (bb) return -1
      return dir * compareValues(va, vb)
    })
  }, [filtered, sort, fieldByKey])

  const mapped = columns.map((c) => {
    const field = fieldOf(c)
    if (!field) return c
    const key  = colKeyOf(c, field)
    const col  = c as ColumnType<T>
    // leave room for the sort + filter icons in the header
    const minW = typeof col.title === 'string' ? Math.min(col.title.length * 8 + 64, 180) : 0
    const sortOrder: SortOrder = sort && sort.key === key ? sort.order : null
    return {
      ...col,
      key,
      width: typeof col.width === 'number' ? Math.max(col.width, minW) : col.width,
      sorter: true,                       // sorting is done by this hook
      sortOrder,
      sortDirections: ['ascend', 'descend'] as SortOrder[],
      filteredValue: filters[key] ?? null,
      onFilter: undefined,                // filtering is done by this hook
      defaultSortOrder: undefined,
      defaultFilteredValue: undefined,
      filterDropdown: (dd: FilterDropdownProps) => (
        <ExcelFilterPanel<T>
          data={data} specs={specs} colKey={key} field={field}
          sortOrder={sortOrder}
          onSort={(o) => setSort(o ? { key, order: o } : null)}
          dd={dd}
        />
      ),
    } as ColumnType<T>
  })

  // pass this to <Table onChange>
  const onChange = (
    _p: TablePaginationConfig,
    f: Record<string, FilterValue | null>,
    s: SorterResult<T> | SorterResult<T>[],
    extra: TableCurrentDataSource<T>,
  ) => {
    if (extra.action === 'sort') {
      const one = Array.isArray(s) ? s[0] : s
      const k   = one && one.order ? String(one.columnKey ?? one.field ?? '') : ''
      setSort(k ? { key: k, order: one.order as Exclude<SortOrder, null> } : null)
    } else if (extra.action === 'filter') {
      const next: Filters = {}
      Object.entries(f).forEach(([k, v]) => { next[k] = v ? v.map(String) : null })
      setFilters(next)
      optsRef.current.onFilterChange?.()
    }
  }

  const clearAll = () => setFilters({})
  const removeOne = (key: string) => {
    setFilters((prev) => ({ ...prev, [key]: null }))
    optsRef.current.onFilterChange?.()
  }

  const titleByKey: Record<string, string> = {}
  columns.forEach((c) => {
    const f = fieldOf(c)
    if (!f) return
    const t = typeof (c as any).title === 'string' ? ((c as any).title as string) : f
    titleByKey[colKeyOf(c, f)] = t.length > 30 ? t.slice(0, 30) + '…' : t
  })

  const filterBar = specs.length > 0 ? (
    <div style={{
      background: '#fffbe6', border: '1px solid #ffe58f', borderRadius: 6,
      padding: '6px 12px', marginBottom: 12,
      display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap',
    }}>
      <FilterFilled style={{ color: '#faad14' }} />
      <Typography.Text strong>Bộ lọc cột:</Typography.Text>
      {specs.map((s) => (
        <Tag key={s.key} closable style={{ margin: 0 }}
             onClose={(e) => { e.preventDefault(); removeOne(s.key) }}>
          {titleByKey[s.key] ?? s.key} ({s.set.size})
        </Tag>
      ))}
      <Typography.Text type="secondary">· {filtered.length}/{data.length} dòng</Typography.Text>
      <Button size="small" type="link" onClick={clearAll}>Xóa bộ lọc cột</Button>
      <Typography.Text type="secondary" style={{ fontSize: 12 }}>
        (Xuất file chưa áp dụng bộ lọc cột)
      </Typography.Text>
    </div>
  ) : null

  return {
    columns: mapped as ColumnsType<T>,
    dataSource,
    onChange,
    filterBar,
    clearAll,
    activeCount: specs.length,
  }
}
