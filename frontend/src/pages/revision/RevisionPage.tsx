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
