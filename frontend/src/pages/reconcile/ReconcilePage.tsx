/**
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
