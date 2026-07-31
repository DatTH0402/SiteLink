/**
 * RevisionPage.tsx – Revision History Viewer
 *
 * Fixes & improvements:
 * 1. All site/cell columns shown in the main table.
 * 2. Rename banners (cell/site name) only shown when that field appears
 *    in changed_fields diff – not based on snapshot field values.
 * 3. Province (Tỉnh) filter added.
 * 4. Table loads automatically on mount and on filter change.
 *    Empty filters → show all records (sorted by time desc).
 */
import React, { useState, useCallback, useEffect } from 'react'
import {
  Typography, Tabs, Input, Button, Table, Tag, Space,
  Row, Col, Badge, Alert, Select, Divider,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  SearchOutlined, ReloadOutlined, HistoryOutlined,
  FileExcelOutlined, FormOutlined,
} from '@ant-design/icons'
import {
  getSiteRevisions,
  getCell3GRevisions,
  getCell4GRevisions,
  getCell5GRevisions,
} from '@/api/revision'
import type { SiteRevision, CellRevisionBase } from '@/api/revision'
import { getTinhList } from '@/api/report'
import type { TinhItem } from '@/types'

// ── constants ─────────────────────────────────────────────────────────────────
const SOURCE_TAG: Record<string, React.ReactNode> = {
  form:  <Tag icon={<FormOutlined />}      color="blue">Form</Tag>,
  excel: <Tag icon={<FileExcelOutlined />} color="green">Excel</Tag>,
}

const boolTag = (v: unknown) =>
  v ? <Tag color="green">x</Tag> : <Tag color="default">-</Tag>

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

// ── SnapshotTable: shows all fields at revision time ──────────────────────────
function SnapshotTable({ rows }: { rows: [string, unknown][] }) {
  return (
    <table style={{ borderCollapse: 'collapse', fontSize: 12, width: '100%' }}>
      <thead>
        <tr style={{ background: '#e6f7ff' }}>
          <th style={{ padding: '4px 8px', border: '1px solid #bae7ff', width: 220 }}>Trường</th>
          <th style={{ padding: '4px 8px', border: '1px solid #bae7ff' }}>Giá trị tại revision</th>
        </tr>
      </thead>
      <tbody>
        {rows.map(([k, v]) => (
          <tr key={k}>
            <td style={{
              padding: '3px 8px', border: '1px solid #f0f0f0',
              fontFamily: 'monospace', fontSize: 11, color: '#555',
            }}>{k}</td>
            <td style={{
              padding: '3px 8px', border: '1px solid #f0f0f0',
              fontFamily: 'monospace',
              color: (v === null || v === undefined || v === '') ? '#ccc' : '#222',
            }}>
              {v === null || v === undefined || v === ''
                ? <em>–</em>
                : typeof v === 'boolean' ? (v ? '✓ Có' : '✗ Không') : String(v)}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

// ── Site snapshot field list ───────────────────────────────────────────────────
function siteSnap(r: SiteRevision): [string, unknown][] {
  return [
    ['site_name', r.site_name], ['site_name_old_ref', r.site_name_old_ref],
    ['site_name_cu', r.site_name_cu], ['mien', r.mien], ['tinh', r.tinh],
    ['phuong_xa', r.phuong_xa], ['site_vip', r.site_vip],
    ['lat', r.lat], ['long', r.long],
    ['tram_2g', r.tram_2g], ['tram_3g', r.tram_3g],
    ['tram_4g', r.tram_4g], ['tram_5g', r.tram_5g],
    ['repeater', r.repeater], ['booster', r.booster],
    ['node_truyen_dan_only', r.node_truyen_dan_only],
    ['tram_phu_song_tsca', r.tram_phu_song_tsca],
    ['phan_loai_tram', r.phan_loai_tram],
    ['moran_3g', r.moran_3g], ['moran_4g', r.moran_4g], ['moran_5g', r.moran_5g],
    ['ma_ptm', r.ma_ptm],
    ['do_cao_dinh_cot_anten', r.do_cao_dinh_cot_anten],
    ['do_cao_cot_anten', r.do_cao_cot_anten],
    ['dia_chi', r.dia_chi], ['ghi_chu', r.ghi_chu],
  ]
}

// ── Cell snapshot field list ───────────────────────────────────────────────────
function cellSnap(r: CellRevisionBase): [string, unknown][] {
  const base: [string, unknown][] = [
    ['site_name', r.site_name], ['site_name_old', r.site_name_old],
    ['cell_name', r.cell_name], ['cell_name_old', r.cell_name_old],
    ['mien', r.mien], ['tinh', r.tinh], ['phuong_xa', r['phuong_xa']],
    ['cell_vip', r['cell_vip']], ['moran', r['moran']],
    ['lat', r['lat']], ['long', r['long']],
    ['vung_phu_song', r['vung_phu_song']], ['vendor', r.vendor],
    ['do_cao_anten', r['do_cao_anten']], ['azimuth', r.azimuth],
    ['m_tilt', r['m_tilt']], ['e_tilt', r['e_tilt']], ['total_tilt', r['total_tilt']],
    ['loai_anten', r['loai_anten']], ['baseband', r['baseband']],
    ['rf', r['rf']], ['cell_id', r['cell_id']], ['mimo', r.mimo],
  ]
  // tech-specific
  if (r['chung_anten'] !== undefined) base.push(['chung_anten', r['chung_anten']])
  if (r['arfcn']       !== undefined) base.push(['arfcn',       r['arfcn']])
  if (r['psc']         !== undefined) base.push(['psc',         r['psc']])
  if (r['earfcn']      !== undefined) base.push(['earfcn',      r['earfcn']])
  if (r['nr_arfcn']    !== undefined) base.push(['nr_arfcn',    r['nr_arfcn']])
  if (r['pci']         !== undefined) base.push(['pci',         r['pci']])
  if (r['root_sequence_id'] !== undefined) base.push(['root_sequence_id', r['root_sequence_id']])
  return base
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
// SITE REVISION TAB
// ═════════════════════════════════════════════════════════════════════════════
function SiteRevisionTab({ tinhList }: { tinhList: TinhItem[] }) {
  const [search,  setSearch]  = useState('')
  const [tinh,    setTinh]    = useState<string | undefined>()
  const [data,    setData]    = useState<SiteRevision[]>([])
  const [loading, setLoading] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const params: Record<string, unknown> = { limit: 500 }
      if (search.trim()) params.site_name = search.trim()
      const rows = await getSiteRevisions(params)
      setData(tinh ? rows.filter(r => r.tinh === tinh) : rows)
    } finally { setLoading(false) }
  }, [search, tinh])

  useEffect(() => { load() }, [load])

  const columns: ColumnsType<SiteRevision> = [
    {
      title: 'Rev#', dataIndex: 'revision_no', width: 60, fixed: 'left',
      render: (v: number) => <Badge count={v} color="#597ef7" />,
    },
    {
      title: 'Thời gian', dataIndex: 'created_at', width: 155, fixed: 'left',
      defaultSortOrder: 'descend',
      sorter: (a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime(),
      render: (v: string) => v ? new Date(v).toLocaleString('vi-VN') : '-',
    },
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
    { title: 'Cao đỉnh cột (m)', dataIndex: 'do_cao_dinh_cot_anten', width: 150 },
    { title: 'Cao cột (m)',      dataIndex: 'do_cao_cot_anten',       width: 120 },
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
    {
      title: 'Số trường TĐ', key: 'diff_count', width: 120,
      render: (_: unknown, r: SiteRevision) => {
        const n = Object.keys(r.changed_fields || {}).length
        return n ? <Tag color="orange">{n} trường</Tag> : <Tag color="default">Tạo mới</Tag>
      },
    },
    { title: 'Ghi chú TĐ', dataIndex: 'change_note', width: 160, ellipsis: { showTitle: true } },
  ]

  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="300px">
          <Input prefix={<SearchOutlined />}
            placeholder="Tìm site name (hiện tại hoặc tên cũ)..."
            value={search} onChange={e => setSearch(e.target.value)}
            onPressEnter={load} allowClear />
        </Col>
        <Col>
          <TinhFilter tinhList={tinhList} value={tinh} onChange={setTinh} />
        </Col>
        <Col>
          <Button type="primary" icon={<SearchOutlined />} onClick={load} loading={loading}>
            Tìm kiếm
          </Button>
        </Col>
        <Col>
          <Button icon={<ReloadOutlined />} onClick={() => { setSearch(''); setTinh(undefined) }}>
            Xóa lọc
          </Button>
        </Col>
      </Row>
      <Typography.Text type="secondary" style={{ display: 'block', marginBottom: 8, fontSize: 12 }}>
        {data.length} phiên bản – nhấn ▶ để xem chi tiết các trường thay đổi
      </Typography.Text>
      <Table
        columns={columns} dataSource={data} rowKey="id"
        loading={loading} size="small"
        scroll={{ x: scrollX, y: 500 }} bordered
        pagination={{ pageSize: 50, showTotal: t => `${t} phiên bản`, showSizeChanger: true }}
        expandable={{
          expandedRowRender: (r: SiteRevision) => {
            const diff   = r.changed_fields || {}
            const nDiff  = Object.keys(diff).length
            // Only show rename banner when site_name is in the diff
            const renamed = 'site_name' in diff
            return (
              <div style={{ padding: '12px 16px' }}>
                {renamed && (
                  <Alert type="warning" showIcon style={{ marginBottom: 12 }}
                    message={
                      <span>Đổi tên site:&nbsp;
                        <strong style={{ color: '#cf1322' }}>{diff['site_name']?.[0] as string}</strong>
                        &nbsp;→&nbsp;
                        <strong style={{ color: '#237804' }}>{diff['site_name']?.[1] as string}</strong>
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
          },
          rowExpandable: () => true,
        }}
      />
    </div>
  )
}

// ═════════════════════════════════════════════════════════════════════════════
// GENERIC CELL REVISION TAB  (tech-specific columns)
// ═════════════════════════════════════════════════════════════════════════════

// ── Shared column builders ────────────────────────────────────────────────────
function makeCommonCellColumns(): ColumnsType<CellRevisionBase> {
  return [
    {
      title: 'Rev#', dataIndex: 'revision_no', width: 60, fixed: 'left',
      render: (v: number) => <Badge count={v} color="#597ef7" />,
    },
    {
      title: 'Thời gian', dataIndex: 'created_at', width: 155, fixed: 'left',
      defaultSortOrder: 'descend' as const,
      sorter: (a: CellRevisionBase, b: CellRevisionBase) =>
        new Date(a.created_at).getTime() - new Date(b.created_at).getTime(),
      render: (v: string) => v ? new Date(v).toLocaleString('vi-VN') : '-',
    },
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
    { title: 'Site Name Old', dataIndex: 'site_name_old', width: 200, ellipsis: { showTitle: true },
      render: (v: string) => v || <span style={{ color: '#ccc' }}>-</span> },
    { title: 'Cell Name Old', dataIndex: 'cell_name_old', width: 200, ellipsis: { showTitle: true },
      render: (v: string) => v || <span style={{ color: '#ccc' }}>-</span> },
    { title: 'Miền', dataIndex: 'mien', width: 70 },
    { title: 'Tỉnh', dataIndex: 'tinh', width: 160 },
    { title: 'Phường xã', key: 'phuong_xa', width: 160,
      render: (_: unknown, r: CellRevisionBase) => String(r['phuong_xa'] ?? '-') },
    { title: 'Cell VIP', key: 'cell_vip', width: 90,
      render: (_: unknown, r: CellRevisionBase) => {
        const v = r['cell_vip']
        return v ? <Tag color="gold">{String(v)}</Tag> : <span>-</span>
      }},
    { title: 'MORAN', key: 'moran', width: 120,
      render: (_: unknown, r: CellRevisionBase) => String(r['moran'] ?? '-') },
    { title: 'Lat',  dataIndex: 'lat',  width: 110 },
    { title: 'Long', dataIndex: 'long', width: 110 },
    { title: 'Vùng phủ sóng', key: 'vung_phu_song', width: 130,
      render: (_: unknown, r: CellRevisionBase) => String(r['vung_phu_song'] ?? '-') },
    { title: 'Vendor', dataIndex: 'vendor', width: 100 },
    { title: 'Cao anten (m)', key: 'do_cao_anten', width: 115,
      render: (_: unknown, r: CellRevisionBase) => String(r['do_cao_anten'] ?? '-') },
    { title: 'Azimuth', dataIndex: 'azimuth', width: 90 },
    { title: 'M-tilt', key: 'm_tilt', width: 80,
      render: (_: unknown, r: CellRevisionBase) => String(r['m_tilt'] ?? '-') },
    { title: 'E-Tilt', key: 'e_tilt', width: 80,
      render: (_: unknown, r: CellRevisionBase) => String(r['e_tilt'] ?? '-') },
    { title: 'Total Tilt', key: 'total_tilt', width: 95,
      render: (_: unknown, r: CellRevisionBase) => String(r['total_tilt'] ?? '-') },
    { title: 'Loại Anten', key: 'loai_anten', width: 220, ellipsis: { showTitle: true },
      render: (_: unknown, r: CellRevisionBase) => String(r['loai_anten'] ?? '-') },
    { title: 'Baseband', key: 'baseband', width: 110,
      render: (_: unknown, r: CellRevisionBase) => String(r['baseband'] ?? '-') },
    { title: 'RF', key: 'rf', width: 90,
      render: (_: unknown, r: CellRevisionBase) => String(r['rf'] ?? '-') },
    { title: 'Cell ID', key: 'cell_id', width: 90,
      render: (_: unknown, r: CellRevisionBase) => String(r['cell_id'] ?? '-') },
    { title: 'MIMO', key: 'mimo', width: 80,
      render: (_: unknown, r: CellRevisionBase) =>
        r['mimo'] ? <Tag color="blue">{String(r['mimo'])}</Tag> : <span>-</span> },
    { title: 'Cell max power (dBm)', key: 'cell_max_power', width: 175,
      render: (_: unknown, r: CellRevisionBase) => String(r['cell_max_power'] ?? '-') },
    { title: 'BBUname', key: 'bbu_name', width: 130,
      render: (_: unknown, r: CellRevisionBase) => String(r['bbu_name'] ?? '-') },
    { title: 'Cell status', key: 'cell_status', width: 140,
      render: (_: unknown, r: CellRevisionBase) => String(r['cell_status'] ?? '-') },
    { title: 'Nguồn', dataIndex: 'change_source', width: 90,
      render: (v: string) => SOURCE_TAG[v] || <Tag>{v}</Tag> },
    { title: 'Người thay đổi', dataIndex: 'changed_by_name', width: 160,
      render: (v: string) => v || <span style={{ color: '#ccc' }}>–</span> },
    {
      title: 'Số trường TĐ', key: 'diff_count', width: 120,
      render: (_: unknown, r: CellRevisionBase) => {
        const n = Object.keys(r.changed_fields || {}).length
        return n ? <Tag color="orange">{n} trường</Tag> : <Tag color="default">Tạo mới</Tag>
      },
    },
  ]
}

function makeCell3GColumns(): ColumnsType<CellRevisionBase> {
  const common = makeCommonCellColumns()
  // Insert 3G-specific columns before the trailing meta columns (Nguồn, Người thay đổi, Số trường TĐ)
  // We splice them in after 'cell_id' column by rebuilding the array
  const metaCount = 3 // Nguồn, Người thay đổi, Số trường TĐ
  const before = common.slice(0, common.length - metaCount)
  const meta   = common.slice(common.length - metaCount)
  const specific: ColumnsType<CellRevisionBase> = [
    { title: 'Chung anten', key: 'chung_anten', width: 120,
      render: (_: unknown, r: CellRevisionBase) => String(r['chung_anten'] ?? '-') },
    { title: 'ARFCN', key: 'arfcn', width: 90,
      render: (_: unknown, r: CellRevisionBase) => String(r['arfcn'] ?? '-') },
    { title: 'UARFCN', key: 'uarfcn', width: 95,
      render: (_: unknown, r: CellRevisionBase) => String(r['uarfcn'] ?? '-') },
    { title: 'LAC', key: 'lac', width: 80,
      render: (_: unknown, r: CellRevisionBase) => String(r['lac'] ?? '-') },
    { title: 'RAC', key: 'rac', width: 80,
      render: (_: unknown, r: CellRevisionBase) => String(r['rac'] ?? '-') },
    { title: 'PSC', key: 'psc', width: 80,
      render: (_: unknown, r: CellRevisionBase) => String(r['psc'] ?? '-') },
    { title: 'URAId', key: 'ura_id', width: 80,
      render: (_: unknown, r: CellRevisionBase) => String(r['ura_id'] ?? '-') },
    { title: 'CPICH power (dBm)', key: 'cpich_power', width: 155,
      render: (_: unknown, r: CellRevisionBase) => String(r['cpich_power'] ?? '-') },
  ]
  return [...before, ...specific, ...meta]
}

function makeCell4GColumns(): ColumnsType<CellRevisionBase> {
  const common = makeCommonCellColumns()
  const metaCount = 3
  const before = common.slice(0, common.length - metaCount)
  const meta   = common.slice(common.length - metaCount)
  const specific: ColumnsType<CellRevisionBase> = [
    { title: 'Chung anten', key: 'chung_anten', width: 120,
      render: (_: unknown, r: CellRevisionBase) => String(r['chung_anten'] ?? '-') },
    { title: 'EnodeB ID', key: 'enodeb_id', width: 110,
      render: (_: unknown, r: CellRevisionBase) => String(r['enodeb_id'] ?? '-') },
    { title: 'EARFCN', key: 'earfcn', width: 90,
      render: (_: unknown, r: CellRevisionBase) => String(r['earfcn'] ?? '-') },
    { title: 'TAC', key: 'tac', width: 80,
      render: (_: unknown, r: CellRevisionBase) => String(r['tac'] ?? '-') },
    { title: 'PCI', key: 'pci', width: 80,
      render: (_: unknown, r: CellRevisionBase) => String(r['pci'] ?? '-') },
    { title: 'Root Sequence ID', key: 'root_sequence_id', width: 155,
      render: (_: unknown, r: CellRevisionBase) => String(r['root_sequence_id'] ?? '-') },
    { title: 'Bandwidth (MHz)', key: 'bandwidth', width: 130,
      render: (_: unknown, r: CellRevisionBase) => String(r['bandwidth'] ?? '-') },
    { title: 'ECI', key: 'eci', width: 110,
      render: (_: unknown, r: CellRevisionBase) => String(r['eci'] ?? '-') },
  ]
  return [...before, ...specific, ...meta]
}

function makeCell5GColumns(): ColumnsType<CellRevisionBase> {
  const common = makeCommonCellColumns()
  const metaCount = 3
  const before = common.slice(0, common.length - metaCount)
  const meta   = common.slice(common.length - metaCount)
  const specific: ColumnsType<CellRevisionBase> = [
    { title: 'gNodeB ID', key: 'gnodeb_id', width: 110,
      render: (_: unknown, r: CellRevisionBase) => String(r['gnodeb_id'] ?? '-') },
    { title: 'TAC', key: 'tac', width: 80,
      render: (_: unknown, r: CellRevisionBase) => String(r['tac'] ?? '-') },
    { title: 'PCI', key: 'pci', width: 80,
      render: (_: unknown, r: CellRevisionBase) => String(r['pci'] ?? '-') },
    { title: 'Root Sequence ID', key: 'root_sequence_id', width: 155,
      render: (_: unknown, r: CellRevisionBase) => String(r['root_sequence_id'] ?? '-') },
    { title: 'SSB-ARFCN', key: 'ssb_arfcn', width: 110,
      render: (_: unknown, r: CellRevisionBase) => String(r['ssb_arfcn'] ?? '-') },
    { title: 'Center-ARFCN', key: 'center_arfcn', width: 125,
      render: (_: unknown, r: CellRevisionBase) => String(r['center_arfcn'] ?? '-') },
    { title: 'GSCN', key: 'gscn', width: 85,
      render: (_: unknown, r: CellRevisionBase) => String(r['gscn'] ?? '-') },
    { title: 'Bandwidth (MHz)', key: 'bandwidth', width: 130,
      render: (_: unknown, r: CellRevisionBase) => String(r['bandwidth'] ?? '-') },
    { title: 'NCI', key: 'nci', width: 110,
      render: (_: unknown, r: CellRevisionBase) => String(r['nci'] ?? '-') },
    { title: 'MU-MIMO', key: 'mu_mimo', width: 95,
      render: (_: unknown, r: CellRevisionBase) => String(r['mu_mimo'] ?? '-') },
  ]
  return [...before, ...specific, ...meta]
}

function CellRevisionTab({
  tech, fetchFn, tinhList,
}: {
  tech: string
  fetchFn: (p: Record<string, unknown>) => Promise<CellRevisionBase[]>
  tinhList: TinhItem[]
}) {
  const [siteName, setSiteName] = useState('')
  const [cellName, setCellName] = useState('')
  const [tinh,     setTinh]     = useState<string | undefined>()
  const [data,     setData]     = useState<CellRevisionBase[]>([])
  const [loading,  setLoading]  = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const params: Record<string, unknown> = { limit: 500 }
      if (siteName.trim()) params.site_name = siteName.trim()
      if (cellName.trim()) params.cell_name = cellName.trim()
      const rows = await fetchFn(params)
      setData(tinh ? rows.filter(r => r.tinh === tinh) : rows)
    } finally { setLoading(false) }
  }, [siteName, cellName, tinh, fetchFn])

  useEffect(() => { load() }, [load])

  // Select column set based on tech
  const columns: ColumnsType<CellRevisionBase> = React.useMemo(() => {
    const t = tech.toLowerCase()
    if (t === '3g') return makeCell3GColumns()
    if (t === '4g') return makeCell4GColumns()
    if (t === '5g') return makeCell5GColumns()
    return makeCommonCellColumns()
  }, [tech])

  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="250px">
          <Input prefix={<SearchOutlined />}
            placeholder="Site name (hiện tại hoặc cũ)..."
            value={siteName} onChange={e => setSiteName(e.target.value)}
            onPressEnter={load} allowClear />
        </Col>
        <Col flex="250px">
          <Input prefix={<SearchOutlined />}
            placeholder="Cell name (hiện tại hoặc cũ)..."
            value={cellName} onChange={e => setCellName(e.target.value)}
            onPressEnter={load} allowClear />
        </Col>
        <Col>
          <TinhFilter tinhList={tinhList} value={tinh} onChange={setTinh} />
        </Col>
        <Col>
          <Button type="primary" icon={<SearchOutlined />} onClick={load} loading={loading}>
            Tìm kiếm
          </Button>
        </Col>
        <Col>
          <Button icon={<ReloadOutlined />}
            onClick={() => { setSiteName(''); setCellName(''); setTinh(undefined) }}>
            Xóa lọc
          </Button>
        </Col>
      </Row>
      <Typography.Text type="secondary" style={{ display: 'block', marginBottom: 8, fontSize: 12 }}>
        {data.length} phiên bản Cell {tech} – nhấn ▶ để xem chi tiết các trường thay đổi
      </Typography.Text>
      <Table
        columns={columns} dataSource={data} rowKey="id"
        loading={loading} size="small"
        scroll={{ x: scrollX, y: 500 }} bordered
        pagination={{ pageSize: 50, showTotal: t => `${t} phiên bản`, showSizeChanger: true }}
        expandable={{
          expandedRowRender: (r: CellRevisionBase) => {
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
          },
          rowExpandable: () => true,
        }}
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
          </ul>
        }
      />
      <Tabs defaultActiveKey="sites" items={[
        { key: 'sites',   label: '🏗️ Site',    children: <SiteRevisionTab tinhList={tinhList} /> },
        { key: 'cells3g', label: '📡 Cell 3G', children: <CellRevisionTab tech="3G" fetchFn={getCell3GRevisions} tinhList={tinhList} /> },
        { key: 'cells4g', label: '📡 Cell 4G', children: <CellRevisionTab tech="4G" fetchFn={getCell4GRevisions} tinhList={tinhList} /> },
        { key: 'cells5g', label: '📡 Cell 5G', children: <CellRevisionTab tech="5G" fetchFn={getCell5GRevisions} tinhList={tinhList} /> },
      ]} />
    </div>
  )
}
